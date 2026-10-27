import 'dart:convert';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/formats.dart' as rfw;
import 'package:rfw/rfw.dart';

const _root = LibraryName(['test']);
const _core = LibraryName(['restage', 'core']);
Widget _remote(String source) {
  final runtime = Runtime()
    ..update(_core, buildCoreWidgetLibrary())
    ..update(_root,
        rfw.parseLibraryFile('import restage.core; widget Root = $source;'));
  return RemoteWidget(
      runtime: runtime,
      data: DynamicContent(),
      widget: const FullyQualifiedWidgetName(_root, 'Root'));
}

Future<void> _pump(WidgetTester tester, Widget child, {double width = 300}) =>
    tester.pumpWidget(MaterialApp(
        home:
            Center(child: SizedBox(width: width, height: 180, child: child))));
List<Rect> _rects(WidgetTester tester) => [
      for (final label in ['a', 'b', 'c']) tester.getRect(find.text(label))
    ];

final class _Probe extends StatefulWidget {
  const _Probe({super.key, required this.id, this.onTap});
  final String id;
  final VoidCallback? onTap;
  @override
  State<_Probe> createState() => _ProbeState();
}

final class _ProbeState extends State<_Probe> {
  late final String initialId = widget.id;
  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: widget.onTap, child: Text('$initialId:${widget.id}'));
}

