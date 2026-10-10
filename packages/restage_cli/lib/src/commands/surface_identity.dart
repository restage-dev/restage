import 'dart:io';

import 'package:args/args.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/api/selector_syntax.dart';
import 'package:restage_cli/src/config/restage_config.dart';
import 'package:restage_cli/src/publication/publication_errors.dart';
import 'package:restage_cli/src/publication/publication_manifest.dart';
import 'package:restage_shared/restage_shared.dart';

/// The generated manifest consumed by project-context lifecycle commands.
const String kSurfacePublicationManifestPath =
    surfacePublicationManifestRelativePath;

/// The generated invalid-build marker. Its presence makes the manifest
/// unusable, even when an older manifest file is still present.
const String kSurfacePublicationInvalidPath =
    surfacePublicationInvalidRelativePath;

/// Surface categories accepted by the lifecycle command family.
const Set<SurfaceType> kLifecycleSurfaceTypes = <SurfaceType>{
  SurfaceType.onboarding,
  SurfaceType.message,
  SurfaceType.survey,
  SurfaceType.paywall,
  SurfaceType.general,
};

/// Source kinds accepted by exact family lifecycle selectors.
const Set<SurfaceSourceKind> kLifecycleSourceKinds = <SurfaceSourceKind>{
  SurfaceSourceKind.screen,
  SurfaceSourceKind.flowGraph,
  SurfaceSourceKind.paywall,
};

/// The identity and family address selected for a lifecycle operation.
///
/// A null [sourceKind], or a screen with a null [contractVersion], leaves the
/// family for the server to resolve.
@experimental
@immutable
class SurfaceLifecycleIdentity {
  /// Construct a validated lifecycle identity.
  const SurfaceLifecycleIdentity({
    required this.surface,
    required this.slug,
    required this.sourceKind,
    required this.payloadKind,
    required this.contractVersion,
    required this.fromManifest,
  }) : assert(slug != ''),
       assert(
         contractVersion == null ||
             (sourceKind == SurfaceSourceKind.screen && contractVersion > 0),
       );

  /// Surface category.
  final Surface surface;

  /// Stable surface slug.
  final String slug;

  /// Authored source shape, or null when the server resolves it.
  final SurfaceSourceKind? sourceKind;

  /// Declared payload shape. Specialized paywalls may retain either shape
  /// across revisions, so an explicit paywall fallback may leave this null.
  final SurfacePayloadKind? payloadKind;

  /// Positive standalone-screen contract version, or null for a non-versioned
  /// flow/paywall lineage.
  final int? contractVersion;

  /// Whether this identity came from the current generated manifest.
  final bool fromManifest;

  /// Whether this is the identity-wide governance address.
  bool get isIdentityAddress => true;

  /// Whether the family is named exactly, with nothing left to the server.
  bool get isExact =>
      sourceKind != null &&
      (sourceKind != SurfaceSourceKind.screen || contractVersion != null);

  /// Human-readable family address used by CLI output.
  String get familyAddress =>
      describeFamily(sourceKind, contractVersion, payloadKind: payloadKind);

  /// This identity with the family the server resolved for it.
  SurfaceLifecycleIdentity resolvedAs({
    required SurfaceSourceKind sourceKind,
    required int? contractVersion,
  }) => SurfaceLifecycleIdentity(
    surface: surface,
    slug: slug,
    sourceKind: sourceKind,
    payloadKind: payloadKind,
    contractVersion: contractVersion,
    fromManifest: fromManifest,
  );

  /// Wire arguments for a family-scoped operation.
  ///
  /// Keeping the null value explicit is intentional: it selects the existing
  /// non-versioned flow/paywall lineage instead of allowing a caller or server
  /// adapter to synthesize a contract version.
  Map<String, dynamic> get familyAddressArgs => <String, dynamic>{
    'contractVersion': contractVersion,
  };
}

