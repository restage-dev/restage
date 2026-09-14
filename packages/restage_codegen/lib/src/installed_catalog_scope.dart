/// What the generated `registerRestageWidgets()` installs.
enum InstalledCatalogScope {
  /// Complete built-in families by default, selectable during registration.
  whole,

  /// Only the widgets and icons this package draws in its own Dart, plus the
  /// catalog entries its compiled surfaces render.
  derived,
}

/// The builder option key that chooses the scope.
const String kInstalledCatalogOptionKey = 'catalog';

/// The option value naming [InstalledCatalogScope.whole].
const String kWholeCatalogOptionValue = 'full';

/// The option value naming [InstalledCatalogScope.derived].
const String kDerivedCatalogOptionValue = 'derived';

/// Reads the `catalog` option out of a builder's [config].
///
/// Absent or `full` enables full-family registration. Unknown values fail
/// the build rather than falling back to a default.
InstalledCatalogScope readInstalledCatalogScope(Map<String, dynamic> config) {
  final value = config[kInstalledCatalogOptionKey];
  if (value == null || value == kWholeCatalogOptionValue) {
    return InstalledCatalogScope.whole;
  }
  if (value == kDerivedCatalogOptionValue) return InstalledCatalogScope.derived;
  throw ArgumentError.value(
    value,
    kInstalledCatalogOptionKey,
    "Restage: the '$kInstalledCatalogOptionKey' option of the "
    'restage_codegen:user_factories builder accepts '
    "'$kWholeCatalogOptionValue' or '$kDerivedCatalogOptionValue'",
  );
}
