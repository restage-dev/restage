import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:restage_cli/src/receipts/git_repository.dart';
import 'package:restage_cli/src/render_bundles/package_resolution.dart';
import 'package:yaml/yaml.dart';

/// Sources pinned by the lockfile rather than by this repository's history.
const Set<String> _pinnedSources = {'hosted', 'git', 'sdk'};

/// The packages whose source a recorded operation holds to one commit.
final class SourceBoundary {
  /// Construct a boundary over [packages].
  const SourceBoundary({required this.packages});

  /// Repository-relative package roots, sorted.
  final List<String> packages;
}

/// Thrown when the boundary cannot be established honestly.
final class SourceBoundaryException implements Exception {
  /// Construct with a message the developer can act on.
  const SourceBoundaryException(this.message);

  /// Human-readable description of the problem.
  final String message;

  @override
  String toString() => message;
}

/// The packages that feed generation for the app at [projectRoot].
///
/// The app package plus its dependency closure, narrowed to the packages
/// inside the repository. A dependency outside the repository whose source
/// the lockfile does not pin is refused by name unless [allowUnpinned]: a
/// receipt could not say what state it was in.
Future<SourceBoundary> resolveSourceBoundary({
  required Directory projectRoot,
  required GitRepository repository,
  bool allowUnpinned = false,
}) async {
  final appPackage = _packageNameAt(projectRoot);
  final PackageResolution resolution;
  final Set<String> closure;
  try {
    resolution = await PackageResolution.read(projectRoot, appName: appPackage);
    closure = resolution.closure(appPackage, includeDev: true);
  } on PackageResolutionException catch (error) {
    throw SourceBoundaryException(switch (error.failure) {
      PackageResolutionFailure.unresolved =>
        'The packages this app resolves are not on disk. Run `dart pub get` '
            'and retry.',
      PackageResolutionFailure.graphMissing =>
        'The resolved package graph is not on disk, so the packages this app '
            'depends on cannot be read. Run `dart pub get` and retry.',
      PackageResolutionFailure.graphUnreadable =>
        'The resolved package graph cannot be read. Run `dart pub get` and '
            'retry.',
      PackageResolutionFailure.notInGraph =>
        'The resolved package graph does not list "$appPackage". Run '
            '`dart pub get` and retry.',
    });
  }
  final lockSources = _lockSources(resolution.toolDirectory.parent);

  final repositoryRoot = _directoryPath(repository.root);
  final inside = <String>[];
  final unpinned = <String>[];
  for (final name in closure) {
    final root = resolution.rootOf(name);
    if (root == null) continue;
    if (p.equals(repositoryRoot, root) || p.isWithin(repositoryRoot, root)) {
      inside.add(repository.pathspecFor(root));
    } else if (!_pinnedSources.contains(lockSources[name])) {
      unpinned.add(name);
    }
  }
  if (unpinned.isNotEmpty && !allowUnpinned) {
    unpinned.sort();
    throw SourceBoundaryException(
      'These packages are outside the repository, so a receipt cannot say '
      'what state they were in: ${unpinned.join(', ')}. Move them into the '
      'repository, depend on published versions, or drop --record-git.',
    );
  }
  inside.sort();
  return SourceBoundary(packages: inside);
}

String _packageNameAt(Directory projectRoot) {
  final pubspec = File(p.join(projectRoot.path, 'pubspec.yaml'));
  if (!pubspec.existsSync()) {
    throw const SourceBoundaryException(
      'No pubspec.yaml here, so there is no app package to record. Run the '
      'command in the app package.',
    );
  }
  final Object? document;
  try {
    document = loadYaml(pubspec.readAsStringSync());
  } on YamlException {
    throw const SourceBoundaryException('The pubspec here cannot be read.');
  }
  final name = document is Map ? document['name'] : null;
  if (name is! String || name.isEmpty) {
    throw const SourceBoundaryException('The pubspec here declares no name.');
  }
  return name;
}

/// The source the lockfile records for each resolved package.
Map<String, String> _lockSources(Directory workspaceRoot) {
  final lock = File(p.join(workspaceRoot.path, 'pubspec.lock'));
  if (!lock.existsSync()) {
    throw const SourceBoundaryException(
      'No lockfile beside the resolved packages, so their sources cannot be '
      'read. Run `dart pub get` and retry.',
    );
  }
  final Object? document;
  try {
    document = loadYaml(lock.readAsStringSync());
  } on YamlException {
    throw const SourceBoundaryException('The lockfile cannot be read.');
  }
  final packages = document is Map ? document['packages'] : null;
  if (packages is! Map) return const <String, String>{};
  return <String, String>{
    for (final entry in packages.entries)
      if (entry.key is String && entry.value is Map)
        entry.key as String: '${(entry.value as Map)['source']}',
  };
}

String _directoryPath(Directory directory) {
  try {
    return directory.resolveSymbolicLinksSync();
  } on FileSystemException {
    return p.normalize(directory.absolute.path);
  }
}
