import 'package:meta/meta.dart';
import 'package:restage_shared/restage_shared.dart';

import 'surface_screen_types.dart';

/// One hash-bound bundle entry a screen runtime expects to find.
@immutable
final class SurfaceScreenBundleEntryReference {
  /// Creates a reference to one exact bundle entry.
  SurfaceScreenBundleEntryReference({
    required this.logicalPath,
    required this.role,
    required this.byteLength,
    required this.sha256,
  }) {
    if (logicalPath.isEmpty ||
        logicalPath.startsWith('/') ||
        logicalPath.contains('\\') ||
        logicalPath.split('/').any(
              (segment) => segment.isEmpty || segment == '.' || segment == '..',
            )) {
      throw ArgumentError.value(
        logicalPath,
        'logicalPath',
        'must be a normalized relative bundle entry path',
      );
    }
    if (byteLength < 0) {
      throw ArgumentError.value(
          byteLength, 'byteLength', 'must not be negative');
    }
    if (!_sha256Pattern.hasMatch(sha256)) {
      throw ArgumentError.value(
        sha256,
        'sha256',
        'must be sha256:<64 lowercase hex characters>',
      );
    }
  }

  /// Logical path of the entry inside the bundle.
  final String logicalPath;

  /// Bundle-scoped role of the entry.
  final RestageBundleEntryRoleV1 role;

  /// Exact payload byte length.
  final int byteLength;

  /// SHA-256 of the exact entry bytes.
  final String sha256;

  static final RegExp _sha256Pattern = RegExp(r'^sha256:[0-9a-f]{64}$');
}

/// Locates one screen closure inside a packaged source bundle.
///
/// A locator is generated only for an application that deliberately packages
/// its bundles. Its presence never relaxes a hosted check: it says where the
/// optional bundled fallback lives and exactly which bytes are acceptable
/// there, and nothing else.
@immutable
final class SurfaceScreenBundleLocator {
  /// Creates the locator for one exact screen closure.
  SurfaceScreenBundleLocator({
    required this.assetKey,
    required this.packageName,
    required this.authoredLibraryPath,
    required List<SurfaceScreenBundleEntryReference> entries,
  }) : entries = List.unmodifiable(entries) {
    if (assetKey.isEmpty) {
      throw ArgumentError.value(assetKey, 'assetKey', 'must not be empty');
    }
    if (packageName.isEmpty) {
      throw ArgumentError.value(
          packageName, 'packageName', 'must not be empty');
    }
    if (!authoredLibraryPath.startsWith('lib/') ||
        !authoredLibraryPath.endsWith('.dart')) {
      throw ArgumentError.value(
        authoredLibraryPath,
        'authoredLibraryPath',
        'must be a Dart library path under lib/',
      );
    }
    final paths = this.entries.map((entry) => entry.logicalPath).toSet();
    if (paths.length != this.entries.length) {
      throw ArgumentError.value(
        entries,
        'entries',
        'must not contain duplicate logical paths',
      );
    }
    if (_entriesForRole(RestageBundleEntryRoleV1.screenBlob).length != 1 ||
        _entriesForRole(RestageBundleEntryRoleV1.capabilitySidecar).length !=
            1) {
      throw ArgumentError.value(
        entries,
        'entries',
        'must contain exactly one screen blob and one capability sidecar',
      );
    }
  }

  /// Flutter asset key of the packaged bundle.
  final String assetKey;

  /// Package name the bundle must declare.
  final String packageName;

  /// Authored library path the bundle must declare.
  final String authoredLibraryPath;

  /// Every entry this screen requires from the bundle.
  ///
  /// A bundle may legitimately carry more than these — inspection text, or
  /// artifacts belonging to sibling screens in the same authored library.
  /// Those are ignored; only the entries named here are read or checked.
  final List<SurfaceScreenBundleEntryReference> entries;

  /// The one screen-blob entry of this closure.
  SurfaceScreenBundleEntryReference get screenBlob =>
      _entriesForRole(RestageBundleEntryRoleV1.screenBlob).single;

  /// The paired capability-sidecar entry of this closure.
  SurfaceScreenBundleEntryReference get capabilitySidecar =>
      _entriesForRole(RestageBundleEntryRoleV1.capabilitySidecar).single;

  Iterable<SurfaceScreenBundleEntryReference> _entriesForRole(
    RestageBundleEntryRoleV1 role,
  ) =>
      entries.where((entry) => entry.role == role);
}

