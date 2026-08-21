import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:restage/src/measurement/measurement_outbox_protocol.dart';
import 'package:restage/src/measurement/measurement_worker_protocol.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

MeasurementOutboxPreparedBatch outboxPreparedBatch({
  String sessionId = 'session.test',
  int sequence = 1,
  bool isFinal = false,
  String variant = 'default',
  int factCount = 1,
}) =>
    MeasurementOutboxPreparedBatch.fromWorkerPreparedBatch(
      workerPreparedBatch(
        sessionId: sessionId,
        sequence: sequence,
        isFinal: isFinal,
        variant: variant,
        factCount: factCount,
      ),
    );

MeasurementWorkerPreparedBatch workerPreparedBatch({
  String sessionId = 'session.test',
  int sequence = 1,
  bool isFinal = false,
  String variant = 'default',
  int factCount = 1,
}) =>
    workerPreparedBatchForRequest(
      ingestRequest(
        sequence: sequence,
        isFinal: isFinal,
        variant: variant,
        factCount: factCount,
      ),
      sessionId: sessionId,
      sequence: sequence,
      isFinal: isFinal,
    );

MeasurementWorkerPreparedBatch workerPreparedBatchForRequest(
  MeasurementIngestRequestV1 request, {
  String sessionId = 'session.test',
  int? sequence,
  bool? isFinal,
  List<int>? canonicalFrameBytes,
  List<int>? canonicalRequestBytes,
  String? canonicalRequestBase64,
  String? frameSha256,
  String? requestSha256,
}) =>
    MeasurementWorkerPreparedBatch(
      batchId: 'batch.test.0001',
      sessionId: sessionId,
      isFinal: isFinal ?? request.factFrame.isFinal,
      sequence: sequence ?? request.factFrame.sequence,
      canonicalFrameBytes:
          canonicalFrameBytes ?? request.factFrameCanonicalBytes,
      canonicalRequestBytes: canonicalRequestBytes ?? request.canonicalBytes,
      canonicalRequestBase64:
          canonicalRequestBase64 ?? request.canonicalRequestBase64,
      frameSha256: frameSha256 ?? request.factFrameSha256,
      requestSha256: requestSha256 ?? request.requestSha256,
      ownedByteCount: 1,
    );

MeasurementIngestRequestV1 ingestRequest({
  int sequence = 1,
  bool isFinal = false,
  String variant = 'default',
  int factCount = 1,
  MeasurementPublicationBindingReferenceV1? bindingReference,
}) {
  if (factCount <= 0 || factCount > 1024) {
    throw ArgumentError.value(factCount, 'factCount');
  }
  final binding = bindingReference ?? _bindingReference;
  final nonce =
      crypto.sha256.convert(utf8.encode(variant)).toString().substring(0, 24);
  final frame = MeasurementFactFrameV1.fromCanonicalBytes(
    CanonicalJsonCodec.encode({
      'bounds': {
        'maximumCounterValue': 10,
        'maximumInteractionCounters': 0,
        'maximumMissingnessEntries': 0,
        'maximumPresentedPoints': factCount,
      },
      'captureSessionNonce': 'capture.$nonce',
      'facts': [
        for (var index = 0; index < factCount; index += 1)
          {
            'interactionState': 'transportTruncated',
            'lineageId': 'lineage.${index.toString().padLeft(4, '0')}',
            'occurrenceId': index.toRadixString(16).padLeft(64, '0'),
          },
      ],
      'finality': {'kind': isFinal ? 'final' : 'pending'},
      'kind': 'measurementFactFrame',
      'missingness': const <Object?>[],
      'publishedContext': ExactMeasurementPublicationContextRefV1(
        bindingReference: binding,
        surfaceIdentity: PublishedSurfaceIdentityV1(
          target: TargetCoordinate(
            organizationId: OrganizationId(11),
            appId: ApplicationId(23),
            environmentTargetId: EnvironmentTargetId(31),
            namedEnvironmentId: NamedEnvironmentId(37),
            runtimePlane: RuntimePlane.sandbox,
          ),
          surfaceId: SurfaceId('surface.outbox.test'),
        ),
        surfaceRevisionId: SurfaceRevisionId('surface.outbox.test.v1'),
        artifactGraphHash: CanonicalDigest('b' * 64),
        measurementManifestHash: CanonicalDigest('c' * 64),
      ).toJson(),
      'retryPolicy': const {'kind': 'byteIdenticalSameSequence'},
      'rootPresentation': const {'kind': 'successfulFirstPaint'},
      'schemaVersion': 1,
      'sequence': sequence,
      'truncation': const {
        'interactionCounters': {'droppedCount': 0, 'truncated': false},
        'presentedPoints': {'droppedCount': 0, 'truncated': false},
      },
    }),
  );
  return MeasurementIngestRequestV1.fromFactFrame(frame);
}

MeasurementIngestReceiptV1 receiptForRecord(
  MeasurementOutboxRecord record, {
  String? captureSessionNonce,
  String? factFrameSha256,
  bool? isFinal,
  MeasurementPublicationBindingReferenceV1? publicationBindingReference,
  String? requestSha256,
  int? sequence,
}) {
  final batch = record.batch;
  return MeasurementIngestReceiptV1.accepted(
    acceptedObservationCount: 0,
    captureSessionNonce: captureSessionNonce ?? batch.captureSessionNonce,
    factFrameSha256: factFrameSha256 ?? batch.factFrameSha256,
    isFinal: isFinal ?? batch.isFinal,
    persistedAtMicros: 4100000,
    publicationBindingReference: publicationBindingReference ??
        MeasurementPublicationBindingReferenceV1.fromCanonicalBytes(
          batch.publicationBindingReferenceCanonicalBytes,
        ),
    receiptId: 'receipt.outbox.test.0001',
    requestSha256: requestSha256 ?? batch.requestSha256,
    rootObservationUnitKey: 'root.outbox.test.0001',
    sequence: sequence ?? batch.sequence,
  );
}

MeasurementOutboxAcknowledgement acknowledgementForRecord(
  MeasurementOutboxRecord record,
) =>
    MeasurementOutboxAcknowledgement.fromReceipt(
      record: record,
      receipt: receiptForRecord(record),
    )!;

String receiptEnvelopeForRecord(MeasurementOutboxRecord record) =>
    receiptEnvelope(receiptForRecord(record));

String receiptEnvelope(MeasurementIngestReceiptV1 receipt) =>
    '{"receiptCanonicalBase64":"${receipt.canonicalReceiptBase64}"}';

String receiptEnvelopeForCanonicalBytes(List<int> canonicalBytes) =>
    '{"receiptCanonicalBase64":"${base64Url.encode(canonicalBytes).replaceAll('=', '')}"}';

MeasurementPublicationBindingReferenceV1 alternateBindingReference() =>
    MeasurementPublicationBindingReferenceV1(
      publicationAuthorityReference:
          _bindingReference.publicationAuthorityReference,
      bindingDigest: CanonicalDigest('5' * 64),
    );

final MeasurementPublicationBindingReferenceV1 _bindingReference =
    MeasurementPublicationBindingReferenceV1(
  publicationAuthorityReference: RegisteredPublicationAuthorityReferenceV1(
    authorityId: MeasurementPublicationAuthorityId('authority.outbox.test'),
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
