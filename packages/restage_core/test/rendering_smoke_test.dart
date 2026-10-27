// Catalog-walker rendering smoke for the restage.core library.
//
// Iterates `kRegistry.widgets`, synthesises a minimal-valid-props rfw
// source fragment per widget, composes them into one root Column, and
// renders the tree once via the rfw Runtime. For every catalog entry
// the factory's top-level returned widget must be of the expected
// Flutter type — proving the generated factory function instantiates
// the right Flutter widget class without throwing.
//
// The assertion is structural rather than `find.byType`-based: each
// `LocalWidgetLibrary` builder is wrapped to emit a private
// `_SmokeMarker(name, child)` whose `child` is exactly what the
// factory returned. Per-entry assertions find markers by name and
// type-check `marker.child.runtimeType`. This stays robust against
// incidental widgets in the tree — `Image.network`'s broken-image
// placeholder internally composes Padding + Text + Center + SizedBox
// + Column + Container, six catalog entries, and without the wrap
// each would silently satisfy a corresponding `find.byType` assertion
// even if the matching factory had thrown.
//
// Adding a new entry to `kRegistry` automatically extends the smoke;
// at most a curated minimal-props entry is needed when a widget has
// non-defaultable required arguments that the generic synthesiser
// can't construct.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart';

const LibraryName _coreLibrary = LibraryName(<String>['restage', 'core']);
const LibraryName _rootLibrary = LibraryName(<String>['restage', 'paywall']);

/// Catalog entries that won't lay out as Column children. Each gets a
/// dedicated `testWidgets` block below; the main walker excludes them.
///
/// * `Positioned` / `AnimatedPositioned` only lay out inside a `Stack`.
/// * `ListView` / `SingleChildScrollView` need bounded constraints
///   on the scroll axis — a `Column` gives unbounded vertical to its
///   non-flex children, which a scrollable can't lay out against.
const Set<String> _rootOnlyEntries = <String>{
  'AnimatedPositioned',
  'ListView',
  'Positioned',
  'SingleChildScrollView',
};

/// A minimal value for each required property type a factory demands.
const Map<PropertyType, String> _requiredValueByType = <PropertyType, String>{
  PropertyType.widget: 'SizedBox()',
  PropertyType.widgetList: '[SizedBox()]',
  PropertyType.duration: '200',
  PropertyType.real: '1.0',
  PropertyType.integer: '1',
  PropertyType.length: '100.0',
  PropertyType.alignment: '{x: 0.0, y: 0.0}',
  PropertyType.offset: '{x: 0.0, y: 0.0}',
  PropertyType.edgeInsets: '[0.0, 0.0, 0.0, 0.0]',
  PropertyType.color: '0xFF2196F3',
  PropertyType.string: '"smoke"',
};

const String _grid =
    '{_s: "SliverGridDelegateWithFixedCrossAxisCount", crossAxisCount: 2}';

/// Entries whose required values the type table cannot supply. Image loads
/// fail under the test binding and are drained via `tester.takeException()`.
const Map<String, String> _curatedMinimalRfwSource = <String, String>{
  'ClipPathShape': 'ClipPathShape(shape: {type: "rounded", '
      'borderRadius: {topLeft: 12.0}}, child: SizedBox())',
  'Directionality': 'Directionality(textDirection: "ltr", child: SizedBox())',
  'FadeInImageAssetNetwork':
      'FadeInImageAssetNetwork(placeholder: "smoke.png", '
          'image: "https://smoke.invalid/2.png")',
  'GestureDetector': 'GestureDetector(child: SizedBox())',
  'GridView': 'GridView(shrinkWrap: true, gridDelegate: $_grid)',
  'GridViewCount': 'GridViewCount(shrinkWrap: true, crossAxisCount: 2)',
  'GridViewExtent': 'GridViewExtent(shrinkWrap: true, maxCrossAxisExtent: 1.0)',
  'GridViewCustom': 'GridViewCustom(shrinkWrap: true, gridDelegate: $_grid, '
      'childrenDelegate: {_s: "SliverChildListDelegate", children: []})',
  'Image': 'Image(url: "https://smoke.invalid/1.png")',
  'ImageAsset': 'ImageAsset(name: "smoke.png")',
  'TextRich': 'TextRich(textSpan: { text: "smoke" })',
  'TransformScale': 'TransformScale(scale: 1.0)',
};

