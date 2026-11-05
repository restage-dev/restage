import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:restage_core/src/registration.g.dart'
    show buildLayoutBuilder, buildRow;
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart' as rfw;
import 'package:rfw/rfw.dart';

const _keyContract = NativeBindingContract(type: 'flutter.Key');
const _nullableKey = NativeBindingContract(type: 'flutter.Key', nullable: true);
const _program = BuilderProgram(
  values: ValueProgram(
      nodes: [
        ValueNode('capture', nativeBindingReferenceValueType, name: 'key')
      ],
      root: 0,
      captures: {'key': nativeBindingReferenceValueType}),
  result: BuilderResult.body(0, key: 0, keyType: 'nativeBinding'),
  bodyCount: 1,
);

class _EqualModel {
  @override
  bool operator ==(Object other) => other is _EqualModel;
  @override
  int get hashCode => 1;
}

class _Harness {
  _Harness(
      {this.lazy = true, this.duplicate = false, this.checkIndex = false}) {
    runtime.update(
        const LibraryName(['test', 'native']),
        LocalWidgetLibrary({
          kBuilderContinuationWidgetName: buildRestageBuilderContinuation,
          'Item': (context, source) => AnimatedContainer(
                key: RestageDecoders.nativeKey(context, source, ['key']),
                duration: Duration.zero,
                width: 20,
                height: 20,
              ),
          'Lazy': (context, source) =>
              RestageBuilderBinding.construct((bindings) {
                final binding = RestageBuilderBinding(source, ['builder'],
                    context: context);
                bindings.add(binding);
                final indexBinding = checkIndex
                    ? RestageBuilderBinding(source, ['findIndex'],
                        context: context,
                        scalarContract: const ScalarCallbackContract(
                            parameters: [ScalarCallbackParameter.valueKey]))
                    : null;
                if (indexBinding != null) bindings.add(indexBinding);
                return LayoutBuilder(builder: (context, constraints) {
                  final child = binding.build(context, {});
                  projected = child.key;
                  if (indexBinding != null)
                    indexResult = indexBinding.evaluateKey(context, child.key!);
                  return child;
                });
              }),
          'Row': (context, source) => Row(children: [
                for (final child in source.childList(['children']))
                  Expanded(child: child)
              ]),
        }));
    const body = 'Item(key:data.key)';
    const parameterType =
        ValueType('record', fields: {'int': ValueType.integer});
    const indexProgram = ValueProgram(
        nodes: [
          ValueNode('parameter', parameterType, name: 'arg0'),
          ValueNode('field', ValueType.integer, inputs: [0], name: 'int'),
        ],
        root: 1,
        parameters: {'arg0': parameterType});
    final indexSlot = checkIndex
        ? ',findIndex:$kBuilderContinuationWidgetName(version:1,program:${jsonEncode(indexProgram.encode())},captures:{})'
        : '';
    final item = lazy
        ? 'Lazy(builder:$kBuilderContinuationWidgetName(version:1,program:${jsonEncode(_program.encode())},captures:{key:data.key},bodies:[(frame)=>$body])$indexSlot)'
        : body;
    runtime.update(
        const LibraryName(['test']),
        rfw.parseLibraryFile(
            'import test.native; widget Root = ${duplicate ? 'Row(children:[$item,$item])' : item};'));
  }
  final bool lazy;
  final bool duplicate;
  final bool checkIndex;
  Object? indexResult;
  final runtime = Runtime();
  final data = DynamicContent({'key': _keyContract.reference('item')});
  Key? projected;
  Widget mount(Key? key, {bool nullable = false, bool right = false}) {
    data.update(
        'key', (nullable ? _nullableKey : _keyContract).reference('item'));
    final remote = RemoteWidget(
        runtime: runtime,
        data: data,
        widget: const FullyQualifiedWidgetName(LibraryName(['test']), 'Root'));
    return Directionality(
        textDirection: TextDirection.ltr,
        child: RestageNativeValues(
            bindings: {
              'item': NativeBinding(
                  contract: nullable ? _nullableKey : _keyContract, value: key)
            },
            child: Row(children: [
              Expanded(child: right ? const SizedBox() : remote),
              Expanded(child: right ? remote : const SizedBox()),
            ])));
  }

  void dispose() {
    runtime.dispose();
  }
}

