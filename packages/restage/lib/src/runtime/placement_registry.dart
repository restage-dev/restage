import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:meta/meta.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';

import '../delivery/placement_decision_store.dart';
import '../delivery/raced_surface_resolver.dart';
import '../delivery/surface_artifact_store.dart';
import '../resolver/delivery_input_budget.dart';
import '../resolver/surface_assignment_key_provider.dart';
import '../resolver/surface_canonical_carrier_provider.dart';
import '../resolver/surface_delivery_observations.dart';
import '../resolver/surface_request_inputs.dart';
import '../resolver/placement_mount_resolver.dart'
    show placementCacheIsValid, PlacementDeliveryAdmission;
import '../refresh/surface_update_channel.dart';
import 'installed_widget_vocabulary.dart';
import '../restage_rpc_client/placement_delivery_adapter.dart';
import '../restage_rpc_client/restage_rpc_client.dart';
import 'placement_mount.dart';

typedef PlacementDeclaration = ({
  PlacementMountRequestV1 mount,
  SurfaceHostContractV1 host
});

/// Configuration-owned discovery over the existing RPC and artifact store.
@internal
final class PlacementRegistry {
  PlacementRegistry(
      {required this.scope,
      required this.configurationFingerprint,
      required this.client,
      required this.isCurrent,
      this.onBuildInputs,
      this.onDeclarations,
      DateTime Function()? now})
      : now = now ?? DateTime.now;

  final String scope;
  final String configurationFingerprint;
  TargetCoordinate? _storedTarget;
  TargetCoordinate? get target => client().placementTarget ?? _storedTarget;
  final RestageRpcClient Function() client;
  final bool Function() isCurrent;
  final void Function(String platform, int? buildOrdinal)? onBuildInputs;
  final void Function(List<PlacementDeclaration> declarations)? onDeclarations;
  final DateTime Function() now;
  final Map<PlacementMountRequestV1, SurfaceHostContractV1> _mounts = {};

  PlacementDecisionStore get decisions =>
      PlacementDecisionStore(scope: scope, store: sharedSurfaceArtifactStore);

  List<PlacementDeclaration> configure(
      Iterable<GeneratedPlacementDefinition> definitions) {
    final configured = <PlacementDeclaration>[];
    for (final definition in definitions) {
      definition.vocabulary.addToInstalled();
      final declaration =
          PlacementMountBinding(definition: () => definition).capture();
      _mounts[declaration.mount] = declaration.host;
      configured.add(declaration);
    }
    onDeclarations?.call(configured);
    return configured;
  }

  Future<List<PlacementDeclaration>> loadKnownMounts() async {
    try {
      final known = await decisions.knownMounts();
      if (!isCurrent()) return [];
      for (final declaration in known) {
        _mounts.putIfAbsent(declaration.mount, () => declaration.host);
      }
      onDeclarations?.call(known);
      return known;
    } on Object {
      // Startup still includes generated declarations if storage is unavailable.
      return [];
    }
  }

  void remember(PlacementDeclaration declaration) {
    if (!isCurrent()) return;
    _mounts[declaration.mount] = declaration.host;
    onDeclarations?.call([declaration]);
    decisions
        .remember(declaration.mount, declaration.host, isCurrent)
        .catchError((Object _) {});
  }

