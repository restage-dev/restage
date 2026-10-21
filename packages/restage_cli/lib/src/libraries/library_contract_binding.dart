import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:restage_shared/restage_shared.dart';

/// One library contract a push bound.
@experimental
@immutable
final class BoundLibraryContract {
  /// Construct one binding.
  const BoundLibraryContract({
    required this.namespace,
    required this.version,
    required this.file,
  });

  /// The library namespace.
  final String namespace;

  /// The capability version bound.
  final int version;

  /// The snapshot file written.
  final File file;
}

/// Binds the drafted contract of each library version in [required], which
/// maps namespace to capability version.
///
/// A draft is looked for under [projectRoot] and every package it depends on
/// by path. A version already bound stays as it is. A library with no draft,
/// such as one from a package on pub.dev, is left to its own package.
@experimental
List<BoundLibraryContract> bindLibraryContracts({
  required Directory projectRoot,
  required Map<String, int> required,
}) {
  if (required.isEmpty) return const [];
  final roots = _sourceRoots(projectRoot);
  final bound = <BoundLibraryContract>[];
  for (final MapEntry(key: namespace, value: version) in required.entries) {
    final name = '$namespace/v$version.json';
    if (roots.any(
      (root) => File(
        p.join(root, libraryContractSnapshotDirectory, name),
      ).existsSync(),
    )) {
      continue;
    }
    for (final root in roots) {
      final draft = File(p.join(root, libraryContractDraftDirectory, name));
      if (!draft.existsSync()) continue;
      bound.add(_record(root, draft, namespace, version));
      break;
    }
  }
  return bound;
}

/// What `restage library record` did in one package.
@experimental
@immutable
final class LibraryRecordResult {
  /// Construct a result.
  const LibraryRecordResult({
    required this.recorded,
    required this.alreadyRecorded,
  });

  /// The contracts recorded now.
  final List<BoundLibraryContract> recorded;

  /// Drafted versions that were recorded before, as namespace and version.
  final List<(String, int)> alreadyRecorded;

  /// Whether the last build drafted nothing.
  bool get isEmpty => recorded.isEmpty && alreadyRecorded.isEmpty;
}

/// Records every contract the last build drafted under [packageRoot] that is
/// not recorded yet, so a package can bind its libraries before it is
/// published.
@experimental
LibraryRecordResult recordLibraryDrafts(Directory packageRoot) {
  final root = p.normalize(packageRoot.absolute.path);
  final drafts = Directory(p.join(root, libraryContractDraftDirectory));
  final recorded = <BoundLibraryContract>[];
  final already = <(String, int)>[];
  if (drafts.existsSync()) {
    final namespaces = drafts.listSync().whereType<Directory>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final directory in namespaces) {
      final namespace = p.basename(directory.path);
      for (final draft in directory.listSync().whereType<File>()) {
        final version = libraryContractSnapshotVersion(p.basename(draft.path));
        if (version == null) continue;
        if (File(
          p.join(
            root,
            libraryContractSnapshotDirectory,
            namespace,
            'v$version.json',
          ),
        ).existsSync()) {
          already.add((namespace, version));
        } else {
          recorded.add(_record(root, draft, namespace, version));
        }
      }
    }
  }
  return LibraryRecordResult(recorded: recorded, alreadyRecorded: already);
}

/// The directory of the package that holds [start]: the nearest one with a
/// pubspec.yaml, or [start] when there is none.
@experimental
Directory libraryPackageRoot(Directory start) {
  var current = p.normalize(start.absolute.path);
  while (!File(p.join(current, 'pubspec.yaml')).existsSync()) {
    final parent = p.dirname(current);
    if (parent == current) return start.absolute;
    current = parent;
  }
  return Directory(current);
}

/// The JSON form of [result].
@experimental
Map<String, Object?> libraryRecordJson(LibraryRecordResult result) => {
  'recorded': [
    for (final contract in result.recorded)
      {
        'namespace': contract.namespace,
        'version': contract.version,
        'path': contract.file.path,
      },
  ],
  'alreadyRecorded': [
    for (final (namespace, version) in result.alreadyRecorded)
      {'namespace': namespace, 'version': version},
  ],
};

/// The line that tells the developer [contract] was recorded.
@experimental
String libraryRecordedLine(BoundLibraryContract contract) =>
    'Recorded library ${contract.namespace} v${contract.version} in '
    '${p.relative(contract.file.path)}. Commit it; later changes to the '
    'library need a new capabilityVersion.';

BoundLibraryContract _record(
  String root,
  File draft,
  String namespace,
  int version,
) {
  final contents = draft.readAsStringSync();
  final header = LibraryContractHeader.decode(contents, draft.path);
  if (header.namespace != namespace || header.capabilityVersion != version) {
    throw FormatException(
      '${draft.path} records library `${header.namespace}` '
      'v${header.capabilityVersion}.',
    );
  }
  final file = File(
    p.join(root, libraryContractSnapshotDirectory, namespace, 'v$version.json'),
  );
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
  return BoundLibraryContract(
    namespace: namespace,
    version: version,
    file: file,
  );
}

// The app root first, then each package pub resolved from a local path. Pub
// writes those with a relative root; cached packages get an absolute one.
List<String> _sourceRoots(Directory projectRoot) {
  final app = p.normalize(projectRoot.absolute.path);
  final roots = <String>[app];
  var home = app;
  while (!File(
    p.join(home, '.dart_tool', 'package_config.json'),
  ).existsSync()) {
    final parent = p.dirname(home);
    if (parent == home) return roots;
    home = parent;
  }
  final Object? config;
  try {
    config = jsonDecode(
      File(
        p.join(home, '.dart_tool', 'package_config.json'),
      ).readAsStringSync(),
    );
  } on FormatException {
    return roots;
  }
  final packages = config is Map<String, Object?> ? config['packages'] : null;
  if (packages is! List<Object?>) return roots;
  for (final package in packages) {
    final rootUri = package is Map<String, Object?> ? package['rootUri'] : null;
    if (rootUri is! String) continue;
    final uri = Uri.tryParse(rootUri);
    if (uri == null || uri.hasScheme || uri.path.startsWith('/')) continue;
    final root = p.normalize(p.join(home, '.dart_tool', p.fromUri(uri.path)));
    if (!roots.contains(root)) roots.add(root);
  }
  return roots;
}
