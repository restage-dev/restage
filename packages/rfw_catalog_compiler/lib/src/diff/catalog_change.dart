import 'package:meta/meta.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart';

/// Direction of a `required`-flag flip on a property or structured field.
@experimental
enum RequiredFlagDirection {
  /// `required: true` → `required: false`. Additive — blobs authored
  /// against the prior catalog still decode.
  loosened,

  /// `required: false` → `required: true`. Breaking — blobs that lack the
  /// property now fail to decode.
  tightened,
}

/// One detected per-entry change between two canonical catalog versions.
///
/// Produced by `diffCatalogs` and consumed by `classifyCatalogChange`. The
/// hierarchy is `sealed` so the classifier switches over it exhaustively
/// — a new change shape forces a classifier update at compile time rather
/// than falling through to a silent default.
@immutable
@experimental
sealed class CatalogChange {
  /// Creates a catalog change affecting the entry referenced by [affected].
  const CatalogChange({required this.kind, required this.affected});

  /// Wire-ID kind of the affected entry.
  final WireIdKind kind;

  /// `(library, wireId)` reference to the affected entry.
  final WireIdRef affected;

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is CatalogChange &&
      other.kind == kind &&
      other.affected == affected;

  @override
  int get hashCode => Object.hash(runtimeType, kind, affected);
}

/// A new entry appeared in the new catalog version. Additive — no existing
/// blob references it.
@experimental
final class EntryAdded extends CatalogChange {
  /// Creates an entry-added change.
  const EntryAdded({required super.kind, required super.affected});
}

/// An entry present in the old version is absent from the new version.
/// Breaking — blobs referencing the wire ID no longer resolve.
@experimental
final class EntryRemoved extends CatalogChange {
  /// Creates an entry-removed change.
  const EntryRemoved({required super.kind, required super.affected});
}

/// An entry's advisory label (display name, source path, or variant
/// accessor) shifted while its wire ID stayed stable. Free under wire IDs.
@experimental
final class EntryRenamed extends CatalogChange {
  /// Creates an entry-renamed change.
  const EntryRenamed({required super.kind, required super.affected});
}

/// An entry gained a catalog-lifecycle deprecation — `deprecated.catalog`
/// is present in the new version and absent in the old. Additive — blobs
/// continue to resolve; the editor warns.
@experimental
final class EntryDeprecated extends CatalogChange {
  /// Creates an entry-deprecated change.
  const EntryDeprecated({required super.kind, required super.affected});
}

/// An entry gained a successor via a `replace` event — its
/// `deprecated.catalog.replaceWith` is present in the new version.
/// Forwarding — the decoder remaps old references to [successor].
@experimental
final class EntryReplaced extends CatalogChange {
  /// Creates an entry-replaced change forwarding to [successor].
  const EntryReplaced({
    required super.kind,
    required super.affected,
    required this.successor,
    this.transitionId,
  });

  /// The successor entry old references forward to.
  final WireIdRef successor;

  /// Shared transition ID when the replace participates in a multi-event
  /// transition (deprecate + alloc + replace); `null` otherwise.
  final String? transitionId;

  @override
  bool operator ==(Object other) =>
      super == other &&
      other is EntryReplaced &&
      other.successor == successor &&
      other.transitionId == transitionId;

  @override
  int get hashCode => Object.hash(super.hashCode, successor, transitionId);
}

/// A property's or structured field's catalog [PropertyType] changed.
/// Always `kind == WireIdKind.property`.
@experimental
final class PropertyTypeChanged extends CatalogChange {
  /// Creates a property-type change from [from] to [to].
  const PropertyTypeChanged({
    required super.affected,
    required this.from,
    required this.to,
  }) : super(kind: WireIdKind.property);

  /// The property type in the old catalog version.
  final PropertyType from;

  /// The property type in the new catalog version.
  final PropertyType to;

  @override
  bool operator ==(Object other) =>
      super == other &&
      other is PropertyTypeChanged &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(super.hashCode, from, to);
}

/// A property's or structured field's `required` flag flipped.
@experimental
final class RequiredFlagChanged extends CatalogChange {
  /// Creates a required-flag change in [direction].
  const RequiredFlagChanged({
    required super.affected,
    required this.direction,
  }) : super(kind: WireIdKind.property);

  /// Whether the flag was [RequiredFlagDirection.loosened] or
  /// [RequiredFlagDirection.tightened].
  final RequiredFlagDirection direction;

  @override
  bool operator ==(Object other) =>
      super == other &&
      other is RequiredFlagChanged &&
      other.direction == direction;

  @override
  int get hashCode => Object.hash(super.hashCode, direction);
}

