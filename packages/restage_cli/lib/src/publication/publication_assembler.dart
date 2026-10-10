import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_shared/flow_experiment.dart' as flow;

import '../api/surface_publication_api.dart';
import '../commands/surface_payload.dart';
import '../measurement/measurement_publication_candidate_assembler.dart';
import 'publication_errors.dart';
import 'publication_bundle_reader.dart';
import 'publication_manifest.dart';
import 'publication_outputs.dart';

/// The exact payload and typed upload assembled from one generated manifest
/// entry.
final class AssembledSurfacePublication {
  /// Construct an assembled publication.
  AssembledSurfacePublication({
    required this.entry,
    required this.payload,
    required this.request,
    required Map<String, Uint8List> artifactBytes,
    required Map<String, File> selectedBundleFilesByAssetPath,
    this.measurementUpload,
    this.capabilityWarning,
  }) : artifactBytes = Map.unmodifiable({
         for (final item in artifactBytes.entries)
           item.key: Uint8List.fromList(item.value),
       }),
       _selectedBundleFilesByAssetPath = Map.unmodifiable(
         selectedBundleFilesByAssetPath,
       );

  /// The generated identity and declaration that were selected.
  final SurfacePublicationManifestEntry entry;

  /// The canonical assembled payload frame.
  final SurfacePayload payload;

  /// The only request submitted by the publication command.
  final SurfacePublicationUploadRequest request;

  /// Exact bytes read for the declaration paths in [entry].
  final Map<String, Uint8List> artifactBytes;

  /// Exact physical source-bundle closure that supplied [artifactBytes].
  List<File> get selectedBundleFiles =>
      List<File>.unmodifiable(_selectedBundleFilesByAssetPath.values);

  /// Exact output-index asset keys for [selectedBundleFiles].
  ///
  /// The command retains these keys rather than inferring placement from a
  /// source path or scanning the project filesystem after assembly.
  List<String> get selectedBundleAssetPaths =>
      List<String>.unmodifiable(_selectedBundleFilesByAssetPath.keys);

  /// Whether the complete selected closure is usable by bundled Measurement.
  ///
  /// A package that did not select `bundled_runtime` can still publish its
  /// hosted Measurement candidate; it has no target-profile asset to export.
  bool get hasBundledMeasurementSourceClosure =>
      _selectedBundleFilesByAssetPath.isNotEmpty &&
      _selectedBundleFilesByAssetPath.keys.every(
        isMeasurementBundledSourceOwnedBundleAssetPathV1,
      );

  /// Whether generated output incoherently mixes bundled and non-bundled
  /// source bundle placements for one Measurement closure.
  bool get hasMixedMeasurementSourceClosure {
    final paths = _selectedBundleFilesByAssetPath.keys;
    return paths.any(isMeasurementBundledSourceOwnedBundleAssetPathV1) &&
        paths.any(
          (path) => !isMeasurementBundledSourceOwnedBundleAssetPathV1(path),
        );
  }

  final Map<String, File> _selectedBundleFilesByAssetPath;

  /// Optional additive target-neutral Measurement upload.
  final MeasurementBoundSurfacePublicationUploadWire? measurementUpload;

  /// Optional capability note suitable for command output.
  final String? capabilityWarning;
}

/// Reads and assembles the exact artifact closure declared by a generated
/// publication manifest entry.
final class SurfacePublicationAssembler {
  /// Construct an assembler with an injected deterministic bundle reader.
  SurfacePublicationAssembler({PublicationBundleReader? bundleReader})
    : _bundleReader = bundleReader ?? PublicationBundleReaderProvider.current;

  final PublicationBundleReader _bundleReader;

