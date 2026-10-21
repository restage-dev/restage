/// The minimum client capability a surface needs once it uses delivered icon
/// fonts, screen-local values, per-item taps or answers on any flow.
const int kSurfaceFeatureClientFloor = 9;

/// The minimum client capability for widget lists grouped by conditional loops.
const int kGroupedWidgetListClientFloor = 10;

/// The minimum client capability for text joined from parts in a string slot.
const int kJoinedStringClientFloor = 16;

/// The minimum client capability for flow host-action results matched by
/// `always` or `matches` predicates.
const int kActionResultMatchClientFloor = 16;
