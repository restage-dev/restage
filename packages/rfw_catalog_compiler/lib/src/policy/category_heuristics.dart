// packages/rfw_catalog_compiler/lib/src/policy/category_heuristics.dart
import 'package:meta/meta.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart'
    show PropertyCategory;

/// Heuristic rules for property category inference.
@immutable
final class CategoryHeuristics {
  /// Creates a category heuristics instance with the supplied rules.
  const CategoryHeuristics({required this.rules});

  /// Ordered list of category inference rules.
  final List<CategoryRule> rules;

  /// Returns a new instance that appends [rules] to this instance's rules.
  CategoryHeuristics extend({List<CategoryRule> rules = const []}) =>
      CategoryHeuristics(rules: [...this.rules, ...rules]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CategoryHeuristics) return false;
    if (rules.length != other.rules.length) return false;
    for (var i = 0; i < rules.length; i++) {
      if (rules[i] != other.rules[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(rules);
}

/// One category inference rule.
@immutable
final class CategoryRule {
  /// Creates a category rule.
  const CategoryRule({
    required this.namePattern,
    required this.category,
    this.typeNameFilter,
  });

  /// Source-form regex; we store the pattern string rather than a
  /// RegExp instance so the rule itself remains const-constructible.
  final String namePattern;

  /// Optional Dart type display-name filter.
  final String? typeNameFilter;

  /// The category to assign when the rule matches.
  final PropertyCategory category;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CategoryRule &&
          other.namePattern == namePattern &&
          other.typeNameFilter == typeNameFilter &&
          other.category == category);

  @override
  int get hashCode => Object.hash(namePattern, typeNameFilter, category);
}
