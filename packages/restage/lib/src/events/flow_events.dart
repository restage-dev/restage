part of 'restage_event.dart';

/// Fired when an onboarding flow cannot be resolved or rendered.
///
/// Flow events identify the flow, not a paywall. This event mirrors the
/// fail-closed unavailable path used by `RestageOnboarding`.
@immutable
final class FlowUnavailable extends RestageEvent {
  /// Creates a flow-unavailable event.
  const FlowUnavailable({
    required this.flowId,
    required this.flowVersion,
    required this.reason,
    required this.message,
    super.firedAt,
  });

  @override
  String get name => 'flow_unavailable';

  /// Stable onboarding flow identifier.
  final String flowId;

  /// Flow descriptor version.
  final int flowVersion;

  /// Machine-readable unavailable reason.
  final String reason;

  /// Human-readable diagnostic message.
  final String message;

  @override
  Map<String, Object?> toMap() => <String, Object?>{
        'name': name,
        'flowId': flowId,
        'flowVersion': flowVersion,
        'reason': reason,
        'message': message,
        if (firedAt != null) 'firedAt': firedAt!.toIso8601String(),
      };
}

/// Flow-authored semantic event after outbound allowlist filtering.
///
/// [fields] contains only data explicitly declared for this event by the flow
/// document.
@immutable
final class FlowCustomEvent extends RestageEvent {
  /// Creates a filtered custom event emitted by an onboarding flow.
  const FlowCustomEvent({
    required this.flowId,
    required this.flowVersion,
    required this.eventName,
    required this.fields,
    super.firedAt,
  });

  @override
  String get name => 'flow_custom_event';

  /// Stable onboarding flow identifier.
  final String flowId;

  /// Flow descriptor version.
  final int flowVersion;

  /// Flow-authored semantic event name.
  final String eventName;

  /// Filtered allowlisted fields only.
  final Map<String, Object?> fields;

  @override
  Map<String, Object?> toMap() => <String, Object?>{
        'name': name,
        'flowId': flowId,
        'flowVersion': flowVersion,
        'eventName': eventName,
        'fields': fields,
        if (firedAt != null) 'firedAt': firedAt!.toIso8601String(),
      };
}

/// Fired once when a flow runtime frame becomes active, after its initial node
/// is entered.
///
/// For a screen-first flow the initial screen artifact has been selected and
/// decoded when this event is emitted, but the Flutter widget subtree may still
/// fail during build — render failures are reported separately as
/// [FlowUnavailable] with `reason: render_failed`. For a flow whose initial node
/// is a decision, sub-flow, or terminal, this fires when that node is entered,
/// before any screen is shown.
///
/// [flowSessionId] identifies this flow runtime frame. Child flows also include
/// [parentFlowSessionId].
@immutable
final class FlowStarted extends RestageEvent {
  /// Creates a flow-started lifecycle event.
  const FlowStarted({
    required this.flowId,
    required this.flowVersion,
    this.flowSessionId,
    this.parentFlowSessionId,
    super.firedAt,
  });

  @override
  String get name => 'flow_started';

  /// Stable onboarding flow identifier.
  final String flowId;

  /// Flow descriptor version.
  final int flowVersion;

  /// SDK-minted flow session id for this runtime frame.
  final String? flowSessionId;

  /// SDK-minted parent flow session id when this is a child sub-flow.
  final String? parentFlowSessionId;

  @override
  Map<String, Object?> toMap() => <String, Object?>{
        'name': name,
        'flowId': flowId,
        'flowVersion': flowVersion,
        if (flowSessionId != null) 'flowSessionId': flowSessionId,
        if (parentFlowSessionId != null)
          'parentFlowSessionId': parentFlowSessionId,
        if (firedAt != null) 'firedAt': firedAt!.toIso8601String(),
      };
}

/// Fired after an onboarding flow reaches a decoded terminal result.
///
/// Terminal result payloads are filtered and decoded before widget callbacks
/// run; this lifecycle event carries only SDK-defined identity fields.
@immutable
final class FlowCompleted extends RestageEvent {
  /// Creates a flow-completed lifecycle event.
  const FlowCompleted({
    required this.flowId,
    required this.flowVersion,
    this.flowSessionId,
    this.parentFlowSessionId,
    super.firedAt,
  });

  @override
  String get name => 'flow_completed';

  /// Stable onboarding flow identifier.
  final String flowId;

  /// Flow descriptor version.
  final int flowVersion;

  /// SDK-minted flow session id for this runtime frame.
  final String? flowSessionId;

  /// SDK-minted parent flow session id when this is a child sub-flow.
  final String? parentFlowSessionId;

  @override
  Map<String, Object?> toMap() => <String, Object?>{
        'name': name,
        'flowId': flowId,
        'flowVersion': flowVersion,
        if (flowSessionId != null) 'flowSessionId': flowSessionId,
        if (parentFlowSessionId != null)
          'parentFlowSessionId': parentFlowSessionId,
        if (firedAt != null) 'firedAt': firedAt!.toIso8601String(),
      };
}

