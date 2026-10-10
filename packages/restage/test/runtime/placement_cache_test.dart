import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/delivery/surface_artifact_store.dart';
import 'package:restage/src/delivery/placement_decision_store.dart';
import 'package:restage/src/delivery/raced_surface_resolver.dart';
import 'package:restage/src/measurement/placement_mount_attribution.dart';
import 'package:restage/src/resolver/placement_mount_resolver.dart';
import 'package:restage/src/resolver/surface_assignment_key_provider.dart';
import 'package:restage/src/resolver/surface_canonical_carrier_provider.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage/src/runtime/placement_registry.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/placement_delivery_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Restage.debugReset();
    Restage.configure(analyticsEnabled: false, measurementEnabled: false);
    sharedSurfaceArtifactStore = MemorySurfaceArtifactStore();
    SurfaceCanonicalCarrierProvider.installBuiltIns(() => _builtIns('stable'));
  });
  tearDown(() {
    Restage.debugReset();
    sharedSurfaceArtifactStore = null;
  });

  test('registry stores unpublished flow dependencies from one batch request',
      () async {
    final fixture = readPlacementDeliveryFixture(
        fileName: 'retained_flow_dependencies_v1.json');
    final buildJson = fixture.request.buildContract.toJson();
    (buildJson['installedCapability'] as Map)['builtInCatalogVersion'] = 3;
    final installed = InstalledCapability.fromJson(
        buildJson['installedCapability'] as Map<String, dynamic>);
    buildJson['installedCapabilityHash'] = installed.contentHash;
    final build = PlacementBuildContractV1.fromJson(buildJson);
    final request = PlacementBatchRequestV1.fromJson({
      ...fixture.request.toJson(),
      'buildContract': build.toJson(),
      'appBuildContractHash': build.appBuildContractHash,
    });
    final responseJson = fixture.response.toJson();
    for (final row in responseJson['decisions'] as List) {
      final publicJson = (row as Map)['publicDelivery'] as Map;
      (publicJson['cacheValidity'] as Map)['installedCapabilityHash'] =
          installed.contentHash;
      // Let the value owner recompute the projection after the build change.
      final delivery = PublicPlacementDeliveryV1(
        mount: PlacementMountDescriptorV1.fromJson(publicJson['mount']),
        path: PublicDeliveryDecisionPathV1.fromJson(publicJson['path']),
        selectedSurface: DeliverySurfaceReferenceV1.fromJson(
            publicJson['selectedSurface'] as Map<String, Object?>),
        actualPublication: DeliveryPublicationReferenceV1.fromJson(
            publicJson['actualPublication'] as Map<String, Object?>),
        cacheValidity: DeliveryCacheValidityV1.fromJson(
            publicJson['cacheValidity'] as Map<String, Object?>),
        fitRequirement:
            SurfaceFitRequirementV1.fromJson(publicJson['fitRequirement']),
        dependencyClosure: (publicJson['dependencyClosure'] as List)
            .map((value) =>
                DeliveryPolicyScopeV1.fromJson(value as Map<String, Object?>))
            .toSet(),
      );
      (row)['publicDelivery'] = delivery.toJson();
    }
    final response = PlacementBatchResponseV1.fromCanonicalBytes(
        CanonicalJsonCodec.encode(responseJson),
        request: request,
        expectedTarget: fixture.target);
    var requests = 0;
    final registry = _registry((outgoing) async {
      requests++;
      expect(outgoing.method, 'POST');
      expect(outgoing.url.path, '/sdk/v1/placements/resolve');
      expect(outgoing.bodyBytes, request.canonicalBytes);
      return http.Response.bytes(response.canonicalBytes, 200);
    });
    final context = PlacementRequestContext(
        request: request,
        lease: SurfaceAssignmentKeyProvider.captureKeylessLease(),
        inputStamp: 'flow-inputs',
        capturedAt: DateTime.utc(2026, 10, 4),
        isCurrent: () => true);

    final result = await registry.fetch(context);

    expect(result, isNotNull);
    expect(requests, 1);
    expect(result!.artifacts.documents, hasLength(6));
    expect(result.artifacts.publications, hasLength(2));
    final keys = await sharedSurfaceArtifactStore.keys();
    expect(keys.where((key) => key.surfaceType == 'placementArtifact'),
        hasLength(4));
    expect(keys.where((key) => key.surfaceType == 'placementDecision'),
        hasLength(2));
  });

  test('restart replays authenticated stored content with no request',
      () async {
    final fixture = readPlacementDeliveryFixture();
    var requests = 0;
    final initial = _registry((request) async {
      requests++;
      final batch =
          PlacementBatchRequestV1.fromCanonicalBytes(request.bodyBytes);
      return http.Response.bytes(
          placementFixtureResponse(batch).canonicalBytes, 200);
    });
    final first = _resolver(initial, fixture.request.mounts.first);
    expect(
        await first.fresh(first.storeKey, sendAssignmentKey: false), isNotNull);
    expect(requests, 1);
    final restarted = _registry((_) async {
      requests++;
      throw StateError('Offline replay cannot request content.');
    });
    expect(restarted.client().placementTarget, isNull);
    final mounted = _resolver(restarted, fixture.request.mounts.first);
    final replay = await mounted.bestLocal(mounted.storeKey);
    expect(replay, isNotNull);
    expect(mounted.currentAdmission!.delivery.selectedSurface.family,
        DeliveryFamilySelectorV1.screenContract(contractVersion: 7));
    expect(restarted.target, fixture.target);
    expect(requests, 1);
  });

  test('shared bytes do not merge mount decisions', () async {
    final fixture = readPlacementDeliveryFixture();
    var requests = 0;
    final registry = _registry((request) async {
      requests++;
      final batch =
          PlacementBatchRequestV1.fromCanonicalBytes(request.bodyBytes);
      return http.Response.bytes(
          placementFixtureResponse(batch).canonicalBytes, 200);
    });
    final resolvers = [
      for (final mount in fixture.request.mounts) _resolver(registry, mount)
    ];
    final context = await registry.capture(
        mounts: fixture.request.mounts, sendAssignmentKey: false);
    expect(await registry.fetch(context!), isNotNull);
    final keys = await sharedSurfaceArtifactStore.keys();
    expect(keys.where((key) => key.surfaceType == 'placementArtifact'),
        hasLength(1));
    expect(keys.where((key) => key.surfaceType == 'placementDecision'),
        hasLength(2));
    await sharedSurfaceArtifactStore.remove(registry.decisions.decisionKey(
        context.request, fixture.request.mounts.first, context.inputStamp,
        target: fixture.target));
    expect(await resolvers.first.bestLocal(resolvers.first.storeKey), isNull);
    expect(await resolvers.last.bestLocal(resolvers.last.storeKey), isNotNull);
    expect(requests, 1);
  });

  test('assigned restart keeps the original proof and expiry', () async {
    final fixture = readPlacementDeliveryFixture();
    final mount = fixture.request.mounts.first;
    const key = 'original_credential';
    SurfaceAssignmentKeyProvider.current = () => key;
    SurfaceAssignmentKeyProvider.local = () => key;
    SurfaceCanonicalCarrierProvider.enableAssignmentRetention('test_scope');
    final assignment = PresentationAssignmentCarrierV2(
        owner: PresentationAssignmentOwnerV2.path,
        outcomeLinkCarrier:
            base64UrlEncode(List.filled(32, 7)).replaceAll('=', ''));
    var now = DateTime.utc(2026, 10, 4, 12);
    final expires = now.add(const Duration(minutes: 1)).microsecondsSinceEpoch;
    final requests = <PlacementBatchRequestV1>[];
    final initial = _registry((outgoing) async {
      final request =
          PlacementBatchRequestV1.fromCanonicalBytes(outgoing.bodyBytes);
      requests.add(request);
      return http.Response.bytes(
          placementFixtureResponse(request,
              assignment: assignment,
              routingSelectionReceipt: 'opaque.original.receipt',
              cacheValidityOverrides: {
                'assignmentExpiresAtMicros': expires
              }).canonicalBytes,
          200);
    }, now: () => now);
    final resolver = _resolver(initial, mount);
    final first =
        await resolver.fresh(resolver.storeKey, sendAssignmentKey: true);
    expect(first, isNotNull);
    expect(requests.single.heldAssignments, isEmpty);
    final original = resolvedPlacementDeliveryFor(first!)!;
    expect(original.assignment, assignment);

    // Drop only process memory, preserving the existing durable credential scope.
    SurfaceCanonicalCarrierProvider.enableAssignmentRetention('test_scope');
    final restarted =
        _registry((_) async => throw StateError('Offline'), now: () => now);
    final cached = _resolver(restarted, mount);
    final replay = await cached.bestLocal(cached.storeKey);
    expect(replay, isNotNull);
    final held = resolvedPlacementDeliveryFor(replay!)!;
    expect(held.assignment, original.assignment);
    expect(held.routingSelectionReceipt, original.routingSelectionReceipt);
    expect(held.cacheValidity.assignmentExpiresAtMicros, expires);
    expect(cached.currentAdmission!.context.lease.assignmentKey, key);
    expect(cached.currentAdmission!.isAssigned, isTrue);
    expect(restarted.target, fixture.target);
    final returning =
        await restarted.capture(mounts: [mount], sendAssignmentKey: true);
    expect(returning!.request.heldAssignments.single.retainedPathHandle,
        assignment.outcomeLinkCarrier);

    SurfaceAssignmentKeyProvider.local = () => 'other_credential';
    expect(await cached.bestLocal(cached.storeKey), isNull);
    SurfaceAssignmentKeyProvider.local = () => key;
    now = DateTime.fromMicrosecondsSinceEpoch(expires, isUtc: true);
    expect(await cached.bestLocal(cached.storeKey), isNull);
    expect(requests, hasLength(1));
  });

  test('an unproven held assignment is forgotten and not sent again', () async {
    final fixture = readPlacementDeliveryFixture();
    final mount = fixture.request.mounts.first;
    const key = 'original_credential';
    SurfaceAssignmentKeyProvider.current = () => key;
    SurfaceAssignmentKeyProvider.local = () => key;
    SurfaceCanonicalCarrierProvider.enableAssignmentRetention('test_scope');
    final assignment = PresentationAssignmentCarrierV2(
        owner: PresentationAssignmentOwnerV2.path,
        outcomeLinkCarrier:
            base64UrlEncode(List.filled(32, 7)).replaceAll('=', ''));
    var refuse = false;
    final registry = _registry((outgoing) async {
      final request =
          PlacementBatchRequestV1.fromCanonicalBytes(outgoing.bodyBytes);
      final available = placementFixtureResponse(request,
          assignment: assignment,
          routingSelectionReceipt: 'opaque.original.receipt');
      if (!refuse) return http.Response.bytes(available.canonicalBytes, 200);
      return http.Response.bytes(
          PlacementBatchResolvedV1(
              request: request,
              expectedTarget: fixture.target,
              decisions: [
                for (final row in available.decisions)
                  PlacementBatchEntryV1.useFallback(row.descriptor,
                      PlacementBatchRefusalReasonV1.assignmentUnavailable, [])
              ],
              artifacts: const []).canonicalBytes,
          200);
    });
    final resolver = _resolver(registry, mount);
    expect(await resolver.fresh(resolver.storeKey, sendAssignmentKey: true),
        isNotNull);
    expect(
        await SurfaceCanonicalCarrierProvider.heldPlacement(
            mount: mount, assignmentKey: key),
        isNotNull);
    refuse = true;
    final context =
        await registry.capture(mounts: [mount], sendAssignmentKey: true);
    expect(context!.request.heldAssignments, hasLength(1));
    await registry.fetch(context);
    expect(
        await SurfaceCanonicalCarrierProvider.heldPlacement(
            mount: mount, assignmentKey: key),
        isNull);
    SurfaceCanonicalCarrierProvider.enableAssignmentRetention('test_scope');
    final returning =
        await registry.capture(mounts: [mount], sendAssignmentKey: true);
    expect(returning!.request.heldAssignments, isEmpty);
  });

  test('keyless delivery cannot admit or retain an assigned response',
      () async {
    final fixture = readPlacementDeliveryFixture();
    final assignment = PresentationAssignmentCarrierV2(
        owner: PresentationAssignmentOwnerV2.path,
        outcomeLinkCarrier:
            base64UrlEncode(List.filled(32, 7)).replaceAll('=', ''));
    final registry = _registry((outgoing) async => http.Response.bytes(
        placementFixtureResponse(
                PlacementBatchRequestV1.fromCanonicalBytes(outgoing.bodyBytes),
                assignment: assignment)
            .canonicalBytes,
        200));
    final resolver = _resolver(registry, fixture.request.mounts.first);
    expect(await resolver.fresh(resolver.storeKey, sendAssignmentKey: false),
        isNull);
    expect(
        (await sharedSurfaceArtifactStore.keys())
            .where((key) => key.surfaceType == 'placementDecision'),
        isEmpty);
  });

  test('accepted probe posts refresh with its exact retained path authority',
      () async {
    final fixture = readPlacementDeliveryFixture();
    SurfaceAssignmentKeyProvider.current = () => 'original_credential';
    SurfaceAssignmentKeyProvider.local = () => 'original_credential';
    SurfaceCanonicalCarrierProvider.enableAssignmentRetention('test_scope');
    final assignment = PresentationAssignmentCarrierV2(
        owner: PresentationAssignmentOwnerV2.path,
        outcomeLinkCarrier:
            base64UrlEncode(List.filled(32, 7)).replaceAll('=', ''));
    final requests = <PlacementBatchRequestV1>[];
    var digest = CanonicalDigest('c' * 64);
    var throttled = false;
    final registry = _registry((outgoing) async {
      final request =
          PlacementBatchRequestV1.fromCanonicalBytes(outgoing.bodyBytes);
      requests.add(request);
      if (throttled) {
        return http.Response('', 429, headers: {'retry-after': '7'});
      }
      return http.Response.bytes(
          placementFixtureResponse(request,
              assignment: assignment,
              routingSelectionReceipt: 'opaque.original.receipt',
              watch: (delivery) => PlacementDeliveryWatchV1(
                      decisionIdentityDigest: digest,
                      channels: [
                        for (final scope in delivery.dependencyClosure)
                          PlacementDeliveryWatchChannelV1(
                              scope: scope, token: _watchToken)
                      ])).canonicalBytes,
          200);
    });
    final resolver = _resolver(registry, fixture.request.mounts.first);
    expect(await resolver.fresh(resolver.storeKey, sendAssignmentKey: true),
        isNotNull);
    final accepted = resolver.currentAdmission!;
    final cacheKey = (await sharedSurfaceArtifactStore.keys())
        .singleWhere((key) => key.surfaceType == 'placementDecision');
    final original = (await sharedSurfaceArtifactStore.read(cacheKey))!;
    digest = CanonicalDigest('d' * 64);
    final probe = await accepted.probe(accepted.refreshState!);
    expect(probe, isA<PlacementRefreshUnchangedV1>());
    expect(
        (probe as PlacementRefreshUnchangedV1).decisionIdentityDigest, digest);
    expect(probe.watch!.channels.map((channel) => channel.scope).toSet(),
        accepted.delivery.dependencyClosure);
    final request = requests.last;
    expect(request.mode, PlacementBatchModeV1.refresh);
    expect(request.registration, isNull);
    expect(request.assignmentKey, 'original_credential');
    expect(request.heldAssignments.single.retainedPathHandle,
        assignment.outcomeLinkCarrier);
    expect(request.mounts.single, fixture.request.mounts.first);
    expect((await sharedSurfaceArtifactStore.read(cacheKey))!.descriptorJson,
        original.descriptorJson);
    throttled = true;
    final limited = await accepted.probe(accepted.refreshState!);
    expect(limited, isA<PlacementRefreshRateLimitedV1>());
    expect((limited as PlacementRefreshRateLimitedV1).retryAfter,
        const Duration(seconds: 7));
    expect(requests, hasLength(3));
  });

  test('old accepted invalidation cannot remove a newer queued decision',
      () async {
    final fixture = readPlacementDeliveryFixture();
    final old = fixture.response.decisions.first as PlacementBatchAvailableV1;
    final newerResponse = placementFixtureResponse(fixture.request,
        family: DeliveryFamilySelectorV1.screenContract(contractVersion: 8));
    final newer = newerResponse.decisions.first as PlacementBatchAvailableV1;
    final store = _PausedDecisionReadStore();
    final decisions = PlacementDecisionStore(scope: 'test_scope', store: store);
    final key = decisions.decisionKey(
        fixture.request, fixture.request.mounts.first, 'inputs',
        target: fixture.target);
    StoredSurface stored(PlacementBatchAvailableV1 decision) => StoredSurface(
        descriptorJson: decision.canonicalBytes,
        artifactBytes: Uint8List(0),
        sidecar: const {'assignmentKey': 'original_credential'});
    await store.write(key, stored(old));
    final invalidating = decisions.removeAccepted(key, old);
    await store.decisionReadStarted.future;
    final writing = persistAcceptedDelivery(store, key, stored(newer));
    store.release.complete();
    await Future.wait([invalidating, writing]);
    expect((await store.read(key))!.descriptorJson, newer.canonicalBytes);
    await decisions.removeAccepted(key, old);
    expect((await store.read(key))!.descriptorJson, newer.canonicalBytes);
    await decisions.removeAccepted(key, newer);
    expect(await store.read(key), isNull);
  });

  test('corrupt or missing stored closure refuses without GET', () async {
    final fixture = readPlacementDeliveryFixture();
    var requests = 0;
    final registry = _registry((request) async {
      requests++;
      return http.Response.bytes(
          placementFixtureResponse(
                  PlacementBatchRequestV1.fromCanonicalBytes(request.bodyBytes))
              .canonicalBytes,
          200);
    });
    final resolver = _resolver(registry, fixture.request.mounts.first);
    expect(await resolver.fresh(resolver.storeKey, sendAssignmentKey: false),
        isNotNull);
    final artifact = (await sharedSurfaceArtifactStore.keys())
        .singleWhere((key) => key.surfaceType == 'placementArtifact');
    final stored = (await sharedSurfaceArtifactStore.read(artifact))!;
    await sharedSurfaceArtifactStore.write(
        artifact,
        StoredSurface(
            descriptorJson: stored.descriptorJson,
            artifactBytes: Uint8List.fromList([0])));
    expect(await resolver.bestLocal(resolver.storeKey), isNull);
    await sharedSurfaceArtifactStore.remove(artifact);
    expect(await resolver.bestLocal(resolver.storeKey), isNull);
    expect(requests, 1);
  });

  test('origin, credential and input changes cannot replay another authority',
      () async {
    final fixture = readPlacementDeliveryFixture();
    final registry = _registry((request) async => http.Response.bytes(
        placementFixtureResponse(
                PlacementBatchRequestV1.fromCanonicalBytes(request.bodyBytes))
            .canonicalBytes,
        200));
    final resolver = _resolver(registry, fixture.request.mounts.first);
    expect(await resolver.fresh(resolver.storeKey, sendAssignmentKey: false),
        isNotNull);
    for (final other in [
      _registry((_) async => throw StateError('No request'),
          origin: 'https://other.example'),
      _registry((_) async => throw StateError('No request'),
          credential: 'other_key')
    ]) {
      final mounted = _resolver(other, fixture.request.mounts.first);
      expect(await mounted.bestLocal(mounted.storeKey), isNull);
      expect(other.target, isNull);
    }
    SurfaceCanonicalCarrierProvider.installBuiltIns(() => _builtIns('changed'));
    expect(await resolver.bestLocal(resolver.storeKey), isNull);
  });

  test('keyed unassigned cache keeps the original local credential lease',
      () async {
    final fixture = readPlacementDeliveryFixture();
    SurfaceAssignmentKeyProvider.current = () => 'test_credential';
    SurfaceAssignmentKeyProvider.local = () => 'test_credential';
    final registry = _registry((request) async => http.Response.bytes(
        placementFixtureResponse(
                PlacementBatchRequestV1.fromCanonicalBytes(request.bodyBytes))
            .canonicalBytes,
        200));
    final resolver = _resolver(registry, fixture.request.mounts.first);
    expect(await resolver.fresh(resolver.storeKey, sendAssignmentKey: true),
        isNotNull);
    expect(await resolver.bestLocal(resolver.storeKey), isNotNull);
    expect(resolver.currentAdmission!.context.lease.assignmentKey,
        'test_credential');
    SurfaceAssignmentKeyProvider.local = () => 'different_credential';
    expect(await resolver.bestLocal(resolver.storeKey), isNull);
  });

  test('stored accepted-response metadata is required to restore target',
      () async {
    final fixture = readPlacementDeliveryFixture();
    final registry = _registry((request) async => http.Response.bytes(
        placementFixtureResponse(
                PlacementBatchRequestV1.fromCanonicalBytes(request.bodyBytes))
            .canonicalBytes,
        200));
    final resolver = _resolver(registry, fixture.request.mounts.first);
    expect(await resolver.fresh(resolver.storeKey, sendAssignmentKey: false),
        isNotNull);
    final key = (await sharedSurfaceArtifactStore.keys())
        .singleWhere((key) => key.surfaceType == 'placementDecision');
    final stored = (await sharedSurfaceArtifactStore.read(key))!;
    await sharedSurfaceArtifactStore.write(
        key,
        StoredSurface(
            descriptorJson: stored.descriptorJson,
            artifactBytes: stored.artifactBytes,
            sidecar: {...stored.sidecar}
              ..remove('authenticatedConfigurationFingerprint')));
    final restarted = _registry((_) async => throw StateError('No request'));
    final mounted = _resolver(restarted, fixture.request.mounts.first);
    expect(await mounted.bestLocal(mounted.storeKey), isNull);
    expect(restarted.target, isNull);
  });

  test('configuration retirement refuses an in-flight decision write',
      () async {
    final store = _PausedDecisionReadStore();
    sharedSurfaceArtifactStore = store;
    var current = true;
    var requests = 0;
    final fixture = readPlacementDeliveryFixture();
    final registry = _registry((request) async {
      requests++;
      return http.Response.bytes(
          placementFixtureResponse(
                  PlacementBatchRequestV1.fromCanonicalBytes(request.bodyBytes))
              .canonicalBytes,
          200);
    }, isCurrent: () => current);
    final resolver = _resolver(registry, fixture.request.mounts.first);
    final resolving =
        resolver.fresh(resolver.storeKey, sendAssignmentKey: false);
    await store.decisionReadStarted.future;
    current = false;
    store.release.complete();
    expect(await resolving, isNull);
    expect(
        (await store.keys())
            .where((key) => key.surfaceType == 'placementDecision'),
        isEmpty);
    final restarted = _registry((_) async => throw StateError('Offline'));
    final mounted = _resolver(restarted, fixture.request.mounts.first);
    expect(await mounted.bestLocal(mounted.storeKey), isNull);
    expect(restarted.target, isNull);
    expect(requests, 1);
  });

  test('clock rollback cannot replay content captured in the future', () async {
    var now = DateTime.utc(2026, 10, 4, 12);
    var requests = 0;
    final fixture = readPlacementDeliveryFixture();
    final registry = _registry((request) async {
      requests++;
      return http.Response.bytes(
          placementFixtureResponse(
                  PlacementBatchRequestV1.fromCanonicalBytes(request.bodyBytes))
              .canonicalBytes,
          200);
    }, now: () => now);
    final resolver = _resolver(registry, fixture.request.mounts.first);
    expect(await resolver.fresh(resolver.storeKey, sendAssignmentKey: false),
        isNotNull);
    now = now.subtract(const Duration(seconds: 1));
    expect(await resolver.bestLocal(resolver.storeKey), isNull);
    expect(requests, 1);
  });
}

