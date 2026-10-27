import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart';
import 'package:rfw/rfw.dart';

const _core = LibraryName(['restage', 'core']);
const _surface = LibraryName(['test', 'spanBuilder']);
typedef _Event = Map<String, Object?>;

TapGestureRecognizer _recognizer(WidgetTester tester) =>
    (tester.widget<Text>(find.byType(Text)).textSpan! as TextSpan).recognizer!
        as TapGestureRecognizer;

Offset _spanCenter(WidgetTester tester) {
  final paragraph = tester.renderObject<RenderParagraph>(find.byType(RichText));
  return paragraph.localToGlobal(paragraph
      .getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 3))
      .single
      .toRect()
      .center);
}

Future<List<_Event>> _timeline(WidgetTester tester,
    {required bool remote}) async {
  final source =
      File('test/fixtures/span_builder_compiled.rfwtxt').readAsStringSync();
  final events = <_Event>[];
  final nativeRecognizers = <TapGestureRecognizer>[];
  final contexts = <BuildContext>{};
  final baseline = GestureBinding.instance.pointerRouter.debugGlobalRouteCount;
  final data = DynamicContent({
    'context': {'tag': 'old'}
  });
  final runtime = Runtime()
    ..update(
        _core,
        LocalWidgetLibrary({
          ...kCoreLibraryFactories,
          kBuilderContinuationWidgetName: (context, source) {
            contexts.add(context);
            return buildRestageBuilderContinuation(context, source);
          },
        }))
    ..update(_surface, parseLibraryFile(source));
  Widget native(String tag, int generation) => KeyedSubtree(
        key: ValueKey(generation),
        child: LayoutBuilder(builder: (context, constraints) {
          final captured = '$tag:${constraints.maxWidth}';
          final event = tag == 'old' ? 'pick.old' : 'pick.new';
          final recognizer = TapGestureRecognizer()
            ..onTap = () => events.add({
                  'name': event,
                  'arguments': {'value': captured}
                });
          nativeRecognizers.add(recognizer);
          return Text.rich(TextSpan(text: 'Tap', recognizer: recognizer));
        }),
      );
  final inner = ValueNotifier<Widget>(remote
      ? RemoteWidget(
          runtime: runtime,
          data: data,
          widget: const FullyQualifiedWidgetName(_surface, 'Root'),
          onEvent: (name, arguments) => events.add(
              {'name': name, 'arguments': Map<String, Object?>.of(arguments)}))
      : native('old', 0));
  await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
          child: SizedBox(
              width: 320,
              child: ValueListenableBuilder<Widget>(
                  valueListenable: inner, builder: (_, child, __) => child)))));
  final old = _recognizer(tester);
  final oldPointer = await tester.startGesture(_spanCenter(tester));
  await tester.pump(const Duration(milliseconds: 150));
  if (remote) {
    data.update('context', {'tag': 'new'});
  } else {
    inner.value = native('new', 0);
  }
  await tester.pump();
  expect(_recognizer(tester), isNot(same(old)));
  expect(old.onTap, isNotNull);
  await oldPointer.up();
  await tester.pump();
  expect(events, [
    {
      'name': 'pick.old',
      'arguments': {'value': 'old:320.0'}
    }
  ]);
  if (remote) expect(old.onTap, isNull);
  await tester.tapAt(_spanCenter(tester));
  await tester.pump();
  expect(events.last, {
    'name': 'pick.new',
    'arguments': {'value': 'new:320.0'}
  });

  final beforeReplacement = _recognizer(tester);
  final oldContexts = contexts.where((context) => context.mounted).toList();
  if (remote) expect(oldContexts, isNotEmpty);
  final replacingPointer = await tester.startGesture(_spanCenter(tester));
  await tester.pump(const Duration(milliseconds: 150));
  if (remote) {
    runtime.update(_surface, parseLibraryFile(source));
  } else {
    inner.value = native('new', 1);
  }
  await tester.pump();
  expect(_recognizer(tester), isNot(same(beforeReplacement)));
  expect(oldContexts.every((context) => !context.mounted), isTrue);
  expect(beforeReplacement.onTap, isNotNull);
  await replacingPointer.up();
  await tester.pump();
  expect(events.last, {
    'name': 'pick.new',
    'arguments': {'value': 'new:320.0'}
  });
  expect(events, hasLength(3));
  if (remote) expect(beforeReplacement.onTap, isNull);

  final beforeUnmount = _recognizer(tester);
  final unmountingPointer = await tester.startGesture(_spanCenter(tester));
  await tester.pump(const Duration(milliseconds: 150));
  inner.value = const SizedBox();
  await tester.pump();
  expect(contexts.every((context) => !context.mounted), isTrue);
  data.update('context', {'tag': 'late'});
  await tester.pump();
  expect(beforeUnmount.onTap, isNotNull);
  await unmountingPointer.up();
  await tester.pump();
  expect(events, [
    {
      'name': 'pick.old',
      'arguments': {'value': 'old:320.0'}
    },
    {
      'name': 'pick.new',
      'arguments': {'value': 'new:320.0'}
    },
    {
      'name': 'pick.new',
      'arguments': {'value': 'new:320.0'}
    },
    {
      'name': 'pick.new',
      'arguments': {'value': 'new:320.0'}
    },
  ]);
  if (remote) expect(beforeUnmount.onTap, isNull);
  expect(tester.takeException(), isNull);
  expect(GestureBinding.instance.pointerRouter.debugGlobalRouteCount, baseline);
  await tester.pumpWidget(const SizedBox());
  for (final recognizer in nativeRecognizers) recognizer.dispose();
  runtime.dispose();
  inner.dispose();
  return events;
}

