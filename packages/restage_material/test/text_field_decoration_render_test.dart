// The TextField entry renders its decoration, keyboard and input action
// properties through the generated factory.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart' as core;
import 'package:restage_material/restage_material.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart' show parseLibraryFile;
import 'package:rfw/rfw.dart' hide Switch, WidgetLibrary;

const LibraryName _coreLibrary = LibraryName(<String>['restage', 'core']);
const LibraryName _materialLibrary =
    LibraryName(<String>['restage', 'material']);
const LibraryName _rootLibrary = LibraryName(<String>['restage', 'surface']);

void main() {
  setUp(core.InstalledIconTable.reset);
  tearDown(core.InstalledIconTable.reset);

  Future<void> pumpField(WidgetTester tester, String args) async {
    final runtime = Runtime()
      ..update(_coreLibrary, core.buildCoreWidgetLibrary())
      ..update(_materialLibrary, buildMaterialWidgetLibrary())
      ..update(
        _rootLibrary,
        parseLibraryFile('''
import restage.core;
import restage.material;
widget Screen = Scaffold(body: TextField($args));
'''),
      );
    await tester.pumpWidget(
      MaterialApp(
        home: RemoteWidget(
          runtime: runtime,
          data: DynamicContent(),
          widget: const FullyQualifiedWidgetName(_rootLibrary, 'Screen'),
          onEvent: (_, __) {},
        ),
      ),
    );
    await tester.pump();
  }

  InputDecoration decorationOf(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).decoration!;

  test('the catalog entry carries the new properties at version 8', () {
    final entry = kRegistry.findByName('TextField', WidgetLibrary.material)!;
    expect(entry.sinceVersion, 8);
    final names = entry.properties.map((p) => p.name).toSet();
    expect(
      names,
      containsAll(<String>[
        'hintText',
        'labelText',
        'helperText',
        'prefixIconCodepoint',
        'prefixIconFontFamily',
        'prefixIconMatchTextDirection',
        'border',
        'keyboardType',
        'textInputAction',
      ]),
    );
    final keyboard = entry.properties.firstWhere(
      (p) => p.name == 'keyboardType',
    );
    expect(
      keyboard.constraints.allowedValues!.toSet(),
      core.RestageDecoders.supportedTextInputTypeNames,
    );
  });

  testWidgets('hint, label and helper text render', (tester) async {
    await pumpField(
      tester,
      'hintText: "Anything else?", labelText: "Feedback", '
      'helperText: "Optional"',
    );
    expect(find.text('Anything else?'), findsOneWidget);
    expect(find.text('Feedback'), findsOneWidget);
    expect(find.text('Optional'), findsOneWidget);
  });

  testWidgets('keyboard type and input action reach the field', (tester) async {
    await pumpField(
      tester,
      'keyboardType: "emailAddress", textInputAction: "done"',
    );
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.keyboardType, TextInputType.emailAddress);
    expect(field.textInputAction, TextInputAction.done);
  });

  testWidgets('an unknown keyboard type keeps the default', (tester) async {
    await pumpField(tester, 'keyboardType: "datetime-local"');
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.keyboardType, TextInputType.text);
  });

  testWidgets('each border kind maps to its Flutter border', (tester) async {
    await pumpField(tester, 'border: "none"');
    expect(decorationOf(tester).border, InputBorder.none);

    await pumpField(tester, 'border: "underline"');
    expect(decorationOf(tester).border, isA<UnderlineInputBorder>());

    await pumpField(tester, 'border: "outline"');
    expect(decorationOf(tester).border, isA<OutlineInputBorder>());

    await pumpField(tester, '');
    expect(decorationOf(tester).border, isNull);
  });

  testWidgets('the prefix icon resolves through the installed table',
      (tester) async {
    core.InstalledIconTable.install(
      core.RestageIconTable.fromFamilies(
        families: {
          core.RestageIconTable.materialIconsFamily: {
            Icons.search.codePoint: Icons.search,
          },
        },
      ),
    );
    await pumpField(tester, 'prefixIconCodepoint: ${Icons.search.codePoint}');
    expect(find.byIcon(Icons.search), findsOneWidget);
  });

  testWidgets('no prefix codepoint means no prefix icon', (tester) async {
    await pumpField(tester, 'hintText: "x"');
    expect(decorationOf(tester).prefixIcon, isNull);
  });
}
