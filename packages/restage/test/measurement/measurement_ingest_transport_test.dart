import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/src/measurement/measurement_ingest_transport.dart';
import 'package:restage/src/measurement/measurement_runtime_capture.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

void main() {
  group('MeasurementIngestTransport', () {
    test('retries the one canonical request with byte-identical input',
        () async {
      final submission = MeasurementIngestSubmission.fromFactFrame(_frame());
      final adapter = _RecordingRpcAdapter(
        () => const MeasurementIngestRpcAccepted(
          receiptCanonicalBase64: 'cGF5bG9hZC1yZWNlaXB0',
        ),
      );
      final transport = MeasurementIngestTransport.adapter(adapter);

      final first = await transport.submit(submission);
      final retry = await transport.submit(submission);

      expect(
        first,
        isA<MeasurementIngestTransportAccepted>().having(
          (outcome) => outcome.receiptCanonicalBase64,
          'receiptCanonicalBase64',
          'cGF5bG9hZC1yZWNlaXB0',
        ),
      );
      expect(retry, isA<MeasurementIngestTransportAccepted>());
      expect(
        adapter.requests,
        orderedEquals([
          submission.canonicalRequestBase64,
          submission.canonicalRequestBase64,
        ]),
      );
      expect(
        submission.request.factFrameSha256,
        submission.request.factFrame.frameSha256.hex,
      );
    });

    test('maps adapter rejection and conflict to typed outcomes', () async {
      final submission = MeasurementIngestSubmission.fromFactFrame(_frame());

      final rejected = await MeasurementIngestTransport.adapter(
        _RecordingRpcAdapter(() => const MeasurementIngestRpcRejected()),
      ).submit(submission);
      final conflict = await MeasurementIngestTransport.adapter(
        _RecordingRpcAdapter(() => const MeasurementIngestRpcConflict()),
      ).submit(submission);

      expect(rejected, isA<MeasurementIngestTransportRejected>());
      expect(conflict, isA<MeasurementIngestTransportConflict>());
    });

    test('maps session loss and transport errors to unavailable outcomes',
        () async {
      final submission = MeasurementIngestSubmission.fromFactFrame(_frame());

      final unauthenticated = await MeasurementIngestTransport.adapter(
        _RecordingRpcAdapter(
          () => const MeasurementIngestRpcUnauthenticated(),
        ),
      ).submit(submission);
      final transportFailure = await MeasurementIngestTransport.adapter(
        _ThrowingRpcAdapter(),
      ).submit(submission);

      expect(
        unauthenticated,
        isA<MeasurementIngestTransportUnavailable>().having(
          (outcome) => outcome.reason,
          'reason',
          MeasurementIngestUnavailableReason.unauthenticated,
        ),
      );
      expect(
        transportFailure,
        isA<MeasurementIngestTransportUnavailable>().having(
          (outcome) => outcome.reason,
          'reason',
          MeasurementIngestUnavailableReason.transportFailure,
        ),
      );
    });

    test('disabled and no-adapter transports make no adapter call', () async {
      final submission = MeasurementIngestSubmission.fromFactFrame(_frame());
      final adapter = _RecordingRpcAdapter(
        () => const MeasurementIngestRpcAccepted(
          receiptCanonicalBase64: 'must-not-be-used',
        ),
      );

      final disabled = await const MeasurementIngestTransport.disabled().submit(
        submission,
      );
      final noAdapter =
          await const MeasurementIngestTransport.noAdapter().submit(
        submission,
      );

      expect(adapter.requests, isEmpty);
      expect(
        disabled,
        isA<MeasurementIngestTransportUnavailable>().having(
          (outcome) => outcome.reason,
          'reason',
          MeasurementIngestUnavailableReason.disabled,
        ),
      );
      expect(
        noAdapter,
        isA<MeasurementIngestTransportUnavailable>().having(
          (outcome) => outcome.reason,
          'reason',
          MeasurementIngestUnavailableReason.noAdapter,
        ),
      );
    });

    test('maps HTTP adapter unavailable reasons without making them zeros',
        () async {
      final submission = MeasurementIngestSubmission.fromFactFrame(_frame());

      final cases = <MeasurementIngestRpcUnavailableReason,
          MeasurementIngestUnavailableReason>{
        MeasurementIngestRpcUnavailableReason.forbidden:
            MeasurementIngestUnavailableReason.forbidden,
        MeasurementIngestRpcUnavailableReason.serviceUnavailable:
            MeasurementIngestUnavailableReason.serviceUnavailable,
        MeasurementIngestRpcUnavailableReason.unexpectedStatus:
            MeasurementIngestUnavailableReason.unexpectedStatus,
        MeasurementIngestRpcUnavailableReason.malformedResponse:
            MeasurementIngestUnavailableReason.malformedResponse,
        MeasurementIngestRpcUnavailableReason.transportFailure:
            MeasurementIngestUnavailableReason.transportFailure,
      };

      for (final entry in cases.entries) {
        final outcome = await MeasurementIngestTransport.adapter(
          _RecordingRpcAdapter(
            () => MeasurementIngestRpcUnavailable(entry.key),
          ),
        ).submit(submission);

        expect(
          outcome,
          isA<MeasurementIngestTransportUnavailable>().having(
            (value) => value.reason,
            'reason',
            entry.value,
          ),
          reason: entry.key.name,
        );
      }
    });

    test('composes the production adapter through RestageRpcClient', () async {
      final requests = <http.Request>[];
      final client = RestageRpcClient(
        baseUrl: 'https://example.com',
        apiKey: 'rs_pk_test',
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            '{"receiptCanonicalBase64":"cGF5bG9hZC1yZWNlaXB0"}',
            200,
          );
        }),
      );
      final transport = MeasurementIngestTransport.rpc(client);
      final submission = MeasurementIngestSubmission.fromFactFrame(_frame());

      final first = await transport.submit(submission);
      final retry = await transport.submit(submission);

      expect(first, isA<MeasurementIngestTransportAccepted>());
      expect(retry, isA<MeasurementIngestTransportAccepted>());
      expect(requests, hasLength(2));
      for (final request in requests) {
        expect(request.method, 'POST');
        expect(request.url.path, '/sdk/v1/measurement');
        expect(request.headers['Authorization'], 'Bearer rs_pk_test');
        expect(
          request.body,
          '{"canonicalRequestBase64":"${submission.canonicalRequestBase64}"}',
        );
      }
    });
  });

  test('transport contains no legacy analytics or local encoding path', () {
    final source = File(
      'lib/src/measurement/measurement_ingest_transport.dart',
    ).readAsStringSync();

    for (final forbidden in const [
      'analytics_transport.dart',
      'AnalyticsTransport',
      'MeasurementIngestGenerated',
      'GeneratedEndpoint',
      'ingestFrameV1',
      'jsonEncode',
      'sha256',
      '.track(',
      '.flush(',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
  });
}

MeasurementFactFrame _frame() {
  final context = MeasurementMountedArtifactContext(
    artifactGraphHash: CanonicalDigest('a' * 64),
    artifactId: ArtifactId('artifact.sdk.ingest'),
    artifactOccurrenceEdgeToken: ArtifactOccurrenceEdgeToken('edge.sdk.ingest'),
    measurementManifestHash: CanonicalDigest('b' * 64),
    surfaceRevisionId: SurfaceRevisionId('surface.sdk.ingest.v1'),
  );
  final token = OpaqueMeasurementEventSlotToken('opaque-sdk-ingest');
  final routeTable = MeasurementRuntimeRouteTable(
    mountedArtifactContext: context,
    routes: [
      MeasurementRuntimeRouteDeclaration(
        token: token,
        occurrenceId: CanonicalDigest('c' * 64),
        lineageId: PointLineageId('lineage.sdk.ingest'),
      ),
    ],
  );
  final route = routeTable.resolveOpaqueRoute(context: context, token: token)!;
  final session =
      MeasurementRuntimeCaptureSession.testOnlySuccessfulPresentation(
    bounds: MeasurementFactFrameBounds(
      maximumCounterValue: 10,
      maximumPresentedPoints: 1,
      maximumInteractionCounters: 1,
      maximumMissingnessEntries: 1,
    ),
    captureSessionNonce: MeasurementCaptureSessionNonce('session-sdk-ingest'),
    publicationContextRef: _publicationContext(context),
    routeTable: routeTable,
    sequence: 1,
  );
  session.recordPresentation(route);
  return session.teardown();
}

final _bindingReference = MeasurementPublicationBindingReferenceV1(
  publicationAuthorityReference: RegisteredPublicationAuthorityReferenceV1(
    authorityId: MeasurementPublicationAuthorityId('authority.sdk.ingest'),
    externalPublicationAuthorityRef: 'mpa1.${'A' * 32}',
    candidateReference: MeasurementPublicationCandidateReferenceV1(
      candidateDigest: CanonicalDigest('d' * 64),
      selectedPublicationManifestDigest: CanonicalDigest('e' * 64),
      declaredArtifactBytesDigest: CanonicalDigest('f' * 64),
      assembledPublicationUploadDigest: CanonicalDigest('1' * 64),
      measurementPublicationDraftDigest: CanonicalDigest('2' * 64),
    ),
    immutablePublicationDigest: CanonicalDigest('3' * 64),
    declaredArtifactBytesDigest: CanonicalDigest('f' * 64),
  ),
  bindingDigest: CanonicalDigest('4' * 64),
);

ExactMeasurementPublicationContextRefV1 _publicationContext(
  MeasurementMountedArtifactContext context,
) =>
    ExactMeasurementPublicationContextRefV1(
      bindingReference: _bindingReference,
      surfaceIdentity: _transportSurfaceIdentity,
      surfaceRevisionId: context.surfaceRevisionId,
      artifactGraphHash: context.artifactGraphHash,
      measurementManifestHash: context.measurementManifestHash,
    );

final _transportSurfaceIdentity = PublishedSurfaceIdentityV1(
  target: TargetCoordinate(
    organizationId: OrganizationId(1),
    appId: ApplicationId(2),
    environmentTargetId: EnvironmentTargetId(3),
    namedEnvironmentId: NamedEnvironmentId(4),
    runtimePlane: RuntimePlane.sandbox,
  ),
  surfaceId: SurfaceId('surface.sdk.ingest'),
);

final class _RecordingRpcAdapter implements MeasurementIngestRpcAdapter {
  _RecordingRpcAdapter(this._next);

  final MeasurementIngestRpcOutcome Function() _next;
  final requests = <String>[];

  @override
  Future<MeasurementIngestRpcOutcome> submit(
    String canonicalRequestBase64,
  ) async {
    requests.add(canonicalRequestBase64);
    return _next();
  }
}

final class _ThrowingRpcAdapter implements MeasurementIngestRpcAdapter {
  @override
  Future<MeasurementIngestRpcOutcome> submit(
    String canonicalRequestBase64,
  ) async =>
      throw StateError('transport unavailable');
}
