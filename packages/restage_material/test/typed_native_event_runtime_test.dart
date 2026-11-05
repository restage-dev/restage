import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:restage_material/restage_material.dart';
import 'package:rfw/formats.dart' as rfw;
import 'package:rfw/rfw.dart' hide Switch;

const _root = LibraryName(['test']);
const _core = LibraryName(['restage', 'core']);
const _material = LibraryName(['restage', 'material']);
const _local = LibraryName(['test', 'local']);
const _measure = '__restage_measurement_tap_v1';

enum _Plan { yearly }

// A widget whose callbacks take two arguments and an enum, read the way a
// catalog factory reads a typed event.
Widget _probe(BuildContext context, DataSource source) {
  source = RestageValueBinding.dataSource(source, context);
  final pair = source.handler<void Function(int, int)>(
      const ['onPair'], (trigger) => (a, b) => trigger({'a': a, 'b': b}));
  final plan = source.handler<void Function(_Plan)>(
      const ['onPlan'], (trigger) => (plan) => trigger({'value': plan.name}));
  return Column(children: [
    GestureDetector(onTap: () => pair?.call(1, 2), child: const Text('Pair')),
    GestureDetector(
        onTap: () => plan?.call(_Plan.yearly), child: const Text('Plan')),
  ]);
}

Widget _remote(String root, Map<String, NativeBinding<Object?>> bindings,
    List<String> events) {
  final runtime = Runtime()
    ..update(_core, buildCoreWidgetLibrary())
    ..update(_material, buildMaterialWidgetLibrary())
    ..update(_local, LocalWidgetLibrary({'Probe': _probe}))
    ..update(
        _root,
        rfw.parseLibraryFile('import restage.core; import restage.material; '
            'import test.local; widget Root = $root;'));
  return MaterialApp(
    home: Scaffold(
      body: RestageNativeValues(
        bindings: bindings,
        child: RemoteWidget(
          runtime: runtime,
          data: DynamicContent({
            'context': {
              for (final MapEntry(:key, :value) in bindings.entries)
                key: {
                  'kind': 'nativeBinding',
                  'key': key,
                  'type': value.contract.type,
                  'nullable': value.contract.nullable,
                },
            },
          }),
          widget: const FullyQualifiedWidgetName(_root, 'Root'),
          onEvent: (name, arguments) => events.add(name),
        ),
      ),
    ),
  );
}

NativeBinding<Object?> _binding(String type, Object value) => NativeBinding(
    contract: NativeBindingContract(type: type, nullable: false), value: value);

String _slot(String key, {bool measured = false}) =>
    '{nativeEvent: data.context.$key'
    '${measured ? ', measurement: event "$_measure" {}' : ''}}';

void main() {
  group('a typed native callback', () {
    testWidgets('a Switch calls the app with the value Flutter gives',
        (tester) async {
      final calls = <String>[];
      final events = <String>[];
      await tester.pumpWidget(_remote(
          'Switch(value: false, onChanged: ${_slot('cb')})',
          {
            'cb': _binding(
                '(dart:core#bool)->void', (bool on) => calls.add('t $on')),
          },
          events));
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(calls, ['t true']);
      expect(events, isEmpty);
    });

    testWidgets('a nullable Checkbox value reaches the app', (tester) async {
      final calls = <String>[];
      await tester.pumpWidget(
          _remote('Checkbox(value: true, onChanged: ${_slot('cb')})', {
        'cb': _binding(
            '(dart:core#bool?)->void', (bool? on) => calls.add('c $on')),
      }, []));
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(calls, ['c false']);
    });

    testWidgets('a measured typed callback still measures', (tester) async {
      final calls = <String>[];
      final events = <String>[];
      await tester.pumpWidget(_remote(
          'Switch(value: true, onChanged: ${_slot('cb', measured: true)})',
          {
            'cb': _binding(
                '(dart:core#bool)->void', (bool on) => calls.add('t $on')),
          },
          events));
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(calls, ['t false']);
      expect(events, [_measure]);
    });

    testWidgets('two arguments and an enum reach the app as given',
        (tester) async {
      final calls = <String>[];
      final events = <String>[];
      await tester.pumpWidget(_remote(
          'Probe(onPair: ${_slot('pair', measured: true)}, '
          'onPlan: ${_slot('plan')})',
          {
            'pair': _binding('(dart:core#int,dart:core#int)->void',
                (int a, int b) => calls.add('pair $a $b')),
            'plan': _binding('(test#_Plan)->void',
                (_Plan plan) => calls.add('plan ${plan.name}')),
          },
          events));
      await tester.tap(find.text('Pair'));
      await tester.tap(find.text('Plan'));
      await tester.pump();
      expect(calls, ['pair 1 2', 'plan yearly']);
      expect(events, [_measure]);
    });

    testWidgets('a callback of another type is refused', (tester) async {
      await tester.pumpWidget(
          _remote('Switch(value: false, onChanged: ${_slot('cb')})', {
        'cb': _binding('(dart:core#int)->void', (int n) {}),
      }, []));
      expect(tester.takeException(), isA<FormatException>());
    });
  });
}