String _minimalRfwSourceFor(WidgetEntry entry) {
  final curated = _curatedMinimalRfwSource[entry.name];
  if (curated != null) return curated;
  final arguments = [
    for (final property in entry.properties)
      if (property.required)
        if (_requiredValueByType[property.type] case final value?)
          '${property.name}: $value',
  ];
  return '${entry.name}(${arguments.join(', ')})';
}

String _composeSmokeSource(Iterable<WidgetEntry> entries) {
  final fragments = entries.map(_minimalRfwSourceFor).join(',\n      ');
  return '''
import restage.core;

widget Paywall = Column(
  children: [
      $fragments,
  ],
);
''';
}

/// Wraps each builder in a `LocalWidgetLibrary` so the result of every
/// factory invocation is enclosed in a `_SmokeMarker(name, child:
/// factoryReturn)`. The marker preserves the factory's top-level
/// returned widget as its `child` for direct type inspection at
/// assertion time.
LocalWidgetLibrary _wrapLocalLibraryForSmoke(LocalWidgetLibrary library) {
  return LocalWidgetLibrary(<String, LocalWidgetBuilder>{
    for (final entry in library.widgets.entries)
      entry.key: (BuildContext ctx, DataSource source) => _SmokeMarker(
            name: entry.key,
            child: entry.value(ctx, source),
          ),
  });
}

/// Test-only marker the smoke wrap inserts above each rfw factory's
/// returned widget. The marker's `build` returns its `child` unchanged,
/// so layout matches the unwrapped tree; the per-entry assertion finds
/// the marker by name and checks `child.runtimeType`.
class _SmokeMarker extends StatelessWidget {
  const _SmokeMarker({required this.name, required this.child});

  final String name;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

void _expectRendered(WidgetEntry entry) {
  final markers = find
      .byWidgetPredicate(
          (widget) => widget is _SmokeMarker && widget.name == entry.name)
      .evaluate();
  expect(
    markers,
    isNotEmpty,
    reason: 'no _SmokeMarker emitted for ${entry.name} — the factory '
        'either threw or rfw substituted an ErrorWidget',
  );
  // A factory returns the catalog's Flutter class or its Restage wrapper;
  // ClipPath.shape and resource-owning factories return a builder around it.
  final expected = entry.flutterType.split('#').last.split('.').first;
  bool named(Widget widget) =>
      '${widget.runtimeType}' == expected ||
      '${widget.runtimeType}' == 'Restage$expected';
  for (final element in markers) {
    final child = (element.widget as _SmokeMarker).child;
    expect(
      child is Builder || child is RestageResourceBuilder
          ? find
              .descendant(
                  of: find.byWidget(child),
                  matching: find.byWidgetPredicate(named))
              .evaluate()
              .isNotEmpty
          : named(child),
      isTrue,
      reason: 'factory for ${entry.name} returned ${child.runtimeType} '
          '(catalog flutterType: ${entry.flutterType})',
    );
  }
}

Runtime _buildRuntime(String paywallSource) => Runtime()
  ..update(_coreLibrary, _wrapLocalLibraryForSmoke(buildCoreWidgetLibrary()))
  ..update(_rootLibrary, parseLibraryFile(paywallSource));

/// Renders one root-only catalog entry, wrapping the rfw-rendered
/// paywall in a per-entry Flutter widget that supplies whatever
/// ancestor the entry requires (a `Stack` for `Positioned`, a sized
/// box for the scrollables).
Future<void> _pumpRootOnly(
  WidgetTester tester, {
  required String entryName,
  required String paywallSource,
  required Widget Function(Widget paywall) wrap,
}) async {
  final entry = kRegistry.widgets.firstWhere((w) => w.name == entryName);
  final runtime = _buildRuntime(paywallSource);
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: wrap(
        RemoteWidget(
          runtime: runtime,
          data: DynamicContent(),
          widget: const FullyQualifiedWidgetName(_rootLibrary, 'Paywall'),
          onEvent: (_, __) {},
        ),
      ),
    ),
  );
  await tester.pump();
  _expectRendered(entry);
}

