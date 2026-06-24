// packages/rfw_catalog_compiler/lib/src/policy/denylist_policy.dart
import 'package:meta/meta.dart';

/// Type-, type-suffix-, widget-, and per-class-property exclusions.
///
/// All four collections are exact-match except [typeSuffixes], which
/// matches Dart type display names ending with one of the listed
/// suffixes. The filter consults each category in order and returns
/// the first matching reason.
@immutable
final class DenylistPolicy {
  /// Creates a denylist policy with all four exclusion collections.
  const DenylistPolicy({
    required this.types,
    required this.typeSuffixes,
    required this.widgets,
    required this.properties,
  });

  /// Exact-match Dart type names (`'TextEditingController'`, `'FocusNode'`,
  /// …) or library-qualified type identifiers
  /// (`'package:flutter/widgets.dart#BuildContext'`). Simple-name matches use
  /// the analyzer element name without nullability or generics.
  final Set<String> types;

  /// Suffix patterns (`'Controller'`, `'Node'`, …). Match against the
  /// analyzer element name without nullability or generics.
  final Set<String> typeSuffixes;

  /// Fully-qualified widget identifiers
  /// (`'package:flutter/src/widgets/navigator.dart#Navigator'`).
  final Set<String> widgets;

  /// Per-widget property exclusions, keyed by widget flutterType.
  /// Reserved for design-driven exclusions the type denylist does
  /// not cover. Widget-specific `excludeParams` entries in curation
  /// files handle these cases until they are promoted to the
  /// policy ledger.
  final Map<String, Set<String>> properties;

  /// Returns a new policy whose collections are the union of this
  /// policy's collections and the supplied additions.
  DenylistPolicy extend({
    Set<String> types = const {},
    Set<String> typeSuffixes = const {},
    Set<String> widgets = const {},
    Map<String, Set<String>> properties = const {},
  }) {
    return DenylistPolicy(
      types: {...this.types, ...types},
      typeSuffixes: {...this.typeSuffixes, ...typeSuffixes},
      widgets: {...this.widgets, ...widgets},
      properties: {
        ...this.properties,
        for (final entry in properties.entries)
          entry.key: {...?this.properties[entry.key], ...entry.value},
      },
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DenylistPolicy &&
        _setEquals(types, other.types) &&
        _setEquals(typeSuffixes, other.typeSuffixes) &&
        _setEquals(widgets, other.widgets) &&
        _propertyMapEquals(properties, other.properties);
  }

  @override
  int get hashCode => Object.hash(
        Object.hashAllUnordered(types),
        Object.hashAllUnordered(typeSuffixes),
        Object.hashAllUnordered(widgets),
        Object.hashAllUnordered(
          properties.entries.map(
            (e) => Object.hash(e.key, Object.hashAllUnordered(e.value)),
          ),
        ),
      );
}

bool _setEquals(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

bool _propertyMapEquals(
  Map<String, Set<String>> a,
  Map<String, Set<String>> b,
) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    final other = b[entry.key];
    if (other == null) return false;
    if (!_setEquals(entry.value, other)) return false;
  }
  return true;
}

/// A type predicate's verdict. Null means "allowed". A non-null value
/// names which category of the [DenylistPolicy] matched and carries
/// a human-readable reason for the audit trail.
@immutable
final class DenylistMatch {
  /// Creates a denylist match result.
  const DenylistMatch({
    required this.policy,
    required this.reason,
    this.target,
  });

  /// Which sub-category fired
  /// (`'denylist.types'`, `'denylist.typeSuffixes'`,
  /// `'denylist.widgets'`, `'denylist.properties'`).
  final String policy;

  /// Audit-trail reason (e.g.
  /// `'type denylisted: TextEditingController'`).
  final String reason;

  /// Affected target (type display name, FQN, or property name).
  final String? target;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DenylistMatch &&
          other.policy == policy &&
          other.reason == reason &&
          other.target == target);

  @override
  int get hashCode => Object.hash(policy, reason, target);
}
