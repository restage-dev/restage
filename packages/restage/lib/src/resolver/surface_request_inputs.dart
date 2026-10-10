import 'package:meta/meta.dart';

import 'delivery_input_budget.dart';
import 'surface_analytics_identity_provider.dart';
import 'surface_assignment_key_provider.dart';
import 'surface_canonical_carrier_provider.dart';
import 'surface_delivery_observations.dart'
    show currentSurfaceDeliveryObservationCell;
import 'surface_metering_key_provider.dart';

/// The optional inputs of one hosted surface request, read under one budget.
@internal
final class SurfaceRequestInputs {
  SurfaceRequestInputs._({
    required this.budget,
    required SurfaceAssignmentResolutionLease lease,
    required bool Function() assignmentDeadlinePassed,
    required this.meteringKey,
    required this.builtIns,
    required this.heldAssignment,
    required String? analyticsAnonymousId,
    required int analyticsGeneration,
  })  : _lease = lease,
        _assignmentDeadlinePassed = assignmentDeadlinePassed,
        _analyticsAnonymousId = analyticsAnonymousId,
        _analyticsGeneration = analyticsGeneration;

  /// Reads every input concurrently under [budget]; only the held assignment
  /// waits for the lease, because it is keyed by [assignmentKey] or the
  /// lease's key. With [sendAssignmentKey] false neither the key nor a held
  /// assignment is read; a key not ready before [keyDeadline] is absent.
  static Future<SurfaceRequestInputs> gather({
    required DeliveryInputBudget budget,
    required String surface,
    required String slug,
    int? contractVersion,
    String? assignmentKey,
    bool sendAssignmentKey = true,
    Future<void>? keyDeadline,
    SurfaceAssignmentResolutionLease? capturedLease,
  }) async {
    var deadlinePassed = false;
    if (keyDeadline != null) {
      keyDeadline.then((_) => deadlinePassed = true);
    }
    final analyticsGeneration = SurfaceAnalyticsIdentityProvider.generation;
    final observationCell = SurfaceCanonicalCarrierProvider.hasBuiltIns
        ? currentSurfaceDeliveryObservationCell()
        : null;
    final lease = capturedLease == null
        ? SurfaceAssignmentKeyProvider.captureLease(
            budget: budget,
            resolveKey: sendAssignmentKey,
            keyDeadline: keyDeadline,
          )
        : Future.value(sendAssignmentKey
            ? capturedLease
            : capturedLease.withoutAssignment());
    final values = await Future.wait<Object?>([
      lease,
      budget.bound(SurfaceMeteringKeyProvider.currentKey()),
      budget.bound(SurfaceAnalyticsIdentityProvider.anonymousId()),
      // A turn later: observations read the host's view, which a host that
      // starts resolving from initState cannot depend on yet.
      budget.bound(Future<String?>.microtask(() => observationCell != null
          ? observationCell
              .read()
              .then((observations) => observations.canonicalBuiltInsBase64())
          : SurfaceCanonicalCarrierProvider.builtIns())),
      lease.then((captured) => sendAssignmentKey
          ? budget.bound(SurfaceCanonicalCarrierProvider.heldAssignment(
              surface: surface,
              slug: slug,
              contractVersion: contractVersion,
              assignmentKey: assignmentKey ?? captured.assignmentKey,
            ))
          : null),
    ]);
    return SurfaceRequestInputs._(
      budget: budget,
      lease: values[0]! as SurfaceAssignmentResolutionLease,
      assignmentDeadlinePassed: () => deadlinePassed,
      meteringKey: values[1] as String?,
      analyticsAnonymousId: values[2] as String?,
      analyticsGeneration: analyticsGeneration,
      builtIns: values[3] as String?,
      heldAssignment: values[4] as String?,
    );
  }

  /// The deadline the inputs were read under.
  final DeliveryInputBudget budget;

  /// The identity lease captured for the request.
  SurfaceAssignmentResolutionLease get lease =>
      _assignmentDeadlinePassed() ? _lease.withoutAssignment() : _lease;

  final SurfaceAssignmentResolutionLease _lease;
  final bool Function() _assignmentDeadlinePassed;

  /// The metering key, when one answered.
  final String? meteringKey;

  /// The audience-observation carrier, when one answered.
  final String? builtIns;

  /// The assignment this build already holds, when one answered.
  final String? heldAssignment;

  final String? _analyticsAnonymousId;
  final int _analyticsGeneration;

  /// The analytics id, while neither the identity nor the provider has changed.
  String? get analyticsAnonymousId => lease.isCurrent &&
          SurfaceAnalyticsIdentityProvider.generation == _analyticsGeneration
      ? _analyticsAnonymousId
      : null;
}
