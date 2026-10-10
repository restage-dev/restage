// Renders through generated factories to check repaired layout geometry.
// Invalid scalars may cause failures only when combined with constraints,
// offsets or decoration padding.

import 'dart:convert';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart';

const LibraryName _coreLibrary = LibraryName(<String>['restage', 'core']);
const LibraryName _rootLibrary = LibraryName(<String>['restage', 'paywall']);

/// The bounded viewport these cases lay out against.
const double _kViewport = 300;

/// Serves a real single-pixel image for any asset key, so an image case lays out
/// against a decoded image rather than a load failure. A failed load builds a
/// debug error widget instead of the image, which would remove the very render
/// object whose derived size these cases assert on.
class _SinglePixelAssetBundle extends CachingAssetBundle {
  static final Uint8List _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0l'
    'EQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );

  @override
  Future<ByteData> load(String key) async {
    // The image provider resolves scale variants through the asset manifest
    // before requesting bytes; an empty manifest keeps the pixel at scale 1.
    if (key == 'AssetManifest.bin') {
      return const StandardMessageCodec().encodeMessage(<String, Object?>{})!;
    }
    return ByteData.sublistView(_png);
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async =>
      throw UnimplementedError();
}

Future<void> _pump(
  WidgetTester tester,
  String paywallSource, {
  Map<String, Object?>? data,
  AssetBundle? bundle,
}) async {
  final runtime = Runtime()
    ..update(_coreLibrary, buildCoreWidgetLibrary())
    ..update(_rootLibrary, parseLibraryFile(paywallSource));
  final remoteWidget = RemoteWidget(
    runtime: runtime,
    data: DynamicContent(data ?? <String, Object?>{}),
    widget: const FullyQualifiedWidgetName(_rootLibrary, 'Paywall'),
    onEvent: (_, __) {},
  );
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      // Loosen the test window's tight root constraints before applying the
      // bounded viewport used by every derived-position assertion.
      child: Center(
        child: SizedBox(
          width: _kViewport,
          height: _kViewport,
          child: bundle == null
              ? remoteWidget
              : DefaultAssetBundle(bundle: bundle, child: remoteWidget),
        ),
      ),
    ),
  );
  await tester.pump();
}

String _inUnboundedWidth(String widget) => '''
import restage.core;
widget Paywall = Row(children: [$widget]);
''';

String _inUnboundedHeight(String widget) => '''
import restage.core;
widget Paywall = Column(children: [$widget]);
''';

/// A decorated box on an axis its parent leaves unbounded.
///
/// The scroll view ensures that decoration padding contributes directly to the
/// box's derived width instead of being hidden by a tight parent.
String _borderInUnboundedAxis(String widget) => '''
import restage.core;
widget Paywall = SingleChildScrollView(scrollDirection: "horizontal",
  child: $widget);
''';

/// Collects every error reported while [body] runs, so a case can assert on a
/// specific failure even when a later one follows it. The test binding collapses
/// multiple pending errors into one summary, which would otherwise make the
/// originating exception unassertable.
Future<List<Object>> _collectErrors(Future<void> Function() body) async {
  final errors = <Object>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) => errors.add(details.exception);
  try {
    await body();
  } finally {
    FlutterError.onError = previous;
  }
  return errors;
}

