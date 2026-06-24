import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  group('CapabilitySidecar', () {
    final manifest = CapabilityManifest(
      builtInFloor: 2,
      requiredLibraries: const [
        LibraryRequirement(namespace: 'acme.widgets', minVersion: 3),
      ],
    );

    test('hashBlob produces a sha256:<64 hex> hash, deterministic per bytes',
        () {
      final hash = CapabilitySidecar.hashBlob(const [1, 2, 3]);
      expect(hash, matches(RegExp(r'^sha256:[0-9a-f]{64}$')));
      expect(CapabilitySidecar.hashBlob(const [1, 2, 3]), hash);
      expect(CapabilitySidecar.hashBlob(const [1, 2, 4]), isNot(hash));
    });

    test('round-trips through JSON', () {
      final hash = CapabilitySidecar.hashBlob(const [9, 9, 9]);
      final sidecar = CapabilitySidecar(blobSha256: hash, manifest: manifest);
      final decoded = CapabilitySidecar.fromJson(sidecar.toJson());
      expect(decoded.blobSha256, hash);
      expect(decoded.manifest, manifest);
      expect(decoded, sidecar);
    });

    test('fromJson rejects a malformed blob hash', () {
      expect(
        () => CapabilitySidecar.fromJson({
          'blobSha256': 'not-a-hash',
          'manifest': manifest.toJson(),
        }),
        throwsFormatException,
      );
    });

    test('fromJson rejects a missing/typeless manifest', () {
      expect(
        () => CapabilitySidecar.fromJson({
          'blobSha256': CapabilitySidecar.hashBlob(const [1]),
        }),
        throwsFormatException,
      );
    });
  });
}
