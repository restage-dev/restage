import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/commands/surface_push_command.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_cli/src/receipts/git_repository.dart';
import 'package:restage_cli/src/receipts/release_recorder.dart';
import 'package:restage_cli/src/receipts/release_receipt.dart';
import 'package:test/test.dart';

import '../_helpers/publication_fixtures.dart';
import '../_helpers/test_fixtures.dart';

const _receiptPath =
    '.restage/receipts/restage/demo/mobile/surface/paywall/pro_upgrade/staging/'
    'push-r17.json';

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

String _out(ProcessResult result) => (result.stdout as String).trim();

void main() {
  late Directory root;
  late Directory app;
  late Directory home;
  late FileCredentialStore store;
  late StringBuffer out;
  late StringBuffer err;
  late String sourceCommit;

  /// A backend that accepts one push of `pro_upgrade` as r17.
  http.Client acceptsPush({void Function()? onPublish}) =>
      mockHttpClient((request) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body['method'] == 'publishPublication') onPublish?.call();
        return publishSucceeded(
          'pro_upgrade',
          storedRevision: 17,
          activeRevision: 17,
        );
      });

  /// A backend that fails the test if it is called at all.
  ({http.Client client, int Function() calls}) refusesEveryCall() {
    var calls = 0;
    return (
      client: MockClient((request) async {
        calls += 1;
        return http.Response('{}', 500);
      }),
      calls: () => calls,
    );
  }

  Future<int?> push(
    List<String> args, {
    http.Client? client,
    ReceiptGeneratorRunner? generator,
    GitProcessRunner? processRunner,
  }) {
    final command = SurfacePushCommand(
      stdout: out,
      stderr: err,
      interactive: const NonInteractive(),
      credentialStore: store,
      httpClient: client ?? acceptsPush(),
      generator: generator ?? (directory) async => ProcessResult(0, 0, '', ''),
      processRunner: processRunner,
    );
    return (CommandRunner<int>(
      'restage',
      '',
    )..addCommand(command)).run(['push', ...args, '-C', app.path]);
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('recorded_push_');
    home = await Directory.systemTemp.createTemp('recorded_push_home_');
    app = Directory(p.join(root.path, 'app'))..createSync(recursive: true);
    store = FileCredentialStore(p.join(home.path, 'credentials'));
    await seedCredential(store);
    out = StringBuffer();
    err = StringBuffer();

    await _git(root, ['init', '-b', 'main', '.']);
    await _git(root, ['config', 'user.name', 'Receipt Test']);
    await _git(root, ['config', 'user.email', 'receipts@example.test']);
    await _git(root, ['config', 'commit.gpgsign', 'false']);
    await _git(root, ['config', 'core.hooksPath', '.git/hooks']);
    // Background maintenance after a commit can race teardown.
    await _git(root, ['config', 'gc.auto', '0']);
    await _git(root, ['config', 'maintenance.auto', 'false']);

    _write(root, '.gitignore', '.dart_tool/\n**/.restage/build/\n');
    _write(root, 'app/lib/screen.dart', 'const screen = 1;\n');
    _write(
      root,
      'app/restage_config.yaml',
      'project: demo\napp: mobile\ndefaultEnvironment: staging\n',
    );
    _write(
      root,
      p.join('.dart_tool', 'package_config.json'),
      jsonEncode({
        'configVersion': 2,
        'packages': [
          {
            'name': fixturePackageName,
            'rootUri': '../app',
            'packageUri': 'lib/',
            'languageVersion': '3.8',
          },
        ],
      }),
    );
    _write(
      root,
      p.join('.dart_tool', 'package_graph.json'),
      jsonEncode({
        'configVersion': 1,
        'roots': [fixturePackageName],
        'packages': [
          {
            'name': fixturePackageName,
            'dependencies': <String>[],
            'devDependencies': <String>[],
          },
        ],
      }),
    );
    _write(root, 'pubspec.lock', 'packages: {}\n');

    await seedGeneratedPaywall(
      app,
      slug: 'pro_upgrade',
      sources: const ['lib/screen.dart'],
    );
    await _git(root, ['add', '-A']);
    await _git(root, ['commit', '-m', 'first']);
    sourceCommit = _out(await _git(root, ['rev-parse', 'HEAD']));
  });

  tearDown(() {
    root.deleteSync(recursive: true);
    home.deleteSync(recursive: true);
  });

  test('records the push and commits only the receipt', () async {
    final code = await push(['pro_upgrade', '--record-git']);

    expect(code, 0, reason: err.toString());
    final receipt = File(p.join(app.path, _receiptPath));
    expect(receipt.existsSync(), isTrue, reason: err.toString());

    final recorded = ReleaseReceipt.decode(receipt.readAsStringSync());
    expect(recorded.operation, ReceiptOperation.surfacePush);
    expect(recorded.revision?.stored, 17);
    expect(recorded.revision?.activeAfter, 17);
    expect(recorded.surface?.type, 'paywall');
    expect(recorded.surface?.id, 'pro_upgrade');
    expect(recorded.target.project, 'demo');
    expect(recorded.target.app, 'mobile');
    expect(recorded.target.environment, 'staging');
    expect(recorded.target.environmentTargetId, 12);
    expect(recorded.target.runtimePlane, 'sandbox');
    expect(recorded.artifacts, isNotEmpty);
    expect(recorded.generationFingerprint, isNotNull);
    expect(recorded.source.state, ReceiptSourceState.verified);
    expect(recorded.source.commit, sourceCommit);
    expect(recorded.source.branch, 'main');
    expect(recorded.source.packages, ['app']);

    final committed = await _git(root, [
      'show',
      '--name-only',
      '--format=%s',
      'HEAD',
    ]);
    expect(_out(committed).split('\n').where((line) => line.isNotEmpty), [
      'restage: push pro_upgrade r17 to staging',
      'app/$_receiptPath',
    ]);
    expect(_out(await _git(root, ['status', '--porcelain=v1'])), isEmpty);
  });

  test('leaves unrelated staged and working-tree changes alone', () async {
    _write(root, 'notes.md', 'unrelated\n');
    _write(root, 'staged.txt', 'also unrelated\n');
    await _git(root, ['add', 'staged.txt']);

    final code = await push(['pro_upgrade', '--record-git']);

    expect(code, 0, reason: err.toString());
    expect(
      _out(await _git(root, ['status', '--porcelain=v1'])).split('\n')..sort(),
      ['?? notes.md', 'A  staged.txt'],
    );
    final committed = await _git(root, ['show', '--name-only', 'HEAD']);
    expect(_out(committed), contains('app/$_receiptPath'));
    expect(_out(committed), isNot(contains('staged.txt')));
  });

  test('refuses uncommitted source before it reaches the server', () async {
    _write(root, 'app/lib/screen.dart', 'const screen = 2;\n');
    final backend = refusesEveryCall();

    final code = await push([
      'pro_upgrade',
      '--record-git',
    ], client: backend.client);

    expect(code, 1);
    expect(backend.calls(), 0);
    expect(err.toString(), contains('The source is not committed'));
    expect(err.toString(), contains('app/lib/screen.dart'));
    expect(
      _out(await _git(root, ['log', '--oneline'])).split('\n'),
      hasLength(1),
    );
  });

  test('refuses on a detached HEAD', () async {
    await _git(root, ['checkout', '--detach']);
    final backend = refusesEveryCall();

    final code = await push([
      'pro_upgrade',
      '--record-git',
    ], client: backend.client);

    expect(code, 1);
    expect(backend.calls(), 0);
    expect(err.toString(), contains('detached'));
  });

  test('refuses when the output cannot be produced', () async {
    final backend = refusesEveryCall();

    final code = await push(
      ['pro_upgrade', '--record-git'],
      client: backend.client,
      generator: (directory) async => ProcessResult(0, 1, '', 'build failed'),
    );

    expect(code, 1);
    expect(backend.calls(), 0);
    expect(err.toString(), contains('could not be produced'));
    expect(err.toString(), contains('build failed'));
  });

  test('refuses when producing the output changes tracked source', () async {
    final backend = refusesEveryCall();

    final code = await push(
      ['pro_upgrade', '--record-git'],
      client: backend.client,
      generator: (directory) async {
        _write(root, 'app/lib/screen.dart', 'const screen = 3;\n');
        return ProcessResult(0, 0, '', '');
      },
    );

    expect(code, 1);
    expect(backend.calls(), 0);
    expect(err.toString(), contains('no longer agree'));
    expect(err.toString(), contains('app/lib/screen.dart'));
  });

  test(
    'without the flag it pushes exactly as before, touching no Git',
    () async {
      final code = await push(
        ['pro_upgrade'],
        processRunner: (executable, arguments, {workingDirectory}) async =>
            fail('Git ran for a push that did not ask to be recorded'),
        generator: (directory) async =>
            fail('the generator ran for a push that did not ask for it'),
      );

      expect(code, 0, reason: err.toString());
      expect(out.toString(), contains('Pushed pro_upgrade'));
      expect(
        Directory(p.join(app.path, '.restage', 'receipts')).existsSync(),
        isFalse,
      );
      expect(
        _out(await _git(root, ['log', '--oneline'])).split('\n'),
        hasLength(1),
      );
    },
  );

  test(
    'reports a pending receipt when the commit does not go through',
    () async {
      final hook = File(p.join(root.path, '.git', 'hooks', 'pre-commit'))
        ..writeAsStringSync(
          '#!/bin/sh\necho "signing key is locked" >&2\nexit 1\n',
        );
      await Process.run('chmod', ['+x', hook.path]);
      var published = 0;

      final code = await push([
        'pro_upgrade',
        '--record-git',
      ], client: acceptsPush(onPublish: () => published += 1));

      expect(code, 2);
      expect(published, 1);
      expect(err.toString(), contains('signing key is locked'));
      expect(File(p.join(app.path, _receiptPath)).existsSync(), isTrue);
      expect(out.toString(), contains('Pushed pro_upgrade'));
      expect(err.toString(), contains('Git receipt pending'));
      expect(err.toString(), contains(' add -- '));
      expect(err.toString(), contains('commit --only'));
      expect(
        _out(await _git(root, ['log', '--oneline'])).split('\n'),
        hasLength(1),
      );
    },
  );

  test('records every surface of a multi-surface push in one commit', () async {
    final first = await seedGeneratedPaywall(
      app,
      slug: 'pro_upgrade',
      sources: const ['lib/paywalls.dart'],
    );
    final second = await seedGeneratedPaywall(
      app,
      slug: 'trial',
      sources: const ['lib/paywalls.dart'],
    );
    await writeGeneratedOutput(app, [first, second]);
    _write(root, 'app/lib/paywalls.dart', 'const paywalls = 1;\n');
    await _git(root, ['add', '-A']);
    await _git(root, ['commit', '-m', 'two surfaces']);

    final code = await push(
      ['lib/paywalls.dart', '--all', '--record-git'],
      client: mockHttpClient((request) {
        final slug = publishedSlugOf(request);
        return publishSucceeded(
          slug,
          storedRevision: slug == 'trial' ? 4 : 17,
          activeRevision: slug == 'trial' ? 4 : 17,
        );
      }),
    );

    expect(code, 0, reason: err.toString());
    final committed = await _git(root, [
      'show',
      '--name-only',
      '--format=%s',
      'HEAD',
    ]);
    expect(_out(committed).split('\n').where((line) => line.isNotEmpty), [
      'restage: push 2 surfaces to staging',
      'app/$_receiptPath',
      'app/.restage/receipts/restage/demo/mobile/surface/paywall/trial/staging/'
          'push-r4.json',
    ]);
    expect(_out(await _git(root, ['status', '--porcelain=v1'])), isEmpty);
  });

  test(
    'the commands it prints commit the pending receipt as they stand',
    () async {
      final hook = File(p.join(root.path, '.git', 'hooks', 'pre-commit'))
        ..writeAsStringSync('#!/bin/sh\nexit 1\n');
      await Process.run('chmod', ['+x', hook.path]);
      var published = 0;
      expect(
        await push([
          'pro_upgrade',
          '--record-git',
        ], client: acceptsPush(onPublish: () => published += 1)),
        2,
      );
      hook.deleteSync();

      // Run exactly what was printed, from a directory that is not the
      // repository: that is what naming the root is for.
      final printed = err
          .toString()
          .split('\n')
          .where((line) => line.trim().startsWith('git -C '))
          .map((line) => line.trim())
          .toList();
      expect(printed, hasLength(2));
      for (final command in printed) {
        final result = await Process.run('sh', ['-c', command]);
        expect(result.exitCode, 0, reason: '$command\n${result.stderr}');
      }

      expect(published, 1, reason: 'recovery must not push again');
      final committed = await _git(root, [
        'show',
        '--name-only',
        '--format=%s',
        'HEAD',
      ]);
      expect(_out(committed).split('\n').where((line) => line.isNotEmpty), [
        'restage: push pro_upgrade r17 to staging',
        'app/$_receiptPath',
      ]);
      expect(_out(await _git(root, ['status', '--porcelain=v1'])), isEmpty);
    },
  );

  test(
    'records each surface it reached and reports the one it did not',
    () async {
      final first = await seedGeneratedPaywall(
        app,
        slug: 'pro_upgrade',
        sources: const ['lib/paywalls.dart'],
      );
      final second = await seedGeneratedPaywall(
        app,
        slug: 'trial',
        sources: const ['lib/paywalls.dart'],
      );
      await writeGeneratedOutput(app, [first, second]);
      _write(root, 'app/lib/paywalls.dart', 'const paywalls = 1;\n');
      await _git(root, ['add', '-A']);
      await _git(root, ['commit', '-m', 'two surfaces']);

      final code = await push(
        ['lib/paywalls.dart', '--all', '--record-git'],
        client: mockHttpClient((request) {
          final slug = publishedSlugOf(request);
          if (slug == 'trial') return http.Response('{}', 500);
          return publishSucceeded(slug, storedRevision: 17, activeRevision: 17);
        }),
      );

      expect(code, isNot(0));
      expect(err.toString(), contains('Pushed 1 of 2; failed on trial'));
      final committed = await _git(root, ['show', '--name-only', 'HEAD']);
      expect(_out(committed), contains('app/$_receiptPath'));
      expect(_out(committed), isNot(contains('trial')));
      expect(
        Directory(
          p.join(
            app.path,
            '.restage/receipts/restage/demo/mobile/surface/paywall/trial',
          ),
        ).existsSync(),
        isFalse,
      );
    },
  );

  test(
    'each revision of one surface gets its own searchable receipt',
    () async {
      var revision = 16;
      http.Client acceptsNextRevision() => mockHttpClient((request) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body['method'] == 'publishPublication') revision += 1;
        return publishSucceeded(
          'pro_upgrade',
          storedRevision: revision,
          activeRevision: revision,
        );
      });

      expect(
        await push([
          'pro_upgrade',
          '--record-git',
        ], client: acceptsNextRevision()),
        0,
        reason: err.toString(),
      );
      expect(
        await push([
          'pro_upgrade',
          '--record-git',
        ], client: acceptsNextRevision()),
        0,
        reason: err.toString(),
      );

      final directory = Directory(p.join(app.path, p.dirname(_receiptPath)));
      expect(
        directory.listSync().map((entry) => p.basename(entry.path)).toList()
          ..sort(),
        ['push-r17.json', 'push-r18.json'],
      );
      // One commit per invocation, each naming the revision it recorded.
      final log = await _git(root, ['log', '--format=%s']);
      expect(_out(log).split('\n'), [
        'restage: push pro_upgrade r18 to staging',
        'restage: push pro_upgrade r17 to staging',
        'first',
      ]);
    },
  );

  test('two organizations pushing one app each record their own', () async {
    // The fixture's default discovery answers one organization; these two
    // share a project and an app, and each counts revisions on its own.
    http.Client acceptsEither() => mockHttpClient((request) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      switch (body['method']) {
        case 'listMine':
          return http.Response(
            jsonEncode([
              {'organizationId': 11, 'slug': 'acme', 'name': 'Acme'},
              {'organizationId': 12, 'slug': 'other', 'name': 'Other'},
            ]),
            200,
          );
        case 'listApps':
          return http.Response(
            jsonEncode([
              {'id': 5, 'slug': 'mobile', 'name': 'Mobile'},
            ]),
            200,
          );
        case 'listEnvironmentTargets':
          return http.Response(
            jsonEncode([
              {
                'environmentTargetId': 12,
                'namedEnvironmentId': 22,
                'environmentSlug': 'staging',
                'runtimePlane': 'sandbox',
              },
            ]),
            200,
          );
        default:
          return publishSucceeded(
            'pro_upgrade',
            storedRevision: 17,
            activeRevision: 17,
          );
      }
    }, withDefaultTargetDiscovery: false);

    for (final organization in ['acme', 'other']) {
      expect(
        await push([
          'pro_upgrade',
          '--record-git',
          '--organization',
          organization,
        ], client: acceptsEither()),
        0,
        reason: err.toString(),
      );
    }

    const tail =
        'demo/mobile/surface/paywall/pro_upgrade/staging/push-r17.json';
    final first = ReleaseReceipt.decode(
      File(p.join(app.path, '.restage/receipts/acme/$tail')).readAsStringSync(),
    );
    final second = ReleaseReceipt.decode(
      File(
        p.join(app.path, '.restage/receipts/other/$tail'),
      ).readAsStringSync(),
    );
    expect(first.target.organizationId, 11);
    expect(first.target.organization, 'acme');
    expect(second.target.organizationId, 12);
    expect(second.target.organization, 'other');
    expect(first.revision?.stored, 17);
    expect(second.revision?.stored, 17);
  });

  test('a second project pushing from one directory records its own', () async {
    // Revisions are counted per project, so two projects reach r17 in one
    // environment. Both records have to survive.
    expect(await push(['pro_upgrade', '--record-git']), 0, reason: '$err');

    final code = await push([
      'pro_upgrade',
      '--record-git',
      '--project',
      'other',
      '--app',
      'a',
    ]);

    expect(code, 0, reason: err.toString());
    const secondPath =
        '.restage/receipts/restage/other/a/surface/paywall/pro_upgrade/staging/'
        'push-r17.json';
    final second = File(p.join(app.path, secondPath));
    expect(second.existsSync(), isTrue, reason: err.toString());
    final recorded = ReleaseReceipt.decode(second.readAsStringSync());
    expect(recorded.target.project, 'other');
    expect(recorded.target.app, 'a');
    expect(recorded.revision?.stored, 17);
    // The first project's record is untouched, and each push has one commit.
    expect(File(p.join(app.path, _receiptPath)).existsSync(), isTrue);
    final committed = await _git(root, [
      'show',
      '--name-only',
      '--format=%s',
      'HEAD',
    ]);
    expect(_out(committed).split('\n').where((line) => line.isNotEmpty), [
      'restage: push pro_upgrade r17 to staging',
      'app/$secondPath',
    ]);
    expect(_out(await _git(root, ['status', '--porcelain=v1'])), isEmpty);
  });

  test('an earlier receipt waiting to be committed blocks nothing', () async {
    // Git collapses untracked directories, so the receipt has to be named
    // individually for the exclusion to see it.
    _write(
      root,
      'app/.restage/receipts/restage/demo/mobile/surface/paywall/other/staging/'
          'push-r9.json',
      '{}\n',
    );

    final code = await push(['pro_upgrade', '--record-git']);

    expect(code, 0, reason: err.toString());
    expect(File(p.join(app.path, _receiptPath)).existsSync(), isTrue);
  });

  test('the project setting records without the flag', () async {
    _write(
      root,
      'app/restage_config.yaml',
      'project: demo\napp: mobile\ndefaultEnvironment: staging\n'
          'recordGit: true\n',
    );
    await _git(root, ['add', '-A']);
    await _git(root, ['commit', '-m', 'record by default']);

    final code = await push(['pro_upgrade']);

    expect(code, 0, reason: err.toString());
    expect(File(p.join(app.path, _receiptPath)).existsSync(), isTrue);
  });

  test('--no-record-git overrides the project setting', () async {
    _write(
      root,
      'app/restage_config.yaml',
      'project: demo\napp: mobile\ndefaultEnvironment: staging\n'
          'recordGit: true\n',
    );
    await _git(root, ['add', '-A']);
    await _git(root, ['commit', '-m', 'record by default']);

    final code = await push(
      ['pro_upgrade', '--no-record-git'],
      processRunner: (executable, arguments, {workingDirectory}) async =>
          fail('Git ran for a push that opted out of recording'),
      generator: (directory) async => fail('the generator ran'),
    );

    expect(code, 0, reason: err.toString());
    expect(
      Directory(p.join(app.path, '.restage', 'receipts')).existsSync(),
      isFalse,
    );
  });

  test('recording one operation twice keeps a single record', () async {
    expect(await push(['pro_upgrade', '--record-git']), 0, reason: '$err');
    final receipt = File(p.join(app.path, _receiptPath));
    final firstContents = receipt.readAsStringSync();

    final code = await push(['pro_upgrade', '--record-git']);

    expect(code, 0, reason: err.toString());
    expect(receipt.readAsStringSync(), firstContents);
    expect(
      Directory(p.join(app.path, p.dirname(_receiptPath))).listSync(),
      hasLength(1),
    );
    expect(out.toString(), contains('already matches the last commit'));
    expect(
      _out(await _git(root, ['log', '--oneline'])).split('\n'),
      hasLength(2),
    );
  });

  test(
    'refuses to write over a different operation already recorded',
    () async {
      final foreign = ReleaseReceipt(
        operation: ReceiptOperation.surfacePush,
        recordedAt: DateTime.utc(2026, 9),
        target: const ReceiptTarget(
          project: 'demo',
          app: 'mobile',
          environment: 'staging',
        ),
        surface: const ReceiptSurface(
          type: 'paywall',
          id: 'pro_upgrade',
          sourceKind: 'paywall',
        ),
        revision: const ReceiptRevision(stored: 4),
        source: const ReceiptSource.unknown(),
      );
      _write(root, 'app/$_receiptPath', foreign.encode());
      await _git(root, ['add', '-A']);
      await _git(root, ['commit', '-m', 'existing record']);

      final code = await push(['pro_upgrade', '--record-git']);

      expect(code, 2);
      expect(
        File(p.join(app.path, _receiptPath)).readAsStringSync(),
        foreign.encode(),
      );
      expect(err.toString(), contains('already recorded'));
      expect(out.toString(), contains('"stored": 17'));
    },
  );

  test('prints the record when the receipt file cannot be written', () async {
    // A file where the receipts directory belongs: the record has nowhere to
    // go, and losing it would lose the only account of a push that happened.
    _write(root, 'app/.restage/receipts', 'not a directory\n');
    await _git(root, ['add', '-A']);
    await _git(root, ['commit', '-m', 'blocked']);
    var published = 0;

    final code = await push([
      'pro_upgrade',
      '--record-git',
    ], client: acceptsPush(onPublish: () => published += 1));

    expect(code, 2);
    expect(published, 1);
    expect(err.toString(), contains('could not be written'));
    expect(out.toString(), contains('"operation": "surface-push"'));
    expect(out.toString(), contains('"stored": 17'));
  });
}