void main() {
  group('an alignment component is repaired before it can reach layout', () {
    // An alignment slot is a map of {x, y} or {start, y}. A non-map value
    // decodes to null, so the factory's own default applies; only a map can
    // carry a non-finite component.
    testWidgets('a NaN x is zeroed without discarding the authored y',
        (tester) async {
      await _pump(
        tester,
        '''
import restage.core;
widget Paywall = Align(alignment: {x: data.nan, y: 1.0},
  child: Container(width: 20.0, height: 20.0));
''',
        data: <String, Object?>{'nan': double.nan},
      );

      final alignTopLeft = tester.getTopLeft(find.byType(RestageAlign));
      final childTopLeft = tester.getTopLeft(find.byType(Container));
      // Zero x centers the child; the surviving y = 1 keeps it at the bottom.
      expect(childTopLeft.dx, alignTopLeft.dx + 140.0);
      expect(childTopLeft.dy, alignTopLeft.dy + 280.0);
      expect(childTopLeft.dx.isFinite, isTrue);
      expect(childTopLeft.dy.isFinite, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an infinite y is zeroed without discarding the authored x',
        (tester) async {
      await _pump(
        tester,
        '''
import restage.core;
widget Paywall = Align(alignment: {x: 1.0, y: data.inf},
  child: Container(width: 20.0, height: 20.0));
''',
        data: <String, Object?>{'inf': double.infinity},
      );

      final alignTopLeft = tester.getTopLeft(find.byType(RestageAlign));
      final childTopLeft = tester.getTopLeft(find.byType(Container));
      // The surviving x = 1 keeps the child at the right; zero y centers it.
      expect(childTopLeft.dx, alignTopLeft.dx + 280.0);
      expect(childTopLeft.dy, alignTopLeft.dy + 140.0);
      expect(childTopLeft.dx.isFinite, isTrue);
      expect(childTopLeft.dy.isFinite, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('AnimatedScale repairs its concrete alignment components',
        (tester) async {
      await _pump(
        tester,
        '''
import restage.core;
widget Paywall = Align(child: AnimatedScale(scale: 2.0, duration: 100,
  alignment: {x: data.nan, y: 1.0},
  child: Container(width: 20.0, height: 20.0)));
''',
        data: <String, Object?>{'nan': double.nan},
      );

      final alignTopLeft = tester.getTopLeft(find.byType(RestageAlign));
      final childTopLeft = tester.getTopLeft(find.byType(Container));
      // Scaling around bottom-center moves the transformed top-left left by
      // half the child's width and up by its full height.
      expect(childTopLeft.dx, alignTopLeft.dx + 130.0);
      expect(childTopLeft.dy, alignTopLeft.dy + 120.0);
      expect(childTopLeft.dx.isFinite, isTrue);
      expect(childTopLeft.dy.isFinite, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'a directional alignment keeps its subtype when a component is repaired',
        (tester) async {
      await _pump(
        tester,
        '''
import restage.core;
widget Paywall = Align(alignment: {start: data.nan, y: 1.0},
  child: Container(width: 20.0, height: 20.0));
''',
        data: <String, Object?>{'nan': double.nan},
      );

      final align = tester.widget<Align>(find.byType(RestageAlign));
      expect(align.alignment, isA<AlignmentDirectional>());
      final alignment = align.alignment as AlignmentDirectional;
      expect(alignment.start, 0.0);
      expect(alignment.y, 1.0);
      final alignTopLeft = tester.getTopLeft(find.byType(RestageAlign));
      final childTopLeft = tester.getTopLeft(find.byType(Container));
      expect(childTopLeft.dx, alignTopLeft.dx + 140.0);
      expect(childTopLeft.dy, alignTopLeft.dy + 280.0);
      expect(childTopLeft.dx.isFinite, isTrue);
      expect(childTopLeft.dy.isFinite, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a legal directional alignment passes through untouched',
        (tester) async {
      await _pump(
        tester,
        '''
import restage.core;
widget Paywall = Align(alignment: {start: -1.0, y: -1.0},
  child: Container(width: 20.0, height: 20.0));
''',
      );

      final align = tester.widget<Align>(find.byType(RestageAlign));
      expect(align.alignment, isA<AlignmentDirectional>());
      final alignment = align.alignment as AlignmentDirectional;
      expect(alignment.start, -1.0);
      expect(alignment.y, -1.0);
      expect(
        tester.getTopLeft(find.byType(Container)),
        tester.getTopLeft(find.byType(RestageAlign)),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a legal alignment passes through at any finite magnitude',
        (tester) async {
      await _pump(
        tester,
        '''
import restage.core;
widget Paywall = Align(alignment: {x: 4.0, y: -3.0},
  child: Container(width: 20.0, height: 20.0));
''',
      );

      final alignTopLeft = tester.getTopLeft(find.byType(RestageAlign));
      final childTopLeft = tester.getTopLeft(find.byType(Container));
      // Align applies each component to half the remaining space:
      // ((component + 1) / 2) * (300 - 20).
      expect(childTopLeft.dx, alignTopLeft.dx + 700.0);
      expect(childTopLeft.dy, alignTopLeft.dy - 280.0);
      expect(tester.takeException(), isNull);
    });
  });

  group('a layout factor is repaired before it can reach layout', () {
    testWidgets('a NaN width factor is dropped rather than zeroed',
        (tester) async {
      await _pump(
        tester,
        _inUnboundedWidth(
          'Align(widthFactor: data.nan, '
          'child: SizedBox(width: 20.0, height: 20.0))',
        ),
        data: <String, Object?>{'nan': double.nan},
      );

      final size = tester.getSize(find.byType(RestageAlign));
      expect(size.width.isFinite, isTrue);
      expect(size.width, 20.0);
      expect(size.width, isNot(0.0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('an infinite height factor is dropped rather than zeroed',
        (tester) async {
      await _pump(
        tester,
        _inUnboundedHeight(
          'Align(heightFactor: data.inf, '
          'child: SizedBox(width: 20.0, height: 20.0))',
        ),
        data: <String, Object?>{'inf': double.infinity},
      );

      final size = tester.getSize(find.byType(RestageAlign));
      expect(size.height.isFinite, isTrue);
      expect(size.height, 20.0);
      expect(size.height, isNot(0.0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a negative factor is dropped rather than floored',
        (tester) async {
      await _pump(
        tester,
        _inUnboundedWidth(
          'Align(widthFactor: -2.0, '
          'child: SizedBox(width: 20.0, height: 20.0))',
        ),
      );

      final align = tester.widget<Align>(find.byType(RestageAlign));
      expect(align.widthFactor, isNull);
      final size = tester.getSize(find.byType(RestageAlign));
      // Null restores natural sizing; zero would collapse the child extent.
      expect(size.width.isFinite, isTrue);
      expect(size.width, 20.0);
      expect(size.width, isNot(0.0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Center is repaired by the same arm', (tester) async {
      await _pump(
        tester,
        _inUnboundedWidth(
          'Center(widthFactor: data.nan, '
          'child: SizedBox(width: 20.0, height: 20.0))',
        ),
        data: <String, Object?>{'nan': double.nan},
      );

      final center = find.descendant(
        of: find.byType(RemoteWidget),
        matching: find.byType(RestageCenter),
      );
      expect(center, findsOneWidget);
      final size = tester.getSize(center);
      expect(size.width.isFinite, isTrue);
      expect(size.width, 20.0);
      expect(size.width, isNot(0.0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('FractionallySizedBox is repaired by the same arm',
        (tester) async {
      await _pump(
        tester,
        '''
import restage.core;
widget Paywall = FractionallySizedBox(widthFactor: data.nan,
  child: SizedBox(width: 20.0, height: 20.0));
''',
        data: <String, Object?>{'nan': double.nan},
      );

      final child = find.descendant(
        of: find.byType(RestageFractionallySizedBox),
        matching: find.byType(SizedBox),
      );
      expect(child, findsOneWidget);
      final render = tester.renderObject<RenderBox>(child);
      // This widget turns the factor into a tight child constraint, making a
      // non-finite factor the sharpest layout case in this class.
      expect(render.constraints.minWidth.isFinite, isTrue);
      expect(render.constraints.maxWidth.isFinite, isTrue);
      expect(render.size.width.isFinite, isTrue);
      expect(render.size.width, _kViewport);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a legal factor is honoured exactly', (tester) async {
      await _pump(
        tester,
        _inUnboundedWidth(
          'Align(widthFactor: 2.0, '
          'child: SizedBox(width: 20.0, height: 20.0))',
        ),
      );

      expect(tester.getSize(find.byType(RestageAlign)).width, 40.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a large but legal factor is not truncated', (tester) async {
      const factor = 1e5;
      await _pump(
        tester,
        _borderInUnboundedAxis(
          'Align(widthFactor: $factor, '
          'child: SizedBox(width: 20.0, height: 20.0))',
        ),
      );

      expect(tester.getSize(find.byType(RestageAlign)).width, 20.0 * factor);
      expect(tester.takeException(), isNull);
    });
  });

  group('a border side width is repaired before it can reach layout', () {
    // A border side width is validated only by a debug-only constructor
    // assert. An invalid width throws during build in debug, so the decorated
    // box never renders; in release it reaches layout unchecked. The input
    // repair must make the width legal for both modes.
    testWidgets('a NaN Container border contributes no decoration padding',
        (tester) async {
      await _pump(
        tester,
        _borderInUnboundedAxis(
          'Container(border: [{width: data.nan}, {width: 0.0}, '
          '{width: 0.0}, {width: 0.0}], '
          'child: SizedBox(width: 10.0, height: 10.0))',
        ),
        data: <String, Object?>{'nan': double.nan},
      );

      expect(find.byType(Padding), findsOneWidget);
      final render = tester.renderObject<RenderPadding>(find.byType(Padding));
      expect(render.padding.horizontal, 0.0);
      expect(render.padding.horizontal.isFinite, isTrue);
      expect(tester.getSize(find.byType(Padding)).width, 10.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'a NaN AnimatedContainer border contributes no decoration padding',
        (tester) async {
      await _pump(
        tester,
        _borderInUnboundedAxis(
          'AnimatedContainer(duration: 100, '
          'border: [{width: data.nan}, {width: 0.0}, '
          '{width: 0.0}, {width: 0.0}], '
          'child: SizedBox(width: 10.0, height: 10.0))',
        ),
        data: <String, Object?>{'nan': double.nan},
      );

      expect(find.byType(Padding), findsOneWidget);
      final render = tester.renderObject<RenderPadding>(find.byType(Padding));
      expect(render.padding.horizontal, 0.0);
      expect(render.padding.horizontal.isFinite, isTrue);
      expect(tester.getSize(find.byType(Padding)).width, 10.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a negative border side width floors at zero', (tester) async {
      await _pump(
        tester,
        _borderInUnboundedAxis(
          'Container(border: [{width: -40.0}, {width: 0.0}, '
          '{width: 0.0}, {width: 0.0}], '
          'child: SizedBox(width: 10.0, height: 10.0))',
        ),
      );

      expect(find.byType(Padding), findsOneWidget);
      final render = tester.renderObject<RenderPadding>(find.byType(Padding));
      expect(render.padding.horizontal, 0.0);
      expect(tester.getSize(find.byType(Padding)).width, 10.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a large but legal border side width is not truncated',
        (tester) async {
      const width = 2e6;
      await _pump(
        tester,
        _borderInUnboundedAxis(
          'Container(border: [{width: $width}, {width: 0.0}, '
          '{width: 0.0}, {width: 0.0}], '
          'child: SizedBox(width: 10.0, height: 10.0))',
        ),
      );

      final render = tester.renderObject<RenderPadding>(find.byType(Padding));
      expect(render.padding.horizontal, width);
      expect(tester.getSize(find.byType(Padding)).width, width + 10.0);
      expect(tester.takeException(), isNull);
    });
  });

  group('a raw width or height is repaired before it can reach layout', () {
    testWidgets('a NaN Container width is dropped instead of zeroed',
        (tester) async {
      await _pump(
        tester,
        _inUnboundedWidth(
          'Container(width: data.nan, '
          'child: SizedBox(width: 40.0, height: 20.0))',
        ),
        data: <String, Object?>{'nan': double.nan},
      );

      final size = tester.getSize(find.byType(Container));
      expect(size.width.isFinite, isTrue);
      expect(size.width, 40.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a NaN AnimatedContainer width is dropped instead of zeroed',
        (tester) async {
      await _pump(
        tester,
        _inUnboundedWidth(
          'AnimatedContainer(duration: 100, width: data.nan, '
          'child: SizedBox(width: 40.0, height: 20.0))',
        ),
        data: <String, Object?>{'nan': double.nan},
      );

      final size = tester.getSize(find.byType(AnimatedContainer));
      expect(size.width.isFinite, isTrue);
      expect(size.width, 40.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a NaN Container height is dropped instead of zeroed',
        (tester) async {
      await _pump(
        tester,
        _inUnboundedHeight(
          'Container(height: data.nan, '
          'child: SizedBox(width: 40.0, height: 20.0))',
        ),
        data: <String, Object?>{'nan': double.nan},
      );

      final size = tester.getSize(find.byType(Container));
      expect(size.height.isFinite, isTrue);
      expect(size.height, 20.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a NaN AnimatedContainer height is dropped instead of zeroed',
        (tester) async {
      await _pump(
        tester,
        _inUnboundedHeight(
          'AnimatedContainer(duration: 100, height: data.nan, '
          'child: SizedBox(width: 40.0, height: 20.0))',
        ),
        data: <String, Object?>{'nan': double.nan},
      );

      final size = tester.getSize(find.byType(AnimatedContainer));
      expect(size.height.isFinite, isTrue);
      expect(size.height, 20.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a negative width floors at zero', (tester) async {
      await _pump(
        tester,
        _inUnboundedWidth(
          'Container(width: -40.0, '
          'child: SizedBox(width: 40.0, height: 20.0))',
        ),
      );

      expect(tester.getSize(find.byType(Container)).width, 0.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a large but legal width is preserved exactly', (tester) async {
      const width = 2e6;
      await _pump(
        tester,
        _borderInUnboundedAxis(
          'Container(width: $width, '
          'child: SizedBox(width: 40.0, height: 20.0))',
        ),
      );

      expect(tester.getSize(find.byType(Container)).width, width);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a legal width passes through untouched', (tester) async {
      await _pump(
        tester,
        _inUnboundedWidth(
          'Container(width: 72.0, '
          'child: SizedBox(width: 40.0, height: 20.0))',
        ),
      );

      expect(tester.getSize(find.byType(Container)).width, 72.0);
      expect(tester.takeException(), isNull);
    });
  });

  group('a raw constraint scalar is repaired before it can reach layout', () {
    testWidgets('a NaN SizedBox width is dropped rather than zeroed',
        (tester) async {
      await _pump(
        tester,
        _inUnboundedWidth(
          'SizedBox(width: data.nan, '
          'child: Container(width: 40.0, height: 20.0))',
        ),
        data: <String, Object?>{'nan': double.nan},
      );

      final sizedBox = find.descendant(
        of: find.byType(RemoteWidget),
        matching: find.byType(SizedBox),
      );
      final size = tester.getSize(sizedBox);
      // SizedBox's constraint helper performs no clamping, so an unrepaired
      // value reaches layout untouched instead of yielding this natural width.
      expect(size.width.isFinite, isTrue);
      expect(size.width, 40.0);
      expect(size.width, isNot(0.0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a NaN Positioned width is dropped', (tester) async {
      await _pump(
        tester,
        '''
import restage.core;
widget Paywall = Stack(children: [
  Positioned(left: 0.0, top: 0.0, width: data.nan,
    child: Container(width: 40.0, height: 20.0))
]);
''',
        data: <String, Object?>{'nan': double.nan},
      );

      final child = find.descendant(
        of: find.byType(Positioned),
        matching: find.byType(Container),
      );
      final size = tester.getSize(child);
      final topLeft = tester.getTopLeft(child);
      expect(size.width.isFinite, isTrue);
      expect(size.height.isFinite, isTrue);
      expect(topLeft.dx.isFinite, isTrue);
      expect(topLeft.dy.isFinite, isTrue);
      expect(tester.takeException(), isNull);
    });

    // Use an injected asset bundle to keep the image render object present.
    // A network error would replace it with a debug error placeholder.
    testWidgets('a NaN ImageAsset width is dropped', (tester) async {
      await _pump(
        tester,
        _inUnboundedWidth('ImageAsset(name: "pixel.png", width: data.nan)'),
        data: <String, Object?>{'nan': double.nan},
        bundle: _SinglePixelAssetBundle(),
      );
      await tester.pumpAndSettle();

      final size = tester.getSize(find.byType(RestageImage));
      // Finiteness is the discriminating property here: an unrepaired value
      // resolves to an infinite width on this unbounded axis.
      expect(size.width.isFinite, isTrue);
      expect(size.height.isFinite, isTrue);
      // The binding loads the asset but does not decode it, so the repaired
      // slot leaves the image at its zero natural extent. Unrepaired, the value
      // reaches a tightening clamp that maps it to the unbounded maximum.
      expect(size.width, 0.0);
      expect(size.height, 0.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a NaN IntrinsicWidth step is dropped', (tester) async {
      await _pump(
        tester,
        _inUnboundedWidth(
          'IntrinsicWidth(stepWidth: data.nan, '
          'child: Container(width: 40.0, height: 20.0))',
        ),
        data: <String, Object?>{'nan': double.nan},
      );

      final size = tester.getSize(find.byType(RestageIntrinsicWidth));
      // The step divides the intrinsic width before the result is rounded, so
      // a non-finite value throws; zeroing it would also divide by zero.
      expect(size.width.isFinite, isTrue);
      expect(size.width, 40.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a zero IntrinsicWidth step is dropped', (tester) async {
      await _pump(
        tester,
        _inUnboundedWidth(
          'IntrinsicWidth(stepWidth: 0.0, '
          'child: Container(width: 40.0, height: 20.0))',
        ),
      );

      // Zero needs no repair here: the widget itself treats a zero step as
      // unset before building its render object, so the step is never used as
      // a divisor. This case pins that, so the decoder is not later "hardened"
      // against a value the widget already handles.
      final size = tester.getSize(find.byType(RestageIntrinsicWidth));
      expect(size.width.isFinite, isTrue);
      expect(size.width, 40.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a negative IntrinsicWidth step is dropped', (tester) async {
      await _pump(
        tester,
        _inUnboundedWidth(
          'IntrinsicWidth(stepWidth: -1.0, '
          'child: Container(width: 40.0, height: 20.0))',
        ),
      );

      final size = tester.getSize(find.byType(RestageIntrinsicWidth));
      expect(size, const Size(40.0, 20.0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a legal SizedBox width is honoured exactly', (tester) async {
      await _pump(
        tester,
        _inUnboundedWidth('SizedBox(width: 72.0, height: 20.0)'),
      );

      final sizedBox = find.descendant(
        of: find.byType(RemoteWidget),
        matching: find.byType(SizedBox),
      );
      expect(tester.getSize(sizedBox).width, 72.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a large but legal SizedBox width is not truncated',
        (tester) async {
      const width = 2e6;
      await _pump(
        tester,
        _borderInUnboundedAxis('SizedBox(width: $width, height: 20.0)'),
      );

      final sizedBox = find.descendant(
        of: find.byType(RemoteWidget),
        matching: find.byType(SizedBox),
      );
      expect(tester.getSize(sizedBox).width, width);
      expect(tester.takeException(), isNull);
    });
  });

  group('a text metric is repaired before it can reach layout', () {
    testWidgets('a NaN Text font size is dropped', (tester) async {
      await _pump(
        tester,
        _inUnboundedWidth('Text(text: "repair", fontSize: data.nan)'),
        data: <String, Object?>{'nan': double.nan},
      );

      final size = tester.getSize(find.byType(Text));
      expect(size.width.isFinite, isTrue);
      expect(size.height.isFinite, isTrue);
      expect(size.width, greaterThan(0.0));
      expect(size.height, greaterThan(0.0));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'a hostile text metric repairs the same through either wire shape',
        (tester) async {
      await _pump(
        tester,
        // The decomposed slot and the nested span style reach the metric through
        // different decoder arms; both must drop a hostile value identically.
        '''
import restage.core;
widget Paywall = Row(children: [
  Text(text: "repair", letterSpacing: data.nan),
  TextRich(textSpan: {text: "repair", style: {letterSpacing: data.nan}})
]);
''',
        data: <String, Object?>{'nan': double.nan},
      );

      final texts = tester.widgetList<Text>(find.byType(Text)).toList();
      expect(texts, hasLength(2));
      final decomposedMetric = texts.first.style?.letterSpacing;
      final nestedSpan = texts.last.textSpan! as TextSpan;
      final nestedMetric = nestedSpan.style?.letterSpacing;
      expect(decomposedMetric, nestedMetric);
      expect(decomposedMetric, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a legal Text font size is honoured exactly', (tester) async {
      await _pump(
        tester,
        _inUnboundedWidth('Text(text: "repair")'),
      );
      final defaultSize = tester.getSize(find.byType(Text));

      await _pump(
        tester,
        _inUnboundedWidth('Text(text: "repair", fontSize: 48.0)'),
      );
      final authoredSize = tester.getSize(find.byType(Text));

      expect(authoredSize.width, greaterThan(defaultSize.width));
      expect(authoredSize.height, greaterThan(defaultSize.height));
      expect(tester.takeException(), isNull);
    });
  });

  group('a required layout scalar fails loudly instead of reaching layout', () {
    testWidgets('a NaN aspect ratio throws during build', (tester) async {
      await _pump(
        tester,
        '''
import restage.core;
widget Paywall = AspectRatio(aspectRatio: data.nan,
  child: Container(width: 40.0, height: 20.0));
''',
        data: <String, Object?>{'nan': double.nan},
      );

      // This case pins WHICH error is raised. Its sibling below pins what the
      // framework puts on screen afterwards; together they cover the throw and
      // its containment, which is why the same hostile source appears twice.
      expect(tester.takeException(), isA<ArgumentError>());
      expect(find.byType(RestageAspectRatio), findsNothing);
    });

    testWidgets('a failed required scalar is replaced by an error widget',
        (tester) async {
      await _pump(
        tester,
        '''
import restage.core;
widget Paywall = AspectRatio(aspectRatio: data.nan,
  child: Container(width: 40.0, height: 20.0));
''',
        data: <String, Object?>{'nan': double.nan},
      );

      // The sibling case above pins which error is raised; this one pins the
      // consequence — the framework substitutes an error widget for the failed
      // subtree, so a broken value never reaches layout. That substitution is
      // what makes throwing the safe disposition rather than the drastic one.
      expect(find.byType(ErrorWidget), findsOneWidget);
      expect(find.byType(RestageAspectRatio), findsNothing);
      expect(tester.takeException(), isA<ArgumentError>());
    });

    testWidgets('a NaN LimitedBox maximum width throws during build',
        (tester) async {
      final errors = await _collectErrors(() async {
        await _pump(
          tester,
          _inUnboundedWidth(
            'LimitedBox(maxWidth: data.nan, '
            'child: Container(width: 40.0, height: 20.0))',
          ),
          data: <String, Object?>{'nan': double.nan},
        );
      });

      // The required scalar fails during build, so the runtime's error boundary
      // substitutes a placeholder and the widget never reaches layout. A later
      // overflow from that placeholder does not change which error fired first.
      expect(errors.whereType<ArgumentError>(), isNotEmpty);
      expect(errors.first, isA<ArgumentError>());
      expect(find.byType(LimitedBox), findsNothing);
    });

    testWidgets('a legal aspect ratio renders normally', (tester) async {
      await _pump(
        tester,
        _inUnboundedHeight(
          'AspectRatio(aspectRatio: 2.0, '
          'child: Container(width: 40.0, height: 20.0))',
        ),
      );

      final size = tester.getSize(find.byType(RestageAspectRatio));
      expect(size.width.isFinite, isTrue);
      expect(size.height.isFinite, isTrue);
      expect(size.aspectRatio, 2.0);
      expect(tester.takeException(), isNull);
    });
  });
}
