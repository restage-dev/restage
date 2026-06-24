/// Stability tier for a catalog entry. Surfaces whether a widget,
/// structured type, union, or design token may change shape across
/// releases or carries a maintainer commitment to wire compatibility.
///
/// **Compatibility.** Additions to this enum are breaking changes for
/// downstream consumers that switch exhaustively on a [Stability]
/// value. Consumers that want forward compatibility should use a
/// `default` arm or treat unrecognized tiers as [volatile].
enum Stability {
  /// Default tier — the entry may change shape in any release. Consumers
  /// must not rely on its identity, fields, or members staying stable
  /// across catalog versions.
  volatile,

  /// Promoted tier — the entry has a published wire identity that
  /// cannot change without a major version bump.
  stable,
}
