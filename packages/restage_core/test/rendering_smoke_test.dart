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

/// Curated minimal-props for catalog entries the generic synthesiser
/// can't render with empty arguments.
///
/// The factory emitter throws on missing `required: true` scalars
/// (string, edgeInsets, double, etc.) and on missing required widget
/// children (`source.child(...)`), so any widget with such a property
/// must supply a fragment here.
///
/// `Image` / `ImageAsset` / `FadeInImage` all kick off async image
/// loads that fail under `TestWidgetsFlutterBinding`: `Image.network`
/// returns HTTP 400, `Image.asset` and `FadeInImage.assetNetwork`'s
/// asset lookup misses the rootBundle. Each surfaces an exception via
/// the image stream that lands in the binding's exception queue and
/// is drained via `tester.takeException()` after the pump completes.
const Map<String, String> _curatedMinimalRfwSource = <String, String>{
  'AnimatedAlign': 'AnimatedAlign(alignment: {x: 0.0, y: 0.0}, duration: 200, '
      'child: SizedBox())',
  'AnimatedContainer':
      'AnimatedContainer(duration: 200, width: 32.0, height: 32.0)',
  'AnimatedDefaultTextStyle':
      'AnimatedDefaultTextStyle(duration: 200, child: SizedBox())',
  'AnimatedOpacity':
      'AnimatedOpacity(opacity: 1.0, duration: 200, child: SizedBox())',
  'AnimatedPadding':
      'AnimatedPadding(padding: [0.0, 0.0, 0.0, 0.0], duration: 200, '
          'child: SizedBox())',
  'AnimatedRotation':
      'AnimatedRotation(turns: 0.0, alignment: {x: 0.0, y: 0.0}, '
          'duration: 200, child: SizedBox())',
  'AnimatedScale': 'AnimatedScale(scale: 1.0, alignment: {x: 0.0, y: 0.0}, '
      'duration: 200, child: SizedBox())',
  'AnimatedSize': 'AnimatedSize(duration: 200, child: SizedBox())',
  'AnimatedSlide': 'AnimatedSlide(offset: {x: 0.0, y: 0.0}, duration: 200, '
      'child: SizedBox())',
  'AspectRatio': 'AspectRatio(aspectRatio: 1.0)',
  'DefaultTextStyle': 'DefaultTextStyle(child: SizedBox())',
  'Expanded': 'Expanded(child: SizedBox())',
  'FadeInImageAssetNetwork':
      'FadeInImageAssetNetwork(placeholder: "smoke.png", '
          'image: "https://smoke.invalid/2.png")',
  'Flexible': 'Flexible(child: SizedBox())',
  'GestureDetector': 'GestureDetector(child: SizedBox())',
  'Image': 'Image(url: "https://smoke.invalid/1.png")',
  'ImageAsset': 'ImageAsset(name: "smoke.png")',
  'LimitedBox': 'LimitedBox(maxWidth: 100.0, maxHeight: 100.0)',
  'RestageFadeIn': 'RestageFadeIn(child: SizedBox())',
  'RestageMotion': 'RestageMotion(child: SizedBox())',
  'RestagePulse': 'RestagePulse(child: SizedBox())',
  'RestageStagger': 'RestageStagger(children: [SizedBox()])',
  'Opacity': 'Opacity(opacity: 1.0)',
  'Padding': 'Padding(padding: [0.0, 0.0, 0.0, 0.0])',
  'RotatedBox': 'RotatedBox(quarterTurns: 0)',
  'SafeArea': 'SafeArea(child: SizedBox())',
  'Text': 'Text(text: "smoke")',
  // TextRich's positional `textSpan` is required (the factory throws on a
  // missing slot), so the generic `TextRich()` synthesiser can't render it —
  // supply a minimal one-node inline-span tree.
  'TextRich': 'TextRich(textSpan: { text: "smoke" })',
  'TransformRotate': 'TransformRotate(angle: 0.0)',
  'Visibility': 'Visibility(child: SizedBox())',
};

/// Factory-function defaults handle missing properties (`source.v` returns
/// null, `optionalChild` returns null, `childList` returns []), so the
/// default fragment for any entry is just an empty constructor call.
String _minimalRfwSourceFor(WidgetEntry entry) =>
    _curatedMinimalRfwSource[entry.name] ?? '${entry.name}()';

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

