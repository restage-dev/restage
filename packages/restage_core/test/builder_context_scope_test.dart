import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/src/runtime/builder_binding.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart' as rfw;
import 'package:rfw/rfw.dart';

const _local = LibraryName(['restage', 'core']);
const _remote = LibraryName(['test']);
const _themeValue = ValueProgram(
  nodes: [
    ValueNode('parameter', ValueType.string, name: 'context:theme:brightness'),
  ],
  root: 0,
  parameters: {'context:theme:brightness': ValueType.string},
);
const _outer = BuilderProgram(
  values: ValueProgram(
    nodes: [ValueNode('literal', ValueType.string, value: 'outer')],
    root: 0,
  ),
  result: BuilderResult.body(0, key: 0, keyType: 'String'),
  bodyCount: 1,
);

String _slot(BuilderProgram program, String body) =>
    '$kBuilderContinuationWidgetName(version:1,'
    'program:${jsonEncode(program.encode())},captures:{},bodies:[$body])';

ValueProgram _contexts(List<String> names) => ValueProgram(
      nodes: [
        for (final name in names)
          ValueNode('parameter', ValueType.string, name: name),
        ValueNode('concat', ValueType.string,
            inputs: [for (var index = 0; index < names.length; index++) index]),
      ],
      root: names.length,
      parameters: {for (final name in names) name: ValueType.string},
    );

