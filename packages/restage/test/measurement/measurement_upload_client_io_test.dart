import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/measurement/measurement_outbox.dart';
import 'package:restage/src/measurement/measurement_outbox_io.dart'
    show MeasurementOutboxIoFileSystem;
import 'package:restage/src/measurement/measurement_upload_client.dart';
import 'package:restage/src/measurement/measurement_upload_client_stub.dart'
    as unsupported;
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

import 'support/measurement_outbox_test_support.dart';

void main() {
  test('derives the receipt response bound from the shared receipt limit', () {
    expect(
      kMeasurementUploadMaximumReceiptResponseBytes,
      ((measurementIngestMaximumReceiptBytes * 4) + 2) ~/ 3 + 29,
    );
  });

  test('fake production envelope replays exact bytes, then ACKs before cleanup',
      () async {
    final support = await _temporarySupportDirectory();
    addTearDown(() => support.delete(recursive: true));
    final clock = _MutableClock(DateTime.utc(2026, 8, 16, 12));
    final receivedBodies = <Uint8List>[];
    final receivedPaths = <String>[];
    final batch = _batch();
    final receipt = receiptEnvelopeForRecord(_recordForBatch(batch));
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    var attempts = 0;
    unawaited(
      server.forEach((request) async {
        final received = BytesBuilder(copy: false);
        await for (final chunk in request) {
          received.add(chunk);
        }
        receivedBodies.add(received.takeBytes());
        receivedPaths.add(request.uri.path);
        request.response.statusCode =
            attempts++ == 0 ? HttpStatus.serviceUnavailable : HttpStatus.ok;
        if (attempts == 2) {
          request.response
            ..headers.contentType = ContentType.json
            ..write(receipt);
        }
        await request.response.close();
      }),
    );

    final firstStore = _store(
      support,
      clock: clock.call,
      fileSystem: _FailOnceReadyDeleteFileSystem(),
    );
    await firstStore.open();
    final committed = await firstStore.commit(batch);
    expect(committed.outcome, MeasurementOutboxCommitOutcome.committed);
    final coordinator = MeasurementOutboxUploadCoordinator(
      store: firstStore,
      uploadClient: createMeasurementUploadClient(
        configuration: MeasurementUploadConfiguration(
          endpoint: Uri.parse(
            'http://${server.address.host}:${server.port}/sdk/v1/measurement',
          ),
          headersProvider: () => const <String, String>{
            'authorization': 'Bearer transient-only',
          },
        ),
      ),
    );

    expect(
      (await coordinator.uploadNext()).outcome,
      MeasurementOutboxUploadOutcome.retryScheduled,
    );
    clock.advance(const Duration(seconds: 1));
    expect(
      (await coordinator.uploadNext()).outcome,
      MeasurementOutboxUploadOutcome.acknowledgedPendingCleanup,
    );
    expect(receivedBodies, hasLength(2));
    expect(receivedBodies[0], orderedEquals(batch.exactRequestBytes));
    expect(receivedBodies[1], orderedEquals(batch.exactRequestBytes));
    expect(receivedPaths, everyElement('/sdk/v1/measurement'));

    final restarted = _store(support, clock: clock.call);
    final recovered = await restarted.open();
    expect(recovered.recovery.acknowledgedRecordsCleaned, 1);
    expect(await restarted.nextReady(), isNull);
    expect(receivedBodies, hasLength(2));
  });

  test('native client classifies audited HTTP response classes', () async {
    final batch = _batch();
    final record = _recordForBatch(batch);
    final lease = MeasurementOutboxLease(record: record);
    final receipt = receiptEnvelopeForRecord(record);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    unawaited(
      server.forEach((request) async {
        await request.drain<void>();
        final response = request.response;
        switch (request.uri.path) {
          case '/retry':
            response.statusCode = HttpStatus.serviceUnavailable;
          case '/auth':
            response.statusCode = HttpStatus.unauthorized;
          case '/rejected':
            response.statusCode = HttpStatus.badRequest;
          case '/conflict':
            response
              ..statusCode = HttpStatus.conflict
              ..write(receipt);
          case '/success':
            response
              ..statusCode = HttpStatus.ok
              ..write(receipt);
          case '/malformed-success':
            response
              ..statusCode = HttpStatus.ok
              ..write('{}');
          default:
            response.statusCode = HttpStatus.internalServerError;
        }
        await response.close();
      }),
    );
    final origin = 'http://${server.address.host}:${server.port}';
    final cases = <_HttpCase>[
      const _HttpCase('/retry', MeasurementUploadOutcomeKind.retryable),
      const _HttpCase('/auth', MeasurementUploadOutcomeKind.paused),
      const _HttpCase('/rejected', MeasurementUploadOutcomeKind.rejected),
      const _HttpCase('/conflict', MeasurementUploadOutcomeKind.conflict),
      const _HttpCase('/success', MeasurementUploadOutcomeKind.acknowledged),
      const _HttpCase(
        '/malformed-success',
        MeasurementUploadOutcomeKind.protocolFailure,
      ),
    ];

    for (final testCase in cases) {
      final client = createMeasurementUploadClient(
        configuration: MeasurementUploadConfiguration(
          endpoint: Uri.parse('$origin${testCase.path}'),
          headersProvider: () => const <String, String>{},
        ),
      );
      final outcome = await client.send(lease);
      expect(outcome.kind, testCase.expected, reason: testCase.path);
      if (testCase.path == '/auth') {
        expect(
          outcome.holdReason,
          MeasurementOutboxHoldReason.authenticationFailure,
        );
      }
    }
  });

  test('rejects every malformed or mismatched receipt without ready deletion',
      () async {
    final batch = _batch(sessionId: 'session.mutation', variant: 'mutation');
    final record = _recordForBatch(batch);
    final receipt = receiptForRecord(record);
    final receiptDocument = decodeCanonicalObject(receipt.canonicalBytes);
    final unknownReceipt = CanonicalJsonCodec.encode({
      ...receiptDocument,
      'unknown': true,
    });
    final missingReceipt = CanonicalJsonCodec.encode(
      Map<String, Object?>.from(receiptDocument)..remove('requestSha256'),
    );
    final cases = <_ResponseCase>[
      _ResponseCase(
        '/capture-session-nonce',
        receiptEnvelope(
          receiptForRecord(record, captureSessionNonce: 'capture.mismatch'),
        ),
        MeasurementOutboxUploadOutcome.held,
      ),
      _ResponseCase(
        '/sequence',
        receiptEnvelope(receiptForRecord(record, sequence: 2)),
        MeasurementOutboxUploadOutcome.held,
      ),
      _ResponseCase(
        '/request-sha',
        receiptEnvelope(receiptForRecord(record, requestSha256: '0' * 64)),
        MeasurementOutboxUploadOutcome.held,
      ),
      _ResponseCase(
        '/frame-sha',
        receiptEnvelope(receiptForRecord(record, factFrameSha256: '0' * 64)),
        MeasurementOutboxUploadOutcome.held,
      ),
      _ResponseCase(
        '/finality',
        receiptEnvelope(receiptForRecord(record, isFinal: true)),
        MeasurementOutboxUploadOutcome.held,
      ),
      _ResponseCase(
        '/binding',
        receiptEnvelope(
          receiptForRecord(
            record,
            publicationBindingReference: alternateBindingReference(),
          ),
        ),
        MeasurementOutboxUploadOutcome.held,
      ),
      _ResponseCase(
        '/unknown-receipt',
        receiptEnvelopeForCanonicalBytes(unknownReceipt),
        MeasurementOutboxUploadOutcome.held,
      ),
      _ResponseCase(
        '/missing-receipt',
        receiptEnvelopeForCanonicalBytes(missingReceipt),
        MeasurementOutboxUploadOutcome.held,
      ),
      _ResponseCase(
        '/wrong-envelope-key',
        '{"receipt":"${receipt.canonicalReceiptBase64}"}',
        MeasurementOutboxUploadOutcome.held,
      ),
      _ResponseCase(
        '/extra-envelope-key',
        '{"receiptCanonicalBase64":"${receipt.canonicalReceiptBase64}","extra":true}',
        MeasurementOutboxUploadOutcome.held,
      ),
      _ResponseCase(
        '/response-body-spelling',
        ' ${receiptEnvelope(receipt)}',
        MeasurementOutboxUploadOutcome.held,
      ),
      const _ResponseCase(
        '/nominal-2xx-malformed',
        '{}',
        MeasurementOutboxUploadOutcome.held,
      ),
      _ResponseCase(
        '/conflict',
        receiptEnvelope(receipt),
        MeasurementOutboxUploadOutcome.quarantined,
        statusCode: HttpStatus.conflict,
      ),
    ];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final receivedBodies = <String, Uint8List>{};
    final responses = {for (final response in cases) response.path: response};
    unawaited(
      server.forEach((request) async {
        final received = BytesBuilder(copy: false);
        await for (final chunk in request) {
          received.add(chunk);
        }
        receivedBodies[request.uri.path] = received.takeBytes();
        final response = responses[request.uri.path]!;
        request.response
          ..statusCode = response.statusCode
          ..write(response.body);
        await request.response.close();
      }),
    );
    final origin = 'http://${server.address.host}:${server.port}';

    for (var index = 0; index < cases.length; index += 1) {
      final support = await _temporarySupportDirectory();
      addTearDown(() => support.delete(recursive: true));
      final store = _store(support);
      await store.open();
      final committed = await store.commit(
        _batch(
          sessionId: 'session.mutation.$index',
          variant: 'mutation',
        ),
      );
      final committedRecord = committed.record!;
      final coordinator = MeasurementOutboxUploadCoordinator(
        store: store,
        uploadClient: createMeasurementUploadClient(
          configuration: MeasurementUploadConfiguration(
            endpoint: Uri.parse('$origin${cases[index].path}'),
            headersProvider: () => const <String, String>{},
          ),
        ),
      );

      expect(
        (await coordinator.uploadNext()).outcome,
        cases[index].expected,
        reason: cases[index].path,
      );
      expect(
        receivedBodies[cases[index].path],
        orderedEquals(committedRecord.batch.exactRequestBytes),
        reason: cases[index].path,
      );
      expect(
        await File(
          '${support.path}/restage/measurement/outbox-v1/'
          '${committedRecord.fileStem}.ready',
        ).exists(),
        isTrue,
        reason: cases[index].path,
      );
    }
  });

  test('retains or quarantines every non-acknowledgement upload class',
      () async {
    final cases = <_UploadCase>[
      const _UploadCase(
        name: 'retryable network failure',
        outcome: MeasurementUploadOutcome.retryable(),
        expected: MeasurementOutboxUploadOutcome.retryScheduled,
      ),
      const _UploadCase(
        name: 'authentication pause',
        outcome: MeasurementUploadOutcome.paused(
          MeasurementOutboxHoldReason.authenticationFailure,
        ),
        expected: MeasurementOutboxUploadOutcome.held,
      ),
      const _UploadCase(
        name: 'permanent rejection',
        outcome: MeasurementUploadOutcome.rejected(
          MeasurementOutboxQuarantineReason.permanentRejection,
        ),
        expected: MeasurementOutboxUploadOutcome.quarantined,
      ),
      const _UploadCase(
        name: 'unproven conflict',
        outcome: MeasurementUploadOutcome.conflict(),
        expected: MeasurementOutboxUploadOutcome.quarantined,
      ),
      const _UploadCase(
        name: 'mismatched acknowledgement proof',
        outcome: MeasurementUploadOutcome.protocolFailure(),
        expected: MeasurementOutboxUploadOutcome.held,
      ),
    ];

    for (final testCase in cases) {
      final support = await _temporarySupportDirectory();
      addTearDown(() => support.delete(recursive: true));
      final store = _store(support);
      await store.open();
      await store
          .commit(_batch(sessionId: 'session.${testCase.name.hashCode}'));
      final coordinator = MeasurementOutboxUploadCoordinator(
        store: store,
        uploadClient: _FixedUploadClient(testCase.outcome),
      );

      expect(
        (await coordinator.uploadNext()).outcome,
        testCase.expected,
        reason: testCase.name,
      );
      expect(await store.nextReady(), isNull, reason: testCase.name);
    }
  });

  test('allows only one active lease/upload', () async {
    final support = await _temporarySupportDirectory();
    addTearDown(() => support.delete(recursive: true));
    final store = _store(support);
    await store.open();
    final batch = _batch();
    await store.commit(batch);
    final client = _BlockingAcknowledgingUploadClient();
    final coordinator = MeasurementOutboxUploadCoordinator(
      store: store,
      uploadClient: client,
    );

    final first = coordinator.uploadNext();
    await client.started.future;
    expect(
      (await coordinator.uploadNext()).outcome,
      MeasurementOutboxUploadOutcome.busy,
    );
    client.complete(acknowledgementForRecord(_recordForBatch(batch)));
    expect((await first).outcome, MeasurementOutboxUploadOutcome.delivered);
  });

  test('refuses a reset purge until an active upload reaches a durable state',
      () async {
    final support = await _temporarySupportDirectory();
    addTearDown(() => support.delete(recursive: true));
    final store = _store(support);
    await store.open();
    final batch = _batch();
    await store.commit(batch);
    final client = _BlockingAcknowledgingUploadClient();
    final coordinator = MeasurementOutboxUploadCoordinator(
      store: store,
      uploadClient: client,
    );

    final activeUpload = coordinator.uploadNext();
    await client.started.future;
    final blockedReset = await coordinator.purge(
      MeasurementOutboxPurgeReason.privacyReset,
    );

    expect(blockedReset.outcome, MeasurementOutboxPurgeOutcome.failed);
    expect(blockedReset.purgedRecordCount, 0);
    client.complete(acknowledgementForRecord(_recordForBatch(batch)));
    expect(
      (await activeUpload).outcome,
      MeasurementOutboxUploadOutcome.delivered,
    );
  });

  test('unsupported upload client fails closed without reading credentials',
      () async {
    var providerCalled = false;
    final client = unsupported.createMeasurementUploadClient(
      configuration: MeasurementUploadConfiguration(
        endpoint: Uri.parse('https://example.invalid/measurement'),
        headersProvider: () {
          providerCalled = true;
          return const <String, String>{};
        },
      ),
    );
    final batch = _batch();
    final lease = MeasurementOutboxLease(record: _recordForBatch(batch));

    expect(
      (await client.send(lease)).kind,
      MeasurementUploadOutcomeKind.unavailable,
    );
    expect(providerCalled, isFalse);
  });
}