String _builtIns(String channel) => base64UrlEncode(CanonicalJsonCodec.encode({
      'platform': 'android',
      'sdkApiLevel': 4,
      'channel': channel,
    })).replaceAll('=', '');

const _watchToken =
    'v2.i5p7lxR3.1767229200.NDI6b25ib2FyZGluZzp3ZWxjb21lLWZsb3c.'
    'kV0gFtXCrtsWdYcIFXaVNEQDQFjXwvrEn4t_WY_KX44';

PlacementRegistry _registry(
    Future<http.Response> Function(http.Request) respond,
    {String origin = 'https://example.com',
    String credential = 'test_key',
    bool Function()? isCurrent,
    DateTime Function()? now}) {
  final client = RestageRpcClient(
      baseUrl: origin, apiKey: credential, httpClient: MockClient(respond));
  addTearDown(client.close);
  return PlacementRegistry(
      scope: SurfaceStoreKey.scopeFor(
          apiKey: credential, environment: 'production', baseUrl: origin),
      configurationFingerprint: SurfaceStoreKey.configurationFingerprintFor(
          apiKey: credential, environment: 'production', baseUrl: origin),
      client: () => client,
      isCurrent: isCurrent ?? () => true,
      now: now ?? () => DateTime.utc(2026, 10, 4, 12));
}

