import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:restage_measurement_schema/src/canonical.dart';
import 'package:restage_measurement_schema/src/identifiers.dart';

/// Complete private argument namespace removed by every generic host.
const String kMeasurementPublicationReservedArgumentPrefixV1 =
    '__restage_measurement_';

/// Exact private argument key carrying one Measurement route carrier.
const String kMeasurementPublicationRouteArgumentKeyV1 =
    '__restage_measurement_route_v1';

/// Fixed route-carrier version marker.
const String kMeasurementPublicationRouteCarrierPrefixV1 = 'mrv1';

/// Number of opaque local-token bytes carried by one V1 route value.
const int kMeasurementPublicationRouteCarrierLocalTokenBytes = 24;

/// Number of unpadded base64url characters for a 192-bit local token.
const int kMeasurementPublicationRouteCarrierLocalTokenLength = 32;

/// Maximum code-unit length of one complete private route carrier.
const int kMaximumMeasurementPublicationRouteCarrierLength = 256;

/// Parsed strict spelling of one private full route carrier.
///
/// The value remains opaque outside the publication and host-sanitizer seams.
/// Its mounted edge and local token are exposed only to let those seams prove
/// exact carrier closure without consulting event names or business arguments.
final class MeasurementPublicationRouteCarrierV1 extends CanonicalValue {
  MeasurementPublicationRouteCarrierV1._({
    required this.value,
    required this.artifactOccurrenceEdgeToken,
    required Uint8List localToken,
  }) : _localToken = Uint8List.fromList(localToken);

  /// Parses exactly `mrv1.<encoded edge>.<192-bit local token>`.
  factory MeasurementPublicationRouteCarrierV1.parse(String value) {
    if (value.isEmpty ||
        value.length > kMaximumMeasurementPublicationRouteCarrierLength) {
      throw ArgumentError.value(
        value,
        'value',
        'Expected a non-empty route carrier of at most '
            '$kMaximumMeasurementPublicationRouteCarrierLength code units',
      );
    }
    final parts = value.split('.');
    if (parts.length != 3 ||
        parts.first != kMeasurementPublicationRouteCarrierPrefixV1) {
      throw ArgumentError.value(
        value,
        'value',
        'Expected mrv1.<base64url edge>.<192-bit local token>',
      );
    }

    final edgeBytes = _decodeBase64UrlNoPadding(
      parts[1],
      label: 'artifact occurrence edge',
    );
    late final String edgeValue;
    try {
      edgeValue = utf8.decode(edgeBytes, allowMalformed: false);
    } on FormatException {
      throw ArgumentError.value(
        value,
        'value',
        'The route carrier edge must be well-formed UTF-8',
      );
    }
    late final ArtifactOccurrenceEdgeToken edge;
    try {
      edge = ArtifactOccurrenceEdgeToken(edgeValue);
      // The identifier constructor is the grammar authority here.
      // ignore: avoid_catching_errors
    } on ArgumentError {
      throw ArgumentError.value(
        value,
        'value',
        'The route carrier edge must be an exact artifact occurrence edge',
      );
    }
    if (_base64UrlNoPadding(utf8.encode(edge.value)) != parts[1]) {
      throw ArgumentError.value(
        value,
        'value',
        'The route carrier edge must use canonical base64url spelling',
      );
    }

    if (parts[2].length !=
        kMeasurementPublicationRouteCarrierLocalTokenLength) {
      throw ArgumentError.value(
        value,
        'value',
        'The route carrier local token must be exactly '
            '$kMeasurementPublicationRouteCarrierLocalTokenLength characters',
      );
    }
    final localToken = _decodeBase64UrlNoPadding(
      parts[2],
      label: 'local token',
    );
    if (localToken.length !=
            kMeasurementPublicationRouteCarrierLocalTokenBytes ||
        _base64UrlNoPadding(localToken) != parts[2]) {
      throw ArgumentError.value(
        value,
        'value',
        'The route carrier local token must be canonical 192-bit base64url',
      );
    }

    return MeasurementPublicationRouteCarrierV1._(
      value: value,
      artifactOccurrenceEdgeToken: edge,
      localToken: Uint8List.fromList(localToken),
    );
  }

  /// Decodes byte-exact canonical carrier bytes.
  factory MeasurementPublicationRouteCarrierV1.fromCanonicalBytes(
    List<int> bytes,
  ) =>
      verifyCanonicalRoundTrip(
        MeasurementPublicationRouteCarrierV1.fromJson(
          decodeCanonicalObject(bytes),
        ),
        bytes,
        path: 'measurementPublicationRouteCarrier',
      );

