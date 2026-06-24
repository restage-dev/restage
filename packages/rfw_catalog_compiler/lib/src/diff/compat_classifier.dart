import 'package:meta/meta.dart';
import 'package:rfw_catalog_compiler/src/diff/catalog_change.dart';

/// The four-way compatibility classification for a catalog change.
///
/// Determines whether — and how — a change to a catalog entry affects
/// paywall blobs authored against the prior catalog version. The diff tool
/// emits a `CompatRule` for [forwarding] and [breaking] changes only;
/// [free] and [additive] changes need no decode-time mediation.
@experimental
enum CompatClassification {
  /// Zero-cost change: no migration, no wire-compat entry. Renames are
  /// free — wire identity is unchanged.
  free,

  /// Existing consumers ignore the addition; no migration is needed.
  additive,

  /// Existing references resolve through a forwarding entry; migration is
  /// automatic at blob decode time.
  forwarding,

  /// Existing references fail to resolve; migration is required, or the
  /// entry renders an error placeholder.
  breaking,
}

/// Classifies a detected [CatalogChange] per the compatibility taxonomy.
///
/// The `switch` is exhaustive over the sealed [CatalogChange] hierarchy —
/// the analyzer rejects an unhandled subtype, so a new change shape cannot
/// reach production without an explicit classification rule. A
/// mis-classification (especially `breaking` as `additive`) silently
/// breaks shipped blobs, so each arm documents the rule it implements.
///
/// Infrastructure ahead of application: this classifier has no production
/// consumer yet (the emitted `CompatRule` type is production; the
/// diff/classifier logic that produces it is not wired in).
@experimental
CompatClassification classifyCatalogChange(CatalogChange change) {
  return switch (change) {
    // A new entry was added. No existing blob references it.
    EntryAdded() => CompatClassification.additive,
    // An entry was removed. Blobs referencing the wire ID fail to resolve.
    EntryRemoved() => CompatClassification.breaking,
    // Rename. Wire identity is unchanged; only a display label shifts.
    EntryRenamed() => CompatClassification.free,
    // Deprecate. Blobs continue to resolve; the editor warns.
    EntryDeprecated() => CompatClassification.additive,
    // Replace with a successor — the decoder remaps via a rule. Valid for
    // every wire-ID kind.
    EntryReplaced() => CompatClassification.forwarding,
    // A property / structured-field type change. Conservatively breaking:
    // a true widening is sub-`PropertyType` (e.g. EdgeInsets ↔
    // EdgeInsetsGeometry both map to `PropertyType.edgeInsets`) and never
    // surfaces as an observable change here.
    PropertyTypeChanged() => CompatClassification.breaking,
    // Required-flag flip. Loosening is additive; tightening makes blobs
    // that lack the property fail to decode.
    RequiredFlagChanged(:final direction) => switch (direction) {
        RequiredFlagDirection.loosened => CompatClassification.additive,
        RequiredFlagDirection.tightened => CompatClassification.breaking,
      },
    // Default-source change. Blobs with explicit values are unaffected;
    // blobs relying on the default see the new resolution.
    PropertyDefaultChanged() => CompatClassification.additive,
    // Category / priority change. Editor-surface metadata only.
    PropertyMetadataChanged() => CompatClassification.additive,
    // Synthetic-strategy change. The decoder semantics for the slot shift.
    SyntheticStrategyChanged() => CompatClassification.breaking,
    // Children-slot change. A structural blob change is required.
    WidgetChildrenSlotChanged() => CompatClassification.breaking,
    // A union gained a member. A new option; existing blobs unaffected.
    UnionMemberAdded() => CompatClassification.additive,
    // A union lost a member. Blobs with that discriminator value fail.
    UnionMemberRemoved() => CompatClassification.breaking,
    // Discriminator-field change. The on-wire union format shifts.
    UnionDiscriminatorChanged() => CompatClassification.breaking,
    // Variant argument-shape / argument-type change. The decoder
    // semantics for the variant shift.
    VariantArgumentsChanged() => CompatClassification.breaking,
    // Resolver-path change. Existing blobs see the new resolution.
    TokenResolverChanged() => CompatClassification.additive,
    // Literal-fallback change. Same render-time resolution contract as a
    // resolver change.
    TokenFallbackChanged() => CompatClassification.additive,
    // Token-type change. Properties referencing the token may have
    // type-mismatched defaults.
    TokenTypeChanged() => CompatClassification.breaking,
  };
}