/// Human-readable family address: `contract vN`, a non-versioned lineage, or
/// the current family when the server resolves it.
String describeFamily(
  SurfaceSourceKind? sourceKind,
  int? contractVersion, {
  SurfacePayloadKind? payloadKind,
}) {
  if (contractVersion != null) return 'contract v$contractVersion';
  if (sourceKind == null) return 'current family';
  if (sourceKind == SurfaceSourceKind.screen) return 'current contract';
  final payload = payloadKind?.wireName;
  return payload == null
      ? 'non-versioned ${sourceKind.wireName}'
      : 'non-versioned ${sourceKind.wireName}/$payload';
}

/// Resolve one lifecycle identity from the current generated manifest, or
/// from explicit selectors outside it. Selectors left out are resolved by the
/// server.
@experimental
Future<SurfaceLifecycleIdentity?> resolveSurfaceLifecycleIdentity({
  required ArgResults? argResults,
  required SurfaceType? fixedSurfaceType,
  required String slug,
  required StringSink stderr,
}) async {
  final explicitType = _readSurfaceType(
    argResults: argResults,
    fixedSurfaceType: fixedSurfaceType,
    stderr: stderr,
  );
  if (fixedSurfaceType == null && _hasInvalidSurfaceType(argResults)) {
    return null;
  }
  final explicitSourceKind = _readSourceKind(
    argResults: argResults,
    stderr: stderr,
  );
  if (_hasInvalidSourceKind(argResults)) return null;
  final explicitVersion = _readContractVersion(argResults, stderr);
  if (explicitVersion == _invalidContractVersion) return null;
  final refusal = _explicitSelectorRefusal(
    surfaceType: explicitType,
    sourceKind: explicitSourceKind,
    contractVersion: explicitVersion,
  );
  if (refusal != null) {
    stderr.writeln(refusal);
    return null;
  }

  final loaded = await _loadConfigForIdentity(argResults, stderr);
  final projectRoot = loaded?.source.parent;
  if (projectRoot != null) {
    final manifestFile = File(
      p.join(projectRoot.path, kSurfacePublicationManifestPath),
    );
    final invalidMarker = File(
      p.join(projectRoot.path, kSurfacePublicationInvalidPath),
    );
    if (manifestFile.existsSync() || invalidMarker.existsSync()) {
      final LoadedSurfacePublicationManifest loadedManifest;
      try {
        loadedManifest = await SurfacePublicationManifestLoader().load(
          projectRoot: projectRoot,
        );
      } on PublicationManifestException catch (e) {
        stderr.writeln(e.message);
        return null;
      }

      final slugMatches = loadedManifest.manifest.publications
          .where((entry) => entry.publication.slug == slug)
          .toList(growable: false);
      if (slugMatches.isNotEmpty) {
        final SurfacePublication selected;
        try {
          selected = loadedManifest
              .select(
                slug: slug,
                type: explicitType,
                // A positive contract version is the existing typed shorthand
                // for a screen family. Do not infer paywall source kind from a
                // category when no explicit selector was supplied: a current
                // manifest entry remains the authority, and duplicate entries
                // must be rejected as ambiguous.
                sourceKind:
                    explicitSourceKind ??
                    (explicitVersion == null ? null : SurfaceSourceKind.screen),
                contractVersion: explicitVersion,
              )
              .publication;
        } on PublicationManifestException catch (e) {
          stderr.writeln(e.message);
          return null;
        }
        final identity = _identityFromPublication(selected);
        if (!_validateExplicitSourceKind(
          identity,
          explicitSourceKind,
          stderr,
        )) {
          return null;
        }
        if (!_validateExplicitVersion(identity, explicitVersion, stderr)) {
          return null;
        }
        return identity;
      }

      // A current manifest is authoritative. Explicit identity is allowed
      // here only because the source may have been removed from the roster.
      if (explicitType == null) {
        stderr.writeln(
          'Surface "$slug" is not present in the generated manifest. '
          'Pass --type and, for a standalone screen, --contract-version to '
          'target a removed source explicitly.',
        );
        return null;
      }
    }
  }

  final type = explicitType;
  if (type == null) {
    final valid = kLifecycleSurfaceTypes.map((t) => t.wireName).join(', ');
    stderr.writeln(
      'Required: --type <$valid>, or run from a project with a generated '
      'surface publication manifest.',
    );
    return null;
  }
  return _explicitIdentity(
    type: type,
    slug: slug,
    sourceKind: explicitSourceKind,
    contractVersion: explicitVersion,
  );
}

