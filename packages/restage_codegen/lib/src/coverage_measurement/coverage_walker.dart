import 'package:restage_codegen/src/coverage_measurement/coverage_report.dart';
import 'package:restage_codegen/src/widget_classification.dart';

/// Buckets a single [classification] into the [CoverageBucket] that
/// describes whether the widget inlines today and, if not, why.
///
/// Bucketing precedence inside the `inlinable*` family is
/// `declarativeState > themeAsData > constantFolding > composition-only`
/// — each bucket implies the lower mechanisms may also be present. See
/// [CoverageBucket] for the full taxonomy.
CoverageBucket bucketFor(WidgetClassification classification) =>
    switch (classification) {
      ImperativeWidget() => CoverageBucket.structural,
      UnclassifiableWidget() => CoverageBucket.deferred,
      ComposableWidget(:final requiredMechanisms) =>
        _composableBucket(requiredMechanisms),
    };

/// Buckets a [classification] with the translator's strict-emit [outcome]
/// folded in — the emit-confirmed bucketing (B1).
///
/// A widget the classifier would bucket into an `inlinable*` family but
/// whose [outcome] is [EmitOutcome.failed] is demoted to
/// [CoverageBucket.classifierOnly]: the classifier recognised it, the
/// translator would not emit it. Every other case defers to [bucketFor]:
///   - [EmitOutcome.confirmed] keeps the classifier's inlinable bucket
///     (the emit agreed);
///   - [EmitOutcome.notAttempted] keeps the classifier bucket as the
///     upper-bound measurement (deferred/structural widgets, or a
///     classifier-only run);
///   - a `deferred`/`structural` classifier verdict is never promoted by
///     an emit outcome — there is nothing to emit-confirm.
CoverageBucket bucketForEmit(
  WidgetClassification classification,
  EmitOutcome outcome,
) {
  final classifierBucket = bucketFor(classification);
  if (outcome == EmitOutcome.failed && classifierBucket.isInlinable) {
    return CoverageBucket.classifierOnly;
  }
  return classifierBucket;
}

CoverageBucket _composableBucket(Set<InliningMechanism> mechanisms) {
  if (mechanisms.contains(InliningMechanism.declarativeState)) {
    return CoverageBucket.inlinableDeclarativeState;
  }
  if (mechanisms.contains(InliningMechanism.themeAsData)) {
    return CoverageBucket.inlinableThemeAsData;
  }
  if (mechanisms.contains(InliningMechanism.constantFolding)) {
    return CoverageBucket.inlinableConstantFold;
  }
  return CoverageBucket.inlinableComposition;
}
