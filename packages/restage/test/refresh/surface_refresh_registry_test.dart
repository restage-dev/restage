import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/refresh/surface_refresh_registry.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';

import '../support/placement_delivery_fixture.dart';

final class _RecordingChannel implements SurfaceUpdateChannel {
  final controller = StreamController<SurfaceUpdate>.broadcast(sync: true);
  final watched = <SurfaceRef>[];
  var cancelled = 0;

  @override
  Stream<SurfaceUpdate> watch(SurfaceRef surface) {
    watched.add(surface);
    late final StreamController<SurfaceUpdate> out;
    StreamSubscription<SurfaceUpdate>? sub;
    out = StreamController<SurfaceUpdate>(
      onListen: () {
        sub = controller.stream
            .where((u) => u.surface == surface)
            .listen(out.add);
      },
      onCancel: () {
        cancelled++;
        return sub?.cancel();
      },
    );
    return out.stream;
  }
}

final class _ThrowingChannel implements SurfaceUpdateChannel {
  var watchCalls = 0;

  @override
  Stream<SurfaceUpdate> watch(SurfaceRef surface) {
    watchCalls++;
    throw StateError('broken channel');
  }
}

final class _RecordingDeliveryChannel implements DeliveryUpdateChannel {
  final controller =
      StreamController<DeliveryPolicyScopeV1>.broadcast(sync: true);
  final surfaceChannel = _RecordingChannel();
  final activity = <({bool opened, DeliveryPolicyScopeV1 scope})>[];
  final bindings = <({
    DeliveryPolicyScopeV1 scope,
    PlacementDeliveryWatchV1? watch,
    Future<PlacementRefreshProbeV1> Function()? probe,
  })>[];
  final _active = <DeliveryPolicyScopeV1, int>{};

  Set<DeliveryPolicyScopeV1> get activeScopes => _active.keys.toSet();

  @override
  Stream<SurfaceUpdate> watch(SurfaceRef surface) =>
      surfaceChannel.watch(surface);

  @override
  Stream<DeliveryPolicyScopeV1> watchDelivery(
    DeliveryPolicyScopeV1 scope, {
    PlacementDeliveryWatchV1? watch,
    Future<PlacementRefreshProbeV1> Function()? reconnectProbe,
  }) {
    activity.add((opened: true, scope: scope));
    bindings.add((scope: scope, watch: watch, probe: reconnectProbe));
    late final StreamController<DeliveryPolicyScopeV1> out;
    StreamSubscription<DeliveryPolicyScopeV1>? sub;
    out = StreamController<DeliveryPolicyScopeV1>(onListen: () {
      _active.update(scope, (count) => count + 1, ifAbsent: () => 1);
      sub = controller.stream
          .where((changed) => changed == scope)
          .listen(out.add);
    }, onCancel: () {
      activity.add((opened: false, scope: scope));
      final remaining = _active[scope]! - 1;
      if (remaining == 0) {
        _active.remove(scope);
      } else {
        _active[scope] = remaining;
      }
      return sub?.cancel();
    });
    return out.stream;
  }

  Future<void> close() async {
    await controller.close();
    await surfaceChannel.controller.close();
  }
}

DeliveryPolicyScopeV1 _surfaceScope(
  PublicPlacementDeliveryV1 base,
  String id, {
  DeliveryFamilySelectorV1 family = const DeliveryFamilySelectorV1.general(),
}) =>
    DeliveryPolicyScopeV1(
      root: DeliveryRootIdentityV1.surface(PublishedSurfaceIdentityV1(
          target: base.mount.placement.target, surfaceId: SurfaceId(id))),
      family: family,
    );

PublicPlacementDeliveryV1 _delivery({
  String surfaceId = 'surface.v1.a',
  int version = 1,
  int policyRevision = 1,
  String? bindingDigest,
  Iterable<DeliveryPolicyScopeV1> extraDependencies = const [],
}) {
  final base = (readPlacementDeliveryFixture().response.decisions.first
          as PlacementBatchAvailableV1)
      .publicDelivery;
  final child =
      _surfaceScope(base, surfaceId, family: base.selectedSurface.family);
  final surface = DeliverySurfaceReferenceV1(
      surfaceIdentity: child.root.surface!, family: child.family);
  final publication = DeliveryPublicationReferenceV1(
      surface: surface,
      publishedVersion: version,
      payloadFormatVersion: base.actualPublication.payloadFormatVersion,
      contentHash: base.actualPublication.contentHash,
      publicationBindingRef:
          bindingDigest == null ? null : _binding(bindingDigest));
  final path = PublicDeliveryDecisionPathV1(steps: [
    base.path.steps.first,
    PublicDeliveryDecisionStepV1(
        scope: child, source: PublicDeliverySelectionSourceV1.ownerDefault),
  ], actualPublication: publication);
  final policyDigest =
      CanonicalDigest(policyRevision.toString().padLeft(64, '0'));
  final validity = DeliveryCacheValidityV1.fromJson({
    ...base.cacheValidity.toJson(),
    'selectionIdentityDigest': path.selectionIdentityDigest.hex,
    'policySelections': [
      DeliveryPolicyDocumentSelectionV1(
              policyRevision: DeliveryPolicyRevisionRefV1(
                  scope: child,
                  ordinal: policyRevision,
                  canonicalPolicyDigest: policyDigest,
                  revisionId: 'policy.v1.child-$policyRevision'),
              documentRef: ExactRoutingDocumentRefV1(
                  schemaVersion: 2, canonicalDigest: policyDigest))
          .toJson(),
    ],
  });
  return PublicPlacementDeliveryV1(
      mount: base.mount,
      path: path,
      selectedSurface: surface,
      actualPublication: publication,
      fitRequirement: base.fitRequirement,
      cacheValidity: validity,
      dependencyClosure: {
        ...path.steps.map((step) => step.scope),
        ...extraDependencies,
      });
}

