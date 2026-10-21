import 'package:meta/meta.dart';
import 'package:restage_shared/restage_shared.dart' show Surface;

import 'event_enums.dart';
import 'surface_assignment.dart';

part 'analytics_properties.dart';
part 'delivery_events.dart';
part 'flow_events.dart';
part 'interaction_events.dart';
part 'presentation_events.dart';

/// Base type for every event the Restage SDK emits.
///
/// Event handlers should include a wildcard or default case so they remain
/// compatible with additional event types:
/// ```dart
/// RestagePaywall(
///   onEvent: (event) {
///     switch (event) {
///       case PaywallViewed(): ...;
///       case _: break;
///     }
///   },
/// );
/// ```
@immutable
sealed class RestageEvent {
  /// Const base constructor. `firedAt` is populated by the SDK at fire time;
  /// passing it explicitly is supported for tests and replay.
  const RestageEvent({this.paywallId, this.firedAt, this.attribution});

  /// Canonical snake_case event name, safe for vendor analytics forwarding.
  String get name;

  /// Which paywall fired this event. `null` for app-wide lifecycle events
  /// (e.g. `FlowUnavailable` fired before a surface is mounted).
  final String? paywallId;

  /// Wall-clock time the event was fired. Populated by the SDK runtime.
  final DateTime? firedAt;

  /// Exact surface presentation captured when this event was emitted.
  final SurfaceEventAttribution? attribution;

  /// Stable identifier of the surface that emitted this event.
  String? get surfaceId => attribution?.surfaceId;

  /// Product category of the surface that emitted this event.
  Surface? get surfaceType => attribution?.surfaceType;

  /// Exact rendered-content version at event emission.
  String? get surfaceVersion => attribution?.surfaceVersion;

  /// Served experiment assignment at event emission.
  SurfaceAssignment? get assignment => attribution?.assignment;

  /// Experiment identifier at event emission.
  String? get experimentId => assignment?.experimentId;

  /// Experiment revision identifier at event emission.
  String? get experimentRevisionId => assignment?.experimentRevisionId;

  /// Experiment epoch identifier at event emission.
  String? get experimentEpochId => assignment?.experimentEpochId;

  /// Served variant identifier at event emission.
  String? get variantId => assignment?.variantId;

  /// Bounded, vendor-neutral properties safe to forward with [name].
  /// Property names use the `restage_` prefix.
  Map<String, Object> get analyticsProperties => _analyticsPropertiesFor(this);

  /// Complete event representation, including fields that are not suitable for
  /// analytics forwarding. Use [analyticsProperties] for vendor SDKs.
  Map<String, Object?> toMap();
}

