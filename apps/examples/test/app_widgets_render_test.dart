import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/surfaces/app_widgets.dart';
import 'package:restage_example/user_factories.g.dart';
import 'package:restage_example/widgets/factory_tally_chip.dart';
import 'package:restage_example/widgets/own_key_chip.dart';
import 'package:restage_example/widgets/tally_chip.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart' show encodeLibraryBlob, parseLibraryFile;
import 'package:rfw/rfw.dart' show RemoteWidget;

import '_support/support_directory_channel.dart';

final class _Switchable implements VariantResolver {
  _Switchable(this.bytes);

  // The design the next load delivers; none falls back.
  Uint8List? bytes;

  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) =>
      _Resolver(bytes).resolve(id, placementId: placementId, locale: locale);
}

final class _Resolver implements VariantResolver {
  const _Resolver(this.bytes);

  final Uint8List? bytes;

  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async {
    final design = bytes;
    if (design == null) {
      throw const RestagePaywallError(
          code: RestageErrorCodes.deliveryUnavailable, message: 'No design');
    }
    return ResolvedVariant(
      bytes: design,
      surfaceVersion: '1',
      paywallId: id,
      paywallPublishedVersion: 1,
    );
  }
}

// Shows the fallback until [bytes] holds a design, at [version].
final class _Flipping implements VariantResolver {
  Uint8List? bytes;
  int version = 1;

  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async {
    final design = bytes;
    if (design == null) {
      throw const RestagePaywallError(
          code: RestageErrorCodes.deliveryUnavailable, message: 'No design');
    }
    return ResolvedVariant(
      bytes: design,
      surfaceVersion: '$version',
      paywallId: id,
      paywallPublishedVersion: version,
    );
  }

  /// The same delivery, for a screen.
  late final SurfaceScreenResolver screen = _FlippingScreen(this);
}

final class _FlippingScreen implements SurfaceScreenResolver {
  _FlippingScreen(this.delivery);

  final _Flipping delivery;

  @override
  Future<ResolvedSurfaceScreen> resolve<E>(SurfaceScreenRef<E> screen) async {
    final design = delivery.bytes;
    if (design == null) {
      throw const SurfaceScreenUnavailableError(
          reason: SurfaceScreenUnavailableReason.missing, message: 'No design');
    }
    final capabilities = screen.capabilities;
    return ResolvedSurfaceScreen.hosted(
      surface: screen.surface,
      slug: screen.slug,
      contractVersion: screen.contractVersion,
      publishedRevision: delivery.version,
      sourceKind: screen.sourceKind,
      payloadKind: screen.payloadKind,
      capabilities: capabilities,
      contractFingerprint: screen.contractFingerprint,
      eventContractHash: screen.eventContract.hash,
      blob: design,
      contentHash: BlobSurfacePayload(
        minClient: capabilities.builtInFloor,
        blob: design,
        requiredLibraries: capabilities.requiredLibraries,
      ).contentHash,
      cacheHit: false,
    );
  }
}

const _bundle = 'assets/restage/bundles/lib/surfaces/app_widgets.rsbundle';

String _design(String id) => String.fromCharCodes(
      RestageBundleCodec.decode(File(_bundle).readAsBytesSync())
          .entries
          .singleWhere((entry) => entry.logicalPath.endsWith('/$id.rfwtxt'))
          .bytes,
    );

List<String?> _texts(WidgetTester tester) => [
      for (final element in find.byType(Text).evaluate())
        (element.widget as Text).data ??
            (element.widget as Text).textSpan?.toPlainText(),
    ];

// The first value in [node]'s subtree: the slider's thumb carries it.
String _value(SemanticsNode node) {
  var value = node.value;
  node.visitChildren((child) {
    if (value.isEmpty) value = _value(child);
    return value.isEmpty;
  });
  return value;
}

