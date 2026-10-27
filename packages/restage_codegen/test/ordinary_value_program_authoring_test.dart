import 'dart:io';

import 'package:analyzer/dart/element/element.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/builder_expression_lowering.dart';
import 'package:restage_codegen/src/factory_emitter.dart';
import 'package:restage_codegen/src/native_catalog_index.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/host_data_shape.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import 'helpers.dart';

final class _ItemsReader implements ValueReader {
  @override
  int length(List<Object> path) => 2;
  @override
  Object? read(List<Object> path, ValueType type) =>
      throw StateError('Unexpected eager item read');
}

void main() {
  test('contextual double integer literals retain native arithmetic type',
      () async {
    final expression = await parseExpressionFromSourceForTest(
        'double x(bool wide)=>wide ? 2 : 1;');
    final lowering = BuilderExpressionLowering(capture: (e) => e.toSource());
    final program = lowering.program(lowering.lower(expression));
    program.validate();
    expect(
        program.nodes
            .where((node) => node.op == 'literal')
            .map((node) => node.type.kind),
        everyElement('double'));
    expect(
        program.nodes
            .where((node) => node.op == 'literal')
            .map((node) => node.value),
        everyElement(isA<double>()));
  });

  test('native constructor scalar slots use the shared pure value program',
      () async {
    final probe = await parseMethodExpressionFromSourceForTest('''
import 'package:flutter/widgets.dart';
class Probe extends StatelessWidget {
  const Probe({required this.items});
  final List<String> items;
  Widget build(BuildContext context) => SizedBox(width: (items.length + 1) / 2,
    child: IgnorePointer(ignoring: items.length.isEven, child: const SizedBox()));
}
''', className: 'Probe');
    final parameter =
        probe.classes['Probe']!.unnamedConstructor!.formalParameters.single;
    final shape = deriveHostDataShape(parameter.type, root: 'items');
    final file =
        File('packages/restage_core/lib/src/widget_catalog/catalog.json')
                .existsSync()
            ? File('packages/restage_core/lib/src/widget_catalog/catalog.json')
            : File('../restage_core/lib/src/widget_catalog/catalog.json');
    final catalog =
        requireNativeCatalog(decodeCatalog(file.readAsStringSync()));
    final result =
        ExpressionTranslator(catalog: catalog, helpers: HelperRegistry())
            .translate(probe.expression, rootParams: [
      RootContextParam(
        name: 'items',
        type: parameter.type,
        typeCode: 'List<String>',
        kind: RootContextParamKind.named,
        hostDataShape: shape.shape,
        field: (parameter as FieldFormalParameterElement).field,
        isRequired: true,
        defaultValueCode: null,
        hasNullDefault: false,
      )
    ]);
    expect(result.issues.where((i) => !i.code.isBuildNotice), isEmpty);
    expect(result.dsl, contains('program:'));
    expect(result.dsl, contains('isEven'));
    final root = rfw
        .parseLibraryFile('import restage.core;widget Root=${result.dsl};')
        .widgets
        .single
        .root as rfw.ConstructorCall;
    final width = root.arguments['width']! as Map;
    final program = ValueProgram.decode(width['program']! as String);
    expect(
        ValueEvaluator(program, captures: _ItemsReader(), parameters: {})
            .evaluate(),
        1.5);
    expect(
        emitFactoryFunction(
            catalog.widgets.firstWhere((w) => w.name == 'SizedBox'),
            nativeIndex: NativeCatalogIndex(catalog)),
        contains('source = RestageValueBinding.dataSource(source, context);'));
  });
}