  /// Decodes a closed carrier representation and re-proves its encoded edge.
  factory MeasurementPublicationRouteCarrierV1.fromJson(
    Map<String, Object?> json,
  ) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'artifactOccurrenceEdgeToken', 'kind', 'value'},
      requiredKeys: const {'artifactOccurrenceEdgeToken', 'kind', 'value'},
      path: 'measurementPublicationRouteCarrier',
    );
    if (reader.string('kind') != 'measurementPublicationRouteCarrier') {
      throw const CanonicalFormatException(
        'measurementPublicationRouteCarrier.kind must be '
        '"measurementPublicationRouteCarrier"',
      );
    }
    try {
      final carrier = MeasurementPublicationRouteCarrierV1.parse(
        reader.string('value'),
      );
      if (carrier.artifactOccurrenceEdgeToken !=
          ArtifactOccurrenceEdgeToken(
            reader.string('artifactOccurrenceEdgeToken'),
          )) {
        throw const CanonicalFormatException(
          'measurementPublicationRouteCarrier edge does not match value',
        );
      }
      return carrier;
      // Decoding must translate constructor admission failures to wire errors.
      // ignore: avoid_catching_errors
    } on ArgumentError catch (error) {
      throw CanonicalFormatException(
        'measurementPublicationRouteCarrier is invalid: ${error.message}',
      );
    }
  }

  /// Derives the exact local token from the target-neutral route closure.
  factory MeasurementPublicationRouteCarrierV1.derive({
    required CanonicalDigest routeDraftClosureDigest,
    required ArtifactOccurrenceEdgeToken artifactOccurrenceEdgeToken,
    required GeneratedReferenceId generatedReferenceId,
  }) {
    final localDigest = sha256.convert(<int>[
      ...CanonicalHashDomain.measurementPublicationRouteLocalToken.prefixBytes,
      ...CanonicalJsonCodec.encode({
        'artifactOccurrenceEdgeToken': artifactOccurrenceEdgeToken.value,
        'generatedReferenceId': generatedReferenceId.value,
        'routeDraftClosureDigest': routeDraftClosureDigest.hex,
      }),
    ]).bytes;
    final localToken = Uint8List.fromList(
      localDigest.sublist(
        0,
        kMeasurementPublicationRouteCarrierLocalTokenBytes,
      ),
    );
    return MeasurementPublicationRouteCarrierV1.parse(
      '$kMeasurementPublicationRouteCarrierPrefixV1.'
      '${_base64UrlNoPadding(utf8.encode(artifactOccurrenceEdgeToken.value))}.'
      '${_base64UrlNoPadding(localToken)}',
    );
  }

  /// Complete opaque runtime spelling.
  final String value;

  /// Exact mounted graph edge encoded into [value].
  final ArtifactOccurrenceEdgeToken artifactOccurrenceEdgeToken;

  final Uint8List _localToken;

  /// Defensive copy of the derived local 192-bit token.
  Uint8List get localToken => Uint8List.fromList(_localToken);

  @override
  Map<String, Object?> toJson() => {
        'artifactOccurrenceEdgeToken': artifactOccurrenceEdgeToken.value,
        'kind': 'measurementPublicationRouteCarrier',
        'value': value,
      };
}

/// Canonical fingerprint of one strict full route-carrier spelling.
///
/// Only the fingerprint is retained in the published binding. The raw carrier
/// remains draft and generated-artifact material.
final class OpaqueMeasurementRouteTokenV1 extends CanonicalValue {
  /// Creates one already-validated opaque route-carrier fingerprint.
  const OpaqueMeasurementRouteTokenV1({required this.fingerprint});

  /// Parses [value] and fingerprints its complete strict carrier spelling.
  factory OpaqueMeasurementRouteTokenV1.fromRuntimeCarrier(String value) {
    final carrier = MeasurementPublicationRouteCarrierV1.parse(value);
    return OpaqueMeasurementRouteTokenV1(
      fingerprint: canonicalSha256(
        CanonicalHashDomain.measurementPublicationRouteCarrier,
        CanonicalJsonCodec.encode(carrier.value),
      ),
    );
  }

  /// Decodes byte-exact canonical route-token bytes.
  factory OpaqueMeasurementRouteTokenV1.fromCanonicalBytes(List<int> bytes) =>
      verifyCanonicalRoundTrip(
        OpaqueMeasurementRouteTokenV1.fromJson(decodeCanonicalObject(bytes)),
        bytes,
        path: 'opaqueMeasurementRouteToken',
      );

  /// Decodes a closed route-carrier fingerprint.
  factory OpaqueMeasurementRouteTokenV1.fromJson(Map<String, Object?> json) {
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: const {'fingerprint', 'kind'},
      requiredKeys: const {'fingerprint', 'kind'},
      path: 'opaqueMeasurementRouteToken',
    );
    if (reader.string('kind') != 'opaqueMeasurementRouteToken') {
      throw const CanonicalFormatException(
        'opaqueMeasurementRouteToken.kind must be '
        '"opaqueMeasurementRouteToken"',
      );
    }
    return OpaqueMeasurementRouteTokenV1(
      fingerprint: CanonicalDigest(reader.string('fingerprint')),
    );
  }

  /// Domain-separated fingerprint of one full carrier spelling.
  final CanonicalDigest fingerprint;

  @override
  Map<String, Object?> toJson() => {
        'fingerprint': fingerprint.hex,
        'kind': 'opaqueMeasurementRouteToken',
      };
}

List<int> _decodeBase64UrlNoPadding(String value, {required String label}) {
  if (value.isEmpty || !_base64UrlNoPaddingPattern.hasMatch(value)) {
    throw ArgumentError.value(
      value,
      label,
      'Expected unpadded base64url characters',
    );
  }
  try {
    return base64Url.decode(base64Url.normalize(value));
  } on FormatException {
    throw ArgumentError.value(value, label, 'Expected valid base64url');
  }
}

String _base64UrlNoPadding(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

final RegExp _base64UrlNoPaddingPattern = RegExp(r'^[A-Za-z0-9_-]+$');
