// packages/rfw_catalog_compiler/lib/src/policy/priority_heuristics.dart
import 'package:meta/meta.dart';

/// Heuristic settings that control property-priority ordering.
@immutable
final class PriorityHeuristics {
  /// Creates a priority heuristics instance.
  const PriorityHeuristics({
    required this.requiredAsPrimary,
    required this.firstNCommon,
  });

  /// Whether required parameters are promoted to primary priority.
  final bool requiredAsPrimary;

  /// Number of leading common parameters promoted to common priority.
  final int firstNCommon;

  /// Returns a new instance with the supplied overrides applied.
  PriorityHeuristics extend({
    bool? requiredAsPrimary,
    int? firstNCommon,
  }) =>
      PriorityHeuristics(
        requiredAsPrimary: requiredAsPrimary ?? this.requiredAsPrimary,
        firstNCommon: firstNCommon ?? this.firstNCommon,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PriorityHeuristics &&
          other.requiredAsPrimary == requiredAsPrimary &&
          other.firstNCommon == firstNCommon);

  @override
  int get hashCode => Object.hash(requiredAsPrimary, firstNCommon);
}
