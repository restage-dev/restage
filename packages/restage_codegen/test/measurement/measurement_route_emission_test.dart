import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/issue.dart';
import 'package:restage_codegen/src/measurement/measurement_event_occurrence.dart';
import 'package:restage_codegen/src/measurement/measurement_route_emission.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';
import 'package:test/test.dart';

import '../helpers.dart';

const _probeFlutterType = '$kSyntheticProbeLibraryUri#Probe';

void main() {
  test('production event lowering attaches the exact route marker', () async {
    final root = await parseExpressionFromSourceForTest('''
      class Probe {
        const Probe({this.onPressed});
        final void Function()? onPressed;
      }

      void Function() paywallEvent(String name) => throw UnimplementedError();

      Object x() => Probe(onPressed: paywallEvent('activate'));
    ''');
    final widget = root as InstanceCreationExpression;
    final eventParameter = widget.argumentList.arguments
        .whereType<NamedExpression>()
        .single
        .name
        .label
        .element! as FormalParameterElement;
    final eventOccurrence = MeasurementOccurrenceScope.root('test#Source')
        .widget(widget.constructorName.type.element! as InterfaceElement)
        .event(eventParameter);
    final generatedReferenceId = GeneratedReferenceId(
      'reference.route-translator',
    );
    final translator = ExpressionTranslator(
      catalog: catalogWith([
        entry(
          name: 'Probe',
          flutterType: _probeFlutterType,
          properties: [prop('onPressed', PropertyType.event)],
        ),
      ]),
      helpers: HelperRegistry()
        ..registerAll([
          HelperDefinition(
            name: 'paywallEvent',
            libraryOrigin: 'package:restage_codegen',
            returnCategory: HelperReturnCategory.voidCallback,
            translate: (args) => 'event ${args.positional.single} {}',
          ),
        ]),
      measurementRouteEmissionPlan: MeasurementRouteEmissionPlan([
        MeasurementRouteEmissionBinding(
          occurrence: eventOccurrence,
          generatedReferenceId: generatedReferenceId,
        ),
      ]),
    );

    final result = translator.translate(root);

    expect(result.issues, isEmpty);
    expect(result.dsl, contains('event "activate"'));
    final marker = MeasurementRouteEmissionPlan.markerForGeneratedReference(
      generatedReferenceId,
    );
    expect(
      result.dsl,
      contains('$kMeasurementRouteReferenceMarkerKeyV1: "$marker"'),
    );
  });

  test('production event lowering rejects authored reserved arguments',
      () async {
    final root = await parseExpressionFromSourceForTest('''
      class Probe {
        const Probe({this.onPressed});
        final void Function()? onPressed;
      }

      void Function() paywallEvent(String name) => throw UnimplementedError();

      Object x() => Probe(onPressed: paywallEvent('activate'));
    ''');
    final widget = root as InstanceCreationExpression;
    final eventParameter = widget.argumentList.arguments
        .whereType<NamedExpression>()
        .single
        .name
        .label
        .element! as FormalParameterElement;
    final eventOccurrence = MeasurementOccurrenceScope.root('test#Source')
        .widget(widget.constructorName.type.element! as InterfaceElement)
        .event(eventParameter);
    final translator = ExpressionTranslator(
      catalog: catalogWith([
        entry(
          name: 'Probe',
          flutterType: _probeFlutterType,
          properties: [prop('onPressed', PropertyType.event)],
        ),
      ]),
      helpers: HelperRegistry()
        ..registerAll([
          HelperDefinition(
            name: 'paywallEvent',
            libraryOrigin: 'package:restage_codegen',
            returnCategory: HelperReturnCategory.voidCallback,
            translate: (_) => 'event "activate" '
                '{ __restage_measurement_customer_key: "bad" }',
          ),
        ]),
      measurementRouteEmissionPlan: MeasurementRouteEmissionPlan([
        MeasurementRouteEmissionBinding(
          occurrence: eventOccurrence,
          generatedReferenceId: GeneratedReferenceId(
            'reference.route-authored-reserved',
          ),
        ),
      ]),
    );

    final result = translator.translate(root);

    expect(result.dsl, isEmpty);
    expect(
      result.issues.map((issue) => issue.code),
      contains(IssueCode.invalidEventConfiguration),
    );
  });
}
