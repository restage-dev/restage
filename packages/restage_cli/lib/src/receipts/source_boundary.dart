import 'dart:convert';
import 'dart:io';

import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/receipts/git_repository.dart';
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
/// the lockfile does not pin is refused by name: nothing here records what
/// state it was in.
Future<SourceBoundary> resolveSourceBoundary({
  required Directory projectRoot,
  required GitRepository repository,
}) async {
  final toolDirectory = _findPackageConfigDirectory(projectRoot);
  if (toolDirectory == null) {
    throw const SourceBoundaryException(
      'The packages this app resolves are not on disk. Run `dart pub get` '
      'and retry.',
    );
  }
  final config = await loadPackageConfig(
    File(p.join(toolDirectory.path, 'package_config.json')),
  );
  final rootByName = <String, String>{
    for (final package in config.packages)
      package.name: _directoryPath(Directory.fromUri(package.root)),
  };
  final appPackage = _packageNameAt(projectRoot);
  final closure = _closure(
    graph: File(p.join(toolDirectory.path, 'package_graph.json')),
    appPackage: appPackage,
  );
  final lockSources = _lockSources(toolDirectory.parent);

  final repositoryRoot = _directoryPath(repository.root);
  final inside = <String>[];
  final unpinned = <String>[];
  for (final name in closure) {
    final root = rootByName[name];
    if (root == null) continue;
    if (p.equals(repositoryRoot, root) || p.isWithin(repositoryRoot, root)) {
      inside.add(repository.pathspecFor(root));
    } else if (!_pinnedSources.contains(lockSources[name])) {
      unpinned.add(name);
    }
  }
  if (unpinned.isNotEmpty) {
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

/// The directory holding the resolved package configuration for [from].
Directory? _findPackageConfigDirectory(Directory from) {
  var current = from.absolute;
  while (true) {
    final candidate = Directory(p.join(current.path, '.dart_tool'));
    if (File(p.join(candidate.path, 'package_config.json')).existsSync()) {
      return candidate;
    }
    final parent = current.parent;
    if (parent.path == current.path) return null;
    current = parent;
  }
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

/// Package names the app depends on, directly or through its dependencies.
///
/// Development dependencies count for the app itself: they run the build.
Set<String> _closure({required File graph, required String appPackage}) {
  if (!graph.existsSync()) {
    throw const SourceBoundaryException(
      'The resolved package graph is not on disk, so the packages this app '
      'depends on cannot be read. Run `dart pub get` and retry.',
    );
  }
  final Object? document;
  try {
    document = jsonDecode(graph.readAsStringSync());
  } on FormatException {
    throw const SourceBoundaryException(
      'The resolved package graph cannot be read. Run `dart pub get` and '
      'retry.',
    );
  }
  final entries = document is Map ? document['packages'] : null;
  if (entries is! List) {
    throw const SourceBoundaryException(
      'The resolved package graph lists no packages. Run `dart pub get` and '
      'retry.',
    );
  }
  final dependencies = <String, List<String>>{};
  final development = <String, List<String>>{};
  for (final entry in entries) {
    if (entry is! Map) continue;
    final name = entry['name'];
    if (name is! String) continue;
    dependencies[name] = _names(entry['dependencies']);
    development[name] = _names(entry['devDependencies']);
  }
  if (!dependencies.containsKey(appPackage)) {
    throw SourceBoundaryException(
      'The resolved package graph does not list "$appPackage". Run '
      '`dart pub get` and retry.',
    );
  }
  final seen = <String>{appPackage};
  final pending = <String>[
    ...dependencies[appPackage]!,
    ...development[appPackage]!,
  ];
  while (pending.isNotEmpty) {
    final name = pending.removeLast();
    if (!seen.add(name)) continue;
    pending.addAll(dependencies[name] ?? const <String>[]);
  }
  return seen;
}

List<String> _names(Object? value) => <String>[
  if (value is List)
    for (final entry in value)
      if (entry is String) entry,
];

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
