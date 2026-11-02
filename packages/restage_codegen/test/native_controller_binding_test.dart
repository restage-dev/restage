import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:restage_codegen/src/build_body.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/emit_utils.dart';
import 'package:restage_codegen/src/factory_emitter.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/hoisting.dart';
import 'package:restage_codegen/src/native_binding_routes.dart';
import 'package:restage_codegen/src/native_catalog_index.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import 'helpers.dart';

Catalog _catalog() {
  final catalogs = [
    for (final package in ['restage_core', 'restage_material'])
      decodeCatalog(
        File(
          '../$package/lib/src/widget_catalog/catalog.json',
        ).readAsStringSync(),
      ),
  ];
  final native = <String, (WidgetLibrary, String, String)>{
    'ScrollController': (
      WidgetLibrary.core,
      'package:flutter/src/widgets/scroll_controller.dart#ScrollController',
      's9990',
    ),
    'TabController': (
      WidgetLibrary.material,
      'package:flutter/src/material/tab_controller.dart#TabController',
      's9991',
    ),
  };
  const consumers = {
    'GridView',
    'GridViewCount',
    'GridViewExtent',
    'GridViewBuilder',
    'GridViewCustom',
    'ListView',
    'SingleChildScrollView',
    'TabBar',
    'TabBarView',
  };
  return Catalog(
    schemaVersion: kSupportedSchemaVersion,
    generatedAt: '1970-01-01T00:00:00Z',
    libraries: {for (final catalog in catalogs) ...catalog.libraries},
    widgets: [
      for (final widget in catalogs.expand((catalog) => catalog.widgets))
        if (!consumers.contains(widget.name))
          widget
        else
          WidgetEntry(
            wireId: widget.wireId,
            name: widget.name,
            library: widget.library,
            category: widget.category,
            description: widget.description,
            flutterType: widget.flutterType,
            childrenSlot: widget.childrenSlot,
            decomposes: widget.decomposes,
            sinceVersion: widget.sinceVersion,
            properties: [
              for (final property in widget.properties)
                if (property.name != 'controller') property,
              PropertyEntry(
                wireId: WireId('p9990'),
                name: 'controller',
                type: PropertyType.structured,
                description: '',
                constructorNullable: true,
                sinceVersion: 24,
                valueShape: StructuredShape(
                  propertyType: PropertyType.structured,
                  structuredRef: WireIdRef(
                    library: widget.library.namespace,
                    wireId: WireId(
                      native[widget.library == WidgetLibrary.core
                              ? 'ScrollController'
                              : 'TabController']!
                          .$3,
                    ),
                  ),
                ),
              ),
            ],
          ),
    ],
    structuredTypes: [
      for (final catalog in catalogs)
        for (final entry in catalog.structuredTypes)
          if (!native.values.any((route) => route.$2 == entry.sourceType))
            entry,
      for (final entry in native.entries)
        StructuredEntry(
          wireId: WireId(entry.value.$3),
          name: entry.key,
          library: entry.value.$1,
          description: '',
          sourceType: entry.value.$2,
          fields: const [],
          variants: const [],
        ),
    ],
    unions: [for (final catalog in catalogs) ...catalog.unions],
  );
}

Future<TranslationResult> _translate(
  String value, {
  String type = 'ScrollController',
  String prelude = '',
}) async {
  final probe = await parseMethodExpressionFromSourceForTest(
    '''
import 'package:flutter/material.dart';
class Probe extends StatelessWidget {
 const Probe({required this.controller});
 final $type controller;
 @override Widget build(BuildContext context) { $prelude return $value; }
}
''',
    className: 'Probe',
    rootPackage: 'apps_examples',
  );
  final parameter =
      probe.classes['Probe']!.unnamedConstructor!.formalParameters.single
          as FieldFormalParameterElement;
  return ExpressionTranslator(
    catalog: _catalog(),
    helpers: HelperRegistry(),
  ).translate(
    probe.expression,
    hoistInMount: true,
    rootInlined: InlinedDefinitions(
      localBindings: extractInlinableBuildBody(
        probe.expression.thisOrAncestorOfType<MethodDeclaration>()!.body,
      )!.localBindings,
    ),
    rootParams: [
      RootContextParam(
        name: 'controller',
        type: parameter.type,
        typeCode: parameter.type.getDisplayString(),
        kind: RootContextParamKind.named,
        hostDataShape: null,
        field: parameter.field,
        isRequired: true,
        defaultValueCode: null,
        hasNullDefault: false,
      ),
    ],
  );
}

