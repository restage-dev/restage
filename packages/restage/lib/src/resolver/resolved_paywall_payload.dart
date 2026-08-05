import 'dart:async';
import 'dart:ui' show Locale;

import 'package:meta/meta.dart';

import '../flow/flow_experiment_mount.dart'
    show
        FlowCandidatePrefetchAccepted,
        FlowExperimentPresentationAuthority,
        FlowMountRevalidationBoundary;
import '../flow/flow_resolver.dart' show FlowResolver, ResolvedFlow;
import 'resolved_variant.dart';
import 'surface_assignment_key_provider.dart';

/// SDK-internal result of resolving a paywall surface to either a single blob
/// or a lowered multi-screen flow. The public [VariantResolver.resolve] SPI
/// still returns a blob-only [ResolvedVariant]; this richer shape is produced
/// only by the built-in resolvers via
/// [FlowCapableVariantResolver.resolvePayload].
@immutable
sealed class ResolvedPaywallPayload {
  const ResolvedPaywallPayload({
    this.assignmentLease,
    HostedPayloadPublication? hostedPublication,
    FlowExperimentPresentationAuthority? experimentAuthority,
  })  : _hostedPublication = hostedPublication,
        _experimentAuthority = experimentAuthority;

  /// The internal actor generation that selected a hosted artifact.
  /// Bundled and custom payloads carry no lease.
  final SurfaceAssignmentResolutionLease? assignmentLease;

  final HostedPayloadPublication? _hostedPublication;
  final FlowExperimentPresentationAuthority? _experimentAuthority;

  /// Publishes a fresh hosted payload to resolver hold-last-good at the exact
  /// host render commit. Cached and bundled payloads carry no publication.
  @internal
  void publishHostedLastGood() {
    _hostedPublication?.commit();
    _experimentAuthority?.publishHostedLastGood();
  }

  /// Abandons a fresh hosted candidate that never reached render commitment.
  @internal
  void abandonHostedLastGood() {
    _hostedPublication?.abandon();
    final authority = _experimentAuthority;
    authority?.abandonHostedLastGood();
    authority?.disposePresentation();
  }

  /// Abandons only the provisional artifact while a mount-wide retry retains
  /// the same strict presentation authority.
  @internal
  void abandonHostedCandidate() {
    _hostedPublication?.abandon();
    _experimentAuthority?.abandonHostedLastGood();
  }

  /// Whether the exact strict flow snapshot still owns [boundary].
  @internal
  bool revalidateHostedPresentation(FlowMountRevalidationBoundary boundary) =>
      _experimentAuthority?.revalidate(boundary) ?? true;

  /// Releases any strict per-presentation resolver retained after first paint.
  @internal
  void disposeHostedPresentation() =>
      _experimentAuthority?.disposePresentation();

  /// Whether this payload carries strict flow presentation authority.
  @internal
  bool get hasHostedExperimentAuthority => _experimentAuthority != null;
}

/// Strict flow-paywall authority that can spend the next attempt without
/// recapturing its frozen bundled baseline.
@internal
abstract interface class FlowPaywallExperimentRetryAuthority
    implements FlowExperimentPresentationAuthority {
  Future<FlowPaywallPayload?> resolveNextPayload();
}

/// A single-blob paywall: the existing path.
@immutable
final class BlobPaywallPayload extends ResolvedPaywallPayload {
  const BlobPaywallPayload(
    this.variant, {
    super.assignmentLease,
    super.hostedPublication,
  });

  final ResolvedVariant variant;
}

/// A lowered, flow-shaped paywall (entry screen + pushed screen + transitions).
///
/// Carries a fully-resolved [ResolvedFlow] (the validated FlowDocument + its
/// pinned screen blobs), symmetric with [BlobPaywallPayload] carrying bytes.
@immutable
final class FlowPaywallPayload extends ResolvedPaywallPayload {
  const FlowPaywallPayload({
    required this.flow,
    required this.paywallId,
    this.paywallPublishedVersion,
    this.experimentId,
    this.variantId,
    this.experimentEpoch,
    this.resolvedFromActiveArm = false,
    super.assignmentLease,
    super.hostedPublication,
    super.experimentAuthority,
  })  : _retryAuthority = null,
        acceptedCandidate = null,
        _pinnedFlowResolver = null;

