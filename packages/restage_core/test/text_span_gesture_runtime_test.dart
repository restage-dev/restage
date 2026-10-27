import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart';

Offset _spanCenter(WidgetTester tester, int start, int end,
    {int paragraphIndex = 0}) {
  final paragraph = tester
      .renderObject<RenderParagraph>(find.byType(RichText).at(paragraphIndex));
  final box = paragraph
      .getBoxesForSelection(TextSelection(baseOffset: start, extentOffset: end))
      .single;
  return paragraph.localToGlobal(box.toRect().center);
}

const _core = LibraryName(['restage', 'core']);
const _surface = LibraryName(['test', 'surface']);
String _library(String span) =>
    'import restage.core; widget Surface = TextRich(textSpan: $span);';
Runtime _runtime(String span) => Runtime()
  ..update(_core, buildCoreWidgetLibrary())
  ..update(_surface, parseLibraryFile(_library(span)));
Widget _mount(Runtime runtime, List<String> events, {DynamicContent? data}) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
          child: RemoteWidget(
              runtime: runtime,
              data: data ?? DynamicContent(),
              widget: const FullyQualifiedWidgetName(_surface, 'Surface'),
              onEvent: (name, _) => events.add(name))),
    );
TapGestureRecognizer _tap(WidgetTester tester) =>
    (tester.widget<Text>(find.byType(Text)).textSpan! as TextSpan).recognizer!
        as TapGestureRecognizer;

class _HeldArenaRecognizer extends OneSequenceGestureRecognizer {
  @override
  String get debugDescription => 'held arena';
  @override
  void addAllowedPointer(PointerDownEvent event) {
    startTrackingPointer(event.pointer);
    GestureBinding.instance.gestureArena.hold(event.pointer);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerUpEvent || event is PointerCancelEvent)
      stopTrackingPointer(event.pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}
}

Future<List<String>> _nativeTransition(
  WidgetTester tester, {
  required bool remote,
  required String kind,
  required String phase,
  required String transition,
}) async {
  final events = <String>[];
  final controls = <GestureRecognizer>[];
  final baseline = GestureBinding.instance.pointerRouter.debugGlobalRouteCount;
  String span(String label) => kind == 'longPress'
      ? '{text: "Tap", recognizer: {kind: "longPress", duration: 80, onLongPress: event "$label.long" {}, onLongPressUp: event "$label.up" {}, onLongPressCancel: event "$label.cancel" {}}}'
      : '{text: "Tap", recognizer: {kind: "doubleTap", onDoubleTap: event "$label.double" {}, onDoubleTapCancel: event "$label.cancel" {}}}';
  Widget native(String label) {
    final GestureRecognizer recognizer;
    if (kind == 'longPress') {
      final value = LongPressGestureRecognizer(
          duration: const Duration(milliseconds: 80));
      value.onLongPress = () => events.add('$label.long');
      value.onLongPressUp = () => events.add('$label.up');
      value.onLongPressCancel = () => events.add('$label.cancel');
      recognizer = value;
    } else {
      final value = DoubleTapGestureRecognizer();
      value.onDoubleTap = () => events.add('$label.double');
      value.onDoubleTapCancel = () => events.add('$label.cancel');
      recognizer = value;
    }
    controls.add(recognizer);
    return Center(
        child: Text.rich(TextSpan(text: 'Tap', recognizer: recognizer)));
  }

  final runtime = _runtime(span('old'));
  final inner =
      ValueNotifier<Widget>(remote ? _mount(runtime, events) : native('old'));
  await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: GestureDetector(
          onLongPress: kind == 'longPress' ? () {} : null,
          child: ValueListenableBuilder<Widget>(
              valueListenable: inner, builder: (_, child, __) => child))));
  final old = (tester.widget<Text>(find.byType(Text)).textSpan! as TextSpan)
      .recognizer!;
  final point = _spanCenter(tester, 0, 3);
  final first = await tester.startGesture(point);
  TestGesture pending = first;
  if (kind == 'doubleTap') {
    await first.up();
    await tester.pump(const Duration(milliseconds: 80));
    if (phase == 'second down') pending = await tester.startGesture(point);
  } else {
    await tester.pump(const Duration(milliseconds: 10));
  }
  if (transition == 'unmount') {
    inner.value = const SizedBox();
  } else if (remote) {
    runtime.update(
        _surface,
        parseLibraryFile(
            _library(transition == 'replace' ? span('new') : '{text: "Tap"}')));
  } else {
    inner.value = transition == 'replace'
        ? native('new')
        : const Center(child: Text.rich(TextSpan(text: 'Tap')));
  }
  await tester.pump();
  if (kind == 'longPress') {
    if (phase == 'cancel') {
      await pending.cancel();
    } else {
      await tester.pump(const Duration(milliseconds: 100));
      await pending.up();
    }
  } else {
    if (phase == 'between taps') pending = await tester.startGesture(point);
    await tester.pump(const Duration(milliseconds: 20));
    await pending.up();
  }
  await tester.pump(const Duration(milliseconds: 400));
  if (remote) {
    if (old is LongPressGestureRecognizer) expect(old.onLongPress, isNull);
    if (old is DoubleTapGestureRecognizer) expect(old.onDoubleTap, isNull);
  }
  final result = List<String>.of(events);
  inner.value = const SizedBox();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  // The outer detector remains mounted while the inner owner must be gone.
  expect(GestureBinding.instance.pointerRouter.debugGlobalRouteCount, baseline);
  for (final recognizer in controls) {
    if (recognizer is LongPressGestureRecognizer) {
      recognizer.onLongPress = null;
      recognizer.onLongPressUp = null;
      recognizer.onLongPressCancel = null;
    }
    if (recognizer is DoubleTapGestureRecognizer) {
      recognizer.onDoubleTap = null;
      recognizer.onDoubleTapCancel = null;
    }
    recognizer.dispose();
  }
  await tester.pumpWidget(const SizedBox());
  inner.dispose();
  return result;
}