void main() {
  testWidgets('collection context remains in its authored callback scope',
      (tester) async {
    const collection = BuilderProgram(
      values: _themeValue,
      result: BuilderResult.body(0, values: {'label': 0}),
      bodyCount: 1,
      collection: true,
    );
    final ordinary =
        '{version:1,program:${jsonEncode(_themeValue.encode())},captures:{}}';
    final children = _slot(collection,
        '(row) => Label(prefix:"collection ",value:row.values.label)');
    final outer = _slot(_outer, '''
(body) => Dark(child: Column(children:[
  Collection(children:$children),
  Label(prefix:"ordinary ",value:$ordinary)
]))
''');
    final harness = _ContextHarness('widget Root = Native(builder:$outer);');
    await tester.pumpWidget(harness.widget);
    expect(tester.takeException(), isNull);
    expect(find.text('collection light'), findsOneWidget);
    expect(find.text('ordinary light'), findsOneWidget);
    expect(harness.returnedKeys.single, const ValueKey<String>('outer'));

    harness.theme.value = ThemeData.dark();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('collection dark'), findsOneWidget);
    expect(find.text('ordinary dark'), findsOneWidget);
    harness.descendantTheme.value = ThemeData.light();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('collection dark'), findsOneWidget);
    expect(find.text('ordinary dark'), findsOneWidget);
  });

  testWidgets('dead collection branches never read missing localization',
      (tester) async {
    const collection = BuilderProgram(
      values: ValueProgram(
        nodes: [
          ValueNode('literal', ValueType.integer, value: 1),
          ValueNode('parameter', ValueType.string,
              name: 'context:device:languageCode'),
          ValueNode('literal', ValueType.boolean, value: false),
          ValueNode('literal', ValueType.string, value: 'safe'),
        ],
        root: 3,
        parameters: {
          'context:device:languageCode': ValueType.string,
          'i': ValueType.integer,
        },
      ),
      result: BuilderResult.forEach(
        0,
        'i',
        BuilderResult.branch(
          2,
          BuilderResult.body(0, values: {'label': 1}),
          BuilderResult.body(0, values: {'label': 3}),
        ),
      ),
      bodyCount: 1,
      collection: true,
    );
    final children =
        _slot(collection, '(row) => Label(value:row.values.label)');
    final outer = _slot(_outer, '(body) => Collection(children:$children)');
    final harness = _ContextHarness('widget Root = Native(builder:$outer);');
    await tester.pumpWidget(harness.widget);
    expect(tester.takeException(), isNull);
    expect(find.text('safe'), findsOneWidget);
  });

  testWidgets('nested authored callbacks establish their own context scope',
      (tester) async {
    const inner = BuilderProgram(
      values: _themeValue,
      result: BuilderResult.body(0, values: {'label': 0}),
      bodyCount: 1,
    );
    final child = _slot(
        inner, '(body) => Label(prefix:"inner ",value:body.values.label)');
    final outer = _slot(_outer, '(body) => Dark(child:Native(builder:$child))');
    final harness = _ContextHarness('widget Root = Native(builder:$outer);');
    await tester.pumpWidget(harness.widget);
    expect(tester.takeException(), isNull);
    expect(find.text('inner dark'), findsOneWidget);
  });

  testWidgets('nested collections preserve native lexical ancestor depth',
      (tester) async {
    final values = _contexts([
      'context:theme:brightness',
      'context:ancestor:1:theme:brightness',
    ]);
    final deepest = _slot(
        BuilderProgram(
            values: values,
            result: BuilderResult.body(0, values: {'label': values.root}),
            bodyCount: 1,
            collection: true),
        '(row) => Label(prefix:"depth ",value:row.values.label)');
    final middle = _slot(
        BuilderProgram(
            values: _outer.values,
            result: const BuilderResult.body(0),
            bodyCount: 1,
            collection: true),
        '(row) => Collection(children:$deepest)');
    final ordinary =
        '{version:1,program:${jsonEncode(values.encode())},captures:{}}';
    final inner = _slot(_outer, '''
(body) => Light(child:Column(children:[
  Collection(children:$middle),
  Label(prefix:"ordinary depth ",value:$ordinary)
]))
''');
    final outer = _slot(_outer, '(body) => Dark(child:Native(builder:$inner))');
    final harness = _ContextHarness('widget Root = Native(builder:$outer);');
    await tester.pumpWidget(harness.widget);
    expect(tester.takeException(), isNull);
    expect(find.text('depth darklight'), findsOneWidget);
    expect(find.text('ordinary depth darklight'), findsOneWidget);
    harness.theme.value = ThemeData.dark();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('depth darkdark'), findsOneWidget);
  });

  testWidgets('native callback ancestor chains retain multiple levels',
      (tester) async {
    final values = _contexts([
      'context:theme:brightness',
      'context:ancestor:1:theme:brightness',
      'context:ancestor:2:theme:brightness',
    ]);
    final inner = _slot(
        BuilderProgram(
            values: values,
            result: BuilderResult.body(0, values: {'label': values.root}),
            bodyCount: 1),
        '(body) => Label(value:body.values.label)');
    final middle =
        _slot(_outer, '(body) => Light(child:Native(builder:$inner))');
    final outer =
        _slot(_outer, '(body) => Dark(child:Native(builder:$middle))');
    final harness = _ContextHarness('widget Root = Native(builder:$outer);');
    await tester.pumpWidget(harness.widget);
    expect(tester.takeException(), isNull);
    expect(find.text('lightdarklight'), findsOneWidget);
  });

  testWidgets('root collections propagate their original context to bodies',
      (tester) async {
    final ordinary =
        '{version:1,program:${jsonEncode(_themeValue.encode())},captures:{}}';
    final children = _slot(
        BuilderProgram(
            values: _outer.values,
            result: const BuilderResult.body(0),
            bodyCount: 1,
            collection: true),
        '(row) => Dark(child:Label(value:$ordinary))');
    final harness =
        _ContextHarness('widget Root = Collection(children:$children);');
    await tester.pumpWidget(harness.widget);
    expect(tester.takeException(), isNull);
    expect(find.text('light'), findsOneWidget);
  });

  testWidgets('missing or invalid ancestor addresses fail when evaluated',
      (tester) async {
    for (final name in [
      'context:ancestor:1:theme:brightness',
      'context:ancestor:0:theme:brightness',
      'context:ancestor:65:theme:brightness',
    ]) {
      final values = _contexts([name]);
      final slot = _slot(
          BuilderProgram(
              values: values,
              result: BuilderResult.body(0, values: {'label': values.root}),
              bodyCount: 1),
          '(body) => Label(value:body.values.label)');
      final harness = _ContextHarness('widget Root = Native(builder:$slot);',
          catchErrors: true);
      await tester.pumpWidget(harness.widget);
      expect(tester.takeException(), isNull);
      expect(harness.errors.single, isA<FormatException>());
      expect(find.text('rejected'), findsOneWidget);
    }
  });

  testWidgets('global target platform is independent of the inherited theme',
      (tester) async {
    final themePlatform = defaultTargetPlatform == TargetPlatform.iOS
        ? TargetPlatform.android
        : TargetPlatform.iOS;
    final values = _contexts([
      'context:device:defaultTargetPlatform',
      'context:device:platform',
    ]);
    final slot = _slot(
        BuilderProgram(
            values: values,
            result: BuilderResult.body(0, values: {'label': values.root}),
            bodyCount: 1),
        '(body) => Label(value:body.values.label)');
    final harness = _ContextHarness('widget Root = Native(builder:$slot);');
    harness.theme.value = ThemeData(platform: themePlatform);
    await tester.pumpWidget(harness.widget);
    expect(tester.takeException(), isNull);
    expect(find.text('${defaultTargetPlatform.name}${themePlatform.name}'),
        findsOneWidget);
  });
}

