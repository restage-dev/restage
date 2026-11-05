import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart' as rfw;
import 'package:rfw/rfw.dart';

class Source extends Fake implements DataSource {
  Source(this.data);
  final Map<String, Object?> data;
  Object? at(List<Object> path) {
    Object? v = data;
    for (final k in path) {
      if (v is! Map) return null;
      v = v[k];
    }
    return v;
  }

  @override
  bool isMap(List<Object> path) => at(path) is Map;
  @override
  bool isList(List<Object> path) => at(path) is List;
  @override
  T? v<T extends Object>(List<Object> path) {
    final value = at(path);
    return value is T ? value : null;
  }
}

class _CountingSource extends Fake implements DataSource {
  _CountingSource(this.source, this.onProgram);
  final DataSource source;
  final VoidCallback onProgram;
  @override
  T? v<T extends Object>(List<Object> path) {
    if (path.length == 1 && path.single == 'program') onProgram();
    return source.v<T>(path);
  }
}

void main() {
  testWidgets('scalar and key callbacks decode once for each invocation',
      (tester) async {
    const program = ValueProgram(
        nodes: [ValueNode('literal', ValueType.integer, value: 7)], root: 0);
    const remote = LibraryName(['decode_count']);
    late RestageBuilderBinding binding;
    late BuildContext host;
    var reads = 0;
    final runtime = Runtime()
      ..update(
          const LibraryName(['restage', 'core']),
          LocalWidgetLibrary({
            kBuilderContinuationWidgetName: (context, source) =>
                buildRestageBuilderContinuation(
                    context, _CountingSource(source, () => reads++)),
            'Host': (context, source) {
              host = context;
              binding =
                  RestageBuilderBinding(source, ['slot'], context: context);
              return const SizedBox();
            },
          }))
      ..update(
          remote,
          rfw.parseLibraryFile('import restage.core; widget Root = Host(slot: '
              '$kBuilderContinuationWidgetName(version: 1, program: ${jsonEncode(program.encode())}, captures: {}));'));
    addTearDown(runtime.dispose);
    await tester.pumpWidget(RemoteWidget(
        runtime: runtime,
        data: DynamicContent(),
        widget: const FullyQualifiedWidgetName(remote, 'Root')));
    expect(reads, 0);
    expect(binding.evaluate(host, {}), 7);
    expect(reads, 1);
    expect(binding.evaluateKey(host, const ValueKey<int>(1)), 7);
    expect(reads, 2);
    expect(binding.evaluateKey(host, const ValueKey<int>(2)), 7);
    expect(reads, 3);
    binding.dispose();
  });

  testWidgets('nullable native capture accepts actual null', (tester) async {
    late BuildContext host;
    await tester.pumpWidget(Builder(builder: (c) {
      host = c;
      return const SizedBox();
    }));
    const type = ValueType.native('flutter.Key', nullable: true);
    const p = ValueProgram(
        nodes: [ValueNode('capture', type, name: 'key')],
        root: 0,
        captures: {'key': type});
    final source = Source({
      'program': p.encode(),
      'version': 1,
      'captures': {'key': null}
    });
    expect(RestageValueBinding(source, []).evaluate(host), isNull);
    expect(
        RestageValueBinding(
            Source({'program': p.encode(), 'version': 1, 'captures': {}}),
            []).evaluate(host),
        isNull);
    for (final invalid in [
      1,
      1.5,
      true,
      'key',
      [],
      {},
      const NativeBindingContract(type: 'flutter.Key', nullable: true)
          .reference('missing')
    ]) {
      final malformed = Source({
        'program': p.encode(),
        'version': 1,
        'captures': {'key': invalid}
      });
      expect(() => RestageValueBinding(malformed, []).evaluate(host),
          throwsFormatException);
    }
  });
  testWidgets('only a reader of native values rebuilds when they change',
      (tester) async {
    const contract = NativeBindingContract(type: 'flutter.Key');
    final raw = Source({
      'text': 'plain',
      'key': contract.reference('key'),
    });
    var plainBuilds = 0;
    var nativeBuilds = 0;
    Key? read;
    // The same leaves each pump, so only a dependency rebuilds them.
    final leaves = Column(children: [
      _Leaf((context) {
        plainBuilds++;
        RestageValueBinding.dataSource(raw, context).v<String>(['text']);
      }),
      _Leaf((context) {
        nativeBuilds++;
        read = RestageValueBinding.readNative<Key>(
            RestageValueBinding.dataSource(raw, context), ['key'], context,
            type: 'flutter.Key');
      }),
    ]);
    Widget tree(Key key) => Directionality(
          textDirection: TextDirection.ltr,
          child: RestageNativeValues(
            bindings: {'key': NativeBinding(contract: contract, value: key)},
            child: leaves,
          ),
        );
    await tester.pumpWidget(tree(const ValueKey(1)));
    await tester.pumpWidget(tree(const ValueKey(2)));
    expect(read, const ValueKey(2));
    expect(nativeBuilds, 2);
    expect(plainBuilds, 1);
  });

  testWidgets('retained computed reader keeps its original installed map',
      (tester) async {
    const native = ValueType.native('flutter.Key');
    const valueContract = NativeBindingContract(type: 'flutter.Key');
    const callContract = NativeBindingContract(
        type: 'installed.key',
        call: NativeCallContract(
            inputs: [], result: native, implementation: 'key-v1'));
    final program = ValueProgram(nodes: [
      ValueNode('native.call', native, value: {
        'binding': 'make',
        'contract': callContract.toJson(),
        'captures': <String, String>{}
      })
    ], root: 0);
    const capture = ValueProgram(
        nodes: [ValueNode('capture', native, name: 'key')],
        root: 0,
        captures: {'key': native});
    final raw = Source({
      'computed': {'program': program.encode(), 'version': 1, 'captures': {}},
      'capture': {
        'program': capture.encode(),
        'version': 1,
        'captures': {'key': valueContract.reference('borrowed')}
      },
    });
    DataSource? retained;
    late BuildContext host;
    var calls = 0;
    Widget tree(Key key) => RestageNativeValues(
            bindings: {
              'make': NativeBinding(
                  contract: callContract,
                  value: NativeCallAdapter(callContract, (_, __) {
                    calls++;
                    return NativeBinding(contract: valueContract, value: key);
                  })),
              'borrowed': NativeBinding(contract: valueContract, value: key),
            },
            child: Builder(builder: (context) {
              host = context;
              retained ??= RestageValueBinding.dataSource(raw, context);
              return const SizedBox();
            }));
    final original = ObjectKey(Object());
    await tester.pumpWidget(tree(original));
    await tester.pumpWidget(tree(ObjectKey(Object())));
    expect(calls, 0);
    expect(
        RestageValueBinding.readNative<Key>(retained!, ['computed'], host,
            type: 'flutter.Key'),
        same(original));
    expect(
        (RestageValueBinding(retained!, ['capture']).evaluate(host)!
                as ValueNative)
            .value,
        same(original));
    expect(calls, 1);
  });

  for (final wrapped in [false, true]) {
    testWidgets(
        'deferred and nested bodies retain native bindings, wrapped $wrapped',
        (tester) async {
      const valueContract = NativeBindingContract(type: 'flutter.Key');
      const native = ValueType.native('flutter.Key');
      const callContract = NativeBindingContract(
          type: 'installed.key',
          call: NativeCallContract(
              inputs: [], result: native, implementation: 'key-v1'));
      final computed = ValueProgram(nodes: [
        ValueNode('native.call', native, value: {
          'binding': 'make',
          'contract': callContract.toJson(),
          'captures': <String, String>{}
        })
      ], root: 0);
      const capture = ValueProgram(
          nodes: [ValueNode('capture', native, name: 'key')],
          root: 0,
          captures: {'key': native});
      const builder = BuilderProgram(
          values: ValueProgram(
              nodes: [
                ValueNode('literal', ValueType.integer, value: 7),
                ValueNode('local.write', ValueType.integer,
                    inputs: [0], name: 'count')
              ],
              root: 1,
              locals: {'count': ValueType.integer}),
          result: BuilderResult.let(1, BuilderResult.body(0)),
          bodyCount: 1);
      const local = ValueProgram(
          nodes: [
            ValueNode('local.read', ValueType.integer, name: 'count'),
            ValueNode('string', ValueType.string, inputs: [0]),
          ],
          root: 1,
          outerLocals: {'count': ValueType.integer});
      String valueSlot(ValueProgram program, String captures) =>
          '{version: 1, program: ${jsonEncode(program.encode())}, captures: {$captures}}';
      final reference =
          '{kind: "nativeBinding", key: "borrowed", type: "flutter.Key", nullable: false}';
      final arguments =
          'computed: ${valueSlot(computed, '')}, borrowed: $reference, capture: ${valueSlot(capture, 'key: $reference')}, local: ${valueSlot(local, '')}';
      String slot(String body) =>
          '$kBuilderContinuationWidgetName(version: 1, program: ${jsonEncode(builder.encode())}, captures: {}, bodies: [(frame) => $body])';
      const remote = LibraryName(['scope']);
      final bindings = <RestageBuilderBinding>[];
      late RestageBuilderBinding binding;
      late RestageBuilderBinding nested;
      late BuildContext foreignHost;
      final seen = <Key?>[];
      DataSource? savedLocalReader;
      Widget leaf(BuildContext context, DataSource source) {
        savedLocalReader ??= RestageValueBinding.dataSource(source, context);
        final values =
            wrapped ? RestageValueBinding.dataSource(source, context) : source;
        for (final field in ['computed', 'borrowed', 'capture']) {
          seen.add(RestageDecoders.nativeBinding<Key>(context, values, [field],
              type: 'flutter.Key'));
        }
        return const SizedBox();
      }

      final runtime = Runtime()
        ..update(
            const LibraryName(['restage', 'core']),
            LocalWidgetLibrary({
              kBuilderContinuationWidgetName: buildRestageBuilderContinuation,
              'Host': (context, source) {
                binding =
                    RestageBuilderBinding(source, ['slot'], context: context);
                bindings.add(binding);
                return const SizedBox();
              },
              'Body': (context, source) {
                nested =
                    RestageBuilderBinding(source, ['nested'], context: context);
                bindings.add(nested);
                return leaf(context, source);
              },
              'Leaf': leaf,
            }))
        ..update(
            remote,
            rfw.parseLibraryFile(
                'import restage.core; widget Root = Host(slot: ${slot('Body($arguments, nested: ${slot('Leaf($arguments)')})')});'));
      addTearDown(runtime.dispose);
      final oldKey = ObjectKey(Object());
      final replacement = ObjectKey(Object());
      final moved = ObjectKey(Object());
      final calls = <Key>[];
      Widget scope(Key key, Widget child) => RestageNativeValues(bindings: {
            'make': NativeBinding(
                contract: callContract,
                value: NativeCallAdapter(callContract, (_, __) {
                  calls.add(key);
                  return NativeBinding(contract: valueContract, value: key);
                })),
            'borrowed': NativeBinding(contract: valueContract, value: key),
          }, child: child);
      Widget? body;
      Widget? nestedBody;
      Widget tree(Key key) => scope(
          key,
          Column(children: [
            RemoteWidget(
                runtime: runtime,
                data: DynamicContent(),
                widget: const FullyQualifiedWidgetName(remote, 'Root')),
            scope(moved, Builder(builder: (context) {
              foreignHost = context;
              return const SizedBox();
            })),
            if (body != null) scope(moved, body),
            if (nestedBody != null) scope(moved, nestedBody),
          ]));
      await tester.pumpWidget(tree(oldKey));
      final retained = binding;
      await tester.pumpWidget(tree(replacement));
      body = retained.build(foreignHost, {});
      await tester.pumpWidget(tree(replacement));
      expect(tester.takeException(), isNull);
      expect(seen, hasLength(3));
      expect(
          RestageValueBinding.read<String>(
              savedLocalReader!, ['local'], foreignHost),
          '7');
      expect(seen.every((key) => identical(key, oldKey)), isTrue);
      final retainedNested = nested;
      nestedBody = retainedNested.build(foreignHost, {});
      await tester.pumpWidget(tree(replacement));
      expect(tester.takeException(), isNull);
      expect(seen.length, greaterThanOrEqualTo(6));
      expect(seen.every((key) => identical(key, oldKey)), isTrue);
      expect(calls.every((key) => identical(key, oldKey)), isTrue);
      for (final binding in bindings) {
        binding.dispose();
      }
    });
  }
  for (final replacement in [false, true]) {
    testWidgets(
        'rewrapping preserves native evaluation and snapshot replacement=$replacement',
        (tester) async {
      const native = ValueType.native('flutter.Key');
      const valueContract = NativeBindingContract(type: 'flutter.Key');
      const call = NativeBindingContract(
          type: 'installed.key',
          call: NativeCallContract(
              inputs: [], result: native, implementation: 'key-v1'));
      final program = ValueProgram(nodes: [
        ValueNode('native.call', native, value: {
          'binding': 'make',
          'contract': call.toJson(),
          'captures': <String, String>{}
        })
      ], root: 0);
      final raw = Source({
        'program': program.encode(),
        'version': 1,
        'captures': <String, Object?>{}
      });
      final original = Object();
      final newer = Object();
      var calls = 0;
      late BuildContext host;
      late DataSource first;
      Widget tree(Object model) => RestageNativeValues(
              bindings: {
                'make': NativeBinding(
                    contract: call,
                    value: NativeCallAdapter(call, (_, __) {
                      calls++;
                      return NativeBinding(
                          contract: valueContract, value: ObjectKey(model));
                    }))
              },
              child: Builder(builder: (context) {
                host = context;
                return const SizedBox();
              }));
      await tester.pumpWidget(tree(original));
      first = RestageValueBinding.dataSource(raw, host);
      final firstKey = RestageValueBinding.readNative<Key>(first, [], host,
          type: 'flutter.Key');
      if (replacement) await tester.pumpWidget(tree(newer));
      final second = RestageValueBinding.dataSource(first, host);
      final secondKey = RestageValueBinding.readNative<Key>(second, [], host,
          type: 'flutter.Key');
      expect(secondKey, same(firstKey));
      expect((secondKey! as ObjectKey).value, same(original));
      expect(calls, 1);
      final registry = <String, ValueOperation>{};
      final changedRegistry =
          RestageValueBinding.dataSource(first, host, operations: registry);
      final thirdKey = RestageValueBinding.readNative<Key>(
          changedRegistry, [], host,
          type: 'flutter.Key')! as ObjectKey;
      expect(thirdKey.value, same(original));
      expect(
          RestageValueBinding.dataSource(changedRegistry, host,
              operations: registry),
          same(changedRegistry));
      expect(calls, 2);
      final newInvocation = RestageValueBinding.dataSource(raw, host);
      final fresh = RestageValueBinding.readNative<Key>(newInvocation, [], host,
          type: 'flutter.Key')! as ObjectKey;
      expect(fresh, isNot(same(firstKey)));
      expect(fresh.value, same(replacement ? newer : original));
      expect(calls, 3);
    });
  }

  testWidgets('new nested native mount uses its own bindings', (tester) async {
    const contract = NativeBindingContract(type: 'flutter.Key');
    const native = ValueType.native('flutter.Key');
    const call = NativeBindingContract(
        type: 'installed.key',
        call: NativeCallContract(
            inputs: [], result: native, implementation: 'key-v1'));
    final computed = ValueProgram(nodes: [
      ValueNode('native.call', native, value: {
        'binding': 'make',
        'contract': call.toJson(),
        'captures': <String, String>{}
      })
    ], root: 0);
    const builder = BuilderProgram(
        values: ValueProgram(
            nodes: [ValueNode('literal', ValueType.integer, value: 1)],
            root: 0),
        result: BuilderResult.body(0),
        bodyCount: 1);
    final outer = ObjectKey(Object());
    final inner = ObjectKey(Object());
    late RestageBuilderBinding binding;
    late BuildContext host;
    Key? seen;
    const remote = LibraryName(['isolation']);
    late Runtime runtime;
    runtime = Runtime()
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
            'NewMount': (context, source) => RestageNativeValues(
                    bindings: {
                      'key': NativeBinding(contract: contract, value: inner),
                      'make': NativeBinding(
                          contract: call,
                          value: NativeCallAdapter(
                              call,
                              (_, __) => NativeBinding(
                                  contract: contract, value: inner)))
                    },
                    child: RemoteWidget(
                        runtime: runtime,
                        data: DynamicContent(),
                        widget:
                            const FullyQualifiedWidgetName(remote, 'Inner'))),
            'Leaf': (context, source) {
              seen = RestageDecoders.nativeBinding<Key>(
                  context, source, ['key'],
                  type: 'flutter.Key');
              expect(
                  RestageDecoders.nativeBinding<Key>(
                      context, source, ['computed'],
                      type: 'flutter.Key'),
                  same(inner));
              return const SizedBox();
            }
          }))
      ..update(
          remote,
          rfw.parseLibraryFile(
              'import restage.core; widget Root = Host(slot: $kBuilderContinuationWidgetName(version: 1, program: ${jsonEncode(builder.encode())}, captures: {}, bodies: [(frame) => NewMount()])); widget Inner = Leaf(key: {kind: "nativeBinding", key: "key", type: "flutter.Key", nullable: false}, computed: {version: 1, program: ${jsonEncode(computed.encode())}, captures: {}});'));
    addTearDown(runtime.dispose);
    Widget? body;
    late StateSetter update;
    await tester.pumpWidget(RestageNativeValues(
        bindings: {
          'key': NativeBinding(contract: contract, value: outer),
          'make': NativeBinding(
              contract: call,
              value: NativeCallAdapter(call,
                  (_, __) => NativeBinding(contract: contract, value: outer)))
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
    body = binding.build(host, {});
    update(() {});
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(seen, same(inner));
    binding.dispose();
  });
  for (final newContext in [false, true]) {
    testWidgets(
        'scalar native reader preserves retained map, changed context=$newContext',
        (tester) async {
      const call = NativeBindingContract(
          type: 'installed.message',
          call: NativeCallContract(
              inputs: [],
              result: ValueType.string,
              implementation: 'message-v1'));
      final program = ValueProgram(nodes: [
        ValueNode('native.call', ValueType.string, value: {
          'binding': 'message',
          'contract': call.toJson(),
          'captures': <String, String>{}
        })
      ], root: 0);
      final raw = Source({
        'program': program.encode(),
        'version': 1,
        'captures': <String, Object?>{}
      });
      late BuildContext left;
      late BuildContext right;
      Widget scope(String label, Widget child) =>
          RestageNativeValues(bindings: {
            'message': NativeBinding(
                contract: call,
                value: NativeCallAdapter(call, (_, __) => label))
          }, child: child);
      Widget tree(String label) => Directionality(
          textDirection: TextDirection.ltr,
          child: Row(children: [
            scope(label, Builder(builder: (context) {
              left = context;
              return const SizedBox();
            })),
            scope('foreign', Builder(builder: (context) {
              right = context;
              return const SizedBox();
            }))
          ]));
      await tester.pumpWidget(tree('original'));
      final retained = RestageValueBinding.dataSource(raw, left);
      if (!newContext) await tester.pumpWidget(tree('replacement'));
      final current = newContext ? right : left;
      final registry = <String, ValueOperation>{};
      final rewrapped = RestageValueBinding.dataSource(retained, current,
          operations: registry);
      expect(
          RestageValueBinding.read<String>(rewrapped, [], current,
              operations: registry),
          'original');
      final direct = newContext
          ? RestageValueBinding.read<String>(retained, [], current)
          : RestageValueBinding.read<String>(retained, [], current,
              operations: registry);
      expect(direct, 'original');
    });
  }
}

// Reports each build.
final class _Leaf extends StatelessWidget {
  const _Leaf(this.onBuild);

  final void Function(BuildContext context) onBuild;

  @override
  Widget build(BuildContext context) {
    onBuild(context);
    return const SizedBox();
  }
}
