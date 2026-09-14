import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:restage/src/measurement/measurement_host_session.dart';
import 'package:restage/src/measurement/measurement_outbox_protocol.dart';
import 'package:restage/src/measurement/measurement_worker_protocol.dart';
import 'package:restage/src/runtime/restage.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/measurement_outbox_test_support.dart';

void main() {
  final context = MeasurementPresentationContextV1(
    presentationCountry: 'US',
    platform: 'ios',
    appBuildOrdinal: 42,
    deviceClass: 'phone',
  );
  final carrier = base64UrlEncode(context.canonicalBytes).replaceAll('=', '');
  const receipt = 'opaque.routing.receipt';

  test('measurement disabled opens an inert session without reading', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const supportChannel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final supportDirectory =
        await Directory.systemTemp.createTemp('restage-configure-');
    addTearDown(() async {
      try {
        await Restage.debugResetAndWait();
      } finally {
        messenger.setMockMethodCallHandler(supportChannel, null);
        await supportDirectory.delete(recursive: true);
      }
    });
    messenger.setMockMethodCallHandler(
        supportChannel,
        (call) async => call.method == 'getApplicationSupportDirectory'
            ? supportDirectory.path
            : null);
    await Restage.debugResetAndWait();
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
        appName: 'Example',
        packageName: 'example.app',
        version: '1.0.0',
        buildNumber: '42',
        buildSignature: '');
    Restage.configure(apiKey: 'test-key', measurementEnabled: false);
    expect(Restage.isMeasurementEnabled, isFalse);
    var reads = 0;
    final session =
        await MeasurementHostSessionController.openForResolvedArtifact(
      Object(),
      presentationObservations: () async {
        reads += 1;
        throw StateError('Disabled measurement must not read observations');
      },
    );
    expect(session.debugState, MeasurementHostSessionDebugState.disabled);
    expect(reads, 0);
  });

  test('registration preserves presentation metadata and SDK metadata', () {
    final bytes = context.canonicalBytes;
    final registration = _registration(bytes: bytes, receipt: receipt);
    bytes[0] ^= 1;
    final copy = registration.presentationContextCanonicalBytes!;
    copy[0] ^= 1;
    final wire = registration.toWire();
    expect(wire, hasLength(12));
    final decoded = MeasurementWorkerSessionRegistration.fromWire(wire);
    expect(decoded.presentationContextCanonicalBytes,
        orderedEquals(context.canonicalBytes));
    expect(decoded.routingSelectionReceipt, receipt);
    expect(decoded.sdkRuntimeSessionNonce, 'a' * 64);
    expect(decoded.reportedSdkVersion, '1.0.0');
  });

  test('older ten-entry registration decodes without presentation metadata',
      () {
    final wire = <Object?>[
      'session.test',
      'capture.test',
      ingestRequest().factFrame.publishedContext.canonicalBytes,
      <Object?>[],
      _limits.toWire(),
      1,
      null,
      null,
      'a' * 64,
      '1.0.0',
    ];
    final decoded = MeasurementWorkerSessionRegistration.fromWire(wire);
    expect(decoded.presentationContextCanonicalBytes, isNull);
    expect(decoded.routingSelectionReceipt, isNull);
    expect(decoded.sdkRuntimeSessionNonce, 'a' * 64);
    expect(decoded.reportedSdkVersion, '1.0.0');
    expect(decoded.toWire().take(10), equals(wire));
  });

  test('registration refuses empty and oversized presentation metadata', () {
    for (final build in <MeasurementWorkerSessionRegistration Function()>[
      () => _registration(bytes: []),
      () => _registration(bytes: List.filled(8193, 0)),
      () => _registration(receipt: ''),
      () => _registration(receipt: 'x' * 4097),
    ]) {
      expect(build, throwsArgumentError);
    }
  });

  for (final fields in [
    (context: carrier, receipt: null),
    (context: null, receipt: receipt),
    (context: carrier, receipt: receipt),
  ]) {
    test(
        'presentation metadata survives ingest encoding without losing measurements '
        '(context: ${fields.context != null}, receipt: ${fields.receipt != null})',
        () {
      final request = MeasurementIngestRequestV1.fromFactFrame(
        ingestRequest().factFrame,
        presentationContextCanonicalBase64: fields.context,
        routingSelectionReceipt: fields.receipt,
      );
      final decoded =
          MeasurementIngestRequestV1.fromBase64(request.canonicalRequestBase64);
      expect(decoded.presentationContextCanonicalBase64, fields.context);
      expect(decoded.routingSelectionReceipt, fields.receipt);
      final rebuilt = MeasurementIngestRequestV1.fromFactFrame(
        decoded.factFrame,
        presentationContextCanonicalBase64:
            decoded.presentationContextCanonicalBase64,
        routingSelectionReceipt: decoded.routingSelectionReceipt,
        sdkRuntimeSessionNonce: decoded.sdkRuntimeSessionNonce,
        reportedSdkVersion: decoded.reportedSdkVersion,
      );
      expect(rebuilt.canonicalBytes, orderedEquals(request.canonicalBytes));
    });
  }

  test(
      'outbox preserves presentation metadata through preparation and stored restore',
      () {
    final request = MeasurementIngestRequestV1.fromFactFrame(
      ingestRequest().factFrame,
      presentationContextCanonicalBase64: carrier,
      routingSelectionReceipt: receipt,
    );
    final batch = MeasurementOutboxPreparedBatch.fromWorkerPreparedBatch(
      workerPreparedBatchForRequest(request),
    );
    final expectedBody = utf8.encode(
      '{"canonicalRequestBase64":"${request.canonicalRequestBase64}"}',
    );
    expect(batch.exactRequestBytes, orderedEquals(expectedBody));
    final record = MeasurementOutboxRecord(
      batch: batch,
      createdAtUtcMicros: DateTime.utc(2026, 8, 16).microsecondsSinceEpoch,
      configurationFingerprint: 'config.presentation.v1',
    );
    final restored = MeasurementOutboxRecordCodec.decode(
        MeasurementOutboxRecordCodec.encode(record));
    expect(restored.batch.exactRequestBytes, orderedEquals(expectedBody));
    expect(restored.batch.requestSha256, request.requestSha256);
  });
}

const _limits = MeasurementWorkerSessionLimits(
  maximumCounterValue: 10,
  maximumPresentedPoints: 1,
  maximumInteractionCounters: 0,
  maximumMissingnessEntries: 0,
);

MeasurementWorkerSessionRegistration _registration(
        {List<int>? bytes, String? receipt}) =>
    MeasurementWorkerSessionRegistration(
      sessionId: 'session.test',
      captureSessionNonce: 'capture.test',
      sdkRuntimeSessionNonce: 'a' * 64,
      reportedSdkVersion: '1.0.0',
      publicationContextCanonicalBytes:
          ingestRequest().factFrame.publishedContext.canonicalBytes,
      routes: [],
      limits: _limits,
      firstSequence: 1,
      presentationContextCanonicalBytes: bytes,
      routingSelectionReceipt: receipt,
    );
