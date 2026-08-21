import 'dart:convert';
import 'dart:typed_data';

import 'package:restage_shared/src/surface_contract/surface_contract_json.dart';

/// The only packaged location for the Measurement bundled target profile.
///
/// This is deliberately outside the source-owned `.rsbundle` directory. The
/// profile names the selected bundle files but is never an entry in one.
const String kMeasurementBundledTargetProfileAssetPath =
    'assets/restage/measurement/target-profile.v1.json';

/// Maximum source-owned bundles sealed by one target profile.
///
/// This is a delivery-profile bound, independent of the payload-entry bound
/// inside each source-owned bundle.
const int kMaximumMeasurementBundledTargetProfileBundleCount = 1024;

/// Maximum UTF-8 bytes in one selected source-owned bundle asset path.
///
/// This matches the frozen classic-ZIP filename ceiling used by source-owned
/// `.rsbundle` paths. It applies to the complete Flutter asset key, including
/// the fixed `assets/restage/bundles/` prefix and `.rsbundle` suffix.
const int kMaximumMeasurementBundledTargetProfileBundleAssetPathUtf8Bytes =
    0xFFFF;

/// Maximum canonical bytes for the exact target carried by one profile.
///
/// A V1 target contains four portable integer authorities and fixed literals;
/// this leaves a strict bounded envelope without importing Measurement types.
const int kMaximumMeasurementBundledTargetProfileTargetCanonicalBytes = 512;

/// Maximum canonical bytes for the exact registry carried by one profile.
///
/// This deliberately mirrors the owning registry's 32 MiB V1 admission bound.
/// `restage_shared` keeps this delivery-envelope constant dependency-free.
const int kMaximumMeasurementBundledTargetProfileRegistryCanonicalBytes =
    32 * 1024 * 1024;

// Exact V1 canonical framing limits. A profile object with empty strings and
// an empty array is 127 UTF-8 bytes; a bundle record with an empty asset path
// is 99 bytes. The required source-owned asset prefix and suffix consume 32
// of the 65,535 admitted path bytes. Every remaining byte can be a JSON
// control scalar, whose canonical spelling is six UTF-8 bytes. These values
// therefore bound every accepted canonical path spelling without narrowing the
// existing source-owned path grammar.
const int _kRequiredBundleAssetPathUtf8Bytes = 32;
const int _kMaximumBundleAssetPathCanonicalJsonContentBytes =
    _kRequiredBundleAssetPathUtf8Bytes +
        (6 *
            (kMaximumMeasurementBundledTargetProfileBundleAssetPathUtf8Bytes -
                _kRequiredBundleAssetPathUtf8Bytes));
const int _kTargetProfileFixedCanonicalBytes = 127;
const int _kTargetProfileBundleRecordFixedCanonicalBytes = 99;
const int _kMaximumTargetCanonicalBase64UrlBytes = 683;
const int _kMaximumRegistryCanonicalBase64UrlBytes = 44739243;

/// Maximum UTF-8 bytes admitted for one target-profile asset.
///
/// This exact whole-profile envelope is closed under the V1 field bounds:
/// `127 + 683 + 44,739,243 + 1,024 * (99 + 393,050) + 1,023` equals
/// 447,325,652. The raw asset is rejected before JSON or base64 decoding.
const int kMaximumMeasurementBundledTargetProfileAssetBytes =
    _kTargetProfileFixedCanonicalBytes +
        _kMaximumTargetCanonicalBase64UrlBytes +
        _kMaximumRegistryCanonicalBase64UrlBytes +
        (kMaximumMeasurementBundledTargetProfileBundleCount *
            (_kTargetProfileBundleRecordFixedCanonicalBytes +
                _kMaximumBundleAssetPathCanonicalJsonContentBytes)) +
        (kMaximumMeasurementBundledTargetProfileBundleCount - 1);

const String _kMeasurementBundledTargetProfileKind =
    'measurementBundledTargetProfile';
const int _kMeasurementBundledTargetProfileSchemaVersion = 1;
const String _kSourceOwnedBundleAssetDirectory = 'assets/restage/bundles/';

/// Whether [assetPath] is one exact source-owned bundled asset key.
///
/// This is the shared admission grammar for the immutable target profile and
/// the CLI's packaging boundary. A non-bundled generated-output closure cannot
/// select a bundled Measurement target profile.
bool isMeasurementBundledSourceOwnedBundleAssetPathV1(String assetPath) {
  try {
    _validateAssetPath(assetPath, 'assetPath');
    return true;
  } on FormatException {
    return false;
  }
}

