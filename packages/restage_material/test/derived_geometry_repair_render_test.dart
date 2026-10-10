// End-to-end proofs for structured geometry repairs in material factories.
//
// The assertions target resolved styles and laid-out sizes, because that is
// where a decoded value becomes observable geometry.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart' as core;
import 'package:restage_material/restage_material.dart';
import 'package:rfw/formats.dart' show parseLibraryFile;
import 'package:rfw/rfw.dart' hide Switch, WidgetLibrary;

const LibraryName _coreLibrary = LibraryName(<String>['restage', 'core']);
const LibraryName _materialLibrary =
    LibraryName(<String>['restage', 'material']);
const LibraryName _rootLibrary = LibraryName(<String>['restage', 'paywall']);

/// The bounded viewport these cases lay out against.
const double _kViewport = 300;

/// The one icon the Icon cases name, installed the way an app installs the
/// icons its surfaces render.
const core.RestageIconTable _icons = core.RestageIconTable.fromFamilies(
  families: <String, Map<int, IconData>>{
    core.RestageIconTable.materialIconsFamily: <int, IconData>{
      0xe87d: Icons.commute_sharp,
    },
  },
);

Future<void> _pump(
  WidgetTester tester,
  String paywallSource, {
  Map<String, Object?>? data,
}) async {
  final runtime = Runtime()
    ..update(_coreLibrary, core.buildCoreWidgetLibrary())
    ..update(_materialLibrary, buildMaterialWidgetLibrary())
    ..update(_rootLibrary, parseLibraryFile(paywallSource));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: _kViewport,
            height: _kViewport,
            child: RemoteWidget(
              runtime: runtime,
              data: DynamicContent(data ?? <String, Object?>{}),
              widget: const FullyQualifiedWidgetName(
                _rootLibrary,
                'Paywall',
              ),
              onEvent: (_, __) {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

String _boundedButton(String arguments) => '''
import restage.core;
import restage.material;
widget Paywall = Align(child: ElevatedButton($arguments,
  child: SizedBox(width: 10.0, height: 10.0)));
''';

String _unboundedWidth(String widget) => '''
import restage.core;
import restage.material;
widget Paywall = SingleChildScrollView(scrollDirection: "horizontal",
  child: Align(alignment: "topStart", child: $widget));
''';

String _unboundedHeight(String widget) => '''
import restage.core;
import restage.material;
widget Paywall = SingleChildScrollView(
  child: Column(children: [$widget]));
''';

String _unboundedWidthButton(String arguments) => _unboundedWidth(
      'ElevatedButton($arguments, '
      'child: SizedBox(width: 10.0, height: 10.0))',
    );

RoundedRectangleBorder _resolvedRoundedShape(WidgetTester tester) {
  final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
  final shape = button.style?.shape?.resolve(<WidgetState>{});
  expect(shape, isA<RoundedRectangleBorder>());
  return shape! as RoundedRectangleBorder;
}

void main() {
  group('a size is repaired before it can reach layout', () {
    testWidgets('a NaN minimum width drops the whole minimum size',
        (tester) async {
      await _pump(
        tester,
        _boundedButton(
          'minimumSize: {width: data.nan, height: 100.0}',
        ),
        data: <String, Object?>{'nan': double.nan},
      );

      final size = tester.getSize(find.byType(ElevatedButton));
      // The button uses its own default minimum instead of filling the wide
      // parent or retaining the other component of an unusable Size.
      expect(size.width.isFinite, isTrue);
      expect(size.height.isFinite, isTrue);
      expect(size.width, lessThan(_kViewport));
      expect(size.height, lessThan(100.0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a NaN fixed width drops the whole fixed size', (tester) async {
      await _pump(
        tester,
        _boundedButton(
          'fixedSize: {width: data.nan, height: 100.0}',
        ),
        data: <String, Object?>{'nan': double.nan},
      );

      final size = tester.getSize(find.byType(ElevatedButton));
      // Natural button sizing survives; the unusable fixed width never becomes
      // a tight infinite constraint that expands to the parent.
      expect(size.width.isFinite, isTrue);
      expect(size.height.isFinite, isTrue);
      expect(size.width, lessThan(_kViewport));
      expect(size.height, lessThan(100.0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a negative minimum width floors without losing its height',
        (tester) async {
      await _pump(
        tester,
        _boundedButton(
          'minimumSize: {width: -40.0, height: 80.0}',
        ),
      );

      final size = tester.getSize(find.byType(ElevatedButton));
      expect(size.width.isFinite, isTrue);
      expect(size.height, 80.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a large but legal minimum size is not truncated',
        (tester) async {
      const width = 2e6;
      await _pump(
        tester,
        _unboundedWidthButton(
          'minimumSize: {width: $width, height: 80.0}',
        ),
      );

      final size = tester.getSize(find.byType(ElevatedButton));
      expect(size.width, width);
      expect(size.height, 80.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a legal size passes through untouched', (tester) async {
      await _pump(
        tester,
        _boundedButton(
          'minimumSize: {width: 120.0, height: 80.0}',
        ),
      );

      expect(
        tester.getSize(find.byType(ElevatedButton)),
        const Size(120.0, 80.0),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('a raw constraint scalar is repaired before it can reach layout', () {
    setUp(() => core.InstalledIconTable.install(_icons));
    tearDown(core.InstalledIconTable.reset);

    testWidgets('a NaN Icon size is dropped', (tester) async {
      await _pump(
        tester,
        _unboundedWidth('Icon(iconCodepoint: 0xe87d, size: data.nan)'),
        data: <String, Object?>{'nan': double.nan},
      );

      final size = tester.getSize(find.byType(Icon));
      // The icon falls back to its ambient theme size. Unrepaired, the value
      // reaches a tight constraint helper that performs no clamping.
      expect(size.width.isFinite, isTrue);
      expect(size.height.isFinite, isTrue);
      expect(size.width, greaterThan(0.0));
      expect(size.height, greaterThan(0.0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a legal Icon size is honoured exactly', (tester) async {
      await _pump(
        tester,
        _unboundedWidth('Icon(iconCodepoint: 0xe87d, size: 48.0)'),
      );

      expect(tester.getSize(find.byType(Icon)), const Size(48.0, 48.0));
      expect(tester.takeException(), isNull);
    });
  });

  group('a shape border side width is repaired before it can reach layout', () {
    // A border side width is validated only by a debug-only constructor
    // assert. An invalid width throws during build in debug, so the decorated
    // box never renders; in release it reaches layout unchecked. The input
    // repair must make the width legal for both modes.
    testWidgets('a NaN shape side is zeroed without changing its subtype',
        (tester) async {
      await _pump(
        tester,
        _boundedButton(
          'shape: {type: "rounded", side: {width: data.nan}}',
        ),
        data: <String, Object?>{'nan': double.nan},
      );

      expect(find.byType(ElevatedButton), findsOneWidget);
      final shape = _resolvedRoundedShape(tester);
      expect(shape.side.width, 0.0);
      final size = tester.getSize(find.byType(ElevatedButton));
      expect(size.width.isFinite, isTrue);
      expect(size.height.isFinite, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a negative shape side width floors at zero', (tester) async {
      await _pump(
        tester,
        _boundedButton(
          'shape: {type: "rounded", side: {width: -40.0}}',
        ),
      );

      expect(find.byType(ElevatedButton), findsOneWidget);
      expect(_resolvedRoundedShape(tester).side.width, 0.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a large but legal shape side width is preserved',
        (tester) async {
      const width = 2e6;
      await _pump(
        tester,
        _boundedButton(
          'shape: {type: "rounded", side: {width: $width}}',
        ),
      );

      expect(_resolvedRoundedShape(tester).side.width, width);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a standalone button side uses the same width repair',
        (tester) async {
      await _pump(
        tester,
        _boundedButton('side: {width: data.nan}'),
        data: <String, Object?>{'nan': double.nan},
      );

      expect(find.byType(ElevatedButton), findsOneWidget);
      final button = tester.widget<ElevatedButton>(
        find.byType(ElevatedButton),
      );
      final side = button.style?.side?.resolve(<WidgetState>{});
      expect(side?.width, 0.0);
      final size = tester.getSize(find.byType(ElevatedButton));
      expect(size.width.isFinite, isTrue);
      expect(size.height.isFinite, isTrue);
      expect(tester.takeException(), isNull);
    });
  });

  group('a progress minimum height is repaired before it can reach layout', () {
    testWidgets('a NaN minimum height is dropped', (tester) async {
      await _pump(
        tester,
        _unboundedHeight('LinearProgressIndicator(minHeight: data.nan)'),
        data: <String, Object?>{'nan': double.nan},
      );

      // The value becomes a constraint minimum inside the widget, and on an
      // unbounded axis an unrepaired one clamps to the axis maximum.
      final size = tester.getSize(find.byType(LinearProgressIndicator));
      expect(size.height.isFinite, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a zero minimum height is dropped', (tester) async {
      await _pump(
        tester,
        _unboundedHeight('LinearProgressIndicator(minHeight: 0.0)'),
      );

      // The widget's own domain is strictly positive, so zero is as unusable
      // as a non-finite value and must degrade to the widget's default rather
      // than reach it.
      final size = tester.getSize(find.byType(LinearProgressIndicator));
      expect(size.height.isFinite, isTrue);
      expect(size.height, greaterThan(0.0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a legal minimum height is honoured exactly', (tester) async {
      await _pump(
        tester,
        _unboundedHeight('LinearProgressIndicator(minHeight: 12.0)'),
      );

      expect(tester.getSize(find.byType(LinearProgressIndicator)).height, 12.0);
      expect(tester.takeException(), isNull);
    });
  });

  group('a badge offset is repaired before it can reach layout', () {
    testWidgets('a NaN offset component is zeroed', (tester) async {
      await _pump(
        tester,
        '''
import restage.core;
import restage.material;
widget Paywall = Align(child: Badge(offset: {x: data.nan, y: 4.0},
  label: Text(text: "1"),
  child: SizedBox(width: 40.0, height: 40.0)));
''',
        data: <String, Object?>{'nan': double.nan},
      );

      // The offset is added to the badge's position during layout, so an
      // unrepaired component leaves the label at a non-finite location.
      final label = find.descendant(
        of: find.byType(Badge),
        matching: find.byType(Text),
      );
      final topLeft = tester.getTopLeft(label);
      expect(topLeft.dx.isFinite, isTrue);
      expect(topLeft.dy.isFinite, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a legal offset is applied as authored', (tester) async {
      await _pump(
        tester,
        '''
import restage.core;
import restage.material;
widget Paywall = Align(child: Badge(offset: {x: 0.0, y: 0.0},
  label: Text(text: "1"),
  child: SizedBox(width: 40.0, height: 40.0)));
''',
      );

      final label = find.descendant(
        of: find.byType(Badge),
        matching: find.byType(Text),
      );
      expect(tester.getTopLeft(label).dx.isFinite, isTrue);
      expect(tester.takeException(), isNull);
    });
  });
}
