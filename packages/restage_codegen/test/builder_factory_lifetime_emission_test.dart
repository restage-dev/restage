import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:build/build.dart';
import 'package:restage_codegen/builder.dart';
import 'package:restage_codegen/src/factory_emitter.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

WidgetEntry _entry(String name, List<PropertyEntry> properties) => WidgetEntry(
      wireId: WireId.unallocatedWidget,
      name: name,
      library: WidgetLibrary.core,
      category: WidgetCategory.layout,
      description: '',
      flutterType: 'package:flutter/widgets.dart#$name',
      childrenSlot: ChildrenSlot.none,
      properties: properties,
    );

PropertyEntry _callback({
  bool nullable = false,
  WidgetBuilderParameter parameter = WidgetBuilderParameter.boxConstraints,
  bool nullableResult = false,
}) =>
    PropertyEntry(
      wireId: WireId.unallocatedProperty,
      name: 'builder',
      type: PropertyType.widgetBuilder,
      description: '',
      required: true,
      constructorNullable: nullable,
      builderContract: WidgetBuilderContract(parameters: [
        WidgetBuilderParameter.buildContext,
        parameter,
      ], nullableResult: nullableResult),
    );

String _source(WidgetEntry entry) {
  final source = emitFactoryFunction(entry)!;
  final parsed = parseString(content: source);
  expect(parsed.errors, isEmpty);
  final function = parsed.unit.declarations.single as FunctionDeclaration;
  final body = function.functionExpression.body as BlockFunctionBody;
  expect(body.block.statements, hasLength(2));
  expect(body.block.statements.first.toSource(),
      'source = RestageValueBinding.dataSource(source, context);');
  final returned = body.block.statements.whereType<ReturnStatement>().single;
  final construct = returned.expression! as MethodInvocation;
  expect(construct.target!.toSource(), 'RestageBuilderBinding');
  expect(construct.methodName.name, 'construct');
  expect(construct.argumentList.arguments.single, isA<FunctionExpression>());
  return source.replaceAll(RegExp(r'\s+'), ' ');
}

void main() {
  test('native callback binding is constructed once before its typed closure',
      () {
    final source = _source(_entry('LayoutBuilder', [_callback()]));
    expect(RegExp(r'RestageBuilderBinding\(source,').allMatches(source),
        hasLength(1));
    expect(source.indexOf('final restageBuilderBindingbuilder'),
        lessThan(source.indexOf('return LayoutBuilder(')));
    expect(
        source, contains('builderBindings.add(restageBuilderBindingbuilder)'));
    expect(
        source,
        contains('contract: const WidgetBuilderContract(parameters: '
            '[WidgetBuilderParameter.buildContext, '
            'WidgetBuilderParameter.boxConstraints], nullableResult: false)'));
    expect(
        source,
        contains('builder: (BuildContext arg0, BoxConstraints arg1) => '
            'restageBuilderBindingbuilder.build(arg0, '
            "{'arg1': RestageBuilderBinding.constraints(arg1)})"));
  });

  test('nullable callback property retains absence and native orientation type',
      () {
    final source = _source(_entry('OrientationBuilder', [
      _callback(nullable: true, parameter: WidgetBuilderParameter.orientation),
    ]));
    expect(source, contains('RestageBuilderBinding.optional(source,'));
    expect(
        source,
        contains(
            'if (restageBuilderBindingbuilder != null) builderBindings.add'));
    expect(
        source,
        contains('builder: restageBuilderBindingbuilder == null ? null : '
            '(BuildContext arg0, Orientation arg1) => '
            "restageBuilderBindingbuilder.build(arg0, {'arg1': arg1.name})"));
  });

  test('nullable indexed result uses the native nullable invocation method',
      () {
    final source = _source(_entry('IndexedProbe', [
      _callback(
          parameter: WidgetBuilderParameter.itemIndex, nullableResult: true),
    ]));
    expect(
        source,
        contains('(BuildContext arg0, int arg1) => '
            "restageBuilderBindingbuilder.buildNullable(arg0, {'arg1': arg1})"));
  });

  test('child collection bindings share lifetime and nullable list presence',
      () {
    final source = _source(_entry('CollectionProbe', const [
      PropertyEntry(
        wireId: WireId.unallocatedProperty,
        name: 'children',
        type: PropertyType.widgetList,
        description: '',
        constructorNullable: true,
      ),
    ]));
    expect(
        source,
        contains(
            "RestageDecoders.isWidgetList(source, const <Object>['children']) "
            '? RestageDecoders.widgetList(source, '
            "const <Object>['children'], context: context, "
            'bindings: builderBindings) : null'));
  });

  test(
      'core registration installs the hidden continuation without a catalog row',
      () async {
    final catalog = Catalog(
      schemaVersion: kSupportedSchemaVersion,
      generatedAt: '1970-01-01T00:00:00Z',
      libraries: {WidgetLibrary.core: const LibraryInfo(version: '1.0.0')},
      widgets: [],
    );
    await testBuilder(
      factoryFunctionBuilder(BuilderOptions.empty),
      {
        'restage_core|lib/src/widget_catalog/catalog.json':
            encodeCatalog(catalog)
      },
      rootPackage: 'restage_core',
      outputs: {
        'restage_core|lib/src/registration.g.dart': decodedMatches(allOf(
          contains("import 'package:restage_core/restage_core.dart';"),
          contains(
              "'__RestageBuilderContinuation': buildRestageBuilderContinuation"),
          isNot(contains('Widget buildRestageBuilderContinuation(')),
        )),
      },
    );
  });
}