MeasurementPublicationBindingReferenceV1 _binding(String digest) {
  final declaredBytes = CanonicalDigest('a' * 64);
  return MeasurementPublicationBindingReferenceV1(
    publicationAuthorityReference: RegisteredPublicationAuthorityReferenceV1(
      authorityId:
          MeasurementPublicationAuthorityId('restage-surface-publication.v1'),
      externalPublicationAuthorityRef: 'mpa1.${'e' * 32}',
      candidateReference: MeasurementPublicationCandidateReferenceV1(
        candidateDigest: CanonicalDigest('1' * 64),
        selectedPublicationManifestDigest: CanonicalDigest('2' * 64),
        declaredArtifactBytesDigest: declaredBytes,
        assembledPublicationUploadDigest: CanonicalDigest('3' * 64),
        measurementPublicationDraftDigest: CanonicalDigest('4' * 64),
      ),
      immutablePublicationDigest: CanonicalDigest('5' * 64),
      declaredArtifactBytesDigest: declaredBytes,
    ),
    bindingDigest: CanonicalDigest(digest * 64),
  );
}

PlacementRefreshStateV1 _state(PublicPlacementDeliveryV1 delivery) => (
      mount: delivery.mount,
      decisionIdentityDigest: delivery.publicProjectionDigest,
      dependencies: delivery.dependencyClosure,
    );

PlacementDeliveryWatchV1 _watchFor(PublicPlacementDeliveryV1 delivery,
        {String digest = 'a', String tag = 'first'}) =>
    PlacementDeliveryWatchV1(
      decisionIdentityDigest: CanonicalDigest(digest * 64),
      channels: [
        for (final (index, scope) in delivery.dependencyClosure.indexed)
          PlacementDeliveryWatchChannelV1(
            scope: scope,
            token: 'v2.ABCDEFGH.2000000000000.'
                '${base64UrlEncode(utf8.encode('$tag-$index')).replaceAll('=', '')}.'
                '${base64UrlEncode(List.filled(32, 1)).replaceAll('=', '')}',
          ),
      ],
    );

SurfaceRefreshHandle _handle(
  String slug, {
  Set<SurfaceRefreshTrigger> triggers = const {},
  bool Function()? canSwap,
  int? Function()? renderedVersion,
  bool stampable = false,
  required List<String> refreshed,
}) =>
    SurfaceRefreshHandle(
      surface: SurfaceRef(surfaceType: 'paywall', slug: slug),
      triggers: triggers,
      canSwap: canSwap ?? () => true,
      renderedVersion: renderedVersion,
      stampable: stampable,
      refresh: () async => refreshed.add(slug),
    );

void _configureStampRpc(
  Map<String, int?> versionBySlug, {
  Map<String, http.Response>? responseBySlug,
  void Function()? onStampRequest,
  bool? requiresResolution,
}) {
  Restage.debugRestageRpcClient = RestageRpcClient(
    baseUrl: 'https://example.com',
    apiKey: 'rs_pk_test',
    httpClient: MockClient((request) async {
      if (request.url.path == '/sdk/v1/surface-stamp') {
        onStampRequest?.call();
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final response = responseBySlug?[body['surfaceSlug']];
        if (response != null) return response;
        final version = versionBySlug[body['surfaceSlug']];
        if (version == null) {
          return http.Response('{"error":"unavailable"}', 404);
        }
        return http.Response(
          jsonEncode({
            'version': version,
            if (requiresResolution != null)
              'requiresResolution': requiresResolution,
          }),
          200,
        );
      }
      return http.Response('{"entitlements":[]}', 200);
    }),
  );
}

