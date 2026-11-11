import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/authoring/onboarding_event.dart'
    show RecordedEventHost;
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart' as rfw
    show encodeLibraryBlob, parseLibraryFile;
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/compiled_surfaces/native_flow.dart';
import '../support/placement_delivery_fixture.dart';
import 'surface_screen_test_support.dart';

const _close = SurfaceEvent<void>('close');
const _undeclared = SurfaceEvent<void>('undeclared');

final _schema = SurfaceScreenEventSchema(events: [
  SurfaceScreenEvent(
      id: 'close', arguments: const SurfaceScreenEventNoArguments()),
]);

GeneratedPlacementDefinition _definition(ScreenFixture<String> fixture) =>
    GeneratedPlacementDefinition(
      defaultSurface: fixture.ref,
      defaultSurfaceLocator: DeliverySurfaceLocatorV1(
        surfaceType: DeliverySurfaceTypeId('general'),
        slug: fixture.ref.slug,
        family: DeliveryFamilySelectorV1.screenContract(
            contractVersion: fixture.ref.contractVersion),
      ),
      key: PlacementKeyV1.generatedDefault(
          surfaceType: DeliverySurfaceTypeId('general'),
          slug: fixture.ref.slug),
      hostContract: readPlacementDeliveryFixture()
          .request
          .buildContract
          .contractsByHash
          .values
          .first,
      vocabulary: SurfaceVocabulary.none,
    );

// A button firing [_close] from [context], as a copied build passes it on.
Widget _closeFrom(BuildContext context, String label) => TextButton(
      onPressed: context.surfaceEvent(_close),
      child: Text(label),
    );

Matcher _refusal(String reason) => isA<AssertionError>().having(
      (error) => '${error.message}',
      'message',
      contains(reason),
    );

final class _ReadyResolver implements VariantResolver {
  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async =>
      ResolvedVariant(
        bytes: Uint8List.fromList(rfw.encodeLibraryBlob(rfw.parseLibraryFile(
            'import restage.core; widget Paywall = Text(text: "Ready");'))),
        surfaceVersion: 'test',
        paywallId: id,
      );
}

