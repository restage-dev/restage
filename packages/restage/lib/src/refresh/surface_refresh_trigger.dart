/// Ambient live-refresh mechanisms a mounted surface may opt into.
///
/// Live refresh is off by default. The effective set for a surface resolves
/// most-specific-wins: the widget-level override, else the per-surface
/// override configured on `Restage.configure(liveRefreshOverrides:)`, else
/// the app-global `liveRefresh` set, else empty. Whichever level resolves is
/// used verbatim — sets are never merged across levels.
///
/// The set governs only the ambient mechanisms. A fresh mount always fetches
/// the active version (core delivery), and an explicit reload call always
/// runs — neither is gated here.
enum SurfaceRefreshTrigger {
  /// Re-check the surface's active version when the app returns to the
  /// foreground, and apply the new content if it changed (subject to the
  /// swap-safety gate).
  appResume,

  /// Hold a lightweight update subscription while the surface is on screen
  /// and the app is foregrounded, applying new publishes as they happen
  /// (subject to the swap-safety gate).
  updateChannel,
}