Object? _spanShape(InlineSpan span) {
  final text = span as TextSpan;
  return [text.text, text.style, text.children?.map(_spanShape).toList()];
}

Future<List<_Event>> _collectionTimeline(WidgetTester tester,
    {required bool remote}) async {
  final source = File(Platform.environment['SPAN_COLLECTION_FIXTURE_PATH'] ??
          'test/fixtures/span_collections_compiled.rfwtxt')
      .readAsStringSync();
  final events = <_Event>[];
  final nativeRecognizers = <TapGestureRecognizer>[];
  final baseline = GestureBinding.instance.pointerRouter.debugGlobalRouteCount;
  final data = DynamicContent({
    'context': {'labels': <String>[], 'groups': <List<String>>[], 'show': false}
  });
  final runtime = Runtime()
    ..update(_core, buildCoreWidgetLibrary())
    ..update(_surface, parseLibraryFile(source));
  Widget native(List<String> labels, bool show, {bool interactive = true}) =>
      Text.rich(TextSpan(children: [
        ...const [TextSpan(text: 'start')],
        if (show) const TextSpan(text: 'heading'),
        ...?(show ? const [TextSpan(text: 'nullable')] : null),
        if (show) const TextSpan(text: 'selected'),
        for (final label in labels) ...[
          TextSpan(
              text: label,
              style: const TextStyle(fontWeight: FontWeight.w600),
              recognizer: !interactive
                  ? null
                  : (TapGestureRecognizer()
                    ..onTap = () => events.add({
                          'name': 'pick',
                          'arguments': {'value': label}
                        }))),
          if (show) const TextSpan(text: '|'),
          const TextSpan(text: '(', children: [TextSpan(text: ')')]),
        ],
        for (final extra in const ['x', 'y']) ...[
          TextSpan(text: extra),
          if (show) const TextSpan(text: '~'),
        ],
        for (final group in [
          for (final label in labels) [label, '!']
        ]) ...[
          for (final item in group) TextSpan(text: item),
        ],
        const TextSpan(text: 'end', children: []),
      ]));
  final inner = ValueNotifier<Widget>(remote
      ? RemoteWidget(
          runtime: runtime,
          data: data,
          widget: const FullyQualifiedWidgetName(_surface, 'Root'),
          onEvent: (name, args) => events
              .add({'name': name, 'arguments': Map<String, Object?>.of(args)}))
      : native([], false));
  await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
          child: ValueListenableBuilder<Widget>(
              valueListenable: inner, builder: (_, child, __) => child))));
  Future<void> update(List<String> labels, bool show) async {
    if (remote) {
      data.update('context', {
        'labels': labels,
        'groups': [
          for (final label in labels) [label, '!']
        ],
        'show': show
      });
    } else {
      inner.value = native(labels, show);
    }
    await tester.pump();
    final actual = tester.widget<Text>(find.byType(Text)).textSpan! as TextSpan;
    final expected =
        (native(labels, show, interactive: false) as Text).textSpan!;
    expect(_spanShape(actual), _spanShape(expected));
    final recognizers = actual.children!
        .cast<TextSpan>()
        .map((span) => span.recognizer)
        .whereType<TapGestureRecognizer>()
        .toList();
    expect(recognizers.toSet(), hasLength(labels.length));
    if (!remote) nativeRecognizers.addAll(recognizers);
  }

  for (final labels in [
    <String>[],
    ['a'],
    ['a', 'b', 'c']
  ]) {
    for (final show in [false, true]) {
      await update(labels, show);
    }
  }
  await update(['a', 'b'], false);
  final first = (tester.widget<Text>(find.byType(Text)).textSpan! as TextSpan)
      .children!
      .cast<TextSpan>()
      .firstWhere((span) => span.text == 'a')
      .recognizer! as TapGestureRecognizer;
  Offset center(int start, int end) {
    final paragraph =
        tester.renderObject<RenderParagraph>(find.byType(RichText));
    return paragraph.localToGlobal(paragraph
        .getBoxesForSelection(
            TextSelection(baseOffset: start, extentOffset: end))
        .single
        .toRect()
        .center);
  }

  final pending = await tester.startGesture(center(5, 6));
  await tester.pump(const Duration(milliseconds: 150));
  await update(['b', 'a'], false);
  expect(first.onTap, isNotNull);
  await pending.up();
  await tester.pump();
  expect(events, [
    {
      'name': 'pick',
      'arguments': {'value': 'a'}
    }
  ]);
  if (remote) expect(first.onTap, isNull);
  await tester.tapAt(center(5, 6));
  await tester.pump();
  expect(events.last, {
    'name': 'pick',
    'arguments': {'value': 'b'}
  });
  final removing = await tester.startGesture(center(5, 6));
  await tester.pump(const Duration(milliseconds: 150));
  await update([], false);
  await removing.up();
  await tester.pump();
  expect(events.last, {
    'name': 'pick',
    'arguments': {'value': 'b'}
  });
  expect(events, hasLength(3));
  await tester.pumpWidget(const SizedBox());
  for (final recognizer in nativeRecognizers.toSet()) {
    recognizer.dispose();
  }
  expect(tester.takeException(), isNull);
  expect(GestureBinding.instance.pointerRouter.debugGlobalRouteCount, baseline);
  runtime.dispose();
  inner.dispose();
  return events;
}

