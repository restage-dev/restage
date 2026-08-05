import 'package:restage/src/events/restage_event.dart';
import 'package:restage_shared/restage_shared.dart';

import 'root_analytics_context.dart';

/// Event names the SDK does NOT yet bridge to analytics in production.
///
/// The Tier-2 `paywall_session_summary` contract exists, but active
/// instrumentation (and thus a real, populated summary) is deferred — emitting a
/// zeroed summary would pollute analytics, so the production bridge suppresses
/// it. When capture is enabled, this suppression is lifted.
const Set<String> kProdSuppressedEventNames = <String>{
  'paywall_session_summary'
};

/// Whether [eventName] is suppressed from the production analytics bridge.
bool isProdSuppressedAnalyticsEvent(String eventName) =>
    kProdSuppressedEventNames.contains(eventName);

/// Keys in a [RestageEvent.toMap] that are promoted to typed envelope fields (or
/// otherwise consumed) and therefore must NOT also appear in `properties`.
///
/// Anything NOT listed here falls through to `properties` (the principled
/// default) — so a key is only removed from this set when it has a genuine
/// typed envelope home. A field with no home (e.g. a sub-flow's
/// `parentFlowSessionId`) stays in `properties` rather than being dropped.
/// (The longer-term fix is to derive this set from the envelope's typed fields
/// so "promoted" and "has a column" cannot diverge — tracked as a follow-up.)
const Set<String> _promotedKeys = <String>{
  'name',
  'paywallId',
  'flowId',
  'flowVersion',
  'flowSessionId',
  'firedAt',
  'productId',
  'offerId',
  'variantId',
  'experimentId',
  'experimentEpoch',
  'surfaceVersion',
  'publishedVersion',
};

/// Maps an SDK [RestageEvent] to the wire [AnalyticsEvent] envelope, attaching
/// the four-level identity and the client [appContext].
///
/// Without an authoritative [rootAttribution], the compatibility mapping is
/// data-driven off [RestageEvent.toMap]: a `flowId` maps to onboarding, a
/// non-null `paywallId` maps to paywall, and any other event is app-wide. An
/// authoritative root binding instead supplies the actual root surface, ID,
/// version, session, and experiment assignment.
/// Promoted conversion dims (`productId`/`offerId`) land on typed envelope
/// fields. Experiment dimensions come only from a complete authoritative root
/// binding; payload claims are scrubbed but never trusted. Every other residual
/// field goes to `properties` **after the reserved-key scrub** (so a custom
/// event can never smuggle render context). `tier`/`source` are NOT set here —
/// the server stamps them.
AnalyticsEvent mapRestageEventToEnvelope(
  RestageEvent event, {
  required String eventId,
  required String anonymousId,
  required String sessionId,
  required AnalyticsAppContext appContext,
  required DateTime now,
  RootAnalyticsEventBinding? rootAttribution,
  String? surfaceSessionId,
  String? userId,
}) {
  final map = event.toMap();
  final flowId = map['flowId'] as String?;
  final paywallId = event.paywallId;

  final String? eventSurface;
  final String? eventSurfaceId;
  final String? eventSurfaceSessionId;
  if (flowId != null) {
    eventSurface = AnalyticsSurface.onboarding;
    eventSurfaceId = flowId;
    eventSurfaceSessionId =
        (map['flowSessionId'] as String?) ?? surfaceSessionId;
  } else if (paywallId != null) {
    eventSurface = AnalyticsSurface.paywall;
    eventSurfaceId = paywallId;
    eventSurfaceSessionId = surfaceSessionId;
  } else {
    eventSurface = null;
    eventSurfaceId = null;
    eventSurfaceSessionId = surfaceSessionId;
  }

  final rootContext = rootAttribution?.context;
  final authoritative = rootAttribution != null;
  final surface = rootAttribution?.surface ?? eventSurface;
  final surfaceId = rootAttribution?.surfaceId ?? eventSurfaceId;
  final effectiveSurfaceSessionId =
      authoritative ? rootContext?.surfaceSessionId : eventSurfaceSessionId;
  final surfaceVersion = authoritative
      ? rootContext?.surfaceVersion
      : (map['flowVersion'] ?? map['surfaceVersion'] ?? map['publishedVersion'])
          ?.toString();
  final hasCompleteRootExperiment = rootContext?.experimentId != null &&
      rootContext?.variantId != null &&
      rootContext?.experimentEpoch != null;

  final properties = scrubReservedKeys(<String, Object?>{
    for (final entry in map.entries)
      if (!_promotedKeys.contains(entry.key)) entry.key: entry.value,
  });

  return AnalyticsEvent(
    eventId: eventId,
    name: event.name,
    occurredAt: (event.firedAt ?? now).toUtc(),
    surface: surface,
    surfaceId: surfaceId,
    surfaceVersion: surfaceVersion,
    surfaceSessionId: effectiveSurfaceSessionId,
    anonymousId: anonymousId,
    sessionId: sessionId,
    userId: userId,
    appContext: appContext,
    productId: map['productId'] as String?,
    offerId: map['offerId'] as String?,
    variantId: hasCompleteRootExperiment ? rootContext?.variantId : null,
    experimentId: hasCompleteRootExperiment ? rootContext?.experimentId : null,
    experimentEpoch:
        hasCompleteRootExperiment ? rootContext?.experimentEpoch : null,
    properties: properties,
  );
}
