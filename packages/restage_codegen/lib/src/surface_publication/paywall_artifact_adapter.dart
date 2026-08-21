// Aggregate-callable paywall artifact facts.
// ignore_for_file: public_member_api_docs

import 'dart:convert';
import 'dart:typed_data';

import 'package:build/build.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:restage_codegen/src/source_visitor.dart';
import 'package:restage_shared/restage_shared.dart';

const String _kPaywallOutputDir = 'assets/paywalls';
const String _kPaywallScreenOutputDir = kPaywallScreensAssetDir;

/// One exact generated file, including the hash and manifest role an
/// aggregate publisher needs. The adapter is the owner of this association;
/// consumers must not derive a sidecar path from [path].
@immutable
final class PaywallArtifactFile {
  PaywallArtifactFile({
    required this.path,
    required List<int> bytes,
    required SurfacePublicationArtifactRole role,
    String? id,
  })  : bytes = Uint8List.fromList(bytes),
        artifact = SurfacePublicationArtifact(
          contentHash: CapabilitySidecar.hashBlob(bytes),
          path: path,
          role: role,
          id: id,
        );

  final String path;
  final Uint8List bytes;
  final SurfacePublicationArtifact artifact;

  String get contentHash => artifact.contentHash;
}

/// A paywall screen blob paired with the exact sidecar that was derived from
/// that blob.
@immutable
final class PaywallScreenArtifactFacts {
  factory PaywallScreenArtifactFacts({
    required String id,
    required String blobPath,
    required List<int> blobBytes,
    required String capabilityPath,
    required List<int> capabilityBytes,
    int? expectedMinClient,
  }) {
    _requireIdentity(id, 'screen artifact id');
    final sidecar = _decodeSidecar(capabilityBytes, capabilityPath);
    final blobHash = CapabilitySidecar.hashBlob(blobBytes);
    if (sidecar.blobSha256 != blobHash) {
      throw FormatException(
        'Capability sidecar "$capabilityPath" does not match blob '
        '"$blobPath".',
      );
    }
    if (expectedMinClient != null &&
        sidecar.manifest.builtInFloor != expectedMinClient) {
      throw FormatException(
        'Capability sidecar "$capabilityPath" declares built-in floor '
        '${sidecar.manifest.builtInFloor}, expected $expectedMinClient.',
      );
    }
    return PaywallScreenArtifactFacts._(
      id: id,
      blob: PaywallArtifactFile(
        path: blobPath,
        bytes: blobBytes,
        role: SurfacePublicationArtifactRole.screenBlob,
        id: id,
      ),
      capabilitySidecar: PaywallArtifactFile(
        path: capabilityPath,
        bytes: capabilityBytes,
        role: SurfacePublicationArtifactRole.capabilitySidecar,
        id: id,
      ),
      sidecar: sidecar,
    );
  }

  const PaywallScreenArtifactFacts._({
    required this.id,
    required this.blob,
    required this.capabilitySidecar,
    required this.sidecar,
  });

  final String id;
  final PaywallArtifactFile blob;
  final PaywallArtifactFile capabilitySidecar;
  final CapabilitySidecar sidecar;

  List<SurfacePublicationArtifact> get artifacts => [
        blob.artifact,
        capabilitySidecar.artifact,
      ];
}

/// The complete generated artifact closure for one canonical or legacy
/// paywall source.
///
/// [standalone] is the specialized paywall payload. [flowDocument] and
/// [flowScreens] are the navigation-flow payload and its complete adapter
/// screen closure. A navigation paywall may intentionally omit [standalone]
/// when the translator suppressed the standalone form; the adapter screen is
/// still required and is always represented by [flowScreens].
@immutable
final class PaywallArtifactFacts {
  PaywallArtifactFacts._({
    required this.slug,
    required this.adapter,
    required this.standalone,
    required this.flowDocument,
    required this.navigationFlow,
    required Map<String, PaywallScreenArtifactFacts> flowScreens,
  }) : flowScreens = Map.unmodifiable(flowScreens);

  final String slug;
  final PaywallScreenArtifactFacts adapter;
  final PaywallScreenArtifactFacts? standalone;
  final PaywallArtifactFile? flowDocument;
  final FlowDocument? navigationFlow;
  final Map<String, PaywallScreenArtifactFacts> flowScreens;

  /// The standalone publication identity owned by the specialized source.
  Surface get surface => Surface.paywall;

  /// Paywalls remain a specialized source kind even when their adapter is
  /// embedded in a flow of another surface category.
  SurfaceSourceKind get sourceKind => SurfaceSourceKind.paywall;

  /// Whether this source has a complete generated navigation-flow payload.
  bool get hasFlow => navigationFlow != null;