Future<List<_Event>> _builderCollectionTimeline(WidgetTester tester,
    {required bool remote}) async {
  final source = File(
          Platform.environment['SPAN_COLLECTION_BUILDER_FIXTURE_PATH'] ??
              'test/fixtures/span_collection_builder_compiled.rfwtxt')
      .readAsStringSync();
  final events = <_Event>[];
  final controls = <TapGestureRecognizer>[];
  final data = DynamicContent({
    'context': {
      'labels': ['a', 'b']
    }
  });
  final runtime = Runtime()
    ..update(_core, buildCoreWidgetLibrary())
    ..update(_surface, parseLibraryFile(source));
  Widget native(List<String> labels) => LayoutBuilder(
      builder: (context, c) => Text.rich(TextSpan(children: [
            for (final label in labels)
              TextSpan(
                  text: '[$label:${c.maxWidth}]',
                  recognizer: (() {
                    final recognizer = TapGestureRecognizer()
                      ..onTap = () => events.add({
                            'name': 'pick',
                            'arguments': {'label': label, 'width': c.maxWidth}
                          });
                    controls.add(recognizer);
                    return recognizer;
                  })()),
          ])));
  final child = ValueNotifier<Widget>(remote
      ? RemoteWidget(
          runtime: runtime,
          data: data,
          widget: const FullyQualifiedWidgetName(_surface, 'Root'),
          onEvent: (name, args) => events
              .add({'name': name, 'arguments': Map<String, Object?>.of(args)}))
      : native(['a', 'b']));
  final width = ValueNotifier<double>(320);
  await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
          child: ValueListenableBuilder<double>(
              valueListenable: width,
              builder: (_, value, __) => SizedBox(
                  width: value,
                  child: ValueListenableBuilder<Widget>(
                      valueListenable: child,
                      builder: (_, value, __) => value))))));
  List<TextSpan> spans() =>
      (tester.widget<Text>(find.byType(Text)).textSpan! as TextSpan)
          .children!
          .cast<TextSpan>();
  expect(spans().map((span) => span.text), ['[a:320.0]', '[b:320.0]']);
  expect(spans().map((span) => span.recognizer).toSet(), hasLength(2));
  final initialParagraph =
      tester.renderObject<RenderParagraph>(find.byType(RichText));
  final initialCenter = initialParagraph.localToGlobal(initialParagraph
      .getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 1))
      .single
      .toRect()
      .center);
  final pending = await tester.startGesture(initialCenter);
  await tester.pump(const Duration(milliseconds: 150));
  if (remote) {
    data.update('context', {
      'labels': ['b', 'a']
    });
  } else {
    child.value = native(['b', 'a']);
  }
  width.value = 240;
  await tester.pump();
  expect(spans().map((span) => span.text), ['[b:240.0]', '[a:240.0]']);
  await pending.up();
  await tester.pump();
  expect(events, [
    {
      'name': 'pick',
      'arguments': {'label': 'a', 'width': 320.0}
    }
  ]);
  final paragraph = tester.renderObject<RenderParagraph>(find.byType(RichText));
  final center = paragraph.localToGlobal(paragraph
      .getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 1))
      .single
      .toRect()
      .center);
  await tester.tapAt(center);
  await tester.pump();
  expect(events.last, {
    'name': 'pick',
    'arguments': {'label': 'b', 'width': 240.0}
  });
  await tester.pumpWidget(const SizedBox());
  for (final control in controls) {
    control.dispose();
  }
  runtime.dispose();
  child.dispose();
  width.dispose();
  expect(tester.takeException(), isNull);
  return events;
}