  /// Assemble [entry] from the fixed project root in [loaded].
  Future<AssembledSurfacePublication> assemble({
    required LoadedSurfacePublicationManifest loaded,
    required SurfacePublicationManifestEntry entry,
  }) async {
    final root = await _assembleEntry(loaded: loaded, entry: entry);
    final available = <AssembledSurfacePublication>[root];
    final rootPayload = root.payload;
    if (rootPayload is FlowSurfacePayload) {
      for (final candidate in loaded.manifest.publications) {
        if ((candidate.publication.surface == entry.publication.surface &&
                candidate.publication.slug == entry.publication.slug) ||
            candidate.publication.surface != entry.publication.surface ||
            candidate.publication.payloadKind != SurfacePayloadKind.flow ||
            candidate.publication.deliveryMode !=
                rootPayload.flowDocument.deliveryMode)
          continue;
        available.add(await _assembleEntry(loaded: loaded, entry: candidate));
      }
    }
    List<AssembledSurfacePublication> selected = [root];
    if (rootPayload is FlowSurfacePayload) {
      final byIdentity =
          <(Surface, String, int), AssembledSurfacePublication>{};
      final documents = <flow.FlowExperimentDocumentContract>[];
      for (final assembled in available) {
        final payload = assembled.payload as FlowSurfacePayload;
        final document = payload.flowDocument;
        byIdentity[(
              assembled.entry.publication.surface,
              document.flow,
              document.version,
            )] =
            assembled;
        documents.add(
          flow.FlowExperimentDocumentContract(
            surfaceType: assembled.entry.publication.surface,
            flowId: document.flow,
            version: document.version,
            schemaVersion: document.schemaVersion,
            minClient: document.minClient,
            contentHash: FlowContentHash.compute(
              FlowDocumentCodec.encodeCanonicalJson(document),
            ),
            requiredLibraries: payload.requiredLibraries,
            flowDocument: document,
          ),
        );
      }
      try {
        selected =
            flow.FlowExperimentDocumentContract.selectCompleteClosure(
                  surfaceType: entry.publication.surface,
                  deliveryMode: rootPayload.flowDocument.deliveryMode,
                  descriptor: flow.FlowExperimentDescriptor(
                    id: rootPayload.flowDocument.flow,
                    version: rootPayload.flowDocument.version,
                    minClient: rootPayload.minClient,
                  ),
                  documents: documents,
                )
                .map(
                  (node) =>
                      byIdentity[(
                        node.surfaceType,
                        node.flowId,
                        node.version,
                      )]!,
                )
                .toList();
      } on FormatException catch (error) {
        throw PublicationAssemblyException(
          'The generated flow publication closure is incomplete: ${error.message}',
        );
      }
    }
    final bytes = <String, Uint8List>{};
    final bundleFiles = <String, File>{};
    for (final assembled in selected) {
      for (final item in assembled.artifactBytes.entries) {
        final previous = bytes[item.key];
        if (previous != null && !_sameBytes(previous, item.value)) {
          throw PublicationAssemblyException(
            'Conflicting generated artifact bytes for "${item.key}".',
          );
        }
        bytes[item.key] = item.value;
      }
      bundleFiles.addAll(assembled._selectedBundleFilesByAssetPath);
    }
    var request = SurfacePublicationUploadRequest(
      publication: entry.publication,
      payload: rootPayload.canonicalBytes,
      artifactManifest: SurfacePublicationManifest(
        publications: selected.map((value) => value.entry).toList(),
      ),
      artifactBytesByPath: bytes,
    );
    final measurementUpload = await MeasurementPublicationCandidateAssembler()
        .assemble(
          loaded: loaded,
          entry: entry,
          request: request,
          artifactBytes: root.artifactBytes,
        );
    if (measurementUpload != null) {
      request = SurfacePublicationUploadRequestV1Codec.decodeJson(
        utf8.decode(measurementUpload.publicationUploadCanonicalBytes),
      );
    }
    return AssembledSurfacePublication(
      entry: entry,
      payload: rootPayload,
      request: request,
      artifactBytes: bytes,
      selectedBundleFilesByAssetPath: bundleFiles,
      measurementUpload: measurementUpload,
      capabilityWarning: root.capabilityWarning,
    );
  }

