import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart' as rfw;
import 'package:rfw/rfw.dart';

const _keyType = ValueType.native('flutter.Key');
const _keyValue = NativeBindingContract(type: 'flutter.Key');
const _callbackType = ValueType.native('void Function(flutter.TapDownDetails)');
const _callbackValue =
    NativeBindingContract(type: 'void Function(flutter.TapDownDetails)');
const _callbackCall = NativeBindingContract(
    type: 'installed.callback',
    call: NativeCallContract(
        inputs: [],
        captures: {'count': ValueType.integer},
        result: _callbackType,
        implementation: 'callback-v1'));
const _keyCall = NativeBindingContract(
    type: 'installed.key',
    call: NativeCallContract(
        inputs: [], result: _keyType, implementation: 'key-v1'));

ValueNode _call(NativeBindingContract contract, String binding,
        {Map<String, String> captures = const {},
        List<int> inputs = const []}) =>
    ValueNode('native.call', contract.call!.result, inputs: inputs, value: {
      'binding': binding,
      'contract': contract.toJson(),
      'captures': captures
    });

class _EmptyReader implements ValueReader {
  @override
  Object? read(List<Object> path, ValueType type) =>
      throw StateError('Unexpected read');
  @override
  int length(List<Object> path) => throw StateError('Unexpected length');
}

class _Source extends Fake implements DataSource {
  _Source(this.values);
  final Object? values;
  Object? at(List<Object> path) {
    var value = values;
    for (final key in path) {
      if (value is! Map) return null;
      value = value[key];
    }
    return value;
  }

  @override
  bool isMap(List<Object> path) => at(path) is Map;
  @override
  bool isList(List<Object> path) => at(path) is List;
  @override
  T? v<T extends Object>(List<Object> path) {
    if (T == Object || T == Key)
      throw StateError('Native values cannot use DataSource.v');
    final value = at(path);
    return value is T ? value : null;
  }
}

