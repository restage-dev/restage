/// The Dart type of a widget slot that Flutter narrows to a sized bar —
/// `Scaffold.appBar` and its kin. Named on `PropertyEntry.widgetType`.
const String kPreferredSizeWidgetType = 'PreferredSizeWidget';

/// The synthetic strategy carrying the height of a
/// [kPreferredSizeWidgetType] slot beside the slot itself.
const String kPreferredSizeHeightSyntheticStrategy = 'preferredSizeHeight';

/// The synthetic strategy that surfaces a `Size` argument as its height
/// alone, rebuilt as `Size.fromHeight(...)` at construction.
const String kSizeFromHeightSyntheticStrategy = 'sizeFromHeight';
