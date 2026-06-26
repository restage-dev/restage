// Prepare a workspace package for publishing to pub.dev.
//
// This repository is a Dart/Flutter workspace: every package pubspec carries
// `publish_to: none` + `resolution: workspace` and refers to its siblings with
// local `path:` dependencies. pub.dev is not a workspace, so a package can't be
// published as-authored. This script rewrites a single package's pubspec (in
// place) into a publishable form:
//
//   1. strip the `publish_to: none` and `resolution: workspace` lines;
//   2. replace each `path:` dependency on a published sibling with a hosted
//      caret constraint pinned to that sibling's current version (read live
//      from the workspace);
//   3. drop any `path:` dependency on a package that is NOT published to
//      pub.dev (an internal-only tool) — consumers couldn't resolve it;
//   4. for a few packages whose tests pull in build tooling, write a
//      `.pubignore` that excludes `test/` from the published archive.
//
// It is intentionally dependency-free (only `dart:io`) so it runs from a clean
// checkout with no `pub get`/bootstrap. It edits text line-by-line rather than
// round-tripping YAML, so comments and formatting survive untouched.
//
// Usage:
//   dart run tool/publish_prepare.dart <package-name> [--root <workspace-root>]
//
// `<package-name>` is a directory under `<root>/packages/`. `--root` defaults to
// the current directory (the workspace root in CI).

import 'dart:io';

/// The packages this script prepares — every package that is published to
/// pub.dev. A `path:` dependency on one of these is rewritten to a hosted
/// constraint; a `path:` dependency on anything else is dropped (it is not a
/// published package and so can't be resolved from pub.dev). Add a package here
/// when it starts publishing.
const _publishable = <String>{
  'restage',
  'restage_core',
  'restage_material',
  'restage_cupertino',
  'rfw_catalog_schema',
  'restage_shared',
  'restage_codegen',
  'rfw_catalog_compiler',
  'restage_a2ui',
};

/// Packages whose `test/` directory must NOT ship in the published archive
/// (their tests import build tooling that is not a runtime dependency).
const _excludeTests = <String>{
  'restage',
  'restage_a2ui',
  'restage_material',
  'restage_cupertino',
};

void main(List<String> args) {
  final positional = <String>[];
  var root = Directory.current.path;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--root') {
      if (i + 1 >= args.length) _fail('--root requires a value');
      root = args[++i];
    } else {
      positional.add(args[i]);
    }
  }
  if (positional.length != 1) {
    _fail(
      'usage: dart run tool/publish_prepare.dart '
      '<package-name> [--root <dir>]',
    );
  }
  final pkg = positional.single;
  if (!_publishable.contains(pkg)) {
    _fail(
      '"$pkg" is not a publishable package '
      '(known: ${_publishable.join(', ')})',
    );
  }

  final packagesDir = Directory('$root/packages');
  if (!packagesDir.existsSync()) {
    _fail('no packages/ directory under "$root"');
  }

  final versions = _readVersionMap(packagesDir);
  final pkgDir = '$root/packages/$pkg';

  // 1. Transform the package's own pubspec.
  _transformPubspec(
    path: '$pkgDir/pubspec.yaml',
    versions: versions,
    // Main pubspecs keep no path deps at all.
    keepPaths: const <String>{},
    label: pkg,
  );

  // 2. Drop test/ from the archive where the package's tests need build tooling.
  if (_excludeTests.contains(pkg)) {
    _appendPubignore('$pkgDir/.pubignore', 'test/');
  }

  // 3. A bundled example sub-package keeps a `path: ../` dependency on its own
  //    parent (which resolves to the bundled package during the parent's
  //    publish); only its other workspace siblings are swapped to hosted.
  final examplePubspec = File('$pkgDir/example/pubspec.yaml');
  if (examplePubspec.existsSync()) {
    _transformPubspec(
      path: examplePubspec.path,
      versions: versions,
      keepPaths: {pkg},
      label: '$pkg/example',
    );
  }

  stdout.writeln('publish_prepare: prepared $pkg');
}

