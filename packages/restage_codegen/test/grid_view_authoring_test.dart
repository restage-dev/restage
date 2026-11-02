import 'package:restage_compiler_core/restage_compiler_core.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/host_data_shape.dart';
import 'dart:io';
import 'dart:isolate';

import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/factory_emitter.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;
import 'package:test/test.dart';

import 'helpers.dart';

final class _LengthReader implements ValueReader {
  @override
  int length(List<Object> path) => 2;
  @override
  Object? read(List<Object> path, ValueType type) =>
      throw StateError('Unexpected item read');
}

void main() {
  Future<Catalog> catalog() async {
    final uri = await Isolate.resolvePackageUri(
      Uri.parse('package:restage_core/src/widget_catalog/catalog.json'),
    );
    return decodeCatalog(File.fromUri(uri!).readAsStringSync());
  }

  test(
    'required nullable scalar callback preserves canonical supplied null',
    () async {
      final source = await parseExpressionFromSourceForTest("""
import 'package:flutter/widgets.dart';
Widget x()=>Probe(callback:null);
class Probe extends StatelessWidget {
 const Probe({required this.callback});
 final int? Function(Key)? callback;
 Widget build(BuildContext context)=>const SizedBox();
}
""", rootPackage: 'apps_examples');
      const property = PropertyEntry(
        wireId: WireId.unallocatedProperty,
        name: 'callback',
        type: PropertyType.scalarCallback,
        description: '',
        required: true,
        constructorNullable: true,
        scalarContract: ScalarCallbackContract(
          parameters: [ScalarCallbackParameter.valueKey],
        ),
      );
      final widget = entry(
        name: 'Probe',
        flutterType: 'package:apps_examples/_expr_probe.dart#Probe',
        properties: [property],
      );
      final registry = catalogWith([widget]);
      final result = ExpressionTranslator(
        catalog: registry,
        helpers: HelperRegistry(),
      ).translate(source);
      expect(
        result.issues,
        isEmpty,
        reason: result.issues.map((issue) => issue.message).join('\n'),
      );
      final library = rfw.parseLibraryFile(
        'import restage.core; widget Root=${result.dsl};',
      );
      final root = library.widgets.single.root as rfw.ConstructorCall;
      expect(root.arguments['callback'], {
        RfwConstructorPresenceProtocol.markerKey: 1,
      });
      expect(deriveSurfaceCapability(library, registry).builtInFloor, 1);
      for (final raw in ['Probe()', 'Probe(callback:null)']) {
        expect(
          () => deriveSurfaceCapability(
            rfw.parseLibraryFile('import restage.core; widget Root=$raw;'),
            registry,
          ),
          throwsFormatException,
        );
      }
      final factory = emitFactoryFunction(
        widget,
      )!.replaceAll(RegExp(r'\s+'), ' ');
      expect(
        factory,
        contains(
          'RestageDecoders.keyIndexCallback(context, source, '
          'restagePresenceCallback.valuePath, bindings: builderBindings)',
        ),
      );
      expect(
        factory,
        contains('if (restagePresenceCallback.supplied) #callback:'),
      );
      expect(factory, contains('Function.apply(Probe.new,'));
    },
  );

  test(
    'optional native key callbacks preserve null and omission equivalence',
    () async {
      final registry = await catalog();
      for (final custom in [false, true]) {
        for (final supplied in [false, true]) {
          final callback = supplied ? ',findChildIndexCallback:null' : '';
          final value = custom
              ? 'GridView.custom(gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:2),childrenDelegate:SliverChildBuilderDelegate((_,i)=>null$callback))'
              : 'GridView.builder(gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:2),itemBuilder:(_,i)=>null$callback)';
          final source = await parseExpressionFromSourceForTest(
            "import 'package:flutter/widgets.dart'; Widget x()=>$value;",
            rootPackage: 'apps_examples',
          );
          final result = ExpressionTranslator(
            catalog: registry,
            helpers: HelperRegistry(),
          ).translate(source);
          expect(
            result.issues,
            isEmpty,
            reason: result.issues.map((issue) => issue.message).join('\n'),
          );
          final library = rfw.parseLibraryFile(
            'import restage.core; widget Root=${result.dsl};',
          );
          final root = library.widgets.single.root as rfw.ConstructorCall;
          final arguments = custom
              ? root.arguments['childrenDelegate']! as Map
              : root.arguments;
          expect(arguments.containsKey('findChildIndexCallback'), isFalse);
          expect(deriveSurfaceCapability(library, registry).builtInFloor, 20);
        }
      }
      final invalid = await parseExpressionFromSourceForTest("""
import 'package:flutter/widgets.dart';
Widget x()=>GridView.custom(gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:2),
 childrenDelegate:SliverChildBuilderDelegate((_,i)=>null,semanticIndexCallback:null));
""", rootPackage: 'apps_examples');
      expect(
        ExpressionTranslator(
          catalog: registry,
          helpers: HelperRegistry(),
        ).translate(invalid).issues,
        isNotEmpty,
      );
    },
  );

  test('native grid constructor family preserves options and delegates', () async {
    final registry = await catalog();
    for (final source in [
      "GridView.count(crossAxisCount: 2, mainAxisExtent: 40, primary: false, reverse: true, addSemanticIndexes: false, children: [Text('a')])",
      "GridView.extent(maxCrossAxisExtent: 100, mainAxisSpacing: 8, children: [Text('a')])",
      "GridView.count(crossAxisCount: 2, children: [Text('a', key: ValueKey<String>('a'))])",
      "GridView.builder(gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2), itemBuilder: (_,i) => null, findChildIndexCallback: null)",
      "GridView(gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2), physics: BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()), scrollCacheExtent: ScrollCacheExtent.viewport(2), children: [Text('a')])",
      "GridView.builder(gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 100), itemBuilder: (_, i) => i >= 5 ? null : Text('item \$i'))",
      "GridView.custom(gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2), childrenDelegate: SliverChildListDelegate([Text('a')], addRepaintBoundaries: false, semanticIndexOffset: 2))",
      "GridView.custom(gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2), childrenDelegate: SliverChildBuilderDelegate((_, i) => i >= 5 ? null : Text('item \$i'), childCount: 5))",
    ]) {
      final expression = await parseExpressionFromSourceForTest(
        "import 'package:flutter/widgets.dart'; Widget x() => $source;",
        rootPackage: 'apps_examples',
      );
      final result = ExpressionTranslator(
        catalog: registry,
        helpers: HelperRegistry(),
      ).translate(expression);
      expect(
        result.issues,
        isEmpty,
        reason: '$source\n${result.issues.map((i) => i.message).join('\n')}',
      );
      final library = rfw.parseLibraryFile(
        'import restage.core; widget Root = ${result.dsl};',
      );
      expect(library.widgets, hasLength(1));
      expect(deriveSurfaceCapability(library, registry).builtInFloor, 20);
      if (source.startsWith('GridView.builder')) {
        expect(result.dsl, isNot(contains('itemCount:')));
        expect(result.dsl, contains('itemBuilder:'));
      }
    }
  });
  test(
    'native grid refuses imperative callbacks and unresolved delegate lookalikes',
    () async {
      final registry = await catalog();
      for (final declaration in [
        "int count=0; Widget x()=>GridView.builder(gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:2),itemBuilder: (_,i) { count++; return Text('item'); });",
        "Widget x()=>GridView.count(crossAxisCount:2,controller:ScrollController());",
        "Widget x()=>GridView.count(crossAxisCount:2,children:[Text('a',key:ObjectKey(Object()))]);",
        "class SliverGridDelegateWithFixedCrossAxisCount { const SliverGridDelegateWithFixedCrossAxisCount({required int crossAxisCount}); } Widget x()=>GridView(gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:2));",
      ]) {
        final expression = await parseExpressionFromSourceForTest(
          "import 'package:flutter/widgets.dart'; $declaration",
          rootPackage: 'apps_examples',
        );
        final result = ExpressionTranslator(
          catalog: registry,
          helpers: HelperRegistry(),
        ).translate(expression);
        expect(result.issues, isNotEmpty, reason: declaration);
      }
    },
  );
  test(
    'native grid key lookup samples the clock on each callback invocation',
    () async {
      final registry = await catalog();
      final expression = await parseExpressionFromSourceForTest("""
import 'package:flutter/widgets.dart';
Widget x()=>GridView.builder(
  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:2),
  itemBuilder:(_,i)=>Text('item'),
  findChildIndexCallback:(key)=>DateTime.now().millisecond,
);
""", rootPackage: 'apps_examples');
      final result = ExpressionTranslator(
        catalog: registry,
        helpers: HelperRegistry(),
      ).translate(expression);
      expect(
        result.issues,
        isEmpty,
        reason: result.issues.map((issue) => issue.message).join('\n'),
      );
      expect(result.hoisted, isEmpty);
      final library = rfw.parseLibraryFile(
        'import restage.core; widget Root=${result.dsl};',
      );
      final root = library.widgets.single.root as rfw.ConstructorCall;
      var reads = 0;
      final operations = {
        ...kIntlValueOperations,
        'clock.now': ClockNowOperation(
          read: () => DateTime.utc(2024, 1, 1, 0, 0, 0, ++reads),
        ),
      };
      final program = decodeRfwProgramEnvelope(
        root.arguments['findChildIndexCallback'],
        operations: operations,
      )!.values;
      expect(reads, 0);
      expect(deriveSurfaceCapability(library, registry).builtInFloor, 24);
      for (final expected in [1, 2]) {
        expect(
          ValueEvaluator(
            program,
            captures: _LengthReader(),
            parameters: {},
            operations: operations,
          ).evaluate(),
          expected,
        );
        expect(reads, expected);
      }
    },
  );
  test(
    'typed indexed data and key lookup use deferred shared programs',
    () async {
      final registry = await catalog();
      final probe = await parseMethodExpressionFromSourceForTest(
        """
import 'package:flutter/widgets.dart';
class Item { const Item(this.id,this.title); final String id; final String title; }
class P extends StatelessWidget {
 const P({required this.items}); final List<Item> items;
 @override Widget build(BuildContext context)=>GridView.builder(
  gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:2),
  itemBuilder:(_,index){ if(index>=items.length) return null;
   return Text(items[index].title,key:ValueKey<String>(items[index].id)); },
  findChildIndexCallback:(key){
   final id=(key as ValueKey<String>).value;
   final index=items.indexWhere((item)=>item.id==id);
   return index<0 ? null : index;
  });
}
""",
        className: 'P',
        rootPackage: 'apps_examples',
      );
      final parameter =
          probe.classes['P']!.unnamedConstructor!.formalParameters.single;
      final result =
          ExpressionTranslator(
            catalog: registry,
            helpers: HelperRegistry(),
          ).translate(
            probe.expression,
            rootParams: [
              RootContextParam(
                name: 'items',
                type: parameter.type,
                typeCode: parameter.type.getDisplayString(),
                kind: RootContextParamKind.named,
                hostDataShape: deriveHostDataShape(
                  parameter.type,
                  root: 'items',
                ).shape,
                field: (parameter as FieldFormalParameterElement).field,
                isRequired: true,
                defaultValueCode: null,
                hasNullDefault: false,
              ),
            ],
          );
      expect(
        result.issues,
        isEmpty,
        reason: result.issues.map((i) => i.message).join('\n'),
      );
      expect(result.dsl, contains('data.context.items'));
      expect(result.dsl, contains('grid.indexWhere'));
      expect(result.dsl, isNot(contains('itemCount:')));
      final library = rfw.parseLibraryFile(
        'import restage.core; widget Root = ${result.dsl};',
      );
      expect(library.widgets, hasLength(1));
      final capability = deriveSurfaceCapability(library, registry);
      expect(capability.builtInFloor, 20);
      expect(
        generatedCodeFloor(
          registry.widgets.firstWhere((w) => w.name == 'GridViewBuilder'),
          registry,
        ),
        3,
      );
    },
  );
  test(
    'custom delegates and cache values retain computed native scalar slots',
    () async {
      final registry = await catalog();
      final probe = await parseMethodExpressionFromSourceForTest(
        """
import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
class P extends StatelessWidget {
 const P({required this.items}); final List<String> items;
 @override Widget build(BuildContext context)=>GridView.custom(
  gridDelegate:SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount:items.length+1,mainAxisExtent:items.length*10),
  scrollCacheExtent:ScrollCacheExtent.viewport(items.length/2),
  childrenDelegate:SliverChildBuilderDelegate((_,index)=>Text(items[index]),
    childCount:items.length,semanticIndexOffset:items.length-1,
    addRepaintBoundaries:items.length>0));
}
""",
        className: 'P',
        rootPackage: 'apps_examples',
      );
      final parameter =
          probe.classes['P']!.unnamedConstructor!.formalParameters.single;
      final result =
          ExpressionTranslator(
            catalog: registry,
            helpers: HelperRegistry(),
          ).translate(
            probe.expression,
            rootParams: [
              RootContextParam(
                name: 'items',
                type: parameter.type,
                typeCode: parameter.type.getDisplayString(),
                kind: RootContextParamKind.named,
                hostDataShape: deriveHostDataShape(
                  parameter.type,
                  root: 'items',
                ).shape,
                field: (parameter as FieldFormalParameterElement).field,
                isRequired: true,
                defaultValueCode: null,
                hasNullDefault: false,
              ),
            ],
          );
      expect(
        result.issues,
        isEmpty,
        reason: result.issues.map((i) => i.message).join('\n'),
      );

      expect(result.dsl, contains('data.context.items'));
      final library = rfw.parseLibraryFile(
        'import restage.core; widget Root = ${result.dsl};',
      );
      expect(deriveSurfaceCapability(library, registry).builtInFloor, 20);
      final root = library.widgets.single.root as rfw.ConstructorCall;
      Object? value(String slot, String field) {
        final envelope = (root.arguments[slot]! as Map)[field]! as Map;
        final program = ValueProgram.decode(
          envelope['program']! as String,
          operations: kGridValueOperations,
        );
        return ValueEvaluator(
          program,
          parameters: const {},
          captures: _LengthReader(),
          operations: kGridValueOperations,
        ).evaluate();
      }

      expect(value('childrenDelegate', 'childCount'), 2);
      expect(value('childrenDelegate', 'semanticIndexOffset'), 1);
      expect(value('childrenDelegate', 'addRepaintBoundaries'), true);
      expect(value('gridDelegate', 'crossAxisCount'), 3);
      expect(value('gridDelegate', 'mainAxisExtent'), 20.0);
      expect(value('scrollCacheExtent', 'value'), 1.0);
    },
  );
  test(
    'nested scalar callbacks retain outer native context and constraints',
    () async {
      final registry = await catalog();
      final source = await parseExpressionFromSourceForTest("""
import 'package:flutter/material.dart';
Widget x()=>LayoutBuilder(builder:(ctx,c)=>GridView.custom(
 gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:2),
 childrenDelegate:SliverChildListDelegate([Text('a')],
   semanticIndexCallback:(_,index)=>Theme.of(ctx).brightness==Brightness.light
     ? index+(c.maxWidth~/100) : null)));
""", rootPackage: 'apps_examples');
      final result = ExpressionTranslator(
        catalog: registry,
        helpers: HelperRegistry(),
      ).translate(source);
      expect(
        result.issues,
        isEmpty,
        reason: result.issues.map((i) => i.message).join('\n'),
      );
      final library = rfw.parseLibraryFile(
        'import restage.core; widget Root = ${result.dsl};',
      );
      expect(deriveSurfaceCapability(library, registry).builtInFloor, 20);
    },
  );
  test(
    'compiled child lists retain key generic identity and explicit null-key presence',
    () async {
      final registry = await catalog();
      final source = await parseExpressionFromSourceForTest("""
import 'package:flutter/widgets.dart';
Widget x()=>GridView.count(crossAxisCount:2,children:[
 Text('a',key:ValueKey<int>(1)),Text('b',key:ValueKey<double>(1.0)),
 Text('c',key:ValueKey<String?>(null)),Text('d',key:null)]);
""", rootPackage: 'apps_examples');
      final result = ExpressionTranslator(
        catalog: registry,
        helpers: HelperRegistry(),
      ).translate(source);
      expect(
        result.issues,
        isEmpty,
        reason: result.issues.map((i) => i.message).join('\n'),
      );
      final root =
          rfw
                  .parseLibraryFile(
                    'import restage.core; widget Root = ${result.dsl};',
                  )
                  .widgets
                  .single
                  .root
              as rfw.ConstructorCall;
      final slot = root.arguments['children']! as rfw.ConstructorCall;
      final program = BuilderProgram.decode(
        slot.arguments['program']! as String,
        operations: kGridValueOperations,
      );
      final children = program.invokeAll(
        captures: _LengthReader(),
        parameters: const {},
        operations: kGridValueOperations,
      );
      expect(children.map((child) => child.keyType), [
        'int',
        'double',
        'String?',
        'Object',
      ]);
      expect(children.map((child) => child.hasKey), [true, true, true, false]);
      expect(children[0].projectedKey, isA<int>());
      expect(children[1].projectedKey, isA<double>());
      expect(children[2].projectedKey, isNull);
    },
  );
}
