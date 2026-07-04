import 'dart:ui' show Locale;

import 'package:meta/meta.dart';

import '../flow/flow_resolver.dart' show ResolvedFlow;
import 'resolved_variant.dart';

/// SDK-internal result of resolving a paywall surface to either a single blob
/// or a lowered multi-screen flow. The public [VariantResolver.resolve] SPI
/// still returns a blob-only [ResolvedVariant]; this richer shape is produced
/// only by the built-in resolvers via
/// [FlowCapableVariantResolver.resolvePayload].
@immutable
sealed class ResolvedPaywallPayload {
  const ResolvedPaywallPayload();
}

/// A single-blob paywall: the existing path.
@immutable
final class BlobPaywallPayload extends ResolvedPaywallPayload {
  const BlobPaywallPayload(this.variant);

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
    this.resolvedFromActiveArm = false,
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
