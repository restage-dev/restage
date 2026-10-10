import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:meta/meta.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';

import '../restage_rpc_client/placement_delivery_adapter.dart';
import 'surface_artifact_store.dart';
import 'raced_surface_resolver.dart';

/// Placement metadata and shared frames in the existing artifact store.
@internal
final class PlacementDecisionStore {
  PlacementDecisionStore({required this.scope, required this.store});

  final String scope;
  final SurfaceArtifactStore store;

  SurfaceStoreKey mountKey(PlacementMountRequestV1 mount) => SurfaceStoreKey(
        scope: scope,
        surfaceType: 'placementMount',
        slug: _hash(mount.canonicalBytes),
        contractVersion: 1,
      );

  Future<void> remember(PlacementMountRequestV1 mount,
      SurfaceHostContractV1 host, bool Function() isCurrent) async {
    if (!isCurrent()) return;
    await store.write(
        mountKey(mount),
        StoredSurface(
          descriptorJson: CanonicalJsonCodec.encode({
            'mount': mount.toJson(),
            'host': host.toJson(),
          }),
          artifactBytes: Uint8List(0),
        ));
  }

  Future<List<({PlacementMountRequestV1 mount, SurfaceHostContractV1 host})>>
      knownMounts() async {
    final result =
        <({PlacementMountRequestV1 mount, SurfaceHostContractV1 host})>[];
    for (final key in await store.keys()) {
      if (key.scope != scope || key.surfaceType != 'placementMount') continue;
      try {
        final value = await store.read(key);
        if (value == null) continue;
        final json = CanonicalJsonCodec.decode(value.descriptorJson) as Map;
        final mount = PlacementMountRequestV1.fromJson(json['mount']);
        final host = SurfaceHostContractV1.fromJson(json['host']);
        if (host.contentHash == mount.hostContractHash &&
            mountKey(mount) == key) {
          result.add((mount: mount, host: host));
        }
      } on Object {
        // Unreadable declarations never become build facts.
      }
    }
    return result;
  }

  SurfaceStoreKey decisionKey(PlacementBatchRequestV1 request,
          PlacementMountRequestV1 mount, String inputStamp,
          {required TargetCoordinate target}) =>
      SurfaceStoreKey(
        scope: scope,
        surfaceType: 'placementDecision',
        slug: _hash(CanonicalJsonCodec.encode({
          'mount': mount.toJson(),
          'build': request.appBuildContractHash,
          'inputs': inputStamp,
          'target': target.toJson(),
        })),
        contractVersion: 1,
      );

  SurfaceStoreKey _artifactKey(
          TargetCoordinate target, ArtifactIdentityV1 identity) =>
      SurfaceStoreKey(
          scope: scope,
          surfaceType: 'placementArtifact',
          slug: _hash(CanonicalJsonCodec.encode({
            'target': target.toJson(),
            'identity': identity.toJson(),
          })),
          contractVersion: identity.payloadFormatVersion);

  /// Frames become durable before metadata can point at them.
  Future<void> write(
      SurfaceStoreKey key,
      PlacementBatchAvailableV1 decision,
      PlacementDeliveryArtifacts artifacts,
      Map<String, Object?> sidecar,
      bool Function() isCurrent) async {
    for (final ref in decision.artifactClosure) {
      if (!isCurrent()) return;
      final bytes = artifacts.frames[ref.identity];
      if (bytes == null) return;
      await store.write(
          _artifactKey(decision.descriptor.placement.target, ref.identity),
          StoredSurface(
              descriptorJson: ref.identity.canonicalBytes,
              artifactBytes: bytes));
    }
    if (!isCurrent()) return;
    await persistAcceptedDelivery(
        store,
        key,
        StoredSurface(
            descriptorJson: decision.canonicalBytes,
            artifactBytes: Uint8List(0),
            sidecar: sidecar),
        publicationGuard: isCurrent);
  }

  /// Re-enters the strict batch codec with the complete stored frame closure.
  Future<PlacementBatchResolvedV1?> read(
      {required PlacementBatchRequestV1 request,
      required String inputStamp,
      required String configurationFingerprint,
      TargetCoordinate? expectedTarget,
      required Future<bool> Function(
              StoredSurface stored, PlacementBatchAvailableV1 decision)
          acceptsStored}) async {
    try {
      final mount = request.mounts.single;
      final keys = expectedTarget == null
          ? (await store.keys()).where((key) =>
              key.scope == scope && key.surfaceType == 'placementDecision')
          : [decisionKey(request, mount, inputStamp, target: expectedTarget)];
      for (final key in keys) {
        final stored = await store.read(key);
        if (stored == null ||
            stored.sidecar['authenticatedConfigurationFingerprint'] !=
                configurationFingerprint) {
          continue;
        }
        final decision =
            PlacementBatchEntryV1.fromCanonicalBytes(stored.descriptorJson);
        if (decision is! PlacementBatchAvailableV1 ||
            stored.sidecar['authenticatedDeliveryDigest'] !=
                decision.publicDelivery.publicProjectionDigest.hex) {
          continue;
        }
        final target = decision.descriptor.placement.target;
        if ((expectedTarget != null && target != expectedTarget) ||
            key != decisionKey(request, mount, inputStamp, target: target) ||
            !await acceptsStored(stored, decision)) {
          continue;
        }
        final frames = <PlacementBatchArtifactV1>[];
        var complete = true;
        for (final identity
            in decision.artifactClosure.map((ref) => ref.identity).toSet()) {
          final artifact = await store.read(_artifactKey(target, identity));
          if (artifact == null ||
              ArtifactIdentityV1.fromCanonicalBytes(artifact.descriptorJson) !=
                  identity) {
            complete = false;
            break;
          }
          frames.add(PlacementBatchArtifactV1(
              identity: identity, bytes: artifact.artifactBytes));
        }
        if (!complete) continue;
        return PlacementBatchResolvedV1(
            request: request,
            expectedTarget: target,
            decisions: [decision],
            artifacts: frames);
      }
      return null;
    } on Object {
      return null;
    }
  }

  Future<void> remove(SurfaceStoreKey key) => store.remove(key);

  Future<void> removeAccepted(
          SurfaceStoreKey key, PlacementBatchAvailableV1 accepted) =>
      evictAcceptedDelivery(store, key, (stored) {
        final current =
            PlacementBatchEntryV1.fromCanonicalBytes(stored.descriptorJson);
        return current is PlacementBatchAvailableV1 &&
            current.publicDelivery.publicProjectionDigest ==
                accepted.publicDelivery.publicProjectionDigest &&
            current.watch?.decisionIdentityDigest ==
                accepted.watch?.decisionIdentityDigest;
      });

  static String _hash(List<int> bytes) =>
      crypto.sha256.convert(bytes).toString();
}