Future<void> _collectionControls(WidgetTester tester) async {
  final source = File(
          Platform.environment['SPAN_COLLECTION_CONTROLS_FIXTURE_PATH'] ??
              'test/fixtures/span_collection_controls_compiled.rfwtxt')
      .readAsStringSync();
  final data = DynamicContent({
    'context': {'flags': <bool>[], 'show': false}
  });
  final runtime = Runtime()
    ..update(_core, buildCoreWidgetLibrary())
    ..update(_surface, parseLibraryFile(source));
  List<InlineSpan> choose(bool flag, String label) =>
      flag && flag ? [TextSpan(text: label)] : [];
  List<InlineSpan> signs(List<bool> values) => [
        for (final flag in values)
          if (flag) const TextSpan(text: '+') else const TextSpan(text: '-')
      ];
  TextSpan native(List<bool> flags, bool show) => TextSpan(children: [
        for (final flag in flags)
          if (flag) const TextSpan(text: 'yes') else const TextSpan(text: 'no'),
        ...choose(show, 'ok'),
        for (final label in const ['a', 'b'])
          if (label == 'a') TextSpan(text: label),
        for (final flag in flags) ...choose(flag, 'local'),
        ...signs(flags),
      ]);
  await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: LayoutBuilder(
          builder: (context, c) => RemoteWidget(
              runtime: runtime,
              data: data,
              widget: const FullyQualifiedWidgetName(_surface, 'Root')))));
  for (final flags in [
    <bool>[],
    [true],
    [false],
    [true, false, true],
    [false, true]
  ]) {
    for (final show in [false, true]) {
      data.update('context', {'flags': flags, 'show': show});
      await tester.pump();
      final actual = tester.widget<Text>(find.byType(Text)).textSpan!;
      expect(_spanShape(actual), _spanShape(native(flags, show)));
      expect(tester.takeException(), isNull);
    }
  }
  await tester.pumpWidget(const SizedBox());
  runtime.dispose();
}

void main() {
  testWidgets(
      'span collection controls match native across builder data updates',
      _collectionControls);
  testWidgets('span loop callbacks retain native builder frames while pending',
      (tester) async {
    final native = await _builderCollectionTimeline(tester, remote: false);
    final remote = await _builderCollectionTimeline(tester, remote: true);
    expect(remote, native);
  });
  testWidgets(
      'authored span fragments match native through updates and pending gestures',
      (tester) async {
    final native = await _collectionTimeline(tester, remote: false);
    final remote = await _collectionTimeline(tester, remote: true);
    expect(remote, native);
  });
  testWidgets(
      'authored pending span builder events match native after data, binding and unmount changes',
      (tester) async {
    final native = await _timeline(tester, remote: false);
    final remote = await _timeline(tester, remote: true);
    expect(remote, native);
  });
}
