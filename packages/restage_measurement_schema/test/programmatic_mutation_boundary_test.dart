import 'dart:io';

import 'package:test/test.dart';

/// Source-level hygiene of this package, asserted over its own files.
///
/// These checks read `lib/` and `pubspec.yaml` from the package root, so they
/// only mean anything from inside this package.
///
/// The invariant is stated positively — what this package may rest on — rather
/// than as a list of neighbours to avoid. A denylist has to name what it
/// excludes, and it passes the moment a new neighbour appears.
///
/// Three ways a reference can hide from a naive scan, each of which was found
/// to slip through an earlier version of this test and each of which now has a
/// permanent control below:
///
///   * a double-quoted directive, when the scan only matched single quotes;
///   * a relative path that climbs out of `lib/` into a sibling package,
///     because it carries no `package:` scheme to notice;
///   * the second and later URIs of a conditional import, when the scan stopped
///     at the first quoted string in the directive.
const _allowedRuntimeDependencies = {'crypto'};
const _allowedDevDependencies = {'test'};

const _allowedImportPrefixes = {
  'dart:',
  'package:crypto/',
  'package:restage_measurement_schema/',
};

void main() {
  final packageRoot = Directory.current.path;

  test('runtime dependencies are exactly the declared floor', () {
    final pubspec = File('$packageRoot/pubspec.yaml').readAsLinesSync();

    expect(
      _blockEntries(pubspec, 'dependencies'),
      _allowedRuntimeDependencies,
      reason: 'A new runtime dependency widens what ships to every consumer.',
    );
    expect(
      _blockEntries(pubspec, 'dev_dependencies'),
      _allowedDevDependencies,
      reason: 'A new dev dependency widens what the published contract needs.',
    );
  });

  test('every library reference resolves inside the allowed floor', () {
    final libraryRoot = '$packageRoot/lib';
    final offenders = <String>[];

    for (final file in _librarySources(packageRoot)) {
      for (final reference in referencedUris(file.readAsStringSync())) {
        final reason = violationFor(
          reference: reference,
          sourcePath: file.path,
          libraryRoot: libraryRoot,
        );
        if (reason != null) {
          final relativePath = file.path.substring(packageRoot.length + 1);
          offenders.add('$relativePath -> $reference ($reason)');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'These references leave the allowed dependency floor.',
    );
  });

  test('the published licence is the permissive one consumers expect', () {
    final licence = File('$packageRoot/LICENSE').readAsStringSync();

    expect(licence, startsWith('BSD 3-Clause License'));
  });

  group('the scan sees references that hide from a naive one', () {
    // Each case below is a reference that a previous version of this test read
    // as clean. They are kept as inputs to the scanner rather than as files on
    // disk, so the capability stays pinned even if the tree changes.

    test('a double-quoted directive is scanned like a single-quoted one', () {
      const source = 'import "package:acme_private_engine/engine.dart";\n';

      expect(referencedUris(source), [
        'package:acme_private_engine/engine.dart',
      ]);
      expect(
        violationFor(
          reference: 'package:acme_private_engine/engine.dart',
          sourcePath: '/pkg/lib/src/a.dart',
          libraryRoot: '/pkg/lib',
        ),
        isNotNull,
      );
    });

    test('a relative path that climbs out of lib is a violation', () {
      const reference = '../../../acme_private_engine/lib/src/x.dart';

      expect(
        violationFor(
          reference: reference,
          sourcePath: '/pkg/lib/src/a.dart',
          libraryRoot: '/pkg/lib',
        ),
        isNotNull,
        reason: 'It carries no scheme, but it leaves the package.',
      );
    });

    test('a relative path that stays inside lib is allowed', () {
      expect(
        violationFor(
          reference: '../canonical.dart',
          sourcePath: '/pkg/lib/src/a.dart',
          libraryRoot: '/pkg/lib',
        ),
        isNull,
      );
    });

    test('every URI of a conditional import is scanned', () {
      const source = "import 'stub.dart'\n"
          "    if (dart.library.io) 'package:acme_private_engine/io.dart'\n"
          "    if (dart.library.js) 'web.dart';\n";

      expect(referencedUris(source), [
        'stub.dart',
        'package:acme_private_engine/io.dart',
        'web.dart',
      ]);
    });
  });
}

/// Every Dart source file that ships in the published package.
Iterable<File> _librarySources(String packageRoot) =>
    Directory('$packageRoot/lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

/// Every URI an `import`, `export`, or `part` directive names.
///
/// Reads the whole directive up to its semicolon and yields *all* of its
/// quoted strings, so conditional-import branches are not missed, and accepts
/// either quote style.
List<String> referencedUris(String source) {
  final directive = RegExp(
    r'^[ \t]*(?:import|export|part)\b[^;]*;',
    multiLine: true,
  );
  final quoted = RegExp(r'''(['"])([^'"]*)\1''');

  return [
    for (final statement in directive.allMatches(source))
      for (final uri in quoted.allMatches(statement.group(0)!)) uri.group(2)!,
  ];
}

/// Why [reference] leaves the allowed floor, or null when it is fine.
String? violationFor({
  required String reference,
  required String sourcePath,
  required String libraryRoot,
}) {
  if (reference.contains(':')) {
    final allowed = _allowedImportPrefixes.any(reference.startsWith);
    return allowed ? null : 'outside the allowed dependency floor';
  }

  // No scheme: a path relative to the importing file. Resolve it and confirm
  // it still lands inside this package's own lib/.
  final directory = sourcePath.substring(0, sourcePath.lastIndexOf('/'));
  final resolved = Uri.file('$directory/').resolve(reference).toFilePath();
  final root = libraryRoot.endsWith('/') ? libraryRoot : '$libraryRoot/';

  return resolved.startsWith(root) ? null : 'escapes lib/ to $resolved';
}

/// The set of keys nested directly under a top-level `pubspec.yaml` block.
Set<String> _blockEntries(List<String> pubspecLines, String blockName) {
  final entries = <String>{};
  final entry = RegExp(r'^  ([A-Za-z_][A-Za-z0-9_]*)\s*:');
  var inBlock = false;

  for (final line in pubspecLines) {
    if (line.trimRight() == '$blockName:') {
      inBlock = true;
      continue;
    }
    if (!inBlock) continue;
    if (line.trim().isEmpty) continue;
    // A line at column zero ends the block.
    if (!line.startsWith(' ')) break;

    final match = entry.firstMatch(line);
    if (match != null) entries.add(match.group(1)!);
  }

  return entries;
}
