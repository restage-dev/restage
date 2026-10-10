import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:restage_cli/src/api/selector_syntax.dart';
import 'package:restage_cli/src/render_bundles/flutter_render_bundle_builder.dart'
    show RenderBundleProcessRunner, runRenderBundleProcess;

/// The Flutter SDK a build runs on, and where it was found.
final class FlutterToolchain {
  const FlutterToolchain({
    required this.executable,
    required this.source,
    required this.version,
  });

  /// The SDK's `bin/flutter`.
  final String executable;

  /// Where the SDK was found, as a reader would name it.
  final String source;

  /// The framework version the SDK reports.
  final String version;

  /// The SDK directory.
  String get root => p.dirname(p.dirname(executable));
}

/// No Flutter SDK a build can use was found.
final class FlutterToolchainException implements Exception {
  const FlutterToolchainException(this.message);

  /// The sentence to show, including how to fix it.
  final String message;

  @override
  String toString() => message;
}

/// Finds the Flutter SDK a build runs on.
typedef FlutterToolchainResolver =
    Future<FlutterToolchain> Function({
      required Directory projectRoot,
      String? flagRoot,
      String? configRoot,
    });

/// Finds the Flutter SDK the app uses. A build runs on whatever version it is.
///
/// A root named by [flagRoot] or [configRoot] is used as given. Otherwise the
/// first SDK found wins: the project's FVM link, its `.fvmrc` or
/// `.flutter-version` pin in the FVM cache, `FLUTTER_ROOT`, then `PATH`.
Future<FlutterToolchain> resolveBuildFlutterToolchain({
  required Directory projectRoot,
  String? flagRoot,
  String? configRoot,
  Map<String, String>? environment,
  RenderBundleProcessRunner? processRunner,
}) async {
  final env = environment ?? Platform.environment;
  final run = processRunner ?? runRenderBundleProcess;
  final explicit = flagRoot != null
      ? (root: flagRoot, source: _flagSource)
      : configRoot != null
      ? (root: configRoot, source: 'flutterRoot in restage_config.yaml')
      : null;
  if (explicit != null) {
    final root = _expandHome(explicit.root, env);
    final executable = _executableIn(root);
    if (executable == null) {
      throw FlutterToolchainException(
        'No Flutter SDK at $root (${explicit.source}). ${flutterRootFix()}',
      );
    }
    final version = await _versionOf(executable, run);
    if (version == null) {
      throw FlutterToolchainException(
        'The Flutter at $root (${explicit.source}) did not report its '
        'version. ${flutterRootFix()}',
      );
    }
    return FlutterToolchain(
      executable: executable,
      source: explicit.source,
      version: version,
    );
  }

  final unreadable = <String>[];
  final seen = <String>{};
  for (final candidate in _implicitCandidates(projectRoot, env)) {
    final executable = _executableIn(candidate.root);
    if (executable == null || !seen.add(executable)) continue;
    final version = await _versionOf(executable, run);
    if (version != null) {
      return FlutterToolchain(
        executable: executable,
        source: candidate.source,
        version: version,
      );
    }
    unreadable.add('${p.dirname(p.dirname(executable))} (${candidate.source})');
  }
  throw FlutterToolchainException(
    unreadable.isEmpty
        ? 'No Flutter SDK was found. ${flutterRootFix()}'
        : 'No Flutter SDK reported its version; tried '
              '${unreadable.join('; ')}. ${flutterRootFix()}',
  );
}

String get _flagSource => currentSelectorSyntax == SelectorSyntax.mcp
    ? 'the flutterRoot argument'
    : '--flutter-root';

/// How to point a build at a different Flutter SDK, worded for the caller.
String flutterRootFix() {
  final syntax = currentSelectorSyntax;
  final build = syntax.command(
    const FollowUp('build push', 'restage_push_build', [
      FollowUpArg('flutterRoot', '<sdk directory>', flag: 'flutter-root'),
    ]),
  );
  return 'To build with a different Flutter, ${syntax.run.toLowerCase()} '
      '$build, set `flutterRoot` in restage_config.yaml, or set FLUTTER_ROOT.';
}

Iterable<({String root, String source})> _implicitCandidates(
  Directory projectRoot,
  Map<String, String> env,
) sync* {
  final home = env['HOME'] ?? env['USERPROFILE'];
  final caches = <String>[
    if (env['FVM_CACHE_PATH'] case final cache? when cache.isNotEmpty) cache,
    if (home != null) p.join(home, 'fvm'),
  ];
  var current = projectRoot.absolute;
  while (true) {
    final link = p.join(current.path, '.fvm', 'flutter_sdk');
    yield (root: link, source: 'FVM link at ${p.dirname(link)}');
    for (final pin in const ['.fvmrc', '.flutter-version']) {
      final version = _pinnedVersion(File(p.join(current.path, pin)));
      if (version == null) continue;
      for (final cache in caches) {
        yield (
          root: p.join(cache, 'versions', version),
          source: '$pin at ${current.path}',
        );
      }
    }
    final parent = current.parent;
    if (parent.path == current.path) break;
    current = parent;
  }
  final flutterRoot = env['FLUTTER_ROOT'];
  if (flutterRoot != null && flutterRoot.isNotEmpty) {
    yield (root: flutterRoot, source: 'FLUTTER_ROOT');
  }
  final path = env['PATH'];
  if (path != null) {
    for (final directory in path.split(Platform.isWindows ? ';' : ':')) {
      if (directory.isEmpty) continue;
      yield (root: p.dirname(directory), source: 'PATH');
    }
  }
}

/// The version a `.fvmrc` or `.flutter-version` file pins, if it names one.
String? _pinnedVersion(File file) {
  final String text;
  try {
    if (!file.existsSync()) return null;
    text = file.readAsStringSync();
  } on FileSystemException {
    return null;
  }
  String? version;
  if (p.basename(file.path) == '.fvmrc') {
    try {
      final document = jsonDecode(text);
      if (document is Map<String, dynamic> && document['flutter'] is String) {
        version = document['flutter'] as String;
      }
    } on FormatException {
      return null;
    }
  } else {
    version = text.trim().split(RegExp(r'\s+')).first;
  }
  // Used as a cache directory name, so never a path.
  if (version == null ||
      version.isEmpty ||
      version.startsWith('.') ||
      version.contains('/') ||
      version.contains(r'\')) {
    return null;
  }
  return version;
}

/// The SDK's `bin/flutter` with links resolved, or null when [root] has none.
String? _executableIn(String root) {
  final file = File(
    p.join(root, 'bin', Platform.isWindows ? 'flutter.bat' : 'flutter'),
  );
  if (!file.existsSync()) return null;
  try {
    return file.resolveSymbolicLinksSync();
  } on FileSystemException {
    return null;
  }
}

Future<String?> _versionOf(
  String executable,
  RenderBundleProcessRunner run,
) async {
  try {
    final result = await run(executable, const <String>[
      '--version',
      '--machine',
    ]);
    if (result.exitCode != 0) return null;
    final output = result.stdout as String;
    final start = output.indexOf('{');
    if (start < 0) return null;
    final document = jsonDecode(output.substring(start));
    if (document is! Map<String, dynamic>) return null;
    return document['frameworkVersion'] as String?;
  } on Object {
    return null;
  }
}

String _expandHome(String root, Map<String, String> env) {
  final home = env['HOME'] ?? env['USERPROFILE'];
  if (home == null) return root;
  if (root == '~') return home;
  if (root.startsWith('~/')) return p.join(home, root.substring(2));
  return root;
}
