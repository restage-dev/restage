import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/measurement/measurement_outbox_protocol.dart';
import 'package:restage/src/measurement/measurement_worker_protocol.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

import 'support/measurement_outbox_test_support.dart';

void main() {
  group('MeasurementOutboxAcknowledgement', () {
    test('a fact receipt acknowledges a fact record', () {
      final record = _record();
      expect(
        MeasurementOutboxAcknowledgement.fromReceipt(
          record: record,
          receipt: receiptForRecord(record),
        ),
        isNotNull,
      );
    });

    test('a diagnostic receipt acknowledges a diagnostic record', () {
      final diagnosticRecord = _diagnosticRecord(
        _diagnosticBatch(_diagnosticWorker(_diagnosticRequest())),
      );
      final acknowledgement = MeasurementOutboxAcknowledgement.fromReceipt(
        record: diagnosticRecord,
        receipt: receiptForRecord(diagnosticRecord),
      );

      expect(acknowledgement, isNotNull);
      expect(acknowledgement!.matches(diagnosticRecord), isTrue);
    });

    test('a receipt of the wrong digest kind does not acknowledge', () {
      final factRecord = _record();
      final diagnosticRecord = _diagnosticRecord(
        _diagnosticBatch(_diagnosticWorker(_diagnosticRequest())),
      );

      expect(
        MeasurementOutboxAcknowledgement.fromReceipt(
          record: diagnosticRecord,
          receipt: receiptForRecord(factRecord),
        ),
        isNull,
      );
      expect(
        MeasurementOutboxAcknowledgement.fromReceipt(
          record: factRecord,
          receipt: receiptForRecord(diagnosticRecord),
        ),
        isNull,
      );
    });
  });

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

    test('carries a diagnostic through worker adaptation and stored restore',
        () {
      final request = _diagnosticRequest();
      final batch = _diagnosticBatch(_diagnosticWorker(request));
      expect(batch.factFrameSha256, isNull);
      expect(batch.diagnosticSha256,
          crypto.sha256.convert(request.diagnostic.canonicalBytes).toString());
      expect(batch.sequence, 7);
      expect(batch.isFinal, isTrue);
      expect(batch.captureSessionNonce, 'capture.diagnostic');
      expect(batch.publicationBindingReferenceCanonicalBytes,
          orderedEquals(alternateBindingReference().canonicalBytes));
      expect(
          batch.exactRequestBytes,
          orderedEquals(utf8.encode(
              '{"canonicalRequestBase64":"${request.canonicalRequestBase64}"}')));
      final encoded =
          MeasurementOutboxRecordCodec.encode(_diagnosticRecord(batch));
      final restored = MeasurementOutboxRecordCodec.decode(encoded);
      expect(restored.batch.factFrameSha256, isNull);
      expect(restored.batch.diagnosticSha256, batch.diagnosticSha256);
      expect(restored.batch.sequence, batch.sequence);
      expect(restored.batch.isFinal, batch.isFinal);
      expect(restored.batch.captureSessionNonce, batch.captureSessionNonce);
      expect(restored.batch.publicationBindingReferenceCanonicalBytes,
          orderedEquals(batch.publicationBindingReferenceCanonicalBytes));
      expect(restored.batch.exactRequestBytes,
          orderedEquals(batch.exactRequestBytes));
      expect(MeasurementOutboxRecordCodec.encode(restored),
          orderedEquals(encoded));
      expect(encoded.length, restored.encodedByteLength);
    });

    test('rejects a diagnostic request with a different capture nonce', () {
      final worker = _diagnosticWorker(_diagnosticRequest());
      expect(
        () => MeasurementOutboxPreparedBatch.fromWorkerPreparedDiagnosticBatch(
          worker,
          captureSessionNonce: 'capture.other',
          publicationBindingReferenceCanonicalBytes:
              alternateBindingReference().canonicalBytes,
        ),
        throwsArgumentError,
      );
    });

    test('rejects invalid diagnostic handoffs and session witnesses', () {
      final request = _diagnosticRequest();
      final worker = _diagnosticWorker(request);
      final mutations = <int, Object?>{
        1: '',
        2: false,
        3: 0,
        5: Uint8List.fromList([0]),
        6: 'AA',
        8: '0' * 64,
      };
      for (final entry in mutations.entries) {
        final wire = worker.toWire()..[entry.key] = entry.value;
        expect(
            () =>
                _diagnosticBatch(MeasurementWorkerPreparedBatch.fromWire(wire)),
            throwsArgumentError,
            reason: 'worker slot ${entry.key}');
      }
      expect(() => _diagnosticBatch(worker, nonce: ''), throwsArgumentError);
      expect(() => _diagnosticBatch(worker, binding: []), throwsArgumentError);
      expect(
          () => _diagnosticBatch(worker,
              binding: List.filled(
                  kMeasurementOutboxMaximumBindingReferenceBytes + 1, 0)),
          throwsArgumentError);
      expect(
          () => _diagnosticBatch(workerPreparedBatch()), throwsArgumentError);
      expect(
          () => MeasurementOutboxPreparedBatch.fromWorkerPreparedBatch(worker),
          throwsArgumentError);
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
    test('restores and re-encodes the original record layout byte-identically',
        () {
      final original = _encodeOriginalRecord(_record());
      final restored = MeasurementOutboxRecordCodec.decode(original);
      expect(restored.batch.diagnosticSha256, isNull);
      expect(MeasurementOutboxRecordCodec.encode(restored),
          orderedEquals(original));
    });

    test('rejects missing, duplicate, and malformed content digests', () {
      final encoded = MeasurementOutboxRecordCodec.encode(_diagnosticRecord(
          _diagnosticBatch(_diagnosticWorker(_diagnosticRequest()))));
      final digestOffset = encoded.length - 46 - 32;
      final both = Uint8List.fromList(encoded)..[106] = 1;
      final neither = Uint8List.fromList([
        ...encoded.sublist(0, digestOffset),
        ...encoded.sublist(digestOffset + 32),
      ]);
      final wrongDiagnostic = Uint8List.fromList(encoded)..[digestOffset] ^= 1;
      final shortDiagnostic = Uint8List.fromList([
        ...encoded.sublist(0, digestOffset),
        ...encoded.sublist(digestOffset + 1),
      ]);
      final wrongFact = MeasurementOutboxRecordCodec.encode(_record())
        ..[106] ^= 1;
      final nonFinal = Uint8List.fromList(encoded)..[16] = 0;
      final zeroSequence = Uint8List.fromList(encoded);
      ByteData.sublistView(zeroSequence).setUint64(18, 0, Endian.big);
      for (final bytes in [
        both,
        neither,
        wrongDiagnostic,
        shortDiagnostic,
        wrongFact,
        nonFinal,
        zeroSequence
      ]) {
        _refreshIntegrity(bytes);
        expect(() => MeasurementOutboxRecordCodec.decode(bytes),
            throwsA(isA<MeasurementOutboxCodecException>()));
      }
    });

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

MeasurementPresentationDiagnosticRequestV1 _diagnosticRequest() =>
    MeasurementPresentationDiagnosticRequestV1.fromDiagnostic(
      const MeasurementPresentationDiagnosticV1(
        rootPresentationReports: MeasurementRootPresentationReportsV1.none,
        stepObserved: false,
        finishReason: MeasurementPresentationFinishReasonV1.paintFailed,
        captureIncomplete: true,
      ),
      captureSessionNonce: 'capture.diagnostic',
      publicationBindingReference: alternateBindingReference(),
      sequence: 7,
    );

MeasurementWorkerPreparedBatch _diagnosticWorker(
        MeasurementPresentationDiagnosticRequestV1 request) =>
    MeasurementWorkerPreparedBatch(
      batchId: 'batch.diagnostic',
      sessionId: 'session.diagnostic',
      isFinal: true,
      sequence: 7,
      canonicalFrameBytes: const [],
      frameSha256: '',
      canonicalRequestBytes: request.canonicalBytes,
      canonicalRequestBase64: request.canonicalRequestBase64,
      requestSha256: request.requestSha256,
      ownedByteCount: 1,
    );

MeasurementOutboxPreparedBatch _diagnosticBatch(
        MeasurementWorkerPreparedBatch worker,
        {String nonce = 'capture.diagnostic',
        List<int>? binding}) =>
    MeasurementOutboxPreparedBatch.fromWorkerPreparedDiagnosticBatch(
      worker,
      captureSessionNonce: nonce,
      publicationBindingReferenceCanonicalBytes:
          binding ?? alternateBindingReference().canonicalBytes,
    );

MeasurementOutboxRecord _diagnosticRecord(
        MeasurementOutboxPreparedBatch batch) =>
    MeasurementOutboxRecord(
        batch: batch,
        createdAtUtcMicros: 1,
        configurationFingerprint: 'config.diagnostic');

void _refreshIntegrity(Uint8List bytes) {
  final offset = bytes.length - 46;
  bytes.setRange(offset, offset + 32,
      crypto.sha256.convert(bytes.sublist(0, offset)).bytes);
}

// Original fixed record layout, independent of the current encoder.
Uint8List _encodeOriginalRecord(MeasurementOutboxRecord record) {
  final batch = record.batch;
  final session = utf8.encode(batch.sessionId);
  final fingerprint = utf8.encode(record.configurationFingerprint);
  final nonce = utf8.encode(batch.captureSessionNonce);
  final binding = batch.publicationBindingReferenceCanonicalBytes;
  final body = batch.exactRequestBytes;
  final bytes = Uint8List(138 +
      session.length +
      fingerprint.length +
      nonce.length +
      binding.length +
      body.length +
      46);
  bytes.setRange(0, 8, [82, 83, 79, 66, 88, 50, 0, 2]);
  ByteData.sublistView(bytes)
    ..setUint16(8, 2, Endian.big)
    ..setUint16(10, session.length, Endian.big)
    ..setUint16(12, fingerprint.length, Endian.big)
    ..setUint16(14, nonce.length, Endian.big)
    ..setUint8(16, batch.isFinal ? 1 : 0)
    ..setUint64(18, batch.sequence, Endian.big)
    ..setInt64(26, record.createdAtUtcMicros, Endian.big)
    ..setUint32(34, body.length, Endian.big)
    ..setUint32(38, binding.length, Endian.big);
  var cursor = 42;
  for (final digest in [
    batch.bodySha256,
    batch.requestSha256,
    batch.factFrameSha256!
  ]) {
    final raw = [
      for (var i = 0; i < digest.length; i += 2)
        int.parse(digest.substring(i, i + 2), radix: 16)
    ];
    bytes.setRange(cursor, cursor + 32, raw);
    cursor += 32;
  }
  for (final part in [session, fingerprint, nonce, binding, body]) {
    bytes.setRange(cursor, cursor + part.length, part);
    cursor += part.length;
  }
  bytes.setRange(bytes.length - 14, bytes.length,
      [82, 83, 79, 66, 45, 67, 79, 77, 77, 73, 84, 45, 86, 50]);
  _refreshIntegrity(bytes);
  return bytes;
}
