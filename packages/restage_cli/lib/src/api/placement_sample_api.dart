import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:restage_cli/src/api/byte_data_wire.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';

/// Largest canonical capture, draft, or reviewed sample request.
const maximumPlacementSampleDocumentBytes =
    kMaximumPlacementRequestBytes +
    placementScreenSampleMaxManifestBytes +
    1024;

/// Binds explicitly supplied capture evidence to an authorized target locally.
PlacementSampleDraftV1 importPlacementSample({
  required Uint8List captureBytes,
  required Uint8List pngBytes,
  required TargetCoordinate target,
  String? screenLabel,
}) {
  final capture = PlacementScreenCaptureV1.fromCanonicalBytes(captureBytes);
  final manifest = capture
      .bindTarget(target)
      .copyWith(screenLabel: screenLabel);
  final validated = validatePlacementScreenSample(
    manifest: manifest,
    pngBytes: pngBytes,
  );
  return PlacementSampleDraftV1(
    manifest: validated.manifest,
    buildContract: capture.buildContract,
    reviewedDigest: validated.reviewDigest,
  );
}

/// A storage owner's typed refusal, with its original reason intact.
@experimental
sealed class PlacementSampleException implements Exception {
  /// Retains the service's refusal term.
  const PlacementSampleException(this.reason);

  /// Original public refusal reason.
  final String reason;

  @override
  String toString() => '$runtimeType: $reason';
}

/// The requested sample operation was rejected.
@experimental
final class PlacementSampleRejected extends PlacementSampleException {
  /// Retains the service's reason.
  const PlacementSampleRejected(super.reason);
}

/// The requested sample body is unavailable.
@experimental
final class PlacementSampleUnavailable extends PlacementSampleException {
  /// Retains the service's reason.
  const PlacementSampleUnavailable(super.reason);
}

/// The service returned malformed or differently addressed sample evidence.
@experimental
final class PlacementSampleResponseException implements Exception {
  /// Creates a response-binding failure.
  const PlacementSampleResponseException();

  @override
  String toString() => 'The service returned an invalid sample result.';
}

/// Typed private sample operations over the shared authenticated transport.
@experimental
final class PlacementSampleApi {
  /// Reuses the existing RPC client and credentials.
  PlacementSampleApi(this._api);

  final RestageApi _api;

  /// Verifies current image bytes before preparing the explicitly reviewed draft.
  Future<PlacementSampleUploadTicketV1> prepare({
    required String projectSlug,
    required String appSlug,
    required TargetCoordinate target,
    required PlacementSamplePrepareV1 request,
    required Uint8List pngBytes,
  }) async {
    if (request.manifest.target != target) {
      throw const FormatException('The draft is for another target.');
    }
    validatePlacementScreenSample(
      manifest: request.manifest,
      pngBytes: pngBytes,
    );
    final result = await _document(
      'prepare',
      projectSlug: projectSlug,
      appSlug: appSlug,
      target: target,
      request: request,
      decode: PlacementSampleUploadTicketV1.fromCanonicalBytes,
    );
    if (result.manifestDigest != request.manifestDigest ||
        result.imageSha256 != request.manifest.pngSha256) {
      throw const PlacementSampleResponseException();
    }
    return result;
  }

  /// Stores current PNG bytes only when they match the server's reviewed ticket.
  Future<PlacementSampleStoredV1> store({
    required String projectSlug,
    required String appSlug,
    required TargetCoordinate target,
    required PlacementSampleUploadTicketV1 ticket,
    required Uint8List pngBytes,
  }) async {
    final png = validatePlacementScreenSamplePng(pngBytes);
    if (png.contentHash != ticket.imageSha256 ||
        png.byteLength > ticket.limits.maxPngBytes ||
        png.width > ticket.limits.maxDimension ||
        png.height > ticket.limits.maxDimension) {
      throw const FormatException(
        'The PNG does not match the reviewed ticket.',
      );
    }
    final result = await _document(
      'store',
      projectSlug: projectSlug,
      appSlug: appSlug,
      target: target,
      request: PlacementSampleStoreV1(
        ticketId: ticket.ticketId,
        manifestDigest: ticket.manifestDigest,
      ),
      decode: PlacementSampleStoredV1.fromCanonicalBytes,
      pngBytes: png.bytes,
    );
    if (result.manifestDigest != ticket.manifestDigest ||
        result.imageSha256 != ticket.imageSha256) {
      throw const PlacementSampleResponseException();
    }
    return result;
  }

