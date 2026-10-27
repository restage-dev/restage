import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart' as rfw;
import 'package:rfw/rfw.dart';

const _root = LibraryName(['test']);
const _core = LibraryName(['restage', 'core']);
String slot(BuilderProgram program, List<String> bodies) =>
    '__RestageBuilderContinuation(version:1,program:${jsonEncode(program.encode())},captures:{},bodies:[${bodies.join(',')}])';
Future<void> pump(WidgetTester tester, String source, Size size,
    {ThemeData? theme, bool unbounded = false}) async {
  final runtime = Runtime()
    ..update(_core, buildCoreWidgetLibrary())
    ..update(_root,
        rfw.parseLibraryFile('import restage.core; widget Root = $source;'));
  Widget target = RemoteWidget(
      runtime: runtime,
      data: DynamicContent(),
      widget: const FullyQualifiedWidgetName(_root, 'Root'));
  if (unbounded) target = UnconstrainedBox(child: target);
  await tester.pumpWidget(Theme(
      data: theme ?? ThemeData.light(),
      child: MediaQuery(
          data: const MediaQueryData(size: Size(1200, 800)),
          child: Directionality(
              textDirection: TextDirection.ltr,
              child: Center(
                  child: SizedBox(
                      width: size.width,
                      height: size.height,
                      child: target))))));
}

