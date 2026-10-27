import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:restage_shared/restage_shared.dart';

import 'fixtures/native_planner_source.dart';

class _NoCaptures implements ValueReader {
  @override
  Object? read(List<Object> path, ValueType type) => throw StateError('$path');
  @override
  int length(List<Object> path) => throw StateError('$path');
}

class _LoggedList extends ListBase<Object> {
  _LoggedList(this.items);
  final List<Object> items;
  final reads = <Object>[];
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
    return items[index];
  }

  @override
  void operator []=(int index, Object value) => items[index] = value;
}

NativeBinding<Object> _native(String type, Object value) =>
    NativeBinding(contract: NativeBindingContract(type: type), value: value);

void main() {
  testWidgets('inert selection keeps actual native values after replacement',
      (tester) async {
    final color = nativePlannerSelectColorAdapter();
    final coalesce = nativePlannerCoalesceColorAdapter();
    final callback = nativePlannerSelectCallbackAdapter();
    final key = nativePlannerSelectKeyAdapter();
    late BuildContext context;
    await tester.pumpWidget(RestageNativeValues(
        bindings: {
          nativePlannerSelectCallbackBinding:
              NativeBinding(contract: callback.contract, value: callback),
          nativePlannerSelectColorBinding:
              NativeBinding(contract: color.contract, value: color),
          nativePlannerCoalesceColorBinding:
              NativeBinding(contract: coalesce.contract, value: coalesce),
          nativePlannerSelectKeyBinding:
              NativeBinding(contract: key.contract, value: key),
        },
        child: Builder(builder: (value) {
          context = value;
          return const SizedBox();
        })));
    final operations = RestageNativeValues.operationsOf(context, {});
    Object? evaluate(ValueProgram program, Map<String, Object?> parameters) =>
        (ValueEvaluator(program,
                    captures: _NoCaptures(),
                    parameters: parameters,
                    operations: operations)
                .evaluate() as ValueNative)
            .value;
    final trace = <String>[];
    void first() => trace.add('first');
    void second() => trace.add('second');
    for (final flag in [true, false]) {
      final selected =
          evaluate(nativePlannerSelectCallbackProgram(operations), {
        'flag': flag,
        'first': _native('callback.selected', first),
        'second': _native('callback.selected', second),
      });
      expect(trace, isEmpty);
      expect(selected, same(flag ? first : second));
    }
    for (final swatch in [Colors.blue, Colors.green]) {
      final actual = evaluate(nativePlannerSelectColorProgram(operations), {
        'flag': true,
        'color': _native('flutter.Color', swatch),
      });
      expect(actual, same(swatch));
      expect((actual as MaterialColor).shade500, swatch.shade500);
      expect(
          evaluate(nativePlannerSelectColorProgram(operations), {
            'flag': false,
            'color': _native('flutter.Color', swatch),
          }),
          same(Colors.red));
      expect(
          evaluate(nativePlannerCoalesceColorProgram(operations), {
            'optional': _native('flutter.Color', swatch),
          }),
          same(swatch));
    }
    expect(
        evaluate(nativePlannerCoalesceColorProgram(operations), {
          'optional': null,
        }),
        same(Colors.red));
    for (final nativeKey in [GlobalKey(), ObjectKey(Object())]) {
      expect(
          evaluate(nativePlannerSelectKeyProgram(operations), {
            'flag': true,
            'key': _native('flutter.Key', nativeKey),
          }),
          same(nativeKey));
      expect(
          evaluate(nativePlannerSelectKeyProgram(operations), {
            'flag': false,
            'key': _native('flutter.Key', nativeKey),
          }),
          same(const ValueKey<String>('fallback')));
    }
  });

  testWidgets(
      'generated adapters preserve native identity, demand and live frames',
      (tester) async {
    final closure = nativePlannerClosureAdapter();
    final key = nativePlannerKeyAdapter();
    final color = nativePlannerColorAdapter();
    final reassign = nativePlannerReassignAdapter();
    final nullable = nativePlannerNullableAdapter();
    final staticClosure = nativePlannerStaticAdapter();
    final interpolation = nativePlannerInterpolationAdapter();
    late BuildContext context;
    await tester.pumpWidget(RestageNativeValues(
        bindings: {
          nativePlannerInterpolationBinding: NativeBinding(
              contract: interpolation.contract, value: interpolation),
          nativePlannerStaticBinding: NativeBinding(
              contract: staticClosure.contract, value: staticClosure),
          nativePlannerClosureBinding:
              NativeBinding(contract: closure.contract, value: closure),
          nativePlannerKeyBinding:
              NativeBinding(contract: key.contract, value: key),
          nativePlannerColorBinding:
              NativeBinding(contract: color.contract, value: color),
          nativePlannerReassignBinding:
              NativeBinding(contract: reassign.contract, value: reassign),
          nativePlannerNullableBinding:
              NativeBinding(contract: nullable.contract, value: nullable),
        },
        child: Builder(builder: (value) {
          context = value;
          return const SizedBox();
        })));
    final operations = RestageNativeValues.operationsOf(context, {});
    Object? evaluate(ValueProgram program, Map<String, Object?> parameters,
            {ValueLocalFrame? frame}) =>
        ValueEvaluator(program,
                captures: _NoCaptures(),
                parameters: parameters,
                operations: operations,
                context: ValueOperationContext(
                    frame: frame, locals: frame?.visibleTypes ?? {}))
            .evaluate();
    final interpolationFrame = ValueLocalFrame({'counter': ValueType.integer})
      ..write('counter', 3);
    final interpolationContext = ValueOperationContext(
        frame: interpolationFrame, locals: interpolationFrame.visibleTypes);
    final generatedInterpolation = (evaluate(
            nativePlannerInterpolationProgram(operations,
                context: interpolationContext),
            {},
            frame: interpolationFrame) as ValueNative)
        .value as String Function();
    final nativeInterpolation = authoredInterpolation(3);
    expect(generatedInterpolation(), nativeInterpolation());
    expect(generatedInterpolation(), nativeInterpolation());
    expect(generatedInterpolation(), 'count:5:5');
    final generatedStatic =
        (evaluate(nativePlannerStaticProgram(operations), {}) as ValueNative)
            .value as int Function();
    expect(generatedStatic(), NativePlannerStatics().x()());
    expect(generatedStatic(), 14);
    final first = Object();
    final second = Object();
    final items = _LoggedList([first, second]);
    expect(items.reads, isEmpty);

    final keyProgram = nativePlannerKeyProgram(operations);
    final skipped = ValueProgram(nodes: [
      ...keyProgram.nodes,
      const ValueNode('literal', ValueType.boolean, value: false),
      const ValueNode('literal', ValueType.nullType),
      ValueNode(
          'conditional', const ValueType.native('flutter.Key', nullable: true),
          inputs: [
            keyProgram.nodes.length,
            keyProgram.root,
            keyProgram.nodes.length + 1
          ]),
    ], root: keyProgram.nodes.length + 2, parameters: keyProgram.parameters);
    final keyParameters = {
      'items': _native('dart.List<Object>', items),
      'index': 1
    };
    expect(evaluate(skipped, keyParameters), isNull);
    expect(items.reads, isEmpty);
    final generatedKey =
        (evaluate(keyProgram, keyParameters) as ValueNative).value as ObjectKey;
    expect(generatedKey.value, same(second));
    expect(items.reads, [1]);
    expect(generatedKey, authoredKey(items, 1));
    expect(items.reads, [1, 1]);

    final frame = ValueLocalFrame({'counter': ValueType.integer})
      ..write('counter', 0);
    final seen = <TapDownDetails>[];
    final parameters = {
      'items': _native('dart.List<Object>', items),
      'seen': _native(
          'callback.seen', (TapDownDetails details) => seen.add(details)),
    };
    ObjectKey Function(TapDownDetails) make(ValueLocalFrame frame) => (evaluate(
            nativePlannerClosureProgram(operations,
                context: ValueOperationContext(
                    frame: frame, locals: frame.visibleTypes)),
            parameters,
            frame: frame) as ValueNative)
        .value as ObjectKey Function(TapDownDetails);
    final callback = make(frame);
    final sibling = make(frame);
    final otherFrame = ValueLocalFrame({'counter': ValueType.integer})
      ..write('counter', 0);
    final independent = make(otherFrame);
    final details = TapDownDetails(globalPosition: const Offset(3, 4));
    expect(frame.read('counter'), 0);
    expect(callback(details).value, same(first));
    expect(sibling(details).value, same(second));
    expect(frame.read('counter'), 2);
    expect(independent(details).value, same(first));
    expect(otherFrame.read('counter'), 1);
    expect(seen.every((value) => identical(value, details)), isTrue);
    frame.write('counter', 0);
    expect(callback(details).value, same(first));
    final nativeSeen = <TapDownDetails>[];
    final nativeCallback = authoredClosure([first, second], 0, nativeSeen.add);
    expect(nativeCallback(details).value, same(first));
    expect(nativeCallback(details).value, same(second));
    expect(nativeSeen.every((value) => identical(value, details)), isTrue);

    final swatch = <int, Color>{500: const Color(0xff102030)};
    MaterialColor construct() =>
        (evaluate(nativePlannerColorProgram(operations), {
          'swatch': _native('dart.Map<int,Color>', swatch),
        }) as ValueNative)
            .value as MaterialColor;
    final generatedColor = construct();
    final otherColor = construct();
    final nativeColor = authoredColor(swatch);
    expect(identical(generatedColor, otherColor), isFalse);
    swatch[500] = const Color(0xffabcdef);
    expect(generatedColor[500], same(nativeColor[500]));
    expect(otherColor[500], same(nativeColor[500]));
    expect(nativePlannerConstant(), same(authoredConstant()));

    final objectFrame =
        ValueLocalFrame({'object': const ValueType.native('dart.Object')})
          ..write('object', _native('dart.Object', first));
    final replacement = (evaluate(
            nativePlannerReassignProgram(operations,
                context: ValueOperationContext(
                    frame: objectFrame, locals: objectFrame.visibleTypes)),
            {'replacement': _native('dart.Object', second)},
            frame: objectFrame) as ValueNative)
        .value as ObjectKey Function();
    expect(replacement().value, same(first));
    expect((objectFrame.read('object') as ValueNative).value, same(second));
    expect(replacement().value, same(second));
    final nullableProgram = nativePlannerNullableProgram(operations);
    expect(evaluate(nullableProgram, {'model': null}), isNull);
    expect(
        ((evaluate(nullableProgram, {'model': _native('dart.Object', first)})
                    as ValueNative)
                .value as ObjectKey)
            .value,
        same(first));
  });
}
