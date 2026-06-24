import 'package:analyzer/dart/element/type.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Maps an abstract Flutter base type (e.g. `Gradient`, `BoxBorder`) to
/// the legacy [PropertyType] member that downstream code uses to lower
/// it on the wire.
///
/// Returns `null` when [type] is not one of the recognized abstract
/// bases — callers fall through to the structured-walker placeholder
/// path, where the field surfaces as a `structured` slot awaiting the
/// future union-resolver pass.
///
/// This is the single source of truth for the abstract-base fallback
/// map across the reflector (top-level properties) and the structured
/// walker (nested structured fields). Schema-evolution decisions
/// (introducing new [PropertyType] members vs. leaning on the union
/// resolver) belong to the catalog-schema contract, not to ad-hoc
/// per-call-site maps.
PropertyType? abstractStructuredFallback(DartType type) {
  final displayName = type.getDisplayString();
  final stripped = displayName.endsWith('?')
      ? displayName.substring(0, displayName.length - 1)
      : displayName;
  return switch (stripped) {
    'Gradient' => PropertyType.gradient,
    'BoxBorder' => PropertyType.border,
    'ShapeBorder' => PropertyType.shapeBorder,
    'OutlinedBorder' => PropertyType.shapeBorder,
    _ => null,
  };
}
