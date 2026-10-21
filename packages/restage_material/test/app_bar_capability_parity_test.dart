import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart' as core;
import 'package:restage_material/restage_material.dart';
import 'package:rfw/formats.dart' show parseLibraryFile;
import 'package:rfw/rfw.dart' hide Switch;

const _rootLibrary = LibraryName(['test']);
const _flexibleColor = Color(0xFF123456);

Widget _remote(String content, {DynamicContent? data}) {
  final runtime = Runtime()
    ..update(
        const LibraryName(['restage', 'core']), core.buildCoreWidgetLibrary())
    ..update(const LibraryName(['restage', 'material']),
        buildMaterialWidgetLibrary())
    ..update(_rootLibrary, parseLibraryFile('''
import restage.core;
import restage.material;
widget Screen = $content;
'''));
  addTearDown(runtime.dispose);
  return RemoteWidget(
    runtime: runtime,
    data: data ?? DynamicContent(),
    widget: const FullyQualifiedWidgetName(_rootLibrary, 'Screen'),
  );
}

String _screen(String barArgs, {double bottomHeight = 0}) => '''
Scaffold(
  appBar: AppBar(title: Text(text: "Title"), $barArgs),
  body: Text(text: "Body"),
  appBarBottomHeight: $bottomHeight,
)
''';

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  ThemeData? theme,
}) async {
  await tester.pumpWidget(MaterialApp(
    key: UniqueKey(),
    theme: theme,
    home: home,
  ));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Color _textColor(WidgetTester tester, String text) => tester
    .widget<RichText>(find.descendant(
      of: find.text(text),
      matching: find.byType(RichText),
    ))
    .text
    .style!
    .color!;

double _paintOpacity(WidgetTester tester, String text) {
  double opacity = 1;
  RenderObject? object = tester.renderObject(find.text(text));
  while (object != null) {
    if (object is RenderOpacity) opacity *= object.opacity;
    if (object is RenderAnimatedOpacity) opacity *= object.opacity.value;
    object = object.parent;
  }
  return opacity;
}

List<({String label, bool header})> _semantics(WidgetTester tester) {
  final result = <({String label, bool header})>[];
  void visit(SemanticsNode node) {
    if (node.label.isNotEmpty) {
      result.add((
        label: node.label,
        header: node.flagsCollection.isHeader,
      ));
    }
    for (final child in node
        .debugListChildrenInOrder(DebugSemanticsDumpOrder.traversalOrder)) {
      visit(child);
    }
  }

  visit(tester.getSemantics(find.byType(Scaffold)));
  return result;
}

Color _paintedBarColor(WidgetTester tester) => tester
    .renderObject<RenderPhysicalModel>(find
        .descendant(
          of: find.byType(AppBar),
          matching: find.byType(PhysicalModel),
        )
        .first)
    .color;

void main() {
  testWidgets('flexible space fills the native app bar bounds', (tester) async {
    final native = Scaffold(
      appBar: AppBar(
        title: const Text('Title'),
        flexibleSpace: Container(
          color: _flexibleColor,
          child: const Align(
            alignment: Alignment.bottomLeft,
            child: Text('Flexible'),
          ),
        ),
      ),
      body: const Text('Body'),
    );
    final delivered = _remote(_screen('''
      flexibleSpace: Container(color: 0xFF123456,
        child: Align(alignment: {x: -1.0, y: 1.0},
          child: Text(text: "Flexible"))),
    '''));
    final coloredBox = find.byWidgetPredicate((widget) =>
        widget is ColoredBox && widget.color == _flexibleColor ||
        widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).color == _flexibleColor);

    await _pump(tester, native);
    final nativeBackground = tester.getRect(coloredBox);
    final nativeText = tester.getRect(find.text('Flexible'));
    expect(nativeBackground, tester.getRect(find.byType(AppBar)));
    expect(nativeText.bottom, nativeBackground.bottom);

    await _pump(tester, delivered);
    expect(tester.getRect(coloredBox), nativeBackground);
    expect(tester.getRect(find.text('Flexible')), nativeText);
  });

  for (final opacity in [
    (toolbar: null, bottom: null),
    (toolbar: 0.0, bottom: 1.0),
    (toolbar: 1.0, bottom: 0.0),
    (toolbar: 0.4, bottom: 0.7),
    (toolbar: 1.0, bottom: 1.0),
  ]) {
    testWidgets('toolbar and bottom opacity match Flutter at $opacity',
        (tester) async {
      final native = Scaffold(
        appBar: AppBar(
          title: const Text('Title'),
          leading: const Text('Leading'),
          actions: const [Text('Action')],
          toolbarOpacity: opacity.toolbar ?? 1,
          bottomOpacity: opacity.bottom ?? 1,
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(30),
            child: SizedBox(height: 30, child: Text('Bottom')),
          ),
        ),
        body: const Text('Body'),
      );
      final delivered = _remote(_screen('''
        leading: Text(text: "Leading"),
        actions: [Text(text: "Action")],
        ${opacity.toolbar == null ? '' : 'toolbarOpacity: ${opacity.toolbar},'}
        ${opacity.bottom == null ? '' : 'bottomOpacity: ${opacity.bottom},'}
        bottom: PreferredSize(preferredSize: 30.0,
          child: SizedBox(height: 30.0, child: Text(text: "Bottom"))),
        bottomHeight: 30.0,
      ''', bottomHeight: 30));
      final theme = ThemeData(
        appBarTheme: const AppBarThemeData(
          titleTextStyle: TextStyle(color: Colors.red),
          toolbarTextStyle: TextStyle(color: Colors.blue),
        ),
      );

      await _pump(tester, native, theme: theme);
      final colors = [
        for (final text in ['Title', 'Leading', 'Action'])
          _textColor(tester, text),
      ];
      final bottomOpacity = _paintOpacity(tester, 'Bottom');
      if (opacity.toolbar != null && opacity.toolbar! < 1) {
        expect(colors.every((color) => color.a < 1), isTrue);
      }
      if (opacity.bottom != null && opacity.bottom! < 1) {
        expect(bottomOpacity, lessThan(1));
      }

      await _pump(tester, delivered, theme: theme);
      expect([
        for (final text in ['Title', 'Leading', 'Action'])
          _textColor(tester, text),
      ], colors);
      expect(_paintOpacity(tester, 'Bottom'), bottomOpacity);
    });
  }

  for (final excludeHeader in [null, false, true]) {
    for (final defaultOrder in [null, false, true]) {
      testWidgets(
          'semantics match Flutter with header excluded $excludeHeader '
          'and default order $defaultOrder', (tester) async {
        final handle = tester.ensureSemantics();
        try {
          final native = Scaffold(
            appBar: AppBar(
              title: const Text('Title'),
              excludeHeaderSemantics: excludeHeader ?? false,
              useDefaultSemanticsOrder: defaultOrder ?? true,
              flexibleSpace: const Align(
                alignment: Alignment.topLeft,
                child: Text('Flexible'),
              ),
            ),
            body: const Text('Body'),
          );
          final delivered = _remote(_screen('''
          ${excludeHeader == null ? '' : 'excludeHeaderSemantics: $excludeHeader,'}
          ${defaultOrder == null ? '' : 'useDefaultSemanticsOrder: $defaultOrder,'}
          flexibleSpace: Align(alignment: {x: -1.0, y: -1.0},
            child: Text(text: "Flexible")),
        '''));

          await _pump(tester, native);
          final semantics = _semantics(tester);
          expect(semantics.singleWhere((node) => node.label == 'Title').header,
              !(excludeHeader ?? false));
          expect(
            semantics.map((node) => node.label),
            defaultOrder != false
                ? ['Title', 'Flexible', 'Body']
                : ['Flexible', 'Title', 'Body'],
          );

          await _pump(tester, delivered);
          expect(_semantics(tester), semantics);
        } finally {
          handle.dispose();
        }
      });
    }
  }

  for (final implyActions in [null, false, true]) {
    testWidgets('implicit end drawer action matches Flutter: $implyActions',
        (tester) async {
      final bar = _remote('''
AppBar(title: Text(text: "Title"),
  ${implyActions == null ? '' : 'automaticallyImplyActions: $implyActions,'})
''');
      final native = AppBar(
        title: const Text('Title'),
        automaticallyImplyActions: implyActions ?? true,
      );
      final results = <({int buttons, bool opened})>[];
      for (final delivered in [false, true]) {
        final scaffoldKey = GlobalKey<ScaffoldState>();
        await _pump(
          tester,
          Scaffold(
            key: scaffoldKey,
            appBar: delivered
                ? PreferredSize(
                    preferredSize: const Size.fromHeight(kToolbarHeight),
                    child: bar,
                  )
                : native,
            endDrawer: const Drawer(child: Text('Drawer content')),
          ),
        );
        final buttons = find.byType(EndDrawerButton).evaluate().length;
        if (buttons != 0) {
          await tester.tap(find.byType(EndDrawerButton));
          await tester.pumpAndSettle();
          expect(find.text('Drawer content'), findsOneWidget);
        }
        results.add((
          buttons: buttons,
          opened: scaffoldKey.currentState!.isEndDrawerOpen,
        ));
      }
      expect(results.first, (
        buttons: implyActions == false ? 0 : 1,
        opened: implyActions != false
      ));
      expect(results.last, results.first);
    });
  }

  for (final animate in [null, false, true]) {
    testWidgets('background color update matches Flutter animation: $animate',
        (tester) async {
      const start = Color(0xFFCC2200);
      const finish = Color(0xFF0055DD);
      final samples = <List<Color>>[];
      for (final delivered in [false, true]) {
        final data = DynamicContent()..update('color', start.toARGB32());
        final color = ValueNotifier<Color>(start);
        addTearDown(color.dispose);
        await _pump(
          tester,
          delivered
              ? _remote(
                  _screen('''
                    elevation: 0.0,
                    backgroundColor: data.color,
                    ${animate == null ? '' : 'animateColor: $animate,'}
                  '''),
                  data: data,
                )
              : ValueListenableBuilder<Color>(
                  valueListenable: color,
                  builder: (_, value, __) => Scaffold(
                    appBar: AppBar(
                      title: const Text('Title'),
                      elevation: 0,
                      backgroundColor: value,
                      animateColor: animate ?? false,
                    ),
                    body: const Text('Body'),
                  ),
                ),
        );
        expect(_paintedBarColor(tester), start);
        if (delivered) {
          data.update('color', finish.toARGB32());
        } else {
          color.value = finish;
        }
        await tester.pump();
        final colors = [_paintedBarColor(tester)];
        await tester.pump(const Duration(milliseconds: 75));
        colors.add(_paintedBarColor(tester));
        await tester.pumpAndSettle();
        colors.add(_paintedBarColor(tester));
        samples.add(colors);
      }
      expect(samples.last, samples.first);
      expect(samples.first.last, finish);
      if (animate == true) {
        expect(samples.first.first, start);
        expect(samples.first[1], isNot(anyOf(start, finish)));
      } else {
        expect(samples.first, everyElement(finish));
      }
    });
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final themedCenter in [null, false, true]) {
      for (final center in [null, false, true]) {
        testWidgets(
            'title placement matches $platform with theme $themedCenter '
            'and centerTitle $center', (tester) async {
          final theme = ThemeData(
            platform: platform,
            appBarTheme: AppBarThemeData(centerTitle: themedCenter),
          );
          await _pump(
            tester,
            Scaffold(
              appBar: AppBar(title: const Text('Title'), centerTitle: center),
              body: const Text('Body'),
            ),
            theme: theme,
          );
          final nativeTitle = tester.getRect(find.text('Title'));
          final centered =
              center ?? themedCenter ?? platform == TargetPlatform.iOS;
          if (centered) {
            expect(nativeTitle.center.dx,
                tester.getRect(find.byType(AppBar)).center.dx);
          } else {
            expect(nativeTitle.left, 16);
          }

          await _pump(
            tester,
            _remote(_screen(center == null ? '' : 'centerTitle: $center,')),
            theme: theme,
          );
          expect(tester.getRect(find.text('Title')), nativeTitle);
        });
      }
    }
  }
}
