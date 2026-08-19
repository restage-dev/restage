import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:restage_shared/restage_shared.dart';

import 'publication_errors.dart';

/// The fixed generated manifest location within a project package.
const String surfacePublicationManifestRelativePath =
    'assets/restage/surface-publication-manifest.json';

/// The fixed code-generation failure marker consumed by the freshness gate.
const String surfacePublicationInvalidRelativePath =
    'assets/restage/surface-publication.invalid';

/// A decoded generated publication manifest and the project root from which
/// its package-relative artifacts are read.
final class LoadedSurfacePublicationManifest {
  /// Construct a loaded manifest.
  const LoadedSurfacePublicationManifest({
    required this.projectRoot,
    required this.manifestFile,
    required this.invalidMarkerFile,
    required this.manifest,
  });

  /// The project package root used for fixed generated asset paths.
  final Directory projectRoot;

  /// The fixed manifest file that was decoded.
  final File manifestFile;

  /// The fixed invalid-marker location checked by the freshness gate.
  final File invalidMarkerFile;

  /// The strict generated manifest.
  final SurfacePublicationManifestV1 manifest;

  /// Select one generated identity for publication.
  ///
  /// [type] is a validation or disambiguation selector only. It never chooses
  /// an artifact directory or changes the generated publication identity.
  SurfacePublicationManifestEntryV1 select({
    required String slug,
    Surface? type,
    SurfaceSourceKind? sourceKind,
    int? contractVersion,
  }) {
    final bySlug = manifest.publications
        .where((entry) => entry.publication.slug == slug)
        .toList(growable: false);
    if (bySlug.isEmpty) {
      throw PublicationManifestException(
        'No generated publication named "$slug" was found in '
        '$surfacePublicationManifestRelativePath. Re-run '
        '`dart run build_runner build` and retry.',
      );
    }

    var candidates = bySlug;
    if (type != null) {
      candidates = candidates
          .where((entry) => entry.publication.surface == type)
          .toList(growable: false);
      if (candidates.isEmpty) {
        final actual = bySlug
            .map((entry) => entry.publication.surface.wireName)
            .join(', ');
        throw PublicationManifestException(
          'Generated publication "$slug" has surface type $actual, which does '
          'not match the requested generated identity. The generated manifest '
          'is authoritative; retry with the matching command.',
        );
      }
    }

    if (sourceKind != null) {
      candidates = candidates
          .where((entry) => entry.publication.sourceKind == sourceKind)
          .toList(growable: false);
    }
    if (contractVersion != null) {
      candidates = candidates
          .where(
            (entry) => entry.publication.contractVersion == contractVersion,
          )
          .toList(growable: false);
    }

    if (candidates.length == 1) return candidates.single;
    if (candidates.isEmpty) {
      throw PublicationManifestException(
        'Generated publication "$slug" does not match the requested '
        'generated source identity. The generated manifest is authoritative; '
        'retry with the matching --type, --source-kind, or '
        '--contract-version.',
      );
    }

    if (candidates.length > 1) {
      final identities = candidates
          .map(
            (entry) =>
                '${entry.publication.surface.wireName}/'
                '${entry.publication.slug} '
                'source=${entry.publication.sourceKind.wireName}'
                '${entry.publication.contractVersion == null ? '' : ' '
                          'contract=v${entry.publication.contractVersion}'}',
          )
          .join(', ');
      throw PublicationManifestException(
        'Publication name "$slug" is ambiguous in the generated manifest '
        '($identities). Pass the exact --type, --source-kind, and/or '
        '--contract-version selector; the CLI will not guess.',
      );
    }
    // The candidate list is non-empty and the branches above return for one
    // candidate or throw for more than one. Keep this unreachable assertion
    // explicit so a future change cannot silently select an ambiguous entry.
    throw StateError('Unreachable empty publication candidate set.');
  }
}

/// Loads the fixed generated publication manifest and enforces its freshness
/// marker before a command performs any backend work.
final class SurfacePublicationManifestLoader {
  /// Load the manifest rooted at [projectRoot].
  Future<LoadedSurfacePublicationManifest> load({
    required Directory projectRoot,
  }) async {
    final root = projectRoot.absolute;
    final manifestFile = File(
      p.join(root.path, surfacePublicationManifestRelativePath),
    );
    final invalidMarkerFile = File(
      p.join(root.path, surfacePublicationInvalidRelativePath),
    );

    if (invalidMarkerFile.existsSync()) {
      throw const PublicationManifestException(
        'Generated publication output is invalid. Remove the stale build '
        'state by re-running `dart run build_runner build`, then retry.',
      );
    }
    if (!manifestFile.existsSync()) {
      throw const PublicationManifestException(
        'No generated publication manifest was found at '
        '`assets/restage/surface-publication-manifest.json`. Run '
        '`dart run build_runner build` and retry.',
      );
    }

    final String source;
    try {
      source = await manifestFile.readAsString();
    } on FileSystemException {
      throw const PublicationManifestException(
        'The generated publication manifest could not be read. Re-run '
        '`dart run build_runner build` and retry.',
      );
    }

    final SurfacePublicationManifestV1 manifest;
    try {
      manifest = SurfacePublicationManifestV1Codec.decodeJson(source);
    } on Object {
      throw const PublicationManifestException(
        'The generated publication manifest is malformed. Re-run '
        '`dart run build_runner build` and retry.',
      );
    }

    if (SurfacePublicationManifestV1Codec.encodeCanonicalJson(manifest) !=
        source) {
      throw const PublicationManifestException(
        'The generated publication manifest is not canonical. Re-run '
        '`dart run build_runner build` and retry.',
      );
    }

    return LoadedSurfacePublicationManifest(
      projectRoot: root,
      manifestFile: manifestFile,
      invalidMarkerFile: invalidMarkerFile,
      manifest: manifest,
    );
  }
}
