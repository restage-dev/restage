import 'dart:typed_data';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:restage_shared/restage_shared.dart';

import 'surface_screen_runtime_provenance.dart';
import 'surface_screen_types.dart';

/// Supplies the packaged source bundle a bundled screen falls back to.
///
/// An application that never packages bundles installs no provider, and every
/// bundled fallback then fails closed. Hosted delivery is unaffected either
/// way: nothing on this seam can relax a hosted identity or contract check.
abstract interface class SurfaceScreenBundleProvider {
  /// Loads the bundle addressed by [locator].
  ///
  /// Throws [SurfaceScreenUnavailableError] when the bundle is absent or is
  /// not a valid container.
  Future<RestageBundle> load(SurfaceScreenBundleLocator locator);
}

/// Reads packaged bundles from a Flutter asset bundle.
///
/// Container parsing belongs to the shared bundle codec, which enforces the
/// deterministic-container rules and verifies every entry against the
/// archive's own integrity data. This provider only supplies bytes to it.
final class AssetSurfaceScreenBundleProvider
    implements SurfaceScreenBundleProvider {
  /// Creates a provider reading from [assetBundle], or Flutter's root bundle.
  const AssetSurfaceScreenBundleProvider({this.assetBundle});

  /// The asset bundle to read, or Flutter's root bundle when omitted.
  final AssetBundle? assetBundle;

  @override
  Future<RestageBundle> load(SurfaceScreenBundleLocator locator) async {
    final Uint8List bytes;
    try {
      final data = await (assetBundle ?? rootBundle).load(locator.assetKey);
      bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } on Object catch (error) {
      throw SurfaceScreenUnavailableError(
        reason: SurfaceScreenUnavailableReason.missing,
        message: 'The packaged screen bundle is unavailable.',
        cause: error,
      );
    }

    try {
      return RestageBundleCodec.decode(bytes);
    } on Object catch (error) {
      throw SurfaceScreenUnavailableError(
        reason: SurfaceScreenUnavailableReason.invalidPayload,
        message: 'The packaged screen bundle is not a valid bundle.',
        cause: error,
      );
    }
  }
}