/// Maps the catalog `entry.name` to the corresponding Flutter [Type].
///
/// The mapping is hand-maintained rather than reflected from
/// `entry.flutterType` because Dart Type objects can't be looked up by
/// URI at runtime. Named-constructor variants (`ImageAsset`) map to
/// the same base class as their default-constructor sibling, since
/// Flutter has no distinct Type per named constructor. A new catalog
/// entry trips a clear `StateError` here before reaching the
/// assertion loop.
Type _flutterTypeFor(String entryName) {
  switch (entryName) {
    case 'Align':
      return Align;
    case 'AnimatedAlign':
      return AnimatedAlign;
    case 'AnimatedContainer':
      return AnimatedContainer;
    case 'AnimatedDefaultTextStyle':
      return AnimatedDefaultTextStyle;
    case 'AnimatedOpacity':
      return AnimatedOpacity;
    case 'AnimatedPadding':
      return AnimatedPadding;
    case 'AnimatedPositioned':
      return AnimatedPositioned;
    case 'AnimatedRotation':
      return AnimatedRotation;
    case 'AnimatedScale':
      return AnimatedScale;
    case 'AnimatedSize':
      return AnimatedSize;
    case 'AnimatedSlide':
      return AnimatedSlide;
    case 'AspectRatio':
      return AspectRatio;
    case 'BackdropFilter':
      return BackdropFilter;
    case 'Center':
      return Center;
    case 'ClipOval':
      return ClipOval;
    case 'ClipRect':
      return ClipRect;
    case 'ClipRRect':
      return ClipRRect;
    case 'Column':
      return Column;
    case 'Container':
      return Container;
    case 'DecoratedBox':
      return DecoratedBox;
    case 'DefaultTextStyle':
      return DefaultTextStyle;
    case 'Expanded':
      return Expanded;
    case 'FadeInImageAssetNetwork':
      return FadeInImage;
    case 'FittedBox':
      return FittedBox;
    case 'FractionallySizedBox':
      return FractionallySizedBox;
    case 'Flexible':
      return Flexible;
    case 'GestureDetector':
      return GestureDetector;
    case 'Image':
    case 'ImageAsset':
      return Image;
    case 'IntrinsicHeight':
      return IntrinsicHeight;
    case 'IntrinsicWidth':
      return IntrinsicWidth;
    case 'LimitedBox':
      return LimitedBox;
    case 'ListView':
      return ListView;
    case 'RestageFadeIn':
      return RestageFadeIn;
    case 'RestageFormattedNumber':
      return RestageFormattedNumber;
    case 'RestageMotion':
      return RestageMotion;
    case 'RestagePrice':
      return RestagePrice;
    case 'RestagePulse':
      return RestagePulse;
    case 'RestageStagger':
      return RestageStagger;
    case 'Opacity':
      return Opacity;
    case 'Padding':
      return Padding;
    case 'Positioned':
      return Positioned;
    case 'RotatedBox':
      return RotatedBox;
    case 'Row':
      return Row;
    case 'SafeArea':
      return SafeArea;
    case 'SingleChildScrollView':
      return SingleChildScrollView;
    case 'SizedBox':
      return SizedBox;
    case 'Spacer':
      return Spacer;
    case 'Stack':
      return Stack;
    case 'Text':
    case 'TextRich':
      // `Text.rich` constructs a `Text` widget (Flutter has no distinct Type
      // per named constructor), same as the plain `Text` entry.
      return Text;
    case 'TransformRotate':
      return Transform;
    case 'Visibility':
      return Visibility;
    case 'Wrap':
      return Wrap;
  }
  throw StateError(
    'rendering_smoke_test: no Flutter Type mapping for catalog entry '
    '"$entryName" — add a case to _flutterTypeFor.',
  );
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
  final expectedType = _flutterTypeFor(entry.name);
  for (final element in markers) {
    final marker = element.widget as _SmokeMarker;
    expect(
      marker.child.runtimeType,
      expectedType,
      reason: 'factory for ${entry.name} returned ${marker.child.runtimeType}, '
          'expected $expectedType (catalog flutterType: ${entry.flutterType})',
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

      final walkerEntries =
          allEntries.where((w) => !_rootOnlyEntries.contains(w.name)).toList();

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
