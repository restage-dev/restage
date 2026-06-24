// packages/rfw_catalog_compiler/lib/src/policy/policy_ledger.dart
import 'package:meta/meta.dart';
import 'package:rfw_catalog_compiler/src/policy/category_heuristics.dart';
import 'package:rfw_catalog_compiler/src/policy/default_content/default_category_heuristics.dart';
import 'package:rfw_catalog_compiler/src/policy/default_content/default_design_token_heuristics.dart';
import 'package:rfw_catalog_compiler/src/policy/default_content/default_mutex_rules.dart';
import 'package:rfw_catalog_compiler/src/policy/default_content/default_priority_heuristics.dart';
import 'package:rfw_catalog_compiler/src/policy/default_content/default_structured_walk.dart';
import 'package:rfw_catalog_compiler/src/policy/default_content/default_theme_binding_seeds.dart';
import 'package:rfw_catalog_compiler/src/policy/default_content/default_type_denylist.dart';
import 'package:rfw_catalog_compiler/src/policy/default_content/default_union_seeds.dart';
import 'package:rfw_catalog_compiler/src/policy/default_content/default_widget_denylist.dart';
import 'package:rfw_catalog_compiler/src/policy/denylist_policy.dart';
import 'package:rfw_catalog_compiler/src/policy/design_token_heuristics.dart';
import 'package:rfw_catalog_compiler/src/policy/mutex_policy.dart';
import 'package:rfw_catalog_compiler/src/policy/priority_heuristics.dart';
import 'package:rfw_catalog_compiler/src/policy/stability_policy.dart';
import 'package:rfw_catalog_compiler/src/policy/structured_walk_policy.dart';
import 'package:rfw_catalog_compiler/src/policy/theme_binding_seeds.dart';
import 'package:rfw_catalog_compiler/src/policy/union_registry.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart' show Stability;

/// Immutable bag of every compiler policy. Constructed once per
/// compile pass and threaded through the analysis pipeline.
@immutable
final class PolicyLedger {
  /// Creates a policy ledger with all sub-policies specified.
  const PolicyLedger({
    required this.denylist,
    required this.mutexRules,
    required this.stabilityRules,
    required this.unionRegistry,
    required this.themeBindingSeeds,
    required this.designTokenHeuristics,
    required this.categoryHeuristics,
    required this.priorityHeuristics,
    required this.structuredWalk,
  });

  /// The default ledger shipped with the compiler.
  const PolicyLedger.builtIn()
      : denylist = const DenylistPolicy(
          types: kBuiltInTypeDenylist,
          typeSuffixes: kBuiltInTypeDenylistSuffixes,
          widgets: kBuiltInWidgetDenylist,
          properties: {},
        ),
        mutexRules = const MutexPolicy(rules: kBuiltInMutexRules),
        stabilityRules = const StabilityPolicy(
          defaultTier: Stability.volatile,
          annotationPromotion: true,
        ),
        unionRegistry = const UnionRegistry(entries: kBuiltInUnionSeeds),
        themeBindingSeeds =
            const ThemeBindingSeeds(namePatterns: kBuiltInThemeBindingSeeds),
        designTokenHeuristics = const DesignTokenHeuristics(
          patterns: kBuiltInDesignTokenHeuristics,
        ),
        categoryHeuristics =
            const CategoryHeuristics(rules: kBuiltInCategoryHeuristics),
        priorityHeuristics = const PriorityHeuristics(
          requiredAsPrimary: kBuiltInRequiredAsPrimary,
          firstNCommon: kBuiltInFirstNCommon,
        ),
        structuredWalk = const StructuredWalkPolicy(
          concreteTypes: kBuiltInStructuredConcrete,
          abstractTypes: kBuiltInStructuredAbstract,
          // Source the depth from the default-content constants so every
          // built-in policy value lives in one place, even when it
          // matches the class-level default.
          // ignore: avoid_redundant_argument_values
          maxDepth: kBuiltInStructuredMaxDepth,
        );

  /// Type- and widget-exclusion rules.
  final DenylistPolicy denylist;

  /// Mutually-exclusive property group rules.
  final MutexPolicy mutexRules;

  /// Stability-tier rules for catalog entries.
  final StabilityPolicy stabilityRules;

  /// Abstract-type to concrete-subtype mappings.
  final UnionRegistry unionRegistry;

  /// Theme-binding seed patterns for property inference.
  final ThemeBindingSeeds themeBindingSeeds;

  /// Design-token heuristic patterns for property inference.
  final DesignTokenHeuristics designTokenHeuristics;

  /// Category heuristic rules for property inference.
  final CategoryHeuristics categoryHeuristics;

  /// Priority heuristic settings for property ordering.
  final PriorityHeuristics priorityHeuristics;

  /// Structured-type whitelist + abstract list governing walker
  /// recursion into nested value types.
  final StructuredWalkPolicy structuredWalk;

  /// Returns a new ledger that replaces the supplied policies and
  /// preserves identity of the others.
  PolicyLedger extend({
    DenylistPolicy? denylist,
    MutexPolicy? mutexRules,
    StabilityPolicy? stabilityRules,
    UnionRegistry? unionRegistry,
    ThemeBindingSeeds? themeBindingSeeds,
    DesignTokenHeuristics? designTokenHeuristics,
    CategoryHeuristics? categoryHeuristics,
    PriorityHeuristics? priorityHeuristics,
    StructuredWalkPolicy? structuredWalk,
  }) {
    return PolicyLedger(
      denylist: denylist ?? this.denylist,
      mutexRules: mutexRules ?? this.mutexRules,
      stabilityRules: stabilityRules ?? this.stabilityRules,
      unionRegistry: unionRegistry ?? this.unionRegistry,
      themeBindingSeeds: themeBindingSeeds ?? this.themeBindingSeeds,
      designTokenHeuristics:
          designTokenHeuristics ?? this.designTokenHeuristics,
      categoryHeuristics: categoryHeuristics ?? this.categoryHeuristics,
      priorityHeuristics: priorityHeuristics ?? this.priorityHeuristics,
      structuredWalk: structuredWalk ?? this.structuredWalk,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PolicyLedger &&
          other.denylist == denylist &&
          other.mutexRules == mutexRules &&
          other.stabilityRules == stabilityRules &&
          other.unionRegistry == unionRegistry &&
          other.themeBindingSeeds == themeBindingSeeds &&
          other.designTokenHeuristics == designTokenHeuristics &&
          other.categoryHeuristics == categoryHeuristics &&
          other.priorityHeuristics == priorityHeuristics &&
          other.structuredWalk == structuredWalk);

  @override
  int get hashCode => Object.hash(
        denylist,
        mutexRules,
        stabilityRules,
        unionRegistry,
        themeBindingSeeds,
        designTokenHeuristics,
        categoryHeuristics,
        priorityHeuristics,
        structuredWalk,
      );
}
