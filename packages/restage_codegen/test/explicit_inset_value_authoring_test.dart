import 'dart:io';

import 'package:restage_codegen/src/catalog_validator.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/factory_emitter.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_shared/rfw_formats.dart' as fmt;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const _source = r'''
import 'package:flutter/widgets.dart';
class InsetReadout extends StatelessWidget {
  const InsetReadout({required this.insets, required this.label});
  final EdgeInsetsGeometry insets;
  final String label;
  @override
  Widget build(BuildContext context) {
    final value = insets.resolve(Directionality.of(context));
    return Text('$label:${insets.runtimeType}:${value.left},${value.top},${value.right},${value.bottom}');
  }
}
''';

void main() {
  test(
    'finite exponential scalars round-trip while strings stay unchanged',
    () async {
      final expression = await parseExpressionFromSourceForTest(
        """
const large = 1.7e308;
const small = 1e-7;
const spelling = '1.7e+308';
Object x() => [
  1.7e308, large, -1.7e308, small, -0.0, '1.7e+308', spelling,
];
""",
        rootPackage: 'apps_examples',
      );
      final result = ExpressionTranslator(
        catalog: kEmptyCatalog,
        helpers: HelperRegistry(),
      ).translate(expression);
      expect(
        result.issues.where((issue) => !issue.code.isInformational),
        isEmpty,
      );
      final model = fmt.parseLibraryFile(
        'widget Surface = ValueProbe(values: ${result.dsl});',
      );
      final decoded = fmt.decodeLibraryBlob(fmt.encodeLibraryBlob(model));
      final values =
          (decoded.widgets.single.root as fmt.ConstructorCall)
                  .arguments['values']!
              as List<Object?>;
      expect(
        values,
        [1.7e308, 1.7e308, -1.7e308, 1e-7, -0.0, '1.7e+308', '1.7e+308'],
      );
      expect(values.take(5), everyElement(isA<double>()));
      expect((values[4]! as double).isNegative, isTrue);
    },
  );

  test(
    'ordinary authored insets retain signed and finite overflow components',
    () async {
      const library = WidgetLibrary.custom('test.insets');
      final widget = entry(
        name: 'InsetReadout',
        library: library,
        flutterType: 'package:apps_examples/_expr_probe.dart#InsetReadout',
        properties: [
          const PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: 'insets',
            type: PropertyType.edgeInsets,
            description: '',
            required: true,
            valueShape: ScalarShape(
              propertyType: PropertyType.edgeInsets,
              dartTypeRef: DartTypeRef(
                libraryUri: 'package:flutter/src/painting/edge_insets.dart',
                symbolName: 'EdgeInsetsGeometry',
              ),
            ),
          ),
          prop('label', PropertyType.string, required: true),
        ],
      );
      final catalog = catalogWith([widget], library: library);
      expect(
        emitFactoryFunction(widget),
        contains("RestageDecoders.edgeInsets(source, <Object>['insets'])"),
      );
      final declarations = <String>[];
      for (final scenario in <String, (String, Map<String, Object>)>{
        'PhysicalNegative': (
          'EdgeInsets.only(left: -7)',
          {'left': -7.0, 'top': 0.0, 'right': 0.0, 'bottom': 0.0},
        ),
        'LogicalNegative': (
          'EdgeInsetsDirectional.only(start: -7)',
          {'start': -7.0, 'top': 0.0, 'end': 0.0, 'bottom': 0.0},
        ),
        'PhysicalOverflow': (
          'EdgeInsets.fromLTRB(1.7e308, 1.7e308, 1.7e308, 1.7e308)',
          {
            'left': 1.7e308,
            'top': 1.7e308,
            'right': 1.7e308,
            'bottom': 1.7e308,
          },
        ),
        'LogicalOverflow': (
          'EdgeInsetsDirectional.fromSTEB(1.7e308, 1.7e308, 1.7e308, 1.7e308)',
          {'start': 1.7e308, 'top': 1.7e308, 'end': 1.7e308, 'bottom': 1.7e308},
        ),
      }.entries) {
        final expression = await parseExpressionFromSourceForTest(
          '$_source\n'
          'Widget x() => InsetReadout( '
          'insets: ${scenario.value.$1}, label: "${scenario.key}");',
          rootPackage: 'apps_examples',
        );
        final result = ExpressionTranslator(
          catalog: catalog,
          helpers: HelperRegistry(),
        ).translate(expression);
        expect(
          result.issues.where((issue) => !issue.code.isInformational),
          isEmpty,
        );
        final model = fmt.parseLibraryFile(
          'import test.insets; widget ${scenario.key} = ${result.dsl};',
        );
        expect(validateModelAgainstCatalog(model, catalog), isEmpty);
        final root = model.widgets.single.root as fmt.ConstructorCall;
        expect(root.arguments['insets'], scenario.value.$2);
        declarations.add('widget ${scenario.key} = ${result.dsl};');
      }
      final text = 'import test.insets;\n${declarations.join('\n')}\n';
      final fixture = File(
        '../restage_core/test/fixtures/explicit_inset_values.rfwtxt',
      );
      if (Platform.environment['WRITE_EXPLICIT_INSET_VALUES_FIXTURE'] == '1') {
        fixture.writeAsStringSync(text);
      }
      expect(
        fmt.encodeLibraryBlob(fmt.parseLibraryFile(text)),
        fmt.encodeLibraryBlob(fmt.parseLibraryFile(fixture.readAsStringSync())),
      );
    },
  );
}
