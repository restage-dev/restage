import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'measurement_outbox_protocol.dart';
import 'measurement_upload_client_protocol.dart';

/// Builds the `dart:io` exact-byte HTTP upload client inside the worker.
MeasurementUploadClient createMeasurementUploadClient({
  required MeasurementUploadConfiguration configuration,
}) =>
    _IoMeasurementUploadClient(configuration: configuration);

final class _IoMeasurementUploadClient implements MeasurementUploadClient {
  _IoMeasurementUploadClient({
    required MeasurementUploadConfiguration configuration,
  }) : _configuration = configuration;

  final MeasurementUploadConfiguration _configuration;
  static const _acknowledgementDecoder =
      MeasurementUploadReceiptAcknowledgementDecoder();

  @override
  Future<MeasurementUploadOutcome> send(MeasurementOutboxLease lease) async {
    Map<String, String> transientHeaders;
    try {
      transientHeaders = Map<String, String>.from(
        await _configuration.headersProvider(),
      );
      if (transientHeaders.entries.any(
        (entry) =>
            entry.key.isEmpty ||
            entry.key.contains('\r') ||
            entry.key.contains('\n') ||
            entry.value.contains('\r') ||
            entry.value.contains('\n'),
      )) {
        return const MeasurementUploadOutcome.paused(
          MeasurementOutboxHoldReason.configurationMismatch,
        );
      }
    } on Object {
      return const MeasurementUploadOutcome.paused(
        MeasurementOutboxHoldReason.configurationMismatch,
      );
    }

    final client = HttpClient();
    try {
      final request = await client
          .postUrl(_configuration.endpoint)
          .timeout(_configuration.requestTimeout);
      request
        ..followRedirects = false
        ..contentLength = lease.exactRequestBytes.length
        ..headers
            .set(HttpHeaders.contentTypeHeader, _configuration.contentType);
      for (final entry in transientHeaders.entries) {
        request.headers.set(entry.key, entry.value);
      }
      request.add(lease.exactRequestBytes);
      final response =
          await request.close().timeout(_configuration.requestTimeout);
      final responseBytes = BytesBuilder(copy: false);
      var responseByteLength = 0;
      var responseTooLarge = false;
      await for (final chunk in response) {
        responseByteLength += chunk.length;
        if (responseByteLength >
            kMeasurementUploadMaximumReceiptResponseBytes) {
          responseTooLarge = true;
          break;
        }
        responseBytes.add(chunk);
      }
      if (responseTooLarge) {
        return const MeasurementUploadOutcome.protocolFailure();
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final acknowledgement = _acknowledgementDecoder.decode(
          responseBytes.takeBytes(),
          lease.record,
        );
        if (acknowledgement != null && acknowledgement.matches(lease.record)) {
          return MeasurementUploadOutcome.acknowledged(acknowledgement);
        }
        return const MeasurementUploadOutcome.protocolFailure();
      }
      if (response.statusCode == HttpStatus.conflict) {
        return const MeasurementUploadOutcome.conflict();
      }
      if (response.statusCode == HttpStatus.unauthorized ||
          response.statusCode == HttpStatus.forbidden) {
        return const MeasurementUploadOutcome.paused(
          MeasurementOutboxHoldReason.authenticationFailure,
        );
      }
      if (response.statusCode == HttpStatus.requestTimeout ||
          response.statusCode == HttpStatus.tooManyRequests ||
          response.statusCode >= HttpStatus.internalServerError) {
        return const MeasurementUploadOutcome.retryable();
      }
      if (response.statusCode >= HttpStatus.badRequest &&
          response.statusCode < HttpStatus.internalServerError) {
        return const MeasurementUploadOutcome.rejected(
          MeasurementOutboxQuarantineReason.permanentRejection,
        );
      }
      return const MeasurementUploadOutcome.protocolFailure();
    } on TimeoutException {
      return const MeasurementUploadOutcome.retryable();
    } on SocketException {
      return const MeasurementUploadOutcome.retryable();
    } on HttpException {
      return const MeasurementUploadOutcome.retryable();
    } on Object {
      return const MeasurementUploadOutcome.retryable();
    } finally {
      client.close(force: true);
    }
  }
}
