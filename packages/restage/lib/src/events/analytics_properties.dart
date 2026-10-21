part of 'restage_event.dart';

Map<String, Object> _analyticsPropertiesFor(RestageEvent event) {
  final properties = <String, Object>{};
  final attribution = event.attribution;
  if (attribution != null) {
    _string(properties, 'restage_surface_id', attribution.surfaceId);
    _string(
      properties,
      'restage_surface_type',
      attribution.surfaceType.wireName,
    );
    _string(
      properties,
      'restage_surface_version',
      attribution.surfaceVersion,
    );
    final assignment = attribution.assignment;
    if (assignment != null) {
      _string(properties, 'restage_experiment', assignment.experimentId);
      _string(
        properties,
        'restage_experiment_revision',
        assignment.experimentRevisionId,
      );
      _string(
        properties,
        'restage_experiment_epoch',
        assignment.experimentEpochId,
      );
      _string(properties, 'restage_variant', assignment.variantId);
    }
  }

  switch (event) {
    case PaywallLoadStarted():
      break;
    case PaywallLoadCompleted(:final loadDuration, :final cacheHit):
      _number(
          properties, 'restage_load_duration_ms', loadDuration.inMilliseconds);
      properties['restage_cache_hit'] = cacheHit ? 1 : 0;
    case PaywallLoadFailed(:final errorCode, :final retryable):
      _string(properties, 'restage_error_code', errorCode);
      properties['restage_retryable'] = retryable ? 1 : 0;
    case PaywallViewed(:final publishedVersion):
      _number(properties, 'restage_published_version', publishedVersion);
    case PaywallDismissed(:final reason, :final timeOnPaywall):
      _string(properties, 'restage_reason', reason.wireName);
      _number(properties, 'restage_time_on_surface_ms',
          timeOnPaywall.inMilliseconds);
    case SurfaceDeliveryRateLimited(:final retryAfter):
      _number(properties, 'restage_retry_after_ms', retryAfter.inMilliseconds);
    case PagerPageChanged(:final pageIndex, :final pageCount):
      _number(properties, 'restage_page_index', pageIndex);
      _number(properties, 'restage_page_count', pageCount);
    case SurfacePointPresented(:final occurrenceId, :final lineageId):
    case SurfacePointInteracted(:final occurrenceId, :final lineageId):
      _string(properties, 'restage_occurrence_id', occurrenceId);
      _string(properties, 'restage_lineage_id', lineageId);
    case SurveyQuestionResponded(:final questionId, :final questionIndex):
      _string(properties, 'restage_question_id', questionId);
      _number(properties, 'restage_question_index', questionIndex);
    case PaywallCustomEvent(:final eventName):
      _string(properties, 'restage_event_name', eventName);
    case FlowUnavailable(:final flowId, :final flowVersion, :final reason):
      _flow(properties, flowId, flowVersion, null);
      _string(properties, 'restage_reason', reason);
    case FlowCustomEvent(
        :final flowId,
        :final flowVersion,
        :final resolvedVersion,
        :final eventName,
      ):
      _flow(properties, flowId, flowVersion, resolvedVersion);
      _string(properties, 'restage_event_name', eventName);
    case FlowStarted(:final flowId, :final flowVersion, :final resolvedVersion):
    case FlowCompleted(
        :final flowId,
        :final flowVersion,
        :final resolvedVersion,
      ):
    case FlowDismissed(
        :final flowId,
        :final flowVersion,
        :final resolvedVersion,
      ):
      _flow(properties, flowId, flowVersion, resolvedVersion);
    case OnboardingStepViewed(
        :final flowId,
        :final flowVersion,
        :final resolvedVersion,
        :final screenId,
        :final stepIndex,
        :final stepCount,
      ):
      _flow(properties, flowId, flowVersion, resolvedVersion);
      _string(properties, 'restage_screen_id', screenId);
      _number(properties, 'restage_step_index', stepIndex);
      _number(properties, 'restage_step_count', stepCount);
    case OnboardingSkipped(
        :final flowId,
        :final flowVersion,
        :final resolvedVersion,
        :final atScreenId,
        :final stepIndex,
      ):
      _flow(properties, flowId, flowVersion, resolvedVersion);
      _string(properties, 'restage_screen_id', atScreenId);
      _number(properties, 'restage_step_index', stepIndex);
    case OnboardingPermissionResponse(
        :final flowId,
        :final flowVersion,
        :final resolvedVersion,
        :final permission,
        :final granted,
      ):
      _flow(properties, flowId, flowVersion, resolvedVersion);
      _string(properties, 'restage_permission', permission);
      properties['restage_granted'] = granted ? 1 : 0;
  }
  return Map<String, Object>.unmodifiable(properties);
}

void _flow(
  Map<String, Object> properties,
  String flowId,
  int flowVersion,
  int? resolvedVersion,
) {
  _string(properties, 'restage_flow_id', flowId);
  _number(properties, 'restage_flow_version', flowVersion);
  _number(properties, 'restage_resolved_version', resolvedVersion);
}

void _string(
  Map<String, Object> properties,
  String key,
  String? value,
) {
  if (value != null) properties[key] = _truncateAnalyticsString(value);
}

void _number(Map<String, Object> properties, String key, num? value) {
  if (value != null && value.isFinite) properties[key] = value;
}

String _truncateAnalyticsString(String value) {
  final result = StringBuffer();
  var codeUnits = 0;
  for (final rune in value.runes) {
    final safeRune = rune >= 0xd800 && rune <= 0xdfff ? 0xfffd : rune;
    final width = safeRune > 0xffff ? 2 : 1;
    if (codeUnits + width > 100) break;
    result.writeCharCode(safeRune);
    codeUnits += width;
  }
  return result.toString();
}
