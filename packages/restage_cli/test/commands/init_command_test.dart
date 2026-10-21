import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:restage_cli/src/cli.dart';
import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/config/restage_config.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../_helpers/test_fixtures.dart';

const _starterPubspec = '''
name: my_app
description: A sample app.

environment:
  sdk: ^3.5.0

dependencies:
  flutter:
    sdk: flutter
''';

Future<void> _writePubspec(
  Directory dir, [
  String content = _starterPubspec,
]) async {
  await File(p.join(dir.path, 'pubspec.yaml')).writeAsString(content);
}

void main() {
  late Directory tempDir;
  late FileCredentialStore store;
  late StringBuffer stdout;
  late StringBuffer stderr;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('init_cmd_');
    store = FileCredentialStore(p.join(tempDir.path, 'credentials'));
    stdout = StringBuffer();
    stderr = StringBuffer();
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('restage init', () {
    test('discovers org/project/app/environment and writes config', () async {
      await _writePubspec(tempDir);
      await seedCredential(store);

      final exitCode =
          await RestageCli(
            stdout: stdout,
            stderr: stderr,
            credentialStore: store,
            httpClient: _discoveryClient(),
          ).run([
            '--non-interactive',
            'init',
            '--directory',
            tempDir.path,
            '--no-starter',
            '--no-add-deps',
          ]);

      expect(exitCode, 0);
      final config = await loadRestageConfig(from: tempDir);
      expect(config, isNotNull);
      expect(config!.config.organization, 'default');
      expect(config.config.project, 'default-project');
      expect(config.config.app, 'default-app');
      expect(config.config.defaultEnvironment, 'staging');
      expect(config.config.endpoint, 'http://localhost:8080/');
      expect(config.config.plane, RuntimePlane.sandbox);
      expect(config.config.organizationId, 7);
      expect(config.config.appId, 5);
      expect(config.config.environmentTargetId, 11);
      expect(config.config.namedEnvironmentId, 9);
    });

    test(
      'forced discovery replaces stale IDs and keeps local settings',
      () async {
        await _writePubspec(tempDir);
        await seedCredential(store);
        await File(p.join(tempDir.path, 'restage_config.yaml')).writeAsString(
          'plane: sandbox\nrecordGit: true\nflutterRoot: ../flutter\n'
          'organizationId: 99\nappId: 98\n'
          'environmentTargetId: 97\nnamedEnvironmentId: 96\n',
        );
        var scopeReads = 0;
        final exitCode =
            await RestageCli(
              stdout: stdout,
              stderr: stderr,
              credentialStore: store,
              httpClient: _discoveryClient(onRead: () => scopeReads++),
            ).run([
              '--non-interactive',
              'init',
              '--directory',
              tempDir.path,
              '--no-starter',
              '--no-add-deps',
              '--force',
            ]);
        expect(exitCode, 0, reason: stderr.toString());
        final config = (await loadRestageConfig(from: tempDir))!.config;
        expect(scopeReads, 1);
        expect(config.organizationId, 7);
        expect(config.appId, 5);
        expect(config.environmentTargetId, 11);
        expect(config.namedEnvironmentId, 9);
        expect(config.recordGit, isTrue);
        expect(config.flutterRoot, '../flutter');
      },
    );

    test(
      '--non-interactive with all flags writes the four artifacts',
      () async {
        await _writePubspec(tempDir);

        final exitCode =
            await RestageCli(
              stdout: stdout,
              stderr: stderr,
              credentialStore: store,
            ).run([
              '--non-interactive',
              'init',
              '--directory',
              tempDir.path,
              '--project',
              'my-project',
              '--app',
              'my-app',
              '--env',
              'dev',
            ]);

        expect(exitCode, 0);

        // restage_config.yaml exists and parses.
        final config = await loadRestageConfig(from: tempDir);
        expect(config, isNotNull);
        expect(config!.config.project, 'my-project');
        expect(config.config.app, 'my-app');
        expect(config.config.defaultEnvironment, 'dev');

        // Starter paywall written.
        final starter = File(
          p.join(tempDir.path, 'lib', 'paywalls', 'starter.dart'),
        );
        expect(starter.existsSync(), isTrue);
        final starterSource = await starter.readAsString();
        expect(starterSource, contains('@Paywall()'));
        expect(starterSource, isNot(contains('@Paywall(id:')));
        expect(stdout.toString(), contains('restage surface push starter'));
        expect(stdout.toString(), isNot(contains('restage paywall push')));

        // Pubspec edits applied.
        final pubspecContent = await File(
          p.join(tempDir.path, 'pubspec.yaml'),
        ).readAsString();
        expect(pubspecContent, contains('restage'));
        expect(pubspecContent, contains('restage: ^2.0.0'));
        expect(pubspecContent, contains('restage_codegen'));
        expect(pubspecContent, contains('restage_codegen: ^2.0.0'));
        expect(pubspecContent, contains('build_runner'));
        expect(pubspecContent, isNot(contains('assets/restage/bundles')));

        final gitignoreContent = await File(
          p.join(tempDir.path, '.gitignore'),
        ).readAsString();
        expect(gitignoreContent, contains('*.rsbundle'));
        expect(gitignoreContent, contains('*.restage.md'));
        expect(gitignoreContent, contains('restage.outputs.json'));
        expect(gitignoreContent, contains('restage.publication.json'));
        expect(gitignoreContent, contains('restage_a2ui_catalog.a2ui.json'));
        expect(gitignoreContent, contains('!assets/restage/bundles/**'));
        expect(stdout.toString(), contains('to ignore Restage build output.'));
        expect(gitignoreContent, isNot(contains('*.generated/')));
        expect(gitignoreContent, isNot(contains('generated/')));
      },
    );

    test(
      'all-flags init writes the stored credential endpoint when signed in',
      () async {
        await _writePubspec(tempDir);
        await seedCredential(
          store,
          endpoint: 'https://restage-backend-staging.example/',
        );

        final exitCode =
            await RestageCli(
              stdout: stdout,
              stderr: stderr,
              credentialStore: store,
            ).run([
              '--non-interactive',
              'init',
              '--directory',
              tempDir.path,
              '--organization',
              'restage',
              '--project',
              'default',
              '--app',
              'default',
              '--env',
              'staging',
              '--no-starter',
              '--no-add-deps',
            ]);

        expect(exitCode, 0);
        final config = await loadRestageConfig(from: tempDir);
        expect(config, isNotNull);
        expect(config!.config.organization, 'restage');
        expect(config.config.project, 'default');
        expect(config.config.app, 'default');
        expect(config.config.defaultEnvironment, 'staging');
        expect(
          config.config.endpoint,
          'https://restage-backend-staging.example/',
        );
        expect(
          stdout.toString(),
          contains(
            'Set endpoint: https://restage-backend-staging.example/ '
            '(from your stored sign-in).\n',
          ),
        );
      },
    );

    test('init without a stored sign-in names no endpoint', () async {
      await _writePubspec(tempDir);

      final exitCode = await _runInit(stdout, stderr, store, tempDir);

      expect(exitCode, 0, reason: stderr.toString());
      expect(stdout.toString(), isNot(contains('Set endpoint')));
    });

    group('build.yaml', () {
      setUp(() => _writePubspec(tempDir));

      File buildYaml() => File(p.join(tempDir.path, 'build.yaml'));

      test('is written, then kept on a second run', () async {
        expect(await _runInit(stdout, stderr, store, tempDir), 0);
        expect(
          buildYaml().readAsStringSync(),
          contains('  - .restage/wire-ids.events.jsonl\n'),
        );
        expect(
          stdout.toString(),
          contains("Wrote build.yaml so builds track Restage's state files.\n"),
        );

        stdout.clear();
        expect(await _runInit(stdout, stderr, store, tempDir), 0);
        expect(
          stdout.toString(),
          contains(
            "Kept build.yaml; it already tracks Restage's state files.\n",
          ),
        );
      });

      test('gets the missing entries added', () async {
        buildYaml().writeAsStringSync('targets:\n  \$default: {}\n');

        expect(await _runInit(stdout, stderr, store, tempDir), 0);
        expect(
          buildYaml().readAsStringSync(),
          contains('  - .restage/measurement-state.json\n'),
        );
        expect(
          stdout.toString(),
          contains(
            "Updated build.yaml so builds track Restage's state files.\n",
          ),
        );
      });

      test('that cannot be edited names the entries to add', () async {
        buildYaml().writeAsStringSync('- not a map\n');

        expect(await _runInit(stdout, stderr, store, tempDir), 0);
        expect(buildYaml().readAsStringSync(), '- not a map\n');
        expect(
          stdout.toString(),
          contains(
            'Could not update build.yaml safely. Add these entries to its '
            'additional_public_assets list:\n'
            '  - .restage/measurement-state.json\n'
            '  - .restage/wire-ids.events.jsonl\n',
          ),
        );
      });
    });

    group('an existing restage_config.yaml', () {
      const existing =
          'plane: sandbox\nrecordGit: true\nflutterRoot: ../flutter\n';
      late File configFile;

      setUp(() async {
        await _writePubspec(tempDir);
        configFile = File(p.join(tempDir.path, 'restage_config.yaml'))
          ..writeAsStringSync(existing);
      });

      test('is kept without --force when non-interactive', () async {
        final exitCode = await _runInit(stdout, stderr, store, tempDir);

        expect(exitCode, 0, reason: stderr.toString());
        expect(configFile.readAsStringSync(), existing);
        expect(
          stdout.toString(),
          contains(
            'Kept existing restage_config.yaml. Pass --force to update it.\n',
          ),
        );
      });

      test(
        'is updated with --force, keeping settings init does not ask',
        () async {
          await seedCredential(store, endpoint: 'https://backend.example/');

          final exitCode = await _runInit(
            stdout,
            stderr,
            store,
            tempDir,
            extra: ['--force'],
          );

          expect(exitCode, 0, reason: stderr.toString());
          final config = (await loadRestageConfig(from: tempDir))!.config;
          expect(config.project, 'p');
          expect(config.app, 'a');
          expect(config.defaultEnvironment, 'dev');
          expect(config.recordGit, isTrue);
          expect(config.flutterRoot, '../flutter');
          expect(config.endpoint, 'https://backend.example/');
          expect(
            stdout.toString(),
            contains(
              'Updated restage_config.yaml.\n'
              'Set endpoint: https://backend.example/ (from your stored sign-in).\n',
            ),
          );
        },
      );

      for (final answer in [true, false]) {
        test(
          'asks before updating when interactive (answer: $answer)',
          () async {
            final interactive = _ConfirmingInteractive(answer);

            final exitCode = await RestageCli(
              stdout: stdout,
              stderr: stderr,
              credentialStore: store,
              interactiveFactory: (_) => interactive,
            ).run(_initArgs(tempDir));

            expect(exitCode, 0, reason: stderr.toString());
            expect(interactive.questions, [
              'restage_config.yaml already exists. Update it with these values?',
            ]);
            if (answer) {
              expect(configFile.readAsStringSync(), contains('project: p'));
              expect(
                stdout.toString(),
                contains('Updated restage_config.yaml.'),
              );
            } else {
              expect(configFile.readAsStringSync(), existing);
              expect(
                stdout.toString(),
                contains('Kept existing restage_config.yaml.\n'),
              );
            }
          },
        );
      }
    });

    test('--dry-run prints the planned changes without writing', () async {
      await _writePubspec(tempDir);

      final exitCode =
          await RestageCli(
            stdout: stdout,
            stderr: stderr,
            credentialStore: store,
          ).run([
            '--non-interactive',
            'init',
            '--directory',
            tempDir.path,
            '--project',
            'p',
            '--app',
            'a',
            '--env',
            'dev',
            '--dry-run',
          ]);

      expect(exitCode, 0);
      expect(stdout.toString(), contains('restage_config.yaml'));
      expect(stdout.toString(), contains('restage'));

      // Verify the filesystem was untouched.
      expect(
        File(p.join(tempDir.path, 'restage_config.yaml')).existsSync(),
        isFalse,
      );
      expect(File(p.join(tempDir.path, '.gitignore')).existsSync(), isFalse);
      expect(File(p.join(tempDir.path, 'build.yaml')).existsSync(), isFalse);
      expect(
        File(
          p.join(tempDir.path, 'lib', 'paywalls', 'starter.dart'),
        ).existsSync(),
        isFalse,
      );
      final pubspecContent = await File(
        p.join(tempDir.path, 'pubspec.yaml'),
      ).readAsString();
      expect(pubspecContent, _starterPubspec);
    });

    test('missing pubspec exits 1 with a clear message', () async {
      // No pubspec.yaml in tempDir.

      final exitCode =
          await RestageCli(
            stdout: stdout,
            stderr: stderr,
            credentialStore: store,
          ).run([
            '--non-interactive',
            'init',
            '--directory',
            tempDir.path,
            '--project',
            'p',
            '--app',
            'a',
            '--env',
            'dev',
          ]);

      expect(exitCode, 1);
      expect(stderr.toString(), contains('pubspec.yaml'));
    });

    for (final (:flag, :args) in const [
      (flag: '--project', args: ['--app', 'a', '--env', 'dev']),
      (flag: '--app', args: ['--project', 'p', '--env', 'dev']),
      (flag: '--env', args: ['--project', 'p', '--app', 'a']),
    ]) {
      test(
        '--non-interactive without $flag exits 1 with a usage hint',
        () async {
          await _writePubspec(tempDir);

          final exitCode =
              await RestageCli(
                stdout: stdout,
                stderr: stderr,
                credentialStore: store,
              ).run([
                '--non-interactive',
                'init',
                '--directory',
                tempDir.path,
                ...args,
              ]);

          expect(exitCode, 1);
          expect(stderr.toString(), contains(flag));
        },
      );
    }

    test('an account with no organization is sent to the dashboard', () async {
      await _writePubspec(tempDir);
      await seedCredential(store, endpoint: 'https://api-preview.restage.dev/');

      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        httpClient: mockHttpClient(
          (_) => http.Response(
            jsonEncode({
              'session': {
                'memberships': <Object>[],
                'workspaceExperiences': <Object>[],
              },
            }),
            200,
          ),
          withDefaultTargetDiscovery: false,
        ),
      ).run(['--non-interactive', 'init', '--directory', tempDir.path]);

      expect(exitCode, 1);
      expect(
        stderr.toString(),
        'No organization yet. Create one in the dashboard: '
        'https://app-preview.restage.dev\n'
        'Then run `restage init` again.\n',
      );
    });

    test('without a sign-in, init says how discovery works', () async {
      await _writePubspec(tempDir);

      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
      ).run(['--non-interactive', 'init', '--directory', tempDir.path]);

      expect(exitCode, 1);
      expect(stderr.toString(), contains('Not signed in.'));
      expect(stderr.toString(), contains('run `restage login`'));
      expect(stderr.toString(), contains('Required: --project <slug>.'));
    });

    test('re-run is idempotent: existing config + deps kept; exit 0', () async {
      await _writePubspec(tempDir);

      final args = [
        '--non-interactive',
        'init',
        '--directory',
        tempDir.path,
        '--project',
        'p',
        '--app',
        'a',
        '--env',
        'dev',
      ];

      var exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
      ).run(args);
      expect(exitCode, 0);
      final gitignore = File(p.join(tempDir.path, '.gitignore'));
      final firstGitignore = await gitignore.readAsString();
      stdout.clear();
      stderr.clear();

      exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
      ).run(args);
      expect(exitCode, 0);
      // Either explicit `kept` reporting in stdout or simply a clean
      // exit is acceptable; the load-bearing assertion is that the
      // second run does not blow up on existing artifacts.
      final config = await loadRestageConfig(from: tempDir);
      expect(config, isNotNull);
      expect(await gitignore.readAsString(), firstGitignore);
    });

    test(
      'updates a partial existing .gitignore while preserving user and negated rules',
      () async {
        await _writePubspec(tempDir);
        const existingGitignore =
            '# Project rules\r\ncustom-cache/\r\n*.rsbundle\r\n'
            '!restage.publication.json\r\n';
        final gitignore = File(p.join(tempDir.path, '.gitignore'))
          ..writeAsStringSync(existingGitignore);

        final exitCode =
            await RestageCli(
              stdout: stdout,
              stderr: stderr,
              credentialStore: store,
            ).run([
              '--non-interactive',
              'init',
              '--directory',
              tempDir.path,
              '--project',
              'p',
              '--app',
              'a',
              '--env',
              'dev',
              '--no-starter',
              '--no-add-deps',
            ]);

        expect(exitCode, 0);
        final updated = await gitignore.readAsString();
        expect(updated.startsWith(existingGitignore), isTrue);
        expect(updated, contains('custom-cache/'));
        expect(updated, contains('*.rsbundle'));
        expect(updated, contains('*.restage.md'));
        expect(updated, contains('restage.outputs.json'));
        expect(updated, isNot(contains('\r\nrestage.publication.json')));
        expect(updated, contains('!restage.publication.json'));
        expect(updated, contains('restage_a2ui_catalog.a2ui.json'));
        expect(updated.replaceAll('\r\n', ''), isNot(contains('\n')));
        expect(updated, isNot(contains('*.generated/')));
        expect(updated, endsWith('\r\n!assets/restage/bundles/**\r\n'));
      },
    );

    test('skips the starter paywall when --no-starter is passed', () async {
      await _writePubspec(tempDir);

      final exitCode =
          await RestageCli(
            stdout: stdout,
            stderr: stderr,
            credentialStore: store,
          ).run([
            '--non-interactive',
            'init',
            '--directory',
            tempDir.path,
            '--project',
            'p',
            '--app',
            'a',
            '--env',
            'dev',
            '--no-starter',
            '--plane',
            'live',
          ]);

      expect(exitCode, 0);
      expect(
        File(
          p.join(tempDir.path, 'lib', 'paywalls', 'starter.dart'),
        ).existsSync(),
        isFalse,
      );
      expect(
        (await loadRestageConfig(from: tempDir))!.config.plane,
        RuntimePlane.live,
      );
      expect(stdout.toString(), isNot(contains('push starter')));
      expect(
        stdout.toString(),
        contains('`restage surface push <id>` to push a surface.'),
      );
    });

    test('skips pubspec edits when --no-add-deps is passed', () async {
      await _writePubspec(tempDir);

      final exitCode =
          await RestageCli(
            stdout: stdout,
            stderr: stderr,
            credentialStore: store,
          ).run([
            '--non-interactive',
            'init',
            '--directory',
            tempDir.path,
            '--project',
            'p',
            '--app',
            'a',
            '--env',
            'dev',
            '--no-add-deps',
          ]);

      expect(exitCode, 0);
      final pubspecContent = await File(
        p.join(tempDir.path, 'pubspec.yaml'),
      ).readAsString();
      expect(pubspecContent, isNot(contains('restage')));
    });
  });
}

