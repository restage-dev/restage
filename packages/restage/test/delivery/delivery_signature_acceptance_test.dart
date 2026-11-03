import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/delivery/delivery_trust.dart';
import 'package:restage/src/restage_rpc_client/surface_artifact_assembly.dart';
import 'package:restage_shared/restage_shared.dart';

import '../support/delivery_signing.dart';

void main() {
  final blob = BlobSurfacePayload(
    minClient: 1,
    blob: Uint8List.fromList(const <int>[1, 2, 3]),
  );

  SurfaceArtifactDescriptor descriptor({
    int version = 4,
    int authorizedAtMicros = 1000,
    TestDeliverySigner? signer,
  }) =>
      (signer ?? testDeliverySigner).signed(SurfaceArtifactDescriptor(
        payloadFormatVersion: kSurfaceArtifactPayloadFormatVersion,
        surfaceType: Surface.onboarding,
        surfaceSlug: 'welcome',
        version: version,
        publishedAtMicros: 1000,
        contentHash: blob.contentHash,
        artifactUrl: 'https://artifacts.test/a',
        artifactPass: 'pass',
        signature: unsignedTestSignature,
        authorizedAtMicros: authorizedAtMicros,
      ));

  SurfaceArtifactOutcome assemble(
    SurfaceArtifactDescriptor value, {
    bool fresh = true,
  }) =>
      assembleSurfaceArtifact(
        descriptor: value,
        artifactBytes: blob.canonicalBytes,
        fresh: fresh,
      );

  Matcher refused(SurfaceArtifactFetchFailure reason) =>
      isA<SurfaceArtifactUnavailable>()
          .having((outcome) => outcome.reason, 'reason', reason);

  test('content signed by the configured key assembles', () {
    expect(assemble(descriptor()), isA<SurfaceArtifactAssembled>());
  });

  test('content signed by another key never assembles', () {
    expect(
      assemble(descriptor(signer: TestDeliverySigner(seedByte: 9))),
      refused(SurfaceArtifactFetchFailure.unknownDeliveryKey),
    );
  });

  test('a field changed after signing never assembles', () {
    final signed = descriptor();
    final tampered = SurfaceArtifactDescriptorV1Codec.decode({
      ...signed.toJson(),
      'version': 5,
    });
    expect(
      assemble(tampered),
      refused(SurfaceArtifactFetchFailure.invalidSignature),
    );
  });

  test('content authorized before the newest shown is refused', () {
    expect(assemble(descriptor(version: 5)), isA<SurfaceArtifactAssembled>());
    // A rule or arm serving an older version from the same set.
    expect(assemble(descriptor(version: 4)), isA<SurfaceArtifactAssembled>());
    expect(
      assemble(descriptor(version: 4, authorizedAtMicros: 900)),
      refused(SurfaceArtifactFetchFailure.rollback),
    );
    // An operator rollback authorizes the restored set again.
    expect(
      assemble(descriptor(version: 3, authorizedAtMicros: 2000)),
      isA<SurfaceArtifactAssembled>(),
    );
    // The version it replaced, replayed with its old authorization, is
    // refused even though it is newer.
    expect(
      assemble(descriptor(version: 5)),
      refused(SurfaceArtifactFetchFailure.rollback),
    );
  });

  test('a saved copy still verifies but is never refused as a rollback', () {
    expect(
      assemble(descriptor(version: 5, authorizedAtMicros: 2000)),
      isA<SurfaceArtifactAssembled>(),
    );
    expect(
      assemble(descriptor(version: 4), fresh: false),
      isA<SurfaceArtifactAssembled>(),
    );
    expect(
      assemble(descriptor(signer: TestDeliverySigner(seedByte: 9)),
          fresh: false),
      refused(SurfaceArtifactFetchFailure.unknownDeliveryKey),
    );
  });

  test('a saved copy raises the bar for later deliveries', () {
    expect(
      assemble(descriptor(version: 6, authorizedAtMicros: 2000), fresh: false),
      isA<SurfaceArtifactAssembled>(),
    );
    expect(
      assemble(descriptor(version: 5)),
      refused(SurfaceArtifactFetchFailure.rollback),
    );
  });

  test('a saved decision read at launch raises the bar before any delivery',
      () {
    DeliveryTrust.seed(descriptor(version: 6, authorizedAtMicros: 2000));
    expect(
      assemble(descriptor(version: 5)),
      refused(SurfaceArtifactFetchFailure.rollback),
    );
    expect(
      assemble(descriptor(version: 6, authorizedAtMicros: 2000)),
      isA<SurfaceArtifactAssembled>(),
    );
  });

  test('a retained dependency is not held to its own version history', () {
    expect(
      assemble(descriptor(version: 5, authorizedAtMicros: 2000)),
      isA<SurfaceArtifactAssembled>(),
    );
    expect(
      assembleDecodedSurfaceArtifact(descriptor(version: 2), blob, root: false),
      isA<SurfaceArtifactAssembled>(),
    );
  });
}
