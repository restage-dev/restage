import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/paywall_helpers.dart';
import 'package:restage_codegen/src/rfw_emitter.dart';
import 'package:restage_codegen/src/widget_classification.dart';
import 'package:restage_shared/rfw_formats.dart' show parseLibraryFile;
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('Dart dollar property and event names emit parseable quoted RFW keys',
      () async {
    final catalog = catalogWith([
      entry(
        name: 'Probe',
        properties: const [
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: r'$source',
            type: PropertyType.string,
            description: '',
          ),
          PropertyEntry(
            wireId: WireId.unallocatedProperty,
            name: r'on$Retry',
            type: PropertyType.event,
            description: '',
          ),
        ],
      ),
    ]);
    final expression = await parseExpressionForTest(
      r"Probe($source: 'authored', on$Retry: paywallEvent('retry'))",
    );
    final result = ExpressionTranslator(
      catalog: catalog,
      helpers: HelperRegistry()..registerAll(paywallHelpers),
    ).translate(expression);

    expect(result.issues, isEmpty);
    expect(
      result.dsl,
      r'Probe("$source": "authored", "on$Retry": event "retry" {})',
    );
    expect(
      () => parseLibraryFile(emitPaywallLibrary(result.dsl)),
      returnsNormally,
      reason: 'quoted Dart-only names must survive the real RFW parser',
    );
  });

  test('Dart dollar parameter names emit parseable quoted args paths',
      () async {
    const classKey = 'package:restage_codegen/_expr_probe.dart#DollarCard';
    final body = await parseExpressionForTest(r'Text($source)');
    final translator = ExpressionTranslator(
      catalog: catalogWith([
        entry(
          name: 'Text',
          properties: [
            prop('text', PropertyType.string, positional: true),
          ],
        ),
      ]),
      helpers: HelperRegistry(),
      customWidgetClassifications: {
        classKey: ComposableWidget(
          classKey,
          requiredMechanisms: {},
          composedCustomWidgets: [],
        ),
      },
      customWidgetBlueprints: {
        classKey: CustomWidgetBlueprint(
          classKey: classKey,
          rfwName: 'DollarCard',
          buildExpression: body,
          params: const [
            CustomWidgetParam(
              name: r'$source',
              isNumeric: false,
              defaultValue: null,
            ),
          ],
        ),
      },
    );
    final expression = await parseExpressionFromSourceForTest(r'''
class DollarCard {
  const DollarCard({required this.$source});
  final String $source;
}
Object x() => DollarCard($source: 'authored');
''');
    final result = translator.translate(expression);

    expect(result.issues, isEmpty);
    expect(result.dsl, r'DollarCard("$source": "authored")');
    expect(
      result.widgetDefinitions['DollarCard'],
      r'Text(text: args."$source")',
    );
    expect(
      () => parseLibraryFile(
        emitPaywallLibrary(
          result.dsl,
          widgetDefinitions: result.widgetDefinitions,
        ),
      ),
      returnsNormally,
      reason: 'quoted path segments must survive the real RFW parser',
    );
  });
}
