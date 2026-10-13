import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:restage_cli/src/receipts/git_repository.dart';
import 'package:restage_cli/src/receipts/source_boundary.dart';
import 'package:restage_cli/src/render_bundles/bundle_source.dart';
import 'package:test/test.dart';

/// Writes everything the source boundary needs before it answers: a root
/// `pubspec.yaml`, `.dart_tool/package_config.json` with slash-terminated
/// `rootUri` and a `packageUri`, the `lib/` directories those name, a
/// `pubspec.lock`, and `.dart_tool/package_graph.json`. Miss one and the
/// boundary refuses.
Future<void> seedResolvableBoundary(Directory root) async {
  await File(
    p.join(root.path, 'pubspec.yaml'),
  ).writeAsString('name: demo_app\n');
  await File(
    p.join(root.path, 'packages', 'widgets', 'pubspec.yaml'),
  ).create(recursive: true).then((file) => file.writeAsString('name: kit\n'));
  await Directory(p.join(root.path, 'lib')).create(recursive: true);
  await Directory(
    p.join(root.path, 'packages', 'widgets', 'lib'),
  ).create(recursive: true);
  await File(p.join(root.path, 'pubspec.lock')).writeAsString(
    'packages:\n'
    '  kit:\n'
    '    dependency: "direct main"\n'
    '    source: path\n'
    '    version: "0.0.0"\n',
  );
  final tool = Directory(p.join(root.path, '.dart_tool'));
  await tool.create(recursive: true);
  await File(p.join(tool.path, 'package_graph.json')).writeAsString(
    jsonEncode(<String, Object?>{
      'packages': <Object?>[
        <String, Object?>{
          'name': 'demo_app',
          'dependencies': <String>['kit'],
          'devDependencies': <String>[],
        },
        <String, Object?>{
          'name': 'kit',
          'dependencies': <String>[],
          'devDependencies': <String>[],
        },
      ],
    }),
  );
  await File(p.join(tool.path, 'package_config.json')).writeAsString(
    jsonEncode(<String, Object?>{
      'configVersion': 2,
      'packages': <Object?>[
        <String, Object?>{
          'name': 'demo_app',
          'rootUri': '../',
          'packageUri': 'lib/',
        },
        <String, Object?>{
          'name': 'kit',
          'rootUri': '../packages/widgets/',
          'packageUri': 'lib/',
        },
      ],
    }),
  );
}

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('bundle_source_test_');
    await seedResolvableBoundary(root);
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  /// Answers the commands the reader issues, in Git's own shapes.
  GitProcessRunner git({
    bool repository = true,
    String? commit,
    String status = '',
    int statusExitCode = 0,
  }) => (executable, arguments, {String? workingDirectory}) async {
    final command = arguments.join(' ');
    if (command.startsWith('rev-parse --show-toplevel')) {
      return repository
          ? ProcessResult(0, 0, '${root.path}\n', '')
          : ProcessResult(0, 128, '', 'not a git repository');
    }
    if (command.startsWith('rev-parse --verify --quiet HEAD')) {
      return commit == null
          ? ProcessResult(0, 1, '', '')
          : ProcessResult(0, 0, '$commit\n', '');
    }
    if (command.startsWith('symbolic-ref')) {
      return ProcessResult(0, 0, 'work\n', '');
    }
    if (command.startsWith('status')) {
      return ProcessResult(0, statusExitCode, status, '');
    }
    fail('unexpected command: git $command');
  };

  test('a clean tree answers with its commit', () async {
    final source = await readBundleSource(
      root,
      processRunner: git(commit: 'a91f2c3d4e5f60718293a4b5c6d7e8f901234567'),
    );
    expect(source.inRepository, isTrue);
    expect(source.commit, 'a91f2c3d4e5f60718293a4b5c6d7e8f901234567');
    expect(source.shortCommit, 'a91f2c3');
    expect(source.dirty, isFalse);
    expect(describeBundleSource(source), 'Built from a91f2c3.');
  });

  test('uncommitted content makes the source dirty', () async {
    final source = await readBundleSource(
      root,
      processRunner: git(
        commit: 'a91f2c3d4e5f60718293a4b5c6d7e8f901234567',
        status: ' M lib/main.dart${String.fromCharCode(0)}',
      ),
    );
    expect(source.dirty, isTrue);
    expect(
      describeBundleSource(source),
      'Built from a91f2c3 with local changes.',
    );
  });

  test('no repository answers with no commit and says so', () async {
    final source = await readBundleSource(
      root,
      processRunner: git(repository: false),
    );
    expect(source.inRepository, isFalse);
    expect(source.commit, isNull);
    expect(
      describeBundleSource(source),
      'Built outside a repository, so no source commit was recorded.',
    );
  });

  test('a repository before its first commit records none', () async {
    final source = await readBundleSource(root, processRunner: git());
    expect(source.inRepository, isTrue);
    expect(source.commit, isNull);
    expect(describeBundleSource(source), 'No source commit was recorded.');
  });

  test('a status that cannot be read records no commit', () async {
    final source = await readBundleSource(
      root,
      processRunner: git(
        commit: 'a91f2c3d4e5f60718293a4b5c6d7e8f901234567',
        statusExitCode: 128,
      ),
    );
    expect(source.inRepository, isTrue);
    expect(source.commit, isNull);
    expect(describeBundleSource(source), 'No source commit was recorded.');
  });

  test('the dirty check covers the packages the app resolves', () async {
    List<String>? pathspecs;
    await readBundleSource(
      root,
      processRunner: (executable, arguments, {String? workingDirectory}) async {
        final command = arguments.join(' ');
        if (command.startsWith('rev-parse --show-toplevel')) {
          return ProcessResult(0, 0, '${root.path}\n', '');
        }
        if (command.startsWith('rev-parse --verify')) {
          return ProcessResult(0, 0, 'a91f2c3d4e5f6071\n', '');
        }
        if (command.startsWith('symbolic-ref')) {
          return ProcessResult(0, 0, 'work\n', '');
        }
        if (command.startsWith('status')) {
          pathspecs = arguments.sublist(arguments.indexOf('--') + 1);
          return ProcessResult(0, 0, '', '');
        }
        fail('unexpected command: git $command');
      },
    );
    expect(pathspecs, <String>['.', 'packages/widgets']);
  });

  test('a boundary that will not resolve reaches the caller', () async {
    await File(p.join(root.path, '.dart_tool', 'package_graph.json')).delete();
    List<String>? pathspecs;
    await expectLater(
      readBundleSource(
        root,
        processRunner:
            (executable, arguments, {String? workingDirectory}) async {
              final command = arguments.join(' ');
              if (command.startsWith('rev-parse --show-toplevel')) {
                return ProcessResult(0, 0, '${root.path}\n', '');
              }
              if (command.startsWith('rev-parse --verify')) {
                return ProcessResult(0, 0, 'a91f2c3d4e5f6071\n', '');
              }
              if (command.startsWith('symbolic-ref')) {
                return ProcessResult(0, 0, 'work\n', '');
              }
              if (command.startsWith('status')) {
                pathspecs = arguments.sublist(arguments.indexOf('--') + 1);
                return ProcessResult(0, 0, '', '');
              }
              fail('unexpected command: git $command');
            },
      ),
      throwsA(isA<SourceBoundaryException>()),
    );
    // Nothing was asked of Git: the answer would have described the wrong set.
    expect(pathspecs, isNull);
  });

  test('a short hash is carried whole', () {
    const source = BundleSource(inRepository: true, commit: 'a91f2c');
    expect(source.shortCommit, 'a91f2c');
  });
}
