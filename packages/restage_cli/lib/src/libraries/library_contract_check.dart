import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/api/library_requirements_api.dart';
import 'package:restage_cli/src/config/restage_config.dart';
import 'package:restage_shared/restage_shared.dart';

/// The oldest capability version each library in [root] still renders, read
/// from its highest recorded contract snapshot. Empty when there are none.
@experimental
Map<String, int> localCompatibleSince(Directory root) {
  final directory = Directory(
    p.join(root.path, libraryContractSnapshotDirectory),
  );
  if (!directory.existsSync()) return const {};
  final result = <String, int>{};
  for (final entry in directory.listSync()) {
    if (entry is! Directory) continue;
    File? newest;
    var newestVersion = 0;
    for (final file in entry.listSync().whereType<File>()) {
      final version = libraryContractSnapshotVersion(p.basename(file.path));
      if (version != null && version > newestVersion) {
        newest = file;
        newestVersion = version;
      }
    }
    if (newest == null) continue;
    final header = LibraryContractHeader.decode(
      newest.readAsStringSync(),
      p.relative(newest.path, from: root.path),
    );
    result[header.namespace] = header.compatibleSince;
  }
  return result;
}

/// One live version this build would stop rendering.
@experimental
@immutable
final class LibraryBreak {
  /// Construct one finding.
  const LibraryBreak({
    required this.version,
    required this.namespace,
    required this.minVersion,
    required this.compatibleSince,
  });

  /// The live version.
  final LiveVersionRequirements version;

  /// The library it needs.
  final String namespace;

  /// The library version it needs.
  final int minVersion;

  /// The oldest library version this build renders.
  final int compatibleSince;

  /// The line naming this finding.
  String get sentence {
    final v = version;
    final surface =
        '${v.surfaceType} ${v.surfaceSlug} '
        'v${v.publishedRevision}${v.versionLabel == null ? '' : ' (${v.versionLabel})'}';
    final needs =
        'needs library $namespace v$minVersion. '
        'This build renders v$compatibleSince and later.';
    return switch (v.kind) {
      LiveVersionKind.experimentArm =>
        'Experiment ${v.experimentLabel ?? v.experimentId} '
            'arm ${v.armLabel ?? v.armId} ($surface) $needs',
      LiveVersionKind.deliveryRule =>
        'Delivery rule ${v.routeId} ($surface) $needs',
      LiveVersionKind.serving => 'Serving $surface $needs',
    };
  }
}

/// Every live version whose required library version this build no longer
/// renders, in environment order.
@experimental
List<LibraryBreak> findLibraryBreaks({
  required List<LiveVersionRequirements> live,
  required Map<String, int> compatibleSince,
}) {
  final breaks = <LibraryBreak>[];
  for (final version in live) {
    final required = version.requiredLibraries;
    if (required == null) continue;
    for (final MapEntry(key: namespace, value: minVersion)
        in required.entries) {
      final since = compatibleSince[namespace];
      if (since != null && minVersion < since) {
        breaks.add(
          LibraryBreak(
            version: version,
            namespace: namespace,
            minVersion: minVersion,
            compatibleSince: since,
          ),
        );
      }
    }
  }
  final environments = {
    for (final item in breaks) item.version.environment,
  }.toList()..sort();
  return [
    for (final environment in environments)
      ...breaks.where((item) => item.version.environment == environment),
  ];
}

/// The directory holding the app's `.restage` folder: the one with
/// restage_config.yaml, or [start] when there is none.
@experimental
Future<Directory> libraryContractRoot(Directory start) async {
  final loaded = await loadRestageConfig(from: start);
  return loaded?.source.parent ?? start.absolute;
}

/// The JSON form of [breaks].
@experimental
List<Map<String, Object?>> libraryBreaksJson(List<LibraryBreak> breaks) => [
  for (final item in breaks)
    {
      'environment': item.version.environment,
      'kind': item.version.kind.name,
      'surfaceType': item.version.surfaceType,
      'surfaceSlug': item.version.surfaceSlug,
      'publishedRevision': item.version.publishedRevision,
      'versionLabel': item.version.versionLabel,
      'routeId': item.version.routeId,
      'experimentId': item.version.experimentId,
      'experimentLabel': item.version.experimentLabel,
      'armId': item.version.armId,
      'armLabel': item.version.armLabel,
      'namespace': item.namespace,
      'minVersion': item.minVersion,
      'compatibleSince': item.compatibleSince,
      'message': item.sentence,
    },
];
