import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage/src/restage_rpc_client/placement_delivery_adapter.dart';
import 'package:restage/src/delivery/surface_artifact_store.dart';
import 'package:restage/src/flow/flow_resolver.dart';
import 'package:restage/src/flow/flow_descriptors.dart';
import 'package:restage/src/resolver/placement_mount_resolver.dart';
import 'package:restage/src/resolver/surface_assignment_key_provider.dart';
import 'package:restage/src/runtime/placement_registry.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';

import '../support/placement_delivery_fixture.dart';

void main() {
  test(
    'one authenticated batch assembles unpublished flow descendants by source identity',
    () async {
      final fixture = readPlacementDeliveryFixture(
        fileName: 'retained_flow_dependencies_v1.json',
      );
      final requests = <http.Request>[];
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response.bytes(fixture.response.canonicalBytes, 200);
        }),
      );
      addTearDown(client.close);
      sharedSurfaceArtifactStore = MemorySurfaceArtifactStore();
      addTearDown(() => sharedSurfaceArtifactStore = null);
      final response = await client.fetchPlacements(
        fixture.request,
        publicationGuard: () => true,
      ) as PlacementBatchResolvedV1;
      final artifacts = placementArtifactsFor(response)!;
      expect(artifacts.frames, hasLength(4));
      expect(artifacts.documents, hasLength(6));
      expect(artifacts.publications, hasLength(2));
      final first = response.decisions.first as PlacementBatchAvailableV1;
      final rootDocument =
          artifacts.publications[first.publicDelivery.actualPublication]!;
      expect(rootDocument.version, 29);
      expect(
        (rootDocument.payload as FlowSurfacePayload).flowDocument.version,
        5,
      );
      final declaration = (
        mount: fixture.request.mounts.first,
        host: fixture.request.buildContract
            .contractsByHash[fixture.request.mounts.first.hostContractHash]!,
      );
      final registry = PlacementRegistry(
        scope: 'retained-flow-test',
        configurationFingerprint: 'retained-flow-test',
        client: () => client,
        isCurrent: () => true,
      );
      final context = PlacementRequestContext(
        request: fixture.request,
        lease: SurfaceAssignmentKeyProvider.captureKeylessLease(),
        inputStamp: 'captured',
        capturedAt: DateTime.utc(2026, 10, 3),
        isCurrent: () => true,
      );
      final resolver = PlacementFlowResolver(
        registry: registry,
        declaration: declaration,
        flow: SurfaceFlowRef<Map<String, Object?>>(
          id: 'first_root',
          version: 29,
          minClient: 2,
          surface: Surface.general,
          decodeResult: (value) => value,
        ),
        originalResolver: const AssetFlowResolver(),
      );
      final root = resolver.convert(
        PlacementDeliveryAdmission(
          decision: first,
          context: context,
          host: declaration.host,
          registry: registry,
          document: rootDocument,
        ),
        artifacts,
        cacheHit: false,
      )!;
      expect(root.document.flow, 'first_root');
      expect(root.document.version, 5);
      final child = await resolver.resolve(
        SurfaceFlowRef<Map<String, Object?>>(
          id: 'shared_child',
          version: 7,
          minClient: 2,
          surface: Surface.general,
          decodeResult: (value) => value,
        ),
      );
      final leaf = await resolver.resolve(
        SurfaceFlowRef<Map<String, Object?>>(
          id: 'shared_leaf',
          version: 11,
          minClient: 2,
          surface: Surface.general,
          decodeResult: (value) => value,
        ),
      );
      expect(child.document.version, 7);
      expect(leaf.document.version, 11);
      expect(
        first.artifactClosure.where(
          (reference) => reference.publication == null,
        ),
        hasLength(2),
      );
      await expectLater(
        resolver.resolve(
          SurfaceFlowRef<Map<String, Object?>>(
            id: 'second_root',
            version: 8,
            minClient: 2,
            surface: Surface.general,
            decodeResult: (value) => value,
          ),
        ),
        throwsA(isA<FlowUnavailableError>()),
      );
      expect(requests, hasLength(1));
      expect(requests.single.method, 'POST');
      expect(requests.single.url.path, '/sdk/v1/placements/resolve');
    },
  );

  test(
    'one placement POST admits two decisions and one transferred frame',
    () async {
      final fixture = readPlacementDeliveryFixture();
      final requests = <http.Request>[];
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: MockClient((request) async {
          requests.add(request);
          expect(request.method, 'POST');
          expect(request.url.path, '/sdk/v1/placements/resolve');
          expect(request.headers['Authorization'], 'Bearer rs_pk_test');
          expect(request.bodyBytes, fixture.request.canonicalBytes);
          return http.Response.bytes(fixture.response.canonicalBytes, 200);
        }),
      );
      addTearDown(client.close);

      final response = await client.fetchPlacements(
        fixture.request,
        publicationGuard: () => true,
      );

      expect(requests, hasLength(1));
      expect(response, isA<PlacementBatchResolvedV1>());
      final resolved = response! as PlacementBatchResolvedV1;
      expect(resolved.decisions, hasLength(2));
      expect(resolved.artifacts, hasLength(1));
      expect(client.heldPlacementArtifacts, hasLength(1));
      expect(client.placementTarget, fixture.target);
      final replacements = resolved.decisions.cast<PlacementBatchAvailableV1>();
      for (final replacement in replacements) {
        expect(
          replacement.publicDelivery.actualPublication.surface.family,
          DeliveryFamilySelectorV1.screenContract(contractVersion: 7),
        );
        expect(
          replacement.publicDelivery.actualPublication.surface.family,
          isNot(replacement.descriptor.defaultSurface!.family),
        );
      }
    },
  );

  test('held batch content is assembled without an artifact GET', () async {
    final fixture = readPlacementDeliveryFixture();
    final requests = <http.Request>[];
    var omitContent = false;
    final client = RestageRpcClient(
      baseUrl: 'https://example.com',
      apiKey: 'rs_pk_test',
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response.bytes(
          CanonicalJsonCodec.encode({
            ...fixture.response.toJson(),
            if (omitContent) 'artifacts': <Object?>[],
          }),
          200,
        );
      }),
    );
    addTearDown(client.close);
    await client.fetchPlacements(fixture.request, publicationGuard: () => true);
    omitContent = true;
    final request = PlacementBatchRequestV1.fromJson({
      ...fixture.request.toJson(),
      'heldArtifacts': [
        for (final identity in client.heldPlacementArtifacts.keys)
          identity.toJson(),
      ],
    });

    final response = await client.fetchPlacements(
      request,
      publicationGuard: () => true,
    );

    expect(response, isA<PlacementBatchResolvedV1>());
    expect(requests, hasLength(2));
    expect(requests.map((request) => request.method), everyElement('POST'));
  });

  test('missing declared held content refuses without a hidden GET', () async {
    final fixture = readPlacementDeliveryFixture();
    final requests = <http.Request>[];
    final request = PlacementBatchRequestV1.fromJson({
      ...fixture.request.toJson(),
      'heldArtifacts': [fixture.response.artifacts.single.identity.toJson()],
    });
    final client = RestageRpcClient(
      baseUrl: 'https://example.com',
      apiKey: 'rs_pk_test',
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response.bytes(
          CanonicalJsonCodec.encode({
            ...fixture.response.toJson(),
            'artifacts': <Object?>[],
          }),
          200,
        );
      }),
    );
    addTearDown(client.close);

    final response = await client.fetchPlacements(
      request,
      publicationGuard: () => true,
    );

    expect(response, isA<PlacementBatchRefusedV1>());
    expect(
      (response! as PlacementBatchRefusedV1).reason,
      PlacementBatchRefusalReasonV1.invalidRequest,
    );
    expect(requests, hasLength(1));
    expect(client.heldPlacementArtifacts, isEmpty);
  });

  test('an independently known target fences a foreign batch', () async {
    final fixture = readPlacementDeliveryFixture();
    final client = RestageRpcClient(
      baseUrl: 'https://example.com',
      apiKey: 'rs_pk_test',
      httpClient: MockClient(
        (_) async => http.Response.bytes(fixture.response.canonicalBytes, 200),
      ),
    );
    addTearDown(client.close);
    final otherTarget = TargetCoordinate.fromJson({
      ...fixture.target.toJson(),
      'appId': 99,
    });

    final response = await client.fetchPlacements(
      fixture.request,
      expectedTarget: otherTarget,
      publicationGuard: () => true,
    );

    expect(response, isA<PlacementBatchRefusedV1>());
    expect(client.placementTarget, isNull);
    expect(client.heldPlacementArtifacts, isEmpty);
  });

  test(
    'a stale generation cannot publish a completed placement reply',
    () async {
      final fixture = readPlacementDeliveryFixture();
      final reply = Completer<http.Response>();
      final posted = Completer<void>();
      var current = true;
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: MockClient((_) {
          posted.complete();
          return reply.future;
        }),
      );
      addTearDown(client.close);
      final pending = client.fetchPlacements(
        fixture.request,
        publicationGuard: () => current,
      );
      final rejected = expectLater(
        pending,
        throwsA(isA<SurfaceRequestPublicationRejected>()),
      );
      await posted.future;
      current = false;
      reply.complete(http.Response.bytes(fixture.response.canonicalBytes, 200));
      await rejected;

      expect(client.heldPlacementArtifacts, isEmpty);
      expect(client.placementTarget, isNull);
    },
  );

  test('a closed publication fence never posts a placement request', () async {
    final fixture = readPlacementDeliveryFixture();
    var requests = 0;
    final client = RestageRpcClient(
      baseUrl: 'https://example.com',
      apiKey: 'rs_pk_test',
      httpClient: MockClient((_) async {
        requests++;
        return http.Response.bytes(fixture.response.canonicalBytes, 200);
      }),
    );
    addTearDown(client.close);

    await expectLater(
      client.fetchPlacements(fixture.request, publicationGuard: () => false),
      throwsA(isA<SurfaceRequestPublicationRejected>()),
    );
    expect(requests, 0);
  });
}