  FlowPaywallPayload.experiment({
    required FlowCandidatePrefetchAccepted acceptedCandidate,
    required this.paywallId,
    this.paywallPublishedVersion,
    this.resolvedFromActiveArm = false,
    super.assignmentLease,
    super.hostedPublication,
    super.experimentAuthority,
  })  : _retryAuthority =
            experimentAuthority is FlowPaywallExperimentRetryAuthority
                ? experimentAuthority
                : null,
        acceptedCandidate = acceptedCandidate,
        _pinnedFlowResolver = acceptedCandidate.resolver,
        flow = acceptedCandidate.candidateRoot,
        experimentId = acceptedCandidate.candidateRoot.assignment?.experimentId,
        variantId = acceptedCandidate.candidateRoot.assignment?.variantId,
        experimentEpoch =
            acceptedCandidate.candidateRoot.assignment?.experimentEpoch;

  @internal
  const FlowPaywallPayload.experimentBaseline({
    required this.flow,
    required FlowResolver pinnedFlowResolver,
    required this.paywallId,
    this.paywallPublishedVersion,
    this.resolvedFromActiveArm = false,
    super.assignmentLease,
    super.hostedPublication,
    super.experimentAuthority,
  })  : _retryAuthority =
            experimentAuthority is FlowPaywallExperimentRetryAuthority
                ? experimentAuthority
                : null,
        acceptedCandidate = null,
        _pinnedFlowResolver = pinnedFlowResolver,
        experimentId = null,
        variantId = null,
        experimentEpoch = null;

  final ResolvedFlow flow;
  final String paywallId;

  /// Atomic parity-accepted candidate root, closure, resolver, and verdict.
  ///
  /// Payload delivery transforms must preserve this exact object.
  @internal
  final FlowCandidatePrefetchAccepted? acceptedCandidate;
  final FlowResolver? _pinnedFlowResolver;
  final FlowPaywallExperimentRetryAuthority? _retryAuthority;

  /// Immutable root/descendant resolver accepted with [flow].
  ///
  /// Null preserves the existing bundled/custom flow-paywall path.
  @internal
  FlowResolver? get pinnedFlowResolver => _pinnedFlowResolver;

  /// Whether first-paint rejection can continue the same frozen transaction.
  @internal
  bool get canRetryHostedPresentation => _retryAuthority != null;

  /// Spends the next strict attempt on the same frozen presentation.
  @internal
  Future<FlowPaywallPayload?> resolveNextHostedPresentation() =>
      _retryAuthority?.resolveNextPayload() ??
      Future<FlowPaywallPayload?>.value();

  /// Server-assigned published version (null for a bundled/custom resolution).
  final int? paywallPublishedVersion;

  /// Server-selected experiment id, when the served artifact is an experiment
  /// arm (null for a bundled/custom resolution). Threaded onto `PaywallViewed`
  /// so a hosted flow-paywall conversion attributes to the experiment arm, at
  /// parity with the blob active path.
  final String? experimentId;

  /// Server-selected variant id, when the served artifact is an experiment arm
  /// (null for a bundled/custom resolution). Rides the same assignment metadata
  /// as [experimentId]; threaded onto `PaywallViewed` for A/B attribution parity
  /// with the blob active path.
  final String? variantId;

  /// Server-selected experiment epoch, when the served artifact is an
  /// experiment arm (null for a bundled/custom resolution).
  final int? experimentEpoch;

  /// Whether this payload was resolved from the hosted active arm (vs a bundled
  /// or custom resolution). The runtime `cacheLastRender` fallback must not
  /// independently re-host an active-resolved flow un-re-gated — it defers to
  /// the resolver's own re-gated hold-last-good; a bundled flow re-hosts freely.
  final bool resolvedFromActiveArm;

