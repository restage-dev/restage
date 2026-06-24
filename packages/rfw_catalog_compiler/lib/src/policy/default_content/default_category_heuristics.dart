// packages/rfw_catalog_compiler/lib/src/policy/default_content/default_category_heuristics.dart
import 'package:rfw_catalog_compiler/src/policy/category_heuristics.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart'
    show PropertyCategory;

/// Built-in category heuristics seeding the obvious cases.
/// Patterns are anchored regex source strings; the consumer compiles
/// them at filter time.
const List<CategoryRule> kBuiltInCategoryHeuristics = [
  CategoryRule(
    namePattern: r'^(alignment|crossAxisAlignment|mainAxisAlignment)$',
    category: PropertyCategory.layout,
  ),
  CategoryRule(
    namePattern: r'^(color|backgroundColor|foregroundColor)$',
    category: PropertyCategory.style,
  ),
  CategoryRule(
    namePattern: r'^on[A-Z].*$',
    category: PropertyCategory.behavior,
  ),
  CategoryRule(
    namePattern: r'^semantic.*$',
    category: PropertyCategory.accessibility,
  ),
];