void main() {
  group('restage_core rendering smoke', () {
    testWidgets('every catalog widget renders into the tree', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final allEntries = kRegistry.widgets;
      expect(allEntries, isNotEmpty,
          reason: 'kRegistry must have widgets for the smoke to be meaningful');

      // Builder widgets need compiled builder programs; their runtime tests
      // render them.
      final walkerEntries = allEntries
          .where((w) =>
              !_rootOnlyEntries.contains(w.name) &&
              !w.properties.any(
                  (p) => p.required && p.type == PropertyType.widgetBuilder))
          .toList();

      final runtime = _buildRuntime(_composeSmokeSource(walkerEntries));
      final data = DynamicContent();

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: RemoteWidget(
            runtime: runtime,
            data: data,
            widget: const FullyQualifiedWidgetName(_rootLibrary, 'Paywall'),
            onEvent: (_, __) {},
          ),
        ),
      );
      await tester.pump();
      // Drain async image-load failures from `Image.network`,
      // `Image.asset`, and `FadeInImage.assetNetwork`. Each completes
      // with an exception (HTTP 400 / asset-not-found) that lands in
      // the binding's exception queue. Expected; clear them.
      await tester.runAsync<void>(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      while (tester.takeException() != null) {
        // Drain all pending exceptions from the image-load failures.
      }

      for (final entry in walkerEntries) {
        _expectRendered(entry);
      }
    });

    // Root-only entries need ancestors the main walker's Column can't
    // provide (`Stack` for `Positioned`; bounded constraints for the
    // scrollables). Each gets its own block with a custom wrap.

    testWidgets('Positioned renders inside a Stack', (tester) async {
      await _pumpRootOnly(
        tester,
        entryName: 'Positioned',
        paywallSource: '''
import restage.core;
widget Paywall = Stack(
  children: [Positioned(left: 0.0, top: 0.0, child: SizedBox())],
);
''',
        wrap: (paywall) => paywall,
      );
    });

    testWidgets('AnimatedPositioned renders inside a Stack', (tester) async {
      await _pumpRootOnly(
        tester,
        entryName: 'AnimatedPositioned',
        paywallSource: '''
import restage.core;
widget Paywall = Stack(
  children: [
    AnimatedPositioned(
      left: 0.0,
      top: 0.0,
      duration: 200,
      child: SizedBox(),
    ),
  ],
);
''',
        wrap: (paywall) => paywall,
      );
    });

    testWidgets('ListView renders in bounded constraints', (tester) async {
      await _pumpRootOnly(
        tester,
        entryName: 'ListView',
        paywallSource: '''
import restage.core;
widget Paywall = ListView();
''',
        wrap: (paywall) => SizedBox(width: 200, height: 200, child: paywall),
      );
    });

    testWidgets('SingleChildScrollView renders in bounded constraints',
        (tester) async {
      await _pumpRootOnly(
        tester,
        entryName: 'SingleChildScrollView',
        paywallSource: '''
import restage.core;
widget Paywall = SingleChildScrollView();
''',
        wrap: (paywall) => SizedBox(width: 200, height: 200, child: paywall),
      );
    });

    testWidgets(
      'DecoratedBox reconstructs its gradient fill',
      (tester) async {
        final runtime = _buildRuntime('''
import restage.core;
widget Paywall = DecoratedBox(
  gradient: {type: "radial", colors: [0xFFAA0000, 0xFF00AA00]},
  child: SizedBox(width: 100.0, height: 100.0),
);
''');
        await tester.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: RemoteWidget(
            runtime: runtime,
            data: DynamicContent(),
            widget: const FullyQualifiedWidgetName(_rootLibrary, 'Paywall'),
          ),
        ));
        final marker = tester.widget<_SmokeMarker>(find.byWidgetPredicate(
            (w) => w is _SmokeMarker && w.name == 'DecoratedBox'));
        final decoration =
            (marker.child as DecoratedBox).decoration as BoxDecoration;
        expect(decoration.gradient, isA<RadialGradient>());
        expect(decoration.gradient!.colors,
            [const Color(0xFFAA0000), const Color(0xFF00AA00)]);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Container BoxDecoration round-trips color, borderRadius, '
      'gradient, border, boxShadow',
      (tester) async {
        // End-to-end: author wire-shape via paywall source → encode →
        // decode through the SDK factory → assert each BoxDecoration
        // field is reconstructed. Locks the catalog's recipe-flat
        // contract against rfw's structured-type decoders.
        const blob = '''
import restage.core;
widget Paywall = Container(
  color: 0xFF112233,
  borderRadius: 8.0,
  gradient: {
    type: "linear",
    begin: {x: -1.0, y: -1.0},
    end: {x: 1.0, y: 1.0},
    colors: [0xFFAA0000, 0xFF00AA00],
  },
  border: [{color: 0xFF000000, width: 2.0}],
  boxShadow: [{color: 0xFF8B5CF6, blurRadius: 24.0, offset: {x: 0.0, y: 8.0}}],
);
''';
        final runtime = _buildRuntime(blob);
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: RemoteWidget(
              runtime: runtime,
              data: DynamicContent(),
              widget: const FullyQualifiedWidgetName(_rootLibrary, 'Paywall'),
              onEvent: (_, __) {},
            ),
          ),
        );
        await tester.pump();

        final marker = tester.widget<_SmokeMarker>(
          find.byWidgetPredicate(
            (w) => w is _SmokeMarker && w.name == 'Container',
          ),
        );
        final container = marker.child as Container;
        final decoration = container.decoration! as BoxDecoration;
        expect(decoration.color, const Color(0xFF112233));
        expect(decoration.borderRadius, BorderRadius.circular(8));
        expect(decoration.gradient, isA<LinearGradient>());
        final gradient = decoration.gradient! as LinearGradient;
        expect(gradient.colors.first, const Color(0xFFAA0000));
        expect(decoration.border, isNotNull);
        expect(decoration.boxShadow, hasLength(1));
        expect(decoration.boxShadow!.first.color, const Color(0xFF8B5CF6));
        expect(decoration.boxShadow!.first.blurRadius, 24.0);
      },
    );

    testWidgets(
      'Container BoxDecoration with shape: circle round-trips without '
      'tripping the shape/borderRadius assertion',
      (tester) async {
        // BoxDecoration asserts `shape != BoxShape.circle ||
        // borderRadius == null`. A missing borderRadius slot must
        // collapse to `null` in the recipe-inner-arg path, not to
        // BorderRadius.zero — otherwise this would crash in debug.
        const blob = '''
import restage.core;
widget Paywall = Container(
  color: 0xFFF2F2F7,
  shape: "circle",
);
''';
        final runtime = _buildRuntime(blob);
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: RemoteWidget(
              runtime: runtime,
              data: DynamicContent(),
              widget: const FullyQualifiedWidgetName(_rootLibrary, 'Paywall'),
              onEvent: (_, __) {},
            ),
          ),
        );
        await tester.pump();

        final marker = tester.widget<_SmokeMarker>(
          find.byWidgetPredicate(
            (w) => w is _SmokeMarker && w.name == 'Container',
          ),
        );
        final container = marker.child as Container;
        final decoration = container.decoration! as BoxDecoration;
        expect(decoration.shape, BoxShape.circle);
        expect(decoration.borderRadius, isNull);
      },
    );
  });
}
