import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:rfw/formats.dart' as rfw;
import 'package:rfw/rfw.dart';

import 'fixtures/native_controller_factories.g.dart' as factories;

const _scroll = NativeBindingContract(type: 'flutter.ScrollController');
const _tabs = NativeBindingContract(type: 'flutter.TabController');
const _root = LibraryName(['test']);
const _core = LibraryName(['restage', 'core']);

class _ScrollController extends ScrollController {
  _ScrollController() : super(initialScrollOffset: 23);
  bool disposed = false;
  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

class _TabController extends TabController {
  _TabController(TickerProvider vsync) : super(length: 2, vsync: vsync);
  bool disposed = false;
  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

Runtime _runtime(String source) => Runtime()
  ..update(
      _core,
      LocalWidgetLibrary({
        ...kCoreLibraryFactories,
        'GridViewCount': factories.buildGridViewCount,
        'ListView': factories.buildListView,
        'SingleChildScrollView': factories.buildSingleChildScrollView,
        'TabBar': factories.buildTabBar,
        'TabBarView': factories.buildTabBarView,
      }))
  ..update(_root,
      rfw.parseLibraryFile('import restage.core; widget Root = $source;'));

Widget _remote(Runtime runtime, NativeBindingContract contract, Object? value,
        {String contextKey = 'controller'}) =>
    RestageNativeValues(
        bindings: {
          'controller': NativeBinding(contract: contract, value: value),
        },
        child: RemoteWidget(
          runtime: runtime,
          data: DynamicContent({
            'context': {contextKey: contract.reference('controller')}
          }),
          widget: const FullyQualifiedWidgetName(_root, 'Root'),
        ));

Future<void> _pump(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(
        home: Center(child: SizedBox(width: 300, height: 180, child: child))));

void main() {
  testWidgets('compiled Flutter source preserves borrowed list and tab objects',
      (tester) async {
    final fixtures = jsonDecode(
        File('test/fixtures/native_controller_sources.json')
            .readAsStringSync()) as Map;
    for (final name in ['list', 'tabs']) {
      final fixture = fixtures[name] as Map;
      final runtime = _runtime(fixture['dsl'] as String);
      final Object controller =
          name == 'list' ? PageController() : _TabController(tester);
      final contract = name == 'list' ? _scroll : _tabs;
      await _pump(
          tester,
          _remote(runtime, contract, controller,
              contextKey: fixture['key'] as String));
      expect(tester.takeException(), isNull);
      if (controller is PageController) {
        expect(tester.widget<Scrollable>(find.byType(Scrollable)).controller,
            same(controller));
        expect(controller.positions, hasLength(1));
        controller.jumpTo(90);
        expect(controller.offset, 90);
      } else {
        final tabs = controller as _TabController;
        expect(
            tester.widget<TabBar>(find.byType(TabBar)).controller, same(tabs));
        expect(tester.widget<TabBarView>(find.byType(TabBarView)).controller,
            same(tabs));
        tabs.animateTo(1, duration: const Duration(milliseconds: 32));
        await tester.pumpAndSettle();
        expect(find.text('second'), findsOneWidget);
      }
      await _pump(tester, const SizedBox());
      if (controller is PageController) controller.dispose();
      if (controller is _TabController) {
        expect(controller.disposed, isFalse);
        controller.dispose();
      }
      runtime.dispose();
    }
  });
  for (final kind in ['grid', 'list', 'single']) {
    testWidgets(
        '$kind retains native attachments offsets and borrowed ownership',
        (tester) async {
      final children =
          List<Widget>.generate(20, (_) => const SizedBox(height: 100));
      Widget native(ScrollController controller) => switch (kind) {
            'grid' => GridView.count(
                controller: controller, crossAxisCount: 2, children: children),
            'list' => ListView(controller: controller, children: children),
            _ => SingleChildScrollView(
                controller: controller, child: const SizedBox(height: 2000)),
          };
      final wireChildren = List.filled(20, 'SizedBox(height:100.0)').join(',');
      final source = switch (kind) {
        'grid' =>
          'GridViewCount(controller:data.context.controller,crossAxisCount:2,children:[$wireChildren])',
        'list' =>
          'ListView(controller:data.context.controller,children:[$wireChildren])',
        _ =>
          'SingleChildScrollView(controller:data.context.controller,child:SizedBox(height:2000.0))',
      };
      final runtime = _runtime(source);
      addTearDown(runtime.dispose);
      final original = _ScrollController();
      final borrowed = _ScrollController();
      final replacement = _ScrollController();
      Future<List<double>> trace(
          ScrollController controller, Widget widget) async {
        final offsets = <double>[];
        void listener() => offsets.add(controller.offset);
        controller.addListener(listener);
        await _pump(tester, widget);
        expect(tester.takeException(), isNull);
        expect(controller.positions, hasLength(1));
        expect(controller.offset, 23);
        controller.jumpTo(75);
        await tester.pump();
        final animation = controller.animateTo(110,
            duration: const Duration(milliseconds: 32), curve: Curves.linear);
        await tester.pumpAndSettle();
        await animation;
        expect(controller.offset, 110);
        controller.removeListener(listener);
        return offsets;
      }

      final expected = await trace(original, native(original));
      await _pump(tester, const SizedBox());
      final actual = await trace(borrowed, _remote(runtime, _scroll, borrowed));
      expect(actual, expected);
      final scrollable = tester.widget<Scrollable>(find.byType(Scrollable));
      expect(scrollable.controller, same(borrowed));
      await _pump(tester, _remote(runtime, _scroll, replacement));
      expect(borrowed.hasClients, isFalse);
      expect(borrowed.disposed, isFalse);
      expect(replacement.positions, hasLength(1));
      await _pump(tester, const SizedBox());
      expect(replacement.hasClients, isFalse);
      expect(replacement.disposed, isFalse);
      for (final controller in [original, borrowed, replacement])
        controller.dispose();
    });
  }

  testWidgets('a PageController stays the actual ScrollController subtype',
      (tester) async {
    final controller = PageController();
    final runtime = _runtime(
        'ListView(controller:data.context.controller,children:[SizedBox(height:2000.0)])');
    addTearDown(runtime.dispose);
    await _pump(tester, _remote(runtime, _scroll, controller));
    expect(tester.takeException(), isNull);
    expect(tester.widget<Scrollable>(find.byType(Scrollable)).controller,
        same(controller));
    expect(controller.positions, hasLength(1));
    controller.jumpTo(60);
    expect(controller.offset, 60);
    await _pump(tester, const SizedBox());
    controller.dispose();
  });

  testWidgets('tab bar and view share native index animation and listeners',
      (tester) async {
    final original = _TabController(tester);
    final borrowed = _TabController(tester);
    final replacement = _TabController(tester);
    Widget native(TabController controller) => Column(children: [
          TabBar(
              controller: controller, tabs: const [Text('one'), Text('two')]),
          Expanded(
              child: TabBarView(
                  controller: controller,
                  children: const [Text('first'), Text('second')])),
        ]);
    final runtime = _runtime('Column(children:['
        'TabBar(controller:data.context.controller,tabs:[Text(text:"one"),Text(text:"two")]),'
        'Expanded(child:TabBarView(controller:data.context.controller,children:[Text(text:"first"),Text(text:"second")]))])');
    addTearDown(runtime.dispose);
    Future<List<(int, bool)>> trace(
        TabController controller, Widget widget) async {
      final events = <(int, bool)>[];
      void listener() =>
          events.add((controller.index, controller.indexIsChanging));
      controller.addListener(listener);
      await _pump(tester, widget);
      expect(tester.takeException(), isNull);
      controller.animateTo(1, duration: const Duration(milliseconds: 32));
      await tester.pumpAndSettle();
      expect(controller.index, 1);
      expect(find.text('second'), findsOneWidget);
      controller.removeListener(listener);
      return events;
    }

    final expected = await trace(original, native(original));
    await _pump(tester, const SizedBox());
    final actual = await trace(borrowed, _remote(runtime, _tabs, borrowed));
    expect(actual, expected);
    expect(
        tester.widget<TabBar>(find.byType(TabBar)).controller, same(borrowed));
    expect(tester.widget<TabBarView>(find.byType(TabBarView)).controller,
        same(borrowed));
    await _pump(tester, _remote(runtime, _tabs, replacement));
    expect(borrowed.disposed, isFalse);
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller,
        same(replacement));
    await _pump(tester, const SizedBox());
    expect(replacement.disposed, isFalse);
    for (final controller in [original, borrowed, replacement])
      controller.dispose();
  });

  testWidgets(
      'omitted and present-null controllers keep inherited native defaults',
      (tester) async {
    const nullable =
        NativeBindingContract(type: 'flutter.ScrollController', nullable: true);
    for (final argument in [
      '',
      'controller:null,',
      'controller:data.context.controller,'
    ]) {
      final inherited = _ScrollController();
      final runtime =
          _runtime('ListView(${argument}children:[SizedBox(height:2000.0)])');
      await _pump(
          tester,
          PrimaryScrollController(
              controller: inherited,
              automaticallyInheritForPlatforms: TargetPlatform.values.toSet(),
              child: _remote(runtime, nullable, null)));
      expect(tester.takeException(), isNull);
      expect(inherited.positions, hasLength(1));
      await _pump(tester, const SizedBox());
      inherited.dispose();
      runtime.dispose();
    }
  });
}
