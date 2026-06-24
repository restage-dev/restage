import 'package:restage_core/registry.dart' show kCoreCatalogContentVersion;
import 'package:restage_cupertino/registry.dart'
    show kCupertinoCatalogContentVersion;
import 'package:restage_material/registry.dart'
    show kMaterialCatalogContentVersion;

/// The built-in catalog capability this SDK build can render.
///
/// Replaces the hand-set capability ceiling: [currentVersion] is the maximum
/// content version across the three built-in catalog libraries (core, material,
/// cupertino), single-sourced from the committed catalogs at SDK build via the
/// per-library generated constants. A delivered surface whose required built-in
/// floor exceeds this value needs a newer SDK than the installed one, so the
/// resolvers reject it before render (fail-closed) rather than rendering a
/// surface they cannot faithfully display.
///
/// Each per-library constant is generated from the committed catalog and locked
/// (by test) against the catalog's max widget `sinceVersion`, so this value
/// cannot drift from the catalog it summarizes.
abstract final class RestageBuiltInCatalogCapabilities {
  RestageBuiltInCatalogCapabilities._();

  /// The installed built-in catalog content version (the maximum over the three
  /// built-in libraries). A compile-time constant — each per-library version is
  /// a `const` generated from the committed catalog.
  static const int currentVersion =
      kCoreCatalogContentVersion >= kMaterialCatalogContentVersion
          ? (kCoreCatalogContentVersion >= kCupertinoCatalogContentVersion
              ? kCoreCatalogContentVersion
              : kCupertinoCatalogContentVersion)
          : (kMaterialCatalogContentVersion >= kCupertinoCatalogContentVersion
              ? kMaterialCatalogContentVersion
              : kCupertinoCatalogContentVersion);
}
