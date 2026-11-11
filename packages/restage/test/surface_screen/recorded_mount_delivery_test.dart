import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_shared/restage_shared.dart';

import '../support/placement_delivery_fixture.dart';
import 'surface_screen_test_support.dart';

// A generated mount records its app code above the screen it creates. The
// events that code fires reach that screen whether it shows its fallback or
// a delivered design, and no outer surface.
const _close = SurfaceEvent<void>('close');

Widget _keep(BuildContext context, DataSource source) =>
    RestageIslandScope.build('Keep', 'missing', context, source);

const _islands = RestageWidgetLibraryRegistration.constant(
  library: WidgetLibrary.custom('app.islands'),
  widgets: [RestageWidgetFactory(name: 'Keep', builder: _keep)],
  islands: true,
);

final _blob = rfwSourceBlob('''
import restage.core;
import app.islands;
widget OnboardingScreen = Column(children: [
  Text(text: "delivered"),
  Keep(),
]);
''');

final _schema = SurfaceScreenEventSchema(events: [
  SurfaceScreenEvent(
      id: 'close', arguments: const SurfaceScreenEventNoArguments()),
]);

final class _IslandButton extends StatelessWidget {
  const _IslandButton(this.onTap);

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) =>
      TextButton(onPressed: onTap, child: const Text('island close'));
}

ScreenFixture<String> _fixture() => stringScreenFixture(
      slug: 'inner',
      blob: _blob,
      schema: _schema,
      vocabulary: const SurfaceVocabulary(libraries: [_islands]),
    );

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

SurfaceScreenResolver _delivered(ScreenFixture<String> fixture) =>
    AssetSurfaceScreenResolver(
      bundleProvider:
          AssetSurfaceScreenBundleProvider(assetBundle: fixture.assetBundle()),
    );

// The generated shape: the mount records its island, then creates the screen.
Widget _mount(
  ScreenFixture<String> fixture,
  List<String> into,
  SurfaceScreenResolver resolver,
) {
  final definition = _definition(fixture);
  return Builder(builder: (mount) {
    final recording = RestageRecording(owner: mount);
    final island =
        recording.island('Keep', _IslandButton(recording.surfaceEvent(_close)));
    return RestageIslandScope(
      owner: mount,
      builders: {
        'Keep': (context, source) =>
            recording.islandAt('Keep', const [], context, source),
      },
      child: RestageScreen<String>(
        screen: fixture.ref,
        placementBinding: RestageScreen.generatedPlacementBinding(
            definition: () => definition, eventOwner: mount),
        resolver: resolver,
        onEvent: into.add,
        fallbackBuilder: (_) => island,
      ),
    );
  });
}

Future<void> _tapIsland(WidgetTester tester) async {
  await tester.tap(find.text('island close'));
  await tester.pump();
}

void main() {
  setUp(() {
    resetSurfaceScreenTestState();
    const SurfaceVocabulary(libraries: [_islands]).addToInstalled();
  });

  testWidgets('a delivered screen nested in a surface keeps its events',
      (tester) async {
    final outer = <String>[];
    final inner = <String>[];
    final fixture = _fixture();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestageEventDispatcher(
          onEvent: (name, _) => outer.add(name),
          child: _mount(fixture, inner, _delivered(fixture)),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('delivered'), findsOneWidget);

    await _tapIsland(tester);

    expect(tester.takeException(), isNull);
    expect(inner, ['close']);
    expect(outer, isEmpty);
  });

  testWidgets('a delivered screen inside a paywall keeps its events',
      (tester) async {
    final paywall = <String>[];
    final inner = <String>[];
    final fixture = _fixture();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywallEventDispatcher(
          onEvent: (name, _) => paywall.add(name),
          child: _mount(fixture, inner, _delivered(fixture)),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('delivered'), findsOneWidget);

    await _tapIsland(tester);

    expect(tester.takeException(), isNull);
    expect(inner, ['close']);
    expect(paywall, isEmpty);
  });

  testWidgets('a standalone delivered screen receives its events',
      (tester) async {
    final inner = <String>[];
    final fixture = _fixture();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: _mount(fixture, inner, _delivered(fixture))),
    ));
    await tester.pumpAndSettle();
    expect(find.text('delivered'), findsOneWidget);

    await _tapIsland(tester);

    expect(tester.takeException(), isNull);
    expect(inner, ['close']);
  });

  testWidgets('a screen delivered after its fallback keeps its events',
      (tester) async {
    final inner = <String>[];
    final fixture = _fixture();
    Widget app(SurfaceScreenResolver resolver) => MaterialApp(
          home: Scaffold(body: _mount(fixture, inner, resolver)),
        );
    await tester.pumpWidget(
      app(FailingScreenResolver(StateError('not yet'))),
    );
    await tester.pumpAndSettle();
    tester.takeException();
    expect(find.text('delivered'), findsNothing);
    await _tapIsland(tester);
    expect(inner, ['close']);

    await tester.pumpWidget(app(_delivered(fixture)));
    await tester.pumpAndSettle();
    expect(find.text('delivered'), findsOneWidget);
    await _tapIsland(tester);

    expect(tester.takeException(), isNull);
    expect(inner, ['close', 'close']);
  });

  testWidgets('a recorded event with no surface hosting it refuses',
      (tester) async {
    final received = <String>[];
    late VoidCallback onTap;
    await tester.pumpWidget(RestageEventDispatcher(
      onEvent: (name, _) => received.add(name),
      child: Builder(builder: (mount) {
        onTap = RestageRecording(owner: mount).surfaceEvent(_close);
        return const SizedBox();
      }),
    ));

    expect(
      onTap,
      throwsA(isA<AssertionError>().having(
        (error) => '${error.message}',
        'message',
        contains("no surface hosts the generated mount's events"),
      )),
    );
    expect(received, isEmpty);
  });

  testWidgets('a step mount that is no longer mounted refuses as unmounted',
      (tester) async {
    final received = <String>[];
    late VoidCallback onTap;
    await tester.pumpWidget(RestageEventDispatcher(
      onEvent: (name, _) => received.add(name),
      child: Builder(builder: (mount) {
        onTap = RestageRecording(mount: mount).surfaceEvent(_close);
        return const SizedBox();
      }),
    ));
    await tester.pumpWidget(const SizedBox());

    expect(
      onTap,
      throwsA(isA<AssertionError>().having(
        (error) => '${error.message}',
        'message',
        '[restage] A generated mount refused a recorded event: the widget '
            'that built the callback is no longer mounted. Try keeping the '
            "callback only while the mount's surface is shown.",
      )),
    );
    expect(received, isEmpty);
  });
}
