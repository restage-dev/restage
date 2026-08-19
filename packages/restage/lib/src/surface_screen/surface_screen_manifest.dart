import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:restage_shared/restage_shared.dart';

import '../flow/flow_descriptors.dart';
import 'surface_screen_types.dart';

/// The fixed generated package manifest used as standalone-screen provenance.
const String kSurfaceScreenPublicationManifestAsset =
    'assets/restage/surface-publication-manifest.json';

/// A verified exact standalone-screen entry from the generated package manifest.
final class SurfaceScreenManifestEntry {
  const SurfaceScreenManifestEntry._({
    required this.surface,
    required this.slug,
    required this.contractVersion,
    required this.sourceKind,
    required this.payloadKind,
    required this.capabilities,
    required this.contractFingerprint,
    required this.eventContractHash,
    required this.eventSchema,
    required this.bundledBlob,
    required this.contentHash,
  });

  final Surface surface;
  final String slug;
  final int contractVersion;
  final SurfaceSourceKind sourceKind;
  final SurfacePayloadKind payloadKind;
  final CapabilityManifest capabilities;
  final String contractFingerprint;
  final String eventContractHash;
  final SurfaceScreenEventSchemaV1 eventSchema;
  final Uint8List bundledBlob;
  final String contentHash;
}

/// Loads and verifies generated standalone-screen publication entries.
///
/// This is intentionally package-internal rather than a caller-configurable
/// registry: the fixed generated manifest is the provenance authority for every
/// screen host and bundled resolver.
abstract final class SurfaceScreenManifestRegistry {
  static final Map<String, Future<SurfaceScreenManifestEntry>> _cache =
      <String, Future<SurfaceScreenManifestEntry>>{};
  static AssetBundle? _debugBundle;

  /// Resolves the exact generated entry for [screen].
  static Future<SurfaceScreenManifestEntry> resolve<E>(
    SurfaceScreenRef<E> screen,
  ) async {
    final key =
        '${screen.surface.wireName}\u0000${screen.slug}\u0000${screen.contractVersion}';
    final entry = await _cache.putIfAbsent(key, () => _load(screen));
    _validateReference(screen, entry);
    return entry;
  }

  @visibleForTesting
  static set debugAssetBundle(AssetBundle? bundle) {
    _debugBundle = bundle;
    _cache.clear();
  }

  @visibleForTesting
  static void debugReset() {
    _debugBundle = null;
    _cache.clear();
  }

  static Future<SurfaceScreenManifestEntry> _load<E>(
    SurfaceScreenRef<E> screen,
  ) async {
    final bundle = _debugBundle ?? rootBundle;
    final SurfacePublicationManifestV1 manifest;
    try {
      manifest = SurfacePublicationManifestV1Codec.decodeJson(
        await bundle.loadString(kSurfaceScreenPublicationManifestAsset),
      );
    } on Object catch (error) {
      throw SurfaceScreenUnavailableError(
        reason: SurfaceScreenUnavailableReason.missing,
        message: 'The generated screen manifest is unavailable.',
        cause: error,
      );
    }

    final candidates = manifest.publications.where(
      (entry) =>
          entry.publication.surface == screen.surface &&
          entry.publication.slug == screen.slug,
    );
    if (candidates.isEmpty) {
      throw const SurfaceScreenUnavailableError(
        reason: SurfaceScreenUnavailableReason.missing,
        message: 'No generated screen publication matches this reference.',
      );
    }
    final entry = candidates.single;
    final publication = entry.publication;
    final eventSchema = publication.eventContract;
    if (publication.sourceKind != SurfaceSourceKind.screen ||
        publication.payloadKind != SurfacePayloadKind.blob ||
        publication.contractVersion != screen.contractVersion ||
        publication.capabilities == null ||
        eventSchema == null ||
        publication.eventContractHash == null ||
        publication.contractFingerprint == null) {
      throw const SurfaceScreenUnavailableError(
        reason: SurfaceScreenUnavailableReason.contractMismatch,
        message:
            'The generated screen publication has an incompatible contract.',
      );
    }

    final eventHash = SurfaceScreenEventContractHashV1.hash(eventSchema);
    final fingerprint = SurfaceScreenContractFingerprintV1.hash(
      sourceKind: publication.sourceKind,
      payloadKind: publication.payloadKind,
      capabilities: publication.capabilities!,
      eventContractHash: eventHash,
    );
    if (publication.eventContractHash != eventHash ||
        publication.contractFingerprint != fingerprint) {
      throw const SurfaceScreenUnavailableError(
        reason: SurfaceScreenUnavailableReason.contractMismatch,
        message: 'The generated screen publication has an invalid contract.',
      );
    }

    final bytesByPath = <String, List<int>>{};
    try {
      for (final artifact in entry.artifacts) {
        final data = await bundle.load(artifact.path);
        bytesByPath[artifact.path] = Uint8List.fromList(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
      }
    } on Object catch (error) {
      throw SurfaceScreenUnavailableError(
        reason: SurfaceScreenUnavailableReason.missing,
        message: 'A generated screen artifact is unavailable.',
        cause: error,
      );
    }

    try {
      final closure = SurfacePublicationManifestV1(
        publications: <SurfacePublicationManifestEntryV1>[entry],
      ).validateArtifactClosure(bytesByPath).single;
      final blobArtifact = entry.artifacts.singleWhere(
        (artifact) =>
            artifact.role == SurfacePublicationArtifactRoleV1.screenBlob &&
            artifact.id == publication.slug,
      );
      final blob = Uint8List.fromList(bytesByPath[blobArtifact.path]!);
      final payload = BlobSurfacePayload(
        minClient: publication.capabilities!.builtInFloor,
        blob: blob,
        requiredLibraries: publication.capabilities!.requiredLibraries,
      );
      closure.validateAssembledPayload(payload.canonicalBytes);
      return SurfaceScreenManifestEntry._(
        surface: publication.surface,
        slug: publication.slug,
        contractVersion: publication.contractVersion!,
        sourceKind: publication.sourceKind,
        payloadKind: publication.payloadKind,
        capabilities: publication.capabilities!,
        contractFingerprint: publication.contractFingerprint!,
        eventContractHash: publication.eventContractHash!,
        eventSchema: eventSchema,
        bundledBlob: blob,
        contentHash: payload.contentHash,
      );
    } on SurfaceScreenUnavailableError {
      rethrow;
    } on Object catch (error) {
      throw SurfaceScreenUnavailableError(
        reason: SurfaceScreenUnavailableReason.invalidPayload,
        message: 'The generated screen artifact failed validation.',
        cause: error,
      );
    }
  }

  static void _validateReference<E>(
    SurfaceScreenRef<E> screen,
    SurfaceScreenManifestEntry entry,
  ) {
    if (screen.sourceKind != entry.sourceKind ||
        screen.payloadKind != entry.payloadKind ||
        screen.capabilities != entry.capabilities ||
        screen.eventContract.hash != entry.eventContractHash ||
        screen.contractFingerprint != entry.contractFingerprint) {
      throw const SurfaceScreenUnavailableError(
        reason: SurfaceScreenUnavailableReason.contractMismatch,
        message: 'The screen reference does not match its generated contract.',
      );
    }
  }
}
