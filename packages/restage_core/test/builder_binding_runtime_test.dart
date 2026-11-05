import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/src/runtime/builder_binding.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart' as rfw;
import 'package:rfw/rfw.dart';

const _local = LibraryName(['restage', 'core']);
const _remote = LibraryName(['test']);
const _item = ValueType('record', fields: {'title': ValueType.string});
const _items = ValueType('list', item: _item);
const _indexed = BuilderProgram(
  values: ValueProgram(
    nodes: [
      ValueNode('capture', _items, name: 'items'),
      ValueNode('parameter', ValueType.integer, name: 'arg1'),
      ValueNode('length', ValueType.integer, inputs: [0]),
      ValueNode('>=', ValueType.boolean, inputs: [1, 2]),
      ValueNode('index', _item, inputs: [0, 1]),
      ValueNode('field', ValueType.string, inputs: [4], name: 'title'),
      ValueNode('parameter', ValueType.string,
          name: 'context:theme:brightness'),
    ],
    root: 5,
    captures: {'items': _items},
    parameters: {
      'arg1': ValueType.integer,
      'context:theme:brightness': ValueType.string,
    },
  ),
  result: BuilderResult.branch(
    3,
    BuilderResult.nullResult(),
    BuilderResult.body(0, values: {'title': 5, 'brightness': 6}, key: 5),
  ),
  bodyCount: 1,
  nullableResult: true,
);

String _slot(BuilderProgram program,
        {String captures = 'items:args.items', String? body}) =>
    '$kBuilderContinuationWidgetName(version:1,'
    'program:${jsonEncode(program.encode())},captures:{$captures},bodies:['
    '${body ?? '(frame) => Body(title:frame.values.title,brightness:frame.values.brightness)'}])';

String _source({String? slot, String extra = ''}) =>
    'widget Root = Alias(items:data.items); '
    'widget Alias = Native(slot:${slot ?? _slot(_indexed)}$extra);';

List<Object?> _data(String prefix) => [
      {'title': '$prefix 0'},
      {'title': '$prefix 1'},
      for (var index = 2; index < 1000; index++) {'unread': index},
    ];

BuilderProgram _collection() => BuilderProgram(
      values: _indexed.values,
      result: const BuilderResult.sequence([
        BuilderResult.forEach(
          2,
          'arg1',
          BuilderResult.body(0, values: {'title': 5, 'brightness': 6}, key: 5),
        ),
        BuilderResult.nullResult(),
      ]),
      bodyCount: 1,
      nullableResult: true,
      collection: true,
    );

const _indexContract = WidgetBuilderContract(
  parameters: [
    WidgetBuilderParameter.buildContext,
    WidgetBuilderParameter.itemIndex,
  ],
  nullableResult: true,
);

