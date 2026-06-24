import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:restage_shared/restage_shared.dart';
import 'package:path/path.dart' as p;

/// A user-facing failure assembling a surface payload from on-disk codegen
/// output. The [message] is ready to print to stderr; the caller maps it to
/// exit code 1.
class SurfacePayloadException implements Exception {
  /// Construct with a ready-to-print [message].
  const SurfacePayloadException(this.message);

  /// Human-readable explanation + remediation.
  final String message;

  @override
  String toString() => message;
}

/// Read the flow document at [flowPath], resolve each referenced screen blob
/// from the sibling `screens/` directory (`<flow-dir>/../screens/<path>`),
/// and return the canonical surface payload bytes
/// ([FlowSurfacePayload.canonicalBytes]) — exactly the frame the backend
/// re-decodes at publish time.
///
/// Throws [SurfacePayloadException] (with a ready-to-print message) when the
/// flow is missing, unreadable, unparseable, or malformed; a screen blob is
/// missing or unreadable; or the on-disk blobs are stale relative to the flow
/// document.
Future<Uint8List> assembleSurfacePayloadBytes(String flowPath) async {
  final flowFile = File(flowPath);
  if (!flowFile.existsSync()) {
    throw SurfacePayloadException(
      'No flow found at $flowPath. Generate it with `dart run build_runner '
      'build` and retry, or override the location with --path <file>.',
    );
  }

  final String flowSource;
  try {
    flowSource = await flowFile.readAsString();
  } on FileSystemException catch (e) {
    throw SurfacePayloadException(
      'Could not read the flow at $flowPath: ${e.osError?.message ?? e.message}.',
    );
  }

  final FlowDocument flowDocument;
  try {
    flowDocument = FlowDocumentCodec.decodeJson(flowSource);
  } on FormatException catch (e) {
    throw SurfacePayloadException(
      'Could not parse the flow at $flowPath: ${e.message}. Re-run '
      '`dart run build_runner build`.',
    );
  }

  // Validate the decoded document BEFORE resolving any blob path. The format's
  // own path rules reject traversal (`..`) and absolute paths; running them
  // first means a malformed flow never drives a read outside the screens
  // directory, and the failure is reported as a malformed flow rather than
  // being mislabelled "stale blobs" downstream.
  try {
    FlowDocumentValidation.checkValid(flowDocument);
  } on ArgumentError {
    throw SurfacePayloadException(
      'The flow at $flowPath is malformed. Re-run `dart run build_runner '
      'build`.',
    );
  }

  final screensDir = p.normalize(p.join(p.dirname(flowPath), '..', 'screens'));
  final screenBlobs = <String, Uint8List>{};
  final perScreenRequired = <List<LibraryRequirement>>[];
  for (final entry in flowDocument.screenArtifacts.entries) {
    final blobPath = p.join(screensDir, entry.value.path);
    final blobFile = File(blobPath);
    if (!blobFile.existsSync()) {
      throw SurfacePayloadException(
        'Screen blob $blobPath is missing. Re-run `dart run build_runner '
        'build`.',
      );
    }
    final Uint8List blob;
    try {
      blob = await blobFile.readAsBytes();
    } on FileSystemException catch (e) {
      throw SurfacePayloadException(
        'Could not read screen blob $blobPath: '
        '${e.osError?.message ?? e.message}.',
      );
    }
    screenBlobs[entry.key] = blob;

    // Each screen carries its own capability sidecar next to the blob. Read it,
    // verify the blob hash (the same tie a paywall uses, so a stale sidecar
    // can't under-declare), and collect its required libraries — the flow's
    // envelope must require every custom library ANY of its screens needs, or a
    // custom-library flow would render fail-open on an under-capable client.
    final sidecar = await loadCapabilitySidecar(blobPath);
    if (CapabilitySidecar.hashBlob(blob) != sidecar.blobSha256) {
      throw SurfacePayloadException(
        'The capability manifest at ${capabilityManifestPath(blobPath)} is '
        'stale relative to the screen blob at $blobPath (content-hash '
        'mismatch). Re-run `dart run build_runner build`.',
      );
    }
    perScreenRequired.add(sidecar.manifest.requiredLibraries);
  }

  final FlowSurfacePayload payload;
  try {
    payload = FlowSurfacePayload(
      flowDocument: flowDocument,
      screenBlobs: screenBlobs,
      requiredLibraries: unionRequiredLibraries(perScreenRequired),
    );
  } on ArgumentError {
    // The factory validates each blob's SHA-256 against the hash recorded in
    // the flow document; a mismatch means the committed blobs drifted from
    // the flow. Surface a precise, non-leaky remediation rather than the raw
    // ArgumentError.
    throw const SurfacePayloadException(
      'The on-disk screen blobs are stale relative to the flow. Re-run '
      '`dart run build_runner build`.',
    );
  }

  return payload.canonicalBytes;
}