void main() {
  testWidgets('omitted native grid children retain Flutter empty defaults',
      (tester) async {
    for (final source in [
      'GridViewCount(crossAxisCount:2,primary:false)',
      'GridViewExtent(maxCrossAxisExtent:100.0,primary:false)',
      'GridView(gridDelegate:{_s:"SliverGridDelegateWithFixedCrossAxisCount",crossAxisCount:2},primary:false)',
    ]) {
      await _pump(tester, _remote(source));
      expect(tester.takeException(), isNull, reason: source);
      final delegate = tester
          .widget<GridView>(find.byType(GridView))
          .childrenDelegate as SliverChildListDelegate;
      expect(delegate.children, isEmpty);
    }
  });
  testWidgets(
      'count-less shrink-wrapped grids retain native finite termination',
      (tester) async {
    const items = ['a', 'b', 'c'];
    await _pump(
        tester,
        GridView.builder(
            primary: false,
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, mainAxisExtent: 30),
            itemBuilder: (_, index) =>
                index >= items.length ? null : Text(items[index])));
    final expected = _rects(tester);
    const list = ValueType('list', item: ValueType.string);
    const values = ValueProgram(
        nodes: [
          ValueNode('capture', list, name: 'c0'),
          ValueNode('parameter', ValueType.integer, name: 'arg1'),
          ValueNode('length', ValueType.integer, inputs: [0]),
          ValueNode('>=', ValueType.boolean, inputs: [1, 2]),
          ValueNode('index', ValueType.string, inputs: [0, 1]),
        ],
        root: 4,
        captures: {'c0': list},
        parameters: {'arg1': ValueType.integer});
    const program = BuilderProgram(
        values: values,
        result: BuilderResult.branch(3, BuilderResult.nullResult(),
            BuilderResult.body(0, values: {'label': 4})),
        bodyCount: 1,
        nullableResult: true);
    final slot =
        '__RestageBuilderContinuation(version:1,program:${jsonEncode(program.encode())},captures:{c0:data.items},bodies:[(s)=>Text(text:s.values.label)])';
    final runtime = Runtime()
      ..update(_core, buildCoreWidgetLibrary())
      ..update(
          _root,
          rfw.parseLibraryFile(
              'import restage.core; widget Root = GridViewBuilder(primary:false,shrinkWrap:true,gridDelegate:{_s:"SliverGridDelegateWithFixedCrossAxisCount",crossAxisCount:2,mainAxisExtent:30.0},itemBuilder:$slot);'));
    await _pump(
        tester,
        RemoteWidget(
            runtime: runtime,
            data: DynamicContent({'items': items}),
            widget: const FullyQualifiedWidgetName(_root, 'Root')));
    expect(_rects(tester), expected);
    expect(
        (tester.widget<GridView>(find.byType(GridView)).childrenDelegate
                as SliverChildBuilderDelegate)
            .childCount,
        isNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets('scalar native context stays lexical beneath a descendant Theme',
      (tester) async {
    const values = ValueProgram(
        nodes: [ValueNode('literal', ValueType.boolean, value: true)], root: 0);
    const outer = BuilderProgram(
        values: values, result: BuilderResult.body(0), bodyCount: 1);
    const semantic = ValueProgram(
        nodes: [
          ValueNode('parameter', ValueType.string,
              name: 'context:theme:brightness'),
          ValueNode('literal', ValueType.string, value: 'light'),
          ValueNode('==', ValueType.boolean, inputs: [0, 1]),
          ValueNode('parameter', ValueType.integer, name: 'arg1'),
          ValueNode('literal', ValueType.nullType, value: null),
          ValueNode('conditional', ValueType('int', nullable: true),
              inputs: [2, 3, 4]),
        ],
        root: 5,
        parameters: {
          'context:theme:brightness': ValueType.string,
          'arg1': ValueType.integer
        });
    final scalar =
        '__RestageBuilderContinuation(version:1,program:${jsonEncode(semantic.encode())},captures:{})';
    final body =
        '(s)=>DarkTheme(child:GridViewCustom(primary:false,gridDelegate:{_s:"SliverGridDelegateWithFixedCrossAxisCount",crossAxisCount:2},childrenDelegate:{_s:"SliverChildListDelegate",children:[Text(text:"a")],semanticIndexCallback:$scalar}))';
    final slot =
        '__RestageBuilderContinuation(version:1,program:${jsonEncode(outer.encode())},captures:{},bodies:[$body])';
    final runtime = Runtime()
      ..update(_core, buildCoreWidgetLibrary())
      ..update(
          const LibraryName(['probe']),
          LocalWidgetLibrary({
            'DarkTheme': (context, source) =>
                Theme(data: ThemeData.dark(), child: source.child(['child'])),
          }))
      ..update(
          _root,
          rfw.parseLibraryFile(
              'import restage.core; import probe; widget Root = LayoutBuilder(builder:$slot);'));
    await _pump(
        tester,
        RemoteWidget(
            runtime: runtime,
            data: DynamicContent(),
            widget: const FullyQualifiedWidgetName(_root, 'Root')));
    final grid = tester.widget<GridView>(find.byType(GridView));
    expect(Theme.of(tester.element(find.byType(GridView))).brightness,
        Brightness.dark);
    expect(
        (grid.childrenDelegate as SliverChildListDelegate)
            .semanticIndexCallback(const SizedBox(), 3),
        3);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'computed native delegate and cache scalars use the shared factory adapter',
      (tester) async {
    const list = ValueType('list', item: ValueType.string);
    const nodes = [
      ValueNode('capture', list, name: 'c0'),
      ValueNode('length', ValueType.integer, inputs: [0]),
      ValueNode('literal', ValueType.integer, value: 1),
      ValueNode('+', ValueType.integer, inputs: [1, 2]),
      ValueNode('literal', ValueType.integer, value: 10),
      ValueNode('*', ValueType.integer, inputs: [1, 4]),
      ValueNode('toDouble', ValueType.real, inputs: [5]),
      ValueNode('literal', ValueType.integer, value: 2),
      ValueNode('/', ValueType.real, inputs: [1, 7]),
      ValueNode('-', ValueType.integer, inputs: [1, 2]),
      ValueNode('literal', ValueType.integer, value: 0),
      ValueNode('>', ValueType.boolean, inputs: [1, 10]),
    ];
    String scalar(int root) {
      final program =
          ValueProgram(nodes: nodes, root: root, captures: const {'c0': list});
      return '{version:1,program:${jsonEncode(program.encode())},captures:{c0:data.items}}';
    }

    const builder = BuilderProgram(
        values: ValueProgram(
            nodes: [
              ValueNode('capture', list, name: 'c0'),
              ValueNode('parameter', ValueType.integer, name: 'arg1'),
              ValueNode('index', ValueType.string, inputs: [0, 1]),
            ],
            root: 2,
            captures: {'c0': list},
            parameters: {'arg1': ValueType.integer}),
        result: BuilderResult.body(0, values: {'label': 2}),
        bodyCount: 1,
        nullableResult: true);
    final slot =
        '__RestageBuilderContinuation(version:1,program:${jsonEncode(builder.encode())},captures:{c0:data.items},bodies:[(s)=>Text(text:s.values.label)])';
    const items = ['a', 'b'];
    await _pump(
        tester,
        GridView.custom(
            primary: false,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: items.length + 1,
                mainAxisExtent: items.length * 10),
            scrollCacheExtent: ScrollCacheExtent.viewport(items.length / 2),
            childrenDelegate: SliverChildBuilderDelegate(
                (_, index) => Text(items[index]),
                childCount: items.length,
                semanticIndexOffset: items.length - 1,
                addRepaintBoundaries: items.isNotEmpty)));
    final expected = [
      tester.getRect(find.text('a')),
      tester.getRect(find.text('b'))
    ];
    final runtime = Runtime()
      ..update(_core, buildCoreWidgetLibrary())
      ..update(
          _root,
          rfw.parseLibraryFile(
              'import restage.core; widget Root = GridViewCustom(primary:false,gridDelegate:{_s:"SliverGridDelegateWithFixedCrossAxisCount",crossAxisCount:${scalar(3)},mainAxisExtent:${scalar(6)}},scrollCacheExtent:{_s:"viewport",value:${scalar(8)}},childrenDelegate:{_s:"SliverChildBuilderDelegate",builder:$slot,childCount:${scalar(1)},semanticIndexOffset:${scalar(9)},addRepaintBoundaries:${scalar(11)}});'));
    await _pump(
        tester,
        RemoteWidget(
            runtime: runtime,
            data: DynamicContent({'items': items}),
            widget: const FullyQualifiedWidgetName(_root, 'Root')));
    expect([tester.getRect(find.text('a')), tester.getRect(find.text('b'))],
        expected);
    final grid = tester.widget<GridView>(find.byType(GridView));
    final delegate = grid.childrenDelegate as SliverChildBuilderDelegate;
    expect(delegate.childCount, 2);
    expect(delegate.semanticIndexOffset, 1);
    expect(delegate.addRepaintBoundaries, isTrue);
    expect(grid.scrollCacheExtent, const ScrollCacheExtent.viewport(1));
    expect(tester.takeException(), isNull);
  });
  testWidgets('mixed ValueKey generic identities stay distinct across reorder',
      (tester) async {
    await _pump(
        tester,
        GridView.count(primary: false, crossAxisCount: 2, children: const [
          _Probe(key: ValueKey<int>(1), id: 'int'),
          _Probe(key: ValueKey<double>(1.0), id: 'double'),
        ]));
    expect(tester.takeException(), isNull);
    const values = ValueProgram(
        nodes: [
          ValueNode('literal', ValueType.integer, value: 1),
          ValueNode('literal', ValueType.real, value: 1.0),
          ValueNode('literal', ValueType.string, value: 'int'),
          ValueNode('literal', ValueType.string, value: 'double'),
          ValueNode('capture', ValueType.boolean, name: 'c0'),
        ],
        root: 4,
        captures: {'c0': ValueType.boolean});
    const integer =
        BuilderResult.body(0, values: {'id': 2}, key: 0, keyType: 'int');
    const real =
        BuilderResult.body(1, values: {'id': 3}, key: 1, keyType: 'double');
    const program = BuilderProgram(
        values: values,
        result: BuilderResult.branch(4, BuilderResult.sequence([real, integer]),
            BuilderResult.sequence([integer, real])),
        bodyCount: 2,
        collection: true);
    final slot =
        '__RestageBuilderContinuation(version:1,program:${jsonEncode(program.encode())},captures:{c0:data.swap},bodies:[(s)=>Probe(id:s.values.id),(s)=>Probe(id:s.values.id)])';
    final runtime = Runtime()
      ..update(_core, buildCoreWidgetLibrary())
      ..update(
          const LibraryName(['probe']),
          LocalWidgetLibrary({
            'Probe': (context, source) => _Probe(id: source.v<String>(['id'])!),
          }))
      ..update(
          _root,
          rfw.parseLibraryFile(
              'import restage.core; import probe; widget Root = GridViewCount(primary:false,crossAxisCount:2,children:$slot);'));
    final data = DynamicContent({'swap': false});
    await _pump(
        tester,
        RemoteWidget(
            runtime: runtime,
            data: data,
            widget: const FullyQualifiedWidgetName(_root, 'Root')));
    expect(find.text('int:int'), findsOneWidget);
    expect(find.text('double:double'), findsOneWidget);
    expect(tester.takeException(), isNull);
    data.update('swap', true);
    await tester.pump();
    expect(find.text('int:int'), findsOneWidget);
    expect(find.text('double:double'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'scalar key callbacks preserve native generic casts and ignored keys',
      (tester) async {
    const keyShape = ValueType('record', fields: {'value': ValueType.number});
    const read = ValueProgram(
        nodes: [
          ValueNode('parameter', keyShape, name: 'arg0'),
          ValueNode('field', ValueType.number, inputs: [0], name: 'value'),
          ValueNode('toInt', ValueType.integer, inputs: [1]),
        ],
        root: 2,
        parameters: {'arg0': keyShape});
    const constant = ValueProgram(
        nodes: [ValueNode('literal', ValueType.integer, value: 7)], root: 0);
    Object? actual;
    Object? failure;
    Key nativeKey = const ValueKey<int>(1);
    final runtime = Runtime()
      ..update(_core, buildCoreWidgetLibrary())
      ..update(
          const LibraryName(['probe']),
          LocalWidgetLibrary({
            'KeyProbe': (context, source) =>
                RestageBuilderBinding.construct((bindings) {
                  final binding = RestageBuilderBinding(
                      source, const ['callback'],
                      scalarContract: const ScalarCallbackContract(
                          parameters: [ScalarCallbackParameter.valueKey]));
                  bindings.add(binding);
                  try {
                    actual = binding.evaluateKey(context, nativeKey);
                  } catch (error) {
                    failure = error;
                  }
                  return const SizedBox();
                }),
          }));
    Future<void> run(ValueProgram program, Key key) async {
      await tester.pumpWidget(const SizedBox());
      nativeKey = key;
      actual = null;
      failure = null;
      final slot =
          '__RestageBuilderContinuation(version:1,program:${jsonEncode(program.encode())},captures:{})';
      runtime.update(
          _root,
          rfw.parseLibraryFile(
              'import restage.core; import probe; widget Root = KeyProbe(callback:$slot);'));
      await _pump(
          tester,
          RemoteWidget(
              runtime: runtime,
              data: DynamicContent(),
              widget: const FullyQualifiedWidgetName(_root, 'Root')));
    }

    await run(read, const ValueKey<int>(1));
    expect(actual, 1);
    expect(failure, isNull);
    await run(read, const ValueKey<Object>(1));
    expect(failure, isA<TypeError>());
    const guarded = ValueProgram(
        nodes: [
          ValueNode('parameter', keyShape, name: 'arg0'),
          ValueNode('field', ValueType.number, inputs: [0], name: 'value'),
          ValueNode('toInt', ValueType.integer, inputs: [1]),
          ValueNode('literal', ValueType.boolean, value: true),
          ValueNode('literal', ValueType.integer, value: 0),
          ValueNode('conditional', ValueType.integer, inputs: [3, 4, 2]),
        ],
        root: 5,
        parameters: {'arg0': keyShape});
    await run(guarded, const ValueKey<Object>(1));
    expect(actual, 0);
    expect(failure, isNull);
    const eagerCast = ValueProgram(
        nodes: [
          ValueNode('parameter', keyShape, name: 'arg0'),
          ValueNode('field', ValueType.number, inputs: [0], name: 'value'),
          ValueNode('let', keyShape, inputs: [1, 0]),
          ValueNode('literal', ValueType.integer, value: 7),
          ValueNode('let', ValueType.integer, inputs: [2, 3]),
        ],
        root: 4,
        parameters: {'arg0': keyShape});
    await run(eagerCast, const ValueKey<Object>(1));
    expect(failure, isA<TypeError>());

    await run(constant, ObjectKey(Object()));
    expect(actual, 7);
    expect(failure, isNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets('grid geometry follows nested native layout constraints',
      (tester) async {
    const shape = ValueType('record', fields: {'maxWidth': ValueType.real});
    const values = ValueProgram(
        nodes: [
          ValueNode('parameter', shape, name: 'arg1'),
          ValueNode('field', ValueType.real, inputs: [0], name: 'maxWidth'),
          ValueNode('literal', ValueType.real, value: 400.0),
          ValueNode('>=', ValueType.boolean, inputs: [1, 2]),
          ValueNode('literal', ValueType.integer, value: 3),
          ValueNode('literal', ValueType.integer, value: 2),
          ValueNode('conditional', ValueType.integer, inputs: [3, 4, 5]),
        ],
        root: 6,
        parameters: {'arg1': shape});
    const program = BuilderProgram(
        values: values,
        result: BuilderResult.body(0, values: {'count': 6}),
        bodyCount: 1);
    final slot =
        '__RestageBuilderContinuation(version:1,program:${jsonEncode(program.encode())},captures:{},bodies:[(s)=>GridViewCount(crossAxisCount:s.values.count,primary:false,mainAxisExtent:43.0,children:[Text(text:"a"),Text(text:"b"),Text(text:"c")])])';
    for (final width in [300.0, 500.0]) {
      await _pump(
          tester,
          LayoutBuilder(
              builder: (context, c) => GridView.count(
                  crossAxisCount: c.maxWidth >= 400 ? 3 : 2,
                  primary: false,
                  mainAxisExtent: 43,
                  children: const [Text('a'), Text('b'), Text('c')])),
          width: width);
      final expected = _rects(tester);
      await _pump(tester, _remote('LayoutBuilder(builder:$slot)'),
          width: width);
      expect(_rects(tester), expected);
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('count and extent preserve native geometry and scalar flags',
      (tester) async {
    for (final extent in [false, true]) {
      Widget native() => extent
          ? GridView.extent(
              maxCrossAxisExtent: 120,
              mainAxisExtent: 43,
              crossAxisSpacing: 7,
              mainAxisSpacing: 11,
              padding: const EdgeInsets.all(9),
              primary: false,
              reverse: true,
              addAutomaticKeepAlives: false,
              addRepaintBoundaries: false,
              addSemanticIndexes: false,
              dragStartBehavior: DragStartBehavior.down,
              clipBehavior: Clip.hardEdge,
              hitTestBehavior: HitTestBehavior.translucent,
              children: const [Text('a'), Text('b'), Text('c')])
          : GridView.count(
              crossAxisCount: 2,
              mainAxisExtent: 43,
              crossAxisSpacing: 7,
              mainAxisSpacing: 11,
              padding: const EdgeInsets.all(9),
              primary: false,
              reverse: true,
              addAutomaticKeepAlives: false,
              addRepaintBoundaries: false,
              addSemanticIndexes: false,
              dragStartBehavior: DragStartBehavior.down,
              clipBehavior: Clip.hardEdge,
              hitTestBehavior: HitTestBehavior.translucent,
              children: const [Text('a'), Text('b'), Text('c')]);
      await _pump(tester, native());
      final expected = _rects(tester);
      final source =
          '${extent ? 'GridViewExtent(maxCrossAxisExtent:120.0' : 'GridViewCount(crossAxisCount:2'},mainAxisExtent:43.0,crossAxisSpacing:7.0,mainAxisSpacing:11.0,padding:[9.0,9.0,9.0,9.0],primary:false,reverse:true,addAutomaticKeepAlives:false,addRepaintBoundaries:false,addSemanticIndexes:false,dragStartBehavior:"down",clipBehavior:"hardEdge",hitTestBehavior:"translucent",children:[Text(text:"a"),Text(text:"b"),Text(text:"c")])';
      await _pump(tester, _remote(source));
      expect(_rects(tester), expected);
      final grid = tester.widget<GridView>(find.byType(GridView));
      expect(grid.primary, isFalse);
      expect(grid.reverse, isTrue);
      expect(grid.dragStartBehavior, DragStartBehavior.down);
      expect(grid.hitTestBehavior, HitTestBehavior.translucent);
      final delegate = grid.childrenDelegate as SliverChildListDelegate;
      expect(delegate.addAutomaticKeepAlives, isFalse);
      expect(delegate.addRepaintBoundaries, isFalse);
      expect(delegate.addSemanticIndexes, isFalse);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('unnamed and custom construct standard native delegates',
      (tester) async {
    for (final custom in [false, true]) {
      final source =
          '${custom ? 'GridViewCustom' : 'GridView'}(primary:false,gridDelegate:{_s:"SliverGridDelegateWithMaxCrossAxisExtent",maxCrossAxisExtent:120.0,mainAxisExtent:50.0},${custom ? 'childrenDelegate:{_s:"SliverChildListDelegate",fixed:true,semanticIndexOffset:3,children:[Text(text:"a"),Text(text:"b"),Text(text:"c")]}' : 'children:[Text(text:"a"),Text(text:"b"),Text(text:"c")]'},physics:{_s:"BouncingScrollPhysics",parent:{_s:"AlwaysScrollableScrollPhysics"}},scrollCacheExtent:{_s:"viewport",value:0.5})';
      await _pump(tester, _remote(source));
      final grid = tester.widget<GridView>(find.byType(GridView));
      expect(
          grid.gridDelegate, isA<SliverGridDelegateWithMaxCrossAxisExtent>());
      expect(grid.physics, isA<BouncingScrollPhysics>());
      expect(grid.physics!.parent, isA<AlwaysScrollableScrollPhysics>());
      expect(grid.scrollCacheExtent, const ScrollCacheExtent.viewport(0.5));
      if (custom)
        expect(
            (grid.childrenDelegate as SliverChildListDelegate)
                .semanticIndexOffset,
            3);
      if (custom) {
        expect(
            identical(
                (grid.childrenDelegate as SliverChildListDelegate)
                    .semanticIndexCallback,
                const SliverChildListDelegate.fixed(<Widget>[])
                    .semanticIndexCallback),
            isTrue);
      }

      expect(find.text('a'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets(
      'builder remains lazy and nullable guard survives recycling and updates',
      (tester) async {
    for (final custom in [false, true]) {
      await tester.pumpWidget(const SizedBox());
      const item = ValueType('record',
          fields: {'id': ValueType.string, 'title': ValueType.string});
      const items = ValueType('list', item: item);
      const values = ValueProgram(
          nodes: [
            ValueNode('capture', items, name: 'c0'),
            ValueNode('parameter', ValueType.integer, name: 'arg1'),
            ValueNode('length', ValueType.integer, inputs: [0]),
            ValueNode('>=', ValueType.boolean, inputs: [1, 2]),
            ValueNode('index', item, inputs: [0, 1]),
            ValueNode('field', ValueType.string, inputs: [4], name: 'title'),
            ValueNode('field', ValueType.string, inputs: [4], name: 'id'),
          ],
          root: 5,
          captures: {'c0': items},
          parameters: {'arg1': ValueType.integer});
      const program = BuilderProgram(
          values: values,
          result: BuilderResult.branch(
              3,
              BuilderResult.nullResult(),
              BuilderResult.body(0,
                  values: {'label': 5}, key: 6, keyType: 'String')),
          bodyCount: 1,
          nullableResult: true);
      final slot =
          '__RestageBuilderContinuation(version:1,program:${jsonEncode(program.encode())},captures:{c0:data.items},bodies:[(s)=>Text(text:s.values.label)])';
      const semantic = ValueProgram(
          nodes: [
            ValueNode('parameter', ValueType.integer, name: 'arg1'),
            ValueNode('literal', ValueType.integer, value: 2),
            ValueNode('%', ValueType.integer, inputs: [0, 1]),
            ValueNode('literal', ValueType.integer, value: 0),
            ValueNode('==', ValueType.boolean, inputs: [2, 3]),
            ValueNode('~/', ValueType.integer, inputs: [0, 1]),
            ValueNode('literal', ValueType.nullType, value: null),
            ValueNode('conditional', ValueType('int', nullable: true),
                inputs: [4, 5, 6]),
          ],
          root: 7,
          parameters: {'arg1': ValueType.integer});
      final semanticSlot =
          '__RestageBuilderContinuation(version:1,program:${jsonEncode(semantic.encode())},captures:{})';
      final gridSource = custom
          ? 'GridViewCustom(primary:false,gridDelegate:{_s:"SliverGridDelegateWithFixedCrossAxisCount",crossAxisCount:2,mainAxisExtent:50.0},scrollCacheExtent:{_s:"pixels",value:0.0},childrenDelegate:{_s:"SliverChildBuilderDelegate",builder:$slot,semanticIndexCallback:$semanticSlot,addRepaintBoundaries:false})'
          : 'GridViewBuilder(primary:false,gridDelegate:{_s:"SliverGridDelegateWithFixedCrossAxisCount",crossAxisCount:2,mainAxisExtent:50.0},scrollCacheExtent:{_s:"pixels",value:0.0},itemBuilder:$slot)';
      final runtime = Runtime()
        ..update(_core, buildCoreWidgetLibrary())
        ..update(
            _root,
            rfw.parseLibraryFile(
                'import restage.core; widget Root = $gridSource;'));
      final records = [
        for (var i = 0; i < 10000; i++) {'id': 'id$i', 'title': 'item$i'}
      ];
      final data = DynamicContent({'items': records});
      await _pump(
          tester,
          RemoteWidget(
              runtime: runtime,
              data: data,
              widget: const FullyQualifiedWidgetName(_root, 'Root')));
      final grid = tester.widget<GridView>(find.byType(GridView));
      expect((grid.childrenDelegate as SliverChildBuilderDelegate).childCount,
          isNull);
      expect(grid.semanticChildCount, isNull);
      if (custom) {
        final delegate = grid.childrenDelegate as SliverChildBuilderDelegate;
        expect(delegate.addRepaintBoundaries, isFalse);
        expect(delegate.semanticIndexCallback(const SizedBox(), 3), isNull);
        expect(delegate.semanticIndexCallback(const SizedBox(), 4), 2);
      }

      expect(find.text('item0'), findsOneWidget);
      expect(find.byType(Text).evaluate().length, lessThan(100));
      tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position
          .jumpTo(3000);
      await tester.pump();
      expect(find.text('item120'), findsOneWidget);
      expect(find.text('item0'), findsNothing);
      expect(find.byType(Text).evaluate().length, lessThan(100));
      tester.state<ScrollableState>(find.byType(Scrollable)).position.jumpTo(0);
      data.update('items', records.take(2).toList());
      await tester.pump();
      expect(find.text('item0'), findsOneWidget);
      expect(find.text('item1'), findsOneWidget);
      expect(find.text('item2'), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets(
      'native key-index callback retains child state and event identity on reorder',
      (tester) async {
    for (final list in [false, true]) {
      await tester.pumpWidget(const SizedBox());
      const item = ValueType('record', fields: {'id': ValueType.string});
      const items = ValueType('list', item: item);
      const key = ValueType('record', fields: {'value': ValueType.string});
      const predicate = ValueProgram(
          nodes: [
            ValueNode('parameter', item, name: 'item'),
            ValueNode('field', ValueType.string, inputs: [0], name: 'id'),
            ValueNode('parameter', ValueType.string, name: 'outer0'),
            ValueNode('==', ValueType.boolean, inputs: [1, 2]),
          ],
          root: 3,
          parameters: {'item': item, 'outer0': ValueType.string});
      final lookup = ValueProgram(
          nodes: [
            const ValueNode('capture', items, name: 'c0'),
            const ValueNode('parameter', key, name: 'arg0'),
            const ValueNode('field', ValueType.string,
                inputs: [1], name: 'value'),
            ValueNode('grid.indexWhere', ValueType.integer,
                inputs: const [0, 2], value: predicate.encode()),
          ],
          root: 3,
          captures: const {'c0': items},
          parameters: const {'arg0': key});
      const values = ValueProgram(
          nodes: [
            ValueNode('capture', items, name: 'c0'),
            ValueNode('parameter', ValueType.integer, name: 'arg1'),
            ValueNode('index', item, inputs: [0, 1]),
            ValueNode('field', ValueType.string, inputs: [2], name: 'id'),
          ],
          root: 3,
          captures: {'c0': items},
          parameters: {'arg1': ValueType.integer});
      const builder = BuilderProgram(
          values: values,
          result: BuilderResult.body(0,
              values: {'id': 3}, key: 3, keyType: 'String'),
          bodyCount: 1,
          nullableResult: true);
      final slot =
          '__RestageBuilderContinuation(version:1,program:${jsonEncode(builder.encode())},captures:{c0:data.items},bodies:[(s)=>Probe(id:s.values.id,onTap:event "tap" {id:s.values.id})])';
      final indexSlot =
          '__RestageBuilderContinuation(version:1,program:${jsonEncode(lookup.encode())},captures:{c0:data.items})';
      final collection = BuilderProgram(
          values: ValueProgram(
              nodes: [
                ...values.nodes,
                const ValueNode('length', ValueType.integer, inputs: [0])
              ],
              root: values.root,
              captures: values.captures,
              parameters: values.parameters),
          result: const BuilderResult.forEach(
              4,
              'arg1',
              BuilderResult.body(0,
                  values: {'id': 3}, key: 3, keyType: 'String')),
          bodyCount: 1,
          collection: true);
      final listSlot =
          '__RestageBuilderContinuation(version:1,program:${jsonEncode(collection.encode())},captures:{c0:data.items},bodies:[(s)=>Probe(id:s.values.id,onTap:event "tap" {id:s.values.id})])';
      final gridSource = list
          ? 'GridViewCount(primary:false,crossAxisCount:2,mainAxisExtent:50.0,children:$listSlot)'
          : 'GridViewBuilder(primary:false,gridDelegate:{_s:"SliverGridDelegateWithFixedCrossAxisCount",crossAxisCount:2,mainAxisExtent:50.0},itemCount:4,itemBuilder:$slot,findChildIndexCallback:$indexSlot)';
      final runtime = Runtime()
        ..update(_core, buildCoreWidgetLibrary())
        ..update(
            const LibraryName(['probe']),
            LocalWidgetLibrary({
              'Probe': (context, source) => _Probe(
                  id: source.v<String>(['id'])!,
                  onTap: source.voidHandler(['onTap'])),
            }))
        ..update(
            _root,
            rfw.parseLibraryFile(
                'import restage.core; import probe; widget Root = $gridSource;'));
      final data = DynamicContent({
        'items': [
          for (final id in ['a', 'b', 'c', 'd']) {'id': id}
        ]
      });
      final events = <Object?>[];
      await _pump(
          tester,
          RemoteWidget(
              runtime: runtime,
              data: data,
              onEvent: (name, args) => events.add(args['id']),
              widget: const FullyQualifiedWidgetName(_root, 'Root')));
      expect(find.text('a:a'), findsOneWidget);
      data.update('items', [
        for (final id in ['c', 'a', 'd', 'b']) {'id': id}
      ]);
      await tester.pump();
      for (final id in ['a', 'b', 'c', 'd'])
        expect(find.text('$id:$id'), findsOneWidget);
      await tester.tap(find.text('c:c'));
      expect(events, ['c']);
      expect(tester.takeException(), isNull);
    }
  });
}