  /// Whether this paywall emitted only its adapter, with no own publication
  /// payload.
  ///
  /// A pushed paywall that lowers `Navigator.pop(context)` has no standalone
  /// payload and does not own its own navigation document. The aggregate must
  /// prove the adapter appears in a different generated flow closure before it
  /// may treat this source as embedded.
  bool get isEmbeddedOnly => standalone == null && navigationFlow == null;

  /// Exact manifest facts for the standalone specialized paywall payload.
  /// Returns an empty list when the translator deliberately suppressed that
  /// payload for a flow-only navigation source.
  List<SurfacePublicationArtifact> get standaloneArtifacts =>
      standalone == null ? const [] : standalone!.artifacts;

  /// Exact manifest facts for the navigation-flow payload, including every
  /// adapter screen and its matching sidecar.
  List<SurfacePublicationArtifact> get flowArtifacts {
    final document = flowDocument;
    if (document == null) return const [];
    final entries = <SurfacePublicationArtifact>[document.artifact];
    final ordered = flowScreens.values.toList()
      ..sort((left, right) => left.id.compareTo(right.id));
    for (final screen in ordered) {
      entries.addAll(screen.artifacts);
    }
    return List.unmodifiable(entries);
  }

  /// Exact bytes keyed by the exact package-relative artifact paths.
  Map<String, Uint8List> get filesByPath {
    final files = <String, Uint8List>{};
    void add(PaywallArtifactFile file) {
      final previous = files[file.path];
      if (previous != null && !_bytesEqual(previous, file.bytes)) {
        throw FormatException(
          'Generated paywall artifact path "${file.path}" has two '
          'different byte values.',
        );
      }
      files[file.path] = Uint8List.fromList(file.bytes);
    }

    if (standalone != null) {
      add(standalone!.blob);
      add(standalone!.capabilitySidecar);
    }
    add(adapter.blob);
    add(adapter.capabilitySidecar);
    if (flowDocument != null) add(flowDocument!);
    for (final screen in flowScreens.values) {
      add(screen.blob);
      add(screen.capabilitySidecar);
    }
    return Map.unmodifiable(files);
  }
}

/// Reads and validates the generated paywall files owned by one source.
///
/// This is the aggregate seam: it returns every path, exact byte hash, flow
/// document, adapter blob, and matching capability sidecar needed to assemble
/// a publication manifest. It never asks a caller to infer a sibling path.
abstract final class PaywallArtifactAdapter {
  /// Reads the generated family for a normalized visitor finding. The
  /// adapter owns the mapping from the source asset's physical stem to the
  /// generated paths; callers supply the authoritative normalized id rather
  /// than reconstructing either identity or sibling paths themselves.
  static Future<PaywallArtifactFacts> readForSource(
    BuildStep buildStep,
    PaywallSourceFound source,
  ) {
    return read(
      buildStep,
      slug: source.id,
      artifactStem: p.basenameWithoutExtension(source.assetId.path),
    );
  }

  /// Reads the conventional per-source generated outputs from [buildStep].
  /// [artifactStem] is the physical output owner (normally the Dart filename
  /// stem); [slug] is the authoritative source identity and may differ from
  /// that stem for a canonical explicit-id declaration.
  static Future<PaywallArtifactFacts> read(
    BuildStep buildStep, {
    required String slug,
    required String artifactStem,
  }) async {
    final standaloneBlobPath = '$_kPaywallOutputDir/$artifactStem.rfw';
    final standaloneCapabilityPath =
        '$_kPaywallOutputDir/$artifactStem.capability.json';
    final adapterBlobPath =
        '$_kPaywallScreenOutputDir/paywall_$artifactStem.rfw';
    final adapterCapabilityPath =
        '$_kPaywallScreenOutputDir/paywall_$artifactStem.capability.json';
    final flowDocumentPath = '$_kPaywallOutputDir/$artifactStem.flow.json';

    final files = <String, List<int>>{};
    await _readOptionalPair(
      buildStep,
      standaloneBlobPath,
      standaloneCapabilityPath,
      files,
    );
    await _readRequiredPair(
      buildStep,
      adapterBlobPath,
      adapterCapabilityPath,
      files,
    );
    if (await buildStep.canRead(
      AssetId(buildStep.inputId.package, flowDocumentPath),
    )) {
      files[flowDocumentPath] = await buildStep.readAsBytes(
        AssetId(buildStep.inputId.package, flowDocumentPath),
      );
    }

    final flowDocument = _decodeOptionalFlowDocument(
      files[flowDocumentPath],
      flowDocumentPath,
    );
    if (flowDocument != null) {
      for (final artifact in flowDocument.screenArtifacts.entries) {
        final blobPath = _flowScreenAssetPath(artifact.value.path);
        final capabilityPath = _capabilityPath(blobPath);
        await _readRequiredPair(
          buildStep,
          blobPath,
          capabilityPath,
          files,
        );
      }
    }

    return fromFiles(
      slug: slug,
      standaloneBlobPath: standaloneBlobPath,
      standaloneCapabilityPath: standaloneCapabilityPath,
      adapterBlobPath: adapterBlobPath,
      adapterCapabilityPath: adapterCapabilityPath,
      flowDocumentPath: flowDocumentPath,
      files: files,
    );
  }