void main() {
  testWidgets('native fresh recognizer pending gesture differential',
      (tester) async {
    for (final strategy in ['retain', 'dispose', 'reuse']) {
      final events = <String>[];
      final resources = <TapGestureRecognizer>[];
      TapGestureRecognizer? current;
      Widget build(String label) {
        final previous = current;
        final next = strategy == 'reuse' && previous != null
            ? previous
            : (TapGestureRecognizer()
              ..onTapCancel = () => events.add('cancel:$label'));
        if (!resources.contains(next)) resources.add(next);
        next.onTap = () => events.add(label);
        current = next;
        if (strategy == 'dispose') previous?.dispose();
        return Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
                child: Text.rich(TextSpan(text: 'Tap', recognizer: next))));
      }

      await tester.pumpWidget(build('old'));
      final gesture = await tester.startGesture(_spanCenter(tester, 0, 3));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpWidget(build('new'));
      await gesture.up();
      await tester.pump();
      // ignore: avoid_print
      print('NATIVE $strategy: $events');
      expect(
          events,
          strategy == 'retain'
              ? ['old']
              : strategy == 'reuse'
                  ? ['new']
                  : ['cancel:old']);
      await tester.pumpWidget(const SizedBox());
      for (final resource in resources) {
        if (strategy != 'dispose' || identical(resource, current))
          resource.dispose();
      }
    }
  });
  for (final transition in ['remove', 'unmount']) {
    testWidgets('native pending $transition keeps in-flight callback',
        (tester) async {
      final events = <String>[];
      final recognizer = TapGestureRecognizer()
        ..onTap = (() => events.add('tap'))
        ..onTapCancel = () => events.add('cancel');
      await tester.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
              child:
                  Text.rich(TextSpan(text: 'Tap', recognizer: recognizer)))));
      final gesture = await tester.startGesture(_spanCenter(tester, 0, 3));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpWidget(transition == 'unmount'
          ? const SizedBox()
          : const Directionality(
              textDirection: TextDirection.ltr,
              child: Center(child: Text.rich(TextSpan(text: 'Tap')))));
      await gesture.up();
      await tester.pump();
      // ignore: avoid_print
      print('NATIVE $transition: $events');
      expect(events, ['tap']);
      recognizer.dispose();
    });
  }
  testWidgets(
      'generated native spans preserve exact hit regions and noninheritance',
      (tester) async {
    final events = <String>[];
    final runtime = _runtime(
        '{ text: "parent ", recognizer: {kind: "tap", onTap: event "parent" {}}, children: [{text: "child "}, {text: "link", recognizer: {kind: "tap", onTap: event "link" {}}}, {text: " inert"}] }');
    await tester.pumpWidget(_mount(runtime, events));
    await tester.tapAt(_spanCenter(tester, 0, 6));
    await tester.tapAt(_spanCenter(tester, 7, 12));
    await tester.tapAt(_spanCenter(tester, 13, 17));
    await tester.tapAt(_spanCenter(tester, 18, 23));
    expect(events, ['parent', 'link']);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets(
      'data refresh constructs a fresh recognizer and replaces callbacks',
      (tester) async {
    final events = <String>[];
    final runtime = _runtime(
        '{text: data.label, recognizer: {kind: "tap", onTap: switch data.current {true: event "new" {}, false: event "old" {}}}}');
    final data = DynamicContent()
      ..update('label', 'Tap')
      ..update('current', false);
    await tester.pumpWidget(_mount(runtime, events, data: data));
    final old = _tap(tester);
    data.update('current', true);
    await tester.pump();
    final current = _tap(tester);
    expect(current, isNot(same(old)));
    await tester.tapAt(_spanCenter(tester, 0, 3));
    await tester.pump();
    expect(events, ['new']);
    expect(old.onTap, isNull);
    runtime.update(_surface,
        parseLibraryFile(_library('{text: "Tap", recognizer: {kind: "tap"}}')));
    await tester.pump();
    expect(_tap(tester).onTap, isNull);
    await tester.tapAt(_spanCenter(tester, 0, 3));
    expect(events, ['new']);
    runtime.update(_surface, parseLibraryFile(_library('{text: "Tap"}')));
    await tester.pump();
    expect(
        (tester.widget<Text>(find.byType(Text)).textSpan! as TextSpan)
            .recognizer,
        isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  for (final transition in ['replace', 'remove', 'unmount']) {
    testWidgets('runtime pending $transition matches native in-flight callback',
        (tester) async {
      final events = <String>[];
      final runtime = _runtime(
          '{text: "Tap", recognizer: {kind: "tap", onTap: event "old" {}, onTapCancel: event "cancel" {}}}');
      await tester.pumpWidget(_mount(runtime, events));
      final old = _tap(tester);
      final gesture = await tester.startGesture(_spanCenter(tester, 0, 3));
      await tester.pump(const Duration(milliseconds: 150));
      if (transition == 'unmount') {
        await tester.pumpWidget(const SizedBox());
      } else {
        runtime.update(
            _surface,
            parseLibraryFile(_library(transition == 'replace'
                ? '{text: "Tap", recognizer: {kind: "tap", onTap: event "new" {}}}'
                : '{text: "Tap"}')));
        await tester.pump();
      }
      expect(old.onTap, isNotNull);
      await gesture.up();
      await tester.pump();
      expect(events, ['old']);
      expect(old.onTap, isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  }

  testWidgets('two surfaces own distinct native resources and event bindings',
      (tester) async {
    final eventsA = <String>[];
    final eventsB = <String>[];
    final runtime = _runtime(
        '{text: "Tap", recognizer: {kind: "tap", onTap: event "go" {}}}');
    await tester.pumpWidget(Column(children: [
      Expanded(child: _mount(runtime, eventsA)),
      Expanded(child: _mount(runtime, eventsB))
    ]));
    final spans = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.textSpan! as TextSpan)
        .toList();
    expect(spans[0].recognizer, isNot(same(spans[1].recognizer)));
    await tester.tapAt(_spanCenter(tester, 0, 3, paragraphIndex: 0));
    expect(eventsA, ['go']);
    expect(eventsB, isEmpty);
    await tester.tapAt(_spanCenter(tester, 0, 3, paragraphIndex: 1));
    expect(eventsB, ['go']);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('native double tap and long press keep their recognizer types',
      (tester) async {
    final events = <String>[];
    final runtime = _runtime(
        '{text: "Tap", recognizer: {kind: "doubleTap", onDoubleTap: event "double" {}}}');
    await tester.pumpWidget(_mount(runtime, events));
    expect(
        (tester.widget<Text>(find.byType(Text)).textSpan! as TextSpan)
            .recognizer,
        isA<DoubleTapGestureRecognizer>());
    await tester.tapAt(_spanCenter(tester, 0, 3));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(_spanCenter(tester, 0, 3));
    expect(events, ['double']);
    runtime.update(
        _surface,
        parseLibraryFile(_library(
            '{text: "Tap", recognizer: {kind: "longPress", duration: 20, onLongPress: event "long" {}, onLongPressUp: event "up" {}}}')));
    await tester.pump();
    expect(
        (tester.widget<Text>(find.byType(Text)).textSpan! as TextSpan)
            .recognizer,
        isA<LongPressGestureRecognizer>());
    final gesture = await tester.startGesture(_spanCenter(tester, 0, 3));
    await tester.pump(const Duration(milliseconds: 30));
    await gesture.up();
    expect(events, ['double', 'long', 'up']);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 350));
  });
  for (final remote in [false, true]) {
    testWidgets(
        '${remote ? 'runtime' : 'native'} preserves a tap in an arena held after pointer up',
        (tester) async {
      final events = <String>[];
      final native = TapGestureRecognizer()..onTap = (() => events.add('old'));
      final runtime = _runtime(
          '{text: "Tap", recognizer: {kind: "tap", onTap: event "old" {}}}');
      Widget wrap(Widget child) => Directionality(
          textDirection: TextDirection.ltr,
          child: RawGestureDetector(gestures: {
            _HeldArenaRecognizer:
                GestureRecognizerFactoryWithHandlers<_HeldArenaRecognizer>(
                    _HeldArenaRecognizer.new, (_) {}),
          }, child: child));
      await tester.pumpWidget(wrap(remote
          ? _mount(runtime, events)
          : Center(
              child: Text.rich(TextSpan(text: 'Tap', recognizer: native)))));
      final gesture =
          await tester.startGesture(_spanCenter(tester, 0, 3), pointer: 71);
      await tester.pump(const Duration(milliseconds: 150));
      final old = remote ? _tap(tester) : native;
      await gesture.up();
      if (remote) {
        runtime.update(_surface, parseLibraryFile(_library('{text: "Tap"}')));
        await tester.pump();
      }
      await tester.pump(const Duration(seconds: 1));
      expect(events, isEmpty);
      expect(old.onTap, isNotNull);
      GestureBinding.instance.gestureArena.release(71);
      await tester.pump();
      expect(events, ['old']);
      if (remote) expect(old.onTap, isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      native.dispose();
    });
  }

  testWidgets(
      'constructor presence keeps native slop null and supported device configuration',
      (tester) async {
    final runtime = _runtime(
        r"{text: 'Tap', recognizer: {kind: 'tap', supportedDevices: ['touch'], preAcceptSlopTolerance: {'$restage.constructor.presence': 1}, postAcceptSlopTolerance: {'$restage.constructor.presence': 1, '$restage.constructor.value': 9.0}}}");
    await tester.pumpWidget(_mount(runtime, []));
    final recognizer = _tap(tester);
    expect(recognizer.preAcceptSlopTolerance, isNull);
    expect(recognizer.postAcceptSlopTolerance, 9);
    expect(recognizer.supportedDevices, {PointerDeviceKind.touch});
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets(
      'generic owner disposes each build once and cleans failed allocation',
      (tester) async {
    final disposed = <Object>[];
    final first = Object();
    final second = Object();
    Widget build(Object resource) =>
        RestageResourceBuilder(builder: (resources) {
          resources.own(resource, dispose: disposed.add);
          return const SizedBox();
        });
    await tester.pumpWidget(build(first));
    await tester.pumpWidget(build(second));
    expect(disposed, [first]);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(disposed, [first, second]);
    final failed = Object();
    expect(
        () => RestageResourceBuilder(builder: (resources) {
              resources.own(failed, dispose: disposed.add);
              throw StateError('failed build');
            }),
        throwsStateError);
    expect(disposed, [first, second, failed]);
  });
  testWidgets(
      'early native arena rejection retires without inventing cancel events',
      (tester) async {
    final events = <String>[];
    final runtime = _runtime(
        '{text: "Tap", recognizer: {kind: "tap", onTap: event "tap" {}, onTapCancel: event "cancel" {}}}');
    await tester.pumpWidget(RawGestureDetector(gestures: {
      EagerGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
              EagerGestureRecognizer.new, (_) {}),
    }, child: _mount(runtime, events)));
    final old = _tap(tester);
    final gesture = await tester.startGesture(_spanCenter(tester, 0, 3));
    await gesture.up();
    runtime.update(_surface, parseLibraryFile(_library('{text: "Tap"}')));
    await tester.pump();
    expect(events, isEmpty);
    expect(old.onTap, isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  for (final kind in ['longPress', 'doubleTap']) {
    for (final phase in kind == 'longPress'
        ? ['up', 'cancel']
        : ['between taps', 'second down']) {
      for (final transition in ['replace', 'remove', 'unmount']) {
        testWidgets(
            '$kind $phase during $transition matches native and retires while outer remains mounted',
            (tester) async {
          final native = await _nativeTransition(tester,
              remote: false, kind: kind, phase: phase, transition: transition);
          final runtime = await _nativeTransition(tester,
              remote: true, kind: kind, phase: phase, transition: transition);
          expect(runtime, native);
          if (kind == 'longPress') {
            expect(runtime,
                phase == 'cancel' ? ['old.cancel'] : ['old.long', 'old.up']);
          } else if (phase == 'second down') {
            expect(runtime, ['old.double']);
          } else {
            expect(runtime, isEmpty);
          }
        });
      }
    }
  }
}