void main() {
  setUp(() {
    resetSurfaceScreenTestState();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group("a copied build's own context fires on the surface it shows", () {
    // The generated mount's copy runs above the screen it shows; [built]
    // receives the mount's own context.
    Future<List<String>> pumpCopy(
      WidgetTester tester, {
      required bool nested,
      required Widget Function(BuildContext mount) built,
      List<String>? outer,
    }) async {
      final inner = <String>[];
      final fixture = stringScreenFixture(
          slug: 'picker', schema: _schema, packagesBundle: false);
      final definition = _definition(fixture);
      Widget mount() => Builder(builder: (context) {
            final original = built(context);
            return RestageScreen<String>(
              screen: fixture.ref,
              placementBinding: RestageScreen.generatedPlacementBinding(
                  definition: () => definition, eventOwner: context),
              onEvent: inner.add,
              fallbackBuilder: (_) => original,
            );
          });
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: nested
              ? RestageEventDispatcher(
                  onEvent: (name, _) => outer!.add(name), child: mount())
              : mount(),
        ),
      ));
      await tester.pumpAndSettle();
      tester.takeException();
      return inner;
    }

    for (final nested in [true, false]) {
      testWidgets('through an alias, nested=$nested', (tester) async {
        final outer = <String>[];
        final inner = await pumpCopy(tester, nested: nested, outer: outer,
            built: (context) {
          final ctx = context;
          return _closeFrom(ctx, 'alias');
        });
        await tester.tap(find.text('alias'));
        expect(inner, ['close']);
        expect(outer, isEmpty);
      });

      testWidgets('through a helper method, nested=$nested', (tester) async {
        final outer = <String>[];
        final inner = await pumpCopy(tester,
            nested: nested,
            outer: outer,
            built: (context) => _closeFrom(context, 'helper'));
        await tester.tap(find.text('helper'));
        expect(inner, ['close']);
        expect(outer, isEmpty);
      });

      testWidgets('from a dialog it opens, nested=$nested', (tester) async {
        final outer = <String>[];
        final inner = await pumpCopy(tester,
            nested: nested,
            outer: outer,
            built: (context) => TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => _closeFrom(context, 'in dialog'),
                  ),
                  child: const Text('open'),
                ));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('in dialog'));
        expect(inner, ['close']);
        expect(outer, isEmpty);
      });
    }
  });

  testWidgets("a delivered paywall's mount opens a dialog that fires on it",
      (tester) async {
    Restage.debugReset();
    final outer = <String>[];
    final paywall = <String>[];
    late BuildContext mount;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestageEventDispatcher(
          onEvent: (name, _) => outer.add(name),
          child: Builder(builder: (context) {
            mount = context;
            return RestagePaywall(
              id: 'native_offer',
              placementBinding: RestagePaywall.generatedPlacementBinding(
                definition: nativeOfferPlacementDefinition,
                eventOwner: context,
              ),
              resolver: _ReadyResolver(),
              onEvent: (event) {
                if (event is PaywallCustomEvent) paywall.add(event.eventName);
              },
            );
          }),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Ready'), findsOneWidget);
    // A delivered callback opens terms with the mount's context.
    showDialog<void>(
      context: mount,
      builder: (_) => _closeFrom(mount, 'accept'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('accept'));
    expect(paywall, ['close']);
    expect(outer, isEmpty);
  });

  testWidgets('a sheet whose paywall is gone refuses, never reaching outside',
      (tester) async {
    final outer = <String>[];
    final paywall = <String>[];
    final show = ValueNotifier(true);
    late BuildContext opener;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestageEventDispatcher(
          onEvent: (name, _) => outer.add(name),
          child: ValueListenableBuilder<bool>(
            valueListenable: show,
            builder: (_, fallback, __) => RestagePaywallEventDispatcher(
              // The delivered stage replaces the fallback.
              key: ValueKey(fallback),
              onEvent: (name, _) => paywall.add(name),
              child: Builder(builder: (context) {
                if (fallback) opener = context;
                return Text(fallback ? 'fallback' : 'delivered');
              }),
            ),
          ),
        ),
      ),
    ));
    showModalBottomSheet<void>(
      context: opener,
      builder: (context) => _closeFrom(context, 'sheet close'),
    );
    await tester.pumpAndSettle();
    show.value = false;
    await tester.pump();

    expect(
      () => tester.widget<TextButton>(find.byType(TextButton)).onPressed!(),
      throwsA(_refusal('callback dispatch is not admitted')),
    );
    expect(outer, isEmpty);
    expect(paywall, isEmpty);
  });

  testWidgets('a route stays put when its mount goes', (tester) async {
    final received = <String>[];
    final show = ValueNotifier(true);
    final tick = ValueNotifier(0);
    late RestageRecording recording;
    late BuildContext mount;
    await tester.pumpWidget(MaterialApp(
      home: ValueListenableBuilder<bool>(
        valueListenable: show,
        builder: (_, visible, __) => visible
            ? Builder(builder: (context) {
                mount = context;
                recording = RestageRecording(owner: context);
                return RestageEventDispatcher(
                  onEvent: (name, _) => received.add(name),
                  child: RecordedEventHost(
                    owner: context,
                    child: const SizedBox(),
                  ),
                );
              })
            : const SizedBox(),
      ),
    ));
    Navigator.of(mount).push(MaterialPageRoute<void>(
      builder: (_) => ValueListenableBuilder<int>(
        valueListenable: tick,
        builder: (_, __, ___) => recording.route(Builder(
          builder: (context) => _closeFrom(context, 'route close'),
        )),
      ),
    ));
    await tester.pumpAndSettle();
    show.value = false;
    tick.value++;
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      () => tester.widget<TextButton>(find.byType(TextButton)).onPressed!(),
      throwsA(isA<AssertionError>()),
    );
    expect(received, isEmpty);
  });

  testWidgets('a dialog of a screen whose element another screen took refuses',
      (tester) async {
    final a = <String>[];
    final b = <String>[];
    final first = stringScreenFixture(
        slug: 'first', schema: _schema, packagesBundle: false);
    final second = stringScreenFixture(
        slug: 'second', schema: _schema, packagesBundle: false);
    Widget screen(ScreenFixture<String> fixture, List<String> into,
            Widget original) =>
        RestageScreen<String>(
          screen: fixture.ref,
          onEvent: into.add,
          fallbackBuilder: (_) => original,
        );
    // Unkeyed: removing the first screen gives the second its element.
    Widget tree({required bool withFirst}) => MaterialApp(
          home: Scaffold(
            body: Column(children: [
              if (withFirst)
                screen(
                  first,
                  a,
                  Builder(
                    builder: (context) => TextButton(
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (context) => _closeFrom(context, 'A close'),
                      ),
                      child: const Text('open'),
                    ),
                  ),
                ),
              screen(second, b, const Text('B')),
            ]),
          ),
        );
    await tester.pumpWidget(tree(withFirst: true));
    await tester.pumpAndSettle();
    tester.takeException();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(tree(withFirst: false));
    await tester.pumpAndSettle();
    tester.takeException();

    expect(
      () => tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'A close'))
          .onPressed!(),
      throwsA(_refusal('callback dispatch is not admitted')),
    );
    expect(a, isEmpty);
    expect(b, isEmpty);
  });

  testWidgets("a dialog keeps reaching its screen's latest handler",
      (tester) async {
    final events = <String>[];
    final fixture = stringScreenFixture(
        slug: 'picker', schema: _schema, packagesBundle: false);
    final rebuild = ValueNotifier(0);
    late BuildContext opener;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ValueListenableBuilder<int>(
          valueListenable: rebuild,
          builder: (_, generation, __) => RestageScreen<String>(
            screen: fixture.ref,
            // A new closure on every rebuild, as Flutter code writes it.
            onEvent: (event) => events.add('$generation:$event'),
            fallbackBuilder: (_) => Builder(builder: (context) {
              opener = context;
              return const Text('screen');
            }),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    tester.takeException();
    showDialog<void>(
      context: opener,
      builder: (context) => _closeFrom(context, 'close'),
    );
    await tester.pumpAndSettle();
    rebuild.value++;
    await tester.pumpAndSettle();

    await tester.tap(find.text('close'));
    expect(events, ['1:close']);
  });

  testWidgets('a staged second host never takes the shown one\'s events',
      (tester) async {
    final outer = <String>[];
    final live = <String>[];
    final candidate = <String>[];
    final staged = ValueNotifier(false);
    late BuildContext mount;
    late RestageRecording recording;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestageEventDispatcher(
          onEvent: (name, _) => outer.add(name),
          child: Builder(builder: (context) {
            mount = context;
            recording = RestageRecording(owner: context);
            return ValueListenableBuilder<bool>(
              valueListenable: staged,
              builder: (_, withCandidate, __) => Column(children: [
                RestagePaywallEventDispatcher(
                  onEvent: (name, _) => live.add(name),
                  mount: context,
                  child: RecordedEventHost(
                    owner: context,
                    child: const Text('live'),
                  ),
                ),
                if (withCandidate)
                  RestagePaywallEventDispatcher(
                    onEvent: (name, _) => candidate.add(name),
                    mount: context,
                    child: RecordedEventHost(
                      owner: context,
                      child: const Text('candidate'),
                    ),
                  ),
              ]),
            );
          }),
        ),
      ),
    ));
    void fire(String id) => mount.surfaceEvent(SurfaceEvent<void>(id))();

    fire('only_live');
    staged.value = true;
    await tester.pump();
    fire('with_candidate');
    staged.value = false;
    await tester.pump();
    fire('candidate_dropped');
    BuildContext? dialog;
    showDialog<void>(
      context: mount,
      builder: (_) => recording.route(Builder(builder: (context) {
        dialog = context;
        return const Text('terms');
      })),
    );
    await tester.pumpAndSettle();
    dialog!.surfaceEvent(const SurfaceEvent<void>('dialog_after_drop'))();

    expect(live, [
      'only_live',
      'with_candidate',
      'candidate_dropped',
      'dialog_after_drop',
    ]);
    expect(candidate, isEmpty);
    expect(outer, isEmpty);
  });

  testWidgets('an offstage host for the same owner leaves the shown one',
      (tester) async {
    final shown = <String>[];
    final staged = <String>[];
    final owner = Object();
    final recording = RestageRecording(owner: owner);
    Widget tree({required bool withStaged}) => Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(children: [
            RestageEventDispatcher(
              onEvent: (name, _) => shown.add(name),
              child: RecordedEventHost(owner: owner, child: const Text('A')),
            ),
            if (withStaged)
              Offstage(
                child: RestageEventDispatcher(
                  onEvent: (name, _) => staged.add(name),
                  child:
                      RecordedEventHost(owner: owner, child: const Text('B')),
                ),
              ),
          ]),
        );
    await tester.pumpWidget(tree(withStaged: false));
    recording.surfaceEvent(_close)();
    await tester.pumpWidget(tree(withStaged: true));
    recording.surfaceEvent(_close)();
    await tester.pumpWidget(tree(withStaged: false));
    recording.surfaceEvent(_close)();

    expect(shown, ['close', 'close', 'close']);
    expect(staged, isEmpty);
  });

  testWidgets('a route a mount pushes with no surface hosting it refuses',
      (tester) async {
    final outer = <String>[];
    late BuildContext mount;
    await tester.pumpWidget(MaterialApp(
      builder: (_, child) => RestageEventDispatcher(
        onEvent: (name, _) => outer.add(name),
        child: child!,
      ),
      home: Builder(builder: (context) {
        mount = context;
        return const Text('home');
      }),
    ));
    final recording = RestageRecording(owner: Object());
    Navigator.of(mount).push(MaterialPageRoute<void>(
      builder: (_) => recording.route(
        Builder(builder: (context) => _closeFrom(context, 'route close')),
      ),
    ));
    await tester.pumpAndSettle();

    expect(
      () => tester.widget<TextButton>(find.byType(TextButton)).onPressed!(),
      throwsA(_refusal('callback dispatch is not admitted')),
    );
    expect(outer, isEmpty);
  });

  group('an app event its contract rejects', () {
    Widget keep(BuildContext context, DataSource source) =>
        RestageIslandScope.build('Keep', 'missing', context, source);
    final islands = RestageWidgetLibraryRegistration(
      library: const WidgetLibrary.custom('app.islands'),
      widgets: [RestageWidgetFactory(name: 'Keep', builder: keep)],
      islands: true,
    );

    testWidgets('is reported and leaves the delivered screen up',
        (tester) async {
      SurfaceVocabulary(libraries: [islands]).addToInstalled();
      final unavailable = <Object>[];
      final fixture = stringScreenFixture(
        slug: 'inner',
        blob: rfwSourceBlob('''
import restage.core;
import app.islands;
widget OnboardingScreen = Column(children: [
  Text(text: "delivered"),
  Keep(),
]);
'''),
        schema: _schema,
        vocabulary: SurfaceVocabulary(libraries: [islands]),
      );
      final definition = _definition(fixture);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (mount) {
            final recording = RestageRecording(owner: mount);
            final placed = recording.island(
              'Keep',
              Builder(
                builder: (context) => TextButton(
                  onPressed: context.surfaceEvent(_undeclared),
                  child: const Text('undeclared'),
                ),
              ),
            );
            return RestageIslandScope(
              owner: mount,
              builders: {
                'Keep': (c, s) => recording.islandAt('Keep', const [], c, s),
              },
              child: RestageScreen<String>(
                screen: fixture.ref,
                placementBinding: RestageScreen.generatedPlacementBinding(
                    definition: () => definition, eventOwner: mount),
                resolver: AssetSurfaceScreenResolver(
                    bundleProvider: AssetSurfaceScreenBundleProvider(
                        assetBundle: fixture.assetBundle())),
                onUnavailable: unavailable.add,
                fallbackBuilder: (_) => placed,
              ),
            );
          }),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('delivered'), findsOneWidget);

      await tester.tap(find.text('undeclared'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isA<FormatException>());
      expect(find.text('delivered'), findsOneWidget);
      expect(unavailable, isEmpty);
    });
  });
}