/// A property's or structured field's `defaultSource` changed — including a
/// `null` ↔ non-`null` transition or a change of `DefaultValueSourceKind`.
/// Additive — blobs carrying an explicit value are unaffected.
@experimental
final class PropertyDefaultChanged extends CatalogChange {
  /// Creates a property-default change.
  const PropertyDefaultChanged({required super.affected})
      : super(kind: WireIdKind.property);
}

/// A property's editor metadata (`category` / `priority`) changed.
/// Additive — editor-surface metadata only.
@experimental
final class PropertyMetadataChanged extends CatalogChange {
  /// Creates a property-metadata change.
  const PropertyMetadataChanged({required super.affected})
      : super(kind: WireIdKind.property);
}

/// A property's `synthetic` codegen strategy changed. Breaking — the
/// decoder semantics for the slot shift.
@experimental
final class SyntheticStrategyChanged extends CatalogChange {
  /// Creates a synthetic-strategy change.
  const SyntheticStrategyChanged({required super.affected})
      : super(kind: WireIdKind.property);
}

/// A widget's `childrenSlot` changed (none ↔ single ↔ list). Breaking — a
/// structural blob change is required.
@experimental
final class WidgetChildrenSlotChanged extends CatalogChange {
  /// Creates a children-slot change from [from] to [to].
  const WidgetChildrenSlotChanged({
    required super.affected,
    required this.from,
    required this.to,
  }) : super(kind: WireIdKind.widget);

  /// The children slot in the old catalog version.
  final ChildrenSlot from;

  /// The children slot in the new catalog version.
  final ChildrenSlot to;

  @override
  bool operator ==(Object other) =>
      super == other &&
      other is WidgetChildrenSlotChanged &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(super.hashCode, from, to);
}

/// A member structured type was added to a union. Additive — a new option;
/// existing blobs are unaffected.
@experimental
final class UnionMemberAdded extends CatalogChange {
  /// Creates a union-member-added change for [member].
  const UnionMemberAdded({required super.affected, required this.member})
      : super(kind: WireIdKind.union);

  /// The structured member added to the union.
  final WireIdRef member;

  @override
  bool operator ==(Object other) =>
      super == other && other is UnionMemberAdded && other.member == member;

  @override
  int get hashCode => Object.hash(super.hashCode, member);
}

/// A member structured type was removed from a union. Breaking — blobs
/// carrying that discriminator value fail.
@experimental
final class UnionMemberRemoved extends CatalogChange {
  /// Creates a union-member-removed change for [member].
  const UnionMemberRemoved({required super.affected, required this.member})
      : super(kind: WireIdKind.union);

  /// The structured member removed from the union.
  final WireIdRef member;

  @override
  bool operator ==(Object other) =>
      super == other && other is UnionMemberRemoved && other.member == member;

  @override
  int get hashCode => Object.hash(super.hashCode, member);
}

/// A union's discriminator field changed. Breaking — the on-wire format
/// for the union slot shifts.
@experimental
final class UnionDiscriminatorChanged extends CatalogChange {
  /// Creates a discriminator change.
  const UnionDiscriminatorChanged({required super.affected})
      : super(kind: WireIdKind.union);
}

/// A factory variant's argument shape changed — its `sourceKind` or
/// arg-to-field `argMappings` differ. Breaking — the decoder semantics for
/// the variant shift.
@experimental
final class VariantArgumentsChanged extends CatalogChange {
  /// Creates a variant-arguments change.
  const VariantArgumentsChanged({required super.affected})
      : super(kind: WireIdKind.variant);
}

/// A design token's `resolver` (theme-binding path) changed. Additive —
/// existing blobs see the new resolved value at render time.
@experimental
final class TokenResolverChanged extends CatalogChange {
  /// Creates a token-resolver change.
  const TokenResolverChanged({required super.affected})
      : super(kind: WireIdKind.designToken);
}

/// A design token's `literalFallback` changed. Additive — same render-time
/// resolution contract as a resolver change.
@experimental
final class TokenFallbackChanged extends CatalogChange {
  /// Creates a token-fallback change.
  const TokenFallbackChanged({required super.affected})
      : super(kind: WireIdKind.designToken);
}

/// A design token's [DesignTokenType] changed. Breaking — properties
/// referencing the token may have type-mismatched defaults.
@experimental
final class TokenTypeChanged extends CatalogChange {
  /// Creates a token-type change from [from] to [to].
  const TokenTypeChanged({
    required super.affected,
    required this.from,
    required this.to,
  }) : super(kind: WireIdKind.designToken);

  /// The token type in the old catalog version.
  final DesignTokenType from;

  /// The token type in the new catalog version.
  final DesignTokenType to;

  @override
  bool operator ==(Object other) =>
      super == other &&
      other is TokenTypeChanged &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(super.hashCode, from, to);
}