final class _ContextHarness {
  _ContextHarness(String source, {bool catchErrors = false}) {
    addTearDown(theme.dispose);
    addTearDown(descendantTheme.dispose);
    runtime
      ..update(
          _local,
          LocalWidgetLibrary({
            kBuilderContinuationWidgetName: buildRestageBuilderContinuation,
            'Native': (context, source) =>
                RestageBuilderBinding.construct((bindings) {
                  final binding = RestageBuilderBinding(source, ['builder']);
                  bindings.add(binding);
                  return LayoutBuilder(builder: (context, constraints) {
                    try {
                      final result = binding.build(context, {});
                      returnedKeys.add(result.key);
                      return result;
                    } catch (error) {
                      if (!catchErrors) rethrow;
                      errors.add(error);
                      return const Text('rejected');
                    }
                  });
                }),
            'Collection': (context, source) =>
                RestageBuilderBinding.construct((bindings) {
                  final binding = RestageBuilderBinding(source, ['children']);
                  bindings.add(binding);
                  return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: binding.buildList(context, {}));
                }),
            'Label': (context, source) {
              source = RestageValueBinding.dataSource(source, context);
              return Text('${source.v<String>([
                        'prefix'
                      ]) ?? ''}${RestageValueBinding.read<String>(source, ['value'], context)}');
            },
            'Dark': (context, source) => ValueListenableBuilder<ThemeData>(
                  valueListenable: descendantTheme,
                  child: source.child(['child']),
                  builder: (context, theme, child) =>
                      Theme(data: theme, child: child!),
                ),
            'Light': (context, source) =>
                Theme(data: ThemeData.light(), child: source.child(['child'])),
            'Column': (context, source) => Column(
                mainAxisSize: MainAxisSize.min,
                children: source.childList(['children'])),
          }))
      ..update(_remote, rfw.parseLibraryFile('import restage.core; $source'));
  }

  final runtime = Runtime();
  final theme = ValueNotifier(ThemeData.light());
  final descendantTheme = ValueNotifier(ThemeData.dark());
  final errors = <Object>[];
  final returnedKeys = <Key?>[];
  Widget get widget => Directionality(
        textDirection: TextDirection.ltr,
        child: ValueListenableBuilder<ThemeData>(
          valueListenable: theme,
          builder: (context, theme, child) => Theme(data: theme, child: child!),
          child: Center(
            child: SizedBox(
              width: 300,
              height: 200,
              child: RemoteWidget(
                runtime: runtime,
                data: DynamicContent(),
                widget: const FullyQualifiedWidgetName(_remote, 'Root'),
              ),
            ),
          ),
        ),
      );
}
