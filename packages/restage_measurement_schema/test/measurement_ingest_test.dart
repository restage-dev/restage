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

    for (final subjectField in const [
      'customerId',
      'purchaserId',
      'context',
      'data',
    ]) {
      test('rejects a frame with a $subjectField field before encoding', () {
        final frame = decodeCanonicalObject(_validFrameBytes());
        final injectedSubject = CanonicalJsonCodec.encode({
          ...frame,
          subjectField: 'must-not-be-accepted',
        });

        expect(
          () => MeasurementFactFrameV1.fromCanonicalBytes(injectedSubject),
          throwsA(isA<MeasurementIngestCodecException>()),
        );
      });
    }
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

  group('canonical experiment assignment on the fact frame', () {
    test('is absent from ordinary delivery', () {
      expect(_validatedFrame().experimentAssignment, isNull);
    });

    test('carries the opaque carrier', () {
      final frame = _validatedFrame(
        experimentAssignment: _assignment(),
      );
      final assignment = frame.experimentAssignment;

      expect(assignment, isNotNull);
      expect(assignment!.outcomeLinkCarrier, _carrier);
      expect(assignment.toJson(), {
        'kind': 'measurementExperimentAssignment',
        'outcomeLinkCarrier': _carrier,
        'schemaVersion': 1,
      });
    });

    test('retains independently bounded first occurrences on each fact', () {
      final frame = _validatedFrame(
        experimentAssignment: _assignment(),
        factFields: {
          'presentationFirstOccurrenceMicros': 0,
          'interactionFirstOccurrenceMicros':
              measurementIngestMaximumOutcomeWitnessMicros,
        },
      );
      expect(frame.facts.single.presentationFirstOccurrenceMicros, 0);
      expect(
        frame.facts.single.interactionFirstOccurrenceMicros,
        measurementIngestMaximumOutcomeWitnessMicros,
      );
      expect(
        frame.facts.single.toJson()['presentationFirstOccurrenceMicros'],
        0,
      );
      expect(
        frame.facts.single.toJson()['interactionFirstOccurrenceMicros'],
        measurementIngestMaximumOutcomeWitnessMicros,
      );
      expect(
        _validatedFrame().facts.single.toJson(),
        isNot(contains('presentationFirstOccurrenceMicros')),
      );
      expect(
        _validatedFrame().facts.single.toJson(),
        isNot(contains('interactionFirstOccurrenceMicros')),
      );
    });

    test('rejects out-of-bound, unordered and unsupported fact witnesses', () {
      for (final field in [
        'presentationFirstOccurrenceMicros',
        'interactionFirstOccurrenceMicros',
      ]) {
        for (final value in [
          -1,
          measurementIngestMaximumOutcomeWitnessMicros + 1,
          '1',
          1.5,
          null,
        ]) {
          expect(
            () => MeasurementFact.fromJson(
              {
                ..._validatedFrame().facts.single.toJson(),
                field: value,
              },
              bounds: _validatedFrame().bounds,
            ),
            throwsA(isA<MeasurementIngestCodecException>()),
            reason: '$field: $value',
          );
        }
      }
      for (final fields in <Map<String, Object?>>[
        {
          'presentationFirstOccurrenceMicros': 10,
          'interactionFirstOccurrenceMicros': 9,
        },
        {
          'interactionState': 'observedZero',
          'interactionCount': {'saturated': false, 'value': 0},
          'interactionFirstOccurrenceMicros': 1,
        },
        {
          'interactionState': 'transportTruncated',
          'interactionCount': null,
          'interactionFirstOccurrenceMicros': 1,
        },
      ]) {
        expect(
          () => _validatedFrame(factFields: fields),
          throwsA(isA<MeasurementIngestCodecException>()),
        );
      }
    });

    test('assigned and witnessed frames require a bounded capture elapsed time',
        () {
      final assigned = decodeCanonicalObject(
        _validFrameBytes(experimentAssignment: _assignment()),
      );
      expect(_validatedFrame().frameElapsedMicros, isNull);
      expect(
        _validatedFrame(experimentAssignment: _assignment()).frameElapsedMicros,
        measurementIngestMaximumOutcomeWitnessMicros,
      );
      for (final invalid in [
        -1,
        measurementIngestMaximumOutcomeWitnessMicros + 1,
        null,
        '1',
      ]) {
        expect(
          () => MeasurementFactFrameV1.fromCanonicalBytes(
            CanonicalJsonCodec.encode({
              ...assigned,
              'frameElapsedMicros': invalid,
            }),
          ),
          throwsA(isA<MeasurementIngestCodecException>()),
        );
      }
      assigned.remove('frameElapsedMicros');
      expect(
        () => MeasurementFactFrameV1.fromCanonicalBytes(
          CanonicalJsonCodec.encode(assigned),
        ),
        throwsA(isA<MeasurementIngestCodecException>()),
      );
      final witnessed = decodeCanonicalObject(
        _validFrameBytes(
          factFields: {'interactionFirstOccurrenceMicros': 10},
        ),
      );
      for (final elapsed in [null, 9]) {
        if (elapsed == null) {
          witnessed.remove('frameElapsedMicros');
        } else {
          witnessed['frameElapsedMicros'] = elapsed;
        }
        expect(
          () => MeasurementFactFrameV1.fromCanonicalBytes(
            CanonicalJsonCodec.encode(witnessed),
          ),
          throwsA(isA<MeasurementIngestCodecException>()),
        );
      }
    });

    test('rides inside the signed request bytes and changes their digest', () {
      final ordinary = MeasurementIngestRequestV1.fromFactFrame(
        _validatedFrame(),
      );
      final assigned = MeasurementIngestRequestV1.fromFactFrame(
        _validatedFrame(experimentAssignment: _assignment()),
      );
      final witnessed = MeasurementIngestRequestV1.fromFactFrame(
        _validatedFrame(
          experimentAssignment: _assignment(),
          factFields: {'interactionFirstOccurrenceMicros': 1},
        ),
      );

      expect(decodeCanonicalObject(assigned.canonicalBytes).keys, {
        'factFrameCanonicalBase64',
        'factFrameSha256',
        'kind',
        'schemaVersion',
      });
      expect(assigned.factFrameSha256, isNot(ordinary.factFrameSha256));
      expect(assigned.requestSha256, isNot(ordinary.requestSha256));
      expect(witnessed.factFrameSha256, isNot(assigned.factFrameSha256));
      expect(witnessed.requestSha256, isNot(assigned.requestSha256));
    });

    test('rejects every noncanonical assignment', () {
      final invalid = <String, Map<String, Object?>>{
        'unknown key': {..._assignment(), 'armId': 'treatment'},
        'missing carrier': {
          'kind': 'measurementExperimentAssignment',
          'schemaVersion': 1,
        },
        'empty carrier': _assignment(carrier: ''),
        'padded carrier': _assignment(carrier: 'YWJj='),
        'noncanonical carrier': _assignment(carrier: 'not/base64+url'),
        'oversized carrier': _assignment(carrier: 'A' * 5000),
        'wrong kind': {
          ..._assignment(),
          'kind': 'measurementSurfaceAssignment',
        },
        'wrong schema version': {..._assignment(), 'schemaVersion': 2},
        'global witness': {..._assignment(), 'outcomeFirstOccurrenceMicros': 1},
      };

      for (final entry in invalid.entries) {
        expect(
          () => _validatedFrame(experimentAssignment: entry.value),
          throwsA(isA<MeasurementIngestCodecException>()),
          reason: entry.key,
        );
      }
    });
  });
}

