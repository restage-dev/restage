import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:restage/src/delivery/delivered_fonts.dart';
import 'package:restage/src/delivery/surface_artifact_store.dart';
import 'package:restage/src/resolver/surface_assignment_key_provider.dart';
import 'package:restage/src/resolver/surface_canonical_carrier_provider.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage/src/restage_rpc_client/surface_artifact_assembly.dart';
import 'package:restage_shared/restage_shared.dart';

import '../support/hosted_artifact_delivery.dart';

void main() {
  setUp(() {
    SurfaceAssignmentKeyProvider.clear();
    SurfaceCanonicalCarrierProvider.clear();
  });
  tearDown(() {
    SurfaceAssignmentKeyProvider.clear();
    SurfaceCanonicalCarrierProvider.clear();
  });

  RestageRpcClient clientFor(
    HostedArtifactFixture delivery,
    List<Map<String, dynamic>> bodies,
    Map<String, Object?> response, {
    Map<String, String> headers = const <String, String>{},
  }) {
    final client = RestageRpcClient(
      baseUrl: 'https://example.com',
      apiKey: 'rs_pk_test',
      httpClient: delivery.client((request) async {
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(jsonEncode(response), 200, headers: headers);
      }),
    );
    addTearDown(client.close);
    return client;
  }

  test('an assembled delivery carries its halves exactly as served', () async {
    final delivery = HostedArtifactFixture();
    final document = testBlobDocument(const [4, 5, 6]);
    final response = delivery.describe(document);
    final client = clientFor(delivery, [], response);

    final result = await client.fetchSurface(
      surfaceType: 'paywall',
      surfaceSlug: 'pro_upgrade',
    );

    final stored = result!.stored!;
    expect(jsonDecode(utf8.decode(stored.descriptorJson)), response);
    expect(stored.artifactBytes, document.payload.canonicalBytes);
  });

  test('a stored delivery replays to the same document without a request',
      () async {
    final delivery = HostedArtifactFixture();
    final document = testBlobDocument(const [4, 5, 6]);
    final client = clientFor(delivery, [], delivery.describe(document));
    final fetched = await client.fetchSurface(
      surfaceType: 'paywall',
      surfaceSlug: 'pro_upgrade',
    );
    final requestsBefore = delivery.artifactRequests.length;

    final replayed = await replayStoredSurface(fetched!.stored!);

    expect(assembledBlob(replayed!.artifact), [4, 5, 6]);
    expect(delivery.artifactRequests, hasLength(requestsBefore));
  });

  test('stored bytes that no longer match their description do not replay',
      () async {
    final delivery = HostedArtifactFixture();
    final client = clientFor(
      delivery,
      [],
      delivery.describe(testBlobDocument(const [4, 5, 6])),
    );
    final stored = (await client.fetchSurface(
      surfaceType: 'paywall',
      surfaceSlug: 'pro_upgrade',
    ))!
        .stored!;

    final tampered = StoredSurface(
      descriptorJson: stored.descriptorJson,
      artifactBytes: Uint8List.fromList(stored.artifactBytes)..[0] ^= 0xff,
      sidecar: stored.sidecar,
    );

    expect(await replayStoredSurface(tampered), isNull);
    expect(
      await replayStoredSurface(StoredSurface(
        descriptorJson: Uint8List.fromList(utf8.encode('not json')),
        artifactBytes: stored.artifactBytes,
      )),
      isNull,
    );
  });

  test('a delivery refused at assembly carries nothing to store', () async {
    final delivery = HostedArtifactFixture();
    final document = testBlobDocument(const [4, 5, 6]);
    final response = delivery.describeRaw(
      surfaceType: document.surfaceType,
      surfaceSlug: document.surfaceSlug,
      version: document.version,
      publishedAt: document.publishedAt,
      content: document.payload.canonicalBytes,
      declaredContentHash: 'sha256:${'0' * 64}',
    );
    final client = clientFor(delivery, [], response);

    final result = await client.fetchSurface(
      surfaceType: 'paywall',
      surfaceSlug: 'pro_upgrade',
    );

    expect(result!.artifact, isA<SurfaceArtifactUnavailable>());
    expect(result.stored, isNull);
  });

  test('a stored delivery whose icon font fails to load does not replay',
      () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    addTearDown(DeliveredIconFontLoader.reset);
    final fontBytes = File(
      '../restage_shared/test/fonts/fixtures/material_icons_subset.otf',
    ).readAsBytesSync();
    final document = SurfaceDocument(
      surfaceType: Surface.paywall,
      surfaceSlug: 'pro_upgrade',
      version: 1,
      minClient: kSurfaceFeatureClientFloor,
      payload: BlobSurfacePayload(
        minClient: kSurfaceFeatureClientFloor,
        blob: Uint8List.fromList(const [1, 2, 3]),
        iconFonts: [
          DeliveredIconFont(family: 'MaterialIcons', bytes: fontBytes),
        ],
      ),
      publishedAt: DateTime.utc(2026),
    );
    final delivery = HostedArtifactFixture();
    final response = delivery.describeRaw(
      surfaceType: document.surfaceType,
      surfaceSlug: document.surfaceSlug,
      version: document.version,
      publishedAt: document.publishedAt,
      content: document.payload.canonicalBytes,
      payloadFormatVersion: kMaxSupportedSurfaceArtifactPayloadFormatVersion,
    );
    DeliveredIconFontLoader.reset();
    DeliveredIconFontLoader.loadFont = (_, __) async {};
    final client = clientFor(delivery, [], response);
    final stored = (await client.fetchSurface(
      surfaceType: 'paywall',
      surfaceSlug: 'pro_upgrade',
    ))!
        .stored!;

    DeliveredIconFontLoader.reset();
    DeliveredIconFontLoader.loadFont =
        (_, __) async => throw StateError('font rejected');

    expect(await replayStoredSurface(stored), isNull);
  });

  group('the assignment key', () {
    test('is sent and recorded beside the stored delivery', () async {
      SurfaceAssignmentKeyProvider.current = () => 'assignment-a';
      final delivery = HostedArtifactFixture();
      final bodies = <Map<String, dynamic>>[];
      final client = clientFor(
        delivery,
        bodies,
        delivery.describe(testBlobDocument(const [1])),
      );

      final result = await client.fetchSurface(
        surfaceType: 'paywall',
        surfaceSlug: 'pro_upgrade',
      );

      expect(bodies.single['assignmentKey'], 'assignment-a');
      expect(storedSurfaceAssignmentKey(result!.stored!), 'assignment-a');
    });

    test('is omitted, with any held assignment, when not to be sent', () async {
      var keyReads = 0;
      SurfaceAssignmentKeyProvider.current = () {
        keyReads += 1;
        return 'assignment-a';
      };
      SurfaceCanonicalCarrierProvider.installHeldAssignment(() => 'aGVsZA');
      final delivery = HostedArtifactFixture();
      final bodies = <Map<String, dynamic>>[];
      final client = clientFor(
        delivery,
        bodies,
        delivery.describe(testBlobDocument(const [1])),
      );

      final result = await client.fetchSurface(
        surfaceType: 'paywall',
        surfaceSlug: 'pro_upgrade',
        sendAssignmentKey: false,
      );

      expect(keyReads, 0);
      expect(bodies.single, isNot(contains('assignmentKey')));
      expect(bodies.single, isNot(contains('assignmentCanonicalBase64')));
      expect(storedSurfaceAssignmentKey(result!.stored!), isNull);
    });

    test('is omitted when not ready before the key deadline', () async {
      final never = Future<String?>.delayed(const Duration(days: 1));
      SurfaceAssignmentKeyProvider.current = () => never;
      final delivery = HostedArtifactFixture();
      final bodies = <Map<String, dynamic>>[];
      final client = clientFor(
        delivery,
        bodies,
        delivery.describe(testBlobDocument(const [1])),
      );

      await client.fetchSurface(
        surfaceType: 'paywall',
        surfaceSlug: 'pro_upgrade',
        keyDeadline: Future<void>.value(),
      );

      expect(bodies.single, isNot(contains('assignmentKey')));
    });
  });
}
