import 'dart:typed_data';

import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    show
        CanonicalFormatException,
        CanonicalJsonCodec,
        CanonicalObjectReader,
        requireCanonicalObject;
import 'package:restage_shared/src/surface_contract/surface_contract_json.dart';

/// The immutable device identity carried until a credential is confirmed.
final class SurfaceRegistrationTupleV1 {
  /// Creates a tuple. Its client timestamp is identity, not expiry authority.
  const SurfaceRegistrationTupleV1({
    required this.registrationNonce,
    required this.registrationCreatedAtMicros,
  });

  /// Reads the same two tuple fields alongside an ordinary request body.
  factory SurfaceRegistrationTupleV1.fromJson(Object? value) {
    final json = requireCanonicalObject(value, 'registration');
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: json.keys.toSet(),
      requiredKeys: const {'registrationNonce', 'registrationCreatedAtMicros'},
      path: 'registration',
    );
    final nonce = reader.string('registrationNonce');
    final createdAt = reader.integer('registrationCreatedAtMicros');
    final Uint8List bytes;
    try {
      bytes = SurfaceContractJson.decodeCanonicalBase64Url(
        nonce,
        'registrationNonce',
      );
    } on FormatException {
      throw const CanonicalFormatException('Invalid base64url');
    }
    if (bytes.length != 32 || createdAt < 1 || createdAt > 9007199254740991) {
      throw const CanonicalFormatException('Invalid registration tuple');
    }
    return SurfaceRegistrationTupleV1(
      registrationNonce: nonce,
      registrationCreatedAtMicros: createdAt,
    );
  }

  /// Refuses a partial or malformed tuple rather than treating it as absent.
  static SurfaceRegistrationTupleV1? fromServeBody(Map<String, Object?> body) {
    if (!body.containsKey('registrationNonce') &&
        !body.containsKey('registrationCreatedAtMicros')) {
      return null;
    }
    return SurfaceRegistrationTupleV1.fromJson(body);
  }

  /// Unpadded canonical base64url encoding of 32 random bytes.
  final String registrationNonce;

  /// Client creation time; immutable handle identity only.
  final int registrationCreatedAtMicros;

  /// Original folded tuple fields.
  Map<String, Object?> toJson() => {
        'registrationNonce': registrationNonce,
        'registrationCreatedAtMicros': registrationCreatedAtMicros,
      };
}

/// Credential confirmation carried beside ordinary content decisions.
final class SurfaceRegistrationMetadataV1 {
  /// Creates confirmed expiry and the issuer's post-lock clock.
  const SurfaceRegistrationMetadataV1({
    required this.credentialHandle,
    required this.expiresAtMicros,
    required this.serverNowMicros,
  });

  /// Reads the original exact three-field folded confirmation.
  factory SurfaceRegistrationMetadataV1.fromJson(Object? value) {
    final json = requireCanonicalObject(value, 'registration metadata');
    const keys = {'credentialHandle', 'expiresAtMicros', 'serverNowMicros'};
    final reader = CanonicalObjectReader(
      json,
      allowedKeys: keys,
      requiredKeys: keys,
      path: 'registration metadata',
    );
    final handle = reader.string('credentialHandle');
    final expiry = reader.integer('expiresAtMicros');
    final now = reader.integer('serverNowMicros');
    if (!RegExp(r'^ic1\.[0-9a-f]{64}$').hasMatch(handle) ||
        expiry < 1 ||
        now < 1) {
      throw const CanonicalFormatException('Invalid registration metadata');
    }
    return SurfaceRegistrationMetadataV1(
      credentialHandle: handle,
      expiresAtMicros: expiry,
      serverNowMicros: now,
    );
  }

  /// Decodes the exact original canonical confirmation bytes.
  factory SurfaceRegistrationMetadataV1.fromCanonicalBytes(List<int> bytes) {
    final result = SurfaceRegistrationMetadataV1.fromJson(
      CanonicalJsonCodec.decode(bytes),
    );
    if (!SurfaceContractJson.bytesEqual(result.toCanonicalBytes(), bytes)) {
      throw const CanonicalFormatException('Not the canonical representation');
    }
    return result;
  }

  /// Refuses partial confirmation beside the other response fields.
  static SurfaceRegistrationMetadataV1? fromServeBody(
    Map<String, Object?> body,
  ) {
    const keys = {'credentialHandle', 'expiresAtMicros', 'serverNowMicros'};
    if (!keys.any(body.containsKey)) return null;
    return SurfaceRegistrationMetadataV1.fromJson({
      for (final key in keys)
        if (body.containsKey(key)) key: body[key],
    });
  }

  /// Confirmed opaque credential handle.
  final String credentialHandle;

  /// Immutable issuer expiry; authorization remains external.
  final int expiresAtMicros;

  /// Clock sampled by the issuer after its registration lock wait.
  final int serverNowMicros;

  /// Original folded confirmation fields.
  Map<String, Object?> toJson() => {
        'credentialHandle': credentialHandle,
        'expiresAtMicros': expiresAtMicros,
        'serverNowMicros': serverNowMicros,
      };

  /// Exact original canonical confirmation bytes.
  Uint8List toCanonicalBytes() => CanonicalJsonCodec.encode(toJson());
}
