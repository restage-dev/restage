import 'dart:async';

import 'package:meta/meta.dart';
import 'package:restage_shared/restage_shared.dart'
    show CanonicalSurfaceExperimentAssignmentV1, Surface;

import '../measurement/measurement_resolved_publication_provenance.dart'
    show
        attachMeasurementPublicationBindingReference,
        surfaceResolutionSourceFor;
import '../resolver/report_surface_resolution.dart';
import '../resolver/surface_assignment_key_provider.dart';
import '../resolver/surface_assignment_credential_store.dart';
import '../resolver/surface_canonical_carrier_provider.dart';
import '../restage_rpc_client/restage_rpc_client.dart'
    show storedSurfaceAssignmentKey, storedSurfaceRegistrationFingerprint;
import '../resolver/surface_resolution_report.dart';
import 'surface_delivery_receipt.dart';
import 'surface_delivery_receipt_batch.dart';
import 'surface_artifact_store.dart';

/// A resolver a mount can race: local candidates against a gated fetch.
@internal
abstract interface class RacedSurfaceResolver<T> {
  /// Local candidates only: disk last-good (re-gated), then bundled. Null
  /// when there is none. Never touches the network.
  Future<T?> bestLocal(SurfaceStoreKey key);

  /// Network fetch plus every gate. On accept, persists to the store before
  /// completing.
  ///
  /// With [sendAssignmentKey] false, or when the key is not ready before
  /// [keyDeadline] completes, the request carries no assignment key and no
  /// held assignment, so the server assigns nothing.
  Future<T?> fresh(
    SurfaceStoreKey key, {
    required bool sendAssignmentKey,
    Future<void>? keyDeadline,
  });

  /// Drops the stored delivery for [key], for a candidate that failed to
  /// render, so the next mount falls back.
  Future<void> forgetStored(SurfaceStoreKey key);
}

final Expando<RacedSurfaceResolver<Object?>> _racedResolvers =
    Expando<RacedSurfaceResolver<Object?>>('restage.racedSurfaceResolver');

/// Makes [raced] the raceable side of [owner].
@internal
void registerRacedResolver(
  Object owner,
  RacedSurfaceResolver<Object?> raced,
) =>
    _racedResolvers[owner] = raced;

/// The raceable side of [resolver], or null when it has none.
@internal
RacedSurfaceResolver<T>? racedResolverOf<T>(Object resolver) {
  final raced = resolver is RacedSurfaceResolver<T>
      ? resolver
      : _racedResolvers[resolver];
  return raced is RacedSurfaceResolver<T> ? raced : null;
}

/// A raceable side that forwards to its owning resolver.
@internal
final class RacedSurfaceDelegate<T>
    with RacedSurfaceReporting<T>
    implements RacedSurfaceResolver<T> {
  /// Creates a delegate over the owner's callbacks.
  RacedSurfaceDelegate({
    required Future<T?> Function(SurfaceStoreKey key) bestLocal,
    required Future<T?> Function(
      SurfaceStoreKey key, {
      required bool sendAssignmentKey,
      Future<void>? keyDeadline,
    }) fresh,
    Object Function(T winner)? leafOf,
    Surface Function(SurfaceStoreKey key)? surfaceFor,
  })  : _bestLocal = bestLocal,
        _fresh = fresh,
        _leafOf = leafOf,
        _surfaceFor = surfaceFor;

  final Future<T?> Function(SurfaceStoreKey key) _bestLocal;
  final Future<T?> Function(
    SurfaceStoreKey key, {
    required bool sendAssignmentKey,
    Future<void>? keyDeadline,
  }) _fresh;
  final Object Function(T winner)? _leafOf;
  final Surface Function(SurfaceStoreKey key)? _surfaceFor;

  @override
  SurfaceArtifactStore get store => sharedSurfaceArtifactStore;

  @override
  Future<T?> bestLocal(SurfaceStoreKey key) => _bestLocal(key);

  @override
  Future<T?> fresh(
    SurfaceStoreKey key, {
    required bool sendAssignmentKey,
    Future<void>? keyDeadline,
  }) =>
      _fresh(
        key,
        sendAssignmentKey: sendAssignmentKey,
        keyDeadline: keyDeadline,
      );

  @override
  Object reportedLeafOf(T winner) =>
      _leafOf?.call(winner) ?? super.reportedLeafOf(winner);

  @override
  Surface reportSurfaceFor(SurfaceStoreKey key) =>
      _surfaceFor?.call(key) ?? super.reportSurfaceFor(key);
}