/// Compiled-in provenance for one independently published screen.
///
/// This is the runtime authority for a screen's identity and contract. It is
/// ordinary generated Dart the application compiles in, so hosted validation
/// works whether or not any physical artifact is packaged with the app.
///
/// The contract hashes are *derived* here rather than restated: a generated
/// reference carries the values the build computed, this derives the same
/// values from the same inputs, and [validateReference] requires the two to
/// agree. A divergence between the build-time and runtime encoders therefore
/// fails closed instead of passing unnoticed.
@immutable
final class SurfaceScreenRuntimeProvenance {
  /// Creates provenance from a decoded event schema.
  factory SurfaceScreenRuntimeProvenance({
    required Surface surface,
    required String slug,
    required int contractVersion,
    required CapabilityManifest capabilities,
    required SurfaceScreenEventSchemaV1 eventSchema,
    SurfaceScreenBundleLocator? bundle,
  }) {
    if (contractVersion < 1) {
      throw ArgumentError.value(
        contractVersion,
        'contractVersion',
        'must be positive',
      );
    }
    final eventContractHash =
        SurfaceScreenEventContractHashV1.hash(eventSchema);
    return SurfaceScreenRuntimeProvenance._(
      surface: surface,
      slug: slug,
      contractVersion: contractVersion,
      capabilities: capabilities,
      eventSchema: eventSchema,
      eventContractHash: eventContractHash,
      contractFingerprint: SurfaceScreenContractFingerprintV1.hash(
        sourceKind: sourceKind,
        payloadKind: payloadKind,
        capabilities: capabilities,
        eventContractHash: eventContractHash,
      ),
      bundle: bundle,
    );
  }

  /// Creates provenance from the canonical event-schema JSON a build emits.
  ///
  /// Generated code passes the schema in its canonical encoded form rather
  /// than as a Dart literal tree, so the value that is hashed at runtime is
  /// the exact value the build hashed.
  factory SurfaceScreenRuntimeProvenance.generated({
    required Surface surface,
    required String slug,
    required int contractVersion,
    required CapabilityManifest capabilities,
    required String eventSchemaJson,
    SurfaceScreenBundleLocator? bundle,
  }) =>
      SurfaceScreenRuntimeProvenance(
        surface: surface,
        slug: slug,
        contractVersion: contractVersion,
        capabilities: capabilities,
        eventSchema:
            SurfaceScreenEventSchemaV1Codec.decodeJson(eventSchemaJson),
        bundle: bundle,
      );

  const SurfaceScreenRuntimeProvenance._({
    required this.surface,
    required this.slug,
    required this.contractVersion,
    required this.capabilities,
    required this.eventSchema,
    required this.eventContractHash,
    required this.contractFingerprint,
    required this.bundle,
  });

  /// Source semantics every standalone screen has.
  static const SurfaceSourceKind sourceKind = SurfaceSourceKind.screen;

  /// Payload semantics every standalone screen has.
  static const SurfacePayloadKind payloadKind = SurfacePayloadKind.blob;

  /// Product category of the screen.
  final Surface surface;

  /// Publication slug of the screen.
  final String slug;

  /// Application-pinned standalone-screen contract version.
  final int contractVersion;

  /// Render-capability floor and library requirements of the screen.
  final CapabilityManifest capabilities;

  /// Complete accepted event set of the screen.
  final SurfaceScreenEventSchemaV1 eventSchema;

  /// Hash derived from [eventSchema].
  final String eventContractHash;

  /// Fingerprint derived from the contract fields.
  final String contractFingerprint;

  /// Where the optional packaged fallback lives, when one was generated.
  final SurfaceScreenBundleLocator? bundle;

  /// Fails closed unless [resolved] matches this generated contract exactly.
  void validateResolved(ResolvedSurfaceScreen resolved) {
    if (resolved.surface != surface ||
        resolved.slug != slug ||
        resolved.contractVersion != contractVersion) {
      throw const SurfaceScreenUnavailableError(
        reason: SurfaceScreenUnavailableReason.identityMismatch,
        message:
            'The resolved screen identity does not match generated provenance.',
      );
    }
    if (resolved.sourceKind != sourceKind ||
        resolved.payloadKind != payloadKind ||
        resolved.capabilities != capabilities ||
        resolved.contractFingerprint != contractFingerprint ||
        resolved.eventContractHash != eventContractHash) {
      throw const SurfaceScreenUnavailableError(
        reason: SurfaceScreenUnavailableReason.contractMismatch,
        message:
            'The resolved screen contract does not match generated provenance.',
      );
    }
    final payload = BlobSurfacePayload(
      minClient: capabilities.builtInFloor,
      blob: resolved.blob,
      requiredLibraries: capabilities.requiredLibraries,
    );
    if (payload.contentHash != resolved.contentHash) {
      throw const SurfaceScreenUnavailableError(
        reason: SurfaceScreenUnavailableReason.invalidPayload,
        message: 'The resolved screen content hash does not match its bytes.',
      );
    }
    if (resolved.origin != SurfaceScreenOrigin.bundled) return;

    // Bundled bytes are additionally pinned to the exact generated entry, so a
    // repackaged asset cannot substitute different content for this screen.
    final locator = bundle;
    final entryHash = resolved.bundledEntryHash;
    if (locator == null ||
        entryHash == null ||
        entryHash != locator.screenBlob.sha256 ||
        CapabilitySidecar.hashBlob(resolved.blob) != entryHash) {
      throw const SurfaceScreenUnavailableError(
        reason: SurfaceScreenUnavailableReason.contractMismatch,
        message: 'Bundled screen content does not match generated provenance.',
      );
    }
  }
}
