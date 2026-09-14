import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/widgets.dart' show IconData;
import 'package:restage_core/restage_core.dart'
    show InstalledIconTable, RestageIconTable;
import 'package:restage_shared/restage_shared.dart'
    show InstalledCapability, WidgetLibrary, WidgetVocabulary;

import 'builtin_catalog_capabilities.dart';
import 'library_runtime_registry.dart';
import 'restage_widget_libraries.dart';

/// The exact built-in widgets and icons this app installed, in the form the
/// delivery service reads.
///
/// Widget names are namespaced by the library that carries them; icon code
/// points are keyed by font family. The stores retain caller-owned maps, so
/// every capture checks their current keys. An unchanged vocabulary reuses its
/// canonical snapshot without repeating sorting and freezing.
WidgetVocabulary installedWidgetVocabulary() {
  final libraries = InstalledWidgetLibraries.current;
  final icons = InstalledIconTable.current;
  final widgetNames = <String>{
    for (final name in libraries.core.keys)
      WidgetVocabulary.qualifiedName(WidgetLibrary.core.namespace, name),
    for (final name in libraries.material.keys)
      WidgetVocabulary.qualifiedName(WidgetLibrary.material.namespace, name),
    for (final name in libraries.cupertino.keys)
      WidgetVocabulary.qualifiedName(WidgetLibrary.cupertino.namespace, name),
  };
  final codePoints = _installedCodePoints(icons);
  final cached = _cached;
  if (cached != null &&
      setEquals(cached.widgetNames, widgetNames) &&
      cached.iconCodePoints.length == codePoints.length &&
      codePoints.entries.every(
        (entry) => setEquals(cached.iconCodePoints[entry.key], entry.value),
      )) {
    return cached;
  }
  return _cached = WidgetVocabulary(
    widgetNames: widgetNames,
    iconCodePoints: codePoints,
  );
}

/// The code points [icons] can render per font family, mirroring and
/// non-mirroring together — the vocabulary reports what the app carries, and
/// the two halves of a shared code point are the same point on the wire.
Map<String, Set<int>> _installedCodePoints(RestageIconTable icons) {
  final codePoints = <String, Set<int>>{};
  for (final families in <Map<String, Map<int, IconData>>>[
    icons.families,
    icons.mirrored,
  ]) {
    for (final family in families.entries) {
      if (family.value.isEmpty) continue;
      (codePoints[family.key] ??= <int>{}).addAll(family.value.keys);
    }
  }
  return codePoints;
}

/// The capability contract this build presents to the delivery service: the
/// built-in catalog version, the registered custom libraries, and the exact
/// widgets and icons installed.
InstalledCapability currentInstalledCapability() => InstalledCapability(
      builtInCatalogVersion: RestageBuiltInCatalogCapabilities.currentVersion,
      installedLibraries: LibraryRuntimeRegistry.installedSnapshot(),
      vocabulary: installedWidgetVocabulary(),
    );

WidgetVocabulary? _cached;
