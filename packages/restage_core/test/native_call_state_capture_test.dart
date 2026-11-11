import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart' as rfw;
import 'package:rfw/rfw.dart';

const _core = LibraryName(['restage', 'core']);
const _root = LibraryName(['root']);
const _onPlanType = '(dart:core#String)->void';
const _onPlan = ValueType.native(_onPlanType);

NativeBindingContract _callContract(ValueType argument, String id) =>
    NativeBindingContract(
        type: 'installed.call',
        call: NativeCallContract(
            inputs: [_onPlan, argument],
            result: const ValueType.native(kNativeVoidCallbackType),
            implementation: id));

String _program(
        ValueType argument, NativeBindingContract contract, String binding) =>
    ValueProgram(
        nodes: [
          const ValueNode('capture', _onPlan, name: 'c0'),
          ValueNode('capture', argument, name: 'c1'),
          ValueNode('native.call', contract.call!.result, inputs: [
            0,
            1
          ], value: {
            'binding': binding,
            'contract': contract.toJson(),
            'captures': <String, String>{},
          }),
        ],
        root: 2,
        captures: {'c0': _onPlan, 'c1': argument}).encode();

void main() {
  testWidgets(
      'program captures over state resolve to the value after set state',
      (tester) async {
    final boolCall = _callContract(ValueType.boolean, 'bool-v1');
    final stringCall = _callContract(ValueType.string, 'string-v1');
    NativeCallAdapter adapter(NativeBindingContract contract,
            String Function(Object? argument) plan) =>
        NativeCallAdapter(contract, (inputs, _) {
          final onPlan =
              (inputs[0]! as ValueNative).value! as void Function(String);
          final argument = inputs[1];
          return NativeBinding<VoidCallback>(
              contract:
                  const NativeBindingContract(type: kNativeVoidCallbackType),
              value: () => onPlan(plan(argument)));
        });
    final received = <String>[];
    final runtime = Runtime()
      ..update(_core, LocalWidgetLibrary(kCoreLibraryFactories))
      ..update(
          _root,
          rfw.parseLibraryFile('import restage.core; '
              'widget Root { annual: true } = Column(children: ['
              'GestureDetector(onTap: set state.annual = true, '
              'child: Text(text: "Annual")), '
              'GestureDetector(onTap: set state.annual = false, '
              'child: Text(text: "Monthly")), '
              'GestureDetector(onTap: {nativeEvent: {version: 1, program: '
              '${jsonEncode(_program(ValueType.boolean, boolCall, 'byState'))}, '
              'captures: {c0: data.context.onPlan, c1: state.annual}}}, '
              'child: Text(text: "Reference")), '
              'GestureDetector(onTap: {nativeEvent: {version: 1, program: '
              '${jsonEncode(_program(ValueType.string, stringCall, 'bySwitch'))}, '
              'captures: {c0: data.context.onPlan, c1: switch state.annual '
              '{true: "annual", false: "monthly"}}}}, '
              'child: Text(text: "Switch")), '
              ']);'));
    addTearDown(runtime.dispose);
    final data = DynamicContent()
      ..update('context', <String, Object?>{
        'onPlan': <String, Object?>{
          'kind': 'nativeBinding',
          'key': 'onPlan',
          'type': _onPlanType,
          'nullable': false,
        },
      });
    await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: RestageNativeValues(
            bindings: {
              'onPlan': NativeBinding<Object?>(
                  contract: const NativeBindingContract(type: _onPlanType),
                  value: received.add),
              'byState': NativeBinding<Object?>(
                  contract: boolCall,
                  value: adapter(boolCall,
                      (annual) => annual! as bool ? 'annual' : 'monthly')),
              'bySwitch': NativeBinding<Object?>(
                  contract: stringCall,
                  value: adapter(stringCall, (plan) => plan! as String)),
            },
            child: RemoteWidget(
                runtime: runtime,
                data: data,
                widget: const FullyQualifiedWidgetName(_root, 'Root')))));
    expect(tester.takeException(), isNull);

    Future<void> tap(String label) async {
      await tester.tap(find.text(label));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    await tap('Reference');
    await tap('Switch');
    await tap('Monthly');
    await tap('Reference');
    await tap('Switch');
    await tap('Annual');
    await tap('Reference');
    await tap('Switch');
    expect(received,
        ['annual', 'annual', 'monthly', 'monthly', 'annual', 'annual']);
  });
}
