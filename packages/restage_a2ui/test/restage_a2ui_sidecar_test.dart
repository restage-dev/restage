import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage_a2ui/src/restage_a2ui_sidecar.dart';
import 'package:restage_shared/restage_shared.dart';

CapabilityManifest _manifest() => CapabilityManifest(
  builtInFloor: 2,
  requiredLibraries: [
    const LibraryRequirement(namespace: 'acme.widgets', minVersion: 3),
  ],
);

void main() {
  group('RestageA2uiSidecar', () {
    test('toJson emits the spec shape {restageCapability, a2ui}', () {
      final sidecar = RestageA2uiSidecar(
        capability: _manifest(),
        perItemSinceVersion: const {'Text': 1, 'AcmeBanner': 5},
        a2ui: const {
          'version': 'v0.9',
          'updateComponents': {
            'surfaceId': 's',
            'components': [
              {'id': 'root', 'component': 'Text', 'text': 'Hi'},
            ],
          },
        },
      );

      final json = sidecar.toJson();
      expect(json.keys, containsAll(<String>['restageCapability', 'a2ui']));
      final cap = json['restageCapability']! as Map<String, Object?>;
      expect(cap['builtInFloor'], 2);
      expect(cap['requiredLibraries'], isA<List<Object?>>());
      expect(cap['perItemSinceVersion'], {'Text': 1, 'AcmeBanner': 5});
      expect(json['a2ui'], isA<Map<String, Object?>>());
    });

    test('round-trips through JSON', () {
      final original = RestageA2uiSidecar(
        capability: _manifest(),
        perItemSinceVersion: const {'Text': 1},
        a2ui: const {
          'version': 'v0.9',
          'deleteSurface': {'surfaceId': 's'},
        },
      );
      final encoded = jsonEncode(original.toJson());
      final decoded = RestageA2uiSidecar.fromJson(
        jsonDecode(encoded) as Map<String, Object?>,
      );
      expect(jsonEncode(decoded.toJson()), encoded);
      expect(decoded.capability, original.capability);
      expect(decoded.perItemSinceVersion, original.perItemSinceVersion);
    });

    test(
      'always emits requiredLibraries + perItemSinceVersion (even empty)',
      () {
        final sidecar = RestageA2uiSidecar(
          capability: CapabilityManifest(
            builtInFloor: 1,
            requiredLibraries: const [],
          ),
          perItemSinceVersion: const {},
          a2ui: const {'version': 'v0.9'},
        );
        final cap =
            sidecar.toJson()['restageCapability']! as Map<String, Object?>;
        expect(cap['requiredLibraries'], isEmpty);
        expect(cap['perItemSinceVersion'], isEmpty);
      },
    );

    test('fromJson fails closed on a malformed envelope', () {
      // restageCapability absent.
      expect(
        () => RestageA2uiSidecar.fromJson(const {'a2ui': <String, Object?>{}}),
        throwsFormatException,
      );
      // restageCapability not an object.
      expect(
        () => RestageA2uiSidecar.fromJson(const {
          'restageCapability': 'nope',
          'a2ui': <String, Object?>{},
        }),
        throwsFormatException,
      );
      // a2ui key absent.
      expect(
        () => RestageA2uiSidecar.fromJson(const {
          'restageCapability': {
            'builtInFloor': 1,
            'requiredLibraries': <Object?>[],
          },
        }),
        throwsFormatException,
      );
      // restageCapability with a bad manifest (builtInFloor not int).
      expect(
        () => RestageA2uiSidecar.fromJson(const {
          'restageCapability': {
            'builtInFloor': 'x',
            'requiredLibraries': <Object?>[],
          },
          'a2ui': <String, Object?>{},
        }),
        throwsFormatException,
      );
    });

    test('isRestageSidecar detects the wrapper vs a raw payload', () {
      expect(
        RestageA2uiSidecar.isRestageSidecar(const {
          'restageCapability': {
            'builtInFloor': 1,
            'requiredLibraries': <Object?>[],
          },
          'a2ui': <String, Object?>{},
        }),
        isTrue,
      );
      expect(
        RestageA2uiSidecar.isRestageSidecar(const {
          'version': 'v0.9',
          'updateComponents': {'surfaceId': 's', 'components': <Object?>[]},
        }),
        isFalse,
      );
      expect(RestageA2uiSidecar.isRestageSidecar('not a map'), isFalse);
    });

    test(
      'cache-drift: the wrapper binds the required floor to the payload',
      () {
        // A payload generated against catalog v1 carries builtInFloor 1 — and
        // keeps carrying it through any cache round-trip, independent of the
        // catalog the app later installs. This is the datum the drift check
        // rests on (verified end-to-end in cache_drift_e2e_test.dart).
        final v1 = RestageA2uiSidecar(
          capability: CapabilityManifest(
            builtInFloor: 1,
            requiredLibraries: const [],
          ),
          perItemSinceVersion: const {'Text': 1},
          a2ui: const {'version': 'v0.9'},
        );
        final roundTripped = RestageA2uiSidecar.fromJson(
          jsonDecode(jsonEncode(v1.toJson())) as Map<String, Object?>,
        );
        expect(roundTripped.capability.builtInFloor, 1);
      },
    );
  });
}
