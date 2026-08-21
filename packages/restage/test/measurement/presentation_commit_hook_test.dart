import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/measurement/presentation_commit.dart';
import 'package:restage/src/measurement/measurement_runtime_capture.dart';
import 'package:restage/src/runtime/error_boundary.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

void main() {
  testWidgets(
    'a real successful first paint emits one exact fact after a test callback',
    (tester) async {
      final sink = _RecordingSink();
      final revision = _publishedRevision('success');
      final routeHandle = MeasurementPresentationRouteHandle.open(
        publishedSurfaceRevision: revision,
        captureSink: sink,
      );
      final callbackSinkCounts = <int>[];

      await tester.pumpWidget(
        _host(
          routeHandle: routeHandle,
          child: _TestOnlyCallback(
            onInvoke: () => callbackSinkCounts.add(sink.facts.length),
            child: const SizedBox.square(dimension: 20),
          ),
        ),
      );

      expect(callbackSinkCounts, isNotEmpty);
      expect(callbackSinkCounts, everyElement(0));
      expect(sink.facts, hasLength(1));
      expect(
        sink.facts.single.context.publishedSurfaceRevision,
        same(revision),
      );
      expect(
        sink.facts.single.context.artifactGraphHash,
        revision.artifactGraphHash,
      );
      expect(
        sink.facts.single.context.measurementManifestHash,
        revision.measurementManifestHash,
      );
      expect(
        sink.facts.single.context.rootArtifactOccurrenceEdgeToken,
        revision.rootArtifactOccurrenceEdgeToken,
      );
    },
  );

  testWidgets(
    'the production capture session cannot emit before and can emit after its real first paint',
    (tester) async {
      final revision = _publishedRevision('capture-session');
      final mountedContext = MeasurementMountedArtifactContext(
        artifactGraphHash: revision.artifactGraphHash,
        artifactId: revision.rootArtifactId,
        artifactOccurrenceEdgeToken: revision.rootArtifactOccurrenceEdgeToken,
        measurementManifestHash: revision.measurementManifestHash,
        surfaceRevisionId: revision.revisionId,
      );
      final routeTable = MeasurementRuntimeRouteTable(
        mountedArtifactContext: mountedContext,
        routes: [
          MeasurementRuntimeRouteDeclaration(
            token: OpaqueMeasurementEventSlotToken('capture-session-slot'),
            occurrenceId: CanonicalDigest('c' * 64),
            lineageId: PointLineageId('lineage.capture-session'),
          ),
        ],
      );
      final bindingReference = _bindingReference('c');
      final session = MeasurementRuntimeCaptureSession(
        bounds: MeasurementFactFrameBounds(
          maximumCounterValue: 1,
          maximumPresentedPoints: 1,
          maximumInteractionCounters: 1,
          maximumMissingnessEntries: 1,
        ),
        captureSessionNonce: MeasurementCaptureSessionNonce(
          'capture-session-real-first-paint',
        ),
        publicationContextRef: _publicationContext(
          revision: revision,
          bindingReference: bindingReference,
        ),
        routeTable: routeTable,
        sequence: 1,
      );
      final routeHandle = MeasurementPresentationRouteHandle.open(
        publishedSurfaceRevision: revision,
        captureSink: session,
      );

      expect(session.teardown, throwsStateError);

      await tester.pumpWidget(
        _host(
          routeHandle: routeHandle,
          child: const SizedBox.square(dimension: 20),
        ),
      );
      await tester.pump();

      final frame = decodeCanonicalObject(session.teardown().canonicalBytes);
      expect(frame['rootPresentation'], const {'kind': 'successfulFirstPaint'});
      expect(
        frame['publishedContext'],
        _publicationContext(
          revision: revision,
          bindingReference: bindingReference,
        ).toJson(),
      );
    },
  );

  testWidgets('duplicate paints emit exactly one presentation fact', (
    tester,
  ) async {
    final sink = _RecordingSink();
    final routeHandle = MeasurementPresentationRouteHandle.open(
      publishedSurfaceRevision: _publishedRevision('duplicate'),
      captureSink: sink,
    );

    await tester.pumpWidget(
      _host(
        routeHandle: routeHandle,
        child: const SizedBox.square(dimension: 20),
      ),
    );
    await tester.pumpWidget(
      _host(
        routeHandle: routeHandle,
        child: const SizedBox.square(
          key: ValueKey<String>('second-real-paint'),
          dimension: 20,
        ),
      ),
    );
    await tester.pump();

    expect(sink.facts, hasLength(1));
  });

  testWidgets('a capture rejection fails closed and is never retried', (
    tester,
  ) async {
    final sink = _ThrowingSink();
    final routeHandle = MeasurementPresentationRouteHandle.open(
      publishedSurfaceRevision: _publishedRevision('capture-rejected'),
      captureSink: sink,
    );

    await tester.pumpWidget(
      _host(
        routeHandle: routeHandle,
        child: const SizedBox.square(dimension: 20),
      ),
    );
    await tester.pumpWidget(
      _host(
        routeHandle: routeHandle,
        child: const SizedBox.square(
          key: ValueKey<String>('capture-rejected-repaint'),
          dimension: 20,
        ),
      ),
    );

    expect(sink.attempts, 1);
  });

  testWidgets('a failed render permanently fails the presentation closed', (
    tester,
  ) async {
    final sink = _RecordingSink();
    var failures = 0;
    final routeHandle = MeasurementPresentationRouteHandle.open(
      publishedSurfaceRevision: _publishedRevision('failed-render'),
      captureSink: sink,
    );

    await tester.pumpWidget(
      _host(
        routeHandle: routeHandle,
        child: RuntimeErrorBoundary(
          onFirstPaintSuccess: () {},
          onError: (_, __) => failures += 1,
          errorReplacement: (_, __, ___) => const SizedBox.shrink(),
          child: const _ThrowDuringPaint(),
        ),
      ),
    );
    await tester.pump();
    expect(failures, 1);

    await tester.pumpWidget(
      _host(
        routeHandle: routeHandle,
        child: const SizedBox.square(dimension: 20),
      ),
    );
    await tester.pump();

    expect(sink.facts, isEmpty);
  });

  testWidgets('an unmounted route rejects a later real paint callback', (
    tester,
  ) async {
    final sink = _RecordingSink();
    final routeHandle = MeasurementPresentationRouteHandle.open(
      publishedSurfaceRevision: _publishedRevision('unmounted'),
      captureSink: sink,
    );

    await tester.pumpWidget(
      _host(
        routeHandle: routeHandle,
        offstage: true,
        child: const SizedBox.square(dimension: 20),
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(
      _host(
        routeHandle: routeHandle,
        child: const SizedBox.square(dimension: 20),
      ),
    );
    await tester.pump();

    expect(sink.facts, isEmpty);
  });

  testWidgets('replacing a mounted route rejects the stale handle', (
    tester,
  ) async {
    final staleSink = _RecordingSink();
    final nextSink = _RecordingSink();
    final staleHandle = MeasurementPresentationRouteHandle.open(
      publishedSurfaceRevision: _publishedRevision('stale'),
      captureSink: staleSink,
    );
    final nextHandle = MeasurementPresentationRouteHandle.open(
      publishedSurfaceRevision: _publishedRevision('next'),
      captureSink: nextSink,
    );

    await tester.pumpWidget(
      _host(
        routeHandle: staleHandle,
        offstage: true,
        child: const SizedBox.square(dimension: 20),
      ),
    );
    await tester.pumpWidget(
      _host(
        routeHandle: nextHandle,
        child: const SizedBox.square(dimension: 20),
      ),
    );
    await tester.pump();

    expect(staleSink.facts, isEmpty);
    expect(nextSink.facts, hasLength(1));
  });

  testWidgets(
    'a route superseded during paint cannot commit after the paint returns',
    (tester) async {
      final sink = _RecordingSink();
      final routeHandle = MeasurementPresentationRouteHandle.open(
        publishedSurfaceRevision: _publishedRevision('superseded'),
        captureSink: sink,
      );

      await tester.pumpWidget(
        _host(
          routeHandle: routeHandle,
          child: _PaintProbe(
            onPaint: routeHandle.supersede,
            child: const SizedBox.square(dimension: 20),
          ),
        ),
      );
      await tester.pump();

      expect(sink.facts, isEmpty);
    },
  );

  testWidgets('a route rolled over during paint cannot commit a late fact', (
    tester,
  ) async {
    final sink = _RecordingSink();
    final routeHandle = MeasurementPresentationRouteHandle.open(
      publishedSurfaceRevision: _publishedRevision('rollover'),
      captureSink: sink,
    );

    await tester.pumpWidget(
      _host(
        routeHandle: routeHandle,
        child: _PaintProbe(
          onPaint: routeHandle.rollover,
          child: const SizedBox.square(dimension: 20),
        ),
      ),
    );
    await tester.pump();

    expect(sink.facts, isEmpty);
  });
}

Widget _host({
  required MeasurementPresentationRouteHandle routeHandle,
  required Widget child,
  bool offstage = false,
}) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: Offstage(
        offstage: offstage,
        child: MeasurementPresentationCommitHook(
          key: const ValueKey<String>('measurement-presentation-hook'),
          routeHandle: routeHandle,
          child: child,
        ),
      ),
    );

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

ExactMeasurementPublicationContextRefV1 _publicationContext({
  required PublishedSurfaceRevisionV1 revision,
  required MeasurementPublicationBindingReferenceV1 bindingReference,
}) =>
    ExactMeasurementPublicationContextRefV1(
      bindingReference: bindingReference,
      surfaceIdentity: revision.surfaceIdentity,
      surfaceRevisionId: revision.revisionId,
      artifactGraphHash: revision.artifactGraphHash,
      measurementManifestHash: revision.measurementManifestHash,
    );

MeasurementPublicationBindingReferenceV1 _bindingReference(String seed) {
  final candidate = MeasurementPublicationCandidateReferenceV1(
    candidateDigest: CanonicalDigest(seed * 64),
    selectedPublicationManifestDigest: CanonicalDigest('b' * 64),
    declaredArtifactBytesDigest: CanonicalDigest('c' * 64),
    assembledPublicationUploadDigest: CanonicalDigest('d' * 64),
    measurementPublicationDraftDigest: CanonicalDigest('e' * 64),
  );
  return MeasurementPublicationBindingReferenceV1(
    publicationAuthorityReference: RegisteredPublicationAuthorityReferenceV1(
      authorityId: MeasurementPublicationAuthorityId(
        'authority.presentation.$seed',
      ),
      externalPublicationAuthorityRef: 'mpa1.${seed.toUpperCase() * 32}',
      candidateReference: candidate,
      immutablePublicationDigest: CanonicalDigest('f' * 64),
      declaredArtifactBytesDigest: candidate.declaredArtifactBytesDigest,
    ),
    bindingDigest: CanonicalDigest('0' * 64),
  );
}

final class _RecordingSink implements MeasurementPresentationCaptureSink {
  final facts = <MeasurementSuccessfulPresentationFact>[];

  @override
  void recordSuccessfulPresentation(
    MeasurementSuccessfulPresentationFact fact,
  ) {
    facts.add(fact);
  }
}

final class _ThrowingSink implements MeasurementPresentationCaptureSink {
  var attempts = 0;

  @override
  void recordSuccessfulPresentation(
      MeasurementSuccessfulPresentationFact fact) {
    attempts += 1;
    throw StateError('capture unavailable');
  }
}

final class _TestOnlyCallback extends StatelessWidget {
  const _TestOnlyCallback({required this.onInvoke, required this.child});

  final VoidCallback onInvoke;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    onInvoke();
    return child;
  }
}

final class _PaintProbe extends SingleChildRenderObjectWidget {
  const _PaintProbe({required this.onPaint, required super.child});

  final VoidCallback onPaint;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPaintProbe(onPaint);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderPaintProbe renderObject,
  ) {
    renderObject.onPaint = onPaint;
  }
}

final class _RenderPaintProbe extends RenderProxyBox {
  _RenderPaintProbe(this._onPaint);

  VoidCallback _onPaint;

  set onPaint(VoidCallback value) => _onPaint = value;

  @override
  void paint(PaintingContext context, Offset offset) {
    _onPaint();
    super.paint(context, offset);
  }
}

final class _ThrowDuringPaint extends LeafRenderObjectWidget {
  const _ThrowDuringPaint();

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderThrow();
}

final class _RenderThrow extends RenderBox {
  @override
  void performLayout() {
    size = constraints.constrain(const Size.square(20));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    throw StateError('test paint failure');
  }
}
