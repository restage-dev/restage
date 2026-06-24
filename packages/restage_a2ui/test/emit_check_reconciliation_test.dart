import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
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
/// toolchain is genui-free; this package owns genui). This test pins the seam
/// by reading the toolchain's REAL committed stamp output and proving the
/// check reconciles with it — so a field rename on either side fails here.
///
/// The fixture is the toolchain's golden A2UI catalog (drift-guarded in the
/// emitter package); we read only its `restageCapability` block + component
/// names — the contract surface, not the genui-specific schema body.
const _emittedCatalogPath =
    '../restage_codegen/test/a2ui/golden/sample_catalog.a2ui.json';

Catalog _catalogOf(List<String> names) => Catalog([
  for (final name in names)
    CatalogItem(
      name: name,
      dataSchema: S.object(properties: const {}),
      widgetBuilder: (_) => const SizedBox.shrink(),
    ),
]);

Map<String, Object?> _rawPayload(List<String> types) => {
  'version': 'v0.9',
  'updateComponents': {
    'surfaceId': 's',
    'components': [
      for (final t in types) {'id': t, 'component': t},
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
        catalog: _catalogOf(componentNames.keys.toList()),
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
        catalog: _catalogOf(componentNames.keys.toList()),
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
        catalog: _catalogOf(componentNames.keys.toList()),
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
        catalog: _catalogOf(componentNames.keys.toList()),
        installed: installed,
      );
      final result = check.check(_rawPayload(['Text', 'NotInCatalog']));
      expect(result, isA<A2uiRejected>());
      expect((result as A2uiRejected).diagnostic, contains('NotInCatalog'));
    });
  });
}
