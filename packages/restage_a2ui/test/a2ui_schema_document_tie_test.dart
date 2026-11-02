import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:restage_a2ui/restage_a2ui.dart';

import 'generated/interactive_catalog.g.dart' as interactive;
import 'generated/rich_shape_catalog.g.dart' as rich;

/// Pins the separate capability stamp to the emitted producer document.
void main() {
  _tieGroup(
    label: 'rich-shape',
    catalog: rich.buildRestageCatalog(),
    documentPath: 'test/generated/rich_shape_catalog.a2ui.json',
    capability: rich.restageA2uiCapability,
  );
  _tieGroup(
    label: 'interactive',
    catalog: interactive.buildRestageCatalog(),
    documentPath: 'test/generated/interactive_catalog.a2ui.json',
    capability: interactive.restageA2uiCapability,
  );
}

void _tieGroup({
  required String label,
  required CatalogImplementation catalog,
  required String documentPath,
  required RestageA2uiCapability capability,
}) {
  test(
    '$label: generated const capability exactly matches the A2UI document',
    () {
      final document =
          jsonDecode(File(documentPath).readAsStringSync())
              as Map<String, Object?>;
      final a2ui = (document['a2uiCatalog']! as Map).cast<String, Object?>();
      final stamp = (document['restageCapability']! as Map)
          .cast<String, Object?>();

      expect(capability.schemaDialect, a2ui[r'$schema']);
      expect(capability.a2uiProtocolVersion, a2ui['protocolVersion']);
      expect(capability.schemaVersion, a2ui['protocolVersion']);
      expect(capability.catalogId, a2ui['catalogId']);
      expect(
        capability.fingerprint,
        capability.catalogId.substring('restage:catalog/'.length),
      );
      expect(capability.catalogContentVersion, stamp['catalogContentVersion']);
      expect([
        for (final library in capability.availableLibraries)
          {'namespace': library.namespace, 'version': library.version},
      ], stamp['availableLibraries']);
      expect(capability.perItemSinceVersion, stamp['perItemSinceVersion']);
    },
  );
}