  /// Validates an already-read generated file family. This pure form is used
  /// by package aggregate owners that read assets in a separate discovery
  /// pass, and by tests that need to prove stale/partial closure rejection.
  static PaywallArtifactFacts fromFiles({
    required String slug,
    required String standaloneBlobPath,
    required String standaloneCapabilityPath,
    required String adapterBlobPath,
    required String adapterCapabilityPath,
    required String flowDocumentPath,
    required Map<String, List<int>> files,
  }) {
    _requireIdentity(slug, 'paywall slug');
    final standalone = _optionalScreen(
      slug: slug,
      blobPath: standaloneBlobPath,
      capabilityPath: standaloneCapabilityPath,
      files: files,
    );
    final adapter = _requiredScreen(
      id: '$kPaywallScreenIdPrefix$slug',
      blobPath: adapterBlobPath,
      capabilityPath: adapterCapabilityPath,
      files: files,
    );

    final flowBytes = files[flowDocumentPath];
    final flowDocument =
        _decodeOptionalFlowDocument(flowBytes, flowDocumentPath);
    final flowFile = flowDocument == null
        ? null
        : PaywallArtifactFile(
            path: flowDocumentPath,
            bytes: flowBytes!,
            role: SurfacePublicationArtifactRole.flowDocument,
          );

    final flowScreens = <String, PaywallScreenArtifactFacts>{};
    if (flowDocument != null) {
      if (flowDocument.flow != slug) {
        throw FormatException(
          'Paywall flow artifact "$flowDocumentPath" has flow identity '
          '"${flowDocument.flow}", expected "$slug".',
        );
      }
      FlowDocumentValidation.checkValid(flowDocument);
      for (final entry in flowDocument.screenArtifacts.entries) {
        final screenId = entry.key;
        final blobPath = _flowScreenAssetPath(entry.value.path);
        final capabilityPath = _capabilityPath(blobPath);
        flowScreens[screenId] = _requiredScreen(
          id: screenId,
          blobPath: blobPath,
          capabilityPath: capabilityPath,
          files: files,
          expectedMinClient: entry.value.minClient,
          expectedContentHash: entry.value.contentHash.value,
        );
      }
      final entryScreen = flowScreens[adapter.id];
      if (entryScreen == null) {
        throw FormatException(
          'Paywall flow artifact "$flowDocumentPath" does not contain '
          'the generated adapter screen "${adapter.id}".',
        );
      }
      if (entryScreen.blob.contentHash != adapter.blob.contentHash ||
          entryScreen.capabilitySidecar.contentHash !=
              adapter.capabilitySidecar.contentHash) {
        throw FormatException(
          'Paywall adapter artifacts do not match the flow screen closure '
          'for "${adapter.id}".',
        );
      }
    }

    return PaywallArtifactFacts._(
      slug: slug,
      adapter: adapter,
      standalone: standalone,
      flowDocument: flowFile,
      navigationFlow: flowDocument,
      flowScreens: flowScreens,
    );
  }
}

Future<void> _readRequiredPair(
  BuildStep buildStep,
  String blobPath,
  String capabilityPath,
  Map<String, List<int>> files,
) async {
  final blobId = AssetId(buildStep.inputId.package, blobPath);
  final capabilityId = AssetId(buildStep.inputId.package, capabilityPath);
  final hasBlob = await buildStep.canRead(blobId);
  final hasCapability = await buildStep.canRead(capabilityId);
  if (!hasBlob || !hasCapability) {
    throw FormatException(
      'Paywall artifact family is incomplete: expected both "$blobPath" '
      'and "$capabilityPath".',
    );
  }
  files[blobPath] = await buildStep.readAsBytes(blobId);
  files[capabilityPath] = await buildStep.readAsBytes(capabilityId);
}

Future<void> _readOptionalPair(
  BuildStep buildStep,
  String blobPath,
  String capabilityPath,
  Map<String, List<int>> files,
) async {
  final blobId = AssetId(buildStep.inputId.package, blobPath);
  final capabilityId = AssetId(buildStep.inputId.package, capabilityPath);
  final hasBlob = await buildStep.canRead(blobId);
  final hasCapability = await buildStep.canRead(capabilityId);
  if (hasBlob != hasCapability) {
    throw FormatException(
      'Paywall artifact family is partial: expected both "$blobPath" '
      'and "$capabilityPath", or neither.',
    );
  }
  if (!hasBlob) return;
  files[blobPath] = await buildStep.readAsBytes(blobId);
  files[capabilityPath] = await buildStep.readAsBytes(capabilityId);
}