  Future<PlacementRequestContext?> capture(
      {required List<PlacementMountRequestV1> mounts,
      required bool sendAssignmentKey,
      Future<void>? keyDeadline,
      bool Function()? publicationGuard,
      SurfaceAssignmentResolutionLease? retainedLease,
      PlacementBatchModeV1 mode = PlacementBatchModeV1.mount}) async {
    final declarations =
        Map<PlacementMountRequestV1, SurfaceHostContractV1>.of(_mounts);
    if (mounts.isEmpty || !isCurrent() || !(publicationGuard?.call() ?? true)) {
      return null;
    }
    return DeliveryInputBudget.run((budget) async {
      final cell = currentSurfaceDeliveryObservationCell();
      final inputs = await SurfaceRequestInputs.gather(
          budget: budget,
          surface: mounts.first.defaultSurface?.surfaceType.value ?? 'paywall',
          slug: mounts.first.defaultSurface?.slug ?? 'placement',
          sendAssignmentKey: sendAssignmentKey,
          keyDeadline: keyDeadline);
      if (!isCurrent() ||
          !(publicationGuard?.call() ?? true) ||
          !inputs.lease.isCurrent ||
          !inputs.lease.canSend) {
        return null;
      }
      final observations = inputs.builtIns == null
          ? <String, Object?>{}
          : CanonicalJsonCodec.decode(
              base64Url.decode(base64Url.normalize(inputs.builtIns!))) as Map;
      final platform = observations['platform'] as String? ??
          normalizeDeliveryPlatform(
              isWeb: kIsWeb, targetPlatform: defaultTargetPlatform);
      if (platform == null) return null;
      onBuildInputs?.call(platform, observations['appBuildOrdinal'] as int?);
      final build = PlacementBuildContractV1(
          platform: platform,
          buildOrdinal: observations['appBuildOrdinal'] as int?,
          mounts: declarations.keys.toList(),
          contractsByHash: {
            for (final host in declarations.values) host.contentHash: host
          },
          installedCapability: inputs.installedCapability,
          installedCapabilityHash: inputs.installedCapabilityHash);
      final localNow = now();
      final clock = DeliveryLocalClockV1(localNow.timeZoneOffset.inMinutes);
      final stamp = placementInputStamp(inputs.builtIns, localNow);
      final registration = inputs.lease.registration;
      final lease = retainedLease ?? inputs.lease;
      final assignmentKey = (sendAssignmentKey || retainedLease != null) &&
              lease.isCurrent &&
              lease.assignmentsAllowed
          ? lease.assignmentKey
          : null;
      final held = assignmentKey == null
          ? <PlacementHeldAssignmentV1>[]
          : await budget
              .bound(Future.wait([
                for (final mount in mounts)
                  SurfaceCanonicalCarrierProvider.heldPlacement(
                          mount: mount, assignmentKey: assignmentKey)
                      .then((carrier) {
                    if (carrier == null) return null;
                    final assignment =
                        PresentationAssignmentCarrierV2.fromCanonicalBytes(
                            base64Url.decode(base64Url.normalize(carrier)));
                    return assignment.owner ==
                            PresentationAssignmentOwnerV2.path
                        ? PlacementHeldAssignmentV1(
                            key: mount.key,
                            hostContractHash: mount.hostContractHash,
                            retainedPathHandle: assignment.outcomeLinkCarrier)
                        : null;
                  })
              ]))
              .then((values) =>
                  values?.whereType<PlacementHeldAssignmentV1>().toList() ??
                  <PlacementHeldAssignmentV1>[]);
      final request = PlacementBatchRequestV1(
          mounts: mounts,
          buildContract: build,
          appBuildContractHash: build.appBuildContractHash,
          mode: mode,
          localClock: clock,
          heldArtifacts: client().heldPlacementArtifacts.keys.toSet(),
          sdkInstalledLibraries: inputs.sdkInstalledLibraries,
          sdkBuiltInsCanonicalBase64: inputs.builtIns,
          sdkSupportedPolicyRevisions: supportedPolicyRevisionsCarrier(),
          assignmentKey: assignmentKey,
          heldAssignments: held,
          registration: mode == PlacementBatchModeV1.refresh ||
                  !sendAssignmentKey ||
                  registration == null
              ? null
              : SurfaceRegistrationTupleV1.fromJson(registration.tuple),
          meteringKey: inputs.meteringKey,
          analyticsAnonymousId: inputs.analyticsAnonymousId);
      return PlacementRequestContext(
          request: request,
          lease: lease,
          inputStamp: stamp,
          capturedAt: localNow.toUtc(),
          isCurrent: () =>
              isCurrent() &&
              (publicationGuard?.call() ?? true) &&
              inputs.lease.isCurrent &&
              lease.isCurrent &&
              currentInstalledCapability().contentHash ==
                  inputs.installedCapabilityHash &&
              (cell == null ||
                  placementInputStamp(cell.currentBuiltInsBase64, now()) ==
                      stamp));
    });
  }

