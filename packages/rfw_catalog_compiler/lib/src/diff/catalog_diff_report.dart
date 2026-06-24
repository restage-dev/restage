import 'package:meta/meta.dart';
import 'package:rfw_catalog_compiler/src/diff/catalog_change.dart';
import 'package:rfw_catalog_compiler/src/diff/catalog_diff.dart';
import 'package:rfw_catalog_compiler/src/diff/compat_classifier.dart';
import 'package:rfw_catalog_compiler/src/diff/compat_rule_emitter.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// A detected [CatalogChange] paired with its compatibility classification.
@immutable
@experimental
final class ClassifiedChange {
  /// Pairs [change] with its [classification].
  const ClassifiedChange({
    required this.change,
    required this.classification,
  });

  /// The detected per-entry change.
  final CatalogChange change;

  /// The change's four-way compatibility classification.
  final CompatClassification classification;

  @override
  bool operator ==(Object other) =>
      other is ClassifiedChange &&
      other.change == change &&
      other.classification == classification;

  @override
  int get hashCode => Object.hash(change, classification);
}

/// The full result of diffing two canonical catalog versions: every
/// detected change with its classification, plus the emitted CompatRules.
@immutable
@experimental
final class CatalogDiffReport {
  /// Creates a diff report.
  const CatalogDiffReport({
    required this.fromVersion,
    required this.toVersion,
    required this.changes,
    required this.compatRules,
  });

  /// Version label of the baseline (version A) catalog.
  final String fromVersion;

  /// Version label of the current (version B) catalog.
  final String toVersion;

  /// Every detected per-entry change, each paired with its classification,
  /// in deterministic order.
  final List<ClassifiedChange> changes;

  /// The CompatRules emitted for the `forwarding` / `breaking` changes —
  /// the subset the backend forwarding layer consumes at decode time.
  final List<CompatRule> compatRules;
}

/// Diffs two canonical catalog versions end to end: detects every per-entry
/// change, classifies each per the compatibility taxonomy, and emits the
/// CompatRules for the `forwarding` / `breaking` ones.
///
/// [fromVersion] / [toVersion] default to the catalogs' `generatedAt`
/// timestamps when not supplied. Both [baseline] and [current] must be
/// canonical catalogs — entries carry wire IDs.
///
/// Infrastructure ahead of application: this end-to-end diff path has no
/// production consumer yet (the emitted `CompatRule` type is production; the
/// diff/classifier logic that produces it is not wired in).
@experimental
CatalogDiffReport computeCatalogDiff(
  Catalog baseline,
  Catalog current, {
  String? fromVersion,
  String? toVersion,
}) {
  final from = fromVersion ?? baseline.generatedAt;
  final to = toVersion ?? current.generatedAt;
  final detected = diffCatalogs(baseline, current);
  return CatalogDiffReport(
    fromVersion: from,
    toVersion: to,
    changes: [
      for (final change in detected)
        ClassifiedChange(
          change: change,
          classification: classifyCatalogChange(change),
        ),
    ],
    compatRules: emitCompatRules(detected, fromVersion: from, toVersion: to),
  );
}
