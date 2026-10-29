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
        expect(pubspecContent, contains('restage_material: ^2.0.0'));
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

    group('the Android manifest', () {
      setUp(() => _writePubspec(tempDir));

      File manifest() => File(
        p.join(
          tempDir.path,
          'android',
          'app',
          'src',
          'main',
          'AndroidManifest.xml',
        ),
      );
      const source =
          '<manifest xmlns:android="x">\n    <application/>\n</manifest>\n';

      test('gets the INTERNET permission, then is kept', () async {
        manifest()
          ..createSync(recursive: true)
          ..writeAsStringSync(source);

        expect(await _runInit(stdout, stderr, store, tempDir), 0);
        expect(
          manifest().readAsStringSync(),
          '<manifest xmlns:android="x">\n'
          '    <uses-permission android:name="android.permission.INTERNET"/>\n'
          '    <application/>\n</manifest>\n',
        );
        expect(
          stdout.toString(),
          contains(
            'Added the INTERNET permission to '
            'android/app/src/main/AndroidManifest.xml. Release builds can now '
            'reach Restage.',
          ),
        );

        stdout.clear();
        expect(await _runInit(stdout, stderr, store, tempDir), 0);
        expect(
          stdout.toString(),
          contains('AndroidManifest.xml already allows network access.'),
        );
      });

      test('is only planned on a dry run', () async {
        manifest()
          ..createSync(recursive: true)
          ..writeAsStringSync(source);

        expect(
          await _runInit(stdout, stderr, store, tempDir, extra: ['--dry-run']),
          0,
        );
        expect(manifest().readAsStringSync(), source);
        expect(
          stdout.toString(),
          contains(
            '  update ${manifest().path} '
            '(Add the INTERNET permission for release builds)',
          ),
        );
      });

      test('is not mentioned in a project without one', () async {
        expect(await _runInit(stdout, stderr, store, tempDir), 0);
        expect(stdout.toString(), isNot(contains('INTERNET')));
      });
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

    final sixCell = <(String, String)>[
      for (final slug in ['dev', 'staging', 'production'])
        for (final plane in ['sandbox', 'live']) (slug, plane),
    ];
    const threeCell = <(String, String)>[
      ('dev', 'sandbox'),
      ('staging', 'sandbox'),
      ('production', 'live'),
    ];

    Future<({int? exit, String? environment, String? plane})> initOn(
      List<(String, String)> grid,
      List<String> extra,
    ) async {
      await _writePubspec(tempDir);
      await seedCredential(store);
      final exit =
          await RestageCli(
            stdout: stdout,
            stderr: stderr,
            credentialStore: store,
            httpClient: _discoveryClient(grid: grid),
          ).run([
            '--yes',
            'init',
            '--directory',
            tempDir.path,
            '--no-starter',
            '--no-add-deps',
            ...extra,
          ]);
      final config = await loadRestageConfig(from: tempDir);
      return (
        exit: exit,
        environment: config?.config.defaultEnvironment,
        plane: config?.config.plane?.name,
      );
    }

    for (final (name, grid) in [
      ('six-cell', sixCell),
      ('three-cell', threeCell),
    ]) {
      test('--yes on a $name app picks the first sandbox environment and '
          'says so', () async {
        final result = await initOn(grid, []);
        expect(result.exit, 0, reason: stderr.toString());
        expect(result.environment, 'dev');
        expect(result.plane, 'sandbox');
        expect(
          stdout.toString(),
          contains('Using environment `dev` (sandbox)'),
        );
      });

      test('--env staging on a $name app needs no --plane', () async {
        final result = await initOn(grid, ['--env', 'staging']);
        expect(result.exit, 0, reason: stderr.toString());
        expect(result.environment, 'staging');
        expect(result.plane, 'sandbox');
      });
    }

    test(
      '--env production with no --plane uses sandbox when it is on both',
      () async {
        final result = await initOn(sixCell, ['--env', 'production']);
        expect(result.exit, 0, reason: stderr.toString());
        expect(result.plane, 'sandbox');
      },
    );

    test(
      '--env production with no --plane finds it on the live plane',
      () async {
        final result = await initOn(threeCell, ['--env', 'production']);
        expect(result.exit, 0, reason: stderr.toString());
        expect(result.environment, 'production');
        expect(result.plane, 'live');
      },
    );

    test(
      '--env production on the wrong explicit plane says which to pass',
      () async {
        final result = await initOn(threeCell, [
          '--env',
          'production',
          '--plane',
          'sandbox',
        ]);
        expect(result.exit, 1);
        expect(
          stderr.toString(),
          contains(
            '`production` has no sandbox environment. Pass --plane live.',
          ),
        );
      },
    );

    test('--yes --plane live on a three-cell app picks production', () async {
      final result = await initOn(threeCell, ['--plane', 'live']);
      expect(result.exit, 0, reason: stderr.toString());
      expect(result.environment, 'production');
      expect(result.plane, 'live');
    });

    const allSelectors = [
      '--organization',
      'default',
      '--project',
      'default-project',
      '--app',
      'default-app',
    ];

    test('a mistyped --env with every flag given fails and names the '
        'environments', () async {
      final result = await initOn(threeCell, [
        ...allSelectors,
        '--env',
        'stagin',
      ]);
      expect(result.exit, isNot(0));
      expect(result.environment, isNull);
      expect(
        stderr.toString(),
        contains('No environment `stagin` in this app. '),
      );
      expect(stderr.toString(), contains('dev, staging, production'));
    });

    test('an app with only a live environment initializes with no --env '
        'or --plane', () async {
      final result = await initOn(const [('production', 'live')], []);
      expect(result.exit, 0, reason: stderr.toString());
      expect(result.environment, 'production');
      expect(result.plane, 'live');
    });

    test('--plane with every flag given still checks the environment '
        'exists on that plane', () async {
      final result = await initOn(threeCell, [
        ...allSelectors,
        '--env',
        'production',
        '--plane',
        'sandbox',
      ]);
      expect(result.exit, isNot(0));
      expect(result.environment, isNull);
      expect(
        stderr.toString(),
        contains('`production` has no sandbox environment. Pass --plane live.'),
      );
    });

    Future<int> initAllFlags(http.Client client) async {
      await _writePubspec(tempDir);
      await seedCredential(store);
      return RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        httpClient: client,
      ).run([
        '--yes',
        'init',
        '--directory',
        tempDir.path,
        '--no-starter',
        '--no-add-deps',
        ...allSelectors,
        '--env',
        'staging',
      ]);
    }

    test('all flags with an unreachable backend initialize from the flags '
        'and say they were not checked', () async {
      final exit = await initAllFlags(
        mockHttpClient(
          (_) => throw const SocketException('connection refused'),
          withDefaultTargetDiscovery: false,
        ),
      );
      expect(exit, 0, reason: stderr.toString());
      final config = await loadRestageConfig(from: tempDir);
      expect(config!.config.defaultEnvironment, 'staging');
      expect(
        stderr.toString(),
        contains(
          'Continuing with the slugs you passed; they were not checked.',
        ),
      );
    });

    test(
      'all flags with a rejected credential fail and write no config',
      () async {
        final exit = await initAllFlags(
          mockHttpClient(
            (_) => http.Response('{"error":"unauthorized"}', 401),
            withDefaultTargetDiscovery: false,
          ),
        );
        expect(exit, 1);
        expect(await loadRestageConfig(from: tempDir), isNull);
        expect(stderr.toString(), isNot(contains('unauthorized')));
        expect(stderr.toString(), isNot(contains('Continuing')));
      },
    );

    test('all flags with a typed refusal fail and write no config', () async {
      final exit = await initAllFlags(
        mockHttpClient(
          (_) => http.Response(
            '{"className":"ProjectNotFoundException",'
            '"data":{"slug":"default-project"}}',
            400,
          ),
          withDefaultTargetDiscovery: false,
        ),
      );
      expect(exit, 1);
      expect(await loadRestageConfig(from: tempDir), isNull);
      expect(stderr.toString(), isNot(contains('className')));
    });

    for (final (name, body) in [
      ('a list', '[]'),
      ('an empty object', '{}'),
      (
        'a malformed app row',
        '{"organizationId": 7, "session": {"memberships": [], '
            '"workspaceExperiences": []}, "projects": [], '
            '"apps": [{"slug": 5}], "environments": [], '
            '"environmentTargets": [], "surfaces": [], '
            '"legacyDefaultTargetIds": []}',
      ),
      (
        'a malformed target row',
        '{"organizationId": 7, "session": {"memberships": [], '
            '"workspaceExperiences": []}, "projects": [], "apps": [], '
            '"environments": [], "environmentTargets": [{"runtimePlane": 5}], '
            '"surfaces": [], "legacyDefaultTargetIds": []}',
      ),
      (
        'a wrong-typed organization id',
        '{"organizationId": "7", "session": {"memberships": [], '
            '"workspaceExperiences": []}, "projects": [], "apps": [], '
            '"environments": [], "environmentTargets": [], "surfaces": [], '
            '"legacyDefaultTargetIds": []}',
      ),
      (
        'a malformed surface row',
        '{"organizationId": 7, "session": {"memberships": [], '
            '"workspaceExperiences": []}, "projects": [], "apps": [], '
            '"environments": [], "environmentTargets": [], '
            '"surfaces": [{"id": "x"}]}',
      ),
      (
        'a missing list',
        '{"organizationId": 7, "session": {"memberships": [], '
            '"workspaceExperiences": []}, "projects": [], "apps": [], '
            '"environments": [], "environmentTargets": []}',
      ),
      (
        'a malformed environment row',
        '{"organizationId": 7, "session": {"memberships": [], '
            '"workspaceExperiences": []}, "projects": [], "apps": [], '
            '"environments": [{"slug": 5}], "environmentTargets": [], "surfaces": []}',
      ),
      (
        'a wrong-typed field',
        '{"organizationId": 7, "session": {"memberships": "x"}, '
            '"projects": 1}',
      ),
    ]) {
      test('a malformed scope reply ($name) fails with exit 2 and no stack '
          'trace', () async {
        final exit = await initAllFlags(
          mockHttpClient(
            (_) => http.Response(body, 200),
            withDefaultTargetDiscovery: false,
          ),
        );
        expect(exit, 2);
        expect(await loadRestageConfig(from: tempDir), isNull);
        expect(
          stderr.toString(),
          contains('The current scope is unavailable.'),
        );
      });
    }

    test(
      'all flags with a server error exit 2 and do not echo the body',
      () async {
        final exit = await initAllFlags(
          mockHttpClient(
            (_) => http.Response('internal secret detail', 500),
            withDefaultTargetDiscovery: false,
          ),
        );
        expect(exit, 2);
        expect(await loadRestageConfig(from: tempDir), isNull);
        expect(stderr.toString(), contains('(HTTP 500)'));
        expect(stderr.toString(), isNot(contains('secret')));
      },
    );

    test('an unreachable backend without every flag exits 2', () async {
      await _writePubspec(tempDir);
      await seedCredential(store);
      final exit =
          await RestageCli(
            stdout: stdout,
            stderr: stderr,
            credentialStore: store,
            httpClient: mockHttpClient(
              (_) => throw const SocketException('connection refused'),
              withDefaultTargetDiscovery: false,
            ),
          ).run([
            '--yes',
            'init',
            '--directory',
            tempDir.path,
            '--no-starter',
            '--no-add-deps',
          ]);
      expect(exit, 2);
      expect(await loadRestageConfig(from: tempDir), isNull);
    });

    test('all flags with no sign-in say the slugs were not checked', () async {
      await _writePubspec(tempDir);
      final exit =
          await RestageCli(
            stdout: stdout,
            stderr: stderr,
            credentialStore: store,
          ).run([
            '--yes',
            'init',
            '--directory',
            tempDir.path,
            '--no-starter',
            '--no-add-deps',
            '--project',
            'p',
            '--app',
            'a',
            '--env',
            'dev',
          ]);
      expect(exit, 0, reason: stderr.toString());
      expect(
        stderr.toString(),
        contains(
          'Continuing with the slugs you passed; they were not checked.',
        ),
      );
    });

    test('several organizations with no --organization asks for it', () async {
      await _writePubspec(tempDir);
      await seedCredential(store);
      final exit =
          await RestageCli(
            stdout: stdout,
            stderr: stderr,
            credentialStore: store,
            httpClient: mockHttpClient(
              (_) => http.Response(
                jsonEncode({
                  'organizationId': 7,
                  'session': {
                    'memberships': [
                      for (final (i, slug) in ['one', 'two'].indexed)
                        {
                          'organizationId': 7 + i,
                          'slug': slug,
                          'name': slug,
                          'role': 'owner',
                        },
                    ],
                    'workspaceExperiences': <Object>[],
                  },
                  'projects': <Object>[],
                  'apps': <Object>[],
                  'environments': <Object>[],
                  'environmentTargets': <Object>[],
                  'legacyDefaultTargetIds': <Object>[],
                  'surfaces': <Object>[],
                }),
                200,
              ),
              withDefaultTargetDiscovery: false,
            ),
          ).run([
            '--non-interactive',
            'init',
            '--directory',
            tempDir.path,
            '--no-starter',
            '--no-add-deps',
            '--project',
            'default-project',
            '--app',
            'default-app',
            '--env',
            'staging',
          ]);
      expect(exit, 1);
      expect(await loadRestageConfig(from: tempDir), isNull);
      expect(stderr.toString(), contains('--organization'));
    });

    test('--preview-wrapper must name a function the app declares', () async {
      await _writePubspec(tempDir);
      final exitCode =
          await RestageCli(
            stdout: stdout,
            stderr: stderr,
            credentialStore: store,
          ).run(
            _initArgs(tempDir, [
              '--preview-wrapper',
              'lib/restage_preview.dart#wrapPreview',
            ]),
          );
      expect(exitCode, 1);
      expect(stderr.toString(), contains('lib/restage_preview.dart'));
      expect(
        File(p.join(tempDir.path, 'restage_config.yaml')).existsSync(),
        isFalse,
      );
    });

    test('--preview-wrapper is written to the config', () async {
      await _writePubspec(tempDir);
      File(p.join(tempDir.path, 'lib', 'restage_preview.dart'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('''
import 'package:flutter/widgets.dart';

Widget wrapPreview(Widget child) => child;
''');
      final exitCode =
          await RestageCli(
            stdout: stdout,
            stderr: stderr,
            credentialStore: store,
          ).run(
            _initArgs(tempDir, [
              '--preview-wrapper',
              'lib/restage_preview.dart#wrapPreview',
            ]),
          );
      expect(exitCode, 0, reason: stderr.toString());
      final config = await loadRestageConfig(from: tempDir);
      expect(
        config!.config.previewWrapper,
        'lib/restage_preview.dart#wrapPreview',
      );
      expect(stdout.toString(), isNot(contains('previewWrapper: lib')));
    });

    test('init without a wrapper shows the config line to add', () async {
      await _writePubspec(tempDir);
      await _runInit(stdout, stderr, store, tempDir);
      expect(
        stdout.toString(),
        contains('previewWrapper: lib/restage_preview.dart#wrapPreview'),
      );
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
              'projects': <Object>[],
              'apps': <Object>[],
              'environments': <Object>[],
              'environmentTargets': <Object>[],
              'legacyDefaultTargetIds': <Object>[],
              'surfaces': <Object>[],
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

http.Client _discoveryClient({
  void Function()? onRead,
  List<(String, String)> grid = const [('staging', 'sandbox')],
}) => mockHttpClient((request) {
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
      // One row per environment target, as the server returns them.
      'environments': [
        for (final (i, cell) in grid.indexed)
          {
            'id': 11 + i,
            'appId': 5,
            'namedEnvironmentId':
                9 + grid.map((c) => c.$1).toSet().toList().indexOf(cell.$1),
            'slug': cell.$1,
          },
      ],
      'environmentTargets': [
        for (final (i, cell) in grid.indexed)
          {
            'environmentTargetId': 11 + i,
            'namedEnvironmentId':
                9 + grid.map((c) => c.$1).toSet().toList().indexOf(cell.$1),
            'environmentSlug': cell.$1,
            'runtimePlane': cell.$2,
          },
      ],
      'legacyDefaultTargetIds': <Object>[],
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