/// Fired each time an onboarding screen becomes the active screen — a per-screen
/// funnel impression.
///
/// One fires per *forward* screen entry; returning to a prior screen with the
/// built-in back navigation does not re-fire it. Flow id/version/session ride
/// the analytics envelope (they are not duplicated into the per-event payload);
/// [screenId], [stepIndex], and [stepCount] are the event-specific payload.
@immutable
final class OnboardingStepViewed extends RestageEvent {
  /// Creates a step-viewed funnel impression event.
  const OnboardingStepViewed({
    required this.flowId,
    required this.flowVersion,
    required this.screenId,
    required this.stepIndex,
    this.flowSessionId,
    this.stepCount,
    super.firedAt,
  });

  @override
  String get name => 'onboarding_step_viewed';

  /// Stable onboarding flow identifier.
  final String flowId;

  /// Flow descriptor version.
  final int flowVersion;

  /// SDK-minted flow session id for this runtime frame.
  final String? flowSessionId;

  /// The screen state id of the screen that just became active.
  final String screenId;

  /// Zero-based position of this screen in the flow's current navigation depth.
  ///
  /// Returning to an earlier screen yields its lower index again (back is a
  /// pop, not a new impression), so the index stays bounded by how deep the
  /// user has navigated. It saturates at the runtime's retained-history cap on
  /// pathologically deep flows.
  final int stepIndex;

  /// Total number of screens authored in the flow document, when known.
  ///
  /// A best-effort denominator for a "step X of Y" reading. For a linear flow
  /// it is the path length; for a branching flow it is the authored-screen
  /// total (an upper bound on any single path), hence optional.
  final int? stepCount;

  @override
  Map<String, Object?> toMap() => <String, Object?>{
        'name': name,
        'flowId': flowId,
        'flowVersion': flowVersion,
        if (flowSessionId != null) 'flowSessionId': flowSessionId,
        'screenId': screenId,
        'stepIndex': stepIndex,
        if (stepCount != null) 'stepCount': stepCount,
        if (firedAt != null) 'firedAt': firedAt!.toIso8601String(),
      };
}

/// Fired when the user takes the reserved `skip` affordance on an onboarding
/// screen — the funnel-critical opt-out signal.
///
/// Promoted to a first-class event (rather than riding the generic skip custom
/// event) because skip is a drop-off point worth measuring on its own. It is
/// additive: the host still receives whatever skip behavior the flow declares.
@immutable
final class OnboardingSkipped extends RestageEvent {
  /// Creates a skip event.
  const OnboardingSkipped({
    required this.flowId,
    required this.flowVersion,
    required this.atScreenId,
    required this.stepIndex,
    this.flowSessionId,
    super.firedAt,
  });

  @override
  String get name => 'onboarding_skipped';

  /// Stable onboarding flow identifier.
  final String flowId;

  /// Flow descriptor version.
  final int flowVersion;

  /// SDK-minted flow session id for this runtime frame.
  final String? flowSessionId;

  /// The screen state id the user skipped from.
  final String atScreenId;

  /// Zero-based navigation depth of [atScreenId] when skipped (see
  /// [OnboardingStepViewed.stepIndex]).
  final int stepIndex;

  @override
  Map<String, Object?> toMap() => <String, Object?>{
        'name': name,
        'flowId': flowId,
        'flowVersion': flowVersion,
        if (flowSessionId != null) 'flowSessionId': flowSessionId,
        'atScreenId': atScreenId,
        'stepIndex': stepIndex,
        if (firedAt != null) 'firedAt': firedAt!.toIso8601String(),
      };
}

/// Fired when an onboarding permission host-action reports its result —
/// granted or declined.
///
/// A "permission host-action" is any flow host-action whose result reports a
/// `granted` boolean (e.g. the notification-priming action). [permission] is
/// the action's name; [granted] is the user's decision. Both grant and decline
/// fire this event — the decline is exactly the funnel signal worth capturing.
@immutable
final class OnboardingPermissionResponse extends RestageEvent {
  /// Creates a permission-response event.
  const OnboardingPermissionResponse({
    required this.flowId,
    required this.flowVersion,
    required this.permission,
    required this.granted,
    this.flowSessionId,
    super.firedAt,
  });

  @override
  String get name => 'onboarding_permission_response';

  /// Stable onboarding flow identifier.
  final String flowId;

  /// Flow descriptor version.
  final int flowVersion;

  /// SDK-minted flow session id for this runtime frame.
  final String? flowSessionId;

  /// The host-action name that requested the permission.
  final String permission;

  /// Whether the user granted the permission.
  final bool granted;

  @override
  Map<String, Object?> toMap() => <String, Object?>{
        'name': name,
        'flowId': flowId,
        'flowVersion': flowVersion,
        if (flowSessionId != null) 'flowSessionId': flowSessionId,
        'permission': permission,
        'granted': granted,
        if (firedAt != null) 'firedAt': firedAt!.toIso8601String(),
      };
}
