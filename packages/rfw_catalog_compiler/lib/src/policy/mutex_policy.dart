// packages/rfw_catalog_compiler/lib/src/policy/mutex_policy.dart
import 'package:meta/meta.dart';

/// Mutually-exclusive property groups, keyed by widget flutterType.
///
/// Each value is a list of groups; each group is a list of property
/// names on that widget that must not all be set together.
@immutable
final class MutexPolicy {
  /// Creates a mutex policy with the supplied rules map.
  const MutexPolicy({required this.rules});

  /// Per-widget mutex groups; keyed by widget flutterType.
  final Map<String, List<List<String>>> rules;

  /// Returns a new policy that merges this policy's rules with [rules].
  MutexPolicy extend({
    Map<String, List<List<String>>> rules = const {},
  }) {
    return MutexPolicy(
      rules: {
        ...this.rules,
        for (final entry in rules.entries)
          entry.key: [...?this.rules[entry.key], ...entry.value],
      },
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! MutexPolicy) return false;
    if (rules.length != other.rules.length) return false;
    for (final entry in rules.entries) {
      final theirs = other.rules[entry.key];
      if (theirs == null) return false;
      if (entry.value.length != theirs.length) return false;
      for (var i = 0; i < entry.value.length; i++) {
        final a = entry.value[i];
        final b = theirs[i];
        if (a.length != b.length) return false;
        for (var j = 0; j < a.length; j++) {
          if (a[j] != b[j]) return false;
        }
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAllUnordered(
        rules.entries.map(
          (e) => Object.hash(
            e.key,
            Object.hashAllUnordered(
              e.value.map(Object.hashAll),
            ),
          ),
        ),
      );
}