void main() {
  for (final form in ['spread', 'helper', 'widget']) {
    testWidgets(
        'compiled collection aliases preserve native reorder form=$form',
        (tester) async {
      final first = ObjectKey(_EqualModel());
      final second = ObjectKey(_EqualModel());
      Widget item(Key key) => AnimatedContainer(
          key: key, duration: Duration.zero, width: 20, height: 20);
      Widget native(bool reverse) {
        final left = [item(first)];
        final right = [item(second)];
        return Directionality(
            textDirection: TextDirection.ltr,
            child: Row(children: [
              ...(reverse ? [...right, ...left] : [...left, ...right])
            ]));
      }

      await tester.pumpWidget(native(false));
      final nativeFirst = tester.state(find.byKey(first));
      final nativeSecond = tester.state(find.byKey(second));
      await tester.pumpWidget(native(true));
      expect(tester.state(find.byKey(first)), same(nativeFirst));
      expect(tester.state(find.byKey(second)), same(nativeSecond));
      final expectedFirstPosition = tester.getTopLeft(find.byKey(first));
      final expectedSecondPosition = tester.getTopLeft(find.byKey(second));
      await tester.pumpWidget(const SizedBox());

      final fixture = jsonDecode(File(
              'test/fixtures/native_key_spread${form == 'spread' ? '' : '_$form'}.json')
          .readAsStringSync()) as Map<String, dynamic>;
      final slots = fixture['slots'] as Map<String, dynamic>;
      final runtime = Runtime();
      runtime.update(
          const LibraryName(['restage', 'core']),
          LocalWidgetLibrary({
            kBuilderContinuationWidgetName: buildRestageBuilderContinuation,
            'Row': buildRow,
            'AnimatedContainer': (context, source) =>
                item(RestageDecoders.nativeKey(context, source, ['key'])!),
          }));
      runtime.update(const LibraryName(['test']),
          rfw.parseLibraryFile(fixture['source'] as String));
      Map<String, Object> context(bool reverse) => {
            slots['this.first'] as String: _keyContract.reference('first'),
            slots['this.second'] as String: _keyContract.reference('second'),
            'reverse': reverse,
          };
      final data = DynamicContent({'context': context(false)});
      await tester.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: RestageNativeValues(
              bindings: {
                'first': NativeBinding(contract: _keyContract, value: first),
                'second': NativeBinding(contract: _keyContract, value: second),
              },
              child: RemoteWidget(
                  runtime: runtime,
                  data: data,
                  widget: const FullyQualifiedWidgetName(
                      LibraryName(['test']), 'Root')))));
      expect(tester.takeException(), isNull);
      final remoteFirst = tester.state(find.byKey(first));
      final remoteSecond = tester.state(find.byKey(second));
      data.update('context', context(true));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(tester.state(find.byKey(first)), same(remoteFirst));
      expect(tester.state(find.byKey(second)), same(remoteSecond));
      expect(tester.getTopLeft(find.byKey(first)), expectedFirstPosition);
      expect(tester.getTopLeft(find.byKey(second)), expectedSecondPosition);
      await tester.pumpWidget(const SizedBox());
      runtime.dispose();
    });
  }

  testWidgets(
      'unused helper arguments throw in native source order before child construction',
      (tester) async {
    final key = ObjectKey(Object());
    var childConstructions = 0;
    Widget item(Key key) {
      childConstructions++;
      return AnimatedContainer(
          key: key, duration: Duration.zero, width: 20, height: 20);
    }

    List<Widget> childrenFor(Key key,
            {required int later, required int earlier}) =>
        [item(key)];
    final fixture = jsonDecode(
        File('test/fixtures/native_key_helper_arguments.json')
            .readAsStringSync()) as Map<String, dynamic>;
    final runtime = Runtime();
    runtime.update(
        const LibraryName(['restage', 'core']),
        LocalWidgetLibrary({
          kBuilderContinuationWidgetName: buildRestageBuilderContinuation,
          'Row': buildRow,
          'LayoutBuilder': buildLayoutBuilder,
          'AnimatedContainer': (context, source) =>
              item(RestageDecoders.nativeKey(context, source, ['key'])!),
        }));
    runtime.update(const LibraryName(['test']),
        rfw.parseLibraryFile(fixture['source'] as String));
    for (final values in [(0, 2), (1, 2), (1, 0)]) {
      childConstructions = 0;
      final native = Directionality(
          textDirection: TextDirection.ltr,
          child: LayoutBuilder(
              builder: (context, constraints) => Row(
                  children: childrenFor(key,
                      earlier: 1 ~/ values.$1, later: [0][values.$2]))));
      expect(childConstructions, 0);
      await tester.pumpWidget(native);
      final nativeError = tester.takeException();
      if (values.$1 == 0)
        expect(nativeError, isA<IntegerDivisionByZeroException>());
      else if (values.$2 == 2)
        expect(nativeError, isA<RangeError>());
      else
        expect(nativeError, isNull);
      final nativeConstructions = childConstructions;
      expect(nativeConstructions, nativeError == null ? 1 : 0);
      await tester.pumpWidget(const SizedBox());
      childConstructions = 0;
      final remote = Directionality(
          textDirection: TextDirection.ltr,
          child: RestageNativeValues(
              bindings: {
                'key': NativeBinding(contract: _keyContract, value: key),
              },
              child: RemoteWidget(
                  runtime: runtime,
                  data: DynamicContent({
                    'context': {
                      fixture['slot'] as String: _keyContract.reference('key'),
                      'zero': values.$1,
                      'index': values.$2,
                    }
                  }),
                  widget: const FullyQualifiedWidgetName(
                      LibraryName(['test']), 'Root'))));
      expect(childConstructions, 0);
      await tester.pumpWidget(remote);
      final remoteError = tester.takeException();
      if (nativeError is RangeError) {
        expect(remoteError, isA<RangeError>());
        final range = remoteError! as RangeError;
        expect(range.invalidValue, nativeError.invalidValue);
        expect(range.start, nativeError.start);
        expect(range.end, nativeError.end);
      } else {
        expect(remoteError?.runtimeType, nativeError?.runtimeType);
      }
      expect(childConstructions, nativeConstructions);
      if (remoteError == null)
        expect(
            tester.widget<AnimatedContainer>(find.byKey(key)).key, same(key));
      await tester.pumpWidget(const SizedBox());
    }
    runtime.dispose();
  });

  testWidgets(
      'retained native key projection and body use the same installed map',
      (tester) async {
    RestageBuilderBinding? retained;
    Key? projected;
    final runtime = Runtime();
    runtime.update(
        const LibraryName(['test', 'native']),
        LocalWidgetLibrary({
          kBuilderContinuationWidgetName: buildRestageBuilderContinuation,
          'Host': (context, source) {
            retained ??=
                RestageBuilderBinding(source, ['slot'], context: context);
            return LayoutBuilder(builder: (context, constraints) {
              final child = retained!.build(context, {});
              projected = RestageBuilderBinding.originalKey(child.key!);
              return child;
            });
          },
          'Item': (context, source) => AnimatedContainer(
              key: RestageDecoders.nativeKey(context, source, ['key']),
              duration: Duration.zero,
              width: 20,
              height: 20),
        }));
    runtime.update(
        const LibraryName(['test']),
        rfw.parseLibraryFile(
            'import test.native; widget Root = Host(slot: $kBuilderContinuationWidgetName(version:1,program:${jsonEncode(_program.encode())},captures:{key:data.key},bodies:[(frame)=>Item(key:data.key)]));'));
    final data = DynamicContent({'key': _keyContract.reference('item')});
    Widget tree(Key key) => Directionality(
        textDirection: TextDirection.ltr,
        child: RestageNativeValues(
            bindings: {
              'item': NativeBinding(contract: _keyContract, value: key),
            },
            child: RemoteWidget(
                runtime: runtime,
                data: data,
                widget: const FullyQualifiedWidgetName(
                    LibraryName(['test']), 'Root'))));
    final original = ObjectKey(Object());
    final replacement = ObjectKey(Object());
    await tester.pumpWidget(tree(original));
    expect(tester.takeException(), isNull);
    final state = tester.state(find.byKey(original));
    expect(projected, same(original));
    await tester.pumpWidget(tree(replacement));
    expect(tester.takeException(), isNull);
    expect(projected, same(original));
    expect(tester.state(find.byKey(original)), same(state));
    expect(find.byKey(replacement), findsNothing);
    await tester.pumpWidget(const SizedBox());
    retained!.dispose();
    runtime.dispose();
  });

  testWidgets('child-index callbacks receive the original native ValueKey',
      (tester) async {
    final harness = _Harness(checkIndex: true);
    const key = ValueKey<int>(7);
    await tester.pumpWidget(harness.mount(key));
    expect(tester.takeException(), isNull);
    expect(harness.indexResult, key.value);
    expect(RestageBuilderBinding.originalKey(harness.projected!), same(key));
    await tester.pumpWidget(const SizedBox());
    harness.dispose();
  });

  testWidgets('native key decoder distinguishes omitted and malformed inputs',
      (tester) async {
    for (final value in [
      null,
      0,
      1.0,
      false,
      'bad',
      <Object?>[],
      <String, Object?>{}
    ]) {
      final harness = _Harness(lazy: false);
      await tester.pumpWidget(harness.mount(const ValueKey(1)));
      if (value == null) {
        harness.runtime.update(const LibraryName(['test']),
            rfw.parseLibraryFile('import test.native; widget Root = Item();'));
      } else {
        harness.data.update('key', value);
      }
      await tester.pump();
      expect(tester.takeException(),
          value == null ? isNull : isA<FormatException>());
      if (value == null)
        expect(
            tester
                .widget<AnimatedContainer>(find.byType(AnimatedContainer))
                .key,
            isNull);
      await tester.pumpWidget(const SizedBox());
      harness.dispose();
    }
  });

  testWidgets('compiled borrowed key reaches the native callback body',
      (tester) async {
    final fixture =
        jsonDecode(File('test/fixtures/native_key.json').readAsStringSync())
            as Map<String, dynamic>;
    final runtime = Runtime();
    runtime.update(
        const LibraryName(['restage', 'core']),
        LocalWidgetLibrary({
          kBuilderContinuationWidgetName: buildRestageBuilderContinuation,
          'LayoutBuilder': buildLayoutBuilder,
          'Text': (context, source) => Text(source.v<String>(['text'])!,
              key: RestageDecoders.nativeKey(context, source, ['key'])),
        }));
    runtime.update(const LibraryName(['test']),
        rfw.parseLibraryFile(fixture['source'] as String));
    final key = GlobalKey();
    final data = DynamicContent({
      'context': {fixture['slot'] as String: _keyContract.reference('item')}
    });
    await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: RestageNativeValues(
            bindings: {
              'item': NativeBinding(contract: _keyContract, value: key)
            },
            child: RemoteWidget(
                runtime: runtime,
                data: data,
                widget: const FullyQualifiedWidgetName(
                    LibraryName(['test']), 'Root')))));
    expect(tester.takeException(), isNull);
    final native = tester.widget<Text>(find.text('item'));
    expect(native.key, same(key));
    expect(key.currentWidget, same(native));
    expect(key.currentContext, same(tester.element(find.text('item'))));
    await tester.pumpWidget(const SizedBox());
    runtime.dispose();
  });

  testWidgets('borrowed ObjectKey collection reorders native state',
      (tester) async {
    const keysType = ValueType('list', item: nativeBindingReferenceValueType);
    const program = BuilderProgram(
      values: ValueProgram(
          nodes: [
            ValueNode('capture', keysType, name: 'keys'),
            ValueNode('length', ValueType.integer, inputs: [0]),
            ValueNode('parameter', ValueType.integer, name: 'index'),
            ValueNode('index', nativeBindingReferenceValueType, inputs: [0, 2]),
            ValueNode('field', ValueType.string, inputs: [3], name: 'key'),
          ],
          root: 4,
          captures: {'keys': keysType},
          parameters: {'index': ValueType.integer}),
      result: BuilderResult.forEach(
          1,
          'index',
          BuilderResult.body(0,
              values: {'slot': 4}, key: 3, keyType: 'nativeBinding')),
      bodyCount: 1,
      collection: true,
    );
    final harness = _Harness();
    final runtime = harness.runtime;
    runtime.update(
        const LibraryName(['test', 'collection']),
        LocalWidgetLibrary({
          'Collection': (context, source) =>
              RestageBuilderBinding.construct((bindings) {
                final binding =
                    RestageBuilderBinding(source, ['items'], context: context);
                bindings.add(binding);
                return Row(children: binding.buildList(context, {}));
              }),
        }));
    runtime.update(const LibraryName(['test']), rfw.parseLibraryFile('''
import test.native;
import test.collection;
widget Root = Collection(items: $kBuilderContinuationWidgetName(
  version: 1, program: ${jsonEncode(program.encode())}, captures: {keys:data.keys},
  bodies: [(frame) => Item(key: {kind: "nativeBinding", type: "flutter.Key", nullable: false, key: frame.values.slot})]));
'''));
    final first = ObjectKey(_EqualModel());
    final second = ObjectKey(_EqualModel());
    final a = _keyContract.reference('a');
    final b = _keyContract.reference('b');
    harness.data.update('keys', [a, b]);
    await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: RestageNativeValues(
            bindings: {
              'a': NativeBinding(contract: _keyContract, value: first),
              'b': NativeBinding(contract: _keyContract, value: second),
            },
            child: RemoteWidget(
                runtime: runtime,
                data: harness.data,
                widget: const FullyQualifiedWidgetName(
                    LibraryName(['test']), 'Root')))));
    expect(tester.takeException(), isNull);
    final stateA = tester.state(find.byKey(first));
    final stateB = tester.state(find.byKey(second));
    final xA = tester.getTopLeft(find.byKey(first)).dx;
    final xB = tester.getTopLeft(find.byKey(second)).dx;
    harness.data.update('keys', [b, a]);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(tester.state(find.byKey(first)), same(stateA));
    expect(tester.state(find.byKey(second)), same(stateB));
    expect(tester.getTopLeft(find.byKey(first)).dx, xB);
    expect(tester.getTopLeft(find.byKey(second)).dx, xA);
    await tester.pumpWidget(const SizedBox());
    harness.dispose();
  });

  for (final lazy in [false, true]) {
    testWidgets(
        'native GlobalKey reaches actual widget and survives reparent lazy=$lazy',
        (tester) async {
      final key = GlobalKey<State<AnimatedContainer>>();
      final harness = _Harness(lazy: lazy);
      await tester.pumpWidget(harness.mount(key));
      expect(tester.takeException(), isNull);
      final state = key.currentState!;
      final element = key.currentContext!;
      expect(key.currentWidget, isA<AnimatedContainer>());
      expect(key.currentWidget!.key, same(key));
      expect(state.widget, same(key.currentWidget));
      expect(state.context, same(element));
      if (lazy) {
        expect(harness.projected, isA<LocalKey>());
        expect(
            RestageBuilderBinding.originalKey(harness.projected!), same(key));
      }
      await tester.pumpWidget(harness.mount(key, right: true));
      expect(tester.takeException(), isNull);
      expect(key.currentState, same(state));
      expect(key.currentContext, same(element));
      await tester.pumpWidget(const SizedBox());
      expect(key.currentState, isNull);
      harness.dispose();
    });
  }
  testWidgets('borrowed ObjectKey preserves identity and replacement',
      (tester) async {
    final first = _EqualModel();
    final equal = _EqualModel();
    expect(first, equal);
    final key = ObjectKey(first);
    final harness = _Harness();
    await tester.pumpWidget(harness.mount(key));
    final state = tester.state(find.byType(AnimatedContainer));
    final projection = harness.projected;
    expect(tester.widget<AnimatedContainer>(find.byType(AnimatedContainer)).key,
        same(key));
    await tester.pumpWidget(harness.mount(ObjectKey(first)));
    expect(harness.projected, projection);
    expect(tester.state(find.byType(AnimatedContainer)), same(state));
    await tester.pumpWidget(harness.mount(ObjectKey(equal)));
    expect(harness.projected, isNot(projection));
    expect(tester.state(find.byType(AnimatedContainer)), isNot(same(state)));
    await tester.pumpWidget(const SizedBox());
    harness.dispose();
  });
  testWidgets('present-null native key leaves native and wrapper unkeyed',
      (tester) async {
    final harness = _Harness();
    await tester.pumpWidget(harness.mount(null, nullable: true));
    expect(tester.takeException(), isNull);
    expect(harness.projected, isNull);
    expect(tester.widget<AnimatedContainer>(find.byType(AnimatedContainer)).key,
        isNull);
    await tester.pumpWidget(const SizedBox());
    harness.dispose();
  });
  testWidgets('duplicate native GlobalKeys retain Flutter failure',
      (tester) async {
    final failures = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError =
        (details) => failures.add(details.exceptionAsString());
    try {
      final key = GlobalKey<State<AnimatedContainer>>();
      final harness = _Harness(duplicate: true);
      await tester.pumpWidget(harness.mount(key));
      await tester.pumpWidget(const SizedBox());
      expect(failures, isNotEmpty);
      final remoteFailure = failures.join('\n');
      harness.dispose();
      failures.clear();
      await tester.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: Row(children: [
            for (var index = 0; index < 2; index++)
              Expanded(
                  child: LayoutBuilder(
                      builder: (context, constraints) => AnimatedContainer(
                          key: key,
                          duration: Duration.zero,
                          width: 20,
                          height: 20)))
          ])));
      await tester.pumpWidget(const SizedBox());
      expect(failures, isNotEmpty);
      expect(remoteFailure, failures.join('\n'));
      expect(remoteFailure, contains('Failed assertion'));
    } finally {
      FlutterError.onError = previous;
    }
  });
}
