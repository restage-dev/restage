import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart' as core;
import 'package:restage_material/restage_material.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart' show parseLibraryFile;
import 'package:rfw/rfw.dart' hide Switch, WidgetLibrary;

const _root = LibraryName(['test']);

Runtime _runtime(String screen) {
  final runtime = Runtime()
    ..update(
        const LibraryName(['restage', 'core']), core.buildCoreWidgetLibrary())
    ..update(const LibraryName(['restage', 'material']),
        buildMaterialWidgetLibrary())
    ..update(
        const LibraryName(['pages']),
        LocalWidgetLibrary({
          'Page': (context, source) => _Page(source.v<String>(['name'])!),
        }))
    ..update(_root, parseLibraryFile('''
import restage.core;
import restage.material;
import pages;
widget Screen = $screen;
'''));
  addTearDown(runtime.dispose);
  return runtime;
}

Widget _delivered(Runtime runtime, {DynamicContent? data}) => RemoteWidget(
      runtime: runtime,
      data: data ?? DynamicContent(),
      widget: const FullyQualifiedWidgetName(_root, 'Screen'),
    );

String _tabsSource(
        {int length = 4, int initialIndex = 1, String arguments = ''}) =>
    '''
DefaultTabController(
  length: $length,
  initialIndex: $initialIndex,
  child: Column(children: [
    TabBar(tabs: [${List.generate(length, (i) => 'Tab(text: "Tab $i")').join(',')}]),
    Expanded(child: TabBarView($arguments children: [
      ${List.generate(length, (i) => 'Page(name: "Page $i")').join(',')}
    ])),
  ]),
)
''';

Widget _nativeTabs(
        {int length = 4,
        int initialIndex = 1,
        double fraction = 1,
        Clip clip = Clip.hardEdge,
        DragStartBehavior drag = DragStartBehavior.start}) =>
    DefaultTabController(
      length: length,
      initialIndex: initialIndex,
      child: Column(children: [
        TabBar(tabs: List.generate(length, (i) => Tab(text: 'Tab $i'))),
        Expanded(
            child: TabBarView(
          viewportFraction: fraction,
          clipBehavior: clip,
          dragStartBehavior: drag,
          children: List.generate(length, (i) => _Page('Page $i')),
        )),
      ]),
    );

Future<void> _mount(WidgetTester tester, Widget screen,
    {TextDirection direction = TextDirection.ltr}) async {
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: Directionality(
    textDirection: direction,
    child: screen,
  ))));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

int _index(WidgetTester tester, [int view = 0]) => DefaultTabController.of(
      tester.element(find.byType(TabBarView).at(view)),
    ).index;

