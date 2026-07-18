import 'dart:ui' show Locale;

import 'package:meta/meta.dart';

import '../flow/flow_resolver.dart' show ResolvedFlow;
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
  }) : _hostedPublication = hostedPublication;

  /// The internal actor generation that selected a hosted artifact.
  /// Bundled and custom payloads carry no lease.
  final SurfaceAssignmentResolutionLease? assignmentLease;

  final HostedPayloadPublication? _hostedPublication;

  /// Publishes a fresh hosted payload to resolver hold-last-good at the exact
  /// host render commit. Cached and bundled payloads carry no publication.
  @internal
  void publishHostedLastGood() => _hostedPublication?.commit();

  /// Abandons a fresh hosted candidate that never reached render commitment.
  @internal
  void abandonHostedLastGood() => _hostedPublication?.abandon();
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
  });

  final ResolvedFlow flow;
  final String paywallId;

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
