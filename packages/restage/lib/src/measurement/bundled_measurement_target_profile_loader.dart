import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show AssetBundle, ByteData, rootBundle;
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';

import '../assets/bundled_asset_source.dart';
import 'bundled_measurement_publication_binding_read_port.dart';

/// Raised when the packaged Measurement target profile cannot be admitted.
final class BundledMeasurementTargetProfileLoadException implements Exception {
  /// Creates a fail-closed profile-load diagnostic.
  const BundledMeasurementTargetProfileLoadException(this.message);

  /// Safe failure detail.
  final String message;

  @override
  String toString() => 'BundledMeasurementTargetProfileLoadException: $message';
}

/// Verified bundled Measurement authority decoded from the profile asset.
///
/// The target is an output of profile validation. A host cannot supply a
/// different target value to influence bundled Measurement resolution.
final class BundledMeasurementTargetProfileLoadResult {
  /// Creates one fully verified bundled Measurement authority.
  const BundledMeasurementTargetProfileLoadResult({
    required this.target,
    required this.bindingReadPort,
  });

  /// Exact target selected by the packaged target profile.
  final TargetCoordinate target;

  /// Exact-only read port over the verified profile closure.
  final BundledMeasurementPublicationBindingReadPort bindingReadPort;
}

/// Loads the exact packaged Measurement target profile for offline reads.
///
/// This loader performs no network I/O, asset discovery, active/current
/// selection, or fallback read. It bypasses [BundledAssetSource] so the
/// separate profile asset can never be supplied by a source-owned `.rsbundle`.
abstract final class BundledMeasurementTargetProfileLoader {
  /// Validates the selected target profile and constructs its exact read port.
  static Future<BundledMeasurementTargetProfileLoadResult> load({
    AssetBundle? assetBundle,
  }) async {
    final bundle = _directBundle(assetBundle ?? rootBundle);
    final profileBytes = await _loadExact(
      bundle,
      kMeasurementBundledTargetProfileAssetPath,
      maximumBytes: kMaximumMeasurementBundledTargetProfileAssetBytes,
    );
    final profile = _decodeProfile(profileBytes);
    final profileTarget = _decodeTarget(profile.targetCanonicalBytes);

    final registry = _decodeRegistry(profile.registryCanonicalBytes);
    if (!_sameBytes(
        profileTarget.canonicalBytes, registry.target.canonicalBytes)) {
      throw const BundledMeasurementTargetProfileLoadException(
        'The Measurement registry does not match the target profile.',
      );
    }

    final verifiedBundles = await _validateSelectedBundles(bundle, profile);
    try {
      return BundledMeasurementTargetProfileLoadResult(
        target: profileTarget,
        bindingReadPort: BundledMeasurementPublicationBindingReadPort(
          target: profileTarget,
          registry: registry,
          verifiedBundles: verifiedBundles,
        ),
      );
    } on Object {
      throw const BundledMeasurementTargetProfileLoadException(
        'The Measurement target profile has an invalid verified bundle closure.',
      );
    }
  }

  static AssetBundle _directBundle(AssetBundle bundle) {
    var direct = bundle;
    while (direct is BundledAssetSource) {
      direct = direct.delegate;
    }
    return direct;
  }

  static Future<Uint8List> _loadExact(
    AssetBundle bundle,
    String path, {
    required int maximumBytes,
  }) async {
    try {
      final ByteData data = await bundle.load(path);
      return await enforceBundledMeasurementAssetByteLimitBeforeCopy(
        byteLength: data.lengthInBytes,
        maximumBytes: maximumBytes,
        path: path,
        copy: () => Uint8List.fromList(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        ),
      );
    } on BundledMeasurementTargetProfileLoadException {
      rethrow;
    } on Object {
      throw BundledMeasurementTargetProfileLoadException(
        'Could not load the exact Measurement asset "$path".',
      );
    }
  }

  static MeasurementBundledTargetProfileV1 _decodeProfile(List<int> bytes) {
    try {
      return MeasurementBundledTargetProfileV1.fromCanonicalBytes(bytes);
    } on Object {
      throw const BundledMeasurementTargetProfileLoadException(
        'The Measurement target profile is malformed or noncanonical.',
      );
    }
  }

  static TargetCoordinate _decodeTarget(List<int> bytes) {
    try {
      return TargetCoordinate.fromCanonicalBytes(bytes);
    } on Object {
      throw const BundledMeasurementTargetProfileLoadException(
        'The Measurement target profile has invalid target bytes.',
      );
    }
  }

  static MeasurementPublicationBundledRegistryV1 _decodeRegistry(
    List<int> bytes,
  ) {
    try {
      return MeasurementPublicationBundledRegistryV1.fromCanonicalBytes(bytes);
    } on Object {
      throw const BundledMeasurementTargetProfileLoadException(
        'The Measurement target profile has invalid registry bytes.',
      );
    }
  }

  static Future<List<RestageBundle>> _validateSelectedBundles(
    AssetBundle bundle,
    MeasurementBundledTargetProfileV1 profile,
  ) async {
    final verified = <RestageBundle>[];
    for (final selectedBundle in profile.bundles) {
      final bytes = await _loadExact(
        bundle,
        selectedBundle.assetPath,
        maximumBytes: kRestageBundleMaxClassicZipValue,
      );
      if (_sha256(bytes) != selectedBundle.sha256) {
        throw BundledMeasurementTargetProfileLoadException(
          'The selected bundle "${selectedBundle.assetPath}" does not match '
          'the Measurement target profile.',
        );
      }
      try {
        verified.add(RestageBundleCodec.decode(bytes));
      } on Object {
        throw BundledMeasurementTargetProfileLoadException(
          'The selected bundle "${selectedBundle.assetPath}" is malformed.',
        );
      }
    }
    return List<RestageBundle>.unmodifiable(verified);
  }
}

/// Applies the exact asset byte limit before invoking [copy].
///
/// The loader passes `ByteData.lengthInBytes` and the closure that copies the
/// ByteData view. Keeping the guard outside the closure makes the pre-copy
/// admission mechanically testable without allocating an oversized buffer.
@visibleForTesting
T enforceBundledMeasurementAssetByteLimitBeforeCopy<T>({
  required int byteLength,
  required int maximumBytes,
  required String path,
  required T Function() copy,
}) {
  if (byteLength > maximumBytes) {
    throw BundledMeasurementTargetProfileLoadException(
      'Could not load the exact Measurement asset "$path".',
    );
  }
  return copy();
}

String _sha256(List<int> bytes) => 'sha256:${crypto.sha256.convert(bytes)}';

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
