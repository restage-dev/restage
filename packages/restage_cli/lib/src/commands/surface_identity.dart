import 'dart:io';

import 'package:args/args.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
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

/// The exact identity and family address selected for a lifecycle operation.
///
/// A standalone screen has a positive [contractVersion]. Flow graphs and
/// specialized paywalls use the existing non-versioned lineage and therefore
/// carry a null contract version.
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
         (sourceKind == SurfaceSourceKind.screen &&
                 payloadKind == SurfacePayloadKind.blob &&
                 contractVersion != null &&
                 contractVersion > 0) ||
             (sourceKind != SurfaceSourceKind.screen &&
                 contractVersion == null),
       );

  /// Surface category.
  final Surface surface;

  /// Stable surface slug.
  final String slug;

  /// Authored source shape.
  final SurfaceSourceKind sourceKind;

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

  /// Whether this family is the non-versioned lineage.
  bool get isNonVersioned => contractVersion == null;

  /// Human-readable family address used by CLI output.
  String get familyAddress {
    final version = contractVersion;
    if (version != null) return 'contract v$version';
    final payload = payloadKind?.wireName;
    return payload == null
        ? 'non-versioned ${sourceKind.wireName}'
        : 'non-versioned ${sourceKind.wireName}/$payload';
  }

  /// Wire arguments for a family-scoped operation.
  ///
  /// Keeping the null value explicit is intentional: it selects the existing
  /// non-versioned flow/paywall lineage instead of allowing a caller or server
  /// adapter to synthesize a contract version.
  Map<String, dynamic> get familyAddressArgs => <String, dynamic>{
    'contractVersion': contractVersion,
  };
}

/// Resolve one lifecycle identity from the current generated manifest, with a
/// typed explicit fallback for work outside that manifest.
@experimental
Future<SurfaceLifecycleIdentity?> resolveSurfaceLifecycleIdentity({
  required ArgResults? argResults,
  required SurfaceType? fixedSurfaceType,
  required String slug,
  required StringSink stderr,
  bool requireExplicitSourceKindForFallback = true,
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
  if (!_validateExplicitSelector(
    surfaceType: explicitType,
    sourceKind: explicitSourceKind,
    contractVersion: explicitVersion,
    stderr: stderr,
  )) {
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
  if (requireExplicitSourceKindForFallback &&
      explicitSourceKind == null &&
      explicitVersion == null) {
    stderr.writeln(
      'Lifecycle identity for "$slug" is ambiguous outside the generated '
      'manifest. Pass --source-kind to select flowGraph or specialized '
      'paywall; use --source-kind screen with --contract-version <N> for a '
      'standalone screen.',
    );
    return null;
  }
  final sourceKind = _fallbackSourceKind(
    surfaceType: type,
    sourceKind: explicitSourceKind,
    contractVersion: explicitVersion,
  );
  final payloadKind = switch (sourceKind) {
    SurfaceSourceKind.screen => SurfacePayloadKind.blob,
    SurfaceSourceKind.flowGraph => SurfacePayloadKind.flow,
    SurfaceSourceKind.paywall => null,
  };
  return SurfaceLifecycleIdentity(
    surface: type,
    slug: slug,
    sourceKind: sourceKind,
    payloadKind: payloadKind,
    contractVersion: sourceKind == SurfaceSourceKind.screen
        ? explicitVersion
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
      'The generated ${identity.sourceKind.wireName} family for '
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
    'The generated ${identity.sourceKind.wireName} family for '
    '"${identity.slug}" does not match explicit --source-kind '
    '${explicitSourceKind.wireName}. The generated manifest is authoritative.',
  );
  return false;
}

bool _validateExplicitSelector({
  required SurfaceType? surfaceType,
  required SurfaceSourceKind? sourceKind,
  required int? contractVersion,
  required StringSink stderr,
}) {
  if (sourceKind == SurfaceSourceKind.screen && contractVersion == null) {
    stderr.writeln(
      '--source-kind screen requires --contract-version <N>; standalone '
      'screen families are positively versioned.',
    );
    return false;
  }
  if (sourceKind != null &&
      sourceKind != SurfaceSourceKind.screen &&
      contractVersion != null) {
    stderr.writeln(
      '--source-kind ${sourceKind.wireName} cannot be combined with '
      '--contract-version; this source kind is non-versioned.',
    );
    return false;
  }
  if (sourceKind == SurfaceSourceKind.paywall &&
      surfaceType != null &&
      surfaceType != SurfaceType.paywall) {
    stderr.writeln(
      '--source-kind paywall requires --type paywall; a specialized paywall '
      'cannot be categorized as another surface.',
    );
    return false;
  }
  return true;
}

SurfaceSourceKind _fallbackSourceKind({
  required SurfaceType surfaceType,
  required SurfaceSourceKind? sourceKind,
  required int? contractVersion,
}) {
  if (sourceKind != null) return sourceKind;
  if (contractVersion != null) return SurfaceSourceKind.screen;
  return surfaceType == SurfaceType.paywall
      ? SurfaceSourceKind.paywall
      : SurfaceSourceKind.flowGraph;
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
