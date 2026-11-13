import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:restage_a2ui/restage_a2ui.dart';
import 'package:restage_shared/restage_shared.dart'
    show CapabilityManifest, LibraryRequirement;

/// End-to-end emit↔check contract reconciliation.
///
/// The toolchain emits a catalog-side capability stamp; the app-side check
/// consumes it (via [A2uiInstalledCapability.fromStampJson]) as the available
/// side, against a sidecar's required [CapabilityManifest]. These two shapes
/// are produced by different packages that cannot import each other (the
/// toolchain is a2ui_flutter-free; this package owns a2ui_flutter). This test pins the seam
/// by reading the toolchain's REAL committed stamp output and proving the
/// check reconciles with it — so a field rename on either side fails here.
///
/// The fixture is the toolchain's golden A2UI catalog (drift-guarded in the
/// emitter package); we read only its `restageCapability` block + component
/// names — the contract surface, not the a2ui_flutter-specific schema body.
const _emittedCatalogPath =
    '../restage_codegen/test/a2ui/golden/sample_catalog.a2ui.json';

CatalogImplementation _catalogOf(List<String> names) => CatalogImplementation(
  id: 'cache-test',
  protocolVersion: A2uiProtocolVersion.v1_0,
  components: [
    for (final name in names)
      ComponentImplementation(
        name: name,
        schema: S.object(properties: const {}),
        builder: (_, _, _, _) => const SizedBox.shrink(),
      ),
  ],
);

Map<String, Object?> _rawPayload(List<String> types) => {
  'version': '1.0',
  'createSurface': {
    'catalogId': 'cache-test',
    'surfaceId': 's',
    'components': [
      for (final (i, t) in types.indexed)
        {'id': i == 0 ? 'root' : t, 'component': t},
    ],
  },
};

Map<String, Object?> _sidecar(
  List<String> types,
  CapabilityManifest manifest,
) => RestageA2uiSidecar(
  capability: manifest,
  perItemSinceVersion: const {},
  a2ui: _rawPayload(types),
).toJson();

void main() {
  // The toolchain's real emitted catalog document.
  final emitted =
      jsonDecode(File(_emittedCatalogPath).readAsStringSync())
          as Map<String, Object?>;
  final stamp = emitted['restageCapability']! as Map<String, Object?>;
  final componentNames =
      (emitted['a2uiCatalog']! as Map<String, Object?>)['components']!
          as Map<String, Object?>;

  group('emit→check reconciliation (real toolchain stamp)', () {
    test('the check consumes the emitted catalog stamp shape', () {
      final installed = A2uiInstalledCapability.fromStampJson(stamp);
      // The toolchain wrote catalogContentVersion + availableLibraries with
      // these exact field names; fromStampJson reads them.
      expect(installed.catalogContentVersion, 2);
      expect(installed.availableLibraries.single.namespace, 'acme.widgets');
      expect(installed.availableLibraries.single.version, 3);
    });

    test('a payload within the emitted catalog renders end-to-end', () {
      final installed = A2uiInstalledCapability.fromStampJson(stamp);
      final check = RestageA2uiPreRenderCheck(
        catalogs: [_catalogOf(componentNames.keys.toList())],
        installed: installed,
      );
      // Requires exactly what the emitted catalog provides: built-in floor 2
      // and acme.widgets >= 3.
      final result = check.check(
        _sidecar(
          ['Text', 'Column'],
          CapabilityManifest(
            builtInFloor: 2,
            requiredLibraries: const [
              LibraryRequirement(namespace: 'acme.widgets', minVersion: 3),
            ],
          ),
        ),
      );
      expect(result, isA<A2uiRenderable>());
    });

    test('a built-in floor above the emitted version is rejected', () {
      final installed = A2uiInstalledCapability.fromStampJson(stamp);
      final check = RestageA2uiPreRenderCheck(
        catalogs: [_catalogOf(componentNames.keys.toList())],
        installed: installed,
      );
      final result = check.check(
        _sidecar([
          'Text',
        ], CapabilityManifest(builtInFloor: 3, requiredLibraries: const [])),
      );
      expect(result, isA<A2uiRejected>());
      expect((result as A2uiRejected).gap, contains('version 3'));
    });

    test('a library above the emitted version is rejected', () {
      final installed = A2uiInstalledCapability.fromStampJson(stamp);
      final check = RestageA2uiPreRenderCheck(
        catalogs: [_catalogOf(componentNames.keys.toList())],
        installed: installed,
      );
      final result = check.check(
        _sidecar(
          ['Text'],
          CapabilityManifest(
            builtInFloor: 1,
            requiredLibraries: const [
              LibraryRequirement(namespace: 'acme.widgets', minVersion: 4),
            ],
          ),
        ),
      );
      expect(result, isA<A2uiRejected>());
      expect((result as A2uiRejected).gap, contains('acme.widgets'));
    });

    test('a component absent from the emitted catalog is rejected', () {
      final installed = A2uiInstalledCapability.fromStampJson(stamp);
      final check = RestageA2uiPreRenderCheck(
        catalogs: [_catalogOf(componentNames.keys.toList())],
        installed: installed,
      );
      final result = check.check(_rawPayload(['Text', 'NotInCatalog']));
      expect(result, isA<A2uiRejected>());
      expect((result as A2uiRejected).diagnostic, contains('NotInCatalog'));
    });
  });
}