/// The lifecycle identity explicit selectors name, outside any manifest.
///
/// Throws [TargetSelectionException] when the selectors conflict.
@experimental
SurfaceLifecycleIdentity explicitLifecycleIdentity({
  required Surface type,
  required String slug,
  SurfaceSourceKind? sourceKind,
  int? contractVersion,
}) {
  final refusal = _explicitSelectorRefusal(
    surfaceType: type,
    sourceKind: sourceKind,
    contractVersion: contractVersion,
  );
  if (refusal != null) throw TargetSelectionException(refusal);
  return _explicitIdentity(
    type: type,
    slug: slug,
    sourceKind: sourceKind,
    contractVersion: contractVersion,
  );
}

SurfaceLifecycleIdentity _explicitIdentity({
  required Surface type,
  required String slug,
  required SurfaceSourceKind? sourceKind,
  required int? contractVersion,
}) {
  final resolvedKind =
      sourceKind ?? (contractVersion == null ? null : SurfaceSourceKind.screen);
  final payloadKind = switch (resolvedKind) {
    SurfaceSourceKind.screen => SurfacePayloadKind.blob,
    SurfaceSourceKind.flowGraph => SurfacePayloadKind.flow,
    SurfaceSourceKind.paywall || null => null,
  };
  return SurfaceLifecycleIdentity(
    surface: type,
    slug: slug,
    sourceKind: resolvedKind,
    payloadKind: payloadKind,
    contractVersion: resolvedKind == SurfaceSourceKind.screen
        ? contractVersion
        : null,
    fromManifest: false,
  );
}

const int _invalidContractVersion = -1;

Future<({RestageConfig config, File source})?> _loadConfigForIdentity(
  ArgResults? argResults,
  StringSink stderr,
) async {
  try {
    return await loadRestageConfig(from: Directory(_readDirectory(argResults)));
  } on RestageConfigFormatException catch (e) {
    stderr.writeln(e.message);
    return null;
  } on FileSystemException catch (e) {
    stderr.writeln('Could not read restage_config.yaml: $e');
    return null;
  }
}

String _readDirectory(ArgResults? argResults) {
  try {
    return argResults?['directory'] as String? ?? '.';
  } on Object {
    return '.';
  }
}

bool _hasInvalidSurfaceType(ArgResults? argResults) {
  String? raw;
  try {
    raw = argResults?['type'] as String?;
  } on Object {
    raw = null;
  }
  if (raw == null || raw.isEmpty) return false;
  try {
    final type = SurfaceType.fromWireName(raw);
    return !kLifecycleSurfaceTypes.contains(type);
  } on FormatException {
    return true;
  }
}

bool _hasInvalidSourceKind(ArgResults? argResults) {
  String? raw;
  try {
    raw = argResults?['source-kind'] as String?;
  } on Object {
    raw = null;
  }
  if (raw == null || raw.isEmpty) return false;
  try {
    final sourceKind = SurfaceSourceKind.fromWireName(raw);
    return !kLifecycleSourceKinds.contains(sourceKind);
  } on FormatException {
    return true;
  }
}

SurfaceType? _readSurfaceType({
  required ArgResults? argResults,
  required SurfaceType? fixedSurfaceType,
  required StringSink stderr,
}) {
  if (fixedSurfaceType != null) return fixedSurfaceType;
  String? raw;
  try {
    raw = argResults?['type'] as String?;
  } on Object {
    raw = null;
  }
  if (raw == null || raw.isEmpty) return null;
  final SurfaceType type;
  try {
    type = SurfaceType.fromWireName(raw);
  } on FormatException {
    final valid = kLifecycleSurfaceTypes.map((t) => t.wireName).join(', ');
    stderr.writeln('Invalid --type "$raw". Valid values: $valid.');
    return null;
  }
  if (!kLifecycleSurfaceTypes.contains(type)) {
    final valid = kLifecycleSurfaceTypes.map((t) => t.wireName).join(', ');
    stderr.writeln('Invalid --type "$raw". Valid values: $valid.');
    return null;
  }
  return type;
}