  /// Binds the complete stored frame under an expected association revision.
  Future<PlacementScreenSampleRefV1> bind({
    required String projectSlug,
    required String appSlug,
    required TargetCoordinate target,
    required PlacementSampleBindV1 request,
  }) async {
    final result = await _document(
      'bind',
      projectSlug: projectSlug,
      appSlug: appSlug,
      target: target,
      request: request,
      decode: PlacementScreenSampleRefV1.fromCanonicalBytes,
    );
    if (result.target != target || result.sampleId != request.sampleId) {
      throw const PlacementSampleResponseException();
    }
    return result;
  }

  /// Reads truthful sample availability without creating an association.
  Future<PlacementSampleReadResultV1> read({
    required String projectSlug,
    required String appSlug,
    required TargetCoordinate target,
    required PlacementSampleReadV1 request,
  }) async {
    final result = await _document(
      'read',
      projectSlug: projectSlug,
      appSlug: appSlug,
      target: target,
      request: request,
      decode: PlacementSampleReadResultV1.fromCanonicalBytes,
    );
    if (result.sampleId != request.sampleId ||
        (result.manifest != null && result.manifest!.target != target) ||
        (result.ref != null && result.ref!.target != target)) {
      throw const PlacementSampleResponseException();
    }
    return result;
  }

  /// Reads an authorized, bounded PNG through the existing RPC transport.
  Future<Uint8List> readImage({
    required String projectSlug,
    required String appSlug,
    required TargetCoordinate target,
    required PlacementSampleReadV1 request,
  }) async {
    final raw = await _call(
      'readImage',
      _arguments(projectSlug, appSlug, target, request),
    );
    try {
      final bytes = decodeByteDataWire(
        raw,
        maximumBytes: placementScreenSampleMaxBytes,
        malformed: (_) => const PlacementSampleResponseException(),
      );
      return validatePlacementScreenSamplePng(bytes).bytes;
    } on FormatException {
      throw const PlacementSampleResponseException();
    }
  }

  /// Removes an image body and its association through fresh authorization.
  Future<PlacementSampleDeleteResultV1> delete({
    required String projectSlug,
    required String appSlug,
    required TargetCoordinate target,
    required PlacementSampleDeleteV1 request,
  }) async {
    final result = await _document(
      'delete',
      projectSlug: projectSlug,
      appSlug: appSlug,
      target: target,
      request: request,
      decode: PlacementSampleDeleteResultV1.fromCanonicalBytes,
    );
    if (result.sampleId != request.sampleId) {
      throw const PlacementSampleResponseException();
    }
    return result;
  }

  Future<T> _document<T>(
    String method, {
    required String projectSlug,
    required String appSlug,
    required TargetCoordinate target,
    required CanonicalValue request,
    required T Function(List<int>) decode,
    Uint8List? pngBytes,
  }) async {
    final raw = await _call(method, {
      ..._arguments(projectSlug, appSlug, target, request),
      if (pngBytes != null) 'pngBytes': encodeByteDataWire(pngBytes),
    });
    try {
      return decode(
        decodeByteDataWire(
          raw,
          maximumBytes: maximumPlacementSampleDocumentBytes,
          malformed: (_) => const PlacementSampleResponseException(),
        ),
      );
    } on CanonicalFormatException {
      throw const PlacementSampleResponseException();
    }
  }

  Map<String, dynamic> _arguments(
    String projectSlug,
    String appSlug,
    TargetCoordinate target,
    CanonicalValue request,
  ) => {
    'projectSlug': projectSlug,
    'appSlug': appSlug,
    'organizationId': target.organizationId.value,
    'environmentTargetId': target.environmentTargetId.value,
    'runtimePlane': target.runtimePlane.name,
    'requestBytes': encodeByteDataWire(request.canonicalBytes),
  };

  Future<dynamic> _call(String method, Map<String, dynamic> arguments) async {
    try {
      return await _api.call('placementSample', method, arguments);
    } on RestageApiException catch (error) {
      final Object? body;
      try {
        body = jsonDecode(error.body);
      } on FormatException {
        rethrow;
      }
      if (body is Map<String, dynamic>) {
        final data = body['data'];
        if (data is! Map<String, dynamic> || data['reason'] is! String) rethrow;
        final reason = data['reason'] as String;
        switch (body['className']) {
          case 'PlacementSampleRejectedException':
            throw PlacementSampleRejected(reason);
          case 'PlacementSampleUnavailableException':
            throw PlacementSampleUnavailable(reason);
        }
      }
      rethrow;
    }
  }
}