const _carrier = 'b3V0Y29tZS1saW5rLWNhcnJpZXI';

Map<String, Object?> _assignment({
  String carrier = _carrier,
}) =>
    {
      'kind': 'measurementExperimentAssignment',
      'outcomeLinkCarrier': carrier,
      'schemaVersion': 1,
    };

MeasurementFactFrameV1 _validatedFrame({
  Map<String, Object?>? experimentAssignment,
  Map<String, Object?> factFields = const {},
}) =>
    MeasurementFactFrameV1.fromCanonicalBytes(
      _validFrameBytes(
        experimentAssignment: experimentAssignment,
        factFields: factFields,
      ),
    );

Uint8List _validFrameBytes({
  Map<String, Object?>? experimentAssignment,
  Map<String, Object?> factFields = const {},
}) =>
    CanonicalJsonCodec.encode({
      if (experimentAssignment != null)
        'experimentAssignment': experimentAssignment,
      'bounds': {
        'maximumCounterValue': 10,
        'maximumInteractionCounters': 1,
        'maximumMissingnessEntries': 1,
        'maximumPresentedPoints': 1,
      },
      'captureSessionNonce': 'session-sdk-ingest-0001',
      if (experimentAssignment != null ||
          factFields.containsKey('presentationFirstOccurrenceMicros') ||
          factFields.containsKey('interactionFirstOccurrenceMicros'))
        'frameElapsedMicros': measurementIngestMaximumOutcomeWitnessMicros,
      'facts': [
        {
          'interactionCount': {'saturated': false, 'value': 1},
          'interactionState': 'observedValue',
          'lineageId': 'lineage.sdk.ingest',
          'occurrenceId': 'a' * 64,
          ...factFields,
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