/// Reports the candidate a mount rendered, exactly once per mount.
///
/// A null [winner] means the host rendered its own fallback: no receipt opens,
/// and the reason explains the next one for this surface.
@internal
void reportRacedSurface<T>(
  RacedSurfaceResolver<T> resolver,
  SurfaceStoreKey key,
  T? winner,
) {
  if (resolver is! RacedSurfaceReporting<T>) return;
  final reporting = resolver as RacedSurfaceReporting<T>;
  if (winner == null) {
    SurfaceDeliveryReceiptBatch.instance.noteRefusal(
      reporting.reportSurfaceFor(key),
      key.slug,
      reporting.localReasonFor(key),
    );
    return;
  }
  final leaf = reporting.reportedLeafOf(winner);
  final source = surfaceResolutionSourceFor(leaf) ??
      surfaceResolutionSourceFor(winner as Object) ??
      SurfaceResolutionSource.bundled;
  reportSurfaceResolution<Object>(
    reporting.reportSurfaceFor(key),
    key.slug,
    leaf,
    source,
    reason: source == SurfaceResolutionSource.fresh
        ? SurfaceDeliveryReceiptReason.none
        : reporting.localReasonFor(key),
  );
  reporting.winnerReported(key, winner);
}

/// Labels where [resolved] came from without reporting it.
@internal
T labelSurfaceSource<T>(T resolved, SurfaceResolutionSource source) {
  attachMeasurementPublicationBindingReference(
    resolved as Object,
    null,
    surfaceResolutionSource: source,
  );
  return resolved;
}

/// Resolves without a deadline: fresh first, then the best local candidate,
/// reported once. Null when neither produced anything.
@internal
Future<T?> resolveRacedInOrder<T>(
  RacedSurfaceResolver<T> resolver,
  SurfaceStoreKey key,
) async {
  final winner = await resolver.fresh(key, sendAssignmentKey: true) ??
      await resolver.bestLocal(key);
  reportRacedSurface(resolver, key, winner);
  return winner;
}

/// Carries SDK-private credential authority without changing resolved DTOs.
@internal
T attachSurfaceAssignmentLease<T extends Object>(
  T resolved,
  SurfaceAssignmentResolutionLease? lease,
) {
  _assignmentLeases[resolved] = lease;
  return resolved;
}

@internal
SurfaceAssignmentResolutionLease? surfaceAssignmentLeaseFor(Object resolved) =>
    _assignmentLeases[resolved];

final _assignmentLeases = Expando<SurfaceAssignmentResolutionLease>();

/// Whether a stored delivery may be reused for the identity this device holds
/// now. A delivery requested with an assignment key is reused only under the
/// same key; one served under an [assignment] also needs that assignment to
/// still be held. [key] is the identity it is reused under.
@internal
Future<({bool reusable, String? key, SurfaceAssignmentResolutionLease? lease})>
    storedDeliveryIdentity({
  required StoredSurface stored,
  required CanonicalSurfaceExperimentAssignmentV1? assignment,
  required String surface,
  required String slug,
  int? contractVersion,
}) async {
  const refused = (reusable: false, key: null, lease: null);
  final storedKey = storedSurfaceAssignmentKey(stored);
  if (storedKey == null) {
    return assignment == null
        ? (
            reusable: true,
            key: null,
            lease: SurfaceAssignmentKeyProvider.captureKeylessLease()
          )
        : refused;
  }
  final identityLease = SurfaceAssignmentKeyProvider.captureKeylessLease();
  final localKey = await SurfaceAssignmentKeyProvider.resolveLocal();
  if (localKey != storedKey) return refused;
  SurfaceRegistrationAttempt? registration;
  if (SurfaceAssignmentKeyProvider.registrationConfigured) {
    registration =
        await SurfaceAssignmentKeyProvider.captureRegistrationAttempt();
    if (registration == null ||
        registration.credentialHandle != storedKey ||
        registration.fingerprint !=
            storedSurfaceRegistrationFingerprint(stored)) {
      return refused;
    }
  }
  if (assignment != null &&
      !await SurfaceCanonicalCarrierProvider.holds(
        surface: surface,
        slug: slug,
        contractVersion: contractVersion,
        assignmentKey: storedKey,
        assignment: assignment,
      )) {
    return refused;
  }
  final lease = identityLease.forStoredAssignment(storedKey, registration);
  return lease.isCurrent
      ? (reusable: true, key: storedKey, lease: lease)
      : refused;
}