/// One exact source-owned bundle admitted to a Measurement target profile.
final class MeasurementBundledTargetProfileBundle {
  /// Creates one profile record for a packaged source-owned bundle.
  MeasurementBundledTargetProfileBundle({
    required this.assetPath,
    required this.sha256,
  }) {
    _validateAssetPath(assetPath, 'assetPath');
    SurfaceContractJson.requireSha256(sha256, 'sha256');
  }

  /// Decodes one strict profile bundle record.
  factory MeasurementBundledTargetProfileBundle.fromJson(
    Object? value, {
    required String path,
  }) {
    final json = SurfaceContractJson.requireObject(value, path);
    SurfaceContractJson.exactKeys(json, const {'assetPath', 'sha256'}, path);
    return MeasurementBundledTargetProfileBundle(
      assetPath: SurfaceContractJson.requiredString(json, 'assetPath', path),
      sha256: SurfaceContractJson.requiredString(json, 'sha256', path),
    );
  }

  /// Flutter asset key for the selected `.rsbundle`.
  final String assetPath;

  /// SHA-256 of the exact packaged bundle bytes.
  final String sha256;

  /// Encodes the strict record shape.
  Map<String, Object?> toJson() => <String, Object?>{
        'assetPath': assetPath,
        'sha256': sha256,
      };
}

/// Immutable delivery profile for one Measurement target.
///
/// The profile is a delivery manifest, not a Measurement or publication wire
/// document. Target and registry values remain opaque exact canonical bytes
/// here; their owning codecs validate them before the SDK exposes a read port.
final class MeasurementBundledTargetProfileV1 {
  /// Creates one immutable target profile.
  MeasurementBundledTargetProfileV1({
    required List<int> targetCanonicalBytes,
    required List<int> registryCanonicalBytes,
    required List<MeasurementBundledTargetProfileBundle> bundles,
  })  : targetCanonicalBytes = _boundedNonEmptyBytes(
          targetCanonicalBytes,
          'targetCanonicalBytes',
          kMaximumMeasurementBundledTargetProfileTargetCanonicalBytes,
        ),
        registryCanonicalBytes = _boundedNonEmptyBytes(
          registryCanonicalBytes,
          'registryCanonicalBytes',
          kMaximumMeasurementBundledTargetProfileRegistryCanonicalBytes,
        ),
        bundles = _sortedBundles(bundles) {
    if (canonicalByteLength >
        kMaximumMeasurementBundledTargetProfileAssetBytes) {
      throw ArgumentError.value(
        canonicalByteLength,
        'target profile',
        'exceeds the $kMaximumMeasurementBundledTargetProfileAssetBytes-byte '
            'asset limit',
      );
    }
  }

  /// Decodes byte-exact canonical target-profile asset bytes.
  factory MeasurementBundledTargetProfileV1.fromCanonicalBytes(
    List<int> bytes,
  ) {
    _requireAssetByteLength(bytes.length);
    late final String source;
    try {
      source = utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      throw const FormatException(
        'Measurement bundled target profile is not valid UTF-8.',
      );
    }
    return MeasurementBundledTargetProfileV1.decodeCanonicalJson(source);
  }

  /// Decodes a byte-exact canonical target-profile asset.
  factory MeasurementBundledTargetProfileV1.decodeCanonicalJson(String source) {
    _requireAssetByteLength(_utf8ByteLength(source));
    final json = SurfaceContractJson.requireObject(
      SurfaceContractJson.decode(
        source,
        label: 'Measurement bundled target profile',
      ),
      r'$',
    );
    SurfaceContractJson.exactKeys(
      json,
      const {
        'bundles',
        'kind',
        'registryCanonicalBytes',
        'schemaVersion',
        'targetCanonicalBytes',
      },
      r'$',
    );
    if (SurfaceContractJson.requiredString(json, 'kind', r'$') !=
        _kMeasurementBundledTargetProfileKind) {
      throw const FormatException(
        'Unsupported Measurement bundled target profile kind.',
      );
    }
    if (SurfaceContractJson.requiredInt(json, 'schemaVersion', r'$') !=
        _kMeasurementBundledTargetProfileSchemaVersion) {
      throw const FormatException(
        'Unsupported Measurement bundled target profile schemaVersion.',
      );
    }
    final rawBundles = SurfaceContractJson.requiredValue(
      json,
      'bundles',
      r'$',
    );
    if (rawBundles is! List) {
      throw const FormatException(r'Expected "$.bundles" to be a list.');
    }
    if (rawBundles.isEmpty ||
        rawBundles.length >
            kMaximumMeasurementBundledTargetProfileBundleCount) {
      throw const FormatException(
        'Measurement bundled target profile bundles must contain 1..'
        '$kMaximumMeasurementBundledTargetProfileBundleCount records.',
      );
    }
    final profile = MeasurementBundledTargetProfileV1(
      targetCanonicalBytes: _decodeBoundedCanonicalBase64Url(
        SurfaceContractJson.requiredString(json, 'targetCanonicalBytes', r'$'),
        r'$.targetCanonicalBytes',
        kMaximumMeasurementBundledTargetProfileTargetCanonicalBytes,
      ),
      registryCanonicalBytes: _decodeBoundedCanonicalBase64Url(
        SurfaceContractJson.requiredString(
          json,
          'registryCanonicalBytes',
          r'$',
        ),
        r'$.registryCanonicalBytes',
        kMaximumMeasurementBundledTargetProfileRegistryCanonicalBytes,
      ),
      bundles: <MeasurementBundledTargetProfileBundle>[
        for (var index = 0; index < rawBundles.length; index += 1)
          MeasurementBundledTargetProfileBundle.fromJson(
            rawBundles[index],
            path: '\$.bundles[$index]',
          ),
      ],
    );
    if (profile.encodeCanonicalJson() != source) {
      throw const FormatException(
        'Measurement bundled target profile is not canonical JSON.',
      );
    }
    return profile;
  }

