// packages/rfw_catalog_compiler/lib/src/policy/union_registry.dart
import 'package:meta/meta.dart';

/// Built-in + customer-supplied abstract-type → concrete-subtype
/// mappings (Gradient → [LinearGradient, …]).
@immutable
final class UnionRegistry {
  /// Creates a union registry from already-immutable seed entries.
  ///
  /// This constructor does not copy [entries]; callers passing a mutable
  /// map should use [UnionRegistry.of] instead, which defensively copies.
  /// The built-in seed map is a compile-time constant and is therefore
  /// already deeply immutable.
  const UnionRegistry({required this.entries});

  /// Creates a union registry, defensively copying [entries] into an
  /// unmodifiable map so the registry cannot be mutated through a
  /// reference the caller retains.
  UnionRegistry.of(Map<String, UnionRegistryEntry> entries)
      : entries = Map<String, UnionRegistryEntry>.unmodifiable(entries);

  /// Abstract-type FQN → registry entry.
  final Map<String, UnionRegistryEntry> entries;

  /// Returns the registry entry whose abstract-type FQN equals [fqn], or
  /// null when no abstract base is registered under that name.
  UnionRegistryEntry? lookup(String fqn) => entries[fqn];

  /// Returns a new registry that merges this registry's entries with
  /// [entries]. The merged registry holds an unmodifiable copy.
  UnionRegistry extend({
    Map<String, UnionRegistryEntry> entries = const {},
  }) =>
      UnionRegistry.of({...this.entries, ...entries});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UnionRegistry && _mapEquals(entries, other.entries));

  @override
  int get hashCode => Object.hashAllUnordered(
        entries.entries.map((e) => Object.hash(e.key, e.value)),
      );
}

/// One entry in a [UnionRegistry], describing an abstract type and its
/// known concrete subtypes.
@immutable
final class UnionRegistryEntry {
  /// Creates a union registry entry from an already-immutable member list.
  ///
  /// This constructor does not copy [members]; callers passing a mutable
  /// list should use [UnionRegistryEntry.of] instead, which defensively
  /// copies and rejects duplicate members. The built-in seed entries use
  /// compile-time-constant member lists and are therefore already
  /// deeply immutable.
  const UnionRegistryEntry({
    required this.abstractType,
    required this.members,
    required this.discriminatorField,
    required this.description,
  });

  /// Creates a union registry entry, defensively copying [members] into an
  /// unmodifiable list. Throws [ArgumentError] when [members] contains a
  /// duplicate, since a discriminated union cannot carry the same concrete
  /// member twice.
  UnionRegistryEntry.of({
    required this.abstractType,
    required List<String> members,
    required this.discriminatorField,
    required this.description,
  }) : members = List<String>.unmodifiable(members) {
    if (members.toSet().length != members.length) {
      throw ArgumentError.value(
        members,
        'members',
        'union registry entry members must be unique',
      );
    }
  }

  /// `'package:flutter/src/painting/gradient.dart#Gradient'`.
  final String abstractType;

  /// Initial concrete subclasses, each as a fully-qualified
  /// `<library-identifier>#<ClassName>` string.
  final List<String> members;

  /// On-wire discriminator (default `'_s'`).
  final String discriminatorField;

  /// A concise human-readable description of this union type and its variants.
  final String description;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UnionRegistryEntry &&
          other.abstractType == abstractType &&
          other.discriminatorField == discriminatorField &&
          other.description == description &&
          _listEquals(members, other.members));

  @override
  int get hashCode => Object.hash(
        abstractType,
        discriminatorField,
        description,
        Object.hashAll(members),
      );
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _mapEquals(
  Map<String, UnionRegistryEntry> a,
  Map<String, UnionRegistryEntry> b,
) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (entry.value != b[entry.key]) return false;
  }
  return true;
}
