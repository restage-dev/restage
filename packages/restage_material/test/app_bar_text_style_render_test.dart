import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart' as core;
import 'package:restage_material/restage_material.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart' show parseLibraryFile;
import 'package:rfw/rfw.dart' hide Switch, WidgetLibrary;

const _rootLibrary = LibraryName(['test']);
const _titleStyle = TextStyle(
  fontSize: 24,
  fontWeight: FontWeight.bold,
  color: Color(0xFF112233),
  letterSpacing: 1,
);
const _toolbarStyle = TextStyle(
  fontSize: 14,
  fontStyle: FontStyle.italic,
  color: Color(0xFF445566),
  height: 1.5,
);
const _themeTitleStyle = TextStyle(fontSize: 20, color: Colors.orange);
const _themeToolbarStyle = TextStyle(fontSize: 12, color: Colors.purple);

void main() {
  test('AppBar text styles reference the registered TextStyle', () {
    final entry = kRegistry.findByName('AppBar', WidgetLibrary.material)!;
    final button =
        kRegistry.findByName('FilledButton', WidgetLibrary.material)!;
    final textStyle =
        button.properties.singleWhere((p) => p.name == 'textStyle');
    final expectedRef =
        (textStyle.valueShape! as StructuredShape).structuredRef;
    expect(entry.sinceVersion, 12);
    for (final name in ['titleTextStyle', 'toolbarTextStyle']) {
      final property = entry.properties.singleWhere((p) => p.name == name);
      expect(property.type, PropertyType.structured);
      expect(property.required, isFalse);
      expect(
        (property.valueShape! as StructuredShape).structuredRef,
        expectedRef,
      );
    }
  });

  Future<AppBar> pumpBar(WidgetTester tester, String styles) async {
    final runtime = Runtime()
      ..update(
          const LibraryName(['restage', 'core']), core.buildCoreWidgetLibrary())
      ..update(const LibraryName(['restage', 'material']),
          buildMaterialWidgetLibrary())
      ..update(_rootLibrary, parseLibraryFile('''
import restage.core;
import restage.material;
widget Screen = Scaffold(
  appBar: AppBar(
    title: Text(text: "Welcome"),
    leading: Text(text: "Back"),
    actions: [Text(text: "Done")],
    $styles
  ),
);
'''));
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(
        appBarTheme: const AppBarThemeData(
          titleTextStyle: _themeTitleStyle,
          toolbarTextStyle: _themeToolbarStyle,
        ),
      ),
      home: RemoteWidget(
        runtime: runtime,
        data: DynamicContent(),
        widget: const FullyQualifiedWidgetName(_rootLibrary, 'Screen'),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    return tester.widget<AppBar>(find.byType(AppBar));
  }

  TextStyle renderedStyle(WidgetTester tester, String text) => tester
      .widget<RichText>(find.descendant(
        of: find.text(text),
        matching: find.byType(RichText),
      ))
      .text
      .style!;

  void expectRenderedStyles(
    WidgetTester tester, {
    TextStyle titleStyle = _titleStyle,
    TextStyle toolbarStyle = _toolbarStyle,
  }) {
    final title = renderedStyle(tester, 'Welcome');
    expect(title.fontSize, titleStyle.fontSize);
    expect(title.fontWeight, titleStyle.fontWeight);
    expect(title.color, titleStyle.color);
    expect(title.letterSpacing, titleStyle.letterSpacing);
    for (final text in ['Back', 'Done']) {
      final toolbar = renderedStyle(tester, text);
      expect(toolbar.fontSize, toolbarStyle.fontSize);
      expect(toolbar.fontStyle, toolbarStyle.fontStyle);
      expect(toolbar.color, toolbarStyle.color);
      expect(toolbar.height, toolbarStyle.height);
    }
  }

  testWidgets('structured styles render independently in title and toolbar',
      (tester) async {
    final appBar = await pumpBar(tester, '''
      titleTextStyle: {color: 0xFF112233, fontSize: 24.0, fontWeight: "w700", letterSpacing: 1.0},
      toolbarTextStyle: {color: 0xFF445566, fontSize: 14.0, fontStyle: "italic", height: 1.5},
    ''');
    expect(appBar.titleTextStyle, _titleStyle);
    expect(appBar.toolbarTextStyle, _toolbarStyle);
    expectRenderedStyles(tester);
  });

  for (final styles in ['', 'titleTextStyle: null, toolbarTextStyle: null,']) {
    testWidgets('absent styles preserve the AppBar theme: $styles',
        (tester) async {
      final appBar = await pumpBar(tester, styles);
      expect(appBar.titleTextStyle, isNull);
      expect(appBar.toolbarTextStyle, isNull);
      expectRenderedStyles(
        tester,
        titleStyle: _themeTitleStyle,
        toolbarStyle: _themeToolbarStyle,
      );
    });
  }
}