void main() {
  testWidgets(
      'native projected keys preserve generic identity and explicit null',
      (tester) async {
    for (final (tag, value, expected) in <(String, Object?, Key)>[
      ('int', 1, const ValueKey<int>(1)),
      ('double', 1.0, const ValueKey<double>(1.0)),
      ('num', 1, const ValueKey<num>(1)),
      ('Object', 1, const ValueKey<Object>(1)),
      ('String?', null, const ValueKey<String?>(null)),
      ('Null', null, const ValueKey<Null>(null)),
    ]) {
      final type = value == null
          ? ValueType.nullType
          : value is int
              ? ValueType.integer
              : ValueType.real;
      final program = BuilderProgram(
          values: ValueProgram(
              nodes: [ValueNode('literal', type, value: value)], root: 0),
          result: BuilderResult.body(0, key: 0, keyType: tag),
          bodyCount: 1);
      final harness = _Harness(
          'widget Root=Native(slot:${_slot(program, captures: '', body: '(frame)=>Body(title:"keyed",brightness:"dark")')});',
          nativeFactory: (context, source) =>
              RestageBuilderBinding.construct((owned) {
                final binding = RestageBuilderBinding(source, ['slot']);
                owned.add(binding);
                final child = binding.build(context, {});
                expect(child.key, expected);
                return child;
              }));
      await tester.pumpWidget(harness.parent(320));
      expect(tester.takeException(), isNull);
      await _dispose(tester, harness);
    }
  });

  testWidgets('a builder decodes its program once across rebuilds',
      (tester) async {
    const program = BuilderProgram(
        values: ValueProgram(nodes: [
          ValueNode('literal', ValueType.string, value: 'decoded once'),
        ], root: 0),
        result: BuilderResult.body(0),
        bodyCount: 1);
    final harness = _Harness(
        'widget Root=Native(slot:${_slot(program, captures: '', body: '(frame)=>Body(title:"once",brightness:"dark")')});');
    final before = debugProgramDecodes;
    await tester.pumpWidget(harness.parent(320));
    await tester.pumpWidget(harness.parent(500));
    expect(tester.takeException(), isNull);
    expect(harness.nativeCallbacks, 2);
    expect(debugProgramDecodes - before, 1);
    await _dispose(tester, harness);
  });

  testWidgets('a binding built again in place updates its invocation tree',
      (tester) async {
    const program = BuilderProgram(
        values: ValueProgram(nodes: [
          ValueNode('literal', ValueType.string, value: 'in place'),
        ], root: 0),
        result: BuilderResult.body(0),
        bodyCount: 1);
    final harness = _Harness(
        'widget Root=Native(slot:${_slot(program, captures: '', body: '(frame)=>Body(title:"kept",brightness:"dark")')});',
        nativeFactory: (context, source) {
      context.dependOnInheritedWidgetOfExactType<_Tick>();
      return RestageBuilderBinding.construct((owned) {
        final binding = RestageBuilderBinding(
            RestageValueBinding.dataSource(source, context), ['slot']);
        owned.add(binding);
        return binding.build(context, {});
      });
    });
    await tester.pumpWidget(_Tick(0, child: harness.parent(320)));
    await tester.pumpWidget(_Tick(1, child: harness.parent(320)));
    expect(tester.takeException(), isNull);
    expect(harness.nativeFactories, 2);
    expect(find.text('kept dark'), findsOneWidget);
    expect(harness.helperContexts, hasLength(1));
    await _dispose(tester, harness);
    expect(harness.helperContexts.single.mounted, isFalse);
  });

  testWidgets('optional callbacks reject supplied scalar and container values',
      (tester) async {
    for (final value in ['false', '0', '1.0', '"text"', '{}', '[]']) {
      final harness = _Harness('widget Root=Native(slot:$value);',
          nativeFactory: (context, source) {
        expect(() => RestageBuilderBinding.optional(source, ['slot']),
            throwsFormatException);
        return const Text('rejected');
      });
      await tester.pumpWidget(harness.parent(320));
      expect(tester.takeException(), isNull);
      await _dispose(tester, harness);
    }
  });

  testWidgets('demand reads update and return null and keys synchronously',
      (tester) async {
    late _Harness harness;
    final keys = <Key?>[];
    var nullReturns = 0;
    harness = _Harness(_source(), data: {'items': _data('initial')},
        callback: (context, binding, constraints) {
      final before = harness.bodyBuilds;
      final index = constraints.maxWidth >= 400 ? 1 : 0;
      final delegate = SliverChildBuilderDelegate((context, _) {
        final child = binding.buildNullable(context, {'arg1': index});
        keys.add(child?.key);
        return child;
      },
          addAutomaticKeepAlives: false,
          addRepaintBoundaries: false,
          addSemanticIndexes: false);
      final result = delegate.build(context, 0);
      final nullDelegate = SliverChildBuilderDelegate(
          (context, _) => binding.buildNullable(context, {'arg1': 1000}));
      expect(nullDelegate.build(context, 0), isNull);
      nullReturns++;
      expect(harness.bodyBuilds, before);
      return result!;
    });

    await tester.pumpWidget(harness.parent(320));
    expect(tester.takeException(), isNull);
    expect(find.text('initial 0 dark'), findsOneWidget);
    expect(keys.last, const ValueKey<Object>('initial 0'));
    expect(harness.nativeFactories, 1);
    expect(harness.helperContexts, hasLength(1));

    final callbacks = harness.nativeCallbacks;
    harness.data.update('items', _data('updated'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('updated 0 dark'), findsOneWidget);
    expect(keys.last, const ValueKey<Object>('updated 0'));
    expect(harness.nativeCallbacks, callbacks + 1);
    expect(harness.nativeFactories, 1);

    await tester.pumpWidget(harness.parent(500));
    expect(tester.takeException(), isNull);
    expect(find.text('updated 1 dark'), findsOneWidget);
    expect(keys.last, const ValueKey<Object>('updated 1'));
    expect(harness.helperContexts, hasLength(1));
    expect(nullReturns, greaterThanOrEqualTo(3));
    await _dispose(tester, harness);
  });

  testWidgets('replacement releases previous subscriptions', (tester) async {
    final harness = _Harness(_source(extra: ',generation:data.generation'),
        data: {'items': _data('initial'), 'generation': 0});
    await tester.pumpWidget(harness.parent(320));
    expect(tester.takeException(), isNull);
    final firstContext = harness.helperContexts.single;
    final firstBinding = harness.bindings.single;

    harness.data.update('generation', 1);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(firstContext.mounted, isFalse);
    expect(harness.helperContexts, hasLength(2));
    expect(harness.helperContexts.where((context) => context.mounted),
        hasLength(1));
    expect(() => firstBinding.build(harness.lastCallbackContext!, {'arg1': 0}),
        throwsStateError);

    final callbacks = harness.nativeCallbacks;
    harness.data.update('items', _data('replaced'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(harness.nativeCallbacks, callbacks + 1);
    expect(find.text('replaced 0 dark'), findsOneWidget);
    await _dispose(tester, harness);
  });

  testWidgets('immediate native builders evaluate during initial mounting',
      (tester) async {
    final harness = _Harness(_source(),
        data: {'items': _data('immediate')},
        nativeBuilder: (binding) =>
            Builder(builder: (context) => binding.build(context, {'arg1': 0})));
    await tester.pumpWidget(harness.parent(320));
    expect(tester.takeException(), isNull);
    expect(find.text('immediate 0 dark'), findsOneWidget);
    harness.data.update('items', _data('updated'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('updated 0 dark'), findsOneWidget);
    expect(harness.nativeFactories, 1);
    await _dispose(tester, harness);
  });

  testWidgets('errors and nonnullable null leave later invocations usable',
      (tester) async {
    final harness = _Harness(_source(), data: {'items': _data('valid')},
        callback: (context, binding, constraints) {
      expect(
          () => binding.buildNullable(context, {'arg1': -1}), throwsRangeError);
      expect(binding.buildNullable(context, {'arg1': 1000}), isNull);
      expect(() => binding.build(context, {'arg1': 1000}), throwsStateError);
      return binding.build(context, {'arg1': 0});
    });
    await tester.pumpWidget(harness.parent(320));
    expect(tester.takeException(), isNull);
    expect(find.text('valid 0 dark'), findsOneWidget);
    harness.data.update('items', _data('recovered'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('recovered 0 dark'), findsOneWidget);
    await _dispose(tester, harness);
  });

  testWidgets('remote state captures preserve the owning state chain',
      (tester) async {
    final harness = _Harness('''
widget Root { items: [{title:"state 0"},{title:"state 1"}] } = Column(
  children:[
    Native(slot:${_slot(_indexed, captures: 'items:state.items')}),
    Button(onTap:set state.items = [{title:"changed 0"},{title:"changed 1"}])
  ]
);
''');
    await tester.pumpWidget(harness.parent(320));
    expect(tester.takeException(), isNull);
    expect(find.text('state 0 dark'), findsOneWidget);
    await tester.tap(find.text('update'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('changed 0 dark'), findsOneWidget);
    expect(harness.nativeFactories, 1);
    await _dispose(tester, harness);
  });

  testWidgets('nested builder frame captures refresh with their outer data',
      (tester) async {
    const inner = BuilderProgram(
      values: ValueProgram(
        nodes: [
          ValueNode('capture', ValueType.string, name: 'title'),
          ValueNode('parameter', ValueType.string,
              name: 'context:theme:brightness'),
        ],
        root: 0,
        captures: {'title': ValueType.string},
        parameters: {'context:theme:brightness': ValueType.string},
      ),
      result: BuilderResult.body(0, values: {'title': 0, 'brightness': 1}),
      bodyCount: 1,
    );
    final outerBody = '(outer) => Native(slot:'
        '${_slot(inner, captures: 'title:outer.values.title')})';
    final harness = _Harness(_source(slot: _slot(_indexed, body: outerBody)),
        data: {'items': _data('nested')});
    await tester.pumpWidget(harness.parent(320));
    expect(tester.takeException(), isNull);
    expect(find.text('nested 0 dark'), findsOneWidget);
    expect(harness.helperContexts.where((context) => context.mounted),
        hasLength(2));

    harness.data.update('items', _data('updated'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('updated 0 dark'), findsOneWidget);
    expect(harness.helperContexts.where((context) => context.mounted),
        hasLength(2));
    await _dispose(tester, harness);
  });

  testWidgets('inherited updates use the actual callback context',
      (tester) async {
    final theme = ValueNotifier(ThemeData.dark());
    addTearDown(theme.dispose);
    final harness =
        _Harness(_source(), data: {'items': _data('theme')}, theme: theme);
    await tester.pumpWidget(harness.parent(320));
    expect(tester.takeException(), isNull);
    expect(find.text('theme 0 dark'), findsOneWidget);
    theme.value = ThemeData.light();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('theme 0 light'), findsOneWidget);
    expect(harness.nativeFactories, 1);
    expect(harness.helperContexts, hasLength(1));
    await _dispose(tester, harness);
  });

  testWidgets('scalar callbacks use the same continuation lifecycle',
      (tester) async {
    final values = _indexed.values;
    final slot = '$kBuilderContinuationWidgetName(version:1,'
        'program:${jsonEncode(values.encode())},captures:{items:args.items})';
    final harness = _Harness(_source(slot: slot),
        data: {'items': _data('scalar')},
        callback: (context, binding, constraints) =>
            Text(binding.evaluate(context, {'arg1': 0})! as String));
    await tester.pumpWidget(harness.parent(320));
    expect(tester.takeException(), isNull);
    expect(find.text('scalar 0'), findsOneWidget);
    harness.data.update('items', _data('updated'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('updated 0'), findsOneWidget);
    expect(harness.nativeFactories, 1);
    await _dispose(tester, harness);
  });

  testWidgets('finite collections preserve children and omission on updates',
      (tester) async {
    final harness = _Harness(_source(slot: _slot(_collection())), data: {
      'items': [
        {'title': 'first'},
        {'title': 'second'},
      ]
    }, callback: (context, binding, constraints) {
      expect(() => binding.build(context, {}), throwsFormatException);
      return Column(children: binding.buildList(context, {}));
    });
    await tester.pumpWidget(harness.parent(320));
    expect(tester.takeException(), isNull);
    expect(find.text('first dark'), findsOneWidget);
    expect(find.text('second dark'), findsOneWidget);
    harness.data.update('items', [
      {'title': 'replacement'}
    ]);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('replacement dark'), findsOneWidget);
    expect(find.text('second dark'), findsNothing);
    await _dispose(tester, harness);
  });

  testWidgets('constructor collections refresh their owning native factory',
      (tester) async {
    final harness = _Harness(_source(slot: _slot(_collection())), data: {
      'items': [
        {'title': 'constructor'}
      ]
    }, nativeFactory: (context, source) {
      return RestageBuilderBinding.construct((owned) {
        final binding = RestageBuilderBinding(source, ['slot']);
        owned.add(binding);
        return Column(children: binding.buildList(context, {}));
      });
    });
    await tester.pumpWidget(harness.parent(320));
    expect(tester.takeException(), isNull);
    expect(find.text('constructor light'), findsOneWidget);
    final previousContext = harness.helperContexts.single;
    harness.data.update('items', [
      {'title': 'reconstructed'}
    ]);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('reconstructed light'), findsOneWidget);
    expect(harness.nativeFactories, 2);
    expect(previousContext.mounted, isFalse);
    expect(harness.helperContexts.where((context) => context.mounted),
        hasLength(1));
    await _dispose(tester, harness);
  });

  testWidgets('callback contract rejects incompatible invocation shapes',
      (tester) async {
    final accepted = _Harness(_source(),
        data: {'items': _data('accepted')}, contract: _indexContract);
    await tester.pumpWidget(accepted.parent(320));
    expect(tester.takeException(), isNull);
    expect(find.text('accepted 0 dark'), findsOneWidget);
    await _dispose(tester, accepted);

    final rejected = _Harness(_source(),
        data: {'items': _data('rejected')},
        contract: const WidgetBuilderContract(parameters: [
          WidgetBuilderParameter.buildContext,
          WidgetBuilderParameter.boxConstraints,
        ]), callback: (context, binding, constraints) {
      expect(() => binding.build(context, {'arg1': 0}), throwsFormatException);
      expect(() => binding.buildList(context, {}), throwsFormatException);
      expect(() => binding.evaluate(context, {}), throwsFormatException);
      return const Text('rejected');
    });
    await tester.pumpWidget(rejected.parent(320));
    expect(tester.takeException(), isNull);
    expect(find.text('rejected'), findsOneWidget);
    expect(rejected.bodyBuilds, 0);
    await _dispose(tester, rejected);
  });

  testWidgets('app value slots check the shape the app supplies',
      (tester) async {
    const state = ValueType('record', fields: {'label': ValueType.string});
    const contract = WidgetBuilderContract(parameters: [
      WidgetBuilderParameter.buildContext,
      WidgetBuilderParameter.data,
      WidgetBuilderParameter.child,
    ]);
    BuilderProgram reading(String name, ValueType type) => BuilderProgram(
        values: ValueProgram(
            nodes: [
              ValueNode('parameter', type, name: name),
              if (type.kind == 'record')
                const ValueNode('field', ValueType.string,
                    inputs: [0], name: 'label'),
            ],
            root: type.kind == 'record' ? 1 : 0,
            parameters: {name: type}),
        result: BuilderResult.body(0,
            values: {'title': type.kind == 'record' ? 1 : 0}),
        bodyCount: 1);
    for (final (program, installed, shown) in [
      (reading('arg1', state), state, 'counted dark'),
      (
        reading('arg1', state),
        const ValueType('record', fields: {'other': ValueType.string}),
        null
      ),
      (reading('arg2', ValueType.string), state, null),
    ]) {
      final harness = _Harness(
          'widget Root=Native(slot:${_slot(program, captures: '', body: '(frame)=>Body(title:frame.values.title,brightness:"dark")')});',
          nativeFactory: (context, source) =>
              RestageBuilderBinding.construct((owned) {
                final binding = RestageBuilderBinding(source, ['slot'],
                    contract: contract, data: {'arg1': installed});
                owned.add(binding);
                final parameters = {
                  'arg1': {'label': 'counted'},
                  'arg2': 'child'
                };
                if (shown == null) {
                  expect(() => binding.build(context, parameters),
                      throwsFormatException);
                  return const Text('refused');
                }
                return binding.build(context, parameters);
              }));
      await tester.pumpWidget(harness.parent(320));
      expect(tester.takeException(), isNull);
      expect(find.text(shown ?? 'refused'), findsOneWidget);
      await _dispose(tester, harness);
    }
  });

  testWidgets('an app builder renders its delivered body with its value',
      (tester) async {
    const program = BuilderProgram(
        values: ValueProgram(
            nodes: [
              ValueNode('parameter', ValueType.integer, name: 'arg1'),
              ValueNode('string', ValueType.string, inputs: [0]),
            ],
            root: 1,
            parameters: {'arg1': ValueType.integer}),
        result: BuilderResult.body(0, values: {'title': 1}),
        bodyCount: 1);
    final counter = ValueNotifier(1);
    var bindings = <RestageBuilderBinding>[];
    // The island build the compiler writes for this builder.
    final harness = _Harness(
        'widget Root=Native(slot:${_slot(program, captures: '', body: '(frame)=>Body(title:frame.values.title,brightness:"dark")')});',
        nativeFactory: (c, s) =>
            RestageBuilderBinding.construct((_restageBindings) {
              bindings = _restageBindings;
              final _restageBinding$builder = RestageBuilderBinding(
                  RestageValueBinding.dataSource(s, c), const <Object>['slot'],
                  contract: const WidgetBuilderContract(parameters: [
                    WidgetBuilderParameter.buildContext,
                    WidgetBuilderParameter.data,
                    WidgetBuilderParameter.child
                  ]),
                  data: const <String, ValueType>{'arg1': ValueType('int')});
              _restageBindings.add(_restageBinding$builder);
              return ValueListenableBuilder<int>(
                  valueListenable: counter,
                  builder: (_restageArg0, _restageArg1, _restageArg2) =>
                      _restageBinding$builder.build(_restageArg0,
                          <String, Object?>{'arg1': _restageArg1}));
            }));
    await tester.pumpWidget(harness.parent(320));
    expect(tester.takeException(), isNull);
    expect(find.text('1 dark'), findsOneWidget);
    counter.value = 2;
    await tester.pump();
    expect(find.text('2 dark'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
    expect(bindings, isNotEmpty);
    for (final binding in bindings) {
      expect(() => binding.build(tester.binding.rootElement!, {'arg1': 3}),
          throwsStateError);
    }
  });

  testWidgets('each builder call reads only the values it recorded',
      (tester) async {
    const program = BuilderProgram(
        values: ValueProgram(
            nodes: [
              ValueNode('parameter', ValueType.integer, name: 'arg1'),
              ValueNode('parameter', ValueType.string, name: 'recorded:label'),
              ValueNode('string', ValueType.string, inputs: [0]),
              ValueNode('literal', ValueType.string, value: ' at '),
              ValueNode('concat', ValueType.string, inputs: [1, 3, 2]),
            ],
            root: 4,
            parameters: {
              'arg1': ValueType.integer,
              'recorded:label': ValueType.string,
            }),
        result: BuilderResult.body(0, values: {'title': 4}),
        bodyCount: 1);
    final calls = <int>[];
    // The island build the compiler writes for a lazy list's builder whose
    // body the app's copied closure records into.
    final harness = _Harness(
        'widget Root=Native(slot:${_slot(program, captures: '', body: '(frame)=>Body(title:frame.values.title,brightness:"dark")')});',
        nativeFactory: (c, s) =>
            RestageBuilderBinding.construct((_restageBindings) {
              final _restageBinding$itemBuilder = RestageBuilderBinding(
                  RestageValueBinding.dataSource(s, c), const <Object>['slot'],
                  contract: const WidgetBuilderContract(parameters: [
                    WidgetBuilderParameter.buildContext,
                    WidgetBuilderParameter.data,
                  ]),
                  data: const <String, ValueType>{'arg1': ValueType('int')});
              _restageBindings.add(_restageBinding$itemBuilder);
              return SizedBox(
                  height: 400,
                  child: ListView.builder(
                      itemCount: 4,
                      itemBuilder: (context, index) {
                        final _restageSlotRecording = <String, Object?>{};
                        _restageRender(Object? _) =>
                            _restageBinding$itemBuilder.build(
                                context, <String, Object?>{'arg1': index},
                                recorded: _restageSlotRecording);
                        calls.add(index);
                        final label = _restageSlotRecording['label'] =
                            'row ${index * 10}';
                        return _restageRender(Text('$label'));
                      }));
            }));
    await tester.pumpWidget(harness.parent(320));
    expect(tester.takeException(), isNull);
    expect(calls, [0, 1, 2, 3]);
    for (var index = 0; index < 4; index++) {
      expect(find.text('row ${index * 10} at $index dark'), findsOneWidget);
    }
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('optional callbacks distinguish absence from a present program',
      (tester) async {
    final absent = _Harness('widget Root = Native();', optional: true);
    await tester.pumpWidget(absent.parent(320));
    expect(tester.takeException(), isNull);
    expect(find.text('absent'), findsOneWidget);
    expect(absent.helperContexts, isEmpty);
    await _dispose(tester, absent);

    final present = _Harness(_source(),
        data: {'items': _data('optional')},
        optional: true,
        contract: _indexContract);
    await tester.pumpWidget(present.parent(320));
    expect(tester.takeException(), isNull);
    expect(find.text('optional 0 dark'), findsOneWidget);
    await _dispose(tester, present);
  });

  testWidgets('failed native construction releases initialized collections',
      (tester) async {
    late _Harness harness;
    harness = _Harness(_source(slot: _slot(_collection())), data: {
      'items': [
        {'title': 'unused'}
      ]
    }, nativeFactory: (context, source) {
      expect(
          () => RestageBuilderBinding.construct((owned) {
                final binding = RestageBuilderBinding(source, ['slot']);
                owned.add(binding);
                harness.bindings.add(binding);
                expect(binding.buildList(context, {}), hasLength(1));
                throw StateError('Native constructor failed');
              }),
          throwsStateError);
      expect(harness.helperContexts.single.mounted, isFalse);
      expect(() => harness.bindings.single.buildList(context, {}),
          throwsStateError);
      return const Text('construction failed');
    });
    await tester.pumpWidget(harness.parent(320));
    expect(tester.takeException(), isNull);
    expect(find.text('construction failed'), findsOneWidget);
    expect(harness.bodyBuilds, 0);
    await _dispose(tester, harness);
  });

  testWidgets('keyed grid children retain state through data reorder',
      (tester) async {
    var order = ['a', 'b', 'c'];
    final harness = _Harness(_source(),
        data: {
          'items': [
            for (final id in order) {'title': id}
          ]
        },
        nativeBuilder: (binding) => GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3),
              findChildIndexCallback: (key) =>
                  order.indexOf((key as ValueKey<Object>).value as String),
              itemBuilder: (context, index) =>
                  binding.buildNullable(context, {'arg1': index}),
            ),
        bodyBuilder: (context, source) =>
            _StatefulBody(source.v<String>(['title'])!));
    await tester.pumpWidget(harness.parent(320));
    expect(tester.takeException(), isNull);
    final original = <String, State>{
      for (final id in order)
        id: tester.state(find.byWidgetPredicate(
            (widget) => widget is _StatefulBody && widget.label == id)),
    };
    order = ['c', 'a', 'b'];
    harness.data.update('items', [
      for (final id in order) {'title': id}
    ]);
    await tester.pump();
    expect(tester.takeException(), isNull);
    for (final id in order) {
      expect(
          tester.state(find.byWidgetPredicate(
              (widget) => widget is _StatefulBody && widget.label == id)),
          same(original[id]));
    }
    await _dispose(tester, harness);
  });
}

Future<void> _dispose(WidgetTester tester, _Harness harness) async {
  final callbackContext = harness.lastCallbackContext;
  harness.data.update('items', _data('pending disposal'));
  await tester.pumpWidget(const SizedBox());
  expect(tester.takeException(), isNull);
  expect(harness.helperContexts.every((context) => !context.mounted), isTrue);
  if (callbackContext != null) {
    for (final binding in harness.bindings) {
      expect(
          () => binding.build(callbackContext, {'arg1': 0}), throwsStateError);
    }
  }
  final callbacks = harness.nativeCallbacks;
  harness.data.update('items', _data('disposed'));
  expect(harness.nativeCallbacks, callbacks);
}

typedef _Callback = Widget Function(
    BuildContext, RestageBuilderBinding, BoxConstraints);

final class _Harness {
  _Harness(String source,
      {Map<String, Object?> data = const {},
      _Callback? callback,
      Widget Function(RestageBuilderBinding)? nativeBuilder,
      LocalWidgetBuilder? bodyBuilder,
      LocalWidgetBuilder? nativeFactory,
      WidgetBuilderContract? contract,
      bool optional = false,
      ValueNotifier<ThemeData>? theme})
      : data = DynamicContent(data) {
    runtime
      ..update(
          _local,
          LocalWidgetLibrary({
            kBuilderContinuationWidgetName: (context, source) {
              helperContexts.add(context);
              expect(context.owner, isNot(same(nativeOwner)));
              return buildRestageBuilderContinuation(context, source);
            },
            'Body': (context, source) {
              bodyBuilds++;
              expect(context.owner, same(nativeOwner));
              return bodyBuilder?.call(context, source) ??
                  Text('${source.v<String>(['title'])} '
                      '${source.v<String>(['brightness'])}');
            },
            'Native': (context, source) {
              nativeFactories++;
              nativeOwner = context.owner;
              if (nativeFactory != null) return nativeFactory(context, source);
              source.v<int>(['generation']);
              final binding = optional
                  ? RestageBuilderBinding.optional(source, ['slot'],
                      contract: contract)
                  : RestageBuilderBinding(source, ['slot'], contract: contract);
              if (binding == null) return const Text('absent');
              bindings.add(binding);
              final native = nativeBuilder?.call(binding) ??
                  LayoutBuilder(builder: (context, constraints) {
                    nativeCallbacks++;
                    lastCallbackContext = context;
                    return callback?.call(context, binding, constraints) ??
                        binding.build(context,
                            {'arg1': constraints.maxWidth >= 400 ? 1 : 0});
                  });
              return RestageBuilderBinding.retain([binding],
                  child: theme == null
                      ? Theme(data: ThemeData.dark(), child: native)
                      : ValueListenableBuilder<ThemeData>(
                          valueListenable: theme,
                          child: native,
                          builder: (context, theme, child) =>
                              Theme(data: theme, child: child!),
                        ));
            },
            'Column': (context, source) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: source.childList(['children']),
                ),
            'Button': (context, source) => GestureDetector(
                onTap: source.voidHandler(['onTap']),
                child: const Text('update')),
          }))
      ..update(_remote, rfw.parseLibraryFile('import restage.core; $source'));
    remote = Builder(
        builder: (context) => runtime.build(
            context,
            const FullyQualifiedWidgetName(_remote, 'Root'),
            this.data,
            (name, arguments) {}));
  }

  final DynamicContent data;
  final runtime = Runtime();
  late final Widget remote;
  final helperContexts = <BuildContext>{};
  final bindings = <RestageBuilderBinding>[];
  BuildOwner? nativeOwner;
  BuildContext? lastCallbackContext;
  int nativeFactories = 0;
  int nativeCallbacks = 0;
  int bodyBuilds = 0;

  Widget parent(double width) => Theme(
        data: ThemeData.light(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child:
              Center(child: SizedBox(width: width, height: 150, child: remote)),
        ),
      );
}

final class _StatefulBody extends StatefulWidget {
  const _StatefulBody(this.label);
  final String label;

  @override
  State<_StatefulBody> createState() => _StatefulBodyState();
}

final class _StatefulBodyState extends State<_StatefulBody> {
  @override
  Widget build(BuildContext context) => Text(widget.label);
}

// Rebuilds what depends on it without rebuilding the remote widget above.
final class _Tick extends InheritedWidget {
  const _Tick(this.value, {required super.child});
  final int value;

  @override
  bool updateShouldNotify(_Tick oldWidget) => value != oldWidget.value;
}
