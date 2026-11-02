import 'package:a2ui_core/a2ui_core.dart';
import 'package:restage_a2ui/restage_a2ui.dart';
import 'package:restage_a2ui/restage_a2ui.dart' as restage;

RestageA2uiPreRenderCheck simple(Catalog catalog) =>
    RestageA2uiPreRenderCheck(catalog: catalog);

restage.RestageA2uiPreRenderCheck expression(
  Map<String, Catalog> catalogs,
  String name,
  restage.A2uiInstalledCapability installed,
) => restage.RestageA2uiPreRenderCheck(
  catalog: catalogs[name]!,
  installed: installed,
);
