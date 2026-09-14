import 'package:flutter/widgets.dart' show IconData;
import 'package:restage_core/restage_core.dart' show RestageIconTable;
import 'package:restage_cupertino/icon_table.dart';
import 'package:restage_material/icon_table.dart';

/// Builds the selected complete icon families, including mirrored glyphs.
///
/// Ordinary `Restage.configure()` uses this when no icon selection exists.
/// Each immutable inner map returns the original Flutter icon constants.
/// Both families default to included. Excluding a full family does not remove
/// icons already installed by the app or a generated surface.
/// Explicitly selected builds can use [RestageIconTable.fromFamilies] and
/// `Restage.configureWithInstalledCatalog()` to retain only their chosen icons.
///
/// Install it during app startup:
///
/// ```dart
/// void main() {
///   InstalledIconTable.install(builtInIconTable());
///   runApp(const MyApp());
/// }
/// ```
RestageIconTable builtInIconTable({
  bool includeMaterial = true,
  bool includeCupertino = true,
}) {
  // Not const, so the whole table enters a build only through a real call to
  // this function.
  // ignore: prefer_const_constructors
  return RestageIconTable.fromFamilies(
    families: // ignore: prefer_const_literals_to_create_immutables
        <String, Map<int, IconData>>{
      if (includeMaterial)
        RestageIconTable.materialIconsFamily: createMaterialIconTable(),
      if (includeCupertino)
        RestageIconTable.cupertinoIconsFamily: createCupertinoIconTable(),
    },
    // ignore: prefer_const_literals_to_create_immutables
    mirrored: <String, Map<int, IconData>>{
      if (includeMaterial)
        RestageIconTable.materialIconsFamily: createMirroredMaterialIconTable(),
      if (includeCupertino)
        RestageIconTable.cupertinoIconsFamily:
            createMirroredCupertinoIconTable(),
    },
  );
}
