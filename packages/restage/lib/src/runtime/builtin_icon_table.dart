import 'package:flutter/widgets.dart' show IconData;
import 'package:restage_core/restage_core.dart'
    show InstalledIconTable, RestageIconTable;
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
      if (includeMaterial) RestageIconTable.materialIconsFamily: _materialIcons,
      if (includeCupertino)
        RestageIconTable.cupertinoIconsFamily: _cupertinoIcons,
    },
    // ignore: prefer_const_literals_to_create_immutables
    mirrored: <String, Map<int, IconData>>{
      if (includeMaterial)
        RestageIconTable.materialIconsFamily: _mirroredMaterialIcons,
      if (includeCupertino)
        RestageIconTable.cupertinoIconsFamily: _mirroredCupertinoIcons,
    },
  );
}

final _materialIcons = createMaterialIconTable();
final _cupertinoIcons = createCupertinoIconTable();
final _mirroredMaterialIcons = createMirroredMaterialIconTable();
final _mirroredCupertinoIcons = createMirroredCupertinoIconTable();

/// Adds built-in glyphs while retaining identical immutable family maps.
void addBuiltInIconTable() {
  final table = builtInIconTable();
  final installed = InstalledIconTable.current;
  table.families.removeWhere(
    (family, icons) => identical(installed.families[family], icons),
  );
  table.mirrored.removeWhere(
    (family, icons) => identical(installed.mirrored[family], icons),
  );
  InstalledIconTable.add(table, explicitSelection: true);
}
