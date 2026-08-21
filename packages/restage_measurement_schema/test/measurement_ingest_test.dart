import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:test/test.dart';

import 'support/exact_publication_context_test_support.dart';

void main() {
  group('MeasurementIngestRequestV1', () {
    test('encodes the exact authenticated request from one validated frame',
        () {
      final frame = _validatedFrame();

      final request = MeasurementIngestRequestV1.fromFactFrame(frame);
      final document = decodeCanonicalObject(request.canonicalBytes);

      expect(document.keys, {
        'factFrameCanonicalBase64',
        'factFrameSha256',
        'kind',
        'schemaVersion',
      });
      expect(document['kind'], 'authenticatedMeasurementIngestRequest');
      expect(document['schemaVersion'], 1);
      expect(
        document['factFrameCanonicalBase64'],
        _base64Url(frame.canonicalBytes),
      );
      expect(document['factFrameSha256'], frame.frameSha256.hex);
      expect(request.factFrameSha256, frame.frameSha256.hex);

      final decoded = MeasurementIngestRequestV1.fromBase64(
        request.canonicalRequestBase64,
      );
      expect(decoded.canonicalBytes, orderedEquals(request.canonicalBytes));
      expect(
        decoded.factFrameCanonicalBytes,
        orderedEquals(frame.canonicalBytes),
      );
      expect(decoded.factFrameSha256, frame.frameSha256.hex);
      expect(decoded.requestSha256, request.requestSha256);
    });

    test('rejects a changed embedded-frame digest', () {
      final request = MeasurementIngestRequestV1.fromFactFrame(
        _validatedFrame(),
      );
      final document = decodeCanonicalObject(request.canonicalBytes);
      final changedDigest = CanonicalJsonCodec.encode({
        ...document,
        'factFrameSha256': '0' * 64,
      });

      expect(
        () => MeasurementIngestRequestV1.fromBase64(_base64Url(changedDigest)),
        throwsA(
          isA<MeasurementIngestCodecException>().having(
            (error) => error.reason,
            'reason',
            'frame_hash_mismatch',
          ),
        ),
      );
    });

    test('rejects a frame with a subject field before encoding', () {
      final frame = decodeCanonicalObject(_validFrameBytes());
      final injectedSubject = CanonicalJsonCodec.encode({
        ...frame,
        'customerId': 'must-not-be-accepted',
      });

      expect(
        () => MeasurementFactFrameV1.fromCanonicalBytes(injectedSubject),
        throwsA(isA<MeasurementIngestCodecException>()),
      );
    });
  });

  group('MeasurementIngestReceiptV1', () {
    test('encodes and strictly round-trips the accepted request proof', () {
      final request = MeasurementIngestRequestV1.fromFactFrame(
        _validatedFrame(),
      );
      final receipt = MeasurementIngestReceiptV1.accepted(
        acceptedObservationCount: 1,
        captureSessionNonce: request.factFrame.captureSessionNonce,
        factFrameSha256: request.factFrameSha256,
        isFinal: request.factFrame.isFinal,
        persistedAtMicros: 4100000,
        publicationBindingReference:
            request.factFrame.publishedContext.bindingReference,
        receiptId: 'receipt.sdk.ingest.0001',
        requestSha256: request.requestSha256,
        rootObservationUnitKey: 'root.sdk.ingest.0001',
        sequence: request.factFrame.sequence,
      );

      final decoded = MeasurementIngestReceiptV1.fromCanonicalBytes(
        receipt.canonicalBytes,
      );
      final decodedBase64 = MeasurementIngestReceiptV1.fromBase64(
        receipt.canonicalReceiptBase64,
      );

      expect(decoded.canonicalBytes, orderedEquals(receipt.canonicalBytes));
      expect(
        decodedBase64.canonicalBytes,
        orderedEquals(receipt.canonicalBytes),
      );
      expect(decoded.requestSha256, request.requestSha256);
      expect(decoded.factFrameSha256, request.factFrameSha256);
      expect(
        decoded.publicationBindingReference,
        request.factFrame.publishedContext.bindingReference,
      );
    });

    test('rejects unknown, missing, wrong-type, and noncanonical receipts', () {
      final request = MeasurementIngestRequestV1.fromFactFrame(
        _validatedFrame(),
      );
      final receipt = MeasurementIngestReceiptV1.accepted(
        acceptedObservationCount: 1,
        captureSessionNonce: request.factFrame.captureSessionNonce,
        factFrameSha256: request.factFrameSha256,
        isFinal: request.factFrame.isFinal,
        persistedAtMicros: 4100000,
        publicationBindingReference:
            request.factFrame.publishedContext.bindingReference,
        receiptId: 'receipt.sdk.ingest.0001',
        requestSha256: request.requestSha256,
        rootObservationUnitKey: 'root.sdk.ingest.0001',
        sequence: request.factFrame.sequence,
      );
      final document = decodeCanonicalObject(receipt.canonicalBytes);
      final binding = Map<String, Object?>.from(
        document['publicationBindingReference']! as Map<String, Object?>,
      );
      final invalid = <List<int>>[
        CanonicalJsonCodec.encode({...document, 'unknown': true}),
        CanonicalJsonCodec.encode(
          Map<String, Object?>.from(document)..remove('requestSha256'),
        ),
        CanonicalJsonCodec.encode({...document, 'requestSha256': 1}),
        CanonicalJsonCodec.encode({
          ...document,
          'publicationBindingReference': {
            ...binding,
            'bindingAlias': binding['bindingDigest'],
          },
        }),
        utf8.encode(' ${utf8.decode(receipt.canonicalBytes)}'),
      ];

      for (final bytes in invalid) {
        expect(
          () => MeasurementIngestReceiptV1.fromCanonicalBytes(bytes),
          throwsA(isA<MeasurementIngestCodecException>()),
        );
      }
    });

    test('requires requestSha256 in the frozen ingest receipt fixture', () {
      final bytes = File(
        'test/fixtures/ingest/ingest_receipt_v1.json',
      ).readAsBytesSync();
      final receipt = MeasurementIngestReceiptV1.fromCanonicalBytes(bytes);
      final requestBytes = File(
        'test/fixtures/ingest/authenticated_ingest_request_v1.json',
      ).readAsBytesSync();

      expect(receipt.canonicalBytes, orderedEquals(bytes));
      expect(receipt.requestSha256, _sha256(requestBytes));
    });
  });
}