Future<List<Object>> _exercise(
    WidgetTester tester, Widget screen, TextDirection direction) async {
  await tester.pumpWidget(const SizedBox());
  await _mount(tester, screen, direction: direction);
  final result = <Object>[];
  void capture() {
    expect(tester.takeException(), isNull);
    final index = _index(tester);
    result.add((index, tester.getRect(find.text('Page $index: 0'))));
  }

  capture();
  for (final index in [2, 0]) {
    await tester.tap(find.text('Tab $index'));
    await tester.pumpAndSettle();
    capture();
  }
  await tester.drag(find.byType(TabBarView),
      Offset(direction == TextDirection.ltr ? -650 : 650, 0));
  await tester.pumpAndSettle();
  capture();
  expect(_index(tester), 1);
  await tester.tap(find.text('Page 1: 0'));
  await tester.pump();
  // The current page owns its own vertical scroll position.
  final currentList = find.byWidgetPredicate((widget) =>
      widget is ListView && widget.key == const ValueKey('Page 1 list'));
  expect(currentList, findsOneWidget);
  await tester.drag(currentList, const Offset(0, -350));
  await tester.pumpAndSettle();
  final scrollable =
      find.descendant(of: currentList, matching: find.byType(Scrollable));
  final offset = tester.state<ScrollableState>(scrollable).position.pixels;
  expect(offset, greaterThan(0));
  expect(_index(tester), 1);
  result.add(offset);
  await tester.tap(find.text('Tab 3'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Tab 1'));
  await tester.pumpAndSettle();
  expect(find.text('Page 1: 1'), findsOneWidget);
  expect(tester.state<ScrollableState>(scrollable).position.pixels, offset);
  result.add(tester.getRect(find.text('Page 1: 1')));
  expect(tester.takeException(), isNull);
  return result;
}

void main() {
  test('TabBarView catalog exposes the native controller-free surface', () {
    final entry = kRegistry.findByName('TabBarView', WidgetLibrary.material)!;
    expect(entry.sinceVersion, 15);
    expect(
        entry.flutterType, 'package:flutter/src/material/tabs.dart#TabBarView');
    expect(entry.properties.map((p) => p.name).toSet(), {
      'children',
      'clipBehavior',
      'dragStartBehavior',
      'viewportFraction',
      'analyticsId',
    });
    expect(
        entry.properties
            .singleWhere((p) => p.name == 'dragStartBehavior')
            .enumType,
        'DragStartBehavior');
  });

  for (final direction in TextDirection.values) {
    testWidgets(
        'native selection, taps, swipe and retained scroll in $direction',
        (tester) async {
      final native = await _exercise(tester, _nativeTabs(), direction);
      final delivered = await _exercise(
          tester, _delivered(_runtime(_tabsSource())), direction);
      expect(delivered, native);
    });
  }

  for (final fraction in [0.75, 1.0, 1.5]) {
    testWidgets(
        'native geometry and enum values at viewport fraction $fraction',
        (tester) async {
      Future<Object> measure(Widget screen) async {
        await tester.pumpWidget(const SizedBox());
        await _mount(tester, screen);
        final view = tester.widget<TabBarView>(find.byType(TabBarView));
        final page = tester.widget<PageView>(find.byType(PageView));
        expect(view.viewportFraction, fraction);
        expect(page.controller!.viewportFraction, fraction);
        expect(view.clipBehavior, Clip.none);
        expect(view.dragStartBehavior, DragStartBehavior.down);
        return (tester.getRect(find.text('Page 1: 0')), _index(tester));
      }

      final native = await measure(_nativeTabs(
          fraction: fraction, clip: Clip.none, drag: DragStartBehavior.down));
      final delivered = await measure(_delivered(_runtime(_tabsSource(
          arguments:
              'viewportFraction: $fraction, clipBehavior: "none", dragStartBehavior: "down",'))));
      expect(delivered, native);
    });
  }

  testWidgets('omitted options retain Flutter defaults', (tester) async {
    await _mount(tester, _delivered(_runtime(_tabsSource())));
    final view = tester.widget<TabBarView>(find.byType(TabBarView));
    expect(view.controller, isNull);
    expect(view.physics, isNull);
    expect(view.viewportFraction, 1);
    expect(view.clipBehavior, Clip.hardEdge);
    expect(view.dragStartBehavior, DragStartBehavior.start);
  });

  testWidgets('mounted data fractions preserve values above one',
      (tester) async {
    final data = DynamicContent()..update('fraction', 0.75);
    final runtime =
        _runtime(_tabsSource(arguments: 'viewportFraction: data.fraction,'));
    final screen = _delivered(runtime, data: data);
    await _mount(tester, screen);
    final state = tester.state(find.byType(TabBarView));
    for (final fraction in [0.75, 1.0, 1.5]) {
      data.update('fraction', fraction);
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(TabBarView)), same(state));
      expect(
          tester
              .widget<PageView>(find.byType(PageView))
              .controller!
              .viewportFraction,
          fraction);
      expect(_index(tester), 1);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('coherent controller and children length changes match native',
      (tester) async {
    Future<List<int>> exercise(bool delivered) async {
      await tester.pumpWidget(const SizedBox());
      final runtime = _runtime(_tabsSource(initialIndex: 0));
      final screen = _delivered(runtime);
      final indices = <int>[];
      await _mount(tester, delivered ? screen : _nativeTabs(initialIndex: 0));
      expect(_index(tester), 0);
      await tester.tap(find.text('Tab 3'));
      await tester.pumpAndSettle();
      expect(_index(tester), 3);
      for (final length in [2, 4]) {
        if (delivered) {
          runtime.update(_root, parseLibraryFile('''
import restage.core;
import restage.material;
import pages;
widget Screen = ${_tabsSource(length: length, initialIndex: 0)};
'''));
          await tester.pumpAndSettle();
        } else {
          await _mount(tester, _nativeTabs(length: length, initialIndex: 0));
        }
        expect(tester.takeException(), isNull);
        expect(tester.widget<TabBarView>(find.byType(TabBarView)).children,
            hasLength(length));
        indices.add(_index(tester));
      }
      return indices;
    }

    final native = await exercise(false);
    expect(await exercise(true), native);
    expect(native, [1, 1]);
  });

  testWidgets('nested tab pages read their nearest controller', (tester) async {
    Future<List<List<int>>> exercise(Widget screen) async {
      await tester.pumpWidget(const SizedBox());
      await _mount(tester, screen);
      final indices = <List<int>>[
        [_index(tester), _index(tester, 1)]
      ];
      await tester.tap(find.text('Tab 0'));
      await tester.pumpAndSettle();
      indices.add([_index(tester), _index(tester, 1)]);
      await tester.tap(find.text('Outer 1'));
      await tester.pumpAndSettle();
      indices.add([_index(tester)]);
      expect(tester.takeException(), isNull);
      return indices;
    }

    final native = await exercise(DefaultTabController(
        length: 2,
        child: Column(children: [
          const TabBar(tabs: [Tab(text: 'Outer 0'), Tab(text: 'Outer 1')]),
          Expanded(
              child: TabBarView(children: [
            _nativeTabs(length: 2),
            const Text('Outer page')
          ])),
        ])));
    final delivered = await exercise(_delivered(_runtime('''
DefaultTabController(length: 2, child: Column(children: [
  TabBar(tabs: [Tab(text: "Outer 0"), Tab(text: "Outer 1")]),
  Expanded(child: TabBarView(children: [${_tabsSource(length: 2)}, Text(text: "Outer page")])),
]))
''')));
    expect(delivered, native);
    expect(native, [
      [0, 1],
      [0, 0],
      [1]
    ]);
  });
}

class _Page extends StatefulWidget {
  const _Page(this.name);
  final String name;
  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> with AutomaticKeepAliveClientMixin {
  int count = 0;
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(children: [
      TextButton(
          onPressed: () => setState(() => count++),
          child: Text('${widget.name}: $count')),
      Expanded(
          child: ListView(key: ValueKey('${widget.name} list'), children: [
        for (var i = 0; i < 40; i++)
          SizedBox(height: 48, child: Text('${widget.name} row $i')),
      ])),
    ]);
  }
}
