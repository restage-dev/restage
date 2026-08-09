/// Sub-grouping of widgets within a library. Used by the editor's
/// component palette and inspector.
enum WidgetCategory {
  /// Widgets that arrange other widgets in space (rows, columns, stacks).
  layout,

  /// Widgets that capture user input (buttons, text fields).
  input,

  /// Widgets that produce non-interactive visual output (text, image).
  decoration,

  /// Action widgets — call-to-action buttons and the interactive
  /// composites a surface is built around (product cards, sheets, paged
  /// selectors). Surface-general: an action is a "Continue" / "Submit" /
  /// "Subscribe" tap on any surface, not only a paywall.
  action,
}

/// How many children a widget accepts.
enum ChildrenSlot {
  /// Widget has no children (e.g. `Text`, `Image`).
  none,

  /// Widget accepts a single `child` widget (e.g. `Padding`, `Container`).
  single,

  /// Widget accepts a list of children (e.g. `Column`, `Row`).
  list,
}