void main() {
  test('native routes require exact defining-library identity', () {
    expect(
      nativeBindingRoute('package:app/controllers.dart#ScrollController'),
      isNull,
    );
    expect(
      nativeBindingRoute(
        'package:flutter/src/widgets/page_view.dart#PageController',
      ),
      isNull,
    );
  });
  for (final (value, type) in [
    (
      'GridView.count(controller: controller, crossAxisCount: 2)',
      'ScrollController',
    ),
    (
      'GridView.extent(controller: controller, maxCrossAxisExtent: 80)',
      'ScrollController?',
    ),
    ('ListView(controller: this.controller)', 'PageController'),
    ('SingleChildScrollView(controller: controller)', 'ScrollController'),
    ('TabBar(controller: controller, tabs: const [])', 'TabController'),
    (
      'TabBarView(controller: controller, children: const [])',
      'TabController?',
    ),
  ]) {
    test('borrows $type in $value', () async {
      final result = await _translate(value, type: type);
      expect(
        result.issues.where((issue) => !issue.code.isBuildNotice),
        isEmpty,
        reason: result.issues.map((issue) => issue.message).join('\n'),
      );
      expect(result.hoisted, hasLength(1));
      final binding = result.hoisted.single;
      expect(binding.kind, HoistValueKind.nativeBinding);
      expect(
        binding.nativeContract!.type,
        type.startsWith('Tab')
            ? 'flutter.TabController'
            : 'flutter.ScrollController',
      );
      expect(binding.nativeContract!.nullable, type.endsWith('?'));
      expect(result.dsl, contains('controller: data.context.${binding.key}'));
    });
  }
  test('a local alias retains the exact constructor field identity', () async {
    final result = await _translate(
      'ListView(controller: alias)',
      prelude: 'final alias = this.controller;',
    );
    expect(result.issues.where((issue) => !issue.code.isBuildNotice), isEmpty);
    expect(result.hoisted, hasLength(1));
    expect(
      result.hoisted.single.nativeContract!.type,
      'flutter.ScrollController',
    );
  });
  test('native construction is refused without copying ownership', () async {
    final result = await _translate('ListView(controller: ScrollController())');
    expect(
      result.issues.where((issue) => !issue.code.isBuildNotice),
      isNotEmpty,
    );
    expect(result.hoisted, isEmpty);
  });
  test('optional native null remains null', () async {
    final result = await _translate('ListView(controller: null)');
    expect(result.issues.where((issue) => !issue.code.isBuildNotice), isEmpty);
    expect(result.hoisted, isEmpty);
    expect(result.dsl, contains('controller: null'));
  });
  test(
    'source-to-runtime fixtures retain actual native binding references',
    () async {
      final cases = <String, Object?>{};
      for (final (name, expression, type) in [
        (
          'list',
          'ListView(controller: this.controller, children: const [SizedBox(height:2000)])',
          'PageController',
        ),
        (
          'tabs',
          "Column(children:[TabBar(controller:controller,tabs:const [Text('one'),Text('two')]),Expanded(child:TabBarView(controller:controller,children:const [Text('first'),Text('second')]))])",
          'TabController',
        ),
      ]) {
        final result = await _translate(expression, type: type);
        expect(
          result.issues.where((issue) => !issue.code.isBuildNotice),
          isEmpty,
        );
        final binding = result.hoisted.single;
        cases[name] = {
          'dsl': result.dsl,
          'key': binding.key,
          'type': binding.nativeContract!.type,
        };
      }
      final generated =
          '${const JsonEncoder.withIndent('  ').convert(cases)}\n';
      final file = File(
        '../restage_core/test/fixtures/native_controller_sources.json',
      );
      if (Platform.environment['WRITE_NATIVE_CONTROLLER_FIXTURE'] == '1') {
        file.writeAsStringSync(generated);
      }
      expect(file.readAsStringSync(), generated);
    },
  );

  test('native factory fixture is the production emitter output', () {
    final catalog = _catalog();
    final index = NativeCatalogIndex(catalog);
    final output = StringBuffer(
      '''// Generated by native_controller_binding_test.dart.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:restage_core/restage_core.dart';
import 'package:rfw/rfw.dart';

''',
    );
    for (final name in [
      'GridViewCount',
      'ListView',
      'SingleChildScrollView',
      'TabBar',
      'TabBarView',
    ]) {
      final widget = catalog.widgets.singleWhere(
        (widget) => widget.name == name,
      );
      final factory = emitFactoryFunction(
        widget,
        nativeIndex: index,
        publicName: true,
      );
      expect(factory, isNotNull, reason: name);
      expect(factory, contains('RestageDecoders.nativeBinding<'));
      output.writeln(factory);
    }
    final file = File(
      '../restage_core/test/fixtures/native_controller_factories.g.dart',
    );
    final generated = formatGeneratedDart(output.toString());
    if (Platform.environment['WRITE_NATIVE_CONTROLLER_FIXTURE'] == '1') {
      file.writeAsStringSync(generated);
    }
    expect(file.readAsStringSync(), generated);
  });
}