/// Creates the immutable runtime snapshot delivered to event listeners.
@internal
RestageEvent snapshotRestageEventForEmission(
  RestageEvent event, {
  required DateTime firedAt,
  required SurfaceEventAttribution? attribution,
}) =>
    switch (event) {
      PaywallLoadStarted() => PaywallLoadStarted(
          paywallId: event.paywallId!,
          firedAt: event.firedAt ?? firedAt,
          attribution: attribution,
        ),
      PaywallLoadCompleted(:final loadDuration, :final cacheHit) =>
        PaywallLoadCompleted(
          paywallId: event.paywallId!,
          loadDuration: loadDuration,
          cacheHit: cacheHit,
          firedAt: event.firedAt ?? firedAt,
          attribution: attribution,
        ),
      PaywallLoadFailed(:final errorCode, :final message, :final retryable) =>
        PaywallLoadFailed(
          paywallId: event.paywallId!,
          errorCode: errorCode,
          message: message,
          retryable: retryable,
          firedAt: event.firedAt ?? firedAt,
          attribution: attribution,
        ),
      PaywallViewed(:final publishedVersion) => PaywallViewed(
          paywallId: event.paywallId!,
          publishedVersion: publishedVersion,
          firedAt: event.firedAt ?? firedAt,
          attribution: attribution,
        ),
      PaywallDismissed(:final reason, :final timeOnPaywall) => PaywallDismissed(
          paywallId: event.paywallId!,
          reason: reason,
          timeOnPaywall: timeOnPaywall,
          firedAt: event.firedAt ?? firedAt,
          attribution: attribution,
        ),
      SurfaceDeliveryRateLimited(
        :final surface,
        :final surfaceId,
        :final retryAfter,
      ) =>
        SurfaceDeliveryRateLimited(
          surface: surface,
          surfaceId: surfaceId,
          retryAfter: retryAfter,
          firedAt: event.firedAt ?? firedAt,
          attribution: attribution,
        ),
      PagerPageChanged(:final pageIndex, :final pageCount) => PagerPageChanged(
          pageIndex: pageIndex,
          pageCount: pageCount,
          firedAt: event.firedAt ?? firedAt,
          attribution: attribution,
        ),
      SurfacePointPresented(:final occurrenceId, :final lineageId) =>
        SurfacePointPresented(
          occurrenceId: occurrenceId,
          lineageId: lineageId,
          firedAt: event.firedAt ?? firedAt,
          attribution: attribution,
        ),
      SurfacePointInteracted(:final occurrenceId, :final lineageId) =>
        SurfacePointInteracted(
          occurrenceId: occurrenceId,
          lineageId: lineageId,
          firedAt: event.firedAt ?? firedAt,
          attribution: attribution,
        ),
      SurveyQuestionResponded(:final questionId, :final questionIndex) =>
        SurveyQuestionResponded(
          questionId: questionId,
          questionIndex: questionIndex,
          firedAt: event.firedAt ?? firedAt,
          attribution: attribution,
        ),
      PaywallCustomEvent(:final eventName, :final args) => PaywallCustomEvent(
          paywallId: event.paywallId!,
          eventName: eventName,
          args: args,
          firedAt: event.firedAt ?? firedAt,
          attribution: attribution,
        ),
      FlowUnavailable(
        :final flowId,
        :final flowVersion,
        :final reason,
        :final message
      ) =>
        FlowUnavailable(
          flowId: flowId,
          flowVersion: flowVersion,
          reason: reason,
          message: message,
          firedAt: event.firedAt ?? firedAt,
          attribution: attribution,
        ),
      FlowCustomEvent(
        :final flowId,
        :final flowVersion,
        :final resolvedVersion,
        :final eventName,
        :final fields,
      ) =>
        FlowCustomEvent(
          flowId: flowId,
          flowVersion: flowVersion,
          resolvedVersion: resolvedVersion,
          eventName: eventName,
          fields: fields,
          firedAt: event.firedAt ?? firedAt,
          attribution: attribution,
        ),
      FlowStarted(
        :final flowId,
        :final flowVersion,
        :final resolvedVersion,
        :final flowSessionId,
        :final parentFlowSessionId,
      ) =>
        FlowStarted(
          flowId: flowId,
          flowVersion: flowVersion,
          resolvedVersion: resolvedVersion,
          flowSessionId: flowSessionId,
          parentFlowSessionId: parentFlowSessionId,
          firedAt: event.firedAt ?? firedAt,
          attribution: attribution,
        ),
      FlowCompleted(
        :final flowId,
        :final flowVersion,
        :final resolvedVersion,
        :final flowSessionId,
        :final parentFlowSessionId,
      ) =>
        FlowCompleted(
          flowId: flowId,
          flowVersion: flowVersion,
          resolvedVersion: resolvedVersion,
          flowSessionId: flowSessionId,
          parentFlowSessionId: parentFlowSessionId,
          firedAt: event.firedAt ?? firedAt,
          attribution: attribution,
        ),
      FlowDismissed(
        :final flowId,
        :final flowVersion,
        :final resolvedVersion,
        :final flowSessionId,
      ) =>
        FlowDismissed(
          flowId: flowId,
          flowVersion: flowVersion,
          resolvedVersion: resolvedVersion,
          flowSessionId: flowSessionId,
          firedAt: event.firedAt ?? firedAt,
          attribution: attribution,
        ),
      OnboardingStepViewed(
        :final flowId,
        :final flowVersion,
        :final resolvedVersion,
        :final flowSessionId,
        :final screenId,
        :final stepIndex,
        :final stepCount,
      ) =>
        OnboardingStepViewed(
          flowId: flowId,
          flowVersion: flowVersion,
          resolvedVersion: resolvedVersion,
          flowSessionId: flowSessionId,
          screenId: screenId,
          stepIndex: stepIndex,
          stepCount: stepCount,
          firedAt: event.firedAt ?? firedAt,
          attribution: attribution,
        ),
      OnboardingSkipped(
        :final flowId,
        :final flowVersion,
        :final resolvedVersion,
        :final flowSessionId,
        :final atScreenId,
        :final stepIndex,
      ) =>
        OnboardingSkipped(
          flowId: flowId,
          flowVersion: flowVersion,
          resolvedVersion: resolvedVersion,
          flowSessionId: flowSessionId,
          atScreenId: atScreenId,
          stepIndex: stepIndex,
          firedAt: event.firedAt ?? firedAt,
          attribution: attribution,
        ),
      OnboardingPermissionResponse(
        :final flowId,
        :final flowVersion,
        :final resolvedVersion,
        :final flowSessionId,
        :final permission,
        :final granted,
      ) =>
        OnboardingPermissionResponse(
          flowId: flowId,
          flowVersion: flowVersion,
          resolvedVersion: resolvedVersion,
          flowSessionId: flowSessionId,
          permission: permission,
          granted: granted,
          firedAt: event.firedAt ?? firedAt,
          attribution: attribution,
        ),
    };
