// packages/rfw_catalog_compiler/lib/src/policy/metadata_inference.dart

/// Property-metadata inference functions.
///
/// This file is the home for pure functions that derive catalog metadata
/// (category, priority, etc.) from property name and type information,
/// using the policy objects defined in this package.
library;

import 'package:rfw_catalog_compiler/src/policy/category_heuristics.dart';
import 'package:rfw_catalog_compiler/src/policy/priority_heuristics.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart'
    show PropertyCategory, PropertyPriority;

/// Returns the [PropertyCategory] for a property named [name], or `null`
/// if no rule in [heuristics] matches.
///
/// Rules are evaluated in order; the first match wins.
///
/// If a rule carries a non-null [CategoryRule.typeNameFilter], the rule
/// matches only when [typeName] equals that filter.  When [typeName] is
/// `null` and the rule has a type filter, the rule does **not** match.
///
/// Returning `null` is deliberate and conservative: a property that does
/// not match any heuristic carries no category claim rather than a
/// guessed one.  Callers should treat a `null` return as "uncategorized"
/// rather than an error.
///
/// Throws [FormatException] if any [CategoryRule.namePattern] is not a
/// valid regular expression.
PropertyCategory? inferPropertyCategory(
  String name,
  CategoryHeuristics heuristics, {
  String? typeName,
}) {
  for (final rule in heuristics.rules) {
    // Type filter: skip the rule when the filter is set and typeName
    // doesn't match (including when typeName is null).
    if (rule.typeNameFilter != null && rule.typeNameFilter != typeName) {
      continue;
    }
    if (RegExp(rule.namePattern).hasMatch(name)) {
      return rule.category;
    }
  }
  return null;
}

/// Returns the [PropertyPriority] for a property, or `null` if no priority
/// claim can be made with confidence.
///
/// When [required] is `true` and `heuristics.requiredAsPrimary` is `true`,
/// the property is promoted to [PropertyPriority.primary]: a required
/// constructor parameter is definitionally the most important property on a
/// widget, a high-confidence, conservative inference.
///
/// [PriorityHeuristics.firstNCommon] is deliberately left unwired by design:
/// declaration order is not a reliable importance signal, so this function
/// takes no declaration-index parameter — making it structurally impossible
/// to consult `firstNCommon`.
///
/// Callers should treat a `null` return as "no priority claim" (left to
/// deliberate curation), not as an error.
PropertyPriority? inferPropertyPriority({
  required bool required,
  required PriorityHeuristics heuristics,
}) =>
    required && heuristics.requiredAsPrimary ? PropertyPriority.primary : null;