void main() {
  testWidgets('omitted native Row and Column children retain empty defaults',
      (tester) async {
    for (final name in ['Row', 'Column']) {
      await pump(tester, '$name()', const Size(300, 200));
      expect(tester.takeException(), isNull);
      final children = name == 'Row'
          ? tester
              .widget<Row>(find.byWidgetPredicate((widget) => widget is Row))
              .children
          : tester
              .widget<Column>(
                  find.byWidgetPredicate((widget) => widget is Column))
              .children;
      expect(children, isEmpty);
    }
  });

  testWidgets('orientation interpolation and name match native Dart',
      (tester) async {
    const program = BuilderProgram(
        values: ValueProgram(
            nodes: [
              ValueNode('parameter', ValueType.string, name: 'arg1'),
              ValueNode('literal', ValueType.string, value: 'Orientation.'),
              ValueNode('concat', ValueType.string, inputs: [1, 0]),
              ValueNode('literal', ValueType.string, value: '|'),
              ValueNode('concat', ValueType.string, inputs: [2, 3, 0, 3, 2]),
              ValueNode('literal', ValueType.string, value: 'portrait'),
              ValueNode('==', ValueType.boolean, inputs: [0, 5]),
              ValueNode('literal', ValueType.nullType),
              ValueNode('conditional', ValueType('String', nullable: true),
                  inputs: [6, 7, 0]),
              ValueNode('nonNull', ValueType.string, inputs: [8]),
              ValueNode('concat', ValueType.string, inputs: [1, 9]),
              ValueNode('literal', ValueType.string, value: 'null'),
              ValueNode('conditional', ValueType.string, inputs: [6, 11, 10]),
              ValueNode('string', ValueType.string, inputs: [8]),
              ValueNode('concat', ValueType.string, inputs: [4, 3, 12, 3, 13]),
            ],
            root: 14,
            parameters: {'arg1': ValueType.string}),
        result: BuilderResult.body(0, values: {'label': 14}),
        bodyCount: 1);
    final source = 'OrientationBuilder(builder:${slot(program, [
          '(frame)=>Text(text:frame.values.label)'
        ])})';
    for (final size in [const Size(200, 600), const Size(600, 200)]) {
      late String native;
      await tester.pumpWidget(Center(
          child: SizedBox(
              width: size.width,
              height: size.height,
              child: OrientationBuilder(builder: (context, orientation) {
                final Orientation? nullable =
                    orientation == Orientation.portrait ? null : orientation;
                native =
                    '$orientation|${orientation.name}|${orientation.toString()}|$nullable|${nullable?.name}';
                return const SizedBox();
              }))));
      await pump(tester, source, size);
      expect(tester.takeException(), isNull);
      expect(find.text(native), findsOneWidget);
    }
  });

  testWidgets('native unbounded constraints retain infinity behind lazy guards',
      (tester) async {
    const shape = ValueType('record', fields: {
      'maxWidth': ValueType.real,
      'hasBoundedWidth': ValueType.boolean
    });
    const program = BuilderProgram(
        values: ValueProgram(
            nodes: [
              ValueNode('parameter', shape, name: 'arg1'),
              ValueNode('field', ValueType.boolean,
                  inputs: [0], name: 'hasBoundedWidth'),
              ValueNode('field', ValueType.real, inputs: [0], name: 'maxWidth'),
              ValueNode('literal', ValueType.integer, value: 2),
              ValueNode('/', ValueType.real, inputs: [2, 3]),
              ValueNode('literal', ValueType.real, value: 80.0),
              ValueNode('conditional', ValueType.real, inputs: [1, 4, 5]),
            ],
            root: 6,
            parameters: {'arg1': shape}),
        result: BuilderResult.body(0, values: {'width': 6}),
        bodyCount: 1);
    final source = 'LayoutBuilder(builder:${slot(program, [
          '(frame)=>SizedBox(width:frame.values.width,height:20.0,child:Text(text:"finite"))'
        ])})';
    await pump(tester, source, const Size(300, 200), unbounded: true);
    expect(tester.takeException(), isNull);
    expect(
        tester
            .widgetList<SizedBox>(find.byType(SizedBox))
            .where((box) => box.width == 80),
        isNotEmpty);
  });

  testWidgets('generated Column decodes ordered collection continuations',
      (tester) async {
    const labels = ValueType('list', item: ValueType.string);
    const program = BuilderProgram(
        values: ValueProgram(
            nodes: [
              ValueNode('capture', labels, name: 'labels'),
              ValueNode('length', ValueType.integer, inputs: [0]),
              ValueNode('parameter', ValueType.integer, name: 'i'),
              ValueNode('index', ValueType.string, inputs: [0, 2]),
            ],
            root: 3,
            captures: {'labels': labels},
            parameters: {'i': ValueType.integer}),
        result: BuilderResult.forEach(
            1, 'i', BuilderResult.body(0, values: {'label': 3})),
        bodyCount: 1,
        collection: true);
    final children = slot(program, ['(frame)=>Text(text:frame.values.label)'])
        .replaceFirst('captures:{}', "captures:{labels:['first','second']}");
    await pump(tester, 'Column(children:$children)', const Size(300, 200));
    expect(tester.takeException(), isNull);
    expect(tester.getTopLeft(find.text('first')).dy,
        lessThan(tester.getTopLeft(find.text('second')).dy));
  });

  testWidgets('captured list updates and newly requested indices remain lazy',
      (tester) async {
    const item = ValueType('record', fields: {'title': ValueType.string});
    const list = ValueType('list', item: item);
    const constraints =
        ValueType('record', fields: {'maxWidth': ValueType.real});
    const values = ValueProgram(
        nodes: [
          ValueNode('capture', list, name: 'items'),
          ValueNode('parameter', constraints, name: 'arg1'),
          ValueNode('field', ValueType.real, inputs: [1], name: 'maxWidth'),
          ValueNode('literal', ValueType.real, value: 400.0),
          ValueNode('>=', ValueType.boolean, inputs: [2, 3]),
          ValueNode('literal', ValueType.integer, value: 1),
          ValueNode('literal', ValueType.integer, value: 0),
          ValueNode('conditional', ValueType.integer, inputs: [4, 5, 6]),
          ValueNode('index', item, inputs: [0, 7]),
          ValueNode('field', ValueType.string, inputs: [8], name: 'title'),
        ],
        root: 9,
        captures: {'items': list},
        parameters: {'arg1': constraints});
    const program = BuilderProgram(
        values: values,
        result: BuilderResult.body(0, values: {'title': 9}),
        bodyCount: 1);
    final source = slot(program, ['(scope) => Text(text:scope.values.title)'])
        .replaceFirst('captures:{}', 'captures:{items:data.items}');
    final runtime = Runtime()
      ..update(_core, buildCoreWidgetLibrary())
      ..update(
          _root,
          rfw.parseLibraryFile(
              'import restage.core; widget Root = LayoutBuilder(builder:$source);'));
    final data = DynamicContent({
      'items': List.generate(10000, (i) => {'title': 'item $i'})
    });
    final remote = RemoteWidget(
        runtime: runtime,
        data: data,
        widget: const FullyQualifiedWidgetName(_root, 'Root'));
    Widget parent(double width) => Directionality(
        textDirection: TextDirection.ltr,
        child:
            Center(child: SizedBox(width: width, height: 100, child: remote)));
    await tester.pumpWidget(parent(320));
    expect(tester.takeException(), isNull);
    expect(find.text('item 0'), findsOneWidget);
    data.update('items', List.generate(10000, (i) => {'title': 'updated $i'}));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('updated 0'), findsOneWidget);
    await tester.pumpWidget(parent(500));
    expect(tester.takeException(), isNull);
    expect(find.text('updated 1'), findsOneWidget);
  });

  testWidgets('native layout uses parent constraints across resize',
      (tester) async {
    const shape = ValueType('record', fields: {'maxWidth': ValueType.real});
    const values = ValueProgram(
        nodes: [
          ValueNode('parameter', shape, name: 'arg1'),
          ValueNode('field', ValueType.real, inputs: [0], name: 'maxWidth'),
          ValueNode('literal', ValueType.integer, value: 2),
          ValueNode('/', ValueType.real, inputs: [1, 2]),
          ValueNode('literal', ValueType.real, value: 400.0),
          ValueNode('>=', ValueType.boolean, inputs: [1, 4]),
          ValueNode('literal', ValueType.string, value: 'wide'),
          ValueNode('literal', ValueType.string, value: 'narrow'),
          ValueNode('conditional', ValueType.string, inputs: [5, 6, 7])
        ],
        root: 3,
        parameters: {'arg1': shape});
    const program = BuilderProgram(
        values: values,
        result: BuilderResult.body(0, values: {'width': 3, 'label': 8}),
        bodyCount: 1);
    final source = 'LayoutBuilder(builder:${slot(program, [
          '(scope) => SizedBox(width:scope.values.width,child:Text(text:scope.values.label))'
        ])})';
    for (final (width, label) in [(320.0, 'narrow'), (500.0, 'wide')]) {
      await pump(tester, source, Size(width, 100));
      final boxes = tester
          .widgetList<SizedBox>(find.byType(SizedBox))
          .where((box) => box.width == width / 2);
      expect(boxes, isNotEmpty);
      expect(find.text(label), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('native orientation uses local dimensions not MediaQuery',
      (tester) async {
    const values = ValueProgram(
        nodes: [ValueNode('parameter', ValueType.string, name: 'arg1')],
        root: 0,
        parameters: {'arg1': ValueType.string});
    const program = BuilderProgram(
        values: values,
        result: BuilderResult.body(0, values: {'label': 0}),
        bodyCount: 1);
    final source = 'OrientationBuilder(builder:${slot(program, [
          '(scope) => Text(text:scope.values.label)'
        ])})';
    for (final (size, label) in [
      (const Size(200, 600), 'portrait'),
      (const Size(600, 200), 'landscape'),
      (const Size(200, 200), 'portrait')
    ]) {
      await pump(tester, source, size);
      expect(find.text(label), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('callback context reads the current inherited theme',
      (tester) async {
    const values = ValueProgram(
        nodes: [
          ValueNode('parameter', ValueType.string,
              name: 'context:theme:brightness')
        ],
        root: 0,
        parameters: {'context:theme:brightness': ValueType.string});
    const program = BuilderProgram(
        values: values,
        result: BuilderResult.body(0, values: {'label': 0}),
        bodyCount: 1);
    final source = 'LayoutBuilder(builder:${slot(program, [
          '(scope) => Text(text:scope.values.label)'
        ])})';
    for (final brightness in [Brightness.dark, Brightness.light]) {
      await pump(tester, source, const Size(300, 200),
          theme: ThemeData(brightness: brightness));
      expect(find.text(brightness.name), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