  Future<void> prefetch(Iterable<PlacementDeclaration> declarations) async {
    final roster = declarations.toList(growable: false);
    if (!isCurrent() || roster.isEmpty) return;
    final mounts =
        roster.map((declaration) => declaration.mount).toSet().toList();
    final context = await capture(
        mounts: mounts,
        sendAssignmentKey: false,
        mode: PlacementBatchModeV1.prefetch);
    if (context == null) return;
    final response = await fetch(context);
    if (response == null) return;
    for (final declaration in roster) {
      if (!context.isCurrent()) return;
      await decisions.remember(
          declaration.mount, declaration.host, context.isCurrent);
    }
  }

  /// Checks the accepted decision through the same side-effect-free batch route.
  Future<PlacementRefreshProbeV1> probe(PlacementDeliveryAdmission accepted,
      PlacementRefreshStateV1 rendered) async {
    if (accepted.refreshState?.decisionIdentityDigest !=
            rendered.decisionIdentityDigest ||
        !accepted.context.isCurrent()) {
      return const PlacementRefreshProbeV1.requiresResolution();
    }
    final context = await capture(
        mounts: accepted.context.request.mounts,
        sendAssignmentKey: false,
        retainedLease: accepted.context.lease,
        mode: PlacementBatchModeV1.refresh,
        publicationGuard: accepted.context.isCurrent);
    if (context == null) return const PlacementRefreshProbeV1.unavailable();
    Duration? retryAfter;
    final response = await client().fetchPlacements(context.request,
        publicationGuard: context.isCurrent,
        registrationLease: context.lease,
        expectedTarget: accepted.delivery.mount.placement.target,
        onRateLimited: (delay) => retryAfter = delay);
    if (retryAfter != null) {
      return PlacementRefreshProbeV1.rateLimited(retryAfter!);
    }
    if (response is PlacementBatchResolvedV1) {
      await _forgetUnprovenCarriers(context, response);
    }
    if (!context.isCurrent() ||
        response is! PlacementBatchResolvedV1 ||
        response.decisions.single is! PlacementBatchAvailableV1) {
      return const PlacementRefreshProbeV1.requiresResolution();
    }
    final decision = response.decisions.single as PlacementBatchAvailableV1;
    final watch = decision.watch;
    return watch == null
        ? const PlacementRefreshProbeV1.requiresResolution()
        : PlacementRefreshProbeV1.unchanged(watch.decisionIdentityDigest,
            watch: watch);
  }

  Future<
      ({
        PlacementBatchResolvedV1 response,
        PlacementDeliveryArtifacts artifacts
      })?> fetch(PlacementRequestContext context) async {
    final response = await client().fetchPlacements(context.request,
        publicationGuard: context.isCurrent,
        registrationLease: context.lease,
        expectedTarget: target);
    if (response is! PlacementBatchResolvedV1 || !context.isCurrent()) {
      return null;
    }
    await _forgetUnprovenCarriers(context, response);
    final artifacts = placementArtifactsFor(response);
    if (artifacts == null) return null;
    for (var index = 0; index < response.decisions.length; index++) {
      final entry = response.decisions[index];
      if (entry is! PlacementBatchAvailableV1) continue;
      if (entry.publicDelivery.assignment != null &&
          (!context.lease.assignmentsAllowed ||
              context.request.assignmentKey == null ||
              context.request.assignmentKey != context.lease.assignmentKey)) {
        continue;
      }
      final host = context.request.buildContract
          .contractsByHash[entry.descriptor.hostContractHash]!;
      if (!placementCacheIsValid(entry.publicDelivery.cacheValidity,
              now: now(), clock: context.request.localClock) ||
          !SurfaceFitEvaluator.evaluate(
                  host: host,
                  requirement: entry.publicDelivery.fitRequirement,
                  installed: context.request.buildContract.installedCapability)
              .accepted ||
          entry.artifactClosure.any((ref) {
            final document = artifacts.documents[ref]!;
            return BlobRenderCapabilityGate.evaluate(
                required: CapabilityManifest(
                    builtInFloor: document.minClient,
                    requiredLibraries: document.requiredLibraries),
                installed: context.request.buildContract
                    .installedCapability) is BlobRenderRejected;
          })) {
        continue;
      }
      final key = decisions.decisionKey(
          context.request, context.request.mounts[index], context.inputStamp,
          target: entry.descriptor.placement.target);
      try {
        final assignment = entry.publicDelivery.assignment;
        if (assignment != null) {
          await SurfaceCanonicalCarrierProvider.retainPlacement(
              mount: context.request.mounts[index],
              lease: context.lease,
              assignment: assignment);
        }
        await decisions.write(
            key,
            entry,
            artifacts,
            {
              'authenticatedConfigurationFingerprint': configurationFingerprint,
              'authenticatedDeliveryDigest':
                  entry.publicDelivery.publicProjectionDigest.hex,
              'inputStamp': context.inputStamp,
              'capturedAtMicros': context.capturedAt.microsecondsSinceEpoch,
              'assignmentKey': context.lease.assignmentKey,
              'registrationFingerprint':
                  context.lease.registration?.fingerprint,
            },
            context.isCurrent);
      } on Object {
        // A storage failure cannot prevent this verified response from rendering.
      }
    }
    return context.isCurrent()
        ? (response: response, artifacts: artifacts)
        : null;
  }