Future<Directory> _temporarySupportDirectory() =>
    Directory.systemTemp.createTemp('restage-measurement-upload-test-');

MeasurementOutboxStore _store(
  Directory support, {
  MeasurementOutboxClock? clock,
  MeasurementOutboxFileSystem? fileSystem,
}) =>
    createMeasurementOutboxStore(
      configuration: MeasurementOutboxConfiguration(
        applicationSupportPath: support.path,
        configurationFingerprint: 'config.test.v1',
      ),
      clock: clock,
      fileSystem: fileSystem,
    );

MeasurementOutboxPreparedBatch _batch({
  String sessionId = 'session.upload',
  int sequence = 1,
  String variant = 'upload',
}) =>
    outboxPreparedBatch(
      sessionId: sessionId,
      sequence: sequence,
      variant: variant,
    );

MeasurementOutboxRecord _recordForBatch(MeasurementOutboxPreparedBatch batch) =>
    MeasurementOutboxRecord(
      batch: batch,
      createdAtUtcMicros: DateTime.utc(2026, 8, 16).microsecondsSinceEpoch,
      configurationFingerprint: 'config.test.v1',
    );

final class _FixedUploadClient implements MeasurementUploadClient {
  const _FixedUploadClient(this._outcome);

  final MeasurementUploadOutcome _outcome;

