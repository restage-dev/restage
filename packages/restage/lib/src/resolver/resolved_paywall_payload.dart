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
  });

  final ResolvedFlow flow;
  final String paywallId;

  /// Server-assigned published version (null for a bundled/custom resolution).
  final int? paywallPublishedVersion;
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
