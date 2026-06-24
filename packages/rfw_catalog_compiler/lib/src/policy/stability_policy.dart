// packages/rfw_catalog_compiler/lib/src/policy/stability_policy.dart
import 'package:meta/meta.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart' show Stability;

/// Stability-tier rules for catalog entries.
@immutable
final class StabilityPolicy {
  /// Creates a stability policy.
  const StabilityPolicy({
    required this.defaultTier,
    required this.annotationPromotion,
  });

  /// [Stability.volatile] for auto-walked entries;
  /// [Stability.stable] requires opt-in.
  final Stability defaultTier;

  /// Honor `@StableProperty` / `@StableWidget` annotations.
  final bool annotationPromotion;

  /// Returns a new policy with the supplied overrides applied.
  StabilityPolicy extend({
    Stability? defaultTier,
    bool? annotationPromotion,
  }) =>
      StabilityPolicy(
        defaultTier: defaultTier ?? this.defaultTier,
        annotationPromotion: annotationPromotion ?? this.annotationPromotion,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StabilityPolicy &&
          other.defaultTier == defaultTier &&
          other.annotationPromotion == annotationPromotion);

  @override
  int get hashCode => Object.hash(defaultTier, annotationPromotion);
}
