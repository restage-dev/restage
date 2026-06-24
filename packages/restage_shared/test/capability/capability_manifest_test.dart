import 'dart:convert';

import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  group('LibraryRequirement', () {
    test('value equality and hashCode', () {
      const a = LibraryRequirement(namespace: 'acme.widgets', minVersion: 3);
      const b = LibraryRequirement(namespace: 'acme.widgets', minVersion: 3);
      const c = LibraryRequirement(namespace: 'acme.widgets', minVersion: 4);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('JSON round-trips', () {
      const r = LibraryRequirement(namespace: 'acme.widgets', minVersion: 3);

      final decoded = LibraryRequirement.fromJson(
        jsonDecode(jsonEncode(r.toJson())) as Map<String, dynamic>,
      );

      expect(decoded, r);
    });
  });

  group('CapabilityManifest', () {
    test('canonicalizes requiredLibraries to namespace order', () {
      final manifest = CapabilityManifest(
        builtInFloor: 5,
        requiredLibraries: const [
          LibraryRequirement(namespace: 'zeta.ui', minVersion: 1),
          LibraryRequirement(namespace: 'acme.widgets', minVersion: 2),
          LibraryRequirement(namespace: 'mid.kit', minVersion: 1),
        ],
      );

      expect(
        manifest.requiredLibraries.map((r) => r.namespace),
        ['acme.widgets', 'mid.kit', 'zeta.ui'],
      );
    });

    test('toJson always emits requiredLibraries, including the empty list', () {
      final manifest = CapabilityManifest(
        builtInFloor: 1,
        requiredLibraries: const [],
      );

      final json = manifest.toJson();

      expect(json.containsKey('requiredLibraries'), isTrue);
      expect(json['requiredLibraries'], isEmpty);
      expect(json['builtInFloor'], 1);
    });

    test('toJson emits requiredLibraries in canonical namespace order', () {
      final manifest = CapabilityManifest(
        builtInFloor: 7,
        requiredLibraries: const [
          LibraryRequirement(namespace: 'b.lib', minVersion: 2),
          LibraryRequirement(namespace: 'a.lib', minVersion: 3),
        ],
      );

      final namespaces = (manifest.toJson()['requiredLibraries'] as List)
          .map((e) => (e as Map<String, dynamic>)['namespace'])
          .toList();

      expect(namespaces, ['a.lib', 'b.lib']);
    });

    test('value equality is independent of input order', () {
      final m1 = CapabilityManifest(
        builtInFloor: 2,
        requiredLibraries: const [
          LibraryRequirement(namespace: 'a.lib', minVersion: 1),
          LibraryRequirement(namespace: 'b.lib', minVersion: 2),
        ],
      );
      final m2 = CapabilityManifest(
        builtInFloor: 2,
        requiredLibraries: const [
          LibraryRequirement(namespace: 'b.lib', minVersion: 2),
          LibraryRequirement(namespace: 'a.lib', minVersion: 1),
        ],
      );

      expect(m1, m2);
      expect(m1.hashCode, m2.hashCode);
    });

    test('JSON round-trips, including the empty requiredLibraries case', () {
      final manifest = CapabilityManifest(
        builtInFloor: 4,
        requiredLibraries: const [
          LibraryRequirement(namespace: 'acme.widgets', minVersion: 3),
        ],
      );
      final empty = CapabilityManifest(
        builtInFloor: 1,
        requiredLibraries: const [],
      );

      expect(
        CapabilityManifest.fromJson(
          jsonDecode(jsonEncode(manifest.toJson())) as Map<String, dynamic>,
        ),
        manifest,
      );
      expect(
        CapabilityManifest.fromJson(
          jsonDecode(jsonEncode(empty.toJson())) as Map<String, dynamic>,
        ),
        empty,
      );
    });

    test('fromJson tolerates an absent requiredLibraries as empty', () {
      final decoded = CapabilityManifest.fromJson(const {'builtInFloor': 3});

      expect(decoded.builtInFloor, 3);
      expect(decoded.requiredLibraries, isEmpty);
    });
  });
}
