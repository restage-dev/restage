import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:restage_core/src/runtime/builder_binding.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart' as rfw;
import 'package:rfw/rfw.dart';

import 'fixtures/computed_native_shape.dart' as authored;

final class _Observe implements ValueOperation {
  _Observe({this.operationName = 'test.observe', this.failure});
  final String operationName;
  final Object? failure;
  int calls = 0;
  @override
  String get name => operationName;
  @override
  int get capability => 19;
  @override
  void validate(ValueNode node, List<ValueType> inputs) {
    if (node.type.kind != 'String' || inputs.isNotEmpty)
      throw const FormatException('Invalid observer');
  }

  @override
  Object? evaluate(List<Object?> inputs, Object? options) {
    calls++;
    if (failure case final error?) throw error;
    return '$calls';
  }
}

void main() {
  testWidgets('authored constructor radius matches native through data changes',
      (tester) async {
    ShapeBorder? decoded;
    final runtime = Runtime()
      ..update(const LibraryName(['restage', 'core']), buildCoreWidgetLibrary())
      ..update(
          const LibraryName(['example', 'native']),
          LocalWidgetLibrary({
            'NativeShapeProbe': (context, source) {
              decoded = RestageDecoders.shapeBorder(
                  RestageValueBinding.dataSource(source, context), ['shape']);
              return const SizedBox();
            }
          }))
      ..update(
          const LibraryName(['test']),
          rfw.parseLibraryFile(
              File('test/fixtures/computed_native_shape.rfwtxt')
                  .readAsStringSync()));
    addTearDown(runtime.dispose);
    final data = DynamicContent({
      'context': {'width': 125.0}
    });
    Future<void> compare(double width) async {
      await tester.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: Row(children: [
            authored.NativeShapeScreen(width: width),
            RemoteWidget(
                runtime: runtime,
                data: data,
                widget: const FullyQualifiedWidgetName(
                    LibraryName(['test']), 'Root')),
          ])));
      expect(
          decoded,
          tester
              .widget<authored.NativeShapeProbe>(
                  find.byType(authored.NativeShapeProbe))
              .shape);
      expect(tester.takeException(), isNull);
    }

    await compare(125);
    data.update('context', {'width': 250.0});
    await compare(250);
  });

  testWidgets(
      'computed scalar shape queries match native radius and preserve absence',
      (tester) async {
    String envelope(Object? value, ValueType type) =>
        '{version:1,program:${jsonEncode(ValueProgram(nodes: [
              ValueNode('literal', type, value: value)
            ], root: 0).encode())},captures:{}}';
    const callback = BuilderProgram(
      values: ValueProgram(
          nodes: [
            ValueNode('parameter', ValueType.string, name: 'unread'),
          ],
          root: 0,
          parameters: {'unread': ValueType.string}),
      result: BuilderResult.body(0, values: {'text': 0}),
      bodyCount: 1,
    );
    final runtime = Runtime()
      ..update(const LibraryName(['restage', 'core']), buildCoreWidgetLibrary())
      ..update(
          const LibraryName(['probe']),
          LocalWidgetLibrary({
            'Probe': (context, raw) {
              final source = RestageValueBinding.dataSource(raw, context);
              // Presence must not evaluate a callback's unavailable parameter.
              final binding =
                  RestageBuilderBinding.optional(source, ['callback']);
              expect(binding, isNotNull);
              binding!.dispose();
              final actual = RestageDecoders.shapeBorder(source, ['shape']);
              expect(
                  actual,
                  const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12.5))));
              for (final path in [
                ['scalar'],
                ['nil'],
                ['absent']
              ]) {
                expect(source.isMap(path), isFalse, reason: '$path');
                expect(source.isList(path), isFalse, reason: '$path');
                expect(source.length(path), 0, reason: '$path');
              }
              expect(source.v<double>(['scalar']), 12.5);
              expect(source.v<bool>(['scalar']), isNull);
              expect(source.v<String>(['nil']), isNull);
              expect(source.v<String>(['absent']), isNull);
              expect(source.isMap(['map']), isTrue);
              expect(source.v<int>(['map', 'value']), 7);
              expect(source.isList(['list']), isTrue);
              expect(source.length(['list']), 2);
              expect(source.v<int>(['list', 1]), 8);
              return const SizedBox();
            }
          }))
      ..update(
          const LibraryName(['test']),
          rfw.parseLibraryFile(
              'import probe; import restage.core; widget Root = Probe(callback:$kBuilderContinuationWidgetName(version:1,program:${jsonEncode(callback.encode())},captures:{},bodies:[(frame)=>Probe()]),shape:{type:"rounded",borderRadius:${envelope(12.5, ValueType.real)}},scalar:${envelope(12.5, ValueType.real)},nil:${envelope(null, ValueType.nullType)},map:{value:7},list:[7,8]);'));
    addTearDown(runtime.dispose);
    await tester.pumpWidget(RemoteWidget(
        runtime: runtime,
        data: DynamicContent(),
        widget: const FullyQualifiedWidgetName(LibraryName(['test']), 'Root')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('constructor scalar views reject compound envelopes consistently',
      (tester) async {
    const program = ValueProgram(nodes: [
      ValueNode('list', ValueType('list', item: ValueType.integer)),
    ], root: 0);
    final runtime = Runtime()
      ..update(
          const LibraryName(['probe']),
          LocalWidgetLibrary({
            'Probe': (context, raw) {
              final source = RestageValueBinding.dataSource(raw, context);
              for (final read in <Object? Function()>[
                () => source.isMap(['value']),
                () => source.isList(['value']),
                () => source.length(['value']),
                () => source.v<String>(['value']),
              ]) {
                expect(read, throwsFormatException);
              }
              return const SizedBox();
            }
          }))
      ..update(
          const LibraryName(['test']),
          rfw.parseLibraryFile(
              'import probe; widget Root = Probe(value:{version:1,program:${jsonEncode(program.encode())},captures:{}});'));
    addTearDown(runtime.dispose);
    await tester.pumpWidget(RemoteWidget(
        runtime: runtime,
        data: DynamicContent(),
        widget: const FullyQualifiedWidgetName(LibraryName(['test']), 'Root')));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'computed scalar readers preserve probes and evaluate once per factory',
      (tester) async {
    final observe = _Observe();
    final operations = <String, ValueOperation>{observe.name: observe};
    const values = ValueProgram(
        nodes: [ValueNode('test.observe', ValueType.string)], root: 0);
    var visits = 0;
    final runtime = Runtime()
      ..update(
          const LibraryName(['probe']),
          LocalWidgetLibrary({
            'Probe': (context, source) {
              visits++;
              source.v<int>(['tick']);
              final expected = '${observe.calls + 1}';
              final values = RestageValueBinding.dataSource(source, context,
                  operations: operations);
              expect(observe.calls, visits - 1);
              expect(values.isMap(['value']), isFalse);
              expect(values.isList(['value']), isFalse);
              expect(values.length(['value']), 0);
              expect(values.v<bool>(['value']), isNull);
              expect(values.v<String>(['value']), expected);
              expect(
                  RestageValueBinding.read<String>(values, ['value'], context),
                  expected);
              expect(
                  () =>
                      RestageValueBinding.read<int>(values, ['value'], context),
                  throwsStateError);
              expect(
                  identical(
                      RestageValueBinding.dataSource(values, context,
                          operations: operations),
                      values),
                  isTrue);
              expect(observe.calls, visits);
              return const SizedBox();
            }
          }))
      ..update(
          const LibraryName(['test']),
          rfw.parseLibraryFile(
              'import probe; widget Root = Probe(tick:data.tick,value:{version:1,program:${jsonEncode(values.encode())},captures:{}});'));
    final data = DynamicContent({'tick': 0});
    await tester.pumpWidget(RemoteWidget(
        runtime: runtime,
        data: data,
        widget: const FullyQualifiedWidgetName(LibraryName(['test']), 'Root')));
    expect(visits, greaterThan(0));
    final initialVisits = visits;
    data.update('tick', 1);
    await tester.pump();
    expect(visits, greaterThan(initialVisits));
    expect(observe.calls, visits);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scalar shape probes preserve lazy reads and native error order',
      (tester) async {
    final error = StateError('first');
    final first = _Observe(operationName: 'test.first', failure: error);
    final later = _Observe(operationName: 'test.later');
    String envelope(_Observe operation) =>
        '{version:1,program:${jsonEncode(ValueProgram(nodes: [
              ValueNode(operation.name, ValueType.string)
            ], root: 0).encode())},captures:{}}';
    final runtime = Runtime()
      ..update(
          const LibraryName(['probe']),
          LocalWidgetLibrary({
            'Probe': (context, raw) {
              final source = RestageValueBinding.dataSource(raw, context,
                  operations: {first.name: first, later.name: later});
              expect(first.calls, 0);
              expect(later.calls, 0);
              expect(() {
                source.isMap(['first']);
                source.isList(['later']);
              }, throwsA(same(error)));
              expect(first.calls, 1);
              expect(later.calls, 0);
              return const SizedBox();
            }
          }))
      ..update(
          const LibraryName(['test']),
          rfw.parseLibraryFile(
              'import probe; widget Root = Probe(first:${envelope(first)},later:${envelope(later)});'));
    addTearDown(runtime.dispose);
    await tester.pumpWidget(RemoteWidget(
        runtime: runtime,
        data: DynamicContent(),
        widget: const FullyQualifiedWidgetName(LibraryName(['test']), 'Root')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('nested native numeric readers consume the same scalar program',
      (tester) async {
    const values = ValueProgram(nodes: [
      ValueNode('literal', ValueType.integer, value: 2),
      ValueNode('literal', ValueType.integer, value: 1),
      ValueNode('+', ValueType.integer, inputs: [0, 1]),
      ValueNode('/', ValueType.real, inputs: [2, 0]),
    ], root: 3);
    final runtime = Runtime()
      ..update(const LibraryName(['restage', 'core']), buildCoreWidgetLibrary())
      ..update(
          const LibraryName(['probe']),
          LocalWidgetLibrary({
            'Nested': (context, source) {
              source = RestageValueBinding.dataSource(source, context);
              return ConstrainedBox(
                  constraints:
                      ArgumentDecoders.boxConstraints(source, ['constraints'])!,
                  child: source.child(['child']));
            }
          }))
      ..update(
          const LibraryName(['test']),
          rfw.parseLibraryFile(
              'import restage.core; import probe; widget Root = Nested(constraints:{maxWidth:{version:1,program:${jsonEncode(values.encode())},captures:{}}},child:SizedBox(width:10.0,height:10.0));'));
    await tester.pumpWidget(Center(
        child: RemoteWidget(
            runtime: runtime,
            data: DynamicContent(),
            widget: const FullyQualifiedWidgetName(
                LibraryName(['test']), 'Root'))));
    expect(tester.getSize(find.byType(SizedBox).last).width, 1.5);
    expect(tester.takeException(), isNull);
  });
}