  /// Exact canonical target-coordinate bytes.
  final Uint8List targetCanonicalBytes;

  /// Exact canonical Measurement registry bytes.
  final Uint8List registryCanonicalBytes;

  /// Exact selected source-owned bundle profile, ordered by UTF-8 asset path.
  final List<MeasurementBundledTargetProfileBundle> bundles;

  /// Canonical UTF-8 bytes stored at
  /// [kMeasurementBundledTargetProfileAssetPath].
  Uint8List get canonicalBytes {
    final bytes = SurfaceContractJson.utf8Bytes(toJson());
    if (bytes.length != canonicalByteLength ||
        bytes.length > kMaximumMeasurementBundledTargetProfileAssetBytes) {
      throw StateError(
        'Measurement bundled target-profile canonical byte accounting failed.',
      );
    }
    return bytes;
  }

  /// Exact canonical UTF-8 length without materializing the profile asset.
  int get canonicalByteLength {
    var byteLength = _kTargetProfileFixedCanonicalBytes +
        _base64UrlLength(targetCanonicalBytes.length) +
        _base64UrlLength(registryCanonicalBytes.length);
    for (final bundle in bundles) {
      byteLength += _kTargetProfileBundleRecordFixedCanonicalBytes +
          _canonicalJsonStringContentUtf8ByteLength(bundle.assetPath);
    }
    return byteLength + bundles.length - 1;
  }

  /// Encodes the profile's strict canonical JSON representation.
  String encodeCanonicalJson() => SurfaceContractJson.encode(toJson());

  /// Encodes the profile's strict canonical JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
        'bundles': <Object?>[for (final bundle in bundles) bundle.toJson()],
        'kind': _kMeasurementBundledTargetProfileKind,
        'registryCanonicalBytes': SurfaceContractJson.encodeBase64Url(
          registryCanonicalBytes,
        ),
        'schemaVersion': _kMeasurementBundledTargetProfileSchemaVersion,
        'targetCanonicalBytes': SurfaceContractJson.encodeBase64Url(
          targetCanonicalBytes,
        ),
      };
}

Uint8List _boundedNonEmptyBytes(
  List<int> value,
  String path,
  int maximumLength,
) {
  if (value.isEmpty) {
    throw ArgumentError.value(value, path, 'must not be empty');
  }
  if (value.length > maximumLength) {
    throw ArgumentError.value(
      value.length,
      path,
      'must contain at most $maximumLength bytes',
    );
  }
  return Uint8List.fromList(value);
}

List<MeasurementBundledTargetProfileBundle> _sortedBundles(
  List<MeasurementBundledTargetProfileBundle> values,
) {
  if (values.isEmpty ||
      values.length > kMaximumMeasurementBundledTargetProfileBundleCount) {
    throw ArgumentError.value(
      values.length,
      'bundles',
      'requires 1..$kMaximumMeasurementBundledTargetProfileBundleCount '
          'source-owned bundles',
    );
  }
  final sorted = List<MeasurementBundledTargetProfileBundle>.of(values)
    ..sort(
      (left, right) =>
          SurfaceContractJson.compareUtf8(left.assetPath, right.assetPath),
    );
  for (var index = 1; index < sorted.length; index += 1) {
    if (sorted[index - 1].assetPath == sorted[index].assetPath) {
      throw ArgumentError(
        'Measurement target-profile bundle paths must be unique',
      );
    }
  }
  return List<MeasurementBundledTargetProfileBundle>.unmodifiable(sorted);
}