  /// Copies this payload for delivery while preserving any accepted candidate.
  @internal
  FlowPaywallPayload copyForDelivery({
    required SurfaceAssignmentResolutionLease? assignmentLease,
    HostedPayloadPublication? hostedPublication,
  }) {
    final candidate = acceptedCandidate;
    if (candidate != null) {
      return FlowPaywallPayload.experiment(
        acceptedCandidate: candidate,
        paywallId: paywallId,
        paywallPublishedVersion: paywallPublishedVersion,
        resolvedFromActiveArm: resolvedFromActiveArm,
        assignmentLease: assignmentLease,
        hostedPublication: hostedPublication,
        experimentAuthority: _experimentAuthority,
      );
    }
    final pinnedResolver = _pinnedFlowResolver;
    if (pinnedResolver != null) {
      return FlowPaywallPayload.experimentBaseline(
        flow: flow,
        pinnedFlowResolver: pinnedResolver,
        paywallId: paywallId,
        paywallPublishedVersion: paywallPublishedVersion,
        resolvedFromActiveArm: resolvedFromActiveArm,
        assignmentLease: assignmentLease,
        hostedPublication: hostedPublication,
        experimentAuthority: _experimentAuthority,
      );
    }
    return FlowPaywallPayload(
      flow: flow,
      paywallId: paywallId,
      paywallPublishedVersion: paywallPublishedVersion,
      experimentId: experimentId,
      variantId: variantId,
      experimentEpoch: experimentEpoch,
      resolvedFromActiveArm: resolvedFromActiveArm,
      assignmentLease: assignmentLease,
      hostedPublication: hostedPublication,
      experimentAuthority: _experimentAuthority,
    );
  }
}

/// SDK-internal capability the built-in resolvers expose so the present path
/// can resolve to a blob OR a flow.
///
/// Host-supplied custom VariantResolvers do NOT implement this; they stay
/// blob-only, and the present path wraps their ResolvedVariant as a
/// [BlobPaywallPayload].
@internal
abstract interface class FlowCapableVariantResolver {
  Future<ResolvedPaywallPayload> resolvePayload(
    String id, {
    String? placementId,
    Locale? locale,
  });
}

/// Presentation-only resolver seam used by the built-in paywall host.
///
/// Unlike [FlowCapableVariantResolver.resolvePayload], a fresh hosted result
/// remains provisional until the host reports actual render commitment. This
/// keeps ordinary resolver callers' eager hold-last-good behavior unchanged.
@internal
abstract interface class PresentationPaywallResolver {
  Future<ResolvedPaywallPayload> resolvePayloadForPresentation(
    String id, {
    String? placementId,
    Locale? locale,
  });
}

final Object _paywallPresentationGuardZoneKey = Object();

/// Runs one built-in host resolution with its mount/supersession authority.
@internal
T withPaywallPresentationGuard<T>({
  required bool Function() guard,
  required T Function() resolve,
}) =>
    runZoned(
      resolve,
      zoneValues: <Object?, Object?>{
        _paywallPresentationGuardZoneKey: guard,
      },
    );

/// Reads the host authority installed by [withPaywallPresentationGuard].
@internal
bool Function() currentPaywallPresentationGuard() {
  final guard = Zone.current[_paywallPresentationGuardZoneKey];
  return guard is bool Function() ? guard : _alwaysCurrentPresentation;
}

bool _alwaysCurrentPresentation() => true;

/// One-shot publication carried only by fresh hosted presentation payloads.
///
/// The resolver owns the callback; the runtime can only commit or abandon it.
/// Clearing both callbacks on the first terminal action avoids retaining the
/// resolver through a payload cached by the widget runtime.
@internal
final class HostedPayloadPublication {
  HostedPayloadPublication({required void Function() onCommit})
      : _onCommit = onCommit;

  void Function()? _onCommit;

  void commit() {
    final callback = _onCommit;
    _onCommit = null;
    callback?.call();
  }

  void abandon() {
    _onCommit = null;
  }
}
