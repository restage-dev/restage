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
import 'package:restage/src/resolver/surface_assignment_credential_store.dart';
import 'package:restage/src/resolver/surface_assignment_key_provider.dart';
import 'package:restage/src/resolver/surface_canonical_carrier_provider.dart';
import 'package:restage/src/resolver/surface_delivery_observations.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage/src/runtime/placement_registry.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/placement_delivery_fixture.dart';
import '../support/sent_placement_request.dart';

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

  test('decisions read ahead follow removals and evictions', () async {
    final registry = PlacementRegistry(
      scope: 'saved-test',
      configurationFingerprint: 'saved-test',
      client: () => throw StateError('No request is made.'),
      isCurrent: () => true,
    );
    const key = SurfaceStoreKey(
        scope: 'saved-test',
        surfaceType: 'placementDecision',
        slug: 'stale',
        contractVersion: 1);
    final fixture = readPlacementDeliveryFixture();
    final decision =
        fixture.response.decisions.first as PlacementBatchAvailableV1;
    registry.warmSaved();
    final saved = registry.decisions.saved!;
    final version = saved.version;
    await registry.decisions.remove(key);
    expect(registry.decisions.saved, same(saved));
    expect(saved.version, greaterThan(version));
    expect((await saved.rows).containsKey(key), isFalse);
    saved.update((rows) => rows[key] = (
          stored: StoredSurface(
              descriptorJson: decision.canonicalBytes,
              artifactBytes: Uint8List(0)),
          decision: decision
        ));
    await registry.decisions.removeAccepted(key, decision);
    // An eviction removes the row it matches and keeps the read ahead.
    expect(registry.decisions.saved, same(saved));
    expect((await saved.rows).containsKey(key), isFalse);
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
        capturedAt: DateTime.utc(2026, 10, 4),
        isCurrent: () => true);

    final result = await registry.fetch(context);
    await PlacementDecisionStore.writesSettled(sharedSurfaceArtifactStore);

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
      final batch = sentPlacementRequest(request.bodyBytes);
      return http.Response.bytes(
          placementFixtureResponse(batch).canonicalBytes, 200);
    });
    final first = _resolver(initial, fixture.request.mounts.first);
    expect(
        await first.fresh(first.storeKey, sendAssignmentKey: false), isNotNull);
    await PlacementDecisionStore.writesSettled(sharedSurfaceArtifactStore);
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

  test('an unreadable stored decision is dropped without hiding the rest',
      () async {
    final fixture = readPlacementDeliveryFixture();
    final scope = SurfaceStoreKey.scopeFor(
        apiKey: 'test_key',
        environment: 'production',
        baseUrl: 'https://example.com');
    final unreadable = SurfaceStoreKey(
        scope: scope,
        surfaceType: 'placementDecision',
        slug: 'unreadable',
        contractVersion: 1);
    // Written first, so a cold scan meets it before the readable decision.
    await sharedSurfaceArtifactStore.write(
        unreadable,
        StoredSurface(
            descriptorJson: Uint8List.fromList(utf8.encode('{"old":true}')),
            artifactBytes: Uint8List(0),
            sidecar: {
              'authenticatedConfigurationFingerprint':
                  SurfaceStoreKey.configurationFingerprintFor(
                      apiKey: 'test_key',
                      environment: 'production',
                      baseUrl: 'https://example.com'),
            }));
    final initial = _registry((request) async => http.Response.bytes(
        placementFixtureResponse(sentPlacementRequest(request.bodyBytes))
            .canonicalBytes,
        200));
    final first = _resolver(initial, fixture.request.mounts.first);
    expect(
        await first.fresh(first.storeKey, sendAssignmentKey: false), isNotNull);
    await PlacementDecisionStore.writesSettled(sharedSurfaceArtifactStore);
    final restarted = _registry((_) async => throw StateError('No request'));
    final mounted = _resolver(restarted, fixture.request.mounts.first);
    expect(await mounted.bestLocal(mounted.storeKey), isNotNull);
    expect(await sharedSurfaceArtifactStore.read(unreadable), isNull);
  });

  test('shared bytes do not merge mount decisions', () async {
    final fixture = readPlacementDeliveryFixture();
    var requests = 0;
    final registry = _registry((request) async {
      requests++;
      final batch = sentPlacementRequest(request.bodyBytes);
      return http.Response.bytes(
          placementFixtureResponse(batch).canonicalBytes, 200);
    });
    final resolvers = [
      for (final mount in fixture.request.mounts) _resolver(registry, mount)
    ];
    final context = await registry.capture(
        mounts: fixture.request.mounts, sendAssignmentKey: false);
    expect(await registry.fetch(context!), isNotNull);
    await PlacementDecisionStore.writesSettled(sharedSurfaceArtifactStore);
    final keys = await sharedSurfaceArtifactStore.keys();
    expect(keys.where((key) => key.surfaceType == 'placementArtifact'),
        hasLength(1));
    expect(keys.where((key) => key.surfaceType == 'placementDecision'),
        hasLength(2));
    await sharedSurfaceArtifactStore.remove(registry.decisions.decisionKey(
        context.request, fixture.request.mounts.first,
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
      final request = sentPlacementRequest(outgoing.bodyBytes);
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
      final request = sentPlacementRequest(outgoing.bodyBytes);
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
          ).canonicalBytes,
          200);
    });
    final resolver = _resolver(registry, mount);
    expect(await resolver.fresh(resolver.storeKey, sendAssignmentKey: true),
        isNotNull);
    await PlacementDecisionStore.writesSettled(sharedSurfaceArtifactStore);
    expect(
        await SurfaceCanonicalCarrierProvider.heldPlacement(
            mount: mount, assignmentKey: key),
        isNotNull);
    refuse = true;
    final context =
        await registry.capture(mounts: [mount], sendAssignmentKey: true);
    expect(context!.request.heldAssignments, hasLength(1));
    await registry.fetch(context);
    await PlacementDecisionStore.writesSettled(sharedSurfaceArtifactStore);
    expect(
        await SurfaceCanonicalCarrierProvider.heldPlacement(
            mount: mount, assignmentKey: key),
        isNull);
    SurfaceCanonicalCarrierProvider.enableAssignmentRetention('test_scope');
    final returning =
        await registry.capture(mounts: [mount], sendAssignmentKey: true);
    expect(returning!.request.heldAssignments, isEmpty);
  });

  test('a withdrawn assignment is not painted from memory', () async {
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
      final request = sentPlacementRequest(outgoing.bodyBytes);
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
          ).canonicalBytes,
          200);
    })
      ..warmSaved();
    await registry.decisions.saved!.rows;
    final resolver = _resolver(registry, mount);
    expect(await resolver.fresh(resolver.storeKey, sendAssignmentKey: true),
        isNotNull);
    await PlacementDecisionStore.writesSettled(sharedSurfaceArtifactStore);
    expect(resolver.heldNow(), isNotNull);
    refuse = true;
    final context =
        await registry.capture(mounts: [mount], sendAssignmentKey: true);
    await registry.fetch(context!);
    await PlacementDecisionStore.writesSettled(sharedSurfaceArtifactStore);
    expect(resolver.heldNow(), isNull);
    expect(await resolver.bestLocal(resolver.storeKey), isNull);
  });

  test('a decision held in memory follows its lease and its saved row',
      () async {
    final fixture = readPlacementDeliveryFixture();
    final mount = fixture.request.mounts.first;
    Future<PlacementPaywallResolver> accepted() async {
      final registry = _registry((outgoing) async {
        final request = sentPlacementRequest(outgoing.bodyBytes);
        return http.Response.bytes(
            placementFixtureResponse(request).canonicalBytes, 200);
      })
        ..warmSaved();
      await registry.decisions.saved!.rows;
      final resolver = _resolver(registry, mount);
      expect(await resolver.fresh(resolver.storeKey, sendAssignmentKey: false),
          isNotNull);
      await PlacementDecisionStore.writesSettled(sharedSurfaceArtifactStore);
      expect(resolver.heldNow(), isNotNull);
      return resolver;
    }

    // A retired credential retires the lease it was accepted under.
    final retired = await accepted();
    SurfaceAssignmentKeyProvider.current = () => 'another_credential';
    expect(retired.heldNow(), isNull);
    // A forgotten saved row takes the held decision with it.
    final forgotten = await accepted();
    await forgotten.forgetStored(forgotten.storeKey);
    expect(forgotten.heldNow(), isNull);
  });

  test('a later answer for the same delivery keeps the held decision',
      () async {
    final fixture = readPlacementDeliveryFixture();
    final mount = fixture.request.mounts.first;
    var receipt = 'opaque.first.receipt';
    final registry = _registry((outgoing) async {
      final request = sentPlacementRequest(outgoing.bodyBytes);
      return http.Response.bytes(
          placementFixtureResponse(request, routingSelectionReceipt: receipt)
              .canonicalBytes,
          200);
    })
      ..warmSaved();
    await registry.decisions.saved!.rows;
    final resolver = _resolver(registry, mount);
    expect(await resolver.fresh(resolver.storeKey, sendAssignmentKey: false),
        isNotNull);
    await PlacementDecisionStore.writesSettled(sharedSurfaceArtifactStore);
    expect(resolver.heldNow(), isNotNull);
    // Another answer for the mount, as the startup batch sends.
    receipt = 'opaque.second.receipt';
    final context =
        await registry.capture(mounts: [mount], sendAssignmentKey: false);
    await registry.fetch(context!);
    await PlacementDecisionStore.writesSettled(sharedSurfaceArtifactStore);
    expect(resolver.heldNow(), isNotNull);
  });

  test('a held decision is used only with the bytes it came from', () async {
    final fixture = readPlacementDeliveryFixture();
    final mount = fixture.request.mounts.first;
    final registry = _registry((outgoing) async {
      final request = sentPlacementRequest(outgoing.bodyBytes);
      return http.Response.bytes(
          placementFixtureResponse(request).canonicalBytes, 200);
    })
      ..warmSaved();
    final saved = registry.decisions.saved!;
    await saved.rows;
    final resolver = _resolver(registry, mount);
    expect(await resolver.fresh(resolver.storeKey, sendAssignmentKey: false),
        isNotNull);
    await PlacementDecisionStore.writesSettled(sharedSurfaceArtifactStore);
    expect(await resolver.bestLocal(resolver.storeKey), isNotNull);
    // Other bytes arrive under the held decision.
    saved.update((rows) {
      final key = rows.keys
          .singleWhere((key) => key.surfaceType == 'placementDecision');
      final row = rows[key]!;
      final tampered = Uint8List.fromList(row.stored.descriptorJson);
      tampered[tampered.length ~/ 2] ^= 1;
      rows[key] = (
        stored: StoredSurface(
            descriptorJson: tampered,
            artifactBytes: row.stored.artifactBytes,
            sidecar: row.stored.sidecar),
        decision: row.decision
      );
    });
    expect(await resolver.bestLocal(resolver.storeKey), isNull);
  });

  test('a verified frame is reused only with the bytes it came from', () async {
    final fixture = readPlacementDeliveryFixture();
    final mount = fixture.request.mounts.first;
    final registry = _registry((outgoing) async {
      final request = sentPlacementRequest(outgoing.bodyBytes);
      return http.Response.bytes(
          placementFixtureResponse(request).canonicalBytes, 200);
    })
      ..warmSaved();
    final saved = registry.decisions.saved!;
    await saved.rows;
    final resolver = _resolver(registry, mount);
    expect(await resolver.fresh(resolver.storeKey, sendAssignmentKey: false),
        isNotNull);
    await PlacementDecisionStore.writesSettled(sharedSurfaceArtifactStore);
    expect(await resolver.bestLocal(resolver.storeKey), isNotNull);
    // Other bytes arrive under the verified frame.
    saved.update((rows) {
      final key = rows.keys
          .singleWhere((key) => key.surfaceType == 'placementArtifact');
      final row = rows[key]!.stored;
      final tampered = Uint8List.fromList(row.artifactBytes);
      tampered[tampered.length ~/ 2] ^= 1;
      rows[key] = (
        stored: StoredSurface(
            descriptorJson: row.descriptorJson,
            artifactBytes: tampered,
            sidecar: row.sidecar),
        decision: null
      );
    });
    expect(await resolver.bestLocal(resolver.storeKey), isNull);
  });

  test('a mount sends its registration until the handle is confirmed',
      () async {
    final fixture = readPlacementDeliveryFixture();
    final registry = _registry((_) async => http.Response('', 503));
    final mount = fixture.request.mounts.first;
    _resolver(registry, mount);
    String? handle;
    SurfaceAssignmentKeyProvider.install(
      key: () => handle,
      identityGeneration: () => 0,
      registration: () async => SurfaceRegistrationAttempt(
        registrationNonce:
            base64UrlEncode(List.filled(32, 7)).replaceAll('=', ''),
        registrationCreatedAtMicros: 1,
        generation: 0,
        fingerprint: 'f' * 64,
        credentialHandle: handle,
      ),
    );
    final first =
        await registry.capture(mounts: [mount], sendAssignmentKey: true);
    expect(first!.request.registration, isNotNull);
    expect(first.request.assignmentKey, isNull);
    handle = 'confirmed_handle';
    final confirmed =
        await registry.capture(mounts: [mount], sendAssignmentKey: true);
    expect(confirmed!.request.registration, isNull);
    expect(confirmed.request.assignmentKey, 'confirmed_handle');
  });

  test('keyless delivery cannot admit or retain an assigned response',
      () async {
    final fixture = readPlacementDeliveryFixture();
    final assignment = PresentationAssignmentCarrierV2(
        owner: PresentationAssignmentOwnerV2.path,
        outcomeLinkCarrier:
            base64UrlEncode(List.filled(32, 7)).replaceAll('=', ''));
    final registry = _registry((outgoing) async => http.Response.bytes(
        placementFixtureResponse(sentPlacementRequest(outgoing.bodyBytes),
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
      final request = sentPlacementRequest(outgoing.bodyBytes);
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
    await PlacementDecisionStore.writesSettled(sharedSurfaceArtifactStore);
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
        fixture.request, fixture.request.mounts.first,
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
          placementFixtureResponse(sentPlacementRequest(request.bodyBytes))
              .canonicalBytes,
          200);
    });
    final resolver = _resolver(registry, fixture.request.mounts.first);
    expect(await resolver.fresh(resolver.storeKey, sendAssignmentKey: false),
        isNotNull);
    await PlacementDecisionStore.writesSettled(sharedSurfaceArtifactStore);
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

  test(
      'origin, credential and consulted input changes cannot replay another '
      'authority', () async {
    final fixture = readPlacementDeliveryFixture();
    final registry = _registry((request) async => http.Response.bytes(
        placementFixtureResponse(sentPlacementRequest(request.bodyBytes),
            cacheValidityOverrides: const {
              'consultedBuiltIns': ['channel']
            }).canonicalBytes,
        200));
    final resolver = _resolver(registry, fixture.request.mounts.first);
    expect(await resolver.fresh(resolver.storeKey, sendAssignmentKey: false),
        isNotNull);
    await PlacementDecisionStore.writesSettled(sharedSurfaceArtifactStore);
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

  test('a change in a fact the decision did not read still replays', () async {
    final fixture = readPlacementDeliveryFixture();
    final registry = _registry((request) async => http.Response.bytes(
        placementFixtureResponse(sentPlacementRequest(request.bodyBytes))
            .canonicalBytes,
        200));
    final resolver = _resolver(registry, fixture.request.mounts.first);
    expect(await resolver.fresh(resolver.storeKey, sendAssignmentKey: false),
        isNotNull);
    await PlacementDecisionStore.writesSettled(sharedSurfaceArtifactStore);
    SurfaceCanonicalCarrierProvider.installBuiltIns(() => _builtIns('changed'));
    expect(await resolver.bestLocal(resolver.storeKey), isNotNull);
  });

  test('captures reuse one build contract until the declarations change',
      () async {
    final mounts = readPlacementDeliveryFixture().request.mounts;
    final registry = _registry((_) async => throw StateError('No request'));
    _resolver(registry, mounts.first);
    Future<PlacementBuildContractV1> build() async =>
        (await withSurfaceDeliveryObservations(
                cell: _cell(Future.value('7')),
                resolve: () => registry.capture(
                    mounts: [mounts.first], sendAssignmentKey: false)))!
            .request
            .buildContract;
    final first = await build();
    expect(await build(), same(first));
    _resolver(registry, mounts.last);
    final widened = await build();
    expect(widened, isNot(same(first)));
    expect(widened.mounts, hasLength(first.mounts.length + 1));
  });

  group('platform reads', () {
    setUp(() {
      debugResetAppBuildOrdinal();
      debugResetOsVersion();
    });
    tearDown(() {
      debugResetAppBuildOrdinal();
      debugResetOsVersion();
    });

    // Saves the fixture's decision under build 7, then restarts the process.
    Future<PlacementPaywallResolver> saved(List<String> consulted) async {
      final fixture = readPlacementDeliveryFixture();
      final registry = _registry((request) async => http.Response.bytes(
          placementFixtureResponse(sentPlacementRequest(request.bodyBytes),
                  cacheValidityOverrides: {'consultedBuiltIns': consulted})
              .canonicalBytes,
          200));
      final resolver = _resolver(registry, fixture.request.mounts.first);
      expect(
          await withSurfaceDeliveryObservations(
              cell: _cell(Future.value('7')),
              resolve: () =>
                  resolver.fresh(resolver.storeKey, sendAssignmentKey: false)),
          isNotNull);
      await PlacementDecisionStore.writesSettled(sharedSurfaceArtifactStore);
      debugResetAppBuildOrdinal();
      debugResetOsVersion();
      return _resolver(_registry((_) async => throw StateError('No request')),
          fixture.request.mounts.first);
    }

    test('a decision that read no fact paints before either read answers',
        () async {
      final mounted = await saved(const []);
      final build = Completer<String?>();
      final local = await withSurfaceDeliveryObservations(
          cell: _cell(build.future, os: Completer<int?>().future),
          resolve: () => mounted.bestLocal(mounted.storeKey));
      expect(local, isNotNull);
      expect(build.isCompleted, isFalse);
    });

    for (final (label, ordinal, replays) in [
      ('the same build replays', '7', true),
      ('another build is refused', '8', false),
    ]) {
      test('a decision that read the build waits for it: $label', () async {
        final mounted = await saved(const ['appBuildOrdinal']);
        final build = Completer<String?>();
        var done = false;
        final local = withSurfaceDeliveryObservations(
            cell: _cell(build.future),
            resolve: () => mounted.bestLocal(mounted.storeKey))
          ..whenComplete(() => done = true);
        await pumpEventQueue();
        expect(done, isFalse);
        build.complete(ordinal);
        expect(await local, replays ? isNotNull : isNull);
      });
    }
  });

  test('keyed unassigned cache keeps the original local credential lease',
      () async {
    final fixture = readPlacementDeliveryFixture();
    SurfaceAssignmentKeyProvider.current = () => 'test_credential';
    SurfaceAssignmentKeyProvider.local = () => 'test_credential';
    final registry = _registry((request) async => http.Response.bytes(
        placementFixtureResponse(sentPlacementRequest(request.bodyBytes))
            .canonicalBytes,
        200));
    final resolver = _resolver(registry, fixture.request.mounts.first);
    expect(await resolver.fresh(resolver.storeKey, sendAssignmentKey: true),
        isNotNull);
    await PlacementDecisionStore.writesSettled(sharedSurfaceArtifactStore);
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
        placementFixtureResponse(sentPlacementRequest(request.bodyBytes))
            .canonicalBytes,
        200));
    final resolver = _resolver(registry, fixture.request.mounts.first);
    expect(await resolver.fresh(resolver.storeKey, sendAssignmentKey: false),
        isNotNull);
    await PlacementDecisionStore.writesSettled(sharedSurfaceArtifactStore);
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
          placementFixtureResponse(sentPlacementRequest(request.bodyBytes))
              .canonicalBytes,
          200);
    }, isCurrent: () => current);
    final resolver = _resolver(registry, fixture.request.mounts.first);
    final resolving =
        resolver.fresh(resolver.storeKey, sendAssignmentKey: false);
    await store.decisionReadStarted.future;
    current = false;
    store.release.complete();
    // The answer was verified before the retirement; its write is refused.
    await resolving;
    await PlacementDecisionStore.writesSettled(sharedSurfaceArtifactStore);
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
          placementFixtureResponse(sentPlacementRequest(request.bodyBytes))
              .canonicalBytes,
          200);
    }, now: () => now);
    final resolver = _resolver(registry, fixture.request.mounts.first);
    expect(await resolver.fresh(resolver.storeKey, sendAssignmentKey: false),
        isNotNull);
    await PlacementDecisionStore.writesSettled(sharedSurfaceArtifactStore);
    now = now.subtract(const Duration(seconds: 1));
    expect(await resolver.bestLocal(resolver.storeKey), isNull);
    expect(requests, 1);
  });
}

SurfaceDeliveryObservationCell _cell(Future<String?> build,
        {Future<int?>? os}) =>
    SurfaceDeliveryObservationCell(() => readSurfaceDeliveryObservations(
        buildNumberSource: () => build,
        osVersionSource: (_) => os ?? Future.value(34)));

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
      baseUrl: origin,
      apiKey: credential,
      httpClient: MockClient((request) async =>
          placementFixtureArtifact(request) ?? await respond(request)));
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
