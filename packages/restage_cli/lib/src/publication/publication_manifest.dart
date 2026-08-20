import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:restage_shared/restage_shared.dart';

import 'publication_errors.dart';
import 'publication_outputs.dart';

/// The default generated publication manifest location within a package.
///
/// Configured `output_root` values and transient Build Runner overrides are
/// resolved from the generated output index instead of this default path.
const String surfacePublicationManifestRelativePath =
    'lib/generated/restage.publication.json';

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
    required this.outputIndex,
  });

  /// The project package root used for fixed generated asset paths.
  final Directory projectRoot;

  /// The fixed manifest file that was decoded.
  final File manifestFile;

  /// The fixed invalid-marker location checked by the freshness gate.
  final File invalidMarkerFile;

  /// The strict generated manifest.
  final SurfacePublicationManifestV1 manifest;

  /// The physical locators paired with [manifest].
  final RestageOutputIndex outputIndex;

  /// Every generated publication compiled from the Dart file at [path].
  ///
  /// The id stays the canonical key. This is a convenience for the developer
  /// who is looking at a file rather than at the manifest, and it resolves
  /// strictly through the generated manifest: no source is parsed and no
  /// directory is scanned, so what publishes is exactly what was generated.
  ///
  /// Matching is on the sources the manifest ATTRIBUTES to the file, which is
  /// wider than what the file declares. A flow records the declaring file of
  /// every screen in its closure, so naming a screen selects the flow that
  /// publishes it.
  ///
  /// Returns every match in manifest order. Callers disambiguate; this
  /// never guesses. Throws when [path] cannot name generated output, when the
  /// manifest predates recorded sources, or when nothing was compiled from
  /// that file.
  List<SurfacePublicationManifestEntryV1> selectByPath({
    required String path,
    Surface? type,
    SurfaceSourceKind? sourceKind,
  }) {
    // Candidates are tried in order, not unioned: two readings can name two
    // different real files, and returning both would offer — and under
    // `--all` publish — a surface the developer never named.
    final candidates = _packageRelativeSourceCandidates(path);
    final attributed = <SurfacePublicationManifestEntryV1>[];
    var resolved = candidates.first;
    for (final candidate in candidates) {
      final matches = manifest.publications
          .where((entry) => entry.sources.contains(candidate))
          .toList(growable: false);
      if (matches.isNotEmpty) {
        attributed.addAll(matches);
        resolved = candidate;
        break;
      }
    }

    if (attributed.isEmpty) {
      throw PublicationManifestException(_nothingAttributed(resolved));
    }

    final matches = attributed
        .where((entry) => type == null || entry.publication.surface == type)
        .where(
          (entry) =>
              sourceKind == null || entry.publication.sourceKind == sourceKind,
        )
        .toList(growable: false);
    if (matches.isNotEmpty) return matches;

    // The file DID compile. Reporting "nothing was compiled from it" and
    // pointing at a rebuild would send the developer somewhere that can
    // never change the answer.
    final actual = attributed
        .map((entry) => entry.publication.surface.wireName)
        .toSet()
        .join(', ');
    throw PublicationManifestException(
      'Nothing compiled from "$resolved" is a '
      '${type?.wireName ?? sourceKind!.wireName} surface; it produced '
      '$actual. The generated manifest is authoritative; retry with the '
      'matching command.',
    );
  }

  /// The message for a path the manifest attributes nothing to.
  ///
  /// A `.dart` suffix always selects file resolution, so an id that happens
  /// to end in `.dart` lands here. Naming it is the difference between an
  /// answer and a rebuild that cannot help.
  String _nothingAttributed(String resolved) {
    if (manifest.publications.every((entry) => entry.sources.isEmpty)) {
      return '${outputIndex.publicationManifestPath} does not record '
          'authoring sources, so a file cannot select a publication. Re-run '
          '`dart run build_runner build` and retry, or publish by id.';
    }
    final collidingId = manifest.publications
        .where((entry) => entry.publication.slug == resolved)
        .map((entry) => entry.publication.slug)
        .firstOrNull;
    if (collidingId != null) {
      return 'No generated publication was compiled from "$resolved". A '
          'surface with the id "$collidingId" exists, but an argument ending '
          'in `.dart` always names a file; rename the surface to publish it.';
    }
    return 'No generated publication was compiled from "$resolved" according '
        'to ${outputIndex.publicationManifestPath}. Re-run '
        '`dart run build_runner build` and retry, or publish by id.';
  }

  /// The package-relative forms [raw] could name, most likely first.
  ///
  /// The caller tries them in order and stops at the first that the manifest
  /// attributes anything to.
  ///
  /// Two readings are plausible and neither is safe to prefer blindly. A path
  /// is normally resolved against the working directory, which is what the
  /// developer's shell completed it against. But the form the manifest
  /// records, every error message prints, and every doc example shows is
  /// package-relative, and pasting that from a subdirectory would otherwise
  /// resolve to a doubled prefix (`lib/lib/screen.dart`) rather than to the
  /// file the developer meant.
  ///
  /// So both readings are offered and the manifest decides between them. That
  /// keeps resolution a pure lookup: nothing is read from disk, so a path that
  /// happens to exist has no advantage over one that does not.
  List<String> _packageRelativeSourceCandidates(String raw) {
    final normalized = p.normalize(raw);
    final candidates = <String>[];

    final fromCurrentDirectory = p
        .split(p.relative(p.absolute(normalized), from: projectRoot.path))
        .join('/');
    if (!_escapesPackage(fromCurrentDirectory)) {
      candidates.add(fromCurrentDirectory);
    }

    if (!p.isAbsolute(normalized)) {
      final asPackageRelative = p.split(normalized).join('/');
      if (!_escapesPackage(asPackageRelative) &&
          !candidates.contains(asPackageRelative)) {
        candidates.add(asPackageRelative);
      }
    }

    if (candidates.isEmpty) {
      throw PublicationManifestException(
        'The path "$raw" is outside the package at ${projectRoot.path}, so it '
        'cannot name generated output.',
      );
    }
    return candidates;
  }

  static bool _escapesPackage(String posixPath) =>
      posixPath == '..' || posixPath.startsWith('../');

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
        '${outputIndex.publicationManifestPath}. Re-run '
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
    final invalidMarkerFile = File(
      p.join(root.path, surfacePublicationInvalidRelativePath),
    );

    if (invalidMarkerFile.existsSync()) {
      throw const PublicationManifestException(
        'Generated publication output is invalid. Remove the stale build '
        'state by re-running `dart run build_runner build`, then retry.',
      );
    }

    final located = await RestagePublicationOutputsLoader().load(
      projectRoot: root,
    );
    final manifestFile = located.publicationFile;
    final source = located.publicationManifestSource;

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
    try {
      located.index.validateAgainstManifest(manifest);
    } on FormatException catch (error) {
      throw PublicationManifestException(
        'The generated output index does not match the canonical publication '
        'manifest: ${error.message} Re-run `dart run build_runner build` and '
        'retry.',
      );
    }

    return LoadedSurfacePublicationManifest(
      projectRoot: root,
      manifestFile: manifestFile,
      invalidMarkerFile: invalidMarkerFile,
      manifest: manifest,
      outputIndex: located.index,
    );
  }
}