  Future<AssembledSurfacePublication> _assembleEntry({
    required LoadedSurfacePublicationManifest loaded,
    required SurfacePublicationManifestEntry entry,
  }) async {
    final bytesByPath = <String, Uint8List>{};
    final bundleFilesByAssetPath = <String, File>{};
    for (final artifact in entry.artifacts) {
      final locator = loaded.outputIndex.locatorFor(artifact.path);
      final bundleFile = _resolveArtifactFile(
        loaded.projectRoot,
        locator.bundle,
      );
      bundleFilesByAssetPath.putIfAbsent(locator.bundle, () => bundleFile);
      final PublicationBundleEntry bundleEntry;
      try {
        bundleEntry = await _bundleReader.readEntry(
          bundleFile: bundleFile,
          entryPath: locator.entry,
        );
      } on PublicationBundleException catch (error) {
        throw PublicationAssemblyException(
          'Generated publication ${entry.publication.surface.wireName}/'
          '${entry.publication.slug} could not read bundle entry '
          '"${locator.entry}" from "${locator.bundle}": '
          '${error.message} Re-run `dart run build_runner build` and retry.',
        );
      } on FileSystemException {
        throw PublicationAssemblyException(
          'Generated publication ${entry.publication.surface.wireName}/'
          '${entry.publication.slug} could not read bundle '
          '"${locator.bundle}". Re-run `dart run build_runner build` and '
          'retry.',
        );
      }
      _validateBundleEntry(
        artifact: artifact,
        locator: locator,
        bundleEntry: bundleEntry,
        publication: entry.publication,
      );
      bytesByPath[artifact.path] = Uint8List.fromList(bundleEntry.bytes);
    }

    final selectedManifest = SurfacePublicationManifest(publications: [entry]);
    final closure = _validateDeclaredClosure(
      selectedManifest,
      bytesByPath,
      entry,
    ).single;

    try {
      final publication = entry.publication;
      final blobs = <String, Uint8List>{};
      final sidecars = <String, CapabilitySidecar>{};
      for (final artifact in entry.artifacts) {
        switch (artifact.role) {
          case SurfacePublicationArtifactRole.flowDocument:
          case SurfacePublicationArtifactRole.iconFont:
          case SurfacePublicationArtifactRole.localSeeds:
            break;
          case SurfacePublicationArtifactRole.screenBlob:
            final blob = bytesByPath[artifact.path]!;
            _validateBlob(blob);
            blobs[artifact.id!] = Uint8List.fromList(blob);
          case SurfacePublicationArtifactRole.capabilitySidecar:
            sidecars[artifact.id!] = _decodeSidecar(
              bytesByPath[artifact.path]!,
            );
        }
      }

      final SurfacePayload payload;
      late final CapabilityManifest capabilityManifest;
      switch (publication.payloadKind) {
        case SurfacePayloadKind.blob:
          final blob = blobs[publication.slug];
          final sidecar = sidecars[publication.slug];
          if (blob == null || sidecar == null) {
            throw const FormatException(
              'The generated blob closure is incomplete.',
            );
          }
          capabilityManifest = sidecar.manifest;
          payload = BlobSurfacePayload(
            minClient: sidecar.manifest.builtInFloor,
            blob: blob,
            requiredLibraries: sidecar.manifest.requiredLibraries,
            iconFonts: closure.iconFonts,
            localSeeds: closure.localSeeds,
          );
        case SurfacePayloadKind.flow:
          final flowArtifact = _findArtifact(
            entry,
            role: SurfacePublicationArtifactRole.flowDocument,
          );
          final flowDocument = _decodeFlowDocument(
            bytesByPath[flowArtifact.path]!,
          );
          final screenBlobs = <String, Uint8List>{};
          final perScreenLibraries = <List<LibraryRequirement>>[];
          for (final id in flowDocument.screenArtifacts.keys) {
            final blob = blobs[id];
            final sidecar = sidecars[id];
            if (blob == null || sidecar == null) {
              throw FormatException(
                'The generated flow closure is missing screen "$id".',
              );
            }
            screenBlobs[id] = blob;
            perScreenLibraries.add(sidecar.manifest.requiredLibraries);
          }
          final requiredLibraries = unionRequiredLibraries(perScreenLibraries);
          capabilityManifest = CapabilityManifest(
            builtInFloor: flowDocument.minClient,
            requiredLibraries: requiredLibraries,
          );
          payload = FlowSurfacePayload(
            flowDocument: flowDocument,
            screenBlobs: screenBlobs,
            requiredLibraries: requiredLibraries,
            iconFonts: closure.iconFonts,
            localSeeds: closure.localSeeds,
          );
      }

      final request = SurfacePublicationUploadRequest(
        publication: publication,
        payload: payload.canonicalBytes,
      );
      closure.validateAssembledPayload(payload.canonicalBytes);
      return AssembledSurfacePublication(
        entry: entry,
        payload: payload,
        request: request,
        artifactBytes: bytesByPath,
        selectedBundleFilesByAssetPath: bundleFilesByAssetPath,
        capabilityWarning: publishCapabilityWarning(capabilityManifest),
      );
    } on PublicationException {
      rethrow;
    } on FormatException catch (error) {
      throw PublicationAssemblyException(
        'Generated publication ${entry.publication.surface.wireName}/'
        '${entry.publication.slug} is invalid: ${error.message} Re-run '
        '`dart run build_runner build` and retry.',
      );
    } on ArgumentError {
      throw PublicationAssemblyException(
        'Generated publication ${entry.publication.surface.wireName}/'
        '${entry.publication.slug} could not be assembled. Re-run '
        '`dart run build_runner build` and retry.',
      );
    }
  }
}