  @override
  Future<MeasurementUploadOutcome> send(MeasurementOutboxLease lease) async =>
      _outcome;
}

final class _BlockingAcknowledgingUploadClient
    implements MeasurementUploadClient {
  final Completer<void> started = Completer<void>();
  final Completer<MeasurementOutboxAcknowledgement> _acknowledgement =
      Completer<MeasurementOutboxAcknowledgement>();

  @override
  Future<MeasurementUploadOutcome> send(MeasurementOutboxLease lease) async {
    started.complete();
    return MeasurementUploadOutcome.acknowledged(await _acknowledgement.future);
  }

  void complete(MeasurementOutboxAcknowledgement acknowledgement) {
    _acknowledgement.complete(acknowledgement);
  }
}

final class _FailOnceReadyDeleteFileSystem
    implements MeasurementOutboxFileSystem {
  final MeasurementOutboxIoFileSystem _delegate =
      const MeasurementOutboxIoFileSystem();
  var _shouldFailReadyDelete = true;

  @override
  Future<void> createDirectory(String path) => _delegate.createDirectory(path);

  @override
  Future<void> delete(String path) async {
    if (_shouldFailReadyDelete && path.endsWith('.ready')) {
      _shouldFailReadyDelete = false;
      throw FileSystemException('simulated delete interruption', path);
    }
    await _delegate.delete(path);
  }

  @override
  Future<List<MeasurementOutboxFileEntry>> listDirectory(String path) =>
      _delegate.listDirectory(path);

  @override
  Future<Uint8List> readBytes(String path) => _delegate.readBytes(path);

  @override
  Future<void> rename(String sourcePath, String destinationPath) =>
      _delegate.rename(sourcePath, destinationPath);

  @override
  Future<void> writeAndFlush(String path, Uint8List bytes) =>
      _delegate.writeAndFlush(path, bytes);
}

final class _MutableClock {
  _MutableClock(this.now);

  DateTime now;

  DateTime call() => now;

  void advance(Duration duration) {
    now = now.add(duration);
  }
}

final class _UploadCase {
  const _UploadCase({
    required this.name,
    required this.outcome,
    required this.expected,
  });

  final String name;
  final MeasurementUploadOutcome outcome;
  final MeasurementOutboxUploadOutcome expected;
}

final class _HttpCase {
  const _HttpCase(this.path, this.expected);

  final String path;
  final MeasurementUploadOutcomeKind expected;
}

final class _ResponseCase {
  const _ResponseCase(
    this.path,
    this.body,
    this.expected, {
    this.statusCode = HttpStatus.ok,
  });

  final String path;
  final String body;
  final MeasurementOutboxUploadOutcome expected;
  final int statusCode;
}
