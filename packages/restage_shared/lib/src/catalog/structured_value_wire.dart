/// Key for the ordered `copyWith` override maps of a structured value.
///
/// The containing map holds the base value. Each override map holds flat
/// native fields, with missing or null fields retaining the previous value
/// through native `copyWith` semantics. A missing or null list applies no
/// overrides. Nested copy lists, malformed layer structures, and lists over
/// [kMaxStructuredCopyWithLayers] invalidate the entire value.
const String kStructuredCopyWithKey = 'copyWith';

/// Maximum copy layers, and maximum nesting of composed values, matching the
/// compiler's collection limit.
const int kMaxStructuredCopyWithLayers = 1000;

/// Marks an icon theme built by `IconThemeData.fallback()`.
const String kIconThemeDataFallbackKey = 'fallback';

/// Holds the `a`, `b` and `t` arguments of an `IconThemeData.lerp` value.
const String kIconThemeDataLerpKey = 'lerp';