MeasurementFactFrameV1 _validatedFrame() =>
    MeasurementFactFrameV1.fromCanonicalBytes(_validFrameBytes());

Uint8List _validFrameBytes() => CanonicalJsonCodec.encode({
      'bounds': {
        'maximumCounterValue': 10,
        'maximumInteractionCounters': 1,
        'maximumMissingnessEntries': 1,
        'maximumPresentedPoints': 1,
      },
      'captureSessionNonce': 'session-sdk-ingest-0001',
      'facts': [
        {
          'interactionCount': {'saturated': false, 'value': 1},
          'interactionState': 'observedValue',
          'lineageId': 'lineage.sdk.ingest',
          'occurrenceId': 'a' * 64,
        },
      ],
      'finality': {'kind': 'final'},
      'kind': 'measurementFactFrame',
      'missingness': [
        {'count': 1, 'state': 'sourceUnavailable'},
      ],
      'publishedContext': exactPublicationContextRefV1(
        target: TargetCoordinate(
          organizationId: OrganizationId(11),
          appId: ApplicationId(23),
          environmentTargetId: EnvironmentTargetId(31),
          namedEnvironmentId: NamedEnvironmentId(37),
          runtimePlane: RuntimePlane.sandbox,
        ),
        surfaceId: SurfaceId('surface.sdk.ingest'),
        surfaceRevisionId: SurfaceRevisionId('surface.sdk.ingest.v1'),
        artifactGraphHash: CanonicalDigest('b' * 64),
        measurementManifestHash: CanonicalDigest('c' * 64),
        bindingReference: _bindingReference,
      ).toJson(),
      'retryPolicy': {'kind': 'byteIdenticalSameSequence'},
      'rootPresentation': {'kind': 'successfulFirstPaint'},
      'schemaVersion': 1,
      'sequence': 1,
      'truncation': {
        'interactionCounters': {'droppedCount': 0, 'truncated': false},
        'presentedPoints': {'droppedCount': 0, 'truncated': false},
      },
    });

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

String _base64Url(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

String _sha256(List<int> bytes) =>
    CanonicalDigest(sha256.convert(bytes).toString()).hex;
