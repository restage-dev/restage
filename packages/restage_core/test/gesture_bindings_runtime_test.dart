import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart';

import '../../restage/test/fixtures/gesture_bindings_source.dart';

const _core = LibraryName(['restage', 'core']);
const _surface = LibraryName(['gestures']);

Widget _remote(String library, Map<String, NativeBinding<Object?>> bindings,
    Map<String, Object?> context) {
  final runtime = Runtime()
    ..update(_core, buildCoreWidgetLibrary())
    ..update(_surface, parseLibraryFile(library));
  return RestageNativeValues(
      bindings: bindings,
      child: RemoteWidget(
          runtime: runtime,
          data: DynamicContent({'context': context}),
          widget: const FullyQualifiedWidgetName(_surface, 'Surface')));
}

Widget _tree(Widget child) => Directionality(
    textDirection: TextDirection.ltr,
    child: Center(child: Transform.scale(scale: 1.5, child: child)));

TextSpan _span(WidgetTester tester) =>
    tester.widget<Text>(find.byType(Text)).textSpan! as TextSpan;

Offset _point(WidgetTester tester) {
  final paragraph = tester.renderObject<RenderParagraph>(find.byType(RichText));
  final rect = paragraph
      .getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 3))
      .single
      .toRect();
  return paragraph.localToGlobal(rect.center);
}

Object _details(Object value) => switch (value) {
      TapDownDetails() => (
          'down',
          value.globalPosition,
          value.localPosition,
          value.kind
        ),
      TapUpDetails() => (
          'up',
          value.globalPosition,
          value.localPosition,
          value.kind
        ),
      TapMoveDetails() => (
          'move',
          value.globalPosition,
          value.localPosition,
          value.kind,
          value.delta
        ),
      LongPressDownDetails() => (
          'down',
          value.globalPosition,
          value.localPosition,
          value.kind
        ),
      LongPressStartDetails() => (
          'start',
          value.globalPosition,
          value.localPosition
        ),
      LongPressMoveUpdateDetails() => (
          'move',
          value.globalPosition,
          value.localPosition,
          value.offsetFromOrigin,
          value.localOffsetFromOrigin
        ),
      LongPressEndDetails() => (
          'end',
          value.globalPosition,
          value.localPosition,
          value.velocity.pixelsPerSecond
        ),
      _ => throw StateError('$value'),
    };

Future<List<Object>> _sequence(WidgetTester tester,
    {required bool remote,
    required String kind,
    required int buttons,
    bool cancel = false}) async {
  final events = <Object>[];
  void seen(String name, Object details) =>
      events.add((name, _details(details)));
  final Widget source;
  final Widget generated;
  switch (kind) {
    case 'tap':
      final screen =
          GestureTapScreen(seen: seen, up: (details) => seen('up', details));
      source = screen;
      generated = _remote(
          gestureTapLibrary, gestureTapBindings(screen), gestureTapContext());
    case 'double':
      final screen = GestureDoubleScreen(seen: seen);
      source = screen;
      generated = _remote(gestureDoubleLibrary, gestureDoubleBindings(screen),
          gestureDoubleContext());
    case 'long':
      final screen = GestureLongScreen(seen: seen);
      source = screen;
      generated = _remote(gestureLongLibrary, gestureLongBindings(screen),
          gestureLongContext());
    default:
      throw StateError(kind);
  }
  final baseline = GestureBinding.instance.pointerRouter.debugGlobalRouteCount;
  await tester.pumpWidget(_tree(remote ? generated : source));
  final recognizer = _span(tester).recognizer!;
  final point = _point(tester);
  var gesture = await tester.startGesture(point,
      kind: PointerDeviceKind.mouse, buttons: buttons);
  events.add('after pointer down');
  if (kind == 'double') {
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 80));
    gesture = await tester.startGesture(point,
        kind: PointerDeviceKind.mouse, buttons: buttons);
  }
  await tester.pump(const Duration(milliseconds: 120));
  events.add('after deadline');
  await gesture.moveBy(const Offset(3, 2),
      timeStamp: const Duration(milliseconds: 140));
  await tester.pump(const Duration(milliseconds: 20));
  events.add('after move');
  if (cancel) {
    await gesture.cancel();
  } else {
    await gesture.up(timeStamp: const Duration(milliseconds: 160));
  }
  events.add('after pointer end');
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 400));
  if (!remote) recognizer.dispose();
  expect(GestureBinding.instance.pointerRouter.debugGlobalRouteCount, baseline);
  return events;
}

