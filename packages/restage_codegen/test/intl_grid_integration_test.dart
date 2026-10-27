import 'dart:io';

import 'package:analyzer/dart/element/element.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/host_data_shape.dart';
import 'package:restage_compiler_core/restage_compiler_core.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/rfw_formats.dart' as rfw;
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('authored Grid predicate composes Intl and lexical theme device locale',
      () async {
    final probe = await parseMethodExpressionFromSourceForTest(r'''
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as i;
class Probe extends StatelessWidget {
  const Probe({required this.items});
  final List<String> items;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (outer, constraints) => GridView.builder(
    primary: false, shrinkWrap: true,
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisExtent: 40),
    itemCount: items.length,
    itemBuilder: (_, index) => Text(items[index], key: ValueKey<String>(items[index])),
    findChildIndexCallback: (key) {
      final id = (key as ValueKey<String>).value;
      final index = items.indexWhere((item) => i.Intl.select(
        Theme.of(outer).brightness == Brightness.light && !MediaQuery.of(outer).boldText
          ? Localizations.localeOf(outer).languageCode : 'hidden',
        {'fr': item, 'other': 'hidden'},
      ) == id);
      return index < 0 ? null : index;
    },
  ));
}
''', className: 'Probe');
    final parameter =
        probe.classes['Probe']!.unnamedConstructor!.formalParameters.single;
    final catalog = decodeCatalog(
        File('../restage_core/lib/src/widget_catalog/catalog.json')
            .readAsStringSync());
    final result =
        ExpressionTranslator(catalog: catalog, helpers: HelperRegistry())
            .translate(
      probe.expression,
      hoistInMount: false,
      rootParams: [
        RootContextParam(
            name: 'items',
            type: parameter.type,
            typeCode: 'List<String>',
            kind: RootContextParamKind.named,
            hostDataShape:
                deriveHostDataShape(parameter.type, root: 'items').shape,
            field: (parameter as FieldFormalParameterElement).field,
            isRequired: true,
            defaultValueCode: null,
            hasNullDefault: false)
      ],
      buildContextParameter:
          probe.classes['Probe']!.getMethod('build')!.formalParameters.first,
    );
    expect(result.issues.where((issue) => !issue.code.isInformational), isEmpty,
        reason: result.issues.map((i) => i.message).join('\n'));
    expect(result.hoisted, isEmpty);
    final source = 'import restage.core; widget Root = ${result.dsl};\n';
    final library = rfw.parseLibraryFile(source);
    final root = library.widgets.single.root as rfw.ConstructorCall;
    final outer = decodeRfwProgramEnvelope(root.arguments['builder'])!;
    final grid = outer.bodies.single.widget as rfw.ConstructorCall;
    final callback =
        decodeRfwProgramEnvelope(grid.arguments['findChildIndexCallback'])!;
    final indexWhere = callback.values.nodes
        .singleWhere((node) => node.op == 'grid.indexWhere');
    final predicate = ValueProgram.decode(indexWhere.value! as String,
        operations: const {...kGridValueOperations, ...kIntlValueOperations});
    expect(predicate.nodes.any((node) => node.op == 'intl.select'), isTrue);
    expect(predicate.parameters.keys.where((key) => key.startsWith('outer')),
        isNotEmpty);
    expect(
        callback.values.parameters.keys,
        containsAll([
          'context:theme:brightness',
          'context:device:boldText',
          'context:device:languageCode'
        ]));
    expect(
        decodeRfwProgramEnvelope(grid.arguments['findChildIndexCallback'])!
            .capability,
        23);
    expect(deriveSurfaceCapability(library, catalog).builtInFloor, 23);
    expect(
        surfaceScreenContractGaps(library,
            events: SurfaceScreenEventSchema(events: const []),
            context: SurfaceScreenHostDataSchema(const {
              'items': SurfaceScreenHostDataListShapeV1(
                  SurfaceScreenHostDataScalarShapeV1(
                      SurfaceScreenHostDataScalarKind.string)),
            })),
        isEmpty);
    expect(
        BlobRenderCapabilityGate.evaluate(
            required: CapabilityManifest(
                builtInFloor: 23, requiredLibraries: const []),
            installed: InstalledCapability(
                builtInCatalogVersion: 22,
                installedLibraries: const [])).accepted,
        isFalse);
    final fixture =
        File('../restage_core/test/fixtures/intl_grid_compiled.rfwtxt');
    if (Platform.environment['REGEN_INTL_GRID_FIXTURE'] == '1')
      fixture.writeAsStringSync(source);
    expect(fixture.readAsStringSync(), source);
  });
}
