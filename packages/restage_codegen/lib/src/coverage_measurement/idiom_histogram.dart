// A frequency table of the widget/Dart idioms a measured corpus of widgets
// exhibits — the findings output that surfaces which real-world constructs
// block or defer inlining. Built purely from the classifier verdicts; no I/O.
//
// This file is `src`-internal tooling, NOT exported from the package barrel.
// Its consumers are the pub.dev measurement entrypoint and its tests.

import 'package:meta/meta.dart';
import 'package:restage_codegen/src/widget_classification.dart';

/// A structured idiom-aggregation key: the construct's classification [kind]
/// (`'<BlockerKind>'`, `'unclassifiable'`, or `'composable'`) and its [subject]
/// (the type/method/field name, an unclassifiable reason head, or a mechanism
/// name). Value-equal so the histogram aggregates on structure, not on a parsed
/// display string.
///
/// For blocker subjects, [subject] is the producer-threaded
/// `Blocker.idiomSubject` (the AST-resolved type / method / field name), read
/// directly — no string-parse of the human-facing detail. A blocker without an
/// `idiomSubject` falls back to its raw `detail`.
@immutable
final class IdiomKey {
  /// Creates an idiom key.
  const IdiomKey(this.kind, this.subject);

  /// The construct's classification family.
  final String kind;

  /// The construct's discriminating name.
  final String subject;

  /// `'<kind> · <subject>'` — the human label (unchanged from the prior
  /// format).
  String get label => '$kind · $subject';

  @override
  bool operator ==(Object other) =>
      other is IdiomKey && other.kind == kind && other.subject == subject;

  @override
  int get hashCode => Object.hash(kind, subject);
}

/// One aggregated idiom row — a construct that appeared across the measured
/// corpus, with how often, its disposition, and whether it is a genuine idiom
/// gap or a measurement artifact of scanning un-annotated packages.
class IdiomRow {
  /// Creates an idiom row.
  IdiomRow({
    required this.key,
    required this.count,
    required this.disposition,
    required this.isUnrecognisedComposition,
    required this.examples,
  });

  /// The structured aggregation key — the construct's [IdiomKey.kind] and
  /// [IdiomKey.subject].
  final IdiomKey key;

  /// Human label — `'<kind> · <subject>'`: `'<blockerKind> · <detail-head>'`,
  /// `'unclassifiable · <reason-head>'`, or `'composable · <mechanism>'`.
  /// Derived from [key].
  String get label => key.label;

  /// How many times this idiom appeared across the corpus.
  final int count;

  /// The disposition this idiom carries when it is a blocker (`reducible` =
  /// a backlog candidate, `deadEnd` = a genuine RFW boundary). Null for
  /// composable / unclassifiable rows, which are not capability boundaries.
  final CustomWidgetDisposition? disposition;

  /// True for `unrecognisedComposedWidget` rows — a composed `Widget` that is
  /// neither a catalog widget nor an `@RestageWidget`-annotated one. These need
  /// inspection (the `Blocker` carries only the source, not the composed type's
  /// library), because the bucket is a **mix**:
  ///   * **in-package sub-widgets** (e.g. `_RawGap`) — the classifier only
  ///     recurses into `@RestageWidget` widgets, so a non-instrumented
  ///     package's own sub-widgets land here. This UNDER-states inlinability
  ///     (false-4b, the safe direction) and is a measurement artifact, NOT a
  ///     catalog gap;
  ///   * **framework / third-party widgets not in our catalog** (e.g.
  ///     `LayoutBuilder`) — a genuine catalog / 4b gap.
  ///
  /// The detail-head (the type name) is the discriminator: `_`-prefixed /
  /// obviously-internal names are typically the former; framework names the
  /// latter. Reported under a separate heading so neither is conflated with the
  /// unambiguous idiom gaps.
  final bool isUnrecognisedComposition;

  /// Up to three example locations / class keys, for drill-down.
  final List<String> examples;
}

/// A frequency table of the idioms a measured corpus exhibits — which
/// constructs block or defer inlining, ranked by how often they appear.
class IdiomHistogram {
  IdiomHistogram._(this.rows);

