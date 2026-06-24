import 'package:meta/meta.dart';
import 'package:restage_codegen/src/coverage_measurement/coverage_walker.dart';
import 'package:restage_codegen/src/widget_classification.dart';

/// The seven buckets a customer widget falls into when measured for
/// inlinability.
///
/// The four `inlinable*` buckets group widgets the classifier
/// **recognises** as composable + needing some subset of the
/// implemented inlining mechanisms. Buckets are disambiguated by the
/// highest mechanism the widget needs; precedence is
/// `declarativeState > themeAsData > constantFolding >
/// composition-only` — each bucket implies the lower mechanisms may
/// also be present.
///
/// **Classifier-recognised vs emit-confirmed.** The classifier is
/// intentionally over-broad: it accepts a wider set than the translator
/// emits. A widget the classifier marks as needing `themeAsData` may
/// still fail to emit if its actual `Theme.of` read is outside the theme
/// contract; a widget marked `declarativeState` may still fail if its
/// initialiser is non-foldable or its setState body is unrecognised. The
/// translator's strict inline path is the gate at emit time.
///
/// The bucketing has two modes:
///   - **Classifier-only** ([bucketFor], or [CoverageReport.from] with no
///     `emitOutcomes`): each `inlinable*` bucket measures what the
///     classifier *recognises* — a useful upper bound on emit success.
///   - **Emit-confirmed** ([bucketForEmit], or [CoverageReport.from] with
///     `emitOutcomes`): a widget the classifier recognised as inlinable
///     but whose strict emit produced issues is demoted to
///     [CoverageBucket.classifierOnly], so the `inlinable*` buckets
///     measure what actually emits. This is the honest metric — it cannot
///     bless a widget the translator would not emit.
///
/// `deferred` and `structural` distinguish the two ways a widget falls
/// out of the inlinable set:
///
///   - **Deferred** — additional codegen support could move the widget
///     into an `inlinable*` bucket; the customer can rewrite to a
///     recognised shape today. The classifier surfaces this as an
///     `UnclassifiableWidget` (its `build()` contains a construct the
///     classifier does not yet recognise).
///   - **Structural** — the widget uses imperative compute / lifecycle /
///     paint that RFW's declarative format cannot express. Codegen
///     support is intentionally unavailable for these shapes. The
///     classifier surfaces this as an
///     `ImperativeWidget` with one or more blockers.
enum CoverageBucket {
  /// Inlinable today; pure composition of catalog widgets, no extra
  /// mechanism beyond catalog composition.
  inlinableComposition('inlinable/composition-only'),

  /// Inlinable today; uses build-time-constant compute folded to
  /// literals (e.g. `EdgeInsets.all(_kGap)`).
  inlinableConstantFold('inlinable/+const-fold'),

  /// Inlinable today; reads `Theme.of(context).<role>` lowered to
  /// `data.theme.*` references.
  inlinableThemeAsData('inlinable/+theme-as-data'),

  /// Inlinable today; carries declarative state (a `StatefulWidget`
  /// with primitive State fields, recognised setState bodies).
  inlinableDeclarativeState('inlinable/+declarative-state'),

  /// The classifier **recognised** the widget as inlinable, but the
  /// translator's strict emit path produced issues — so it does **not**
  /// inline today. This is the gap between classifier-recognised and
  /// emit-confirmed: a `themeAsData` widget whose actual `Theme.of` read
  /// is out of contract, a `declarativeState` widget with a non-foldable
  /// initialiser or an unrecognised setState body, a composition that
  /// collides on its RFW name, etc. Populated only when the harness
  /// supplies emit outcomes (see [EmitOutcome]); a classifier-only run
  /// never lands a widget here. It is **not** counted in
  /// [CoverageReport.inlinableTotal] — the rollup counts emit-confirmed
  /// inlinables only.
  classifierOnly('classifier-only/emit-failed'),

  /// Recognised by the classifier but not yet inlinable today — an
  /// additional codegen increment could recognise the missing construct
  /// or the customer can rewrite to a shape that classifies as
  /// inlinable now.
  deferred('deferred'),

  /// Imperative — uses constructs RFW's declarative format cannot
  /// express.
  structural('structural');

  const CoverageBucket(this.snapshotKey);

  /// Stable identifier for this bucket in the snapshot file and report.
  /// Order in the JSON tracks the enum's declaration order.
  final String snapshotKey;

  /// Whether this is one of the four emit-target `inlinable*` buckets — the
  /// single source of truth for "counts as inlinable", consumed by the
  /// `inlinableTotal` rollup and the emit-aware demotion (`bucketForEmit`).
  /// `classifierOnly` is deliberately excluded: it is recognised-but-not-
  /// emit-confirmed, so it does not count toward inlinability.
  bool get isInlinable => switch (this) {
        inlinableComposition ||
        inlinableConstantFold ||
        inlinableThemeAsData ||
        inlinableDeclarativeState =>
          true,
        classifierOnly || deferred || structural => false,
      };
}

