import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:meta/meta.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';

import '../resolver/resolved_paywall_payload.dart';
import '../resolver/surface_resolution_report.dart';
import 'measurement_resolved_publication_provenance.dart';
import 'measurement_runtime_capture.dart' show MeasurementCaptureSessionNonce;

final _deliveries = Expando<PublicPlacementDeliveryV1>();
final _selectedDocuments = Expando<SurfaceDocument>();

/// The exact leaf already retained by the current rendering hosts.
@internal
Object placementResolvedLeaf(Object resolved) => switch (resolved) {
      BlobPaywallPayload(:final variant) => variant,
      FlowPaywallPayload(:final flow) => flow,
      _ => resolved,
    };

/// Retains public immutable selection authority on one resolved leaf.
@internal
T attachResolvedPlacementDelivery<T extends Object>(
    T resolved, PublicPlacementDeliveryV1 delivery,
    {SurfaceDocument? selectedDocument}) {
  final leaf = placementResolvedLeaf(resolved);
  final existing = _deliveries[leaf];
  if (existing != null && existing != delivery) {
    throw StateError('A resolved leaf cannot change its placement selection.');
  }
  final previousDocument = _selectedDocuments[leaf];
  if (selectedDocument != null &&
      previousDocument != null &&
      previousDocument != selectedDocument) {
    throw StateError('A resolved leaf cannot change its selected document.');
  }
  _deliveries[leaf] = delivery;
  if (selectedDocument != null) _selectedDocuments[leaf] = selectedDocument;
  return resolved;
}

@internal
PublicPlacementDeliveryV1? resolvedPlacementDeliveryFor(Object resolved) =>
    _deliveries[placementResolvedLeaf(resolved)];

@internal
T copyResolvedPlacementDelivery<T extends Object>(Object original, T copy) {
  final delivery = resolvedPlacementDeliveryFor(original);
  return delivery == null
      ? copy
      : attachResolvedPlacementDelivery(copy, delivery,
          selectedDocument:
              _selectedDocuments[placementResolvedLeaf(original)]);
}

/// One presentation's safe tuple, independent of Measurement readiness.
@internal
@immutable
final class MountAttributionSnapshotV1 {
  factory MountAttributionSnapshotV1.hosted({
    required PublicPlacementDeliveryV1 delivery,
    required DeliverySurfaceLocatorV1? defaultSurface,
    required String mountInstanceNonce,
    bool cacheHit = false,
    SurfaceDocument? selectedDocument,
  }) {
    MeasurementCaptureSessionNonce(mountInstanceNonce);
    return MountAttributionSnapshotV1._(
        attribution: MountSelectionAttributionV1(
          placementKey: delivery.mount.placement.key,
          resolvedTarget: delivery.mount.placement.target,
          actualSurface: delivery.selectedSurface,
          actualPublication: delivery.actualPublication,
          measurementBinding: delivery.actualPublication.publicationBindingRef,
          resolvedSelectionDigest: delivery.publicProjectionDigest,
          resolutionKind: cacheHit
              ? MountResolutionKindV1.cached
              : MountResolutionKindV1.hosted,
          evidenceStrength: MountEvidenceStrengthV1.verifiedSelection,
          mountNonceDigest: CanonicalDigest(crypto.sha256
              .convert(utf8.encode(mountInstanceNonce))
              .toString()),
        ),
        hostContractHash: delivery.mount.hostContractHash,
        defaultSurface: defaultSurface,
        mountInstanceNonce: mountInstanceNonce,
        hostedDelivery: delivery,
        selectedDocument: selectedDocument);
  }

