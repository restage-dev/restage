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

/// Names for events a widget can fire. Catalog `fires:` references these.
enum WidgetEventName {
  /// Fired when a tappable widget (button) is pressed.
  onPressed,

  /// Fired when a generic gesture-detector receives a tap.
  onTap,

  /// Fired when a generic gesture-detector receives a long-press.
  /// Same `VoidCallback?` shape as `onTap` — the native short-tap
  /// vs. press-and-hold convention.
  onLongPress,

  /// Fired when a generic gesture-detector receives a double-tap.
  /// Same `VoidCallback?` shape as `onTap`.
  onDoubleTap,

  /// Fired when the value of an input widget changes.
  onChanged,

  /// Fired when an input widget submits a final value.
  onSubmit,

  /// Fired when a text input commits its value (e.g. user presses
  /// return). Distinct from `onSubmit` — this name matches Flutter's
  /// `TextField.onSubmitted` / `CupertinoTextField.onSubmitted`
  /// parameter so text-field curations can wire the typed
  /// `ValueChanged<String>` callback through the same path as
  /// `onChanged`.
  onSubmitted,

  /// Fired when a discrete-selection widget toggles its selected
  /// state within a group (e.g. filter / choice chips). Semantically
  /// distinct from `onChanged` — selection is a discrete pick within
  /// a group, not a value edit — even though the typed callback
  /// shape (`ValueChanged<bool>`) happens to coincide. Name matches
  /// Flutter's `FilterChip.onSelected` / `ChoiceChip.onSelected` so
  /// chip curations wire the callback through the same path as
  /// `onChanged`.
  onSelected,

  /// Fired when an expansion-style widget transitions between
  /// expanded and collapsed (e.g. `ExpansionTile`). Semantically
  /// distinct from `onChanged` — an expand/collapse transition is a
  /// layout-state change, not a value edit. Name matches Flutter's
  /// `ExpansionTile.onExpansionChanged` so the curation wires the
  /// `ValueChanged<bool>` callback through the same path as
  /// `onChanged`.
  onExpansionChanged,

  /// Fired when a multi-page surface settles on a new page index
  /// (e.g. `PageView` / `RestagePager`). Semantically distinct from
  /// `onChanged` — page navigation is a position change in a paged
  /// layout, not a value edit. Name matches Flutter's
  /// `PageView.onPageChanged` so the curation wires the
  /// `ValueChanged<int>` callback through the same path as
  /// `onChanged`.
  onPageChanged,

  /// Fired when an implicit animation reaches its target value. Name
  /// matches Flutter's `ImplicitlyAnimatedWidget.onEnd` parameter and
  /// carries the same `VoidCallback?` shape as `onTap`.
  onEnd,

  /// Fired when the paywall is dismissed.
  onDismiss,

  /// Fired when a modal sheet within the surface is dismissed by a
  /// downward drag or a scrim tap (e.g. `RestageModalSheet`). Distinct
  /// from `onDismiss`: that is the *surface* (paywall) being dismissed,
  /// whereas this is a *sheet within* the surface closing. Name matches
  /// the widget's `onSheetDismissed` parameter and carries the same
  /// `VoidCallback?` shape as `onTap`, wired through the same path.
  onSheetDismissed,
}
