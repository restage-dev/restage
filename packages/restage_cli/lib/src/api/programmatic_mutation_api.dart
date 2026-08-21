import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/api/measurement_wire.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    as measurement;

/// Typed client for the canonical programmatic mutation protocol.
@experimental
class ProgrammaticMutationApi {
  /// Creates a client over the shared RPC transport.
  ProgrammaticMutationApi(this._api);

  final RestageApi _api;

  /// Sends one strict canonical mutation request.
  Future<ProgrammaticMutationResponseWireV1> mutate({
    required String projectSlug,
    required String appSlug,
    required String environmentSlug,
    required int organizationId,
    required int appId,
    required int namedEnvironmentId,
    required int environmentTargetId,
    required RuntimePlane runtimePlane,
    required ProgrammaticMutationRequestWireV1 request,
  }) => mutateCanonicalBytes(
    projectSlug: projectSlug,
    appSlug: appSlug,
    environmentSlug: environmentSlug,
    organizationId: organizationId,
    appId: appId,
    namedEnvironmentId: namedEnvironmentId,
    environmentTargetId: environmentTargetId,
    runtimePlane: runtimePlane,
    canonicalRequestBytes: request.canonicalBytes,
  );

  /// Sends one exact canonical request byte sequence.
  ///
  /// The bytes are decoded before transport, which rejects alternate spellings
  /// and ensures the outbound byte sequence is the canonical request itself.
  Future<ProgrammaticMutationResponseWireV1> mutateCanonicalBytes({
    required String projectSlug,
    required String appSlug,
    required String environmentSlug,
    required int organizationId,
    required int appId,
    required int namedEnvironmentId,
    required int environmentTargetId,
    required RuntimePlane runtimePlane,
    required List<int> canonicalRequestBytes,
  }) async {
    final request = _strictCanonicalRequest(canonicalRequestBytes);
    _requireExactTarget(
      request.target,
      organizationId: organizationId,
      appId: appId,
      namedEnvironmentId: namedEnvironmentId,
      environmentTargetId: environmentTargetId,
      runtimePlane: runtimePlane,
    );
    final rawResponse = await _api
        .call(_endpointName, _methodName, <String, dynamic>{
          'projectSlug': projectSlug,
          'appSlug': appSlug,
          'environmentSlug': environmentSlug,
          'environmentTargetId': environmentTargetId,
          'runtimePlane': runtimePlane.wireName,
          'requestBytes': _byteDataWire(request.canonicalBytes),
          'organizationId': organizationId,
          'appId': appId,
        });
    return ProgrammaticMutationResponseWireV1.fromCanonicalBytes(
      _strictResponseBytes(rawResponse),
    );
  }
}

/// The canonical request addresses a different target than the declared route.
///
/// The exception deliberately carries no coordinate values: callers can report
/// a deterministic safe error without reflecting operator input or request
/// contents. It is raised before any mutation RPC is sent.
@experimental
final class ProgrammaticMutationTargetMismatchException implements Exception {
  /// Creates the target-binding failure.
  const ProgrammaticMutationTargetMismatchException();

  @override
  String toString() =>
      'Canonical mutation request target does not match the '
      'declared route target.';
}

const _endpointName = 'programmaticMutation';
const _methodName = 'mutate';
const _byteDataPrefix = "decode('";
const _byteDataSuffix = "', 'base64')";

ProgrammaticMutationRequestWireV1 _strictCanonicalRequest(List<int> source) {
  // An out-of-range byte count is a caller mistake at this API, not a malformed
  // document, and has always been reported as one.
  final length = source.length;
  if (length == 0 || length > kMaximumProgrammaticMutationWireBytes) {
    throw ArgumentError.value(
      length,
      'canonicalRequestBytes.length',
      'Expected 1..$kMaximumProgrammaticMutationWireBytes bytes',
    );
  }
  return ProgrammaticMutationRequestWireV1.fromCanonicalBytes(source);
}

void _requireExactTarget(
  measurement.TargetCoordinate target, {
  required int organizationId,
  required int appId,
  required int namedEnvironmentId,
  required int environmentTargetId,
  required RuntimePlane runtimePlane,
}) {
  final expectedPlane = switch (runtimePlane) {
    RuntimePlane.sandbox => measurement.RuntimePlane.sandbox,
    RuntimePlane.live => measurement.RuntimePlane.live,
  };
  if (target.organizationId.value != organizationId ||
      target.appId.value != appId ||
      target.namedEnvironmentId.value != namedEnvironmentId ||
      target.environmentTargetId.value != environmentTargetId ||
      target.runtimePlane != expectedPlane) {
    throw const ProgrammaticMutationTargetMismatchException();
  }
}

String _byteDataWire(Uint8List bytes) =>
    "$_byteDataPrefix${base64Encode(bytes)}$_byteDataSuffix";

Uint8List _strictResponseBytes(Object? rawResponse) {
  if (rawResponse is! String ||
      !rawResponse.startsWith(_byteDataPrefix) ||
      !rawResponse.endsWith(_byteDataSuffix)) {
    throw const FormatException('Expected a ByteData response');
  }
  final encoded = rawResponse.substring(
    _byteDataPrefix.length,
    rawResponse.length - _byteDataSuffix.length,
  );
  final maximumEncodedLength =
      ((kMaximumProgrammaticMutationWireBytes + 2) ~/ 3) * 4;
  if (encoded.isEmpty || encoded.length > maximumEncodedLength) {
    throw const FormatException('Response ByteData exceeds its bounded shape');
  }

  late final Uint8List bytes;
  try {
    bytes = Uint8List.fromList(base64Decode(encoded));
  } on FormatException {
    throw const FormatException('Response ByteData is not valid base64');
  }
  if (bytes.isEmpty ||
      bytes.length > kMaximumProgrammaticMutationWireBytes ||
      base64Encode(bytes) != encoded) {
    throw const FormatException('Response ByteData is not canonical');
  }
  return bytes;
}
