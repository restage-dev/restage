import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/measurement/presentation_attempt_summary.dart';
import 'package:restage/src/measurement/presentation_commit.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

void main() {
  test('root reports saturate at many', () {
    final observer = MeasurementPresentationAttemptObserver();
    expect(observer.summarise().rootPresentationReports,
        MeasurementRootPresentationReportsV1.none);
    observer.recordRootPresentation();
    expect(observer.summarise().rootPresentationReports,
        MeasurementRootPresentationReportsV1.one);
    observer.recordRootPresentation();
    expect(observer.summarise().rootPresentationReports,
        MeasurementRootPresentationReportsV1.many);
    observer.recordRootPresentation();
    expect(observer.summarise().rootPresentationReports,
        MeasurementRootPresentationReportsV1.many);
  });

  test('unrecorded finish is unknown', () {
    expect(MeasurementPresentationAttemptObserver().summarise().finishReason,
        MeasurementPresentationFinishReasonV1.unknown);
  });

  for (final reason in MeasurementPresentationFinishReasonV1.values) {
    test('first finish wins for $reason', () {
      final observer = MeasurementPresentationAttemptObserver();
      observer.recordFinish(reason);
      for (final later in MeasurementPresentationFinishReasonV1.values) {
        observer.recordFinish(later);
      }
      expect(observer.summarise().finishReason, reason);
    });
  }

  test('flags are independent and sticky; summaries are snapshots', () {
    final observer = MeasurementPresentationAttemptObserver();
    final initial = observer.summarise();
    expect(initial.stepObserved, isFalse);
    expect(initial.captureIncomplete, isFalse);
    observer.recordStepObserved();
    observer.recordStepObserved();
    expect(observer.summarise().stepObserved, isTrue);
    expect(observer.summarise().captureIncomplete, isFalse);
    observer.recordCaptureIncomplete();
    observer.recordCaptureIncomplete();
    expect(observer.summarise().captureIncomplete, isTrue);
    expect(observer.summarise().stepObserved, isTrue);
    expect(initial.stepObserved, isFalse);
    expect(initial.captureIncomplete, isFalse);
    final incompleteOnly = MeasurementPresentationAttemptObserver()
      ..recordCaptureIncomplete();
    expect(incompleteOnly.summarise().stepObserved, isFalse);
    expect(incompleteOnly.summarise().captureIncomplete, isTrue);
  });

  testWidgets('a healthy root repaint reports one presentation',
      (tester) async {
    final observer = MeasurementPresentationAttemptObserver();
    final sink = _Sink();
    final handle = MeasurementPresentationRouteHandle.open(
      publishedSurfaceRevision: _publishedRevision('repaint'),
      captureSink: sink,
      observer: observer,
    );
    await tester.pumpWidget(_host(handle, size: 20));
    await tester.pumpWidget(_host(handle, size: 40));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(sink.presentations, 1);
    expect(observer.summarise().rootPresentationReports,
        MeasurementRootPresentationReportsV1.one);
    expect(observer.summarise().finishReason,
        MeasurementPresentationFinishReasonV1.committed);
    expect(observer.summarise().captureIncomplete, isFalse);
  });

  testWidgets('unmount before paint preserves an observed step',
      (tester) async {
    final observer = MeasurementPresentationAttemptObserver();
    final sink = _Sink();
    var aborts = 0;
    final handle = MeasurementPresentationRouteHandle.open(
      publishedSurfaceRevision: _publishedRevision('unpainted'),
      captureSink: sink,
      observer: observer,
      onUncommittedAbort: () => aborts += 1,
    );
    await tester.pumpWidget(
        _host(handle, offstage: true, onBuild: observer.recordStepObserved));
    expect(observer.summarise().stepObserved, isTrue);
    expect(sink.presentations, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(observer.summarise().rootPresentationReports,
        MeasurementRootPresentationReportsV1.none);
    expect(observer.summarise().finishReason,
        MeasurementPresentationFinishReasonV1.abandoned);
    expect(observer.summarise().stepObserved, isTrue);
    expect(aborts, 1);
  });

  testWidgets('capture rejection retains the genuine paint report',
      (tester) async {
    final observer = MeasurementPresentationAttemptObserver();
    final handle = MeasurementPresentationRouteHandle.open(
      publishedSurfaceRevision: _publishedRevision('rejected'),
      captureSink: _Sink(reject: true),
      observer: observer,
    );
    await tester.pumpWidget(_host(handle));
    expect(observer.summarise().rootPresentationReports,
        MeasurementRootPresentationReportsV1.one);
    expect(observer.summarise().finishReason,
        MeasurementPresentationFinishReasonV1.captureRejected);
    expect(observer.summarise().captureIncomplete, isTrue);
  });

  test('supersede maps exactly and rollover remains unknown', () {
    for (final rollover in [false, true]) {
      final observer = MeasurementPresentationAttemptObserver();
      final handle = MeasurementPresentationRouteHandle.open(
        publishedSurfaceRevision: _publishedRevision('invalidated'),
        captureSink: _Sink(),
        observer: observer,
      );
      if (rollover) {
        handle.rollover();
      } else {
        handle.supersede();
      }
      expect(
          observer.summarise().finishReason,
          rollover
              ? MeasurementPresentationFinishReasonV1.unknown
              : MeasurementPresentationFinishReasonV1.superseded);
      expect(observer.summarise().rootPresentationReports,
          MeasurementRootPresentationReportsV1.none);
    }
  });
}

Widget _host(MeasurementPresentationRouteHandle handle,
        {bool offstage = false, double size = 20, VoidCallback? onBuild}) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: Offstage(
        offstage: offstage,
        child: MeasurementPresentationCommitHook(
          routeHandle: handle,
          child: Builder(builder: (_) {
            onBuild?.call();
            return SizedBox.square(dimension: size);
          }),
        ),
      ),
    );

final class _Sink implements MeasurementPresentationCaptureSink {
  _Sink({this.reject = false});
  final bool reject;
  var presentations = 0;

  @override
  void recordSuccessfulPresentation(
      MeasurementSuccessfulPresentationFact fact) {
    if (reject) throw StateError('capture unavailable');
    presentations += 1;
  }
}

PublishedSurfaceRevisionV1 _publishedRevision(String suffix) =>
    PublishedSurfaceRevisionV1(
      revisionId: SurfaceRevisionId('surface.presentation.$suffix.v1'),
      surfaceIdentity: PublishedSurfaceIdentityV1(
        target: TargetCoordinate(
          organizationId: OrganizationId(1),
          appId: ApplicationId(2),
          environmentTargetId: EnvironmentTargetId(3),
          namedEnvironmentId: NamedEnvironmentId(4),
          runtimePlane: RuntimePlane.sandbox,
        ),
        surfaceId: SurfaceId('surface.presentation.$suffix'),
      ),
      analyticsSurfaceKey: AnalyticsSurfaceKey('presentation-$suffix'),
      deliverySurfaceType: DeliverySurfaceTypeId('fixture.presentation'),
      revisionOrdinal: 1,
      rootArtifactId: ArtifactId('artifact.presentation.$suffix'),
      rootArtifactOccurrenceEdgeToken: ArtifactOccurrenceEdgeToken(
        'edge.presentation.$suffix',
      ),
      artifactGraphHash: CanonicalDigest('a' * 64),
      measurementManifestHash: CanonicalDigest('b' * 64),
      measurementSchemaVersion: 1,
      minimumMeasurementClient: 1,
    );
