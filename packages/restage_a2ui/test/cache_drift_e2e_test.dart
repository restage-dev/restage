import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:json_schema_builder/json_schema_builder.dart';
import 'package:restage_a2ui/restage_a2ui.dart';
import 'package:restage_shared/restage_shared.dart' show CapabilityManifest;

/// The cache-drift story, end to end through the public API.
///
/// An app caches the serializable Restage sidecar JSON. Later — possibly on a
/// newer or older binary — it replays the cached wrapper through the check
/// before handing the payload to a2ui_flutter. These cases demonstrate that the stamp
/// + the existence walk together catch the drift the design rests on.
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

/// A cached sidecar (its JSON, as an app would persist it) requiring
/// [builtInFloor] and referencing [types].
Map<String, Object?> _cachedSidecar({
  required int builtInFloor,
  required List<String> types,
}) {
  final sidecar = RestageA2uiSidecar(
    capability: CapabilityManifest(
      builtInFloor: builtInFloor,
      requiredLibraries: const [],
    ),
    perItemSinceVersion: {for (final t in types) t: builtInFloor},
    a2ui: {
      'version': 'v1.0',
      'createSurface': {
        'catalogId': 'cache-test',
        'surfaceId': 's',
        'components': [
          for (final (i, t) in types.indexed)
            {'id': i == 0 ? 'root' : t, 'component': t},
        ],
      },
    },
  );
  // Round-trip through JSON to model a real cache read.
  return jsonDecode(jsonEncode(sidecar.toJson())) as Map<String, Object?>;
}

void main() {
  group('cache drift', () {
    test('forward-compatible: a v1 payload renders on a v2 binary', () {
      // Binary installed catalog content version 2; cached payload needs 1.
      final check = RestageA2uiPreRenderCheck(
        catalogs: [
          _catalogOf(['Text', 'Column']),
        ],
        installed: A2uiInstalledCapability(
          catalogContentVersion: 2,
          availableLibraries: const [],
        ),
      );
      final result = check.check(
        _cachedSidecar(builtInFloor: 1, types: ['Text', 'Column']),
      );
      expect(result, isA<A2uiRenderable>());
    });

    test('new payload on an old binary is rejected (the stamp catches it)', () {
      // Binary at v1; the cached payload was generated against v2 and needs it.
      // The existence walk alone could not catch this — every name still
      // exists — so the version stamp is what rejects it.
      final check = RestageA2uiPreRenderCheck(
        catalogs: [
          _catalogOf(['Text', 'Column']),
        ],
        installed: A2uiInstalledCapability(
          catalogContentVersion: 1,
          availableLibraries: const [],
        ),
      );
      final result = check.check(
        _cachedSidecar(builtInFloor: 2, types: ['Text', 'Column']),
      );
      expect(result, isA<A2uiRejected>());
      expect((result as A2uiRejected).gap, contains('version 2'));
    });

    test('incompatible shape change forks the name → existence rejects', () {
      // Under the cumulative-render-support invariant, an incompatible change
      // to a component forks a new identity. The cached payload references the
      // OLD name, which the new binary's catalog no longer has — the existence
      // walk rejects it before a2ui_flutter would throw.
      final check = RestageA2uiPreRenderCheck(
        catalogs: [
          _catalogOf(['Text', 'PriceTag_v2']),
        ],
        installed: A2uiInstalledCapability(
          catalogContentVersion: 2,
          availableLibraries: const [],
        ),
      );
      final result = check.check(
        _cachedSidecar(builtInFloor: 1, types: ['Text', 'PriceTag']),
      );
      expect(result, isA<A2uiRejected>());
      expect((result as A2uiRejected).diagnostic, contains('PriceTag'));
    });
  });
}