void main() {
  useSupportDirectoryChannel();

  setUp(() async {
    await Restage.debugResetAndWait();
    Restage.configure(apiKey: 'rs_pk_test', resolver: const _Resolver(null));
  });

  // The app's widget, the delivered design and the compiled fallback render
  // the same and make the same calls; the design inlines the app widgets that
  // lower and renders the rest from the app.
  for (final (id, original, surface, inlined, islands) in [
    (
      'app_widgets_inline',
      const AppWidgetsInline(title: 'Pro'),
      (VariantResolver r) => AppWidgetsInlineSurface(title: 'Pro', resolver: r),
      [
        'widget AppPill =',
        'widget AppCard =',
        'widget _Boxed =',
        'widget AppTap ='
      ],
      0,
    ),
    // An app class named like a catalog widget is a different class: it
    // inlines under its own name, and the catalog's Card still binds.
    (
      'app_widgets_named_card',
      const AppWidgetsNamedCard(title: 'Pro'),
      (VariantResolver r) =>
          AppWidgetsNamedCardSurface(title: 'Pro', resolver: r),
      ['widget Card_', 'Card(child: Text(text: "Framework"))'],
      0,
    ),
    (
      'app_widgets_island',
      const AppWidgetsIsland(),
      (VariantResolver r) => AppWidgetsIslandSurface(resolver: r),
      ['widget AppPill =', 'widget _Boxed ='],
      1,
    ),
    (
      'app_widgets_forwarded',
      const AppWidgetsForwarded(title: 'Pro'),
      (VariantResolver r) =>
          AppWidgetsForwardedSurface(title: 'Pro', resolver: r),
      [
        'widget AppToggle = Switch(value: false, onChanged: args.onChanged)',
        'widget AppKeyed = Text(text: args.label, key: args.tag)',
      ],
      0,
    ),
    (
      'app_widgets_direct_toggle',
      const AppWidgetsDirectToggle(title: 'Pro'),
      (VariantResolver r) =>
          AppWidgetsDirectToggleSurface(title: 'Pro', resolver: r),
      <String>[],
      0,
    ),
    (
      'app_widgets_direct_tap',
      const AppWidgetsDirectTap(title: 'Pro'),
      (VariantResolver r) =>
          AppWidgetsDirectTapSurface(title: 'Pro', resolver: r),
      <String>[],
      0,
    ),
    // The copy runs the build as written: its local function and its helper's
    // spread list make each call once, as the app does.
    (
      'app_widgets_local_fn',
      const AppWidgetsLocalFn(),
      (VariantResolver r) => AppWidgetsLocalFnSurface(resolver: r),
      <String>[],
      2,
    ),
    (
      'app_widgets_spread',
      const AppWidgetsSpread(),
      (VariantResolver r) => AppWidgetsSpreadSurface(resolver: r),
      <String>[],
      0,
    ),
    (
      'app_widgets_spread_input',
      const AppWidgetsSpreadInput(names: ['a', 'b']),
      (VariantResolver r) =>
          AppWidgetsSpreadInputSurface(names: const ['a', 'b'], resolver: r),
      <String>[],
      0,
    ),
    (
      'app_widgets_spread_computed',
      const AppWidgetsSpreadComputed(names: ['a', 'b']),
      (VariantResolver r) =>
          AppWidgetsSpreadComputedSurface(names: const ['a', 'b'], resolver: r),
      <String>[],
      1,
    ),
    // A getter is code: it runs once, on every path.
    (
      'app_widgets_getter_arg',
      const AppWidgetsGetterArg(title: 'Pro'),
      (VariantResolver r) =>
          AppWidgetsGetterArgSurface(title: 'Pro', resolver: r),
      <String>[],
      1,
    ),
  ]) {
    testWidgets('$id: app widgets render and tap as the app does',
        (tester) async {
      final design = _design(id);
      for (final definition in inlined) {
        expect(design, contains(definition));
      }
      // Islands are named after their surface, underscores doubled.
      expect(
          RegExp('${id.replaceAll('_', '__')}_\\w+\\(')
              .allMatches(design)
              .length,
          islands);

      Future<(List<String?>, List<String>)> run(Widget widget) async {
        appWidgetCalls.clear();
        appWidgetStates = 0;
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: widget)));
        await tester.pumpAndSettle();
        final texts = [
          ..._texts(tester),
          // A forwarded key lands on the widget it names.
          if (find.byKey(const ValueKey('tag Pro')).evaluate().isNotEmpty)
            'key tag Pro',
        ];
        for (final label in ['Go', 'Braced', 'Bang']) {
          if (find.text(label).evaluate().isEmpty) continue;
          await tester.tap(find.text(label));
          await tester.pumpAndSettle();
        }
        if (find.byType(Switch).evaluate().isNotEmpty) {
          await tester.tap(find.byType(Switch));
          await tester.pumpAndSettle();
        }
        return (texts, [...appWidgetCalls]);
      }

      final app = await run(original);
      expect(app.$1, isNotEmpty);
      if (id != 'app_widgets_island') {
        expect(app.$2, isNotEmpty, reason: 'the app widget taps app code');
      }
      for (final (path, resolver) in [
        (
          'delivered',
          _Resolver(
              Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(design))))
        ),
        ('fallback', const _Resolver(null)),
      ]) {
        final rendered = await run(surface(resolver));
        expect(tester.takeException(), isNull, reason: path);
        expect(find.byType(RemoteWidget),
            path == 'delivered' ? findsOneWidget : findsNothing,
            reason: path);
        expect(rendered.$1, app.$1, reason: path);
        expect(rendered.$2, app.$2, reason: path);
      }
    });
  }

  // Flutter keeps a widget across rebuilds, so a theme change reruns its
  // build and not its initializers.
  testWidgets('app_widgets_init_field: a rebuild constructs nothing',
      (tester) async {
    final design = _design('app_widgets_init_field');
    // The texts of a mount under a light then a dark theme, and every app
    // call from the widget's construction on.
    Future<(List<List<String?>>, List<String>)> run(
        Widget Function() widget) async {
      await tester.pumpWidget(const SizedBox());
      appWidgetCalls.clear();
      final built = widget();
      final texts = <List<String?>>[];
      for (final brightness in [Brightness.light, Brightness.dark]) {
        await tester.pumpWidget(MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(body: built)));
        await tester.pumpAndSettle();
        texts.add(_texts(tester));
      }
      return (texts, [...appWidgetCalls]);
    }

    final app = await run(() => AppWidgetsInitField(count: 1));
    expect(app.$1, [
      ['N1', 'light'],
      ['N1', 'dark'],
    ]);
    expect(app.$2, ['shout n1']);
    for (final (path, resolver) in [
      (
        'delivered',
        _Resolver(
            Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(design))))
      ),
      ('fallback', const _Resolver(null)),
    ]) {
      final rendered = await run(
          () => AppWidgetsInitFieldSurface(count: 1, resolver: resolver));
      expect(tester.takeException(), isNull, reason: path);
      expect(rendered.$1, app.$1, reason: path);
      expect(rendered.$2, app.$2, reason: path);
    }
  });

  // A split widget: its design is delivered, its State lives in its wrapper.
  // Two instances keep separate State, and a rebuild keeps each one's.
  testWidgets('app_widgets_tally: split widgets keep their own State',
      (tester) async {
    registerRestageWidgets();
    final design = _design('app_widgets_tally');
    expect(design, contains('widget TallyChip = TallyChip__split('));
    expect(design, contains('restageWidget.values.'));

    Future<List<List<String?>>> run(Widget Function() widget) async {
      tallyChipStates = 0;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: widget())));
      await tester.pumpAndSettle();
      final seen = [_texts(tester)];
      for (final label in ['A #1: 0', 'A #1: 1', 'B #2: 0']) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }
      seen.add(_texts(tester));
      // A rebuild from above keeps each State.
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: widget())));
      await tester.pumpAndSettle();
      seen.add(_texts(tester));
      return seen;
    }

    final app = await run(() => const AppWidgetsTally());
    expect(app, [
      ['A #1: 0', 'B #2: 0'],
      ['A #1: 2', 'B #2: 1'],
      ['A #1: 2', 'B #2: 1'],
    ]);
    final delivered = _Resolver(
        Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(design))));
    for (final (path, resolver) in [
      ('delivered', delivered),
      ('fallback', const _Resolver(null)),
    ]) {
      final rendered =
          await run(() => AppWidgetsTallySurface(resolver: resolver));
      expect(tester.takeException(), isNull, reason: path);
      expect(find.byType(RemoteWidget),
          path == 'delivered' ? findsOneWidget : findsNothing,
          reason: path);
      expect(rendered, app, reason: path);
    }
  });

  // A delivered mount builds its States in the app's order, and a flip from
  // the fallback to the design and a new version in place keep each State,
  // for split widgets and islands alike.
  for (final (id, expected, count, surface, refreshes) in [
    (
      'app_widgets_tally',
      ['A #1: 0', 'B #2: 0'],
      () => tallyChipStates,
      (_Flipping r) => AppWidgetsTallySurface(resolver: r),
      true,
    ),
    (
      'app_widgets_screen_tally',
      ['A #1: 0', 'B #2: 0'],
      () => tallyChipStates,
      (_Flipping r) => AppWidgetsScreenTallySurface(resolver: r.screen),
      // A screen refreshes only through hosted placement delivery: the SDK's
      // island_placement_refresh_test runs its flip and new version.
      false,
    ),
    (
      'app_widgets_factory_tally',
      ['A #1: 0', 'B #2: 0'],
      () => factoryTallyChipStates,
      (_Flipping r) => AppWidgetsFactoryTallySurface(resolver: r),
      true,
    ),
    (
      'app_widgets_counted_pair',
      ['counted 1', 'counted 2'],
      () => appWidgetStates,
      (_Flipping r) => AppWidgetsCountedPairSurface(resolver: r),
      true,
    ),
  ]) {
    testWidgets(
        refreshes
            ? '$id: a flip and a new version keep each State'
            : '$id: delivered, it builds each State once, in order',
        (tester) async {
      registerRestageWidgets();
      final design =
          Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(_design(id))));
      Future<void> mount(_Flipping resolver) async {
        tallyChipStates = 0;
        factoryTallyChipStates = 0;
        appWidgetStates = 0;
        await tester.pumpWidget(const SizedBox());
        await tester
            .pumpWidget(MaterialApp(home: Scaffold(body: surface(resolver))));
        await tester.pumpAndSettle();
      }

      // Delivered at once: built in the app's order.
      await mount(_Flipping()..bytes = design);
      expect(find.byType(RemoteWidget), findsOneWidget);
      expect(_texts(tester), expected);
      expect(count(), 2);
      if (!refreshes) return;

      // A touched mount holds what it shows, so the flip comes untouched; the
      // State count shows whether each State moved or was made again.
      final resolver = _Flipping();
      await mount(resolver);
      expect(find.byType(RemoteWidget), findsNothing);
      expect(_texts(tester), expected);
      expect(count(), 2);
      resolver.bytes = design;
      await Restage.reloadSurfaces();
      await tester.pumpAndSettle();
      expect(find.byType(RemoteWidget), findsOneWidget);
      expect(_texts(tester), expected);
      expect(count(), 2);
      // A new version of the design replaces the shown one in place.
      final shown = tester.widget<RemoteWidget>(find.byType(RemoteWidget));
      resolver.version = 2;
      await Restage.reloadSurfaces();
      await tester.pumpAndSettle();
      expect(
          identical(
              tester.widget<RemoteWidget>(find.byType(RemoteWidget)), shown),
          isFalse);
      expect(_texts(tester), expected);
      expect(count(), 2);
    });
  }

  // An app widget placed at several spots, through a local, a helper or a
  // loop inside a local's value: Flutter gives each spot its own element, so
  // each keeps its own State, across a flip and a new version.
  for (final (id, app, surface, expected) in [
    (
      'app_widgets_count_twice',
      const AppWidgetsCountTwice(),
      (_Flipping r) => AppWidgetsCountTwiceSurface(resolver: r),
      ['count 2', 'between', 'count 1'],
    ),
    (
      'app_widgets_count_spread',
      const AppWidgetsCountSpread(),
      (_Flipping r) => AppWidgetsCountSpreadSurface(resolver: r),
      ['count 2', 'between', 'count 1'],
    ),
    (
      'app_widgets_count_framed_twice',
      const AppWidgetsCountFramedTwice(),
      (_Flipping r) => AppWidgetsCountFramedTwiceSurface(resolver: r),
      ['framed', 'count 2', 'count 1'],
    ),
    (
      'app_widgets_count_rows',
      const AppWidgetsCountRows(names: ['a', 'b']),
      (_Flipping r) =>
          AppWidgetsCountRowsSurface(names: const ['a', 'b'], resolver: r),
      ['rows', 'count 2', 'count 1'],
    ),
  ]) {
    testWidgets('$id: each spot keeps its own State', (tester) async {
      registerRestageWidgets();
      final design =
          Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(_design(id))));
      Future<void> mount(Widget widget) async {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: widget)));
        await tester.pumpAndSettle();
      }

      // The first spot counts twice and the second once, without a touch,
      // which would hold a new design back.
      Future<void> bump() async {
        final states = tester.stateList<AppCountState>(find.byType(AppCount));
        expect(states, hasLength(2));
        states.first
          ..bump()
          ..bump();
        states.last.bump();
        await tester.pump();
      }

      await mount(app);
      await bump();
      expect(_texts(tester), expected);

      await mount(surface(_Flipping()..bytes = design));
      expect(find.byType(RemoteWidget), findsOneWidget);
      await bump();
      expect(_texts(tester), expected);

      final resolver = _Flipping();
      await mount(surface(resolver));
      expect(find.byType(RemoteWidget), findsNothing);
      await bump();
      expect(_texts(tester), expected);
      resolver.bytes = design;
      await Restage.reloadSurfaces();
      await tester.pumpAndSettle();
      expect(find.byType(RemoteWidget), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(_texts(tester), expected);
      resolver.version = 2;
      await Restage.reloadSurfaces();
      await tester.pumpAndSettle();
      expect(_texts(tester), expected);
    });
  }

  // Split widgets keyed by the app in a loop keep their States when the
  // loop's order changes, as Flutter matches keyed elements.
  testWidgets('app_widgets_keyed_tally: a reorder keeps each State',
      (tester) async {
    registerRestageWidgets();
    final design = Uint8List.fromList(encodeLibraryBlob(
        parseLibraryFile(_design('app_widgets_keyed_tally'))));
    Future<List<List<String?>>> run(
        Widget Function(List<String> names) widget) async {
      tallyChipStates = 0;
      final names = ValueNotifier(const ['a', 'b']);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ValueListenableBuilder<List<String>>(
                  valueListenable: names,
                  builder: (_, value, __) => widget(value)))));
      await tester.pumpAndSettle();
      final seen = [_texts(tester)];
      await tester.tap(find.text('a #1: 0'));
      await tester.pumpAndSettle();
      names.value = const ['b', 'a'];
      await tester.pumpAndSettle();
      seen
        ..add(_texts(tester))
        ..add(['$tallyChipStates']);
      return seen;
    }

    final app = await run((names) => AppWidgetsKeyedTally(names: names));
    expect(app, [
      ['a #1: 0', 'b #2: 0'],
      ['b #2: 0', 'a #1: 1'],
      ['2'],
    ]);
    for (final (path, resolver) in [
      ('delivered', _Resolver(design)),
      ('fallback', const _Resolver(null)),
    ]) {
      final rendered = await run((names) =>
          AppWidgetsKeyedTallySurface(names: names, resolver: resolver));
      expect(tester.takeException(), isNull, reason: path);
      expect(find.byType(RemoteWidget),
          path == 'delivered' ? findsOneWidget : findsNothing,
          reason: path);
      expect(rendered, app, reason: path);
    }
  });

  // A split widget's recorded text scaler reaches its delivered body.
  testWidgets("app_widgets_scaled: a split widget reads the app's text scale",
      (tester) async {
    registerRestageWidgets();
    final design = _design('app_widgets_scaled');
    expect(design, contains('widget ScaledChip = ScaledChip__split('));
    expect(design, contains('textScaler: restageWidget.values.'));
    Future<List<(String, double)>> run(Widget widget) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(body: widget))));
      await tester.pumpAndSettle();
      return [
        for (final element in find.byType(RichText).evaluate())
          (
            (element.widget as RichText).text.toPlainText(),
            (element.widget as RichText).textScaler.scale(10),
          ),
      ];
    }

    final app = await run(const AppWidgetsScaled());
    expect(app, [('Scaled', 15.0)]);
    for (final (path, resolver) in [
      (
        'delivered',
        _Resolver(
            Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(design))))
      ),
      ('fallback', const _Resolver(null)),
    ]) {
      final rendered = await run(AppWidgetsScaledSurface(resolver: resolver));
      expect(tester.takeException(), isNull, reason: path);
      expect(find.byType(RemoteWidget),
          path == 'delivered' ? findsOneWidget : findsNothing,
          reason: path);
      expect(rendered, app, reason: path);
    }
  });

  // A callback that returns a value: Flutter reads the app's description.
  testWidgets('app_widgets_slider: a returned value reaches Flutter',
      (tester) async {
    final design = _design('app_widgets_slider');
    expect(design, contains('semanticFormatterCallback: {nativeEvent: '));
    final semantics = tester.ensureSemantics();
    Future<String> run(Widget widget) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: widget)));
      await tester.pumpAndSettle();
      return _value(tester.getSemantics(find.byType(Slider)));
    }

    final app = await run(const AppWidgetsSlider());
    expect(app, '25 percent');
    for (final (path, resolver) in [
      (
        'delivered',
        _Resolver(
            Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(design))))
      ),
      ('fallback', const _Resolver(null)),
    ]) {
      final value = await run(AppWidgetsSliderSurface(resolver: resolver));
      expect(tester.takeException(), isNull, reason: path);
      expect(find.byType(RemoteWidget),
          path == 'delivered' ? findsOneWidget : findsNothing,
          reason: path);
      expect(value, app, reason: path);
    }
    semantics.dispose();
  });

  // A key an app widget's own build creates lands where the app puts it, and
  // the island's child keeps its State when a reload swaps the fallback for
  // the design.
  testWidgets('app_widgets_own_keys: own keys stay with the app',
      (tester) async {
    registerRestageWidgets();
    final design = _design('app_widgets_own_keys');
    expect(design, contains('app__widgets__own__keys_AppOwnKey_0()'));
    expect(design, contains('widget OwnKeyChip = OwnKeyChip__split('));
    final blob =
        Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(design)));

    Future<List<String?>> run(Widget widget) async {
      appOwnKeyStates = 0;
      ownKeyChipStates = 0;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: widget)));
      await tester.pumpAndSettle();
      return [
        ..._texts(tester),
        for (final key in ['own', 'chip'])
          if (find.byKey(ValueKey<String>(key)).evaluate().isNotEmpty)
            'key $key',
      ];
    }

    final app = await run(const AppWidgetsOwnKeys());
    expect(app, ['keys', 'own 1', 'chip 1', 'key own', 'key chip']);
    for (final (path, resolver) in [
      ('delivered', _Resolver(blob)),
      ('fallback', const _Resolver(null)),
    ]) {
      final rendered = await run(AppWidgetsOwnKeysSurface(resolver: resolver));
      expect(tester.takeException(), isNull, reason: path);
      expect(find.byType(RemoteWidget),
          path == 'delivered' ? findsOneWidget : findsNothing,
          reason: path);
      expect(rendered, app, reason: path);
    }

    final resolver = _Switchable(null);
    expect(await run(AppWidgetsOwnKeysSurface(resolver: resolver)), app);
    resolver.bytes = blob;
    await Restage.reloadSurfaces();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(RemoteWidget), findsOneWidget);
    expect(_texts(tester), containsAll(['keys', 'own 1', 'chip 1']));
    expect(appOwnKeyStates, 1);
    // The split widget's keyed child keeps its State across the flip too.
    expect(ownKeyChipStates, 1);
  });
}