/// Read the single rendered-screen blob at [rfwPath] plus its sibling
/// capability manifest, and return the canonical surface payload bytes
/// ([BlobSurfacePayload.canonicalBytes]) — exactly the frame the backend
/// re-decodes at publish time — stamping the **derived** built-in floor and
/// required libraries the codegen recorded in the manifest.
///
/// Unlike [assembleSurfacePayloadBytes] (a flow document plus its per-screen
/// blobs), a paywall is a single compiled blob. The capability floor is no
/// longer a fixed publisher default — it is read from the
/// `<stem>.capability.json` the codegen emits next to the blob, which also
/// records the blob's content hash; the blob is re-hashed and a mismatch fails
/// closed (a stale sidecar cannot under-stamp a changed blob). Throws
/// [SurfacePayloadException] (with a ready-to-print message) when the blob or
/// its manifest is missing, unreadable, malformed, or stale.
Future<Uint8List> assembleBlobSurfacePayloadBytes(String rfwPath) async {
  final file = File(rfwPath);
  if (!file.existsSync()) {
    throw SurfacePayloadException(
      'No paywall blob found at $rfwPath. Export it (or run `dart run '
      'build_runner build`) and retry, or override the location with '
      '--path <file>.',
    );
  }

  final Uint8List blob;
  try {
    blob = await file.readAsBytes();
  } on FileSystemException catch (e) {
    throw SurfacePayloadException(
      'Could not read the paywall blob at $rfwPath: '
      '${e.osError?.message ?? e.message}.',
    );
  }

  final sidecar = await loadCapabilitySidecar(rfwPath);
  // Reject a sidecar that has drifted from the blob it was derived from: the
  // sidecar records the blob's content hash, so a stale sidecar (a partial
  // build, a hand-edit, a committed sidecar gone stale) that would otherwise
  // under-stamp a changed blob fails closed here rather than publishing a wrong
  // floor / missing required library.
  final actualHash = CapabilitySidecar.hashBlob(blob);
  if (actualHash != sidecar.blobSha256) {
    throw SurfacePayloadException(
      'The capability manifest at ${capabilityManifestPath(rfwPath)} is stale '
      'relative to the paywall blob at $rfwPath (content-hash mismatch). '
      'Re-run `dart run build_runner build` to regenerate both together.',
    );
  }
  return BlobSurfacePayload(
    minClient: sidecar.manifest.builtInFloor,
    blob: blob,
    requiredLibraries: sidecar.manifest.requiredLibraries,
  ).canonicalBytes;
}

/// The path of the capability-manifest sidecar emitted next to the compiled
/// blob at [rfwPath] — `<dir>/<stem>.capability.json`.
String capabilityManifestPath(String rfwPath) => p.join(
  p.dirname(rfwPath),
  '${p.basenameWithoutExtension(rfwPath)}.capability.json',
);