/// Reads `name` → `version` for every package in the workspace.
Map<String, String> _readVersionMap(Directory packagesDir) {
  final map = <String, String>{};
  for (final entry in packagesDir.listSync()) {
    if (entry is! Directory) continue;
    final pubspec = File('${entry.path}/pubspec.yaml');
    if (!pubspec.existsSync()) continue;
    String? name;
    String? version;
    for (final line in pubspec.readAsLinesSync()) {
      final n = RegExp(r'^name:\s+(\S+)\s*$').firstMatch(line);
      if (n != null) name = n.group(1);
      final v = RegExp(r'^version:\s+(\S+)\s*$').firstMatch(line);
      if (v != null) version = v.group(1);
    }
    if (name != null && version != null) map[name] = version;
  }
  return map;
}

void _transformPubspec({
  required String path,
  required Map<String, String> versions,
  required Set<String> keepPaths,
  required String label,
}) {
  final file = File(path);
  if (!file.existsSync()) _fail('missing pubspec: $path');
  final lines = file.readAsLinesSync();
  final out = <String>[];

  final stripPublishTo = RegExp(r'^publish_to:\s*none\s*$');
  final stripResolution = RegExp(r'^resolution:\s*workspace\s*$');
  // A bare, indented mapping key with no inline value, e.g. `  restage_core:`.
  final keyLine = RegExp(r'^(\s+)([A-Za-z_][A-Za-z0-9_]*):\s*$');
  final pathLine = RegExp(r'^\s+path:\s*\S');

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (stripPublishTo.hasMatch(line) || stripResolution.hasMatch(line)) {
      continue;
    }

    final key = keyLine.firstMatch(line);
    final isPathDep =
        key != null && i + 1 < lines.length && pathLine.hasMatch(lines[i + 1]);
    if (isPathDep) {
      final indent = key.group(1)!;
      final name = key.group(2)!;
      i++; // consume the `path:` line
      if (keepPaths.contains(name)) {
        out
          ..add(line)
          ..add(lines[i]); // keep the path dep verbatim
        continue;
      }
      if (!_publishable.contains(name)) {
        continue; // not a published package — drop the dependency entirely
      }
      final version = versions[name];
      if (version == null) {
        _fail('$label: no workspace version found for path dep "$name"');
      }
      out.add('$indent$name: ^$version');
      continue;
    }

    out.add(line);
  }

  final result = out.join('\n');
  _assertPublishable(result, label: label, keepPaths: keepPaths);
  file.writeAsStringSync('$result\n');
}

/// Post-conditions that must hold for the rewritten pubspec, so a transform bug
/// fails the build instead of shipping a broken package.
void _assertPublishable(
  String content, {
  required String label,
  required Set<String> keepPaths,
}) {
  if (content.contains('publish_to: none')) {
    _fail('$label: publish_to: none survived the transform');
  }
  if (content.contains('resolution: workspace')) {
    _fail('$label: resolution: workspace survived the transform');
  }
  // No filesystem `path:` dependency may remain, except the intentionally-kept
  // ones (an example sub-package depending on its own bundled parent). Match a
  // relative/absolute path value (`../`, `./`, `/`) so the `path` *package*
  // version constraint (`path: ^1.9.0`) is not a false positive.
  final pathDep = RegExp(r'^\s+path:\s+(\.\.?/|/)');
  for (final raw in content.split('\n')) {
    if (!pathDep.hasMatch(raw)) continue;
    // The example sub-package keeps exactly its bundled-parent path dep.
    if (keepPaths.isNotEmpty) continue;
    _fail('$label: an unresolved path dependency survived: ${raw.trim()}');
  }
}

void _appendPubignore(String path, String entry) {
  final file = File(path);
  final existing = file.existsSync() ? file.readAsLinesSync() : <String>[];
  if (existing.contains(entry)) return;
  final buffer = StringBuffer();
  if (existing.isNotEmpty) {
    buffer.writeln(existing.join('\n'));
  }
  buffer.writeln(entry);
  file.writeAsStringSync(buffer.toString());
}

Never _fail(String message) {
  stderr.writeln('publish_prepare: $message');
  exit(1);
}
