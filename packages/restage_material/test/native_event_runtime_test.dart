import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:restage_material/restage_material.dart';
import 'package:rfw/formats.dart' as rfw;
import 'package:rfw/rfw.dart';

import 'fixtures/native_event_source.dart';

const _root = LibraryName(['test']);
const _core = LibraryName(['restage', 'core']);
const _material = LibraryName(['restage', 'material']);

class _Scroll extends ScrollController {
  bool disposed = false;
  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

class _Tabs extends TabController {
  _Tabs(TickerProvider ticker) : super(length: 2, vsync: ticker);
  bool disposed = false;
  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

Widget _remote(_Tabs tabs, _Scroll scroll, VoidCallback? borrowed,
    {String? measurement}) {
  final library = rfw.parseLibraryFile(
      'import restage.core; import restage.material; widget Root = $nativeEventDsl;');
  if (measurement != null) {
    final root = library.widgets.single.root as rfw.ConstructorCall;
    final children = root.arguments['children']! as List;
    final button = children[2] as rfw.ConstructorCall;
    final event = button.arguments['onPressed']! as Map;
    event['measurement'] = rfw.EventHandler(measurement, {});
  }
  final runtime = Runtime()
    ..update(_core, buildCoreWidgetLibrary())
    ..update(_material, buildMaterialWidgetLibrary())
    ..update(_root, library);
  return RestageNativeValues(
      bindings:
          nativeEventBindings(tabs: tabs, scroll: scroll, borrowed: borrowed),
      child: RemoteWidget(
          runtime: runtime,
          data: DynamicContent({'context': nativeEventData()}),
          widget: const FullyQualifiedWidgetName(_root, 'Root'),
          onEvent: (name, arguments) {
            if (name == measurement) _measurementLog.add(name);
          }));
}

final _measurementLog = <String>[];

Widget _mount(_Tabs tabs, _Scroll scroll, VoidCallback? borrowed,
        {required bool remote, String? measurement}) =>
    Column(children: [
      SizedBox(
          height: 180,
          child: remote
              ? _remote(tabs, scroll, borrowed, measurement: measurement)
              : NativeEventSource(
                  tabs: tabs, scroll: scroll, borrowed: borrowed)),
      SizedBox(
          height: 60,
          child: TabBarView(
              controller: tabs,
              children: const [Text('First page'), Text('Second page')])),
      SizedBox(
          height: 80,
          child: ListView(
              controller: scroll, children: const [SizedBox(height: 1000)])),
    ]);

Widget _lexicalRemote(ValueChanged<int> observer) {
  final runtime = Runtime()
    ..update(_core, buildCoreWidgetLibrary())
    ..update(_material, buildMaterialWidgetLibrary())
    ..update(
        _root,
        rfw.parseLibraryFile(
            'import restage.core; import restage.material; widget Root = $nativeLexicalDsl;'));
  return RestageNativeValues(
      bindings: nativeLexicalBindings(observer: observer),
      child: RemoteWidget(
          runtime: runtime,
          data: DynamicContent({'context': nativeLexicalData()}),
          widget: const FullyQualifiedWidgetName(_root, 'Root')));
}

void main() {
  testWidgets('RFW event and state handlers retain their existing dispatch',
      (tester) async {
    final events = <String>[];
    final runtime = Runtime()
      ..update(_core, buildCoreWidgetLibrary())
      ..update(
          _root,
          rfw.parseLibraryFile(
              'import restage.core; widget Root { flag: false } = GestureDetector(onTap: [set state.flag = true, event "legacy" {}], child: Text(text: switch state.flag { false: "Before", true: "After" }));'));
    await tester.pumpWidget(MaterialApp(
        home: RemoteWidget(
            runtime: runtime,
            data: DynamicContent(),
            widget: const FullyQualifiedWidgetName(_root, 'Root'),
            onEvent: (name, args) => events.add(name))));
    expect(events, isEmpty);
    await tester.tap(find.text('Before'));
    await tester.pump();
    expect(events, ['legacy']);
    expect(find.text('After'), findsOneWidget);
  });

  testWidgets('registered events match native controller methods and listeners',
      (tester) async {
    Future<List<Object>> trace(bool remote) async {
      final tabs = _Tabs(tester);
      final scroll = _Scroll();
      final log = <Object>[];
      tabs.addListener(
          () => log.add(('tab', tabs.index, tabs.indexIsChanging)));
      scroll.addListener(() => log.add(('scroll', scroll.offset)));
      await tester.pumpWidget(MaterialApp(
          home:
              _mount(tabs, scroll, () => log.add('borrowed'), remote: remote)));
      expect(log, isEmpty, reason: 'Callback bodies must wait for interaction');
      expect(tabs.index, 0);
      expect(scroll.offset, 0);
      await tester.tap(find.text('Tab'));
      await tester.pumpAndSettle();
      expect(tabs.index, 1);
      await tester.tap(find.text('Scroll'));
      expect(scroll.offset, 80);
      await tester.tap(find.text('Borrowed'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      expect(scroll.hasClients, isFalse);
      expect(scroll.disposed, isFalse);
      expect(tabs.disposed, isFalse);
      scroll.dispose();
      tabs.dispose();
      return log;
    }

    final native = await trace(false);
    final delivered = await trace(true);
    expect(delivered, native);
    expect(delivered, contains('borrowed'));
  });

  testWidgets('two scopes and replacement keep retained callback ownership',
      (tester) async {
    final first = _Tabs(tester),
        second = _Tabs(tester),
        replacement = _Tabs(tester);
    final firstScroll = _Scroll(),
        secondScroll = _Scroll(),
        replacementScroll = _Scroll();
    final log = <String>[];
    Future<void> mount(_Tabs left, _Scroll leftScroll, String label) =>
        tester.pumpWidget(MaterialApp(
            home: Row(children: [
          Expanded(
              child:
                  _mount(left, leftScroll, () => log.add(label), remote: true)),
          Expanded(
              child: _mount(second, secondScroll, () => log.add('second'),
                  remote: true)),
        ])));
    await mount(first, firstScroll, 'first');
    final retained = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Tab').first)
        .onPressed!;
    final retainedBorrowed = tester
        .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Borrowed').first)
        .onPressed!;
    final retainedScroll = tester
        .widget<GestureDetector>(
            find.widgetWithText(GestureDetector, 'Scroll').first)
        .onTap!;
    await tester.tap(find.text('Tab').last);
    await tester.pumpAndSettle();
    expect(first.index, 0);
    expect(second.index, 1);
    await mount(replacement, replacementScroll, 'replacement');
    expect(firstScroll.hasClients, isFalse);
    expect(first.disposed, isFalse);
    expect(firstScroll.disposed, isFalse);
    retained();
    retainedBorrowed();
    await tester.pumpAndSettle();
    expect(first.index, 1);
    expect(replacement.index, 0);
    expect(log, ['first']);
    // A retained callback must still call its old detached controller.
    expect(retainedScroll, throwsAssertionError);
    expect(replacementScroll.offset, 0);
    await tester.tap(find.text('Borrowed').first);
    expect(log, ['first', 'replacement']);
    await tester.pumpWidget(const SizedBox());
    retainedBorrowed();
    expect(log, ['first', 'replacement', 'first']);
    for (final scroll in [firstScroll, secondScroll, replacementScroll]) {
      expect(scroll.disposed, isFalse);
      scroll.dispose();
    }
    for (final tabs in [first, second, replacement]) {
      expect(tabs.disposed, isFalse);
      tabs.dispose();
    }
  });

  testWidgets(
      'installed event closures retain live lexical cells and separate invocations',
      (tester) async {
    for (final remote in [false, true]) {
      final seen = <int>[];
      Future<void> mount() => tester.pumpWidget(MaterialApp(
          home: SizedBox(
              width: 300,
              height: 200,
              child: remote
                  ? _lexicalRemote(seen.add)
                  : NativeLexicalEventSource(observer: seen.add))));
      await mount();
      expect(seen, isEmpty);
      final retained =
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed!;
      retained();
      retained();
      expect(seen, [0, 1]);
      await tester.pumpWidget(const SizedBox());
      await mount();
      final next =
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed!;
      next();
      retained();
      next();
      expect(seen, [0, 1, 0, 2, 1]);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('native measurement follows the effect once and preserves errors',
      (tester) async {
    final tabs = _Tabs(tester);
    final scroll = _Scroll();
    _measurementLog.clear();
    await tester.pumpWidget(MaterialApp(
        home: _mount(tabs, scroll, () {
      expect(_measurementLog, isEmpty);
      _measurementLog.add('effect');
    }, remote: true, measurement: 'measured')));
    expect(_measurementLog, isEmpty);
    await tester.tap(find.text('Borrowed'));
    expect(_measurementLog, ['effect', 'measured']);
    final pending = Completer<void>();
    _measurementLog.clear();
    Future<void> pendingCallback() {
      _measurementLog.add('pending');
      return pending.future;
    }

    await tester.pumpWidget(MaterialApp(
        home: _mount(tabs, scroll, pendingCallback,
            remote: true, measurement: 'measured')));
    tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Borrowed'))
        .onPressed!();
    expect(pending.isCompleted, isFalse);
    expect(_measurementLog, ['pending', 'measured']);
    pending.complete();
    await tester.pump();
    _measurementLog.clear();
    final error = StateError('native');
    await tester.pumpWidget(MaterialApp(
        home: _mount(tabs, scroll, () => throw error,
            remote: true, measurement: 'measured')));
    final callback = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Borrowed'))
        .onPressed!;
    expect(callback, throwsA(same(error)));
    expect(_measurementLog, isEmpty);
    await tester.pumpWidget(MaterialApp(
        home:
            _mount(tabs, scroll, null, remote: true, measurement: 'measured')));
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Borrowed'))
            .onPressed,
        isNull);
    await tester.pumpWidget(const SizedBox());
    tabs.dispose();
    scroll.dispose();
  });
}