/// The translator's strict-emit verdict for a widget the harness measured —
/// whether attempting the real inline emit produced a clean RFW definition.
///
/// Supplied to [CoverageReport.from] / [bucketForEmit] to upgrade the metric
/// from classifier-recognised to emit-confirmed.
enum EmitOutcome {
  /// The strict emit produced a definition with no issues — emit-confirmed
  /// inlinable.
  confirmed,

  /// The classifier recognised the widget as inlinable, but the strict
  /// emit path produced issues (an out-of-contract theme read, a
  /// non-foldable state initialiser, an unrecognised expression, an RFW
  /// name collision). The classifier over-counted; this widget does not
  /// inline today.
  failed,

  /// Emit was not attempted — the widget is deferred/structural (nothing
  /// to confirm), or the harness ran in classifier-only mode. The
  /// classifier bucket stands as the upper-bound measurement.
  notAttempted,
}

/// A bucketed view of a measured corpus of customer widgets, plus a
/// roll-up of the four `inlinable*` buckets.
///
/// Build via [CoverageReport.from] from a `widgetKey → WidgetClassification`
/// map (the same `'<library URI>#<Class>'` keys the classifier produces).
/// The report exposes counts and the per-bucket widget key lists for
/// drill-down in the human-facing report.
@immutable
class CoverageReport {
  CoverageReport._(Map<CoverageBucket, List<String>> entries)
      : _entries = {
          for (final bucket in CoverageBucket.values)
            bucket: List.unmodifiable(entries[bucket] ?? const <String>[]),
        };

  /// Buckets [classifications] (keyed by widget identity — typically the
  /// classifier's `classKey`) into a [CoverageReport]. Widget keys
  /// inside each bucket are sorted alphabetically so the report is
  /// deterministic across runs.
  ///
  /// When [emitOutcomes] is supplied (keyed the same way), the bucketing is
  /// emit-confirmed: a widget the classifier recognised as inlinable but
  /// whose [EmitOutcome] is [EmitOutcome.failed] is demoted to
  /// [CoverageBucket.classifierOnly]. A widget absent from [emitOutcomes]
  /// is treated as [EmitOutcome.notAttempted] (its classifier bucket
  /// stands). When [emitOutcomes] is null the report is classifier-only —
  /// the upper-bound measurement.
  factory CoverageReport.from(
    Map<String, WidgetClassification> classifications, {
    Map<String, EmitOutcome>? emitOutcomes,
  }) {
    final entries = <CoverageBucket, List<String>>{
      for (final bucket in CoverageBucket.values) bucket: <String>[],
    };
    for (final entry in classifications.entries) {
      final bucket = emitOutcomes == null
          ? bucketFor(entry.value)
          : bucketForEmit(
              entry.value,
              emitOutcomes[entry.key] ?? EmitOutcome.notAttempted,
            );
      entries[bucket]!.add(entry.key);
    }
    for (final list in entries.values) {
      list.sort();
    }
    return CoverageReport._(entries);
  }

  final Map<CoverageBucket, List<String>> _entries;

  /// Number of widgets in [bucket].
  int countOf(CoverageBucket bucket) => _entries[bucket]!.length;

  /// Widget keys that landed in [bucket].
  List<String> widgetsIn(CoverageBucket bucket) => _entries[bucket]!;

  /// Sum of counts across the four `inlinable*` buckets — the headline
  /// "what fraction inlines today" number, useful for chapter-level
  /// roll-up. Keyed off [CoverageBucket.isInlinable], the single source of
  /// truth for the inlinable set.
  int get inlinableTotal => CoverageBucket.values
      .where((b) => b.isInlinable)
      .fold(0, (sum, b) => sum + countOf(b));

  /// Total widgets measured.
  int get total => _entries.values.fold(0, (sum, list) => sum + list.length);

  /// Stable JSON shape for the on-disk snapshot — the bucket
  /// `snapshotKey` mapped to the sorted list of widget keys that
  /// landed in that bucket, in `CoverageBucket.values` declaration
  /// order. The per-bucket key list (rather than a bare count) is
  /// the stronger regression signal: a balanced bucket-swap (one
  /// widget moves out, another moves in, count unchanged) shows up
  /// in the keys but not in the count, so the snapshot catches it.
  Map<String, List<String>> toSnapshotJson() => <String, List<String>>{
        for (final bucket in CoverageBucket.values)
          bucket.snapshotKey: widgetsIn(bucket),
      };
}
