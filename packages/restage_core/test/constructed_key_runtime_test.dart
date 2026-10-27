import 'dart:collection';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:restage_shared/restage_shared.dart';
import 'fixtures/constructed_key_factories.g.dart' as f;
import 'package:rfw/rfw.dart';
import 'package:rfw/formats.dart' as rfw;
import 'fixtures/constructed_key_source.g.dart';

class _EqualModel {
  @override
  bool operator ==(Object other) => other is _EqualModel;
  @override
  int get hashCode => 1;
}

class _LoggedList extends ListBase<Object> {
  _LoggedList(this.items);
  final List<Object> items;
  final reads = <Object>[];
  Object? failure;
  @override
  int get length {
    reads.add('length');
    return items.length;
  }

  @override
  set length(int value) => throw UnsupportedError('length');
  @override
  Object operator [](int index) {
    reads.add(index);
    if (failure case final Object error) throw error;
    return items[index];
  }

  @override
  void operator []=(int index, Object value) => items[index] = value;
}

void main() {
  for (final kind in ['Inline', 'Named', 'Alias']) {
    testWidgets(
        'canonical constant keys preserve identity and collection reorder kind=$kind',
        (tester) async {
      const first = ObjectKey('first'), second = ObjectKey('second');
      Widget item(Key key) => AnimatedContainer(
          key: key,
          duration: const Duration(milliseconds: 1),
          width: 20,
          height: 20);
      Widget native(bool reverse) => Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
              children: reverse
                  ? [item(second), item(first)]
                  : [item(first), item(second)]));
      await tester.pumpWidget(native(false));
      final nativeFirst = tester.state(find.byKey(first)),
          nativeSecond = tester.state(find.byKey(second));
      await tester.pumpWidget(native(true));
      expect(tester.state(find.byKey(first)), same(nativeFirst));
      expect(tester.state(find.byKey(second)), same(nativeSecond));
      final firstPosition = tester.getTopLeft(find.byKey(first)),
          secondPosition = tester.getTopLeft(find.byKey(second));
      await tester.pumpWidget(const SizedBox());
      final makeMount = switch (kind) {
        'Inline' => constructedConstantInlineMount,
        'Named' => constructedConstantNamedMount,
        _ => constructedConstantAliasMount
      };
      final source = switch (kind) {
        'Inline' => constructedConstantInlineSource,
        'Named' => constructedConstantNamedSource,
        _ => constructedConstantAliasSource
      };
      final mount = makeMount([]);
      final runtime = Runtime();
      runtime.update(
          const LibraryName(['restage', 'core']),
          LocalWidgetLibrary({
            kBuilderContinuationWidgetName: buildRestageBuilderContinuation,
            'Row': f.buildRow,
            'AnimatedContainer': f.buildAnimatedContainer
          }));
      runtime.update(const LibraryName(['test']), rfw.parseLibraryFile(source));
      final data = DynamicContent({'context': mount.context});
      await tester.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: RestageNativeValues(
              bindings: mount.bindings,
              child: RemoteWidget(
                  runtime: runtime,
                  data: data,
                  widget: const FullyQualifiedWidgetName(
                      LibraryName(['test']), 'Root')))));
      expect(tester.takeException(), isNull);
      expect(
          tester.widget<AnimatedContainer>(find.byKey(first)).key, same(first));
      expect(tester.widget<AnimatedContainer>(find.byKey(second)).key,
          same(second));
      final firstState = tester.state(find.byKey(first)),
          secondState = tester.state(find.byKey(second));
      data.update('context', makeMount([], null, 3).context);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(tester.state(find.byKey(first)), same(firstState));
      expect(tester.state(find.byKey(second)), same(secondState));
      expect(tester.getTopLeft(find.byKey(first)), firstPosition);
      expect(tester.getTopLeft(find.byKey(second)), secondPosition);
      await tester.pumpWidget(const SizedBox());
      runtime.dispose();
    });
  }
  for (final nested in [false, true]) {
    testWidgets(
        'generated production key preserves lazy referents and frames nested=$nested',
        (tester) async {
      final first = _EqualModel(), equal = _EqualModel();
      expect(first, equal);
      expect(identical(first, equal), isFalse);
      final items = _LoggedList([first]);
      final mount =
          nested ? constructedNestedMount(items) : constructedLazyMount(items);
      expect(items.reads, isEmpty);
      final runtime = Runtime();
      runtime.update(
          const LibraryName(['restage', 'core']),
          LocalWidgetLibrary({
            kBuilderContinuationWidgetName: buildRestageBuilderContinuation,
            'LayoutBuilder': f.buildLayoutBuilder,
            'AnimatedContainer': f.buildAnimatedContainer,
            'Text': f.buildText,
            'SizedBox': f.buildSizedBox,
          }));
      runtime.update(
          const LibraryName(['test']),
          rfw.parseLibraryFile(
              nested ? constructedNestedSource : constructedLazySource));
      final data = DynamicContent({'context': mount.context});
      Widget tree(double width) => Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
              child: SizedBox(
                  width: width,
                  height: 80,
                  child: RestageNativeValues(
                      bindings: mount.bindings,
                      child: RemoteWidget(
                          runtime: runtime,
                          data: data,
                          widget: const FullyQualifiedWidgetName(
                              LibraryName(['test']), 'Root'))))));
      await tester.pumpWidget(tree(100));
      expect(tester.takeException(), isNull);
      expect(items.reads, [0]);
      final widget =
          tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
      expect((widget.key! as ObjectKey).value, same(first));
      final state = tester.state(find.byType(AnimatedContainer));
      await tester.pumpWidget(tree(120));
      expect(tester.takeException(), isNull);
      expect(items.reads, [0, 0]);
      expect(tester.state(find.byType(AnimatedContainer)), same(state));
      items.items[0] = equal;
      await tester.pumpWidget(tree(140));
      expect(tester.takeException(), isNull);
      expect(items.reads, [0, 0, 0]);
      expect(
          (tester.widget<AnimatedContainer>(find.byType(AnimatedContainer)).key!
                  as ObjectKey)
              .value,
          same(equal));
      expect(tester.state(find.byType(AnimatedContainer)), isNot(same(state)));
      final failure = StateError('native indexed access');
      items.failure = failure;
      await tester.pumpWidget(tree(160));
      expect(tester.takeException(), same(failure));
      expect(items.reads, [0, 0, 0, 0]);
      await tester.pumpWidget(const SizedBox());
      runtime.dispose();
    });
  }
  for (final variant in ['delegate', 'nested', 'builder']) {
    testWidgets(
        'native index callback sees exact keys and preserves reordered state variant=$variant',
        (tester) async {
      final first = _EqualModel(),
          second = _EqualModel(),
          third = _EqualModel();
      final items = _LoggedList([first, second, third]);
      final received = <Key>[];
      int? index(Key key) {
        received.add(key);
        final value = (key as ObjectKey).value;
        final index = items.items.indexWhere((item) => identical(item, value));
        return index < 0 ? null : index;
      }

      Widget native(int count) => Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
              data: const MediaQueryData(),
              child: Center(
                  child: SizedBox(
                      width: 80,
                      height: 240,
                      child: GridView.custom(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 1),
                          childrenDelegate: SliverChildBuilderDelegate(
                              (context, index) {
                            final itemKey = ObjectKey(items[index]);
                            return AnimatedContainer(
                                key: itemKey,
                                duration: const Duration(milliseconds: 1),
                                width: 20,
                                height: 20);
                          },
                              childCount: count,
                              findChildIndexCallback: index))))));
      await tester.pumpWidget(native(2));
      expect(tester.takeException(), isNull);
      final nativeFirst = tester.state(find.byKey(ObjectKey(first)));
      final nativeSecond = tester.state(find.byKey(ObjectKey(second)));
      items.items.setAll(0, [second, first, third]);
      await tester.pumpWidget(native(3));
      expect(tester.takeException(), isNull);
      expect(tester.state(find.byKey(ObjectKey(first))), same(nativeFirst));
      expect(tester.state(find.byKey(ObjectKey(second))), same(nativeSecond));
      final nativeReads = List<Object>.of(items.reads);
      expect(nativeReads, [0, 1, 0, 1, 2]);
      await tester.pumpWidget(const SizedBox());
      items.items.setAll(0, [first, second, third]);
      items.reads.clear();
      received.clear();
      final makeMount = switch (variant) {
        'nested' => constructedNestedDelegateMount,
        'builder' => constructedBuilderMount,
        _ => constructedDelegateMount
      };
      final mount = makeMount(items, index);
      expect(items.reads, isEmpty);
      final runtime = Runtime();
      runtime.update(
          const LibraryName(['restage', 'core']),
          LocalWidgetLibrary({
            kBuilderContinuationWidgetName: buildRestageBuilderContinuation,
            'GridViewCustom': f.buildGridViewCustom,
            'GridViewBuilder': f.buildGridViewBuilder,
            'LayoutBuilder': f.buildLayoutBuilder,
            'AnimatedContainer': f.buildAnimatedContainer
          }));
      runtime.update(
          const LibraryName(['test']),
          rfw.parseLibraryFile(switch (variant) {
            'nested' => constructedNestedDelegateSource,
            'builder' => constructedBuilderSource,
            _ => constructedDelegateSource
          }));
      final data = DynamicContent({'context': mount.context});
      await tester.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
              data: const MediaQueryData(),
              child: Center(
                  child: SizedBox(
                      width: 80,
                      height: 240,
                      child: RestageNativeValues(
                          bindings: mount.bindings,
                          child: RemoteWidget(
                              runtime: runtime,
                              data: data,
                              widget: const FullyQualifiedWidgetName(
                                  LibraryName(['test']), 'Root'))))))));
      expect(tester.takeException(), isNull);
      final firstKey =
          tester.widget<AnimatedContainer>(find.byKey(ObjectKey(first))).key!;
      final secondKey =
          tester.widget<AnimatedContainer>(find.byKey(ObjectKey(second))).key!;
      final firstState = tester.state(find.byKey(firstKey));
      final secondState = tester.state(find.byKey(secondKey));
      final firstY = tester.getTopLeft(find.byKey(firstKey)).dy;
      final secondY = tester.getTopLeft(find.byKey(secondKey)).dy;
      expect(items.reads, [0, 1]);
      items.items.setAll(0, [second, first, third]);
      data.update('context', makeMount(items, index, 3).context);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(received.any((key) => identical(key, firstKey)), isTrue);
      expect(received.any((key) => identical(key, secondKey)), isTrue);
      expect(received.every((key) => key is ObjectKey), isTrue);
      expect(tester.state(find.byKey(firstKey)), same(firstState));
      expect(tester.state(find.byKey(secondKey)), same(secondState));
      expect(tester.getTopLeft(find.byKey(firstKey)).dy, secondY);
      expect(tester.getTopLeft(find.byKey(secondKey)).dy, firstY);
      expect(items.reads, nativeReads);
      await tester.pumpWidget(const SizedBox());
      runtime.dispose();
    });
  }
  testWidgets(
      'installed native key result attaches and reparents the actual GlobalKey',
      (tester) async {
    final key = GlobalKey<State<AnimatedContainer>>();
    final items = _LoggedList([Object()]);
    final mount = constructedLazyMount(items);
    final bindings = {...mount.bindings};
    final call = bindings.entries
        .singleWhere((entry) => entry.value.contract.call != null);
    final adapter = NativeCallAdapter(
        call.value.contract,
        (inputs, cells) => NativeBinding(
            contract: const NativeBindingContract(type: 'flutter.Key'),
            value: key));
    bindings[call.key] =
        NativeBinding(contract: call.value.contract, value: adapter);
    final runtime = Runtime();
    runtime.update(
        const LibraryName(['restage', 'core']),
        LocalWidgetLibrary({
          kBuilderContinuationWidgetName: buildRestageBuilderContinuation,
          'LayoutBuilder': f.buildLayoutBuilder,
          'AnimatedContainer': f.buildAnimatedContainer
        }));
    runtime.update(const LibraryName(['test']),
        rfw.parseLibraryFile(constructedLazySource));
    final remote = RemoteWidget(
        runtime: runtime,
        data: DynamicContent({'context': mount.context}),
        widget: const FullyQualifiedWidgetName(LibraryName(['test']), 'Root'));
    Widget tree(bool right) => Directionality(
        textDirection: TextDirection.ltr,
        child: RestageNativeValues(
            bindings: bindings,
            child: Row(children: [
              Expanded(child: right ? const SizedBox() : remote),
              Expanded(child: right ? remote : const SizedBox())
            ])));
    await tester.pumpWidget(tree(false));
    expect(tester.takeException(), isNull);
    final state = key.currentState!, context = key.currentContext!;
    expect(key.currentWidget, isA<AnimatedContainer>());
    expect(key.currentWidget!.key, same(key));
    expect(state.widget, same(key.currentWidget));
    expect(context, same(tester.element(find.byKey(key))));
    expect(items.reads, isEmpty);
    await tester.pumpWidget(tree(true));
    expect(tester.takeException(), isNull);
    expect(key.currentState, same(state));
    expect(key.currentContext, same(context));
    await tester.pumpWidget(const SizedBox());
    expect(key.currentState, isNull);
    runtime.dispose();
  });
  testWidgets('unselected native initializer never indexes original list',
      (tester) async {
    final items = _LoggedList([])..failure = StateError('unselected');
    final mount = constructedSkippedMount(items);
    final runtime = Runtime();
    runtime.update(
        const LibraryName(['restage', 'core']),
        LocalWidgetLibrary({
          kBuilderContinuationWidgetName: buildRestageBuilderContinuation,
          'LayoutBuilder': f.buildLayoutBuilder,
          'SizedBox': f.buildSizedBox,
          'Text': f.buildText
        }));
    runtime.update(const LibraryName(['test']),
        rfw.parseLibraryFile(constructedSkippedSource));
    await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: RestageNativeValues(
            bindings: mount.bindings,
            child: RemoteWidget(
                runtime: runtime,
                data: DynamicContent({'context': mount.context}),
                widget: const FullyQualifiedWidgetName(
                    LibraryName(['test']), 'Root')))));
    expect(tester.takeException(), isNull);
    expect(items.reads, isEmpty);
    await tester.pumpWidget(const SizedBox());
    runtime.dispose();
  });
}
