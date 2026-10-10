import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:restage_cli/src/receipts/git_repository.dart';
import 'package:restage_cli/src/receipts/source_boundary.dart';
import 'package:test/test.dart';

/// A repository rooted at [root], answered without running Git.
Future<GitRepository> _repository(Directory root) async {
  final resolved = root.resolveSymbolicLinksSync();
  final repository = await GitRepository.open(
    root,
    processRunner: (executable, arguments, {workingDirectory}) async =>
        ProcessResult(0, 0, '$resolved\n', ''),
  );
  return repository!;
}

void _write(Directory root, String relative, String contents) {
  File(p.join(root.path, relative))
    ..createSync(recursive: true)
    ..writeAsStringSync(contents);
}

void _writePackageConfig(Directory root, Map<String, String> rootUriByName) {
  _write(
    root,
    p.join('.dart_tool', 'package_config.json'),
    jsonEncode({
      'configVersion': 2,
      'packages': [
        for (final entry in rootUriByName.entries)
          {
            'name': entry.key,
            'rootUri': entry.value,
            'packageUri': 'lib/',
            'languageVersion': '3.8',
          },
      ],
    }),
  );
}

void _writeGraph(Directory root, Map<String, (List<String>, List<String>)> of) {
  _write(
    root,
    p.join('.dart_tool', 'package_graph.json'),
    jsonEncode({
      'configVersion': 1,
      'roots': of.keys.toList(),
      'packages': [
        for (final entry in of.entries)
          {
            'name': entry.key,
            'dependencies': entry.value.$1,
            'devDependencies': entry.value.$2,
          },
      ],
    }),
  );
}

void _writeLock(Directory root, Map<String, String> sourceByName) {
  final buffer = StringBuffer('packages:\n');
  for (final entry in sourceByName.entries) {
    buffer
      ..writeln('  ${entry.key}:')
      ..writeln('    dependency: transitive')
      ..writeln('    source: ${entry.value}')
      ..writeln('    version: "1.0.0"');
  }
  _write(root, 'pubspec.lock', buffer.toString());
}

void main() {
  late Directory root;
  late Directory app;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('receipts_boundary_');
    app = Directory(p.join(root.path, 'apps', 'app'))
      ..createSync(recursive: true);
    _write(root, p.join('apps', 'app', 'pubspec.yaml'), 'name: demo_app\n');
    _write(root, p.join('packages', 'ui', 'pubspec.yaml'), 'name: ui\n');
    _write(root, p.join('packages', 'spare', 'pubspec.yaml'), 'name: spare\n');
    _write(root, p.join('packages', 'builder', 'pubspec.yaml'), 'name: bld\n');
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('covers the app and the packages it depends on here', () async {
    _writePackageConfig(root, {
      'demo_app': '../apps/app',
      'ui': '../packages/ui',
    });
    _writeGraph(root, {
      'demo_app': (['ui'], []),
      'ui': ([], []),
    });
    _writeLock(root, {});

    final boundary = await resolveSourceBoundary(
      projectRoot: app,
      repository: await _repository(root),
    );

    expect(boundary.packages, ['apps/app', 'packages/ui']);
  });

  test('leaves out a package here that the app does not depend on', () async {
    _writePackageConfig(root, {
      'demo_app': '../apps/app',
      'ui': '../packages/ui',
      'spare': '../packages/spare',
    });
    _writeGraph(root, {
      'demo_app': (['ui'], []),
      'ui': ([], []),
      'spare': ([], []),
    });
    _writeLock(root, {});

    final boundary = await resolveSourceBoundary(
      projectRoot: app,
      repository: await _repository(root),
    );

    expect(boundary.packages, isNot(contains('packages/spare')));
  });

  test('counts the development dependencies that run the build', () async {
    _writePackageConfig(root, {
      'demo_app': '../apps/app',
      'bld': '../packages/builder',
    });
    _writeGraph(root, {
      'demo_app': ([], ['bld']),
      'bld': ([], []),
    });
    _writeLock(root, {});

    final boundary = await resolveSourceBoundary(
      projectRoot: app,
      repository: await _repository(root),
    );

    expect(boundary.packages, contains('packages/builder'));
  });

  test('ignores a package the lockfile pins outside the repository', () async {
    final cache = await Directory.systemTemp.createTemp('receipts_cache_');
    addTearDown(() => cache.deleteSync(recursive: true));
    _writePackageConfig(root, {
      'demo_app': '../apps/app',
      'args': cache.uri.toString(),
    });
    _writeGraph(root, {
      'demo_app': (['args'], []),
      'args': ([], []),
    });
    _writeLock(root, {'args': 'hosted'});

    final boundary = await resolveSourceBoundary(
      projectRoot: app,
      repository: await _repository(root),
    );

    expect(boundary.packages, ['apps/app']);
  });

  test('refuses a package outside the repository nothing pins', () async {
    final elsewhere = await Directory.systemTemp.createTemp('receipts_other_');
    addTearDown(() => elsewhere.deleteSync(recursive: true));
    _writePackageConfig(root, {
      'demo_app': '../apps/app',
      'sibling': elsewhere.uri.toString(),
    });
    _writeGraph(root, {
      'demo_app': (['sibling'], []),
      'sibling': ([], []),
    });
    _writeLock(root, {'sibling': 'path'});

    final repository = await _repository(root);

    expect(
      () => resolveSourceBoundary(projectRoot: app, repository: repository),
      throwsA(
        isA<SourceBoundaryException>().having(
          (e) => e.message,
          'message',
          allOf(contains('sibling'), contains('outside the repository')),
        ),
      ),
    );
  });

  test('refuses when the resolved package graph is not on disk', () async {
    _writePackageConfig(root, {
      'demo_app': '../apps/app',
      'ui': '../packages/ui',
      'spare': '../packages/spare',
    });
    _writeLock(root, {});

    final repository = await _repository(root);

    expect(
      () => resolveSourceBoundary(projectRoot: app, repository: repository),
      throwsA(
        isA<SourceBoundaryException>().having(
          (e) => e.message,
          'message',
          allOf(contains('package graph'), contains('dart pub get')),
        ),
      ),
    );
  });

  test('refuses when the packages are not resolved', () async {
    final repository = await _repository(root);

    expect(
      () => resolveSourceBoundary(projectRoot: app, repository: repository),
      throwsA(
        isA<SourceBoundaryException>().having(
          (e) => e.message,
          'message',
          contains('dart pub get'),
        ),
      ),
    );
  });

  test('refuses when there is no lockfile to read sources from', () async {
    _writePackageConfig(root, {'demo_app': '../apps/app'});
    _writeGraph(root, {'demo_app': ([], [])});

    final repository = await _repository(root);

    expect(
      () => resolveSourceBoundary(projectRoot: app, repository: repository),
      throwsA(
        isA<SourceBoundaryException>().having(
          (e) => e.message,
          'message',
          contains('lockfile'),
        ),
      ),
    );
  });
}