void main() {
  testWidgets('installed call runs at demand and returns the original real Key',
      (tester) async {
    final model = Object();
    var calls = 0;
    final adapter = NativeCallAdapter(_keyCall, (inputs, captures) {
      calls++;
      return NativeBinding(contract: _keyValue, value: ObjectKey(model));
    });
    final program = ValueProgram(nodes: [_call(_keyCall, 'key')], root: 0);
    late BuildContext host;
    await tester.pumpWidget(RestageNativeValues(
        bindings: {
          'key': NativeBinding(contract: _keyCall, value: adapter),
        },
        child: Builder(builder: (context) {
          host = context;
          return const SizedBox();
        })));
    expect(calls, 0);
    final source = RestageValueBinding.dataSource(
        _Source({
          'version': 1,
          'program': program.encode(),
          'captures': <String, Object?>{},
        }),
        host);
    final first = RestageDecoders.nativeBinding<Key>(host, source, [],
        type: 'flutter.Key')! as ObjectKey;
    expect(first.value, same(model));
    expect(calls, 1);
    expect(
        RestageDecoders.nativeBinding<Key>(host, source, [],
            type: 'flutter.Key'),
        same(first));
    expect(calls, 1);
    expect(source.v<String>([]), isNull);
    expect(calls, 1);
  });

  testWidgets(
      'native closures share live creation cells and keep native details',
      (tester) async {
    final received = <(TapDownDetails, int)>[];
    var factories = 0;
    final adapter = NativeCallAdapter(_callbackCall, (inputs, captures) {
      factories++;
      final count = captures['count']!.cast<int>();
      return NativeBinding(
          contract: _callbackValue,
          value: (TapDownDetails detail) {
            received.add((detail, count.value++));
          });
    });
    late Map<String, ValueOperation> operations;
    await tester.pumpWidget(RestageNativeValues(
        bindings: {
          'callback': NativeBinding(contract: _callbackCall, value: adapter),
        },
        child: Builder(builder: (context) {
          operations = RestageNativeValues.operationsOf(context, {});
          return const SizedBox();
        })));
    expect(factories, 0);
    final program = ValueProgram(
        nodes: [
          _call(_callbackCall, 'callback', captures: {'count': 'counter'})
        ],
        root: 0,
        outerLocals: {'counter': ValueType.integer});
    final frame = ValueLocalFrame({'counter': ValueType.integer})
      ..write('counter', 0);
    GestureTapDownCallback create(ValueLocalFrame owner) =>
        (ValueEvaluator(program,
                    captures: _EmptyReader(),
                    parameters: {},
                    operations: operations,
                    parentFrame: owner)
                .evaluate()! as ValueNative)
            .value! as GestureTapDownCallback;
    final first = create(frame);
    final second = create(frame);
    expect(first, isNot(same(second)));
    frame.write('counter', 5);
    final detail = TapDownDetails(globalPosition: const Offset(3, 7));
    first(detail);
    second(detail);
    expect(received.map((entry) => entry.$2), [5, 6]);
    expect(received.every((entry) => identical(entry.$1, detail)), isTrue);
    expect(frame.read('counter'), 7);
    final other = ValueLocalFrame({'counter': ValueType.integer})
      ..write('counter', 30);
    create(other)(detail);
    first(detail);
    expect(received.map((entry) => entry.$2), [5, 6, 30, 7]);
    expect(factories, 3);
  });

  testWidgets('missing, incompatible and invalid implementations fail closed',
      (tester) async {
    final program = ValueProgram(nodes: [_call(_keyCall, 'key')], root: 0);
    late Map<String, ValueOperation> operations;
    Future<void> install(Object value) => tester.pumpWidget(RestageNativeValues(
            bindings: {
              'key': NativeBinding(contract: _keyCall, value: value),
            },
            child: Builder(builder: (context) {
              operations = RestageNativeValues.operationsOf(context, {});
              return const SizedBox();
            })));
    Object? evaluate() => ValueEvaluator(program,
            captures: _EmptyReader(), parameters: {}, operations: operations)
        .evaluate();
    await install(Object());
    expect(evaluate, throwsFormatException);
    await install(NativeCallAdapter(_callbackCall, (_, __) => null));
    expect(evaluate, throwsFormatException);
    await install(NativeCallAdapter(_keyCall, (_, __) => 'not a native key'));
    expect(evaluate, throwsStateError);
    await install(NativeCallAdapter(
        _keyCall,
        (_, __) => NativeBinding(
            contract: const NativeBindingContract(type: 'flutter.Color'),
            value: Object())));
    expect(evaluate, throwsStateError);
    operations = {
      'native.call': NativeCallValueOperation({'key': _keyCall})
    };
    expect(evaluate, throwsStateError);
    final failure = StateError('native constructor');
    await install(NativeCallAdapter(_keyCall, (_, __) => throw failure));
    expect(evaluate, throwsA(same(failure)));
  });

  test('native capture reads and writes real objects and actual null', () {
    const type = ValueType.native('flutter.Key', nullable: true);
    final frame = ValueLocalFrame({'key': type})..write('key', null);
    final capture = NativeCapture<Key?>(frame, 'key', type);
    final key = ObjectKey(Object());
    capture.value = key;
    expect(capture.value, same(key));
    expect((frame.read('key')! as ValueNative).value, same(key));
    capture.value = null;
    expect(frame.read('key'), isNull);
    expect(capture.value, isNull);
  });

  testWidgets('unselected calls stay dormant and native null coalesces',
      (tester) async {
    const nullableKey = ValueType.native('flutter.Key', nullable: true);
    const nullCall = NativeBindingContract(
        type: 'installed.null',
        call: NativeCallContract(
            inputs: [], result: nullableKey, implementation: 'null-v1'));
    var calls = 0;
    late Map<String, ValueOperation> operations;
    final key = ObjectKey(Object());
    await tester.pumpWidget(RestageNativeValues(
        bindings: {
          'null': NativeBinding(
              contract: nullCall,
              value: NativeCallAdapter(nullCall, (_, __) => null)),
          'key': NativeBinding(
              contract: _keyCall,
              value: NativeCallAdapter(_keyCall, (_, __) {
                calls++;
                return NativeBinding(contract: _keyValue, value: key);
              })),
        },
        child: Builder(builder: (context) {
          operations = RestageNativeValues.operationsOf(context, {});
          return const SizedBox();
        })));
    Object? evaluate(List<ValueNode> nodes) =>
        ValueEvaluator(ValueProgram(nodes: nodes, root: nodes.length - 1),
                captures: _EmptyReader(),
                parameters: {},
                operations: operations)
            .evaluate();
    expect(
        evaluate([
          const ValueNode('literal', ValueType.boolean, value: false),
          _call(_keyCall, 'key'),
          _call(nullCall, 'null'),
          const ValueNode('conditional', nullableKey, inputs: [0, 1, 2]),
        ]),
        isNull);
    expect(calls, 0);
    expect(
        (evaluate([
          _call(nullCall, 'null'),
          _call(_keyCall, 'key'),
          const ValueNode('??', _keyType, inputs: [0, 1]),
        ])! as ValueNative)
            .value,
        same(key));
    expect(calls, 1);
  });

  testWidgets(
      'deferred body reads its native cell without RFW object transport',
      (tester) async {
    final model = Object();
    final program = BuilderProgram(
        values: ValueProgram(
            nodes: [
              _call(_keyCall, 'key'),
              const ValueNode('local.write', _keyType,
                  inputs: [0], name: 'savedKey'),
            ],
            root: 1,
            locals: {'savedKey': _keyType}),
        result: const BuilderResult.body(0, values: {'native': 1}),
        bodyCount: 1);
    const remote = LibraryName(['native_test']);
    late RestageBuilderBinding binding;
    late BuildContext host;
    Key? seen;
    var calls = 0;
    final runtime = Runtime()
      ..update(
          const LibraryName(['restage', 'core']),
          LocalWidgetLibrary({
            kBuilderContinuationWidgetName: buildRestageBuilderContinuation,
            'Host': (context, source) {
              host = context;
              binding =
                  RestageBuilderBinding(source, ['slot'], context: context);
              return const SizedBox();
            },
            'Body': (context, source) {
              seen = RestageDecoders.nativeBinding<Key>(
                  context, source, ['key'],
                  type: 'flutter.Key');
              expect(source.v<String>(['leaked']), isNull);
              return SizedBox(key: seen);
            },
          }))
      ..update(
          remote,
          rfw.parseLibraryFile('import restage.core; widget Root = Host(slot: '
              '$kBuilderContinuationWidgetName(version: 1, program: ${jsonEncode(program.encode())}, captures: {}, '
              'bodies: [(frame) => Body(key: {kind: "nativeLocal", slot: "savedKey", type: "flutter.Key", nullable: false}, leaked: frame.values.native)]));'));
    addTearDown(runtime.dispose);
    Widget? body;
    late StateSetter update;
    await tester.pumpWidget(RestageNativeValues(
        bindings: {
          'key': NativeBinding(
              contract: _keyCall,
              value: NativeCallAdapter(_keyCall, (_, __) {
                calls++;
                return NativeBinding(
                    contract: _keyValue, value: ObjectKey(model));
              })),
        },
        child: StatefulBuilder(builder: (context, setState) {
          update = setState;
          return Column(children: [
            RemoteWidget(
                runtime: runtime,
                data: DynamicContent(),
                widget: const FullyQualifiedWidgetName(remote, 'Root')),
            if (body != null) body
          ]);
        })));
    expect(tester.takeException(), isNull);
    expect(calls, 0);
    body = binding.build(host, {});
    update(() {});
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect((seen! as ObjectKey).value, same(model));
    expect(calls, 1);
    binding.dispose();
  });
}