/// Persists an accepted delivery for [key]. A delivery fetched without an
/// assignment key never replaces one stored under the key this device holds.
@internal
Future<void> persistAcceptedDelivery(
  SurfaceArtifactStore store,
  SurfaceStoreKey key,
  StoredSurface? stored,
) {
  if (stored == null) return Future<void>.value();
  // Persists for one key run one at a time, so a keyed entry written while a
  // keyless one checks the store is always seen by that check.
  final pending = _persists[store] ??= <SurfaceStoreKey, Future<void>>{};
  final previous = pending[key] ?? Future<void>.value();
  final next = previous.then((_) => _persist(store, key, stored));
  pending[key] = next;
  unawaited(next.whenComplete(() {
    if (identical(pending[key], next)) pending.remove(key);
  }));
  return next;
}

final Expando<Map<SurfaceStoreKey, Future<void>>> _persists =
    Expando<Map<SurfaceStoreKey, Future<void>>>('surface persists');

Future<void> _persist(
  SurfaceArtifactStore store,
  SurfaceStoreKey key,
  StoredSurface stored,
) async {
  try {
    if (storedSurfaceAssignmentKey(stored) == null) {
      final existing = await store.read(key);
      final existingKey =
          existing == null ? null : storedSurfaceAssignmentKey(existing);
      if (existingKey != null &&
          existingKey == await SurfaceAssignmentKeyProvider.resolveLocal()) {
        return;
      }
    }
    await store.write(key, stored);
  } on Object {
    // A delivery that cannot be kept is still rendered.
  }
}

/// Fresh-fetch bookkeeping shared by the built-in raced resolvers.
@internal
mixin RacedSurfaceReporting<T> {
  final Map<SurfaceStoreKey, SurfaceDeliveryReceiptReason?> _freshRefusals =
      <SurfaceStoreKey, SurfaceDeliveryReceiptReason?>{};

  /// The object the delivery receipt and report attach to.
  Object reportedLeafOf(T winner) => winner as Object;

  /// Called once with the candidate the mount rendered.
  void winnerReported(SurfaceStoreKey key, T winner) {}

  /// The surface a resolution for [key] reports under.
  Surface reportSurfaceFor(SurfaceStoreKey key) =>
      Surface.fromWireName(key.surfaceType);

  /// The store this resolver persists accepted deliveries in.
  SurfaceArtifactStore get store;

  /// Drops the stored delivery for [key], for a candidate that failed to
  /// render, so the next mount falls back.
  Future<void> forgetStored(SurfaceStoreKey key) async {
    try {
      await store.remove(key);
    } on Object {
      // A leftover entry is still re-gated on read.
    }
  }

  /// Marks a fresh fetch for [key] as started.
  void freshStarted(SurfaceStoreKey key) => _freshRefusals[key] = null;

  /// Records why the fresh fetch for [key] was not accepted.
  void freshRefused(SurfaceStoreKey key, SurfaceDeliveryReceiptReason reason) =>
      _freshRefusals[key] = reason;

  /// Why a local candidate rendered for [key]: the fresh refusal, or offline
  /// while fresh is still pending.
  SurfaceDeliveryReceiptReason localReasonFor(SurfaceStoreKey key) =>
      _freshRefusals[key] ?? SurfaceDeliveryReceiptReason.offline;
}
