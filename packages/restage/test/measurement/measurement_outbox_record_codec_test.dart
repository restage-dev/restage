import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/measurement/measurement_outbox_protocol.dart';
import 'package:restage/src/measurement/measurement_worker_protocol.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

import 'support/measurement_outbox_test_support.dart';

void main() {
  group('MeasurementOutboxPreparedBatch', () {
    test('builds the exact sole-route body from a validated worker batch', () {
      final request = ingestRequest(sequence: 7, isFinal: true);
      final batch = MeasurementOutboxPreparedBatch.fromWorkerPreparedBatch(
        workerPreparedBatchForRequest(
          request,
          sessionId: 'session.codec',
          sequence: 7,
          isFinal: true,
        ),
      );

      expect(
        batch.exactRequestBytes,
        orderedEquals(
          utf8.encode(
            '{"canonicalRequestBase64":"${request.canonicalRequestBase64}"}',
          ),
        ),
      );
      expect(batch.requestSha256, request.requestSha256);
      expect(batch.factFrameSha256, request.factFrameSha256);
      expect(batch.captureSessionNonce, request.factFrame.captureSessionNonce);
      expect(
        batch.publicationBindingReferenceCanonicalBytes,
        orderedEquals(
          request.factFrame.publishedContext.bindingReference.canonicalBytes,
        ),
      );
    });

    test('fails closed for every inconsistent worker handoff field', () {
      final request = ingestRequest(sequence: 7, isFinal: true);
      final changedRequestBytes = Uint8List.fromList(request.canonicalBytes)
        ..[0] ^= 0x01;
      final changedFrameBytes =
          Uint8List.fromList(request.factFrameCanonicalBytes)..[0] ^= 0x01;
      final alteredBindingRequest = ingestRequest(
        sequence: 7,
        isFinal: true,
        bindingReference: alternateBindingReference(),
      );
      final workers = <String, MeasurementWorkerPreparedBatch>{
        'canonical request bytes': workerPreparedBatchForRequest(
          request,
          canonicalRequestBytes: changedRequestBytes,
        ),
        'canonical request base64': workerPreparedBatchForRequest(
          request,
          canonicalRequestBase64: 'AA',
        ),
        'request hash': workerPreparedBatchForRequest(
          request,
          requestSha256: '0' * 64,
        ),
        'frame bytes': workerPreparedBatchForRequest(
          request,
          canonicalFrameBytes: changedFrameBytes,
        ),
        'frame hash': workerPreparedBatchForRequest(
          request,
          frameSha256: '0' * 64,
        ),
        'sequence': workerPreparedBatchForRequest(request, sequence: 8),
        'finality': workerPreparedBatchForRequest(request, isFinal: false),
        'binding': workerPreparedBatchForRequest(
          alteredBindingRequest,
          canonicalFrameBytes: request.factFrameCanonicalBytes,
        ),
      };

      for (final entry in workers.entries) {
        expect(
          () => MeasurementOutboxPreparedBatch.fromWorkerPreparedBatch(
            entry.value,
          ),
          throwsArgumentError,
          reason: entry.key,
        );
      }
    });
  });

  group('MeasurementOutboxRecordCodec', () {
    test('round-trips exact route bytes and immutable acknowledgement inputs',
        () {
      final record = _record();

      final encoded = MeasurementOutboxRecordCodec.encode(record);
      final decoded = MeasurementOutboxRecordCodec.decode(encoded);

      expect(decoded.batch.sessionId, record.batch.sessionId);
      expect(decoded.batch.sequence, record.batch.sequence);
      expect(decoded.batch.isFinal, record.batch.isFinal);
      expect(decoded.batch.bodySha256, record.batch.bodySha256);
      expect(decoded.batch.requestSha256, record.batch.requestSha256);
      expect(decoded.batch.factFrameSha256, record.batch.factFrameSha256);
      expect(
          decoded.batch.captureSessionNonce, record.batch.captureSessionNonce);
      expect(
        decoded.batch.publicationBindingReferenceCanonicalBytes,
        orderedEquals(record.batch.publicationBindingReferenceCanonicalBytes),
      );
      expect(
        decoded.batch.exactRequestBytes,
        orderedEquals(record.batch.exactRequestBytes),
      );
      expect(decoded.createdAtUtcMicros, record.createdAtUtcMicros);
      expect(decoded.configurationFingerprint, record.configurationFingerprint);
      expect(decoded.fileStem, record.fileStem);
      expect(encoded.length, record.encodedByteLength);
    });

    test('rejects independent mutations of every closed record control', () {
      final record = _record();
      final encoded = MeasurementOutboxRecordCodec.encode(record);
      final sessionLength = utf8.encode(record.batch.sessionId).length;
      final fingerprintLength =
          utf8.encode(record.configurationFingerprint).length;
      final nonceLength = utf8.encode(record.batch.captureSessionNonce).length;
      final bindingLength =
          record.batch.publicationBindingReferenceCanonicalBytes.length;
      final variableStart = MeasurementOutboxRecordCodec.fixedHeaderLength;
      final configurationStart = variableStart + sessionLength;
      final nonceStart = configurationStart + fingerprintLength;
      final bindingStart = nonceStart + nonceLength;
      final bodyStart = bindingStart + bindingLength;
      final mutations = <String, void Function(Uint8List)>{
        'magic': (bytes) => bytes[0] ^= 0xff,
        'version': (bytes) => bytes[9] ^= 0xff,
        'session length': (bytes) => bytes[10] ^= 0x01,
        'configuration length': (bytes) => bytes[12] ^= 0x01,
        'capture nonce length': (bytes) => bytes[14] ^= 0x01,
        'final flag': (bytes) => bytes[16] ^= 0x01,
        'reserved byte': (bytes) => bytes[17] ^= 0x01,
        'sequence': (bytes) => bytes[25] ^= 0x01,
        'created timestamp': (bytes) => bytes[33] ^= 0x01,
        'body length': (bytes) => bytes[37] ^= 0x01,
        'binding length': (bytes) => bytes[41] ^= 0x01,
        'body digest': (bytes) => bytes[42] ^= 0x01,
        'request digest': (bytes) => bytes[74] ^= 0x01,
        'frame digest': (bytes) => bytes[106] ^= 0x01,
        'session bytes': (bytes) => bytes[variableStart] ^= 0x01,
        'configuration bytes': (bytes) => bytes[configurationStart] ^= 0x01,
        'capture nonce bytes': (bytes) => bytes[nonceStart] ^= 0x01,
        'binding bytes': (bytes) => bytes[bindingStart] ^= 0x01,
        'request body spelling': (bytes) => bytes[bodyStart] ^= 0x01,
        'record integrity digest': (bytes) => bytes[bytes.length - 15] ^= 0x01,
        'commit marker': (bytes) => bytes[bytes.length - 1] ^= 0xff,
      };

      for (final entry in mutations.entries) {
        final mutated = Uint8List.fromList(encoded);
        entry.value(mutated);
        expect(
          () => MeasurementOutboxRecordCodec.decode(mutated),
          throwsA(isA<MeasurementOutboxCodecException>()),
          reason: entry.key,
        );
      }
    });

    test('rejects a truncated record and invalid UTF-8 metadata', () {
      final encoded = MeasurementOutboxRecordCodec.encode(_record());
      expect(
        () => MeasurementOutboxRecordCodec.decode(
          encoded.sublist(0, encoded.length - 1),
        ),
        throwsA(isA<MeasurementOutboxCodecException>()),
      );

      final invalidUtf8 = Uint8List.fromList(encoded);
      invalidUtf8[MeasurementOutboxRecordCodec.fixedHeaderLength] = 0xff;
      expect(
        () => MeasurementOutboxRecordCodec.decode(invalidUtf8),
        throwsA(isA<MeasurementOutboxCodecException>()),
      );
    });

    test('keeps route and record bounds derived from the shared request limit',
        () {
      final record = MeasurementOutboxRecord(
        batch: outboxPreparedBatch(factCount: 1024),
        createdAtUtcMicros: DateTime.utc(2026, 8, 16).microsecondsSinceEpoch,
        configurationFingerprint: 'config.codec.v1',
      );

      expect(
        kMeasurementOutboxMaximumHttpBodyBytes,
        ((measurementIngestMaximumRequestBytes * 4) + 2) ~/ 3 + 29,
      );
      expect(
        MeasurementOutboxRecordCodec.encode(record).length,
        lessThanOrEqualTo(kMeasurementOutboxMaximumRecordBytes),
      );
    });
  });

  group('MeasurementOutboxMarkerCodec', () {
    test('requires a receipt digest before ready-record cleanup', () {
      final record = _record();
      final acknowledgement = acknowledgementForRecord(record);
      final marker = MeasurementOutboxMarker.acknowledgement(
        record: record,
        acknowledgement: acknowledgement,
      );
      final encoded = MeasurementOutboxMarkerCodec.encode(marker);
      final decoded = MeasurementOutboxMarkerCodec.decode(encoded);

      expect(decoded.kind, MeasurementOutboxMarkerKind.acknowledged);
      expect(decoded.receiptSha256, acknowledgement.receiptSha256);
      expect(decoded.matches(record), isTrue);

      encoded[encoded.length - 1] ^= 0xff;
      expect(
        () => MeasurementOutboxMarkerCodec.decode(encoded),
        throwsA(isA<MeasurementOutboxCodecException>()),
      );
    });
  });

  test('uses the frozen deterministic no-jitter retry sequence', () {
    expect(measurementOutboxRetryDelay(0), const Duration(seconds: 1));
    expect(measurementOutboxRetryDelay(1), const Duration(seconds: 2));
    expect(measurementOutboxRetryDelay(11), const Duration(seconds: 2048));
    expect(measurementOutboxRetryDelay(12), const Duration(hours: 1));
    expect(measurementOutboxRetryDelay(63), const Duration(hours: 1));
  });
}

MeasurementOutboxRecord _record({String variant = 'record'}) =>
    MeasurementOutboxRecord(
      batch: outboxPreparedBatch(
        sessionId: 'session.codec',
        sequence: 7,
        isFinal: true,
        variant: variant,
      ),
      createdAtUtcMicros: DateTime.utc(2026, 8, 16).microsecondsSinceEpoch,
      configurationFingerprint: 'config.codec.v1',
    );
