// Icons and text field prefix icons draw from a font delivered with the
// surface when the app installs no glyph for them.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart' as core;
import 'package:restage_material/restage_material.dart';
import 'package:rfw/formats.dart' show parseLibraryFile;
import 'package:rfw/rfw.dart' hide Switch, WidgetLibrary;

const LibraryName _coreLibrary = LibraryName(<String>['restage', 'core']);
const LibraryName _materialLibrary =
    LibraryName(<String>['restage', 'material']);
const LibraryName _rootLibrary = LibraryName(<String>['restage', 'surface']);

void main() {
  setUp(core.InstalledIconTable.reset);
  tearDown(core.InstalledIconTable.reset);

  Future<void> pump(WidgetTester tester, String body) async {
    final runtime = Runtime()
      ..update(_coreLibrary, core.buildCoreWidgetLibrary())
      ..update(_materialLibrary, buildMaterialWidgetLibrary())
      ..update(
        _rootLibrary,
        parseLibraryFile('''
import restage.core;
import restage.material;
widget Screen = Scaffold(body: $body);
'''),
      );
    await tester.pumpWidget(
      MaterialApp(
        home: core.DeliveredIconFonts(
          fonts: const {
            'MaterialIcons': core.LoadedIconFont(
              loadedFamily: 'restage-icons-test',
              codePoints: {0xe87d},
            ),
          },
          child: RemoteWidget(
            runtime: runtime,
            data: DynamicContent(),
            widget: const FullyQualifiedWidgetName(_rootLibrary, 'Screen'),
            onEvent: (_, __) {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('an Icon draws a delivered glyph', (tester) async {
    await pump(tester, 'Icon(iconCodepoint: 59517)');

    expect(tester.takeException(), isNull);
    final glyph = tester.widget<core.RestageDeliveredIcon>(
      find.byType(core.RestageDeliveredIcon),
    );
    expect(glyph.codePoint, 0xe87d);
    expect(glyph.fontFamily, 'restage-icons-test');
  });

  testWidgets('a text field prefix icon draws a delivered glyph', (
    tester,
  ) async {
    await pump(tester, 'TextField(prefixIconCodepoint: 59517)');

    expect(tester.takeException(), isNull);
    final decoration =
        tester.widget<TextField>(find.byType(TextField)).decoration!;
    expect(decoration.prefixIcon, isA<core.RestageDeliveredIcon>());
  });
}