PaywallScreenArtifactFacts? _optionalScreen({
  required String slug,
  required String blobPath,
  required String capabilityPath,
  required Map<String, List<int>> files,
}) {
  final blob = files[blobPath];
  final capability = files[capabilityPath];
  if (blob == null && capability == null) return null;
  if (blob == null || capability == null) {
    throw FormatException(
      'Paywall artifact family is partial: expected both "$blobPath" '
      'and "$capabilityPath", or neither.',
    );
  }
  return PaywallScreenArtifactFacts(
    id: slug,
    blobPath: blobPath,
    blobBytes: blob,
    capabilityPath: capabilityPath,
    capabilityBytes: capability,
  );
}

PaywallScreenArtifactFacts _requiredScreen({
  required String id,
  required String blobPath,
  required String capabilityPath,
  required Map<String, List<int>> files,
  int? expectedMinClient,
  String? expectedContentHash,
}) {
  final blob = files[blobPath];
  final capability = files[capabilityPath];
  if (blob == null || capability == null) {
    throw FormatException(
      'Paywall artifact family is incomplete: expected both "$blobPath" '
      'and "$capabilityPath".',
    );
  }
  final facts = PaywallScreenArtifactFacts(
    id: id,
    blobPath: blobPath,
    blobBytes: blob,
    capabilityPath: capabilityPath,
    capabilityBytes: capability,
    expectedMinClient: expectedMinClient,
  );
  if (expectedContentHash != null &&
      facts.blob.contentHash != expectedContentHash) {
    throw FormatException(
      'Flow screen artifact "$id" hash does not match its generated blob '
      '"$blobPath".',
    );
  }
  return facts;
}

CapabilitySidecar _decodeSidecar(List<int> bytes, String path) {
  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } on Object catch (error) {
    throw FormatException(
      'Could not decode capability sidecar "$path": $error',
    );
  }
  if (decoded is! Map) {
    throw FormatException('Capability sidecar "$path" must be a JSON object.');
  }
  final json = Map<String, dynamic>.from(decoded);
  if (!setEquals(json.keys.toSet(), const {'blobSha256', 'manifest'})) {
    throw FormatException(
      'Capability sidecar "$path" has an unexpected field set.',
    );
  }
  final manifest = json['manifest'];
  if (manifest is! Map ||
      !setEquals(
        manifest.keys.toSet(),
        const {'builtInFloor', 'requiredLibraries'},
      )) {
    throw FormatException(
      'Capability sidecar "$path" has an invalid manifest field set.',
    );
  }
  final requirements = manifest['requiredLibraries'];
  if (requirements is! List) {
    throw FormatException(
      'Capability sidecar "$path" must list required libraries.',
    );
  }
  for (final requirement in requirements) {
    final validKeys = requirement is Map &&
        setEquals(
          requirement.keys.toSet(),
          const {'namespace', 'minVersion'},
        );
    if (!validKeys) {
      throw FormatException(
        'Capability sidecar "$path" has an invalid library requirement.',
      );
    }
  }
  try {
    return CapabilitySidecar.fromJson(json);
  } on Object catch (error) {
    throw FormatException('Invalid capability sidecar "$path": $error');
  }
}

FlowDocument? _decodeOptionalFlowDocument(
  List<int>? bytes,
  String path,
) {
  if (bytes == null) return null;
  try {
    return FlowDocumentCodec.decodeJson(utf8.decode(bytes));
  } on Object catch (error) {
    throw FormatException('Invalid paywall flow artifact "$path": $error');
  }
}

String _flowScreenAssetPath(String documentPath) {
  if (documentPath.contains('/') || !documentPath.endsWith('.rfw')) {
    throw FormatException(
      'Paywall flow screen path "$documentPath" is not a flat .rfw path.',
    );
  }
  return '$_kPaywallScreenOutputDir/$documentPath';
}

String _capabilityPath(String blobPath) {
  if (!blobPath.endsWith('.rfw')) {
    throw FormatException('Paywall blob path "$blobPath" is not an .rfw file.');
  }
  return '${p.withoutExtension(blobPath)}.capability.json';
}

void _requireIdentity(String value, String label) {
  if (value.isEmpty || value.trim() != value || value.contains('\u0000')) {
    throw FormatException('$label must be a non-empty trimmed identity.');
  }
}

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

bool setEquals<T>(Set<T> left, Set<T> right) =>
    left.length == right.length && left.containsAll(right);