final class _PausedDecisionReadStore implements SurfaceArtifactStore {
  final delegate = MemorySurfaceArtifactStore();
  final decisionReadStarted = Completer<void>();
  final release = Completer<void>();

  @override
  Future<StoredSurface?> read(SurfaceStoreKey key) async {
    if (key.surfaceType == 'placementDecision' &&
        !decisionReadStarted.isCompleted) {
      decisionReadStarted.complete();
      await release.future;
    }
    return delegate.read(key);
  }

  @override
  Future<void> write(SurfaceStoreKey key, StoredSurface value) =>
      delegate.write(key, value);
  @override
  Future<List<SurfaceStoreKey>> keys() => delegate.keys();
  @override
  Future<void> remove(SurfaceStoreKey key) => delegate.remove(key);
  @override
  Future<void> clear() => delegate.clear();
}

PlacementPaywallResolver _resolver(
    PlacementRegistry registry, PlacementMountRequestV1 mount) {
  final fixture = readPlacementDeliveryFixture();
  return PlacementPaywallResolver(
      registry: registry,
      declaration: (
        mount: mount,
        host: fixture
            .request.buildContract.contractsByHash[mount.hostContractHash]!
      ),
      id: mount.key.slug,
      originalResolver: const _Unavailable());
}

final class _Unavailable implements VariantResolver {
  const _Unavailable();
  @override
  Future<ResolvedVariant> resolve(String id,
          {String? placementId, Locale? locale}) async =>
      throw StateError('No bundled original.');
}
