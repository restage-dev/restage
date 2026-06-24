// packages/rfw_catalog_compiler/lib/src/policy/design_token_heuristics.dart
import 'package:meta/meta.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart' show WireIdRef;

/// Heuristics that map property-name patterns to design-token wire IDs.
@immutable
final class DesignTokenHeuristics {
  /// Creates a design-token heuristics instance with the supplied patterns.
  const DesignTokenHeuristics({required this.patterns});

  /// Property-name patterns → design-token wire IDs.
  final Map<String, WireIdRef> patterns;

  /// Returns a new instance that merges this instance's patterns with
  /// [patterns].
  DesignTokenHeuristics extend({
    Map<String, WireIdRef> patterns = const {},
  }) =>
      DesignTokenHeuristics(patterns: {...this.patterns, ...patterns});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DesignTokenHeuristics &&
          patterns.length == other.patterns.length &&
          patterns.entries.every((e) => other.patterns[e.key] == e.value));

  @override
  int get hashCode => Object.hashAllUnordered(
        patterns.entries.map((e) => Object.hash(e.key, e.value)),
      );
}