class _BorrowedTap extends TapGestureRecognizer {
  int disposals = 0;
  @override
  void dispose() {
    disposals++;
    super.dispose();
  }
}

void main() {
  for (final kind in ['tap', 'long']) {
    for (final buttons in [kPrimaryButton, kSecondaryButton, kTertiaryButton]) {
      for (final cancel in [false, true]) {
        testWidgets(
            '$kind button $buttons cancel=$cancel matches ordinary Flutter',
            (tester) async {
          final native = await _sequence(tester,
              remote: false, kind: kind, buttons: buttons, cancel: cancel);
          final generated = await _sequence(tester,
              remote: true, kind: kind, buttons: buttons, cancel: cancel);
          expect(native.where((event) => event is! String), isNotEmpty);
          expect(generated, native);
        });
      }
    }
  }
  for (final cancel in [false, true]) {
    testWidgets('double-tap details cancel=$cancel match ordinary Flutter',
        (tester) async {
      final native = await _sequence(tester,
          remote: false,
          kind: 'double',
          buttons: kPrimaryButton,
          cancel: cancel);
      final generated = await _sequence(tester,
          remote: true,
          kind: 'double',
          buttons: kPrimaryButton,
          cancel: cancel);
      expect(native.where((event) => event is! String), isNotEmpty);
      expect(generated, native);
    });
  }

  testWidgets(
      'pointer callback exception matches native Flutter timing and identity',
      (tester) async {
    final failure = StateError('gesture failed');
    final traces = <List<Object?>>[];
    for (final remote in [false, true]) {
      final trace = <Object?>[];
      final screen = GestureTapScreen(
          seen: (name, _) {
            trace.add(name);
            if (name == 'down') throw failure;
          },
          up: (_) => trace.add('up'));
      await tester.pumpWidget(_tree(remote
          ? _remote(gestureTapLibrary, gestureTapBindings(screen),
              gestureTapContext())
          : screen));
      final recognizer = _span(tester).recognizer!;
      final pointer = await tester.startGesture(_point(tester));
      trace.add(tester.takeException());
      await tester.pump(const Duration(milliseconds: 120));
      trace.add(tester.takeException());
      await pointer.up();
      trace.add(tester.takeException());
      expect(trace.where((value) => identical(value, failure)), hasLength(1));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 400));
      if (!remote) recognizer.dispose();
      traces.add(trace);
    }
    expect(traces.last, traces.first);
  });

  testWidgets(
      'typed bindings receive original tap detail objects and field tearoff',
      (tester) async {
    final seen = <Object>[];
    void up(TapUpDetails details) => seen.add(details);
    final screen =
        GestureTapScreen(seen: (_, details) => seen.add(details), up: up);
    await tester.pumpWidget(_tree(_remote(
        gestureTapLibrary, gestureTapBindings(screen), gestureTapContext())));
    final recognizer = _span(tester).recognizer! as TapGestureRecognizer;
    expect(recognizer.onTapUp, same(up));
    final down = TapDownDetails(
        globalPosition: const Offset(31, 42),
        localPosition: const Offset(7, 9));
    final end = TapUpDetails(
        kind: PointerDeviceKind.stylus,
        globalPosition: const Offset(32, 43),
        localPosition: const Offset(8, 10));
    final move = TapMoveDetails(
        kind: PointerDeviceKind.invertedStylus,
        globalPosition: const Offset(33, 44),
        localPosition: const Offset(9, 11),
        delta: const Offset(1, 2));
    for (final callback in [
      recognizer.onTapDown!,
      recognizer.onSecondaryTapDown!,
      recognizer.onTertiaryTapDown!
    ]) {
      callback(down);
      expect(seen.last, same(down));
      expect((seen.last as TapDownDetails).kind, isNull);
    }
    for (final callback in [
      recognizer.onTapUp!,
      recognizer.onSecondaryTapUp!,
      recognizer.onTertiaryTapUp!
    ]) {
      callback(end);
      expect(seen.last, same(end));
    }
    recognizer.onTapMove!(move);
    expect(seen.last, same(move));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 400));
    expect(recognizer.onTapDown, isNull);
    expect(recognizer.onTapUp, isNull);
    expect(recognizer.onTapMove, isNull);
    expect(recognizer.onSecondaryTapDown, isNull);
    expect(recognizer.onSecondaryTapUp, isNull);
    expect(recognizer.onTertiaryTapDown, isNull);
    expect(recognizer.onTertiaryTapUp, isNull);
  });

  testWidgets(
      'long-press typed bindings retain native detail and velocity identity',
      (tester) async {
    final seen = <Object>[];
    final screen = GestureLongScreen(seen: (_, details) => seen.add(details));
    await tester.pumpWidget(_tree(_remote(gestureLongLibrary,
        gestureLongBindings(screen), gestureLongContext())));
    final recognizer = _span(tester).recognizer! as LongPressGestureRecognizer;
    const down = LongPressDownDetails(
        globalPosition: Offset(31, 42), localPosition: Offset(7, 9));
    const start = LongPressStartDetails(
        globalPosition: Offset(32, 43), localPosition: Offset(8, 10));
    const move = LongPressMoveUpdateDetails(
        globalPosition: Offset(33, 44),
        localPosition: Offset(9, 11),
        offsetFromOrigin: Offset(2, 2),
        localOffsetFromOrigin: Offset(1, 1));
    const velocity = Velocity(pixelsPerSecond: Offset(140, 210));
    const end = LongPressEndDetails(
        globalPosition: Offset(34, 45),
        localPosition: Offset(10, 12),
        velocity: velocity);
    for (final callback in [
      recognizer.onLongPressDown!,
      recognizer.onSecondaryLongPressDown!,
      recognizer.onTertiaryLongPressDown!
    ]) {
      callback(down);
      expect(seen.last, same(down));
    }
    for (final callback in [
      recognizer.onLongPressStart!,
      recognizer.onSecondaryLongPressStart!,
      recognizer.onTertiaryLongPressStart!
    ]) {
      callback(start);
      expect(seen.last, same(start));
    }
    for (final callback in [
      recognizer.onLongPressMoveUpdate!,
      recognizer.onSecondaryLongPressMoveUpdate!,
      recognizer.onTertiaryLongPressMoveUpdate!
    ]) {
      callback(move);
      expect(seen.last, same(move));
    }
    for (final callback in [
      recognizer.onLongPressEnd!,
      recognizer.onSecondaryLongPressEnd!,
      recognizer.onTertiaryLongPressEnd!
    ]) {
      callback(end);
      expect(seen.last, same(end));
      expect((seen.last as LongPressEndDetails).velocity, same(velocity));
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 400));
    expect([
      recognizer.onLongPressDown,
      recognizer.onLongPressStart,
      recognizer.onLongPressMoveUpdate,
      recognizer.onLongPressEnd,
      recognizer.onSecondaryLongPressDown,
      recognizer.onSecondaryLongPressStart,
      recognizer.onSecondaryLongPressMoveUpdate,
      recognizer.onSecondaryLongPressEnd,
      recognizer.onTertiaryLongPressDown,
      recognizer.onTertiaryLongPressStart,
      recognizer.onTertiaryLongPressMoveUpdate,
      recognizer.onTertiaryLongPressEnd
    ], everyElement(isNull));
  });

  testWidgets(
      'double-tap down receives the original details and clears on retirement',
      (tester) async {
    Object? seen;
    final screen = GestureDoubleScreen(seen: (_, details) => seen = details);
    await tester.pumpWidget(_tree(_remote(gestureDoubleLibrary,
        gestureDoubleBindings(screen), gestureDoubleContext())));
    final recognizer = _span(tester).recognizer! as DoubleTapGestureRecognizer;
    final down = TapDownDetails(
        globalPosition: const Offset(31, 42),
        localPosition: const Offset(7, 9));
    recognizer.onDoubleTapDown!(down);
    expect(seen, same(down));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 400));
    expect(recognizer.onDoubleTapDown, isNull);
  });

  testWidgets('fresh recognizer callbacks share live lexical cells',
      (tester) async {
    final traces = <List<(int, Object)>>[];
    final down = TapDownDetails();
    final up = TapUpDetails(kind: PointerDeviceKind.touch);
    for (final remote in [false, true]) {
      final seen = <(int, Object)>[];
      final screen = GestureLiveScreen(
          seen: (count, details) => seen.add((count, details)));
      await tester.pumpWidget(_tree(remote
          ? _remote(gestureLiveLibrary, gestureLiveBindings(screen),
              gestureLiveContext())
          : screen));
      final spans = _span(tester).children!.cast<TextSpan>();
      final first = spans.first.recognizer! as TapGestureRecognizer;
      final second = spans.last.recognizer! as TapGestureRecognizer;
      expect(first, isNot(same(second)));
      first.onTapDown!(down);
      second.onTapUp!(up);
      first.onTapUp!(up);
      second.onTapDown!(down);
      expect(seen.map((entry) => entry.$1), [0, 1, 2, 3]);
      expect(seen.map((entry) => entry.$2),
          [same(down), same(up), same(up), same(down)]);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 400));
      if (remote) {
        expect(first.onTapDown, isNull);
        expect(second.onTapUp, isNull);
      } else {
        first.dispose();
        second.dispose();
      }
      traces.add(seen);
    }
    expect(traces.last, traces.first);
  });

  testWidgets(
      'gesture closure retains the original descendant callback context',
      (tester) async {
    for (final remote in [false, true]) {
      final seen = <(BuildContext, TapDownDetails, bool)>[];
      final screen = GestureContextScreen(
          seen: (context, details) =>
              seen.add((context, details, context.mounted)));
      await tester.pumpWidget(_tree(remote
          ? _remote(gestureContextLibrary, gestureContextBindings(screen),
              gestureContextContext())
          : screen));
      final expected = tester.element(find.byType(LayoutBuilder));
      final recognizer = _span(tester).recognizer! as TapGestureRecognizer;
      final retained = recognizer.onTapDown!;
      final details = TapDownDetails();
      retained(details);
      expect(seen.single.$1, same(expected));
      expect(seen.single.$2, same(details));
      expect(seen.single.$3, isTrue);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 400));
      retained(details);
      expect(seen.last.$1, same(expected));
      expect(seen.last.$2, same(details));
      expect(seen.last.$3, isFalse);
      if (!remote) recognizer.dispose();
    }
  });

  testWidgets('constructor callback retains its original caller context',
      (tester) async {
    late BuildContext caller;
    BuildContext? captured;
    await tester.pumpWidget(_tree(Builder(builder: (context) {
      caller = context;
      final screen =
          GestureTapScreen(seen: (_, __) => captured = context, up: (_) {});
      return _remote(
          gestureTapLibrary, gestureTapBindings(screen), gestureTapContext());
    })));
    final recognizer = _span(tester).recognizer! as TapGestureRecognizer;
    recognizer.onTapDown!(TapDownDetails());
    expect(captured, same(caller));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('installed top-level tearoff preserves identity and exceptions',
      (tester) async {
    const screen = GestureTearoffScreen();
    await tester.pumpWidget(_tree(_remote(gestureTearoffLibrary,
        gestureTearoffBindings(screen), gestureTearoffContext())));
    final recognizer = _span(tester).recognizer! as TapGestureRecognizer;
    expect(recognizer.onTapDown, same(recordGestureDown));
    final down = TapDownDetails();
    Object? seen;
    gestureTearoffSeen = (details) => seen = details;
    recognizer.onTapDown!(down);
    expect(seen, same(down));
    final failure = StateError('callback failed');
    gestureTearoffSeen = (_) => throw failure;
    expect(() => recordGestureDown(down), throwsA(same(failure)));
    expect(() => recognizer.onTapDown!(down), throwsA(same(failure)));
    gestureTearoffSeen = null;
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 400));
    expect(recognizer.onTapDown, isNull);
  });

  for (final transition in ['replace', 'unmount']) {
    testWidgets(
        'pending detail callbacks retain old invocation through $transition',
        (tester) async {
      final seen = <String>[];
      final baseline =
          GestureBinding.instance.pointerRouter.debugGlobalRouteCount;
      final old = GestureTapScreen(
          seen: (name, _) => seen.add('old.$name'),
          up: (_) => seen.add('old.up'));
      Widget mount(GestureTapScreen screen) => _tree(_remote(
          gestureTapLibrary, gestureTapBindings(screen), gestureTapContext()));
      await tester.pumpWidget(mount(old));
      final recognizer = _span(tester).recognizer! as TapGestureRecognizer;
      final pointer = await tester.startGesture(_point(tester));
      await tester.pump(const Duration(milliseconds: 120));
      expect(seen, ['old.down']);
      final replacement = GestureTapScreen(
          seen: (name, _) => seen.add('new.$name'),
          up: (_) => seen.add('new.up'));
      await tester.pumpWidget(
          transition == 'replace' ? mount(replacement) : const SizedBox());
      await pointer.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(seen, ['old.down', 'old.up']);
      expect(recognizer.onTapDown, isNull);
      expect(recognizer.onTapUp, isNull);
      expect(recognizer.onTapMove, isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 400));
      expect(GestureBinding.instance.pointerRouter.debugGlobalRouteCount,
          baseline);
    });
  }

  testWidgets(
      'shared borrowed recognizer replacement and unmount preserve owner',
      (tester) async {
    final first = _BorrowedTap();
    final second = _BorrowedTap();
    final events = <String>[];
    void firstDown(TapDownDetails details) {}
    void secondDown(TapDownDetails details) {}
    first.onTapDown = firstDown;
    second.onTapDown = secondDown;
    first.onTap = () => events.add('first');
    second.onTap = () => events.add('second');
    final firstCallback = first.onTap;
    final baseline =
        GestureBinding.instance.pointerRouter.debugGlobalRouteCount;
    Widget mount(_BorrowedTap recognizer) {
      final screen = GestureBorrowedScreen(recognizer: recognizer);
      return _tree(_remote(gestureBorrowedLibrary,
          gestureBorrowedBindings(screen), gestureBorrowedContext()));
    }

    await tester.pumpWidget(mount(first));
    expect(
        _span(tester).children!.cast<TextSpan>().map((span) => span.recognizer),
        everyElement(same(first)));
    final gesture = await tester.startGesture(_point(tester));
    await tester.pumpWidget(mount(second));
    expect(
        _span(tester).children!.cast<TextSpan>().map((span) => span.recognizer),
        everyElement(same(second)));
    await gesture.up();
    await tester.pump();
    expect(events, ['first']);
    final pending = await tester.startGesture(_point(tester));
    await tester.pumpWidget(const SizedBox());
    await pending.up();
    await tester.pump(const Duration(milliseconds: 400));
    expect(events, ['first', 'second']);
    expect(first.disposals, 0);
    expect(second.disposals, 0);
    expect(first.onTap, same(firstCallback));
    expect(first.onTapDown, same(firstDown));
    expect(second.onTapDown, same(secondDown));
    expect(second.onTap, isNotNull);
    expect(first.team, isNull);
    expect(second.team, isNull);
    expect(
        GestureBinding.instance.pointerRouter.debugGlobalRouteCount, baseline);
    first.dispose();
    second.dispose();
  });
}
