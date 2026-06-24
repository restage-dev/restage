// packages/rfw_catalog_compiler/lib/src/policy/structured_walk_policy.dart
import 'package:meta/meta.dart';

/// Whitelist + abstract-base list governing how the compiler recurses
/// into structured value types (e.g. `BoxDecoration`, `TextStyle`).
///
/// The walker uses this policy to decide, for each interface type it
/// encounters, whether to (a) recurse INTO it as a concrete structured
/// type, (b) short-circuit on it as an abstract base whose subtypes
/// are catalogued separately, or (c) leave it for non-structured
/// handling. [maxDepth] guards against unbounded recursion through
/// type graphs that loop or are pathologically deep.
@immutable
final class StructuredWalkPolicy {
  /// Creates a structured-walk policy with the supplied whitelist,
  /// abstract list, and depth cap.
  const StructuredWalkPolicy({
    required this.concreteTypes,
    required this.abstractTypes,
    this.maxDepth = 8,
  });

  /// Fully-qualified identifiers (`<library identifier>#<class name>`)
  /// of concrete value types the walker recurses INTO. Each match
  /// expands the property surface with the structured type's own
  /// constructor parameters.
  final Set<String> concreteTypes;

  /// Fully-qualified identifiers of abstract base types the walker
  /// short-circuits on. Matches stop recursion at this node; the
  /// union registry handles dispatch to the concrete subtypes
  /// separately.
  final Set<String> abstractTypes;

  /// Maximum recursion depth before the walker stops descending into
  /// nested structured types. Defaults to 8.
  final int maxDepth;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is StructuredWalkPolicy &&
        _setEquals(concreteTypes, other.concreteTypes) &&
        _setEquals(abstractTypes, other.abstractTypes) &&
        maxDepth == other.maxDepth;
  }

  @override
  int get hashCode => Object.hash(
        Object.hashAllUnordered(concreteTypes),
        Object.hashAllUnordered(abstractTypes),
        maxDepth,
      );
}

bool _setEquals(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);
