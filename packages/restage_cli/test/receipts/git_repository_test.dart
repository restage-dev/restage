import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:restage_cli/src/receipts/git_repository.dart';
import 'package:test/test.dart';

import '../_helpers/test_fixtures.dart';

const _commit = '4444444444444444444444444444444444444444';

/// A runner that answers exactly the commands a test names.
GitProcessRunner _fakeRunner(
  Map<String, ProcessResult> answers, {
  List<List<String>>? seen,
}) {
  return (executable, arguments, {workingDirectory}) async {
    seen?.add(arguments);
    return answers[arguments.join(' ')] ??
        ProcessResult(0, 1, '', 'unexpected command');
  };
}

ProcessResult _ok(String stdout) => ProcessResult(0, 0, stdout, '');
ProcessResult _failed([String stderr = '']) => ProcessResult(0, 1, '', stderr);

/// Join [fields] the way Git terminates them under `-z`.
///
/// Built at run time so the separator never sits in this file as a byte.
String _nulTerminated(List<String> fields) {
  final separator = String.fromCharCode(0);
  return fields.map((field) => '$field$separator').join();
}

Future<ProcessResult> _git(
  Directory repository,
  List<String> arguments, {
  bool allowFailure = false,
}) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: repository.path,
    runInShell: false,
  );
  if (!allowFailure && result.exitCode != 0) {
    fail('git ${arguments.join(' ')} failed: ${result.stderr}');
  }
  return result;
}

void _write(Directory root, String relative, String contents) {
  File(p.join(root.path, relative))
    ..createSync(recursive: true)
    ..writeAsStringSync(contents);
}

