// A delivered widget matches Flutter's own widget given the same arguments:
// same size, same pixels.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart' as core;
import 'package:restage_material/restage_material.dart';
import 'package:rfw/formats.dart' show parseLibraryFile;
import 'package:rfw/rfw.dart' hide WidgetLibrary;

const _root = LibraryName(['test']);
const _boundary = ValueKey('boundary');

void _tap() {}

const _icon = Icon(Icons.commute_sharp);

final _rows = <(String, Widget, {bool bare})>[
  (
    'ElevatedButton(onPressed: event "tap" {}, child: Text(text: "Go"))',
    const ElevatedButton(onPressed: _tap, child: Text('Go')),
    bare: false,
  ),
  (
    'FilledButton(onPressed: event "tap" {}, child: Text(text: "Go"))',
    const FilledButton(onPressed: _tap, child: Text('Go')),
    bare: false,
  ),
  (
    'FilledButtonTonal(onPressed: event "tap" {}, child: Text(text: "Go"))',
    const FilledButton.tonal(onPressed: _tap, child: Text('Go')),
    bare: false,
  ),
  (
    'TextButton(onPressed: event "tap" {}, child: Text(text: "Go"))',
    const TextButton(onPressed: _tap, child: Text('Go')),
    bare: false,
  ),
  (
    'OutlinedButton(onPressed: event "tap" {}, child: Text(text: "Go"))',
    const OutlinedButton(onPressed: _tap, child: Text('Go')),
    bare: false,
  ),
  (
    'IconButton(onPressed: event "tap" {}, '
        'icon: Icon(iconCodepoint: 0xe87d))',
    const IconButton(onPressed: _tap, icon: _icon),
    bare: false,
  ),
  (
    'Card(child: SizedBox(width: 40.0, height: 30.0))',
    const Card(child: SizedBox(width: 40, height: 30)),
    bare: false,
  ),
  (
    'Divider()',
    const Divider(),
    bare: false,
  ),
  (
    'CircularProgressIndicator(value: 0.4)',
    const CircularProgressIndicator(value: 0.4),
    bare: false,
  ),
  // A non-inheriting style takes nothing from the ambient text style.
  (
    'DefaultTextStyle(fontSize: 30.0, '
        'child: Text(text: "Go", inherit: false))',
    const DefaultTextStyle(
      style: TextStyle(fontSize: 30),
      child: Text('Go', style: TextStyle(inherit: false)),
    ),
    bare: false,
  ),
  // The widget's own overflow reaches a non-inheriting Text.
  (
    'DefaultTextStyle(overflow: "ellipsis", softWrap: false, child: SizedBox('
        'width: 40.0, child: Text(text: "Overflowing", inherit: false)))',
    const DefaultTextStyle(
      style: TextStyle(),
      overflow: TextOverflow.ellipsis,
      softWrap: false,
      child: SizedBox(
        width: 40,
        child: Text('Overflowing', style: TextStyle(inherit: false)),
      ),
    ),
    bare: false,
  ),
  // No Directionality above: a directional default would not resolve.
  (
    'TransformRotate(angle: 0.5, child: SizedBox(width: 30.0, height: 10.0, '
        'child: ColoredBox(color: 0xFF2040C0)))',
    Transform.rotate(
      angle: 0.5,
      child: const SizedBox(
        width: 30,
        height: 10,
        child: ColoredBox(color: Color(0xFF2040C0)),
      ),
    ),
    bare: true,
  ),
];

// Themed away from the M3 defaults, so a literal stand-in shows.
final _theme = ThemeData(
  cardTheme: const CardThemeData(elevation: 6),
  dividerTheme: const DividerThemeData(space: 30, thickness: 4),
  iconButtonTheme:
      IconButtonThemeData(style: IconButton.styleFrom(iconSize: 36)),
  progressIndicatorTheme: const ProgressIndicatorThemeData(strokeWidth: 9),
  elevatedButtonTheme:
      ElevatedButtonThemeData(style: ElevatedButton.styleFrom(elevation: 5)),
);

Widget _delivered(String source) {
  final runtime = Runtime()
    ..update(
        const LibraryName(['restage', 'core']), core.buildCoreWidgetLibrary())
    ..update(const LibraryName(['restage', 'material']),
        buildMaterialWidgetLibrary())
    ..update(_root, parseLibraryFile('''
import restage.core;
import restage.material;
widget Screen = $source;
'''));
  addTearDown(runtime.dispose);
  return RemoteWidget(
    runtime: runtime,
    data: DynamicContent(),
    widget: const FullyQualifiedWidgetName(_root, 'Screen'),
  );
}

Future<(Size, ui.Image)> _render(
    WidgetTester tester, Widget widget, bool bare) async {
  final framed = Center(
    child: RepaintBoundary(key: _boundary, child: widget),
  );
  await tester.pumpWidget(
    bare
        ? framed
        : MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: _theme,
            home: Scaffold(body: framed),
          ),
  );
  final size = tester.getSize(find.byKey(_boundary));
  final image = await tester.runAsync(
    () => captureImage(find.byKey(_boundary).evaluate().single),
  );
  return (size, image!);
}

void main() {
  setUp(() => core.InstalledIconTable.install(
        const core.RestageIconTable.fromFamilies(families: {
          core.RestageIconTable.materialIconsFamily: {
            0xe87d: Icons.commute_sharp,
          },
        }),
      ));
  tearDown(core.InstalledIconTable.reset);
  for (final (source, native, :bare) in _rows) {
    testWidgets('matches Flutter: $source', (tester) async {
      final (nativeSize, nativeImage) = await _render(tester, native, bare);
      await tester.pumpWidget(const SizedBox());
      final (size, _) = await _render(tester, _delivered(source), bare);
      expect(size, nativeSize);
      await expectLater(
        find.byKey(_boundary),
        matchesReferenceImage(nativeImage),
      );
    });
  }
}