  Future<void> _forgetUnprovenCarriers(PlacementRequestContext context,
      PlacementBatchResolvedV1 response) async {
    final key = context.request.assignmentKey;
    if (key == null) return;
    for (var index = 0; index < response.decisions.length; index++) {
      final entry = response.decisions[index];
      if (entry is PlacementBatchUseFallbackV1 &&
          entry.reason == PlacementBatchRefusalReasonV1.assignmentUnavailable) {
        await SurfaceCanonicalCarrierProvider.forgetPlacement(
            mount: context.request.mounts[index], assignmentKey: key);
      }
    }
  }

  Future<
      ({
        PlacementBatchAvailableV1 decision,
        PlacementDeliveryArtifacts artifacts,
        PlacementRequestContext context
      })?> local(PlacementRequestContext context) async {
    final expectedTarget = target;
    if (!context.isCurrent()) return null;
    SurfaceAssignmentResolutionLease? storedLease;
    final response = await decisions.read(
        request: context.request,
        inputStamp: context.inputStamp,
        expectedTarget: expectedTarget,
        configurationFingerprint: configurationFingerprint,
        acceptsStored: (stored, decision) async {
          final sidecar = stored.sidecar;
          if (sidecar['inputStamp'] != context.inputStamp ||
              sidecar['capturedAtMicros'] is! int ||
              (sidecar['capturedAtMicros']! as int) >
                  now().toUtc().microsecondsSinceEpoch) {
            return false;
          }
          final mount = context.request.mounts.single;
          final identity = await storedDeliveryIdentity(
              stored: stored,
              assignment: null,
              placement: mount,
              placementAssignment: decision.publicDelivery.assignment,
              surface: mount.defaultSurface?.surfaceType.value ?? 'paywall',
              slug: mount.defaultSurface?.slug ?? mount.key.slug);
          storedLease = identity.lease;
          return identity.reusable;
        });
    if (response == null || !context.isCurrent() || storedLease == null) {
      return null;
    }
    final localContext = PlacementRequestContext(
        request: context.request,
        lease: storedLease!,
        inputStamp: context.inputStamp,
        capturedAt: context.capturedAt,
        isCurrent: () => context.isCurrent() && storedLease!.isCurrent);
    final artifacts = await assemblePlacementDeliveryArtifacts(response,
        publicationGuard: localContext.isCurrent);
    if (artifacts == null || !localContext.isCurrent()) return null;
    _storedTarget ??= response.decisions.single.descriptor.placement.target;
    return (
      decision: response.decisions.single as PlacementBatchAvailableV1,
      artifacts: artifacts,
      context: localContext
    );
  }
}

@internal
final class PlacementRequestContext {
  PlacementRequestContext(
      {required this.request,
      required this.lease,
      required this.inputStamp,
      required this.capturedAt,
      required this.isCurrent});
  final PlacementBatchRequestV1 request;
  final SurfaceAssignmentResolutionLease lease;
  final String inputStamp;
  final DateTime capturedAt;
  final bool Function() isCurrent;
}

@internal
String placementInputStamp(String? builtIns, DateTime time) =>
    '${builtIns ?? ''}\u0000${time.timeZoneOffset.inMinutes}\u0000${time.timeZoneName}';
