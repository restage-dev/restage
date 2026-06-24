/// Coarse grouping of a property's purpose. Drives editor inspector
/// affordances (which section a property appears under, how it's
/// foregrounded) and downstream filtering.
enum PropertyCategory {
  /// Arranges the widget in space (alignment, padding, sizing).
  layout,

  /// Visual appearance (color, typography, decoration).
  style,

  /// Interaction handlers and behavior toggles.
  behavior,

  /// Accessibility metadata (semantics labels, hints).
  accessibility,

  /// Data inputs (text, image source, dataset bindings).
  data,
}

/// Editor priority for a property. The editor surfaces `primary` first,
/// `common` next, and tucks `advanced` behind a disclosure.
enum PropertyPriority {
  /// Most important property on the widget (typically required, or the
  /// one that defines the widget's identity).
  primary,

  /// Frequently used; visible in the inspector's first surface.
  common,

  /// Tucked behind an "advanced" affordance.
  advanced,
}
