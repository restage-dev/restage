import 'package:restage_codegen/src/coverage_measurement/coverage_report.dart';
import 'package:restage_codegen/src/custom_widget_blueprint.dart';
import 'package:restage_codegen/src/expression_translator.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/widget_classification.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Attempts the translator's strict inline emit on each classified widget and
/// maps the result to an [EmitOutcome].
///
/// This is the single source of the emit-confirmed predicate, shared by the
/// build-step coverage harness and the standalone real-package scanner so the
/// two can never disagree on what "emit-confirmed" means: a non-composable
/// widget has nothing to emit-confirm ([EmitOutcome.notAttempted]); a
/// composable widget is [EmitOutcome.confirmed] only when the attempt produced
/// a definition with no issues, else [EmitOutcome.failed].
Map<String, EmitOutcome> computeEmitOutcomes(
  Map<String, WidgetClassification> classifications,
  Map<String, CustomWidgetBlueprint> blueprints, {
  required Catalog catalog,
  required HelperRegistry helpers,
}) {
  final translator = ExpressionTranslator(
    catalog: catalog,
    helpers: helpers,
    customWidgetClassifications: classifications,
    customWidgetBlueprints: blueprints,
  );
  final outcomes = <String, EmitOutcome>{};
  for (final entry in classifications.entries) {
    final classification = entry.value;
    if (classification is! ComposableWidget) {
      outcomes[entry.key] = EmitOutcome.notAttempted;
      continue;
    }
    final blueprint = blueprints[entry.key];
    if (blueprint == null) {
      // A ComposableWidget should always carry a blueprint; absent one it
      // cannot be emit-confirmed.
      outcomes[entry.key] = EmitOutcome.failed;
      continue;
    }
    final result = translator.attemptInlineEmit(classification, blueprint);
    outcomes[entry.key] =
        result.issues.isEmpty && result.widgetDefinitions.isNotEmpty
            ? EmitOutcome.confirmed
            : EmitOutcome.failed;
  }
  return outcomes;
}