List<SurfacePublicationArtifactClosure> _validateDeclaredClosure(
  SurfacePublicationManifest manifest,
  Map<String, List<int>> bytesByPath,
  SurfacePublicationManifestEntry entry,
) {
  try {
    return manifest.validateArtifactClosure(bytesByPath);
  } on FormatException catch (error) {
    throw PublicationAssemblyException(
      'Generated publication ${entry.publication.surface.wireName}/'
      '${entry.publication.slug} is stale or incomplete: '
      '${error.message} Re-run `dart run build_runner build` and retry.',
    );
  } on ArgumentError {
    throw PublicationAssemblyException(
      'Generated publication ${entry.publication.surface.wireName}/'
      '${entry.publication.slug} could not be verified. Re-run '
      '`dart run build_runner build` and retry.',
    );
  }
}

File _resolveArtifactFile(Directory projectRoot, String packagePath) {
  final rootPath = p.normalize(projectRoot.absolute.path);
  final artifactPath = p.normalize(p.join(rootPath, packagePath));
  final relative = p.relative(artifactPath, from: rootPath);
  if (relative == '..' || relative.startsWith('..${p.separator}')) {
    throw const PublicationAssemblyException(
      'A generated publication artifact escaped the project package root. '
      'Re-run `dart run build_runner build` and retry.',
    );
  }
  return File(artifactPath);
}

void _validateBundleEntry({
  required SurfacePublicationArtifact artifact,
  required RestageOutputIndexEntry locator,
  required PublicationBundleEntry bundleEntry,
  required SurfacePublication publication,
}) {
  if (bundleEntry.path != locator.entry || bundleEntry.path != artifact.path) {
    throw PublicationAssemblyException(
      'Generated publication ${publication.surface.wireName}/'
      '${publication.slug} has a bundle entry path mismatch for '
      '"${artifact.path}". Re-run `dart run build_runner build` and retry.',
    );
  }
  if (bundleEntry.role != artifact.role) {
    throw PublicationAssemblyException(
      'Generated publication ${publication.surface.wireName}/'
      '${publication.slug} has a bundle entry role mismatch for '
      '"${artifact.path}". Re-run `dart run build_runner build` and retry.',
    );
  }
  if (bundleEntry.size != bundleEntry.bytes.length) {
    throw PublicationAssemblyException(
      'Generated publication ${publication.surface.wireName}/'
      '${publication.slug} has a bundle entry size mismatch for '
      '"${artifact.path}". Re-run `dart run build_runner build` and retry.',
    );
  }
  final actualHash = CapabilitySidecar.hashBlob(bundleEntry.bytes);
  if (bundleEntry.sha256 != locator.sha256 ||
      bundleEntry.sha256 != artifact.contentHash ||
      actualHash != bundleEntry.sha256) {
    throw PublicationAssemblyException(
      'Generated publication ${publication.surface.wireName}/'
      '${publication.slug} has a bundle entry hash mismatch for '
      '"${artifact.path}". Re-run `dart run build_runner build` and retry.',
    );
  }
}

SurfacePublicationArtifact _findArtifact(
  SurfacePublicationManifestEntry entry, {
  required SurfacePublicationArtifactRole role,
}) {
  for (final artifact in entry.artifacts) {
    if (artifact.role == role) return artifact;
  }
  throw const FormatException(
    'The generated publication closure is missing an artifact.',
  );
}

CapabilitySidecar _decodeSidecar(Uint8List bytes) {
  try {
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Capability sidecar must be an object.');
    }
    return CapabilitySidecar.fromJson(value);
  } on Object {
    throw const FormatException('A generated capability sidecar is malformed.');
  }
}

FlowDocument _decodeFlowDocument(Uint8List bytes) {
  try {
    return FlowDocumentCodec.decodeJson(utf8.decode(bytes));
  } on Object {
    throw const FormatException('The generated flow document is malformed.');
  }
}

void _validateBlob(Uint8List blob) {
  try {
    validateRfwBlobForPublish(blob);
  } on Object {
    throw const FormatException(
      'A generated screen artifact is not a publishable render blob.',
    );
  }
}

bool _sameBytes(List<int> first, List<int> second) {
  if (first.length != second.length) return false;
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) return false;
  }
  return true;
}