SurfaceSourceKind? _readSourceKind({
  required ArgResults? argResults,
  required StringSink stderr,
}) {
  String? raw;
  try {
    raw = argResults?['source-kind'] as String?;
  } on Object {
    raw = null;
  }
  if (raw == null || raw.isEmpty) return null;
  final SurfaceSourceKind sourceKind;
  try {
    sourceKind = SurfaceSourceKind.fromWireName(raw);
  } on FormatException {
    final valid = kLifecycleSourceKinds.map((kind) => kind.wireName).join(', ');
    stderr.writeln('Invalid --source-kind "$raw". Valid values: $valid.');
    return null;
  }
  if (!kLifecycleSourceKinds.contains(sourceKind)) {
    final valid = kLifecycleSourceKinds.map((kind) => kind.wireName).join(', ');
    stderr.writeln('Invalid --source-kind "$raw". Valid values: $valid.');
    return null;
  }
  return sourceKind;
}

int? _readContractVersion(ArgResults? argResults, StringSink stderr) {
  String? raw;
  try {
    raw = argResults?['contract-version'] as String?;
  } on Object {
    raw = null;
  }
  if (raw == null || raw.trim().isEmpty) return null;
  final parsed = int.tryParse(raw.trim());
  if (parsed == null || parsed < 1) {
    stderr.writeln('Expected a positive integer for --contract-version.');
    return _invalidContractVersion;
  }
  return parsed;
}

bool _validateExplicitVersion(
  SurfaceLifecycleIdentity identity,
  int? explicitVersion,
  StringSink stderr,
) {
  if (explicitVersion == null) return true;
  if (identity.contractVersion == null) {
    stderr.writeln(
      'The generated ${identity.sourceKind!.wireName} family for '
      '"${identity.slug}" is non-versioned; do not pass '
      '--contract-version.',
    );
    return false;
  }
  if (identity.contractVersion != explicitVersion) {
    stderr.writeln(
      'The explicit contract version v$explicitVersion does not match the '
      'generated manifest version v${identity.contractVersion} for '
      '"${identity.slug}".',
    );
    return false;
  }
  return true;
}

bool _validateExplicitSourceKind(
  SurfaceLifecycleIdentity identity,
  SurfaceSourceKind? explicitSourceKind,
  StringSink stderr,
) {
  if (explicitSourceKind == null || identity.sourceKind == explicitSourceKind) {
    return true;
  }
  stderr.writeln(
    'The generated ${identity.sourceKind!.wireName} family for '
    '"${identity.slug}" does not match explicit --source-kind '
    '${explicitSourceKind.wireName}. The generated manifest is authoritative.',
  );
  return false;
}

String? _explicitSelectorRefusal({
  required SurfaceType? surfaceType,
  required SurfaceSourceKind? sourceKind,
  required int? contractVersion,
}) {
  if (sourceKind != null &&
      sourceKind != SurfaceSourceKind.screen &&
      contractVersion != null) {
    return '--source-kind ${sourceKind.wireName} cannot be combined with '
        '--contract-version; this source kind is non-versioned.';
  }
  if (sourceKind == SurfaceSourceKind.paywall &&
      surfaceType != null &&
      surfaceType != SurfaceType.paywall) {
    return '--source-kind paywall requires --type paywall; a specialized '
        'paywall cannot be categorized as another surface.';
  }
  return null;
}

SurfaceLifecycleIdentity _identityFromPublication(
  SurfacePublication publication,
) => SurfaceLifecycleIdentity(
  surface: publication.surface,
  slug: publication.slug,
  sourceKind: publication.sourceKind,
  payloadKind: publication.payloadKind,
  contractVersion: publication.contractVersion,
  fromManifest: true,
);