  /// Aggregates [classifications] (the classifier's `classKey → verdict` map)
  /// into an idiom histogram.
  factory IdiomHistogram.from(
    Map<String, WidgetClassification> classifications,
  ) {
    final counts = <IdiomKey, int>{};
    final dispositions = <IdiomKey, CustomWidgetDisposition?>{};
    final unrecognisedCompositions = <IdiomKey>{};
    final examples = <IdiomKey, List<String>>{};

    void bump(
      IdiomKey key,
      String example, {
      CustomWidgetDisposition? disposition,
      bool unrecognisedComposition = false,
    }) {
      counts[key] = (counts[key] ?? 0) + 1;
      // Key-stable for every kind except `composesImperativeWidget`, whose
      // disposition is per-instance (the composed child's). Two such blockers
      // sharing a (kind, subject) key but differing in child disposition
      // collide here (last write wins) — acceptable for a frequency tool.
      dispositions[key] = disposition;
      if (unrecognisedComposition) unrecognisedCompositions.add(key);
      (examples[key] ??= <String>[]).add(example);
    }

    for (final classification in classifications.values) {
      switch (classification) {
        case ImperativeWidget(:final blockers):
          for (final b in blockers) {
            bump(
              IdiomKey(b.kind.name, b.idiomSubject ?? b.detail),
              b.location,
              disposition: b.disposition,
              unrecognisedComposition:
                  b.kind == BlockerKind.unrecognisedComposedWidget,
            );
          }
        case UnclassifiableWidget(:final reason):
          bump(
            IdiomKey('unclassifiable', _reasonHead(reason)),
            classification.classKey,
          );
        case ComposableWidget(:final requiredMechanisms):
          if (requiredMechanisms.isEmpty) {
            bump(
              const IdiomKey('composable', 'composition-only'),
              classification.classKey,
            );
          } else {
            for (final m in requiredMechanisms) {
              bump(IdiomKey('composable', m.name), classification.classKey);
            }
          }
      }
    }

    final rows = [
      for (final key in counts.keys)
        IdiomRow(
          key: key,
          count: counts[key]!,
          disposition: dispositions[key],
          isUnrecognisedComposition: unrecognisedCompositions.contains(key),
          // Sorted before truncation so the kept three are stable regardless of
          // iteration order (deterministic even if a key recurs >3 times).
          examples: List.unmodifiable((examples[key]!..sort()).take(3)),
        ),
    ]..sort((a, b) {
        final byCount = b.count.compareTo(a.count);
        return byCount != 0 ? byCount : a.label.compareTo(b.label);
      });
    return IdiomHistogram._(List.unmodifiable(rows));
  }

  /// Rows, sorted by descending count then label (deterministic).
  final List<IdiomRow> rows;

  /// Stable JSON — a list of `{kind, subject, label, count, disposition?,
  /// unrecognisedComposition, examples}` in row (count-sorted) order. `kind`
  /// and `subject` are the structured aggregation key; `label` is their
  /// `' · '` join, retained for readers that key on the display string.
  List<Map<String, dynamic>> toJson() => [
        for (final r in rows)
          <String, dynamic>{
            'kind': r.key.kind,
            'subject': r.key.subject,
            'label': r.label,
            'count': r.count,
            if (r.disposition != null) 'disposition': r.disposition!.name,
            'unrecognisedComposition': r.isUnrecognisedComposition,
            'examples': r.examples,
          },
      ];

  /// A human-readable table. The unambiguous idiom gaps and the
  /// unrecognised-composition rows are listed under separate headings, so the
  /// in-package recursion-gate artifacts in the latter are never conflated with
  /// the clean idiom signals.
  String render() {
    final idiomGaps = rows.where((r) => !r.isUnrecognisedComposition).toList();
    final compositions =
        rows.where((r) => r.isUnrecognisedComposition).toList();

    String line(IdiomRow r) => '  ${r.count.toString().padLeft(4)}  ${r.label}';

    final buf = StringBuffer()..writeln('Idiom histogram (genuine gaps):');
    if (idiomGaps.isEmpty) {
      buf.writeln('  (none)');
    } else {
      for (final r in idiomGaps) {
        buf.writeln(line(r));
      }
    }
    if (compositions.isNotEmpty) {
      buf
        ..writeln()
        ..writeln('Unrecognised compositions (inspect the type — a mix of '
            'in-package sub-widgets [recursion-gate artifact, under-states '
            'inlinability] and non-catalog framework widgets [a real gap]):');
      for (final r in compositions) {
        buf.writeln(line(r));
      }
    }
    return buf.toString();
  }
}

/// The first clause of an unclassifiable reason (everything up to the first
/// comma — the "…, which this transpiler increment does not yet …" tail is
/// dropped), so similar reasons aggregate into one row. Capped to keep the
/// label readable. The comma is the only split point: a `(` is not, so a reason
/// that opens with `build()` keeps its meaning rather than truncating to
/// `build`.
String _reasonHead(String reason) {
  final head = reason.split(',').first.trim();
  return head.length <= 80 ? head : '${head.substring(0, 79)}…';
}
