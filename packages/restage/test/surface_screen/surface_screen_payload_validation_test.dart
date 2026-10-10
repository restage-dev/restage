import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/delivery/surface_sections_carrier.dart';
import 'package:restage_shared/restage_shared.dart';

import 'surface_screen_test_support.dart';

void main() {
  setUp(resetSurfaceScreenTestState);

  test('validates the payload frame a hosted screen was read with', () {
    final fixture = stringScreenFixture(
      capabilities: CapabilityManifest(
        builtInFloor: kSurfaceFeatureClientFloor,
        requiredLibraries: const <LibraryRequirement>[],
      ),
    );
    // A seed spelled "1.50": accepted on read, spelled "1.5" when re-encoded.
    final canonical = BlobSurfacePayload(
      minClient: kSurfaceFeatureClientFloor,
      blob: fixture.blob,
      localSeeds: const {
        'OnboardingScreen': {'n': 1.5},
      },
    ).canonicalBytes;
    final payload = SurfacePayload.decode(_respell(canonical));
    final rebuilt = BlobSurfacePayload(
      minClient: kSurfaceFeatureClientFloor,
      blob: fixture.blob,
      localSeeds: payload.localSeeds,
    );
    expect(rebuilt.contentHash, isNot(payload.contentHash));

    final resolved = attachSurfacePayload(
      ResolvedSurfaceScreen.hosted(
        surface: fixture.ref.surface,
        slug: fixture.ref.slug,
        contractVersion: fixture.ref.contractVersion,
        publishedRevision: 3,
        sourceKind: fixture.ref.sourceKind,
        payloadKind: fixture.ref.payloadKind,
        capabilities: fixture.capabilities,
        contractFingerprint: fixture.ref.contractFingerprint,
        eventContractHash: fixture.ref.eventContract.hash,
        blob: (payload as BlobSurfacePayload).blob,
        contentHash: payload.contentHash,
        cacheHit: false,
      ),
      payload,
    );

    fixture.ref.provenance.validateResolved(resolved);
    fixture.ref.provenance.validateResolved(resolved.withCacheHit());
  });
}

/// Replaces the seed text "1.5" with "1.50" and fixes its length prefix.
Uint8List _respell(Uint8List bytes) {
  const from = <int>[0, 0, 0, 3, 0x31, 0x2e, 0x35];
  for (var i = 0; i + from.length <= bytes.length; i++) {
    var match = true;
    for (var j = 0; j < from.length; j++) {
      if (bytes[i + j] != from[j]) {
        match = false;
        break;
      }
    }
    if (match) {
      return Uint8List.fromList([
        ...bytes.sublist(0, i),
        0,
        0,
        0,
        4,
        0x31,
        0x2e,
        0x35,
        0x30,
        ...bytes.sublist(i + from.length),
      ]);
    }
  }
  throw StateError('seed text not found');
}