  factory MountAttributionSnapshotV1.original({
    required PlacementKeyV1 key,
    required String hostContractHash,
    required String mountInstanceNonce,
    Object? resolved,
    DeliverySurfaceLocatorV1? defaultSurface,
  }) {
    MeasurementCaptureSessionNonce(mountInstanceNonce);
    return MountAttributionSnapshotV1._(
        attribution: MountSelectionAttributionV1(
            placementKey: key,
            measurementBinding: resolved == null
                ? null
                : measurementPublicationBindingReferenceFor(
                    placementResolvedLeaf(resolved)),
            resolutionKind: MountResolutionKindV1.compiledFallback,
            evidenceStrength: MountEvidenceStrengthV1.reportedLocal,
            mountNonceDigest: CanonicalDigest(crypto.sha256
                .convert(utf8.encode(mountInstanceNonce))
                .toString())),
        hostContractHash: hostContractHash,
        defaultSurface: defaultSurface,
        mountInstanceNonce: mountInstanceNonce);
  }

  factory MountAttributionSnapshotV1.fromResolved({
    required Object resolved,
    required PlacementMountRequestV1 mount,
    required String mountInstanceNonce,
  }) {
    final delivery = resolvedPlacementDeliveryFor(resolved);
    return delivery == null
        ? MountAttributionSnapshotV1.original(
            key: mount.key,
            hostContractHash: mount.hostContractHash,
            defaultSurface: mount.defaultSurface,
            mountInstanceNonce: mountInstanceNonce,
            resolved: resolved)
        : MountAttributionSnapshotV1.hosted(
            delivery: delivery,
            selectedDocument:
                _selectedDocuments[placementResolvedLeaf(resolved)],
            defaultSurface: mount.defaultSurface,
            mountInstanceNonce: mountInstanceNonce,
            cacheHit:
                surfaceResolutionSourceFor(placementResolvedLeaf(resolved)) ==
                    SurfaceResolutionSource.holdLastGood);
  }

  const MountAttributionSnapshotV1._({
    required this.attribution,
    required this.hostContractHash,
    required this.defaultSurface,
    required this.mountInstanceNonce,
    this.hostedDelivery,
    this.selectedDocument,
  });

  final MountSelectionAttributionV1 attribution;
  final String hostContractHash;
  final DeliverySurfaceLocatorV1? defaultSurface;
  final String mountInstanceNonce;
  final PublicPlacementDeliveryV1? hostedDelivery;
  final SurfaceDocument? selectedDocument;
  String? get routingSelectionReceipt =>
      hostedDelivery?.routingSelectionReceipt;
  PresentationAssignmentCarrierV2? get assignment => hostedDelivery?.assignment;
  DeliveryCacheValidityV1? get validity => hostedDelivery?.cacheValidity;
}

final _eventContextKey = Object();

/// Binds a current painted host snapshot through asynchronous authored actions.
@internal
final class MountAttributionEventContext {
  const MountAttributionEventContext(
      {required this.snapshot,
      required this.isCurrent,
      this.isAuthorityCurrent});
  final MountAttributionSnapshotV1 snapshot;
  final bool Function() isCurrent;
  final bool Function()? isAuthorityCurrent;

  bool get isAdmitted => isCurrent() && (isAuthorityCurrent?.call() ?? true);

  static MountAttributionEventContext? get bound =>
      Zone.current[_eventContextKey] as MountAttributionEventContext?;

  static MountAttributionEventContext? get current {
    final context = bound;
    return context != null && context.isAdmitted ? context : null;
  }

  /// Keeps accepted paint facts after the host detaches or changes content.
  MountAttributionEventContext capture({bool Function()? authorityCheck}) {
    final accepted = isCurrent();
    final originalAuthority = isAuthorityCurrent;
    return MountAttributionEventContext(
        snapshot: snapshot,
        isCurrent: () => accepted,
        isAuthorityCurrent: () =>
            (originalAuthority?.call() ?? true) &&
            (authorityCheck?.call() ?? true));
  }

  static T runCaptured<T>(
          MountAttributionEventContext? context, T Function() action) =>
      runZoned(action, zoneValues: {_eventContextKey: context});

  T run<T>(T Function() action) => runCaptured(this, action);
}