Uint8List _decodeBoundedCanonicalBase64Url(
  String source,
  String path,
  int maximumDecodedLength,
) {
  if (source.length > _maximumBase64UrlLength(maximumDecodedLength)) {
    throw FormatException('Expected "$path" to stay within its byte bound.');
  }
  final decoded = SurfaceContractJson.decodeCanonicalBase64Url(source, path);
  if (decoded.length > maximumDecodedLength) {
    throw FormatException('Expected "$path" to stay within its byte bound.');
  }
  return decoded;
}

int _maximumBase64UrlLength(int byteLength) {
  return _base64UrlLength(byteLength);
}

int _base64UrlLength(int byteLength) {
  final paddedLength = ((byteLength + 2) ~/ 3) * 4;
  return switch (byteLength % 3) {
    1 => paddedLength - 2,
    2 => paddedLength - 1,
    _ => paddedLength,
  };
}

void _requireAssetByteLength(int byteLength) {
  if (byteLength > kMaximumMeasurementBundledTargetProfileAssetBytes) {
    throw const FormatException(
      'Measurement bundled target profile exceeds its raw byte bound.',
    );
  }
}

int _utf8ByteLength(String source) {
  if (source.length > kMaximumMeasurementBundledTargetProfileAssetBytes) {
    return source.length;
  }
  var byteLength = 0;
  for (var index = 0; index < source.length; index += 1) {
    final unit = source.codeUnitAt(index);
    if (unit <= 0x7f) {
      byteLength += 1;
    } else if (unit <= 0x7ff) {
      byteLength += 2;
    } else if (unit >= 0xd800 &&
        unit <= 0xdbff &&
        index + 1 < source.length &&
        source.codeUnitAt(index + 1) >= 0xdc00 &&
        source.codeUnitAt(index + 1) <= 0xdfff) {
      byteLength += 4;
      index += 1;
    } else {
      // Dart's UTF-8 codec encodes an unpaired surrogate as U+FFFD.
      byteLength += 3;
    }
    if (byteLength > kMaximumMeasurementBundledTargetProfileAssetBytes) {
      return byteLength;
    }
  }
  return byteLength;
}

void _validateAssetPath(String value, String path) {
  if (value.isEmpty ||
      value.startsWith('/') ||
      value.contains(String.fromCharCode(0x5c)) ||
      value.contains('\u0000') ||
      RegExp('^[A-Za-z][A-Za-z0-9+.-]*:').hasMatch(value) ||
      !value.startsWith(_kSourceOwnedBundleAssetDirectory) ||
      !value.endsWith('.rsbundle')) {
    throw FormatException(
      'Expected "$path" to name a source-owned .rsbundle asset.',
    );
  }
  SurfaceContractJson.requireUnicodeScalars(value, path);
  if (_utf8StringByteLength(value) >
      kMaximumMeasurementBundledTargetProfileBundleAssetPathUtf8Bytes) {
    throw FormatException(
      'Expected "$path" to stay within the classic-ZIP filename bound.',
    );
  }
  final segments = value.split('/');
  if (segments.any(
    (segment) => segment.isEmpty || segment == '.' || segment == '..',
  )) {
    throw FormatException('Expected "$path" to be a normalized asset path.');
  }
}

int _canonicalJsonStringContentUtf8ByteLength(String value) {
  var byteLength = 0;
  for (var index = 0; index < value.length; index += 1) {
    final unit = value.codeUnitAt(index);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      byteLength += 4;
      index += 1;
      continue;
    }
    final escaped = unit == 0x22 ||
        unit == 0x5c ||
        unit == 0x08 ||
        unit == 0x09 ||
        unit == 0x0a ||
        unit == 0x0c ||
        unit == 0x0d;
    byteLength += escaped
        ? 2
        : switch (unit) {
            <= 0x1f => 6,
            <= 0x7f => 1,
            <= 0x7ff => 2,
            _ => 3,
          };
  }
  return byteLength;
}

int _utf8StringByteLength(String value) {
  var byteLength = 0;
  for (var index = 0; index < value.length; index += 1) {
    final unit = value.codeUnitAt(index);
    if (unit <= 0x7f) {
      byteLength += 1;
    } else if (unit <= 0x7ff) {
      byteLength += 2;
    } else if (unit >= 0xd800 && unit <= 0xdbff) {
      byteLength += 4;
      index += 1;
    } else {
      byteLength += 3;
    }
  }
  return byteLength;
}
