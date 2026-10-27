import 'package:restage_shared/restage_shared.dart'
    show kFormattingExpressionClientFloor;
import 'package:restage_core/registry.dart' show kCoreCatalogContentVersion;
import 'package:restage_cupertino/registry.dart'
    show kCupertinoCatalogContentVersion;
import 'package:restage_material/registry.dart'
    show kMaterialCatalogContentVersion;

/// The built-in catalog capability this SDK build can render.
///
/// Combines installed native value operations with generated widget versions.
/// Resolvers refuse delivered surfaces above this version before rendering.
abstract final class RestageBuiltInCatalogCapabilities {
  RestageBuiltInCatalogCapabilities._();

  static const int _catalogVersion =
      kCoreCatalogContentVersion >= kMaterialCatalogContentVersion
          ? (kCoreCatalogContentVersion >= kCupertinoCatalogContentVersion
              ? kCoreCatalogContentVersion
              : kCupertinoCatalogContentVersion)
          : (kMaterialCatalogContentVersion >= kCupertinoCatalogContentVersion
              ? kMaterialCatalogContentVersion
              : kCupertinoCatalogContentVersion);

  /// Includes native expression operations in the installed capability line.
  static const int currentVersion =
      _catalogVersion >= kFormattingExpressionClientFloor
          ? _catalogVersion
          : kFormattingExpressionClientFloor;
}