void main() {
  group('against a fake runner', () {
    test('open returns null outside a repository', () async {
      final repository = await GitRepository.open(
        Directory.current,
        processRunner: _fakeRunner({
          'rev-parse --show-toplevel': _failed('not a git repository'),
        }),
      );

      expect(repository, isNull);
    });

    test('head reads the commit and the branch it is on', () async {
      final repository = await GitRepository.open(
        Directory.current,
        processRunner: _fakeRunner({
          'rev-parse --show-toplevel': _ok('/repo\n'),
          'rev-parse --verify --quiet HEAD': _ok('$_commit\n'),
          'symbolic-ref --quiet --short HEAD': _ok('main\n'),
        }),
      );
      final head = await repository!.head();

      expect(repository.root.path, '/repo');
      expect(head!.commit, _commit);
      expect(head.branch, 'main');
      expect(head.detached, isFalse);
    });

    test('head reports a detached HEAD with no branch', () async {
      final repository = await GitRepository.open(
        Directory.current,
        processRunner: _fakeRunner({
          'rev-parse --show-toplevel': _ok('/repo\n'),
          'rev-parse --verify --quiet HEAD': _ok('$_commit\n'),
          'symbolic-ref --quiet --short HEAD': _failed(),
        }),
      );
      final head = await repository!.head();

      expect(head!.branch, isNull);
      expect(head.detached, isTrue);
    });

    test('head is null when the repository has no commits yet', () async {
      final repository = await GitRepository.open(
        Directory.current,
        processRunner: _fakeRunner({
          'rev-parse --show-toplevel': _ok('/repo\n'),
          'rev-parse --verify --quiet HEAD': _failed(),
        }),
      );

      expect(await repository!.head(), isNull);
    });

    test(
      'uncommitted names every path, including inside a new directory',
      () async {
        final status = _nulTerminated([
          'M  staged.dart',
          ' M changed.dart',
          'MM both.dart',
          '?? new.dart',
          '?? fresh/dir/file.dart',
          // A rename is followed by the path it came from.
          'R  renamed.dart',
          'was.dart',
        ]);
        final repository = await GitRepository.open(
          Directory.current,
          processRunner: _fakeRunner({
            'rev-parse --show-toplevel': _ok('/repo\n'),
            'status --porcelain=v1 -z --untracked-files=all -- lib': _ok(
              status,
            ),
          }),
        );
        final entries = await repository!.uncommitted(paths: const ['lib']);

        expect(entries.map((entry) => entry.path), [
          'staged.dart',
          'changed.dart',
          'both.dart',
          'new.dart',
          'fresh/dir/file.dart',
          'renamed.dart',
        ]);
      },
    );

    test('open says so when Git is not installed', () async {
      expect(
        () => GitRepository.open(
          Directory.current,
          processRunner: (executable, arguments, {workingDirectory}) async =>
              throw const ProcessException('git', ['rev-parse']),
        ),
        throwsA(isA<GitUnavailableException>()),
      );
    });

    test('uncommitted asks Git nothing when the path set is empty', () async {
      final seen = <List<String>>[];
      final repository = await GitRepository.open(
        Directory.current,
        processRunner: _fakeRunner({
          'rev-parse --show-toplevel': _ok('/repo\n'),
        }, seen: seen),
      );
      seen.clear();

      expect(await repository!.uncommitted(paths: const []), isEmpty);
      expect(seen, isEmpty);
    });

    test('commitPaths commits nothing when the paths match HEAD', () async {
      final seen = <List<String>>[];
      final repository = await GitRepository.open(
        Directory.current,
        processRunner: _fakeRunner({
          'rev-parse --show-toplevel': _ok('/repo\n'),
          'add -- receipt.json': _ok(''),
          'diff --quiet HEAD -- receipt.json': _ok(''),
        }, seen: seen),
      );
      final commit = await repository!.commitPaths(
        paths: const ['receipt.json'],
        message: 'receipt',
      );

      expect(commit, isNull);
      expect(
        seen.map((arguments) => arguments.first),
        isNot(contains('commit')),
      );
    });

    test(
      'operationInProgress names what the repository is mid-way through',
      () async {
        final gitDir = await Directory.systemTemp.createTemp(
          'receipts_gitdir_',
        );
        addTearDown(() => gitDir.deleteSync(recursive: true));
        final repository = await GitRepository.open(
          Directory.current,
          processRunner: _fakeRunner({
            'rev-parse --show-toplevel': _ok('/repo\n'),
            'rev-parse --absolute-git-dir': _ok('${gitDir.path}\n'),
          }),
        );

        expect(await repository!.operationInProgress(), isNull);

        File(
          p.join(gitDir.path, 'CHERRY_PICK_HEAD'),
        ).writeAsStringSync(_commit);
        expect(
          await repository.operationInProgress(),
          GitOperationInProgress.cherryPick,
        );

        Directory(p.join(gitDir.path, 'rebase-merge')).createSync();
        expect(
          await repository.operationInProgress(),
          GitOperationInProgress.rebase,
        );

        File(p.join(gitDir.path, 'MERGE_HEAD')).writeAsStringSync(_commit);
        expect(
          await repository.operationInProgress(),
          GitOperationInProgress.merge,
        );
      },
    );
  });

  group('against a real repository', () {
    late Directory root;
    late TestGitTemplate repository;

    setUpAll(() async {
      repository = await TestGitTemplate.create((template) async {
        _write(template, '.gitignore', '.restage/build/\n');
        _write(template, 'lib/app.dart', 'void main() {}\n');
      });
    });
    tearDownAll(() => repository.delete());

    setUp(() async {
      root = await Directory.systemTemp.createTemp('receipts_repo_');
      await repository.copyTo(root);
    });

    tearDown(() => root.deleteSync(recursive: true));

    test('opens from a subdirectory and reads HEAD', () async {
      final repository = await GitRepository.open(
        Directory(p.join(root.path, 'lib')),
      );
      final head = await repository!.head();

      expect(
        repository.root.resolveSymbolicLinksSync(),
        root.resolveSymbolicLinksSync(),
      );
      expect(head!.branch, 'main');
      expect(head.commit, matches(RegExp(r'^[0-9a-f]{40}$')));
      expect(await repository.operationInProgress(), isNull);
    });

    test('reads a detached HEAD', () async {
      await _git(root, ['checkout', '--detach']);
      final repository = await GitRepository.open(root);
      final head = await repository!.head();

      expect(head!.detached, isTrue);
      expect(head.branch, isNull);
    });

    test('sees a merge left in progress', () async {
      await _git(root, ['checkout', '-b', 'other']);
      _write(root, 'lib/app.dart', 'void main() { print(1); }\n');
      await _git(root, ['commit', '-am', 'other']);
      await _git(root, ['checkout', 'main']);
      _write(root, 'lib/app.dart', 'void main() { print(2); }\n');
      await _git(root, ['commit', '-am', 'main']);
      final merge = await _git(root, ['merge', 'other'], allowFailure: true);
      expect(merge.exitCode, isNot(0));

      final repository = await GitRepository.open(root);

      expect(
        await repository!.operationInProgress(),
        GitOperationInProgress.merge,
      );
    });

    test('reports uncommitted content and ignores what Git ignores', () async {
      _write(root, 'lib/staged.dart', 'const a = 1;\n');
      await _git(root, ['add', 'lib/staged.dart']);
      _write(root, 'lib/app.dart', 'void main() { print(3); }\n');
      _write(root, 'lib/new.dart', 'const b = 2;\n');
      _write(root, '.restage/build/metadata.json', '{}\n');
      final repository = await GitRepository.open(root);

      final entries = await repository!.uncommitted(
        paths: [p.join(root.path, 'lib'), '.restage'],
      );

      expect(entries.map((entry) => entry.path).toList()..sort(), [
        'lib/app.dart',
        'lib/new.dart',
        'lib/staged.dart',
      ]);
      expect(
        await repository.uncommitted(paths: const ['.gitignore']),
        isEmpty,
      );
    });

    test('commits only the named path and leaves the index alone', () async {
      _write(root, 'lib/staged.dart', 'const a = 1;\n');
      await _git(root, ['add', 'lib/staged.dart']);
      _write(root, 'lib/app.dart', 'void main() { print(4); }\n');
      _write(root, '.restage/receipts/push-r17.json', '{}\n');
      final repository = await GitRepository.open(root);

      final commit = await repository!.commitPaths(
        paths: const ['.restage/receipts/push-r17.json'],
        message: 'restage: push welcome r17 to staging',
      );

      expect(commit, matches(RegExp(r'^[0-9a-f]{40}$')));
      final committed = await _git(root, [
        'show',
        '--name-only',
        '--format=%s',
        'HEAD',
      ]);
      expect(
        (committed.stdout as String)
            .trim()
            .split('\n')
            .where((line) => line.isNotEmpty),
        [
          'restage: push welcome r17 to staging',
          '.restage/receipts/push-r17.json',
        ],
      );
      final status = await _git(root, ['status', '--porcelain=v1']);
      expect((status.stdout as String).trimRight().split('\n')..sort(), [
        ' M lib/app.dart',
        'A  lib/staged.dart',
      ]);
    });

    test('commits nothing when the receipt already matches HEAD', () async {
      _write(root, '.restage/receipts/push-r17.json', '{}\n');
      final repository = await GitRepository.open(root);
      const paths = ['.restage/receipts/push-r17.json'];
      await repository!.commitPaths(paths: paths, message: 'first');

      final again = await repository.commitPaths(
        paths: paths,
        message: 'again',
      );

      expect(again, isNull);
      final log = await _git(root, ['log', '--oneline']);
      expect((log.stdout as String).trim().split('\n'), hasLength(2));
    });

    test(
      'a failing hook leaves the receipt uncommitted and reports it',
      () async {
        final hook = File(p.join(root.path, '.git', 'hooks', 'pre-commit'))
          ..writeAsStringSync('#!/bin/sh\nexit 1\n');
        await Process.run('chmod', ['+x', hook.path]);
        _write(root, '.restage/receipts/push-r17.json', '{}\n');
        final repository = await GitRepository.open(root);

        await expectLater(
          repository!.commitPaths(
            paths: const ['.restage/receipts/push-r17.json'],
            message: 'restage: push welcome r17 to staging',
          ),
          throwsA(
            isA<GitCommitFailure>().having(
              (failure) => failure.indexRestored,
              'indexRestored',
              isTrue,
            ),
          ),
        );
        final log = await _git(root, ['log', '--oneline']);
        expect((log.stdout as String).trim().split('\n'), hasLength(1));
        // The receipt is left out of the index, so the developer's own next
        // commit does not carry it.
        final status = await _git(root, [
          'status',
          '--porcelain=v1',
          '--untracked-files=all',
        ]);
        expect((status.stdout as String).trimRight().split('\n'), [
          '?? .restage/receipts/push-r17.json',
        ]);
      },
    );
  });
}
