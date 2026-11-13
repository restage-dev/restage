import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage_cli/src/cli.dart';
import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/api/selector_syntax.dart';
import 'package:restage_cli/src/config/restage_config.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'package:restage_cli/src/api/default_endpoint.dart';
import 'package:restage_shared/restage_shared.dart' show canonicalServiceUrl;

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

        // Pubspec edits applied: every Restage package from the same main.
        final pubspecContent = await File(
          p.join(tempDir.path, 'pubspec.yaml'),
        ).readAsString();
        Map<String, Object?> git(String path) => {
          'git': {
            'url': 'https://github.com/restage-dev/restage.git',
            'ref': 'main',
            'path': path,
          },
        };
        final written =
            _plain(loadYaml(pubspecContent))! as Map<String, Object?>;
        expect(written['dependencies'], {
          'flutter': {'sdk': 'flutter'},
          'restage': git('packages/restage'),
          'restage_material': git('packages/restage_material'),
        });
        expect(written['dev_dependencies'], {
          'build_runner': '>=2.15.1 <3.0.0',
          'restage_codegen': git('packages/restage_codegen'),
        });
        expect(written['dependency_overrides'], {
          'restage': git('packages/restage'),
          'restage_material': git('packages/restage_material'),
          'rfw_catalog_schema': git('packages/rfw_catalog_schema'),
        });
        expect(
          pubspecContent,
          contains('dependency_overrides:\n  restage:\n    git:\n'),
        );
        expect(pubspecContent, isNot(contains('assets/restage/bundles')));
        expect(
          stdout.toString(),
          contains(
            "No publishable key, so the first-launch request isn't built "
            'into the app. Try `restage login`, then run `restage init` again '
            'to mint one, or `restage init --sdk-key rs_pk_...`.',
          ),
        );

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

    group('Restage from pub.dev', () {
      test('moves to git main, with the overrides at the end', () async {
        await _writePubspec(tempDir, '''
name: my_app

environment:
  sdk: ^3.5.0

dependencies:
  flutter:
    sdk: flutter
  restage: ^2.0.0

dev_dependencies:
  build_runner: ^2.4.0
  restage_codegen: ^2.0.0

flutter:
  uses-material-design: true
  # assets:
  #   - images/a_dot_burr.jpeg
''');
        expect(
          await _runInit(
            stdout,
            stderr,
            store,
            tempDir,
            extra: const ['--add-deps'],
          ),
          0,
        );
        final source = File(
          p.join(tempDir.path, 'pubspec.yaml'),
        ).readAsStringSync();
        final written = _plain(loadYaml(source))! as Map<String, Object?>;
        Map<String, Object?> git(String path) => {
          'git': {
            'url': 'https://github.com/restage-dev/restage.git',
            'ref': 'main',
            'path': path,
          },
        };
        expect(
          (written['dependencies']! as Map)['restage'],
          git('packages/restage'),
        );
        expect(
          (written['dev_dependencies']! as Map)['restage_codegen'],
          git('packages/restage_codegen'),
        );
        expect((written['dev_dependencies']! as Map)['build_runner'], '^2.4.0');
        expect(
          source.indexOf('dependency_overrides:'),
          greaterThan(source.indexOf('#   - images/a_dot_burr.jpeg')),
        );
        expect(
          stdout.toString(),
          contains(
            'Moved restage, restage_codegen from pub.dev to the main branch '
            'of github.com/restage-dev/restage, so every Restage package '
            'comes from one commit.\n',
          ),
        );
      });
    });

    group('pubspec.yaml', () {
      Future<int?> init() =>
          _runInit(stdout, stderr, store, tempDir, extra: const ['--add-deps']);
      File pubspec() => File(p.join(tempDir.path, 'pubspec.yaml'));

      test('an empty dependency_overrides key is filled, once', () async {
        await _writePubspec(
          tempDir,
          '$_starterPubspec\ndependency_overrides:\n',
        );
        expect(await init(), 0);
        final source = pubspec().readAsStringSync();
        expect(
          'dependency_overrides:'.allMatches(source),
          hasLength(1),
          reason: source,
        );
        final overrides =
            (loadYaml(source) as YamlMap)['dependency_overrides'] as YamlMap;
        expect(
          overrides.keys,
          containsAll(['restage_material', 'rfw_catalog_schema']),
        );
      });

      test('a list at the top is refused with nothing written', () async {
        const list = '- a\n- b\n';
        await _writePubspec(tempDir, list);
        expect(await init(), 1);
        expect(pubspec().readAsStringSync(), list);
        expect(
          stderr.toString(),
          contains('pubspec.yaml does not parse as a map of keys'),
        );
        expect(File(p.join(tempDir.path, 'build.yaml')).existsSync(), isFalse);
      });

      test('a dependency block given as a list is refused', () async {
        const listed =
            'name: my_app\ndependencies: [flutter, cupertino_icons]\n';
        await _writePubspec(tempDir, listed);
        expect(await init(), 1);
        expect(pubspec().readAsStringSync(), listed);
        expect(
          stderr.toString(),
          contains(
            'pubspec.yaml gives `dependencies` as something other than a map '
            'of entries, so init changed nothing.',
          ),
        );
        expect(File(p.join(tempDir.path, 'build.yaml')).existsSync(), isFalse);
      });

      test('one that does not parse is refused with nothing written', () async {
        const broken = 'name: my_app\nname: other\n';
        await _writePubspec(tempDir, broken);
        expect(await init(), 1);
        expect(pubspec().readAsStringSync(), broken);
        expect(
          stderr.toString(),
          contains(
            'pubspec.yaml does not parse, so init changed nothing: Duplicate '
            'mapping key at line 2. Try fixing that line',
          ),
        );
        expect(File(p.join(tempDir.path, 'build.yaml')).existsSync(), isFalse);
      });
    });

    group('the iOS first-launch request', () {
      setUp(() async {
        await _writePubspec(tempDir);
        Directory(
          p.join(tempDir.path, 'ios', 'Runner'),
        ).createSync(recursive: true);
      });

      List<Object?>? assets() =>
          ((_plain(
                        loadYaml(
                          File(
                            p.join(tempDir.path, 'pubspec.yaml'),
                          ).readAsStringSync(),
                        ),
                      )!
                      as Map)['flutter']
                  as Map?)?['assets']
              as List<Object?>?;

      test('is listed as a Flutter asset with a key', () async {
        expect(
          await _runInit(
            stdout,
            stderr,
            store,
            tempDir,
            extra: const ['--add-deps', '--sdk-key', 'rs_pk_sandbox_dev_abc'],
          ),
          0,
        );
        expect(assets(), ['ios/Runner/restage_early.json']);
        // So a Flutter build before the first build_runner finds it.
        expect(
          File(
            p.join(tempDir.path, 'ios', 'Runner', 'restage_early.json'),
          ).readAsStringSync(),
          '{}\n',
        );
      });

      test('keeps a request file the build already wrote', () async {
        final file = File(
          p.join(tempDir.path, 'ios', 'Runner', 'restage_early.json'),
        )..writeAsStringSync('{"url":"built"}');
        expect(
          await _runInit(
            stdout,
            stderr,
            store,
            tempDir,
            extra: const ['--add-deps', '--sdk-key', 'rs_pk_sandbox_dev_abc'],
          ),
          0,
        );
        expect(file.readAsStringSync(), '{"url":"built"}');
      });

      test('is listed with a key and --no-add-deps', () async {
        expect(
          await _runInit(
            stdout,
            stderr,
            store,
            tempDir,
            extra: const [
              '--no-add-deps',
              '--sdk-key',
              'rs_pk_sandbox_dev_abc',
            ],
          ),
          0,
        );
        expect(assets(), ['ios/Runner/restage_early.json']);
        final written =
            _plain(
                  loadYaml(
                    File(
                      p.join(tempDir.path, 'pubspec.yaml'),
                    ).readAsStringSync(),
                  ),
                )!
                as Map;
        expect(written['dev_dependencies'], isNot(contains('restage_codegen')));
        expect(written['dependency_overrides'], isNull);
        expect(
          File(
            p.join(tempDir.path, 'ios', 'Runner', 'restage_early.json'),
          ).readAsStringSync(),
          '{}\n',
        );
      });

      test('is not listed without a key', () async {
        expect(
          await _runInit(
            stdout,
            stderr,
            store,
            tempDir,
            extra: const ['--add-deps'],
          ),
          0,
        );
        expect(assets(), isNull);
      });
    });

    group('build.yaml', () {
      setUp(() => _writePubspec(tempDir));

      File buildYaml() => File(p.join(tempDir.path, 'build.yaml'));

      test('is written, then kept on a second run', () async {
        expect(await _runInit(stdout, stderr, store, tempDir), 0);
        expect(
          buildYaml().readAsStringSync(),
          'additional_public_assets:\n'
          '  - .restage/measurement-state.json\n'
          '  - .restage/wire-ids.events.jsonl\n'
          '  - .restage/receipts/**\n'
          '  - .restage/library-contracts/**\n',
        );
        expect(
          stdout.toString(),
          contains('Wrote build.yaml: state file tracking.\n'),
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
          contains('  - .restage/library-contracts/**\n'),
        );
        expect(
          stdout.toString(),
          contains('Updated build.yaml: state file tracking.\n'),
        );
      });

      YamlMap deliveryOptions() =>
          (loadYaml(buildYaml().readAsStringSync())
                  as YamlMap)['targets'][r'$default']['builders']['restage_codegen:user_factories']['options']
              as YamlMap;

      test(
        '--sdk-key signed out writes the default service URL and says so',
        () async {
          expect(
            await _runInit(
              stdout,
              stderr,
              store,
              tempDir,
              extra: const ['--sdk-key', 'rs_pk_sandbox_dev_abc'],
            ),
            0,
          );
          final url = canonicalServiceUrl(defaultRestageEndpoint);
          expect(deliveryOptions()['api_key'], 'rs_pk_sandbox_dev_abc');
          expect(deliveryOptions()['base_url'], url);
          expect(stdout.toString(), isNot(contains('No publishable key')));
          expect(
            stdout.toString(),
            contains(
              'Wrote build.yaml: state file tracking, the service URL and the '
              'publishable key.\n',
            ),
          );
          expect(
            stdout.toString(),
            contains(
              "You aren't signed in, so build.yaml uses $url as the service "
              'URL. If your app uses another server, try replacing `base_url` '
              'under restage_codegen:user_factories in build.yaml with its '
              'URL.\n',
            ),
          );

          // A rerun without the flag finds the key; a different key is kept.
          stdout.clear();
          expect(await _runInit(stdout, stderr, store, tempDir), 0);
          expect(stdout.toString(), isNot(contains('No publishable key')));
          stdout.clear();
          expect(
            await _runInit(
              stdout,
              stderr,
              store,
              tempDir,
              extra: const ['--sdk-key', 'rs_pk_sandbox_dev_new'],
            ),
            0,
          );
          expect(
            stdout.toString(),
            contains(
              'build.yaml already sets a different api_key under '
              'restage_codegen:user_factories, so it was kept. Try replacing '
              'it there with `api_key: rs_pk_sandbox_dev_new` if you meant to '
              'change it.\n',
            ),
          );
          expect(deliveryOptions()['api_key'], 'rs_pk_sandbox_dev_abc');
        },
      );

      test(
        '--sdk-key signed in writes the sign-in URL without its slash',
        () async {
          await seedCredential(store, endpoint: 'https://api.example.com/');
          expect(
            await _runInit(
              stdout,
              stderr,
              store,
              tempDir,
              extra: const ['--sdk-key', 'rs_pk_sandbox_dev_abc'],
            ),
            0,
          );
          expect(deliveryOptions()['base_url'], 'https://api.example.com');
          expect(stdout.toString(), isNot(contains("aren't signed in")));
        },
      );

      test('an old startup-request block moves to the new options', () async {
        buildYaml().writeAsStringSync('''
additional_public_assets:
  - .restage/measurement-state.json
targets:
  \$default:
    builders:
      restage_codegen:restage_early_template:
        options:
          api_key: rs_pk_sandbox_dev_old
          base_url: https://api.example.com
''');
        expect(await _runInit(stdout, stderr, store, tempDir), 0);
        final source = buildYaml().readAsStringSync();
        expect(source, isNot(contains('restage_early_template')));
        expect(source, contains('  - .restage/measurement-state.json\n'));
        expect(deliveryOptions()['api_key'], 'rs_pk_sandbox_dev_old');
        expect(
          stdout.toString(),
          contains(
            'Updated build.yaml: state file tracking and moved api_key, '
            'base_url from restage_codegen:restage_early_template.\n',
          ),
        );
        expect(stdout.toString(), isNot(contains('No publishable key')));
      });

      test('.restage/** is replaced, and --force does not bring it back, '
          'so push output under .restage/build is no build input', () async {
        buildYaml().writeAsStringSync(
          'additional_public_assets:\n  - .restage/**\n',
        );
        for (final extra in const [
          <String>[],
          <String>['--force'],
        ]) {
          stdout.clear();
          expect(
            await _runInit(stdout, stderr, store, tempDir, extra: extra),
            0,
          );
          final listed =
              (loadYaml(buildYaml().readAsStringSync())
                      as YamlMap)['additional_public_assets']
                  as YamlList;
          expect(listed, isNot(contains('.restage/**')), reason: '$extra');
          expect(listed, [
            '.restage/measurement-state.json',
            '.restage/wire-ids.events.jsonl',
            '.restage/receipts/**',
            '.restage/library-contracts/**',
          ]);
        }
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
            '  - .restage/wire-ids.events.jsonl\n'
            '  - .restage/receipts/**\n'
            '  - .restage/library-contracts/**\n',
          ),
        );
      });
    });

    group('the publishable key', () {
      late List<Map<String, dynamic>> mints;

      setUp(() async {
        mints = [];
        await _writePubspec(tempDir);
      });

      File buildYaml() => File(p.join(tempDir.path, 'build.yaml'));

      Map<Object?, Object?>? deliveryOptions() {
        if (!buildYaml().existsSync()) return null;
        final doc = loadYaml(buildYaml().readAsStringSync()) as YamlMap?;
        final options =
            doc?['targets']?[r'$default']?['builders']?['restage_codegen:user_factories']?['options'];
        return options is YamlMap ? Map.of(options) : null;
      }

      Future<int?> init({
        List<String> extra = const [],
        http.Response Function(Map<String, dynamic> body)? onMint,
        List<(String, String)> grid = const [('staging', 'sandbox')],
      }) =>
          RestageCli(
            stdout: stdout,
            stderr: stderr,
            credentialStore: store,
            httpClient: _discoveryClient(
              grid: grid,
              onMint: (body) {
                mints.add(body);
                return (onMint ?? _mintResponse)(body);
              },
            ),
          ).run([
            '--non-interactive',
            'init',
            '--directory',
            tempDir.path,
            '--no-starter',
            '--no-add-deps',
            ...extra,
          ]);

      test(
        'signed in, init mints one and writes it; a rerun keeps it',
        () async {
          await seedCredential(store, endpoint: 'https://api.example.com/');

          expect(await init(), 0, reason: stderr.toString());
          expect(mints, hasLength(1));
          expect(mints.single, containsPair('kind', 'public'));
          expect(mints.single, containsPair('projectSlug', 'default-project'));
          expect(mints.single, containsPair('appSlug', 'default-app'));
          expect(mints.single, containsPair('environmentSlug', 'staging'));
          expect(mints.single, containsPair('environmentTargetId', 11));
          expect(mints.single, containsPair('runtimePlane', 'sandbox'));
          expect(mints.single, containsPair('organizationId', 7));
          expect(deliveryOptions(), {
            'api_key': _mintedKey,
            'base_url': 'https://api.example.com',
            'delivery_keys': [_deliveryKey],
          });
          expect(
            stdout.toString(),
            contains(
              '  mint a public key for `staging` (sandbox) and write it to '
              'build.yaml\n',
            ),
          );
          expect(
            stdout.toString(),
            contains(
              'Minted public key 13 for `staging` (sandbox) and wrote it to '
              'build.yaml.\n',
            ),
          );
          expect(stdout.toString(), isNot(contains('No publishable key')));
          expect(stdout.toString(), isNot(contains('no delivery keys')));

          stdout.clear();
          expect(await init(), 0, reason: stderr.toString());
          expect(mints, hasLength(1));
          expect(deliveryOptions()!['api_key'], _mintedKey);
          expect(stdout.toString(), isNot(contains('mint a public key')));
          expect(stdout.toString(), isNot(contains('No publishable key')));
        },
      );

      test('a rerun adds a delivery key the server now lists', () async {
        await seedCredential(store);
        expect(await init(), 0, reason: stderr.toString());
        const next = '7:AgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgI=';

        expect(
          await RestageCli(
            stdout: stdout,
            stderr: stderr,
            credentialStore: store,
            httpClient: _discoveryClient(
              onDeliveryKeys: (body) {
                expect(body['projectSlug'], 'default-project');
                expect(body['appSlug'], 'default-app');
                expect(body['organizationId'], 7);
                return http.Response(jsonEncode([next, _deliveryKey]), 200);
              },
            ),
          ).run([
            '--non-interactive',
            'init',
            '--directory',
            tempDir.path,
            '--no-starter',
            '--no-add-deps',
          ]),
          0,
          reason: stderr.toString(),
        );
        expect(deliveryOptions()!['delivery_keys'], [_deliveryKey, next]);
      });

      test('a failed key read finishes init and says so', () async {
        await seedCredential(store);
        expect(
          await RestageCli(
            stdout: stdout,
            stderr: stderr,
            credentialStore: store,
            httpClient: _discoveryClient(
              onMint: _mintResponse,
              onDeliveryKeys: (_) =>
                  throw const SocketException('connection refused'),
            ),
          ).run([
            '--non-interactive',
            'init',
            '--directory',
            tempDir.path,
            '--no-starter',
            '--no-add-deps',
          ]),
          0,
        );
        expect(deliveryOptions()!['api_key'], _mintedKey);
        expect(deliveryOptions()!.containsKey('delivery_keys'), isFalse);
        expect(
          stdout.toString(),
          contains(
            "Could not read the app's delivery keys, so build.yaml lists none. "
            'Could not reach the backend at http://localhost:8080',
          ),
        );
        expect(
          stdout.toString(),
          contains('\nTry running `restage init` again.\n'),
        );
      });

      test('no key, no delivery keys', () async {
        await seedCredential(store);
        expect(await init(onMint: (_) => http.Response('', 503)), 0);
        expect(deliveryOptions(), isNull);
      });

      test('after `restage login --endpoint`, init uses only that server, '
          'with no RESTAGE_BACKEND_URL', () async {
        await seedCredential(store, endpoint: 'https://api.signed-in.example/');
        final hosts = <String>{};
        final inner = _discoveryClient();
        final client = MockClient((request) async {
          hosts.add(request.url.host);
          final copy = http.Request(request.method, request.url)
            ..headers.addAll(request.headers)
            ..bodyBytes = request.bodyBytes;
          return http.Response.fromStream(await inner.send(copy));
        });

        expect(
          await RestageCli(
            stdout: stdout,
            stderr: stderr,
            credentialStore: store,
            httpClient: client,
            environment: const {},
          ).run([
            '--non-interactive',
            'init',
            '--directory',
            tempDir.path,
            '--no-starter',
            '--no-add-deps',
          ]),
          0,
          reason: stderr.toString(),
        );
        expect(hosts, {'api.signed-in.example'});
        final config = (await loadRestageConfig(from: tempDir))!.config;
        expect(config.endpoint, 'https://api.signed-in.example/');
        expect(deliveryOptions(), {
          'api_key': _mintedKey,
          'base_url': 'https://api.signed-in.example',
          'delivery_keys': [_deliveryKey],
        });
        // No ios/ folder, so no iOS first-launch asset either.
        expect(
          File(p.join(tempDir.path, 'pubspec.yaml')).readAsStringSync(),
          isNot(contains('restage_early.json')),
        );
      });

      test('signed out, --sdk-key says how to add the delivery keys', () async {
        expect(
          await _runInit(
            stdout,
            stderr,
            store,
            tempDir,
            extra: const ['--sdk-key', 'rs_pk_sandbox_dev_abc'],
          ),
          0,
          reason: stderr.toString(),
        );
        expect(deliveryOptions()!['api_key'], 'rs_pk_sandbox_dev_abc');
        expect(deliveryOptions()!.containsKey('delivery_keys'), isFalse);
        expect(
          stdout.toString(),
          contains(
            'build.yaml has a publishable key but no delivery keys, so the app '
            'refuses every delivered version and shows its compiled widgets. '
            'Try `restage login`, then run `restage init` again, or list each '
            '`<organizationId>:<key>` line `restage keys delivery` prints, '
            'after its first line, under delivery_keys in build.yaml.\n',
          ),
        );
      });

      test('--sdk-key is written and nothing is minted', () async {
        await seedCredential(store);

        expect(
          await init(extra: const ['--sdk-key', 'rs_pk_sandbox_dev_abc']),
          0,
          reason: stderr.toString(),
        );
        expect(mints, isEmpty);
        expect(deliveryOptions()!['api_key'], 'rs_pk_sandbox_dev_abc');
      });

      test('--dry-run lists the mint and mints nothing', () async {
        await seedCredential(store);

        expect(await init(extra: const ['--dry-run']), 0);
        expect(mints, isEmpty);
        expect(buildYaml().existsSync(), isFalse);
        expect(
          stdout.toString(),
          contains(
            'state file tracking, the service URL, the publishable key and the '
            'delivery keys)\n'
            '  mint a public key for `staging` (sandbox) and write it to '
            'build.yaml\n',
          ),
        );
      });

      http.Response refused(String reason) => http.Response(
        jsonEncode({
          'className': 'UnauthorizedException',
          'data': {
            '__className__': 'UnauthorizedException',
            'resource': 'app:default-app',
            'reason': reason,
          },
        }),
        400,
      );

      test('a non-admin finishes init without a key and is told whom to '
          'ask', () async {
        await seedCredential(store);

        expect(
          await init(onMint: (_) => refused('roleMissing')),
          0,
          reason: stderr.toString(),
        );
        expect(mints, hasLength(1));
        expect(await loadRestageConfig(from: tempDir), isNotNull);
        expect(deliveryOptions(), isNull);
        expect(
          stdout.toString(),
          contains(
            'Wrote build.yaml: state file tracking.\n'
            'Could not mint a publishable key: only an organization admin can '
            "mint one, so the first-launch request isn't built into the app. "
            "Try asking an admin for the app's publishable key, then run "
            '`restage init --sdk-key rs_pk_...`.\n',
          ),
        );
      });

      test('another refusal names it and how to add a key', () async {
        await seedCredential(store);

        expect(
          await init(onMint: (_) => refused('sampleWorkspaceReadOnly')),
          0,
        );
        expect(deliveryOptions(), isNull);
        expect(
          stdout.toString(),
          contains(
            'Could not mint a publishable key, so the first-launch request '
            "isn't built into the app. The demo workspace is read-only. Use "
            'your own organization to make changes.\n'
            'Try running `restage init` again, or `restage init --sdk-key '
            "rs_pk_...` with your app's publishable key.\n",
          ),
        );
      });

      test('an unreachable mint finishes init without a key', () async {
        await seedCredential(store);

        expect(
          await init(
            onMint: (_) => throw const SocketException('connection refused'),
          ),
          0,
          reason: stderr.toString(),
        );
        expect(deliveryOptions(), isNull);
        expect(
          stdout.toString(),
          contains(
            'Could not mint a publishable key, so the first-launch request '
            "isn't built into the app. Could not reach the backend at "
            'http://localhost:8080: SocketException: connection refused\n'
            'To use another server, run `restage login --endpoint <url>`.\n'
            'Try running `restage init` again, or `restage init --sdk-key '
            "rs_pk_...` with your app's publishable key.\n",
          ),
        );
      });

      test('a pubspec init refuses mints nothing', () async {
        await seedCredential(store);
        await _writePubspec(tempDir, 'name: app\ndependencies: [a]\n');

        expect(await init(extra: const ['--add-deps']), 1);
        expect(mints, isEmpty);
        expect(buildYaml().existsSync(), isFalse);
      });

      test('a minted key lists the iOS first-launch request', () async {
        await seedCredential(store);
        Directory(
          p.join(tempDir.path, 'ios', 'Runner'),
        ).createSync(recursive: true);

        expect(await init(), 0, reason: stderr.toString());
        final pubspec = File(
          p.join(tempDir.path, 'pubspec.yaml'),
        ).readAsStringSync();
        expect(pubspec, contains('ios/Runner/restage_early.json'));
        expect(
          File(
            p.join(tempDir.path, 'ios', 'Runner', 'restage_early.json'),
          ).existsSync(),
          isTrue,
        );
      });

      test('a refused mint leaves the iOS request unlisted', () async {
        await seedCredential(store);
        Directory(
          p.join(tempDir.path, 'ios', 'Runner'),
        ).createSync(recursive: true);

        expect(await init(onMint: (_) => refused('roleMissing')), 0);
        final pubspec = File(
          p.join(tempDir.path, 'pubspec.yaml'),
        ).readAsStringSync();
        expect(pubspec, isNot(contains('restage_early.json')));
        expect(
          File(
            p.join(tempDir.path, 'ios', 'Runner', 'restage_early.json'),
          ).existsSync(),
          isFalse,
        );
      });

      test(
        'over MCP, every slug given, init mints and names its tools',
        () async {
          await seedCredential(store);
          Future<int?> mcpInit(
            http.Response Function(Map<String, dynamic>) mint,
          ) =>
              RestageCli(
                stdout: stdout,
                stderr: stderr,
                credentialStore: store,
                hasTerminal: () => false,
                interactiveFactory: (_) => const NonInteractive(),
                selectorSyntax: SelectorSyntax.mcp,
                httpClient: _discoveryClient(
                  onMint: (body) {
                    mints.add(body);
                    return mint(body);
                  },
                ),
              ).run([
                'init',
                '-C',
                tempDir.path,
                '--project',
                'default-project',
                '--app',
                'default-app',
                '--env',
                'staging',
                '--no-starter',
                '--no-add-deps',
              ]);

          expect(await mcpInit((_) => refused('sampleWorkspaceReadOnly')), 0);
          expect(
            stdout.toString(),
            contains(
              '\nTry running restage_init again, or restage_init with sdkKey: '
              "rs_pk_... with your app's publishable key.\n",
            ),
          );

          stdout.clear();
          expect(await mcpInit(_mintResponse), 0, reason: stderr.toString());
          expect(mints, hasLength(2));
          expect(deliveryOptions()!['api_key'], _mintedKey);
        },
      );

      test('a kept config naming another environment mints nothing, and '
          '--env mints for it without changing the config', () async {
        await seedCredential(store);
        const kept =
            'project: default-project\napp: default-app\n'
            'defaultEnvironment: production\nplane: sandbox\n';
        final config = File(p.join(tempDir.path, 'restage_config.yaml'))
          ..writeAsStringSync(kept);
        const grid = [('staging', 'sandbox'), ('production', 'sandbox')];

        expect(await init(grid: grid), 0, reason: stderr.toString());
        expect(mints, isEmpty);
        expect(deliveryOptions(), isNull);
        expect(
          stdout.toString(),
          contains(
            'restage_config.yaml was kept and does not name the `staging` '
            'environment init found, so init minted no publishable key and '
            "the first-launch request isn't built into the app. Try "
            '`restage init --env production` to mint a key for the '
            'environment in restage_config.yaml.\n',
          ),
        );

        stdout.clear();
        expect(
          await init(grid: grid, extra: const ['--env', 'production']),
          0,
          reason: stderr.toString(),
        );
        expect(mints, hasLength(1));
        expect(mints.single, containsPair('environmentSlug', 'production'));
        expect(deliveryOptions()!['api_key'], _mintedKey);
        expect(config.readAsStringSync(), kept);
      });

      test('a kept config naming the found environment gets a key', () async {
        await seedCredential(store);
        await File(p.join(tempDir.path, 'restage_config.yaml')).writeAsString(
          'project: default-project\napp: default-app\n'
          'defaultEnvironment: staging\nplane: sandbox\n',
        );

        expect(await init(), 0, reason: stderr.toString());
        expect(mints, hasLength(1));
        expect(deliveryOptions()!['api_key'], _mintedKey);
      });

      test(
        'signed out, nothing is minted and init says how to get one',
        () async {
          expect(
            await _runInit(stdout, stderr, store, tempDir),
            0,
            reason: stderr.toString(),
          );
          expect(deliveryOptions(), isNull);
          expect(
            stdout.toString(),
            contains(
              "No publishable key, so the first-launch request isn't built into "
              'the app. Try `restage login`, then run `restage init` again to '
              'mint one, or `restage init --sdk-key rs_pk_...`.\n',
            ),
          );
        },
      );
    });

    group('an existing restage_config.yaml', () {
      const existing =
          'project: p\napp: a\ndefaultEnvironment: dev\n'
          'plane: sandbox\nrecordGit: true\nflutterRoot: ../flutter\n';
      const settings =
          'endpoint: https://backend.example/\nplane: live\n'
          'recordGit: true\nflutterRoot: ../flutter\ndeclareAssets: true\n'
          'previewWrapper: lib/restage_preview.dart#wrapPreview\n'
          'organizationId: 3\nappId: 4\n'
          'environmentTargetId: 5\nnamedEnvironmentId: 6\n';
      const retargeted =
          'Updated the target in restage_config.yaml to match your flags. '
          'Other settings are unchanged.';

      void expectSettingsKept(RestageConfig config) {
        expect(config.recordGit, isTrue);
        expect(config.flutterRoot, '../flutter');
        expect(config.declareAssets, isTrue);
        expect(config.previewWrapper, 'lib/restage_preview.dart#wrapPreview');
      }

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

      test('signed out, a retarget replaces only the flagged field', () async {
        configFile.writeAsStringSync(
          'organization: acme\nproject: p\napp: old\ndefaultEnvironment: dev\n'
          '$settings',
        );
        final exitCode = await _runInit(stdout, stderr, store, tempDir);

        expect(exitCode, 0, reason: stderr.toString());
        final config = (await loadRestageConfig(from: tempDir))!.config;
        expect(config.app, 'a');
        expect(config.organization, 'acme');
        expect(config.project, 'p');
        expect(config.defaultEnvironment, 'dev');
        expect(config.endpoint, 'https://backend.example/');
        expect(config.plane, RuntimePlane.live);
        expectSettingsKept(config);
        expect(config.organizationId, 3);
        expect(config.appId, isNull);
        expect(config.environmentTargetId, isNull);
        expect(config.namedEnvironmentId, isNull);
        expect(stdout.toString(), contains(retargeted));
      });

      test('signed in, a retarget keeps the target it was not given', () async {
        await seedCredential(store, endpoint: 'https://backend.example/');
        configFile.writeAsStringSync(
          'organization: default\nproject: default-project\napp: old\n'
          'defaultEnvironment: production\n$settings',
        );
        final exitCode =
            await RestageCli(
              stdout: stdout,
              stderr: stderr,
              credentialStore: store,
              httpClient: _discoveryClient(
                grid: [('staging', 'sandbox'), ('production', 'live')],
              ),
            ).run([
              '--non-interactive',
              'init',
              '--directory',
              tempDir.path,
              '--no-starter',
              '--no-add-deps',
              '--app',
              'default-app',
            ]);

        expect(exitCode, 0, reason: stderr.toString());
        final config = (await loadRestageConfig(from: tempDir))!.config;
        expect(config.app, 'default-app');
        expect(config.organization, 'default');
        expect(config.project, 'default-project');
        expect(config.defaultEnvironment, 'production');
        expect(config.endpoint, 'https://backend.example/');
        expect(config.plane, RuntimePlane.live);
        expectSettingsKept(config);
        expect(config.organizationId, 7);
        expect(config.appId, 5);
        expect(config.environmentTargetId, 12);
        expect(config.namedEnvironmentId, 10);
        expect(stdout.toString(), contains(retargeted));
      });

      for (final (flag, value) in [
        ('--organization', 'acme'),
        ('--plane', 'live'),
      ]) {
        test('a $flag the file does not hold updates the target', () async {
          final exitCode = await _runInit(
            stdout,
            stderr,
            store,
            tempDir,
            extra: [flag, value],
          );

          expect(exitCode, 0, reason: stderr.toString());
          final config = (await loadRestageConfig(from: tempDir))!.config;
          expect(config.organization, flag == '--organization' ? 'acme' : null);
          expect(
            config.plane,
            flag == '--plane' ? RuntimePlane.live : RuntimePlane.sandbox,
          );
          expect(config.recordGit, isTrue);
          expect(config.flutterRoot, '../flutter');
          expect(stdout.toString(), contains(retargeted));
        });
      }

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
      expect(
        stdout.toString(),
        contains(
          "No publishable key, so the first-launch request isn't built into "
          'the app. Try running `restage init` again once Restage is '
          'reachable, or `restage init --sdk-key rs_pk_...`.\n',
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
  http.Response Function(Map<String, dynamic> body)? onMint,
  http.Response Function(Map<String, dynamic> body)? onDeliveryKeys,
}) => mockHttpClient((request) {
  final body = jsonDecode(request.body) as Map<String, dynamic>;
  if (request.url.path == '/deliveryKeys') {
    expect(body['method'], 'list');
    return (onDeliveryKeys ??
        (_) => http.Response(jsonEncode([_deliveryKey]), 200))(body);
  }
  if (request.url.path == '/apiKey') {
    expect(body['method'], 'mintKey');
    return (onMint ?? _mintResponse)(body);
  }
  onRead?.call();
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

const _mintedKey = 'rs_pk_sandbox_staging_0123456789abcdef';
const _deliveryKey = '7:AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=';

http.Response _mintResponse(Map<String, dynamic> body) => http.Response(
  jsonEncode({
    'view': {
      'id': 13,
      'kind': 'public',
      'keyPrefix': 'rs_pk_sandbox_st',
      'environmentSlug': body['environmentSlug'],
      'target': {
        '__className__': 'EnvironmentTargetRef',
        'environmentTargetId': body['environmentTargetId'],
        'namedEnvironmentId': 9,
        'environmentSlug': body['environmentSlug'],
        'runtimePlane': body['runtimePlane'],
      },
    },
    'plaintext': _mintedKey,
  }),
  200,
);

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

/// [node] as plain maps, lists and scalars.
Object? _plain(Object? node) => switch (node) {
  YamlMap() => {
    for (final entry in node.entries) entry.key as String: _plain(entry.value),
  },
  YamlList() => [for (final value in node) _plain(value)],
  _ => node,
};