http.Client _discoveryClient({void Function()? onRead}) => mockHttpClient((
  request,
) {
  onRead?.call();
  final body = jsonDecode(request.body) as Map<String, dynamic>;
  expect(request.url.path, '/scope');
  expect(body['method'], 'read');
  return http.Response(
    jsonEncode({
      'organizationId': 7,
      'session': {
        'memberships': [
          {
            'organizationId': 7,
            'slug': 'default',
            'name': 'Default',
            'role': 'owner',
          },
        ],
        'workspaceExperiences': <Object>[],
      },
      'projects': [
        {'id': 1, 'slug': 'default-project', 'name': 'Default Project'},
      ],
      'apps': [
        {'id': 5, 'projectId': 1, 'slug': 'default-app', 'name': 'Default App'},
      ],
      'environments': [
        {'id': 11, 'appId': 5, 'namedEnvironmentId': 9, 'slug': 'staging'},
      ],
      'environmentTargets': [
        {
          'environmentTargetId': 11,
          'namedEnvironmentId': 9,
          'environmentSlug': 'staging',
          'runtimePlane': 'sandbox',
        },
      ],
      'surfaces': <Object>[],
    }),
    200,
  );
}, withDefaultTargetDiscovery: false);

List<String> _initArgs(Directory dir, [List<String> extra = const []]) => [
  'init',
  '--directory',
  dir.path,
  '--project',
  'p',
  '--app',
  'a',
  '--env',
  'dev',
  '--no-starter',
  '--no-add-deps',
  ...extra,
];

Future<int?> _runInit(
  StringSink stdout,
  StringSink stderr,
  FileCredentialStore store,
  Directory dir, {
  List<String> extra = const [],
}) => RestageCli(
  stdout: stdout,
  stderr: stderr,
  credentialStore: store,
).run(['--non-interactive', ..._initArgs(dir, extra)]);

class _ConfirmingInteractive implements Interactive {
  _ConfirmingInteractive(this.answer);

  final bool answer;
  final questions = <String>[];

  @override
  bool get isInteractive => true;

  @override
  Future<bool> confirm(String question, {bool defaultYes = false}) async {
    questions.add(question);
    return answer;
  }

  @override
  Future<String> prompt(String question, {String? defaultValue}) async =>
      fail('prompt should not be called');

  @override
  Future<T> select<T>(
    String question,
    List<({String label, T value})> options, {
    T? defaultValue,
  }) async => fail('select should not be called');

  @override
  Future<String> secret(String question) async =>
      fail('secret should not be called');

  @override
  Spinner spinner(String message) => fail('spinner should not be called');
}
