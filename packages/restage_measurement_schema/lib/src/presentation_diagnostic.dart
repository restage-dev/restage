import 'canonical.dart';

/// Closed counts of genuine root-paint reports.
enum MeasurementRootPresentationReportsV1 { none, one, many }

/// Closed reasons a presentation attempt ended.
enum MeasurementPresentationFinishReasonV1 {
  committed,
  abandoned,
  superseded,
  paintFailed,
  captureRejected,
  unknown,
}

/// Terminal observations for one presentation attempt.
final class MeasurementPresentationDiagnosticV1 extends CanonicalValue {
  const MeasurementPresentationDiagnosticV1({
    required this.rootPresentationReports,
    required this.stepObserved,
    required this.finishReason,
    required this.captureIncomplete,
  });

  factory MeasurementPresentationDiagnosticV1.fromJson(
      Map<String, Object?> json) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {
        'captureIncomplete',
        'finishReason',
        'kind',
        'rootPresentationReports',
        'schemaVersion',
        'stepObserved'
      },
      requiredKeys: const {
        'captureIncomplete',
        'finishReason',
        'kind',
        'rootPresentationReports',
        'schemaVersion',
        'stepObserved'
      },
      path: 'measurementPresentationDiagnostic',
    );
    validateCanonicalDocument(reader,
        expectedKind: 'measurementPresentationDiagnostic');
    return MeasurementPresentationDiagnosticV1(
      captureIncomplete: reader.boolean('captureIncomplete'),
      finishReason: MeasurementPresentationFinishReasonV1.values
          .byName(reader.string('finishReason')),
      rootPresentationReports: MeasurementRootPresentationReportsV1.values
          .byName(reader.string('rootPresentationReports')),
      stepObserved: reader.boolean('stepObserved'),
    );
  }

  factory MeasurementPresentationDiagnosticV1.fromCanonicalBytes(
          List<int> bytes) =>
      verifyCanonicalRoundTrip(
        MeasurementPresentationDiagnosticV1.fromJson(
            decodeCanonicalObject(bytes)),
        bytes,
        path: 'measurementPresentationDiagnostic',
      );

  final MeasurementRootPresentationReportsV1 rootPresentationReports;
  final bool stepObserved;
  final MeasurementPresentationFinishReasonV1 finishReason;
  final bool captureIncomplete;

  @override
  Map<String, Object?> toJson() => {
        'captureIncomplete': captureIncomplete,
        'finishReason': finishReason.name,
        'kind': 'measurementPresentationDiagnostic',
        'rootPresentationReports': rootPresentationReports.name,
        'schemaVersion': kMeasurementSchemaVersion,
        'stepObserved': stepObserved,
      };
}
