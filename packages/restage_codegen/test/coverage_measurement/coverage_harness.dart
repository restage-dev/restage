import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:restage_codegen/src/annotation_lookup.dart';
import 'package:restage_codegen/src/coverage_measurement/coverage_report.dart';
import 'package:restage_codegen/src/coverage_measurement/emit_outcomes.dart';
import 'package:restage_codegen/src/helper_registry.dart';
import 'package:restage_codegen/src/widget_classification.dart';
import 'package:restage_codegen/src/widget_classifier.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

import '../helpers.dart';

/// The classifier verdicts plus the translator's emit-confirmation outcomes
/// for one fixture pass — everything `CoverageReport.from` needs to bucket
/// emit-confirmed (not merely classifier-recognised) inlinability.
class CoverageProbe {
  const CoverageProbe(this.classifications, this.emitOutcomes);

  /// `classKey → WidgetClassification` for every `@RestageWidget` scanned.
  final Map<String, WidgetClassification> classifications;

  /// `classKey → EmitOutcome` — the strict-emit verdict per classified
  /// widget ([EmitOutcome.notAttempted] for the deferred/structural ones).
  /// **Empty when `probeEmit` was false** (the classifier-only run); a key
  /// absent from this map is treated as [EmitOutcome.notAttempted] by
  /// `CoverageReport.from`, so an empty map yields the classifier-only
  /// (upper-bound) bucketing.
  final Map<String, EmitOutcome> emitOutcomes;
}

/// Drives the [WidgetClassifier] over every `@RestageWidget`-annotated
/// class in [sources] (with [inputPath] naming the library to scan),
/// against [catalog]. Returns the [CoverageProbe] (classifier verdicts +
/// emit outcomes).
///
/// When [probeEmit] is true the harness also attempts the translator's
/// strict inline emit on each recognised widget — but that is only
/// meaningful against a catalog rich enough to emit the fixtures (the real
/// merged catalog). Against a thin synthetic catalog every emit fails for
/// lack of declared properties, so the committed classifier-only snapshot
/// leaves [probeEmit] at its default `false` (the upper-bound measurement);
/// the real-Flutter proof test opts in to demonstrate the lie-catcher.
///
/// The classifier's `results` map accumulates across `classify()`
/// calls, so a single classifier instance scans every annotated class
/// in one pass. Composed (transitively-reached) `@RestageWidget`
/// widgets land in the map too; for the chapter-close measurement
/// that is the right shape — every recognised customer widget gets
/// bucketed regardless of whether it was top-level or composed.
Future<CoverageProbe> classifyAllInFixture(
  Map<String, String> sources, {
  required String inputPath,
  Catalog catalog = kEmptyCatalog,
  HelperRegistry? helpers,
  bool probeEmit = false,
}) async {
  final readerWriter = await readerWriterWithFilesystemSources(
    rootPackage: 'apps_examples',
    includeFlutter: sources.values.any(
      (source) => source.contains('package:flutter/'),
    ),
  );
  final assetMap = <String, String>{
    for (final entry in sources.entries)
      'apps_examples|${entry.key}': entry.value,
  };
  for (final entry in assetMap.entries) {
    readerWriter.testing.writeString(AssetId.parse(entry.key), entry.value);
  }

  CoverageProbe? captured;
  await testBuilder(
    _CoverageProbeBuilder(
      inputAssetId: AssetId('apps_examples', inputPath),
      catalog: catalog,
      helpers: helpers,
      probeEmit: probeEmit,
      onResults: (probe) {
        captured = probe;
      },
    ),
    assetMap,
    rootPackage: 'apps_examples',
    readerWriter: readerWriter,
  );

  final resolved = captured;
  if (resolved == null) {
    throw StateError(
      'classifyAllInFixture: $inputPath did not resolve or contained no '
      '@RestageWidget classes.',
    );
  }
  return resolved;
}

/// Builder that resolves [inputAssetId], iterates `@RestageWidget`-annotated
/// classes in the library, runs [WidgetClassifier.classify] on each, attempts
/// the translator's strict inline emit on each, and hands the classifier
/// verdicts + emit outcomes back through [onResults].
class _CoverageProbeBuilder implements Builder {
  _CoverageProbeBuilder({
    required this.inputAssetId,
    required this.catalog,
    required this.helpers,
    required this.probeEmit,
    required this.onResults,
  });

  final AssetId inputAssetId;
  final Catalog catalog;
  final HelperRegistry? helpers;
  final bool probeEmit;
  final void Function(CoverageProbe) onResults;

  @override
  Map<String, List<String>> get buildExtensions => const {
        '.dart': ['.coverageprobe'],
      };

  @override
  Future<void> build(BuildStep step) async {
    if (step.inputId != inputAssetId) return;
    final library = await step.inputLibrary;
    final classifier = WidgetClassifier(
      catalog: catalog,
      helpers: helpers,
      astNodeFor: (fragment) =>
          step.resolver.astNodeFor(fragment, resolve: true),
    );
    for (final cls in library.classes) {
      if (firstAnnotation(cls, 'RestageWidget') == null) continue;
      await classifier.classify(cls);
    }
    final classifications =
        Map<String, WidgetClassification>.unmodifiable(classifier.results);
    onResults(
      CoverageProbe(
        classifications,
        probeEmit
            ? computeEmitOutcomes(
                classifications,
                classifier.blueprints,
                catalog: catalog,
                helpers: helpers ?? HelperRegistry(),
              )
            : const <String, EmitOutcome>{},
      ),
    );
  }
}
