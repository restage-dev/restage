import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/src/delivery/surface_artifact_store.dart';
import 'package:restage/src/refresh/delivery_announcement.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage/src/runtime/placement_registry.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/placement_delivery_fixture.dart';
import '../support/sent_placement_request.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sharedSurfaceArtifactStore = MemorySurfaceArtifactStore();
  });
  tearDown(() => sharedSurfaceArtifactStore = null);

  final fixture = readPlacementDeliveryFixture();
  final declarations = [
    for (final mount in fixture.request.mounts)
      (
        mount: mount,
        host: fixture
            .request.buildContract.contractsByHash[mount.hostContractHash]!,
      ),
  ];

  PlacementRegistry registryFor(List<PlacementBatchRequestV1> sent,
      {Future<void> Function(PlacementBatchRequestV1 request)? before,
      List<String>? fetched}) {
    final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'test_key',
        httpClient: MockClient((request) async {
          final artifact = placementFixtureArtifact(request);
          if (artifact != null) {
            fetched?.add(request.url.toString());
            return artifact;
          }
          final batch = sentPlacementRequest(request.bodyBytes);
          sent.add(batch);
          await before?.call(batch);
          final answer = batch.inlineMounts.isEmpty
              ? placementFixtureResponse(batch)
              : PlacementBatchResolvedV1.fromBuiltRows(
                  request: batch,
                  expectedTarget: fixture.target,
                  decisions: placementFixtureResponse(batch).decisions,
                  inlineArtifacts: {
                      for (final artifact in fixture.artifacts)
                        artifact.identity: artifact.bytes,
                    });
          return http.Response.bytes(answer.canonicalBytes, 200, headers: {
            if (request.headers.containsKey('restage-want-records'))
              'restage-want-met': '1',
          });
        }));
    addTearDown(client.close);
    final registry = PlacementRegistry(
        scope: SurfaceStoreKey.scopeFor(
            apiKey: 'test_key',
            environment: 'production',
            baseUrl: 'https://example.com'),
        configurationFingerprint: SurfaceStoreKey.configurationFingerprintFor(
            apiKey: 'test_key',
            environment: 'production',
            baseUrl: 'https://example.com'),
        client: () => client,
        isCurrent: () => true,
        now: () => DateTime.utc(2026, 10, 4, 12));
    for (final declaration in declarations) {
      registry.remember(declaration);
    }
    return registry;
  }

  Future<Object?> mount(PlacementRegistry registry, int index) =>
      registry.fetchMount(declarations[index].mount,
          sendAssignmentKey: false, publicationGuard: () => true);

  test('a mount batch after a live-refresh push asks for its content inline',
      () async {
    final sent = <PlacementBatchRequestV1>[];
    final fetched = <String>[];
    final registry = registryFor(sent, fetched: fetched);
    final want = AnnouncedWant('d/1/general/a=${'1' * 64}');
    expect(await withAnnouncedWant(want, () => mount(registry, 0)), isNotNull);
    expect(sent.single.inlineMounts, [0]);
    expect(fetched, isEmpty, reason: 'the answer carried the content');
    expect(want.met, isTrue);

    expect(await mount(registry, 1), isNotNull);
    expect(sent.last.inlineMounts, isEmpty, reason: 'no push announced it');
  });

  test('the startup batch sends only what the mount batch in flight leaves',
      () async {
    expect(declarations.length, greaterThan(1));
    final sent = <PlacementBatchRequestV1>[];
    final registry = registryFor(sent);
    final mounted = mount(registry, 0);
    await registry.prefetch(declarations);
    expect(await mounted, isNotNull);
    expect(sent.map((request) => request.mode),
        [PlacementBatchModeV1.mount, PlacementBatchModeV1.prefetch]);
    expect(sent.last.mounts, [
      for (final declaration in declarations.skip(1)) declaration.mount,
    ]);
  });

  test('the startup batch sends nothing once mounts answered every one',
      () async {
    final sent = <PlacementBatchRequestV1>[];
    final registry = registryFor(sent);
    final mounted = [
      for (var index = 0; index < declarations.length; index++)
        mount(registry, index),
    ];
    await registry.prefetch(declarations);
    for (final answer in mounted) {
      expect(await answer, isNotNull);
    }
    expect(sent.map((request) => request.mode), [PlacementBatchModeV1.mount]);
  });

  test('a mount never waits for the startup batch', () async {
    final sent = <PlacementBatchRequestV1>[];
    final release = Completer<void>();
    final registry = registryFor(sent, before: (request) async {
      if (request.mode == PlacementBatchModeV1.prefetch) await release.future;
    });
    final prefetched = registry.prefetch(declarations);
    await pumpEventQueue();
    expect(
        sent.map((request) => request.mode), [PlacementBatchModeV1.prefetch]);
    expect(await mount(registry, 0), isNotNull);
    release.complete();
    await prefetched;
    expect(sent.map((request) => request.mode),
        [PlacementBatchModeV1.prefetch, PlacementBatchModeV1.mount]);
  });
}
