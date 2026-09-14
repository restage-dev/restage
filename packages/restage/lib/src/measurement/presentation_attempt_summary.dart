import 'package:meta/meta.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

/// Bounded observations for one presentation attempt.
@internal
final class MeasurementPresentationAttemptObserver {
  var _rootPresentations = MeasurementRootPresentationReportsV1.none;
  var _stepObserved = false;
  var _captureIncomplete = false;
  MeasurementPresentationFinishReasonV1? _finishReason;

  void recordRootPresentation() {
    _rootPresentations = switch (_rootPresentations) {
      MeasurementRootPresentationReportsV1.none =>
        MeasurementRootPresentationReportsV1.one,
      MeasurementRootPresentationReportsV1.one ||
      MeasurementRootPresentationReportsV1.many =>
        MeasurementRootPresentationReportsV1.many,
    };
  }

  void recordStepObserved() => _stepObserved = true;

  void recordCaptureIncomplete() => _captureIncomplete = true;

  void recordFinish(MeasurementPresentationFinishReasonV1 reason) {
    _finishReason ??= reason;
  }

  MeasurementPresentationDiagnosticV1 summarise() =>
      MeasurementPresentationDiagnosticV1(
        rootPresentationReports: _rootPresentations,
        stepObserved: _stepObserved,
        captureIncomplete: _captureIncomplete,
        finishReason:
            _finishReason ?? MeasurementPresentationFinishReasonV1.unknown,
      );
}
