import 'package:flutter/foundation.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    show PlacementKeyV1;
import 'package:restage_shared/restage_shared.dart'
    show PlacementBatchRefusalReasonV1;

final Set<(String, PlacementBatchRefusalReasonV1, String?)> _logged = {};

/// Prints one debug-build line the first time [placement] falls back for
/// [reason]; release builds print nothing.
@internal
void debugLogPlacementFallback(
    PlacementKeyV1 placement, PlacementBatchRefusalReasonV1 reason,
    {String? detail}) {
  if (!kDebugMode || !_logged.add((placement.value, reason, detail))) return;
  debugPrint('[restage] placement ${placement.value} shows its fallback '
      '(${placementFallbackReason(reason, detail)}): ${_hint(reason)}');
}

final Set<(String, String)> _loggedNoAnswers = {};

/// Prints one debug-build line the first time [placement] gets no answer for
/// [reason]; release builds print nothing.
@internal
void debugLogPlacementNoAnswer(PlacementKeyV1 placement, String reason,
    [Object? error]) {
  if (!kDebugMode || !_loggedNoAnswers.add((placement.value, reason))) return;
  debugPrint('[restage] placement ${placement.value} shows its fallback '
      '($reason): no answer from the service'
      '${error == null ? '' : ' ($error)'}.');
}

/// The reported reason: the server's code, then its detail when it sent one.
@internal
String placementFallbackReason(
        PlacementBatchRefusalReasonV1 reason, String? detail) =>
    detail == null ? reason.name : '${reason.name}:$detail';

/// Forgets which fallbacks were logged.
@internal
void resetPlacementFallbackLog() {
  _logged.clear();
  _loggedNoAnswers.clear();
}

String _hint(PlacementBatchRefusalReasonV1 reason) => switch (reason) {
      PlacementBatchRefusalReasonV1.unavailable =>
        'nothing is published to it yet. Publish a surface to show it here.',
      PlacementBatchRefusalReasonV1.invalidAuthority =>
        'the server refused this key for it. Check that the API key belongs '
            'to the app that owns this placement.',
      PlacementBatchRefusalReasonV1.unknownLocator =>
        'the server does not know this placement. Check its name and that '
            'this build has reported it.',
      PlacementBatchRefusalReasonV1.invalidRequest =>
        'the request did not match this build. Regenerate and rebuild the app.',
      PlacementBatchRefusalReasonV1.incompatible =>
        'the published version needs a newer app build.',
      PlacementBatchRefusalReasonV1.artifactUnavailable =>
        'its published content could not be fetched. It is retried on the '
            'next mount.',
      PlacementBatchRefusalReasonV1.localClockUnavailable =>
        'its delivery rule needs the device clock and time zone.',
      PlacementBatchRefusalReasonV1.enrollmentRequired =>
        'an experiment needs an assignment key. Check identity setup.',
      PlacementBatchRefusalReasonV1.assignmentUnavailable =>
        'its experiment assignment expired. The next mount enrolls again.',
      PlacementBatchRefusalReasonV1.decodeFailed =>
        'the server response could not be read. Check that the SDK and the '
            'server are current.',
    };