void main() {
  tearDown(() {
    SurfaceRefreshRegistry.instance.debugReset();
    Restage.debugReset();
  });

  test('accepted watch associations and reconnect inputs remain per decision',
      () async {
    final channel = _RecordingDeliveryChannel();
    addTearDown(channel.close);
    Restage.configure(apiKey: 'rs_pk_test', updateChannel: channel);
    final delivery = _delivery();
    final firstWatch = _watchFor(delivery);
    final secondWatch = _watchFor(delivery, digest: 'b', tag: 'second');
    var pendingDigest = firstWatch.decisionIdentityDigest;
    PlacementRefreshStateV1? probed;
    SurfaceRefreshRegistry.instance.register(SurfaceRefreshHandle(
      surface: const SurfaceRef(surfaceType: 'general', slug: 'original'),
      triggers: {SurfaceRefreshTrigger.updateChannel},
      canSwap: () => true,
      placementState: () => (
        mount: delivery.mount,
        decisionIdentityDigest: pendingDigest,
        dependencies: delivery.dependencyClosure,
      ),
      placementWatch: () => firstWatch,
      probePlacement: (state) async {
        probed = state;
        return PlacementRefreshProbeV1.unchanged(state.decisionIdentityDigest,
            watch: firstWatch);
      },
      refresh: () async {},
    ));
    SurfaceRefreshRegistry.instance.register(SurfaceRefreshHandle(
      surface: const SurfaceRef(surfaceType: 'general', slug: 'original'),
      triggers: {SurfaceRefreshTrigger.updateChannel},
      canSwap: () => true,
      placementState: () => (
        mount: delivery.mount,
        decisionIdentityDigest: secondWatch.decisionIdentityDigest,
        dependencies: delivery.dependencyClosure,
      ),
      placementWatch: () => secondWatch,
      refresh: () async {},
    ));
    final count = delivery.dependencyClosure.length;
    expect(channel.bindings.take(count).map((binding) => binding.watch),
        everyElement(firstWatch));
    expect(channel.bindings.skip(count).map((binding) => binding.watch),
        everyElement(secondWatch));
    pendingDigest = CanonicalDigest('c' * 64);
    final renewed =
        await channel.bindings.first.probe!() as PlacementRefreshUnchangedV1;
    expect(probed!.decisionIdentityDigest, firstWatch.decisionIdentityDigest);
    expect(probed!.dependencies, delivery.dependencyClosure);
    expect(renewed.watch, firstWatch);
  });

  test('watch digest and complete closure must match the accepted decision',
      () async {
    final channel = _RecordingDeliveryChannel();
    addTearDown(channel.close);
    Restage.configure(apiKey: 'rs_pk_test', updateChannel: channel);
    final original = _delivery();
    final skipped = _surfaceScope(original, 'surface.v1.skipped');
    final accepted = _delivery(extraDependencies: [skipped]);
    var supplied = _watchFor(original);
    var digest = supplied.decisionIdentityDigest;
    final handle = SurfaceRefreshHandle(
      surface: const SurfaceRef(surfaceType: 'general', slug: 'original'),
      triggers: {SurfaceRefreshTrigger.updateChannel},
      canSwap: () => true,
      placementState: () => (
        mount: accepted.mount,
        decisionIdentityDigest: digest,
        dependencies: accepted.dependencyClosure,
      ),
      placementWatch: () => supplied,
      refresh: () async {},
    );
    SurfaceRefreshRegistry.instance.register(handle);
    expect(
        channel.bindings.map((binding) => binding.watch), everyElement(isNull));
    supplied = _watchFor(accepted, digest: 'b');
    digest = CanonicalDigest('c' * 64);
    SurfaceRefreshRegistry.instance.acceptedPlacementChanged(handle);
    expect(
        channel.bindings.map((binding) => binding.watch), everyElement(isNull));
    expect(channel.activeScopes, accepted.dependencyClosure);
  });

  test(
      'resume compares dependency and held-authority digest beyond public projection',
      () async {
    final channel = _RecordingDeliveryChannel();
    addTearDown(channel.close);
    Restage.configure(apiKey: 'rs_pk_test', updateChannel: channel);
    final delivery = _delivery();
    var acceptedWatch = _watchFor(delivery);
    final updatedWatch = _watchFor(delivery, digest: 'b', tag: 'updated');
    var refreshes = 0;
    late final SurfaceRefreshHandle handle;
    handle = SurfaceRefreshHandle(
      surface: const SurfaceRef(surfaceType: 'general', slug: 'original'),
      triggers: {
        SurfaceRefreshTrigger.appResume,
        SurfaceRefreshTrigger.updateChannel
      },
      canSwap: () => true,
      placementState: () => (
        mount: delivery.mount,
        decisionIdentityDigest: acceptedWatch.decisionIdentityDigest,
        dependencies: delivery.dependencyClosure,
      ),
      placementWatch: () => acceptedWatch,
      probePlacement: (_) async => PlacementRefreshProbeV1.unchanged(
          updatedWatch.decisionIdentityDigest,
          watch: updatedWatch),
      refresh: () async {
        refreshes++;
        acceptedWatch = updatedWatch;
        SurfaceRefreshRegistry.instance.acceptedPlacementChanged(handle);
      },
    );
    SurfaceRefreshRegistry.instance.register(handle);
    final publicDigest = delivery.publicProjectionDigest;
    SurfaceRefreshRegistry.instance.onAppBackgrounded();
    await SurfaceRefreshRegistry.instance.onAppResumed();
    expect(refreshes, 1);
    expect(delivery.publicProjectionDigest, publicDigest);
    expect(acceptedWatch.decisionIdentityDigest,
        updatedWatch.decisionIdentityDigest);
    expect(channel.bindings.last.watch, updatedWatch);
    expect(channel.activeScopes, delivery.dependencyClosure);
    await SurfaceRefreshRegistry.instance.onAppResumed();
    expect(refreshes, 1);
  });

  test(
      'every canonical dependency invalidates and resolves the accepted decision',
      () async {
    final channel = _RecordingDeliveryChannel();
    addTearDown(channel.close);
    Restage.configure(apiKey: 'rs_pk_test', updateChannel: channel);
    final base = _delivery();
    final skipped = _surfaceScope(base, 'surface.v1.skipped');
    final skippedScreen = _surfaceScope(base, 'surface.v1.skipped',
        family: DeliveryFamilySelectorV1.screenContract(contractVersion: 7));
    final future = _surfaceScope(base, 'surface.v1.future');
    final extras = [skipped, skippedScreen, future];
    var accepted = _delivery(extraDependencies: extras);
    var invalidations = 0;
    late final SurfaceRefreshHandle handle;
    handle = SurfaceRefreshHandle(
      surface: const SurfaceRef(surfaceType: 'general', slug: 'original'),
      triggers: {SurfaceRefreshTrigger.updateChannel},
      canSwap: () => true,
      placementState: () => _state(accepted),
      invalidatePlacement: () async => invalidations++,
      refresh: () async {
        accepted = _delivery(
            version: accepted.actualPublication.publishedVersion + 1,
            extraDependencies: extras);
        SurfaceRefreshRegistry.instance.acceptedPlacementChanged(handle);
      },
    );
    SurfaceRefreshRegistry.instance.register(handle);
    expect(channel.activeScopes, accepted.dependencyClosure);
    expect(channel.surfaceChannel.watched, isEmpty);
    for (final dependency in List.of(accepted.dependencyClosure)) {
      final before = accepted.publicProjectionDigest;
      channel.controller.add(dependency);
      await Future<void>.delayed(Duration.zero);
      expect(accepted.publicProjectionDigest, isNot(before));
      expect(channel.activeScopes, accepted.dependencyClosure);
    }
    expect(invalidations, 5);
    expect(accepted.actualPublication.publishedVersion, 6);
  });

  test('resume follows A v1 to B v1 to B v2 while default A remains v1',
      () async {
    final channel = _RecordingDeliveryChannel();
    addTearDown(channel.close);
    Restage.configure(apiKey: 'rs_pk_test', updateChannel: channel);
    _configureStampRpc({'original': 1});
    final a = _delivery();
    final b1 = _delivery(surfaceId: 'surface.v1.b');
    final b2 = _delivery(surfaceId: 'surface.v1.b', version: 2);
    var accepted = a;
    var remote = b1;
    final resolved = <PublicPlacementDeliveryV1>[];
    late final SurfaceRefreshHandle handle;
    handle = SurfaceRefreshHandle(
      surface: const SurfaceRef(surfaceType: 'general', slug: 'original'),
      triggers: {SurfaceRefreshTrigger.updateChannel},
      canSwap: () => true,
      stampable: true,
      renderedVersion: () => accepted.actualPublication.publishedVersion,
      placementState: () => _state(accepted),
      probePlacement: (rendered) async {
        expect(
            rendered.decisionIdentityDigest, accepted.publicProjectionDigest);
        return PlacementRefreshProbeV1.unchanged(remote.publicProjectionDigest);
      },
      refresh: () async {
        accepted = remote;
        resolved.add(accepted);
        SurfaceRefreshRegistry.instance.acceptedPlacementChanged(handle);
      },
    );
    SurfaceRefreshRegistry.instance.register(handle);
    SurfaceRefreshRegistry.instance.onAppBackgrounded();
    await SurfaceRefreshRegistry.instance.onAppResumed();
    expect(accepted.actualPublication, b1.actualPublication);
    expect(channel.activeScopes, b1.dependencyClosure);
    expect(a.actualPublication.publishedVersion, 1);
    remote = b2;
    SurfaceRefreshRegistry.instance.onAppBackgrounded();
    await SurfaceRefreshRegistry.instance.onAppResumed();
    expect(accepted.actualPublication, b2.actualPublication);
    expect(channel.activeScopes, b2.dependencyClosure);
    expect(resolved, [b1, b2]);
    await SurfaceRefreshRegistry.instance.reload();
    expect(resolved, [b1, b2]);
  });

  test(
      'equal publication versions retain changed binding and child policy identity',
      () async {
    final channel = _RecordingDeliveryChannel();
    addTearDown(channel.close);
    Restage.configure(apiKey: 'rs_pk_test', updateChannel: channel);
    final original = _delivery(bindingDigest: 'b');
    var accepted = original;
    var remote = _delivery(bindingDigest: 'c');
    late final SurfaceRefreshHandle handle;
    handle = SurfaceRefreshHandle(
      surface: const SurfaceRef(surfaceType: 'general', slug: 'original'),
      triggers: {SurfaceRefreshTrigger.appResume},
      canSwap: () => true,
      placementState: () => _state(accepted),
      probePlacement: (_) async =>
          PlacementRefreshProbeV1.unchanged(remote.publicProjectionDigest),
      refresh: () async {
        accepted = remote;
        SurfaceRefreshRegistry.instance.acceptedPlacementChanged(handle);
      },
    );
    SurfaceRefreshRegistry.instance.register(handle);
    await SurfaceRefreshRegistry.instance.onAppResumed();
    expect(accepted.actualPublication.publishedVersion, 1);
    expect(accepted.actualPublication.publicationBindingRef, _binding('c'));
    final boundPublication = accepted.actualPublication;
    remote = _delivery(bindingDigest: 'c', policyRevision: 2);
    await SurfaceRefreshRegistry.instance.onAppResumed();
    expect(accepted.actualPublication, boundPublication);
    expect(
        accepted.cacheValidity.policySelections.single.policyRevision.ordinal,
        2);
    expect(accepted.publicProjectionDigest, remote.publicProjectionDigest);
    expect(accepted.publicProjectionDigest,
        isNot(original.publicProjectionDigest));
  });

  test('a skipped child becoming fitting replaces the previous winning child',
      () async {
    final channel = _RecordingDeliveryChannel();
    addTearDown(channel.close);
    Restage.configure(apiKey: 'rs_pk_test', updateChannel: channel);
    final base = _delivery();
    final firstScope = _surfaceScope(base, 'surface.v1.first',
        family: base.selectedSurface.family);
    final second = _delivery(
        surfaceId: 'surface.v1.second', extraDependencies: [firstScope]);
    var accepted = second;
    final first = _delivery(surfaceId: 'surface.v1.first');
    late final SurfaceRefreshHandle handle;
    handle = SurfaceRefreshHandle(
      surface: const SurfaceRef(surfaceType: 'general', slug: 'original'),
      triggers: {SurfaceRefreshTrigger.updateChannel},
      canSwap: () => true,
      placementState: () => _state(accepted),
      refresh: () async {
        accepted = first;
        SurfaceRefreshRegistry.instance.acceptedPlacementChanged(handle);
      },
    );
    SurfaceRefreshRegistry.instance.register(handle);
    expect(channel.activeScopes, second.dependencyClosure);
    channel.controller.add(firstScope);
    await Future<void>.delayed(Duration.zero);
    expect(accepted.actualPublication, first.actualPublication);
    expect(channel.activeScopes, first.dependencyClosure);
  });

  test('push invalidates cache before a locked presentation gate', () async {
    final channel = _RecordingDeliveryChannel();
    addTearDown(channel.close);
    Restage.configure(apiKey: 'rs_pk_test', updateChannel: channel);
    final accepted = _delivery();
    var cached = accepted;
    var cacheAvailable = true;
    var gateChecked = false;
    var refreshes = 0;
    final handle = SurfaceRefreshHandle(
      surface: const SurfaceRef(surfaceType: 'general', slug: 'original'),
      triggers: {SurfaceRefreshTrigger.updateChannel},
      placementState: () => _state(accepted),
      invalidatePlacement: () async {
        expect(cached, accepted);
        cacheAvailable = false;
      },
      canSwap: () {
        expect(cacheAvailable, isFalse);
        gateChecked = true;
        return false;
      },
      refresh: () async => refreshes++,
    );
    SurfaceRefreshRegistry.instance.register(handle);
    channel.controller.add(accepted.dependencyClosure.first);
    await Future<void>.delayed(Duration.zero);
    expect(gateChecked, isTrue);
    expect(cacheAvailable, isFalse);
    expect(refreshes, 0);
    expect(accepted.actualPublication, cached.actualPublication);
  });

  test('new dependencies open before old watches are retired', () async {
    final channel = _RecordingDeliveryChannel();
    addTearDown(channel.close);
    Restage.configure(apiKey: 'rs_pk_test', updateChannel: channel);
    var accepted = _delivery();
    final handle = SurfaceRefreshHandle(
      surface: const SurfaceRef(surfaceType: 'general', slug: 'original'),
      triggers: {SurfaceRefreshTrigger.updateChannel},
      canSwap: () => true,
      placementState: () => _state(accepted),
      refresh: () async {},
    );
    SurfaceRefreshRegistry.instance.register(handle);
    final oldCount = channel.activity.length;
    accepted = _delivery(surfaceId: 'surface.v1.b');
    SurfaceRefreshRegistry.instance.acceptedPlacementChanged(handle);
    final transition = channel.activity.skip(oldCount).toList();
    expect(
        transition.take(accepted.dependencyClosure.length),
        everyElement(predicate<({bool opened, DeliveryPolicyScopeV1 scope})>(
            (event) => event.opened)));
    expect(
        transition.skip(accepted.dependencyClosure.length),
        everyElement(predicate<({bool opened, DeliveryPolicyScopeV1 scope})>(
            (event) => !event.opened)));
    expect(channel.activeScopes, accepted.dependencyClosure);
  });

  test(
      'pending decisions do not replace accepted watch state and inputs are frozen',
      () async {
    final channel = _RecordingDeliveryChannel();
    addTearDown(channel.close);
    Restage.configure(apiKey: 'rs_pk_test', updateChannel: channel);
    final accepted = _delivery();
    final mutableScopes = accepted.dependencyClosure.toSet();
    var pending = _delivery(surfaceId: 'surface.v1.pending');
    PlacementRefreshStateV1? probed;
    final handle = SurfaceRefreshHandle(
      surface: const SurfaceRef(surfaceType: 'general', slug: 'original'),
      triggers: {SurfaceRefreshTrigger.updateChannel},
      canSwap: () => true,
      placementState: () => (
        mount: accepted.mount,
        decisionIdentityDigest: accepted.publicProjectionDigest,
        dependencies: mutableScopes,
      ),
      probePlacement: (state) async {
        probed = state;
        return PlacementRefreshProbeV1.unchanged(state.decisionIdentityDigest);
      },
      refresh: () async => pending = _delivery(surfaceId: 'surface.v1.other'),
    );
    SurfaceRefreshRegistry.instance.register(handle);
    mutableScopes.clear();
    await SurfaceRefreshRegistry.instance.reload();
    expect(probed!.dependencies, accepted.dependencyClosure);
    expect(() => probed!.dependencies.clear(), throwsUnsupportedError);
    expect(channel.activeScopes, accepted.dependencyClosure);
    expect(pending.selectedSurface, isNot(accepted.selectedSurface));
  });

  test('a retired dependency callback cannot refresh the replacement decision',
      () async {
    final channel = _RecordingDeliveryChannel();
    addTearDown(channel.close);
    Restage.configure(apiKey: 'rs_pk_test', updateChannel: channel);
    final invalidating = Completer<void>();
    var accepted = _delivery();
    var refreshes = 0;
    final handle = SurfaceRefreshHandle(
      surface: const SurfaceRef(surfaceType: 'general', slug: 'original'),
      triggers: {SurfaceRefreshTrigger.updateChannel},
      canSwap: () => true,
      placementState: () => _state(accepted),
      invalidatePlacement: () => invalidating.future,
      refresh: () async => refreshes++,
    );
    SurfaceRefreshRegistry.instance.register(handle);
    channel.controller.add(accepted.dependencyClosure.first);
    await Future<void>.delayed(Duration.zero);
    accepted = _delivery(surfaceId: 'surface.v1.b');
    SurfaceRefreshRegistry.instance.acceptedPlacementChanged(handle);
    invalidating.complete();
    await Future<void>.delayed(Duration.zero);
    expect(refreshes, 0);
    expect(channel.activeScopes, accepted.dependencyClosure);
  });

  test('a probe for an older decision cannot resolve after replacement',
      () async {
    final channel = _RecordingDeliveryChannel();
    addTearDown(channel.close);
    Restage.configure(apiKey: 'rs_pk_test', updateChannel: channel);
    final probe = Completer<PlacementRefreshProbeV1>();
    var accepted = _delivery();
    var refreshes = 0;
    final handle = SurfaceRefreshHandle(
      surface: const SurfaceRef(surfaceType: 'general', slug: 'original'),
      triggers: {SurfaceRefreshTrigger.updateChannel},
      canSwap: () => true,
      placementState: () => _state(accepted),
      probePlacement: (_) => probe.future,
      refresh: () async => refreshes++,
    );
    SurfaceRefreshRegistry.instance.register(handle);
    final pending = SurfaceRefreshRegistry.instance.reload();
    accepted = _delivery(surfaceId: 'surface.v1.b');
    SurfaceRefreshRegistry.instance.acceptedPlacementChanged(handle);
    probe.complete(const PlacementRefreshProbeV1.requiresResolution());
    await pending;
    expect(refreshes, 0);
    expect(channel.activeScopes, accepted.dependencyClosure);
  });

  test(
      'placement probes resolve unknown authority and retain rate-limited render',
      () async {
    var accepted = _delivery();
    final original = accepted;
    var result = const PlacementRefreshProbeV1.unavailable();
    var refreshes = 0;
    late final SurfaceRefreshHandle handle;
    handle = SurfaceRefreshHandle(
      surface: const SurfaceRef(surfaceType: 'general', slug: 'original'),
      triggers: {},
      canSwap: () => true,
      stampable: true,
      renderedVersion: () => 1,
      placementState: () => _state(accepted),
      probePlacement: (_) async => result,
      refresh: () async {
        accepted = _delivery(surfaceId: 'surface.v1.b');
        refreshes++;
        SurfaceRefreshRegistry.instance.acceptedPlacementChanged(handle);
      },
    );
    SurfaceRefreshRegistry.instance.register(handle);
    result = const PlacementRefreshProbeV1.rateLimited(Duration(seconds: 7));
    await SurfaceRefreshRegistry.instance.reload();
    expect(accepted, original);
    expect(refreshes, 0);
    result = const PlacementRefreshProbeV1.unavailable();
    await SurfaceRefreshRegistry.instance.reload();
    expect(accepted.selectedSurface.surfaceIdentity.surfaceId.value,
        'surface.v1.b');
    expect(refreshes, 1);
  });

  test(
      'legacy channels watch the accepted selected surface and still probe on resume',
      () async {
    final channel = _RecordingChannel();
    addTearDown(channel.controller.close);
    Restage.configure(apiKey: 'rs_pk_test', updateChannel: channel);
    var accepted = _delivery(surfaceId: 'surface.v1.b');
    var selected = const SurfaceRef(surfaceType: 'general', slug: 'b');
    var refreshes = 0;
    var probes = 0;
    final handle = SurfaceRefreshHandle(
      surface: const SurfaceRef(surfaceType: 'general', slug: 'original'),
      triggers: {SurfaceRefreshTrigger.updateChannel},
      canSwap: () => true,
      placementState: () => _state(accepted),
      renderedSurface: () => selected,
      probePlacement: (state) async {
        probes++;
        return PlacementRefreshProbeV1.unchanged(state.decisionIdentityDigest);
      },
      refresh: () async => refreshes++,
    );
    SurfaceRefreshRegistry.instance.register(handle);
    expect(channel.watched, [selected]);
    channel.controller.add(SurfaceUpdate(selected));
    await Future<void>.delayed(Duration.zero);
    expect(refreshes, 1);
    expect(probes, 0);
    accepted = _delivery(surfaceId: 'surface.v1.c');
    selected = const SurfaceRef(surfaceType: 'general', slug: 'c');
    SurfaceRefreshRegistry.instance.acceptedPlacementChanged(handle);
    expect(channel.watched.last, selected);
    await SurfaceRefreshRegistry.instance.onAppResumed();
    expect(probes, 1);
    expect(refreshes, 1);
  });

  test(
      'background and disposal fence pending dependency work and new registration',
      () async {
    final channel = _RecordingDeliveryChannel();
    addTearDown(channel.close);
    Restage.configure(apiKey: 'rs_pk_test', updateChannel: channel);
    final accepted = _delivery();
    final gate = Completer<void>();
    var refreshes = 0;
    final handle = SurfaceRefreshHandle(
      surface: const SurfaceRef(surfaceType: 'general', slug: 'original'),
      triggers: {SurfaceRefreshTrigger.updateChannel},
      canSwap: () => true,
      placementState: () => _state(accepted),
      invalidatePlacement: () => gate.future,
      refresh: () async => refreshes++,
    );
    SurfaceRefreshRegistry.instance.register(handle);
    channel.controller.add(accepted.dependencyClosure.first);
    SurfaceRefreshRegistry.instance.onAppBackgrounded();
    gate.complete();
    await Future<void>.delayed(Duration.zero);
    expect(refreshes, 0);
    expect(channel.activeScopes, isEmpty);
    SurfaceRefreshRegistry.instance.unregister(handle);
    SurfaceRefreshRegistry.instance.register(handle);
    expect(channel.activeScopes, isEmpty);
    await SurfaceRefreshRegistry.instance.onAppResumed();
    expect(channel.activeScopes, accepted.dependencyClosure);
    expect(refreshes, 1);
    SurfaceRefreshRegistry.instance.unregister(handle);
    channel.controller.add(accepted.dependencyClosure.first);
    await Future<void>.delayed(Duration.zero);
    expect(refreshes, 1);
  });

  testWidgets(
      'local validity alarm remains offline and handles one expired decision',
      (tester) async {
    var now = DateTime.utc(2026, 10, 4, 12);
    final boundary = now.add(const Duration(seconds: 2));
    final registry = SurfaceRefreshRegistry(now: () => now);
    addTearDown(registry.debugReset);
    var invalidations = 0;
    var probes = 0;
    final accepted = _delivery();
    final handle = SurfaceRefreshHandle(
      surface: const SurfaceRef(surfaceType: 'general', slug: 'original'),
      triggers: {},
      canSwap: () => true,
      placementState: () => _state(accepted),
      probePlacement: (_) async {
        probes++;
        return const PlacementRefreshProbeV1.unavailable();
      },
      localValidity: () => now.isBefore(boundary),
      localBoundary: () => boundary,
      invalidateLocal: () async => invalidations++,
      refresh: () async => fail('local expiry must use the existing callback'),
    );
    registry.register(handle);
    now = boundary;
    await tester.pump(const Duration(seconds: 2));
    expect(invalidations, 1);
    await registry.checkLocalValidity();
    await tester.pump(const Duration(seconds: 30));
    expect(invalidations, 1);
    expect(probes, 0);
  });

  test('reload() hits all swappable handles regardless of triggers', () async {
    final refreshed = <String>[];
    final a = _handle('a', refreshed: refreshed);
    final b = _handle('b', canSwap: () => false, refreshed: refreshed);
    SurfaceRefreshRegistry.instance
      ..register(a)
      ..register(b);
    await SurfaceRefreshRegistry.instance.reload();
    expect(refreshed, ['a']); // b gated out by canSwap
    await SurfaceRefreshRegistry.instance.reload(slug: 'a');
    expect(refreshed, ['a', 'a']);
  });

  test(
      'onAppResumed() sweeps ambient-triggered handles but skips untriggered '
      'ones (appResume and updateChannel are both swept)', () async {
    final refreshed = <String>[];
    SurfaceRefreshRegistry.instance
      ..register(_handle('resume',
          triggers: {SurfaceRefreshTrigger.appResume}, refreshed: refreshed))
      ..register(_handle('static', refreshed: refreshed));
    await SurfaceRefreshRegistry.instance.onAppResumed();
    expect(refreshed, ['resume']);
  });

  test(
      'register subscribes updateChannel-triggered handles; emissions gate '
      'through canSwap; unregister cancels', () async {
    final channel = _RecordingChannel();
    Restage.configure(apiKey: 'rs_pk_test', updateChannel: channel);
    final refreshed = <String>[];
    var swappable = true;
    final h = _handle('live',
        triggers: {SurfaceRefreshTrigger.updateChannel},
        canSwap: () => swappable,
        refreshed: refreshed);
    SurfaceRefreshRegistry.instance.register(h);
    expect(channel.watched,
        [const SurfaceRef(surfaceType: 'paywall', slug: 'live')]);

    channel.controller.add(
        const SurfaceUpdate(SurfaceRef(surfaceType: 'paywall', slug: 'live')));
    await Future<void>.delayed(Duration.zero);
    expect(refreshed, ['live']);

    swappable = false;
    channel.controller.add(
        const SurfaceUpdate(SurfaceRef(surfaceType: 'paywall', slug: 'live')));
    await Future<void>.delayed(Duration.zero);
    expect(refreshed, ['live']); // gated

    SurfaceRefreshRegistry.instance.unregister(h);
    expect(channel.cancelled, 1);
    swappable = true;
    channel.controller.add(
        const SurfaceUpdate(SurfaceRef(surfaceType: 'paywall', slug: 'live')));
    await Future<void>.delayed(Duration.zero);
    expect(refreshed, ['live']); // cancelled
  });

  test('onAppBackgrounded cancels update-channel subscriptions', () async {
    final channel = _RecordingChannel();
    Restage.configure(apiKey: 'rs_pk_test', updateChannel: channel);
    final refreshed = <String>[];
    SurfaceRefreshRegistry.instance.register(_handle(
      'live',
      triggers: {SurfaceRefreshTrigger.updateChannel},
      refreshed: refreshed,
    ));
    expect(channel.cancelled, 0);

    SurfaceRefreshRegistry.instance.onAppBackgrounded();
    expect(channel.cancelled, 1);

    channel.controller.add(
      const SurfaceUpdate(SurfaceRef(surfaceType: 'paywall', slug: 'live')),
    );
    await Future<void>.delayed(Duration.zero);
    expect(refreshed, isEmpty);
  });

  test('onAppResumed resubscribes update-channel handles', () async {
    final channel = _RecordingChannel();
    Restage.configure(apiKey: 'rs_pk_test', updateChannel: channel);
    final refreshed = <String>[];
    final versionBySlug = <String, int?>{'live': 1};
    _configureStampRpc(versionBySlug);
    SurfaceRefreshRegistry.instance.register(_handle(
      'live',
      triggers: {SurfaceRefreshTrigger.updateChannel},
      renderedVersion: () => 1,
      stampable: true,
      refreshed: refreshed,
    ));
    SurfaceRefreshRegistry.instance.onAppBackgrounded();

    await SurfaceRefreshRegistry.instance.onAppResumed();
    expect(channel.watched, hasLength(2));
    expect(refreshed, isEmpty);

    versionBySlug['live'] = 2;
    channel.controller.add(
      const SurfaceUpdate(SurfaceRef(surfaceType: 'paywall', slug: 'live')),
    );
    await Future<void>.delayed(Duration.zero);
    expect(refreshed, ['live']);
  });

  test('a synchronous channel failure cannot escape register or resume',
      () async {
    final channel = _ThrowingChannel();
    Restage.configure(apiKey: 'rs_pk_test', updateChannel: channel);
    final refreshed = <String>[];
    final handle = _handle(
      'live',
      triggers: {SurfaceRefreshTrigger.updateChannel},
      refreshed: refreshed,
    );

    expect(
      () => SurfaceRefreshRegistry.instance.register(handle),
      returnsNormally,
    );
    await expectLater(
      SurfaceRefreshRegistry.instance.onAppResumed(),
      completes,
    );

    expect(channel.watchCalls, 2);
    expect(refreshed, ['live']);
  });

  test('channel emissions skip the stamp probe', () async {
    final channel = _RecordingChannel();
    Restage.configure(apiKey: 'rs_pk_test', updateChannel: channel);
    var stampChecks = 0;
    _configureStampRpc(
      {'live': 1},
      onStampRequest: () => stampChecks++,
    );
    final refreshed = <String>[];
    SurfaceRefreshRegistry.instance.register(_handle(
      'live',
      triggers: {SurfaceRefreshTrigger.updateChannel},
      renderedVersion: () => 1,
      stampable: true,
      refreshed: refreshed,
    ));

    channel.controller.add(
      const SurfaceUpdate(SurfaceRef(surfaceType: 'paywall', slug: 'live')),
    );
    await Future<void>.delayed(Duration.zero);

    expect(stampChecks, 0);
    expect(refreshed, ['live']);

    await SurfaceRefreshRegistry.instance.reload(slug: 'live');
    expect(stampChecks, 1);
    expect(refreshed, ['live']);
  });

  test(
      'onAppResumed stamp-checks an update-channel handle with a changed stamp',
      () async {
    final channel = _RecordingChannel();
    Restage.configure(apiKey: 'rs_pk_test', updateChannel: channel);
    final refreshed = <String>[];
    _configureStampRpc({'changed': 2});
    SurfaceRefreshRegistry.instance.register(_handle(
      'changed',
      triggers: {SurfaceRefreshTrigger.updateChannel},
      renderedVersion: () => 1,
      stampable: true,
      refreshed: refreshed,
    ));
    SurfaceRefreshRegistry.instance.onAppBackgrounded();

    await SurfaceRefreshRegistry.instance.onAppResumed();

    expect(refreshed, ['changed']);
  });

  test(
      'onAppResumed stamp-checks an update-channel handle with an unchanged stamp',
      () async {
    final channel = _RecordingChannel();
    Restage.configure(apiKey: 'rs_pk_test', updateChannel: channel);
    final refreshed = <String>[];
    var stampChecks = 0;
    _configureStampRpc(
      {'unchanged': 1},
      onStampRequest: () => stampChecks++,
    );
    SurfaceRefreshRegistry.instance.register(_handle(
      'unchanged',
      triggers: {SurfaceRefreshTrigger.updateChannel},
      renderedVersion: () => 1,
      stampable: true,
      refreshed: refreshed,
    ));
    SurfaceRefreshRegistry.instance.onAppBackgrounded();

    await SurfaceRefreshRegistry.instance.onAppResumed();

    expect(stampChecks, 1);
    expect(refreshed, isEmpty);
  });

  test('a non-updateChannel handle opens no subscription', () async {
    final channel = _RecordingChannel();
    Restage.configure(apiKey: 'rs_pk_test', updateChannel: channel);
    SurfaceRefreshRegistry.instance
        .register(_handle('a', refreshed: <String>[]));
    expect(channel.watched, isEmpty);
  });

  test('a throwing refresh is swallowed and does not block siblings', () async {
    final refreshed = <String>[];
    SurfaceRefreshRegistry.instance
      ..register(SurfaceRefreshHandle(
        surface: const SurfaceRef(surfaceType: 'paywall', slug: 'boom'),
        triggers: const {},
        canSwap: () => true,
        refresh: () async => throw StateError('x'),
      ))
      ..register(_handle('ok', refreshed: refreshed));
    await SurfaceRefreshRegistry.instance.reload();
    expect(refreshed, ['ok']);
  });

  test('a handle whose refresh is in flight is skipped by a second producer',
      () async {
    final gate = Completer<void>();
    var calls = 0;
    final h = SurfaceRefreshHandle(
      surface: const SurfaceRef(surfaceType: 'paywall', slug: 'slow'),
      triggers: const {},
      canSwap: () => true,
      refresh: () async {
        calls++;
        await gate.future;
      },
    );
    SurfaceRefreshRegistry.instance.register(h);
    final first = SurfaceRefreshRegistry.instance.reload();
    // Second producer fires while the first refresh is still in flight.
    await SurfaceRefreshRegistry.instance.reload();
    expect(calls, 1); // re-entrancy guard skipped the second
    gate.complete();
    await first;
    // Now that it's settled, a fresh producer fires again.
    await SurfaceRefreshRegistry.instance.reload();
    expect(calls, 2);
  });

  test('matching version without requiresResolution skips refresh', () async {
    final refreshed = <String>[];
    var stampChecks = 0;
    _configureStampRpc({'same': 5}, onStampRequest: () => stampChecks++);
    SurfaceRefreshRegistry.instance.register(_handle(
      'same',
      renderedVersion: () => 5,
      stampable: true,
      refreshed: refreshed,
    ));

    await SurfaceRefreshRegistry.instance.reload();

    expect(stampChecks, 1);
    expect(refreshed, isEmpty);
  });

  test('matching version requiring a fresh decision runs refresh', () async {
    final refreshed = <String>[];
    var stampChecks = 0;
    _configureStampRpc(
      {'same': 5},
      requiresResolution: true,
      onStampRequest: () => stampChecks++,
    );
    SurfaceRefreshRegistry.instance.register(_handle(
      'same',
      renderedVersion: () => 5,
      stampable: true,
      refreshed: refreshed,
    ));

    await SurfaceRefreshRegistry.instance.reload();

    expect(stampChecks, 1);
    expect(refreshed, ['same']);
  });

  test('moved stamp runs refresh', () async {
    final refreshed = <String>[];
    _configureStampRpc({'moved': 6});
    SurfaceRefreshRegistry.instance.register(_handle(
      'moved',
      renderedVersion: () => 5,
      stampable: true,
      refreshed: refreshed,
    ));

    await SurfaceRefreshRegistry.instance.reload();

    expect(refreshed, ['moved']);
  });

  test('null stamp runs refresh', () async {
    final refreshed = <String>[];
    _configureStampRpc({'unknown': null});
    SurfaceRefreshRegistry.instance.register(_handle(
      'unknown',
      renderedVersion: () => 5,
      stampable: true,
      refreshed: refreshed,
    ));

    await SurfaceRefreshRegistry.instance.reload();

    expect(refreshed, ['unknown']);
  });

  test('a rate-limited stamp skips refresh while a 503 stamp refreshes',
      () async {
    final refreshed = <String>[];
    var stampRequests = 0;
    _configureStampRpc(
      const {},
      responseBySlug: {
        'rate-limited': http.Response(
          'not json',
          429,
          headers: {'Retry-After': '7'},
        ),
        'unavailable': http.Response('{"error":"rate_limited"}', 503),
      },
      onStampRequest: () => stampRequests++,
    );
    SurfaceRefreshRegistry.instance
      ..register(_handle(
        'rate-limited',
        renderedVersion: () => 5,
        stampable: true,
        refreshed: refreshed,
      ))
      ..register(_handle(
        'unavailable',
        renderedVersion: () => 5,
        stampable: true,
        refreshed: refreshed,
      ));

    await SurfaceRefreshRegistry.instance.reload();

    expect(stampRequests, 2);
    expect(refreshed, ['unavailable']);
  });

  test('non-null stamp with null rendered version runs refresh', () async {
    final refreshed = <String>[];
    _configureStampRpc({'versionless': 5});
    SurfaceRefreshRegistry.instance.register(_handle(
      'versionless',
      renderedVersion: () => null,
      stampable: true,
      refreshed: refreshed,
    ));

    await SurfaceRefreshRegistry.instance.reload();

    expect(refreshed, ['versionless']);
  });

  test('handle without a stamp probe runs refresh as before', () async {
    final refreshed = <String>[];
    SurfaceRefreshRegistry.instance.register(
      _handle('legacy', refreshed: refreshed),
    );

    await SurfaceRefreshRegistry.instance.reload();

    expect(refreshed, ['legacy']);
  });

  test(
      'a stampable handle with no configured service still refreshes '
      '(bundled-only path)', () async {
    final refreshed = <String>[];
    SurfaceRefreshRegistry.instance.register(_handle(
      'bundled',
      renderedVersion: () => 1,
      stampable: true,
      refreshed: refreshed,
    ));

    await SurfaceRefreshRegistry.instance.reload();

    expect(refreshed, ['bundled']);
  });
}
