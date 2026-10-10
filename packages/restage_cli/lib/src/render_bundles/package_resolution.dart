import 'dart:convert';
import 'dart:io';

import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Why an app's package resolution could not be read.
enum PackageResolutionFailure {
  /// No package configuration resolves the app.
  unresolved,

  /// The package graph beside the configuration is missing.
  graphMissing,

  /// The package graph cannot be read.
  graphUnreadable,

  /// The package graph does not list the app.
  notInGraph,
}

/// Thrown when an app's package resolution cannot be read.
final class PackageResolutionException implements Exception {
  /// Construct with the [failure].
  const PackageResolutionException(this.failure);

  /// What went wrong.
  final PackageResolutionFailure failure;

  @override
  String toString() => 'PackageResolutionException(${failure.name})';
}

/// The packages an app resolved: `.dart_tool/package_config.json` and the
/// `package_graph.json` beside it.
final class PackageResolution {
  PackageResolution._(this.config, this.toolDirectory);

  /// Reads the resolution that serves [projectRoot].
  ///
  /// The nearest `.dart_tool/package_config.json` from [projectRoot] up is
  /// used. One found in an ancestor, such as a workspace root, must map
  /// [appName] (read from the pubspec when omitted) to [projectRoot].
  static Future<PackageResolution> read(
    Directory projectRoot, {
    String? appName,
  }) async {
    const unresolved = PackageResolutionException(
      PackageResolutionFailure.unresolved,
    );
    final String project;
    try {
      project = p.normalize(projectRoot.resolveSymbolicLinksSync());
    } on FileSystemException {
      throw unresolved;
    }
    var home = project;
    while (FileSystemEntity.typeSync(
          p.join(home, '.dart_tool', 'package_config.json'),
          followLinks: false,
        ) ==
        FileSystemEntityType.notFound) {
      final parent = p.dirname(home);
      if (parent == home) throw unresolved;
      home = parent;
    }
    final toolDirectory = Directory(p.join(home, '.dart_tool'));
    final file = File(p.join(toolDirectory.path, 'package_config.json'));
    if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw unresolved;
    }
    final PackageConfig config;
    try {
      config = await loadPackageConfig(file);
    } on Object {
      throw unresolved;
    }
    if (config.version < 2) throw unresolved;
    final resolution = PackageResolution._(config, toolDirectory);
    if (home != project) {
      final String name;
      try {
        name = appName ?? readProjectPackageName(Directory(project));
      } on StateError {
        throw unresolved;
      }
      final root = resolution.rootOf(name);
      if (root == null || !p.equals(root, project)) throw unresolved;
    }
    return resolution;
  }

  /// The resolved configuration.
  final PackageConfig config;

  /// The `.dart_tool` directory the configuration was read from.
  final Directory toolDirectory;

  /// The directory [name] resolves to, symbolic links resolved, or null when
  /// it is not resolved to a local directory.
  String? rootOf(String name) {
    final package = config[name];
    if (package == null || !package.root.isScheme('file')) return null;
    final directory = Directory.fromUri(package.root);
    try {
      return p.normalize(directory.resolveSymbolicLinksSync());
    } on FileSystemException {
      return p.normalize(directory.absolute.path);
    }
  }

  /// Whether [name] ships with the Flutter SDK the resolution was made with.
  bool isSdkPackage(String name) {
    final flutterRoot = config.extraData is Map
        ? (config.extraData as Map)['flutterRoot']
        : null;
    final root = rootOf(name);
    if (flutterRoot is! String || root == null) return false;
    final sdk = Uri.tryParse(flutterRoot);
    if (sdk == null || !sdk.isScheme('file')) return false;
    return p.isWithin(p.normalize(sdk.toFilePath()), root);
  }

  /// [appName] and every package it depends on, transitively.
  ///
  /// With [includeDev], the app's own development dependencies count too.
  Set<String> closure(String appName, {bool includeDev = false}) {
    final graph = _graph();
    final app = graph[appName];
    if (app == null) {
      throw const PackageResolutionException(
        PackageResolutionFailure.notInGraph,
      );
    }
    final seen = <String>{appName};
    final pending = <String>[
      ...app.dependencies,
      if (includeDev) ...app.devDependencies,
    ];
    while (pending.isNotEmpty) {
      final name = pending.removeLast();
      if (!seen.add(name)) continue;
      pending.addAll(graph[name]?.dependencies ?? const <String>[]);
    }
    return seen;
  }

  /// The runtime dependencies [name] declares directly.
  List<String> dependenciesOf(String name) {
    final entry = _graph()[name];
    if (entry == null) {
      throw const PackageResolutionException(
        PackageResolutionFailure.notInGraph,
      );
    }
    return entry.dependencies;
  }

  Map<String, ({List<String> dependencies, List<String> devDependencies})>?
  _cachedGraph;

  Map<String, ({List<String> dependencies, List<String> devDependencies})>
  _graph() {
    final cached = _cachedGraph;
    if (cached != null) return cached;
    final file = File(p.join(toolDirectory.path, 'package_graph.json'));
    if (!file.existsSync()) {
      throw const PackageResolutionException(
        PackageResolutionFailure.graphMissing,
      );
    }
    final Object? document;
    try {
      document = jsonDecode(file.readAsStringSync());
    } on FormatException {
      throw const PackageResolutionException(
        PackageResolutionFailure.graphUnreadable,
      );
    }
    final entries = document is Map ? document['packages'] : null;
    if (entries is! List) {
      throw const PackageResolutionException(
        PackageResolutionFailure.graphUnreadable,
      );
    }
    return _cachedGraph = {
      for (final entry in entries)
        if (entry is Map && entry['name'] is String)
          entry['name'] as String: (
            dependencies: _names(entry['dependencies']),
            devDependencies: _names(entry['devDependencies']),
          ),
    };
  }
}

List<String> _names(Object? value) => <String>[
  if (value is List)
    for (final entry in value)
      if (entry is String) entry,
];

/// Reads the package name the project's pubspec declares.
String readProjectPackageName(Directory projectRoot) {
  final pubspec = File(p.join(projectRoot.path, 'pubspec.yaml'));
  if (FileSystemEntity.typeSync(pubspec.path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw StateError('project package identity unavailable');
  }
  final Object? document;
  try {
    document = loadYaml(pubspec.readAsStringSync());
  } on Object {
    throw StateError('project package identity unavailable');
  }
  if (document is! YamlMap ||
      document['name'] is! String ||
      !RegExp(r'^[a-z_][a-z0-9_]*$').hasMatch(document['name']! as String)) {
    throw StateError('project package identity unavailable');
  }
  return document['name']! as String;
}

/// The app's version name and build number from the pubspec's `version`
/// field (`1.4.0+42` reads as `1.4.0` and 42); each is null when absent.
({String? name, int? build}) readProjectAppVersion(Directory projectRoot) {
  try {
    final document = loadYaml(
      File(p.join(projectRoot.path, 'pubspec.yaml')).readAsStringSync(),
    );
    final version = document is YamlMap ? document['version'] : null;
    if (version is! String) return (name: null, build: null);
    final plus = version.indexOf('+');
    final name = (plus < 0 ? version : version.substring(0, plus)).trim();
    final build = plus < 0 ? null : int.tryParse(version.substring(plus + 1));
    return (
      name: name.isEmpty || name.length > 64 ? null : name,
      build: build == null || build < 0 || build > 0x7fffffff ? null : build,
    );
  } on Object {
    return (name: null, build: null);
  }
}
