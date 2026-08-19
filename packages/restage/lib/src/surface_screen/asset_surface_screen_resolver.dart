import 'dart:convert';
import 'dart:typed_data';

import 'package:restage_shared/restage_shared.dart';

import '../flow/flow_descriptors.dart';
import 'surface_screen_bundle_provider.dart';
import 'surface_screen_runtime_provenance.dart';
import 'surface_screen_types.dart';

/// Resolves a screen from the source bundle packaged with the application.
///
/// A bundled screen is only ever the fallback for hosted delivery, so every
/// failure here is a fail-closed refusal rather than a degraded result. An
/// application with no packaged bundles installs no provider and gets that
/// refusal on every attempt, which is the intended hosted-only behavior.
final class AssetSurfaceScreenResolver implements BundledSurfaceScreenResolver {
  /// Creates the bundled-screen resolver.
  ///
  /// Bundles are read from the application's assets by default. An
  /// application that packages none still fails closed: the bundle its
  /// provenance names simply is not there.
  const AssetSurfaceScreenResolver({
    this.bundleProvider = const AssetSurfaceScreenBundleProvider(),
  });

  /// Loads the packaged bundle a screen's provenance names.
  final SurfaceScreenBundleProvider? bundleProvider;

  @override
  Future<ResolvedSurfaceScreen> resolve<E>(SurfaceScreenRef<E> screen) async {
    final provenance = screen.provenance;
    final locator = provenance.bundle;
    final provider = bundleProvider;
    if (locator == null || provider == null) {
      throw const SurfaceScreenUnavailableError(
        reason: SurfaceScreenUnavailableReason.missing,
        message: 'No packaged bundle is available for this screen.',
      );
    }

    final bundle = await provider.load(locator);
    _requireDeclaredBy(bundle, locator);
    final blob = _requireEntry(bundle, locator.screenBlob);
    final sidecarBytes = _requireEntry(bundle, locator.capabilitySidecar);
    _requireCapabilitiesAgree(
      _decodeSidecar(sidecarBytes),
      blobSha256: locator.screenBlob.sha256,
      expected: provenance.capabilities,
    );

    return ResolvedSurfaceScreen.bundled(
      surface: provenance.surface,
      slug: provenance.slug,
      contractVersion: provenance.contractVersion,
      sourceKind: SurfaceScreenRuntimeProvenance.sourceKind,
      payloadKind: SurfaceScreenRuntimeProvenance.payloadKind,
      capabilities: provenance.capabilities,
      contractFingerprint: provenance.contractFingerprint,
      eventContractHash: provenance.eventContractHash,
      blob: blob,
      contentHash: BlobSurfacePayload(
        minClient: provenance.capabilities.builtInFloor,
        blob: blob,
        requiredLibraries: provenance.capabilities.requiredLibraries,
      ).contentHash,
      bundledEntryHash: locator.screenBlob.sha256,
    );
  }

  void _requireDeclaredBy(
    RestageBundle bundle,
    SurfaceScreenBundleLocator locator,
  ) {
    if (bundle.packageName != locator.packageName ||
        bundle.authoredLibraryPath != locator.authoredLibraryPath) {
      throw const SurfaceScreenUnavailableError(
        reason: SurfaceScreenUnavailableReason.contractMismatch,
        message: 'The packaged bundle was built for a different library.',
      );
    }
  }

  /// Returns the bytes of [expected], which the bundle codec has already
  /// verified against the archive's own metadata and integrity data.
  Uint8List _requireEntry(
    RestageBundle bundle,
    SurfaceScreenBundleEntryReference expected,
  ) {
    for (final entry in bundle.entries) {
      if (entry.logicalPath != expected.logicalPath) continue;
      if (entry.role != expected.role ||
          entry.byteLength != expected.byteLength ||
          entry.sha256 != expected.sha256) {
        break;
      }
      return entry.bytes;
    }
    throw const SurfaceScreenUnavailableError(
      reason: SurfaceScreenUnavailableReason.contractMismatch,
      message: 'The packaged bundle does not carry the generated screen bytes.',
    );
  }

  void _requireCapabilitiesAgree(
    CapabilitySidecar sidecar, {
    required String blobSha256,
    required CapabilityManifest expected,
  }) {
    if (sidecar.blobSha256 != blobSha256 || sidecar.manifest != expected) {
      throw const SurfaceScreenUnavailableError(
        reason: SurfaceScreenUnavailableReason.contractMismatch,
        message:
            'The packaged capability data does not match the generated contract.',
      );
    }
  }

  CapabilitySidecar _decodeSidecar(List<int> bytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('A capability sidecar must be an object.');
      }
      return CapabilitySidecar.fromJson(decoded);
    } on Object catch (error) {
      throw SurfaceScreenUnavailableError(
        reason: SurfaceScreenUnavailableReason.invalidPayload,
        message: 'The packaged capability data is invalid.',
        cause: error,
      );
    }
  }
}