/// Unions the per-screen required-library lists of a flow into a single
/// canonical list: one entry per namespace carrying the **maximum** minVersion
/// any screen requires (the strictest floor wins), sorted by namespace. A flow
/// must declare every custom library any of its screens needs — declaring less
/// would let an under-capable client render it fail-open.
List<LibraryRequirement> unionRequiredLibraries(
  Iterable<List<LibraryRequirement>> perScreen,
) {
  final maxByNamespace = <String, int>{};
  for (final requirements in perScreen) {
    for (final requirement in requirements) {
      final existing = maxByNamespace[requirement.namespace];
      if (existing == null || requirement.minVersion > existing) {
        maxByNamespace[requirement.namespace] = requirement.minVersion;
      }
    }
  }
  return [
    for (final namespace in maxByNamespace.keys.toList()..sort())
      LibraryRequirement(
        namespace: namespace,
        minVersion: maxByNamespace[namespace]!,
      ),
  ];
}

/// A non-fatal, informational publish-time warning naming the capability a
/// surface requires — `null` when the surface needs only the baseline catalog
/// and no custom libraries (every client supports that, so there is nothing to
/// warn about).
///
/// Phrased in **catalog-version terms**: codegen knows the catalog content
/// version a surface requires, not which app *release* maps to it, so the
/// warning names the version (and any custom libraries), not an app version.
/// Clients built against an older catalog fall back rather than render it.
String? publishCapabilityWarning(CapabilityManifest manifest) {
  final needsAboveBaseline = manifest.builtInFloor > kBaselineCatalogVersion;
  if (!needsAboveBaseline && manifest.requiredLibraries.isEmpty) {
    return null;
  }
  final parts = <String>[
    if (needsAboveBaseline)
      'built-in catalog content version ${manifest.builtInFloor}',
    for (final requirement in manifest.requiredLibraries)
      'custom library "${requirement.namespace}" >= v${requirement.minVersion}',
  ];
  return 'Note: this surface requires ${parts.join(' and ')}. Clients built '
      'against an older catalog (or without those libraries) will fall back '
      'rather than render it.';
}

/// Read + decode the [CapabilityManifest] the codegen emitted next to the blob
/// at [rfwPath]. A convenience over [loadCapabilitySidecar] for callers that
/// only need the manifest (e.g. the publish-time warning) and not the
/// blob-pairing hash.
Future<CapabilityManifest> loadCapabilityManifest(String rfwPath) async =>
    (await loadCapabilitySidecar(rfwPath)).manifest;

/// Read + decode the [CapabilitySidecar] the codegen emitted next to the blob
/// at [rfwPath] — the derived manifest plus the content hash of the blob it was
/// derived from. Throws [SurfacePayloadException] (ready-to-print) when the
/// sidecar is missing, unreadable, or malformed — it is a required build
/// artifact, so its absence is a build-staleness error, not a default.
Future<CapabilitySidecar> loadCapabilitySidecar(String rfwPath) async {
  final path = capabilityManifestPath(rfwPath);
  final file = File(path);
  if (!file.existsSync()) {
    throw SurfacePayloadException(
      'No capability manifest found at $path. Re-run `dart run build_runner '
      'build` to regenerate it alongside the compiled blob.',
    );
  }

  final String source;
  try {
    source = await file.readAsString();
  } on FileSystemException catch (e) {
    throw SurfacePayloadException(
      'Could not read the capability manifest at $path: '
      '${e.osError?.message ?? e.message}.',
    );
  }

  try {
    return CapabilitySidecar.fromJson(
      jsonDecode(source) as Map<String, dynamic>,
    );
  } on FormatException catch (e) {
    throw SurfacePayloadException(
      'The capability manifest at $path is malformed: ${e.message}. Re-run '
      '`dart run build_runner build`.',
    );
  } on TypeError {
    throw SurfacePayloadException(
      'The capability manifest at $path is malformed. Re-run `dart run '
      'build_runner build`.',
    );
  }
}
