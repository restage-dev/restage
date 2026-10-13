import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/cli.dart';
import 'package:restage_cli/src/credentials/credential.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/receipts/release_recorder.dart';
import 'package:restage_cli/src/receipts/source_boundary.dart';
import 'package:restage_cli/src/render_bundles/bundle_source.dart';
import 'package:restage_cli/src/render_bundles/flutter_render_bundle_builder.dart';
import 'package:restage_cli/src/render_bundles/flutter_toolchain.dart';
import 'package:restage_cli/src/render_bundles/generated_widget_catalog.dart';
import 'package:restage_cli/src/render_bundles/render_bundle_archive.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '../_helpers/test_fixtures.dart';

void main() {
  late Directory root;
  late FileCredentialStore store;
  late StringBuffer stdout;
  late StringBuffer stderr;
  late _FakeCatalog catalogStep;
  late _FakeSource sourceStep;
  late ReleaseRecorder recorder;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('build_push_test_');
    store = FileCredentialStore(p.join(root.path, 'credentials'));
    stdout = StringBuffer();
    stderr = StringBuffer();
    catalogStep = _FakeCatalog();
    sourceStep = _FakeSource();
    await store.write(
      const Credential(
        endpoint: 'http://api.restage.localhost:8080/',
        kind: CredentialKind.authKey,
        authToken: 'key:private',
      ),
    );
    await seedRestageConfig(root, 'demo', 'mobile');
    // A recorder over a repository that answers without a real Git.
    recorder = await ReleaseRecorder.open(
      projectRoot: root,
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
        if (command.startsWith('rev-parse --absolute-git-dir')) {
          return ProcessResult(0, 0, '${p.join(root.path, '.git')}\n', '');
        }
        return ProcessResult(0, 0, '', '');
      },
    );
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  test('a push to a named head reports its version and files', () async {
    final builder = _FakeBuilder(Uint8List.fromList(<int>[1, 2, 3]));
    final calls = <String>[];
    final client = _pushClient(
      builder.archive,
      onRpcBody: (body) => calls.add(body['method'] as String),
    );

    final exit = await RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
      httpClient: client,
      renderBundleBuilder: builder,
      renderBundleFlutterToolchain: _fakeFlutter,
      renderBundleCatalog: catalogStep.call,
      renderBundleSource: sourceStep.call,
    ).run(<String>['build', 'push', '-C', root.path, '--env', 'staging']);
    expect(exit, 0, reason: stderr.toString());
    expect(calls, <String>['prepare', 'commit']);
    // Only --record-git holds dependencies outside the repository to account.
    expect(sourceStep.recordGit, isFalse);
    expect(builder.projectRoot?.path, root.path);
    expect(
      builder.parentOrigin,
      Uri.parse('http://dashboard.restage.localhost:8082'),
    );
    expect(builder.catalogJson, '{"libraries":{},"widgets":[]}');
    expect(stdout.toString(), contains('mobile staging version 4'));
    expect(stdout.toString(), contains('Every file was already stored'));
    expect(stderr.toString(), isEmpty);
  });

  for (final organization in [null, 'acme', 'other-org']) {
    test(
      'organization selectors agree before a build upload: $organization',
      () async {
        await seedRestageConfig(
          root,
          'demo',
          'mobile',
          organization: 'configured-org',
        );
        final builder = _FakeBuilder(Uint8List.fromList(<int>[1, 2, 3]));
        final calls = <String>[];
        final exit =
            await RestageCli(
              stdout: stdout,
              stderr: stderr,
              credentialStore: store,
              httpClient: _pushClient(
                builder.archive,
                organizationId: 7,
                onRpcBody: (body) => calls.add(body['method'] as String),
              ),
              renderBundleBuilder: builder,
              renderBundleFlutterToolchain: _fakeFlutter,
              renderBundleCatalog: catalogStep.call,
              renderBundleSource: sourceStep.call,
              environment: const {},
            ).run([
              'build',
              'push',
              '-C',
              root.path,
              '--organization-id=7',
              if (organization != null) '--organization=$organization',
              '--env=staging',
            ]);

        if (organization == 'other-org') {
          expect(exit, 1);
          expect(calls, isEmpty);
          expect(stderr.toString(), contains('Could not resolve organization'));
        } else {
          expect(exit, 0, reason: stderr.toString());
          expect(calls, ['prepare', 'commit']);
        }
      },
    );
  }

  test('the resolved Flutter reaches the generator and the build', () async {
    final builder = _FakeBuilder(Uint8List.fromList(<int>[1, 2, 3]));
    String? seenFlagRoot;
    String? seenConfigRoot;
    File(p.join(root.path, 'restage_config.yaml')).writeAsStringSync(
      'project: demo\napp: mobile\nflutterRoot: sdk/flutter\n',
    );

    final exit = await RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
      httpClient: _pushClient(builder.archive),
      renderBundleBuilder: builder,
      renderBundleFlutterToolchain:
          ({required projectRoot, String? flagRoot, String? configRoot}) async {
            seenFlagRoot = flagRoot;
            seenConfigRoot = configRoot;
            return const FlutterToolchain(
              executable: '/pinned/bin/flutter',
              source: 'PATH',
              version: _flutterVersion,
            );
          },
      renderBundleCatalog: catalogStep.call,
      renderBundleSource: sourceStep.call,
    ).run(<String>['build', 'push', '-C', root.path, '--env', 'staging']);

    expect(exit, 0, reason: stderr.toString());
    expect(seenFlagRoot, isNull);
    expect(seenConfigRoot, p.join(root.absolute.path, 'sdk', 'flutter'));
    expect(catalogStep.flutterExecutable, '/pinned/bin/flutter');
    expect(builder.flutterExecutable, '/pinned/bin/flutter');
  });

  test('no usable Flutter stops the push before the build', () async {
    final builder = _FakeBuilder(Uint8List.fromList(<int>[1, 2, 3]));

    final exit =
        await RestageCli(
          stdout: stdout,
          stderr: stderr,
          credentialStore: store,
          httpClient: _pushClient(builder.archive),
          renderBundleBuilder: builder,
          renderBundleFlutterToolchain:
              ({required projectRoot, String? flagRoot, String? configRoot}) =>
                  throw const FlutterToolchainException(
                    'Builds need Flutter X.',
                  ),
          renderBundleCatalog: catalogStep.call,
          renderBundleSource: sourceStep.call,
        ).run(<String>[
          'build',
          'push',
          '-C',
          root.path,
          '--flutter-root',
          '/elsewhere',
        ]);

    expect(exit, 1);
    expect(
      stderr.toString(),
      'Could not build the render bundle. Builds need Flutter X.\n',
    );
    expect(catalogStep.calls, 0);
    expect(builder.projectRoot, isNull);
  });

  test('a deployed push trusts the origins the server names', () async {
    await store.write(
      const Credential(
        endpoint: 'https://api.restage.dev/',
        kind: CredentialKind.authKey,
        authToken: 'key:private',
      ),
    );
    await seedRestageConfig(
      root,
      'demo',
      'mobile',
      endpoint: 'https://api.restage.dev/',
    );
    final builder = _FakeBuilder(Uint8List.fromList(<int>[1, 2, 3]));
    final client = _withOrigins(
      (request) async {
        expect(request.url.host, 'api.restage.dev');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        switch (body['method']) {
          case 'prepare':
            return http.Response(
              jsonEncode(<String, Object?>{
                'uploadToken': 'token-1',
                'headReference': 'staging',
                'expiresAt': DateTime.utc(2030).toIso8601String(),
                'blobUploadUrl':
                    'https://bundles.restage.dev/render-bundles/v1/blob',
                'missingContentHashes': <String>[],
                'uploadConcurrency': 3,
                'maxFileTransferBytes': 24 * 1024 * 1024,
              }),
              200,
            );
          case 'commit':
            return http.Response(
              jsonEncode(<String, Object?>{
                'version': <String, Object?>{
                  'version': 1,
                  'contentHash': 'sha256:${'a' * 64}',
                },
                'organizationId': 7,
                'organizationSlug': 'acme',
                'headReference': 'staging',
                'reactivated': false,
              }),
              200,
            );
          default:
            fail('unexpected call: ${body['method']}');
        }
      },
      dashboard: 'https://dashboard.restage.dev',
      bundles: 'https://bundles.restage.dev',
    );

    final exit = await RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
      httpClient: client,
      renderBundleBuilder: builder,
      renderBundleFlutterToolchain: _fakeFlutter,
      renderBundleCatalog: catalogStep.call,
      renderBundleSource: sourceStep.call,
    ).run(<String>['build', 'push', '-C', root.path, '--env', 'staging']);

    expect(exit, 0, reason: stderr.toString());
    expect(builder.parentOrigin, Uri.parse('https://dashboard.restage.dev'));
    expect(stdout.toString(), contains('mobile staging version 1'));
    expect(stderr.toString(), isEmpty);
  });

  test('a build that produced nothing is refused', () async {
    final exit = await RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
      httpClient: _withOrigins((_) async => fail('nothing to upload')),
      renderBundleBuilder: _FakeBuilder.empty(),
      renderBundleFlutterToolchain: _fakeFlutter,
      renderBundleCatalog: catalogStep.call,
      renderBundleSource: sourceStep.call,
    ).run(<String>['build', 'push', '-C', root.path]);

    expect(exit, 2);
    expect(stderr.toString(), 'Could not build the render bundle.\n');
  });

  test('a server origin that is not a bare origin is refused', () async {
    for (final (dashboard, bundles) in <(String, String)>[
      ('http://dashboard.restage.localhost:8082/shell', _localBundles),
      ('not-an-origin', _localBundles),
      (_localDashboard, 'ftp://bundles.restage.localhost:8081'),
      (_localDashboard, 'http://user@bundles.restage.localhost:8081'),
    ]) {
      final builder = _FakeBuilder(Uint8List.fromList(<int>[1]));
      var networkCalls = 0;

      final exit = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        httpClient: _withOrigins(
          (_) async {
            networkCalls++;
            return http.Response('', 500);
          },
          dashboard: dashboard,
          bundles: bundles,
        ),
        renderBundleBuilder: builder,
        renderBundleFlutterToolchain: _fakeFlutter,
        renderBundleCatalog: catalogStep.call,
        renderBundleSource: sourceStep.call,
      ).run(<String>['build', 'push', '-C', root.path]);

      expect(exit, 1, reason: '$dashboard $bundles');
      expect(
        stderr.toString(),
        'Could not read where builds go from the server.\n',
        reason: '$dashboard $bundles',
      );
      expect(builder.projectRoot, isNull);
      expect(networkCalls, 0);
      stderr.clear();
    }
  });

  test('an https server may not name plain http origins', () async {
    await store.write(
      const Credential(
        endpoint: 'https://api.example.test/',
        kind: CredentialKind.authKey,
        authToken: 'key:private',
      ),
    );
    await seedRestageConfig(
      root,
      'demo',
      'mobile',
      endpoint: 'https://api.example.test/',
    );
    final builder = _FakeBuilder(Uint8List.fromList(<int>[1]));

    final exit = await RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
      httpClient: _withOrigins(
        (_) async => fail('no call after the origins'),
        dashboard: 'http://dashboard.example.test',
        bundles: 'https://bundles.example.test',
      ),
      renderBundleBuilder: builder,
      renderBundleFlutterToolchain: _fakeFlutter,
      renderBundleCatalog: catalogStep.call,
      renderBundleSource: sourceStep.call,
    ).run(<String>['build', 'push', '-C', root.path]);

    expect(exit, 1);
    expect(builder.projectRoot, isNull);
  });

  test('a server that takes no builds says so before the build', () async {
    final builder = _FakeBuilder(Uint8List.fromList(<int>[1]));
    final exit = await RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
      httpClient: _withOrigins(
        (_) async => fail('no call after the origins read'),
        refusal: 'builds_unavailable',
      ),
      renderBundleBuilder: builder,
      renderBundleFlutterToolchain: _fakeFlutter,
      renderBundleCatalog: catalogStep.call,
      renderBundleSource: sourceStep.call,
    ).run(<String>['build', 'push', '-C', root.path]);

    expect(exit, 1);
    expect(stderr.toString(), 'This server does not accept builds.\n');
    expect(builder.projectRoot, isNull);
  });

  test(
    'a named environment reaches prepare, the upload and the read-back',
    () async {
      const environment = 'staging';
      final builder = _FakeBuilder(Uint8List.fromList(<int>[4, 5, 6]));
      final rpcBodies = <Map<String, dynamic>>[];
      final client = _pushClient(
        builder.archive,
        version: 2,
        missingContentHashes: <String>[
          CapabilitySidecar.hashBlob(builder.appFiles['main.dart.wasm']!),
        ],
        onRpcBody: rpcBodies.add,
        onAuthorization: (_) {},
      );

      final exit = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        httpClient: client,
        renderBundleBuilder: builder,
        renderBundleFlutterToolchain: _fakeFlutter,
        renderBundleCatalog: catalogStep.call,
        renderBundleSource: sourceStep.call,
      ).run(<String>['build', 'push', '-C', root.path, '--env', environment]);

      expect(exit, 0, reason: stderr.toString());
      expect(rpcBodies.map((body) => body['method']), <String>[
        'prepare',
        'commit',
      ]);
      expect(rpcBodies.first['projectSlug'], 'demo');
      expect(rpcBodies.first['appSlug'], 'mobile');
      expect(rpcBodies.first['environment'], environment);
      expect(stdout.toString(), contains('mobile $environment version 2'));
      expect(stdout.toString(), contains('Moved 1 of 3 app files'));
      expect(stderr.toString(), isEmpty);
    },
  );

  test(
    'an edge refusal reports its status instead of one generic line',
    () async {
      final builder = _FakeBuilder(Uint8List.fromList(<int>[7, 8, 9]));
      var uploadCalls = 0;
      final client = _withOrigins((request) async {
        if (request.url.port == 8081) {
          uploadCalls++;
          return http.Response('request entity too large', 413);
        }
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['method'], 'prepare');
        return http.Response(
          jsonEncode(<String, Object?>{
            'uploadToken': 'token-1',
            'headReference': 'staging',
            'expiresAt': DateTime.utc(2030).toIso8601String(),
            'blobUploadUrl':
                'http://bundles.restage.localhost:8081/render-bundles/v1/blob',
            'missingContentHashes': <String>[
              CapabilitySidecar.hashBlob(builder.appFiles['index.html']!),
            ],
            'uploadConcurrency': 3,
            'maxFileTransferBytes': 24 * 1024 * 1024,
          }),
          200,
        );
      });

      final exit = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        httpClient: client,
        renderBundleBuilder: builder,
        renderBundleFlutterToolchain: _fakeFlutter,
        renderBundleCatalog: catalogStep.call,
        renderBundleSource: sourceStep.call,
      ).run(<String>['build', 'push', '-C', root.path]);

      expect(exit, 2);
      expect(uploadCalls, 1);
      expect(
        stdout.toString(),
        'Building with Flutter $_flutterVersion at /sdk (PATH).\n',
      );
      expect(
        stderr.toString(),
        'Could not upload the render bundle (HTTP 413: something between '
        'this machine and the service refused the body size, which was '
        '${gzip.encode(builder.appFiles['index.html']!).length} '
        'compressed bytes).\n',
      );
      expect(stderr.toString(), isNot(contains('request entity too large')));
    },
  );

  test('a build past the raw ceiling reports its measured size', () async {
    var networkCalls = 0;
    final builder = _FakeBuilder(Uint8List(renderBundleMaxArchiveBytes + 1));
    final builtBytes = builder.appFiles.values.fold<int>(
      0,
      (total, bytes) => total + bytes.length,
    );

    final exit = await RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
      httpClient: _withOrigins((_) async {
        networkCalls++;
        return http.Response('', 500);
      }),
      renderBundleBuilder: builder,
      renderBundleFlutterToolchain: _fakeFlutter,
      renderBundleCatalog: catalogStep.call,
      renderBundleSource: sourceStep.call,
    ).run(<String>['build', 'push', '-C', root.path]);

    expect(exit, 2);
    expect(networkCalls, 0);
    expect(
      stderr.toString(),
      'Could not upload the render bundle: built $builtBytes bytes, over the '
      '$renderBundleMaxArchiveBytes byte limit (64 MiB).\n',
    );
  });

  test('build failure is generic and performs no network operation', () async {
    var networkCalls = 0;
    final exit = await RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
      httpClient: _withOrigins((_) async {
        networkCalls++;
        return http.Response('', 500);
      }),
      renderBundleBuilder: _FailingBuilder(),
      renderBundleFlutterToolchain: _fakeFlutter,
      renderBundleCatalog: catalogStep.call,
      renderBundleSource: sourceStep.call,
    ).run(<String>['build', 'push', '-C', root.path]);

    expect(exit, 2);
    expect(networkCalls, 0);
    expect(stderr.toString(), contains('Could not build the render bundle.'));
    expect(stderr.toString(), isNot(contains('sensitive process output')));
  });

  for (final (error, message) in <(RenderBundleBuildException, String)>[
    (
      const RenderBundleBuildException('factories_missing'),
      'Could not build the render bundle: lib/user_factories.g.dart is '
          'missing. Run `dart run build_runner build`, or drop --no-generate '
          'and let the push run it.',
    ),
    (
      const RenderBundleBuildException('render_host_missing'),
      'Could not build the render bundle: the restage package this app uses '
          'is too old to build one. Upgrade restage and push again.',
    ),
    (
      const RenderBundleBuildException('dependencies_unresolved'),
      "Could not build the render bundle: this app's dependencies are not "
          'resolved. Run `flutter pub get` and push again.',
    ),
    (
      const RenderBundleBuildException(
        'dependencies_failed',
        detail: '.restage/build/render_bundle',
      ),
      'Could not build the render bundle: its dependencies did not resolve. '
          'Run `flutter pub get` in .restage/build/render_bundle to see why.',
    ),
    (
      const RenderBundleBuildException(
        'flutter_build_failed',
        detail: '.restage/build/render_bundle',
      ),
      'Could not build the render bundle: `flutter build web` failed. Run '
          '`flutter build web --wasm` in .restage/build/render_bundle to see '
          'why.',
    ),
  ]) {
    test('${error.reason} is named', () async {
      final exit = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        httpClient: _withOrigins((_) async => http.Response('', 500)),
        renderBundleBuilder: _FailingBuilder(error),
        renderBundleFlutterToolchain: _fakeFlutter,
        renderBundleCatalog: catalogStep.call,
        renderBundleSource: sourceStep.call,
      ).run(<String>['build', 'push', '-C', root.path]);

      expect(exit, 2);
      expect(stderr.toString(), '$message\n');
    });
  }

  test('a build that wrote no engine names how to change Flutter', () async {
    final exit = await RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
      httpClient: _withOrigins((_) async => http.Response('', 500)),
      renderBundleBuilder: _FailingBuilder(
        const RenderBundleBuildException('engine_missing'),
      ),
      renderBundleFlutterToolchain: _fakeFlutter,
      renderBundleCatalog: catalogStep.call,
      renderBundleSource: sourceStep.call,
    ).run(<String>['build', 'push', '-C', root.path]);

    expect(exit, 2);
    expect(
      stderr.toString(),
      'Could not build the render bundle: `flutter build web` wrote no '
      'engine files. To build with a different Flutter, run `restage build '
      'push --flutter-root <sdk directory>`, set `flutterRoot` in '
      'restage_config.yaml, or set FLUTTER_ROOT.\n',
    );
  });

  test('a refusal with no sentence of its own still names it', () async {
    final builder = _FakeBuilder(Uint8List.fromList(<int>[1, 2, 3]));
    final exit = await RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
      httpClient: _pushClient(
        builder.archive,
        organizationId: 7,
        prepareRefusal: 'required_file_missing',
      ),
      renderBundleBuilder: builder,
      renderBundleFlutterToolchain: _fakeFlutter,
      renderBundleCatalog: catalogStep.call,
      renderBundleSource: sourceStep.call,
    ).run(<String>['build', 'push', '-C', root.path, '--env', 'staging']);

    expect(exit, 2);
    expect(
      stderr.toString(),
      'Could not upload the render bundle (HTTP 403, refused: '
      'required_file_missing).\n',
    );
  });

  test('an operator-actionable refusal reads as one sentence', () async {
    final builder = _FakeBuilder(Uint8List.fromList(<int>[1, 2, 3]));
    final exit = await RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
      httpClient: _pushClient(
        builder.archive,
        organizationId: 7,
        prepareRefusal: 'upload_key_unavailable',
      ),
      renderBundleBuilder: builder,
      renderBundleFlutterToolchain: _fakeFlutter,
      renderBundleCatalog: catalogStep.call,
      renderBundleSource: sourceStep.call,
    ).run(<String>['build', 'push', '-C', root.path, '--env', 'staging']);

    expect(exit, 2);
    expect(
      stderr.toString(),
      'The service could not mint the credential an upload needs, so nothing '
      'was stored. Try again; if it keeps happening the service is '
      'degraded.\n',
    );
  });

  test('an engine Flutter never published is named', () async {
    final builder = _FakeBuilder(Uint8List.fromList(<int>[1, 2, 3]));
    final exit = await RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
      httpClient: _pushClient(
        builder.archive,
        organizationId: 7,
        prepareRefusal: 'engine_not_released',
      ),
      renderBundleBuilder: builder,
      renderBundleFlutterToolchain: _fakeFlutter,
      renderBundleCatalog: catalogStep.call,
      renderBundleSource: sourceStep.call,
    ).run(<String>['build', 'push', '-C', root.path, '--env', 'staging']);

    expect(exit, 2);
    expect(
      stderr.toString(),
      "Could not upload the render bundle: this build's Flutter engine is not "
      'one Flutter published, so the dashboard cannot load it. Build with a '
      'released Flutter SDK; a custom or local engine is not supported for '
      'previews.\n',
    );
  });

  test('a boundary that will not resolve refuses before the catalog', () async {
    var networkCalls = 0;
    final builder = _FakeBuilder(Uint8List.fromList(<int>[1, 2, 3]));
    final exit = await RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
      httpClient: _withOrigins((_) async {
        networkCalls++;
        return http.Response('', 500);
      }),
      renderBundleBuilder: builder,
      renderBundleFlutterToolchain: _fakeFlutter,
      renderBundleCatalog: catalogStep.call,
      renderBundleSource: (_, {recordGit = false}) async =>
          throw const SourceBoundaryException('The lockfile cannot be read.'),
    ).run(<String>['build', 'push', '-C', root.path]);

    expect(exit, 1);
    expect(stderr.toString(), 'The lockfile cannot be read.\n');
    // The push prints what it built from, so nothing is generated or built
    // until that answer exists.
    expect(catalogStep.calls, 0);
    expect(builder.projectRoot, isNull);
    expect(networkCalls, 0);
  });

  test(
    'refuses a malformed environment before the build or the network',
    () async {
      var networkCalls = 0;
      final builder = _FakeBuilder(Uint8List.fromList(<int>[1]));
      final missingStore = FileCredentialStore(
        p.join(root.path, 'missing-credentials'),
      );

      final exit =
          await RestageCli(
            stdout: stdout,
            stderr: stderr,
            credentialStore: missingStore,
            httpClient: _withOrigins((_) async {
              networkCalls++;
              return http.Response('', 500);
            }),
            renderBundleBuilder: builder,
            renderBundleFlutterToolchain: _fakeFlutter,
            renderBundleCatalog: catalogStep.call,
            renderBundleSource: sourceStep.call,
          ).run(<String>[
            'build',
            'push',
            '-C',
            root.path,
            '--env',
            'Staging/../admin',
          ]);

      expect(exit, 1);
      expect(
        stderr.toString(),
        contains('Refusing the environment `Staging/../admin`'),
      );
      expect(builder.projectRoot, isNull);
      expect(networkCalls, 0);
    },
  );

  test('the push generates the catalog and builds against it', () async {
    final builder = _FakeBuilder(Uint8List.fromList(<int>[1, 2, 3]));
    catalogStep = _FakeCatalog(json: '{"libraries":{"a.b":{}},"widgets":[]}');
    final exit = await RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
      httpClient: _pushClient(builder.archive),
      renderBundleBuilder: builder,
      renderBundleFlutterToolchain: _fakeFlutter,
      renderBundleCatalog: catalogStep.call,
      renderBundleSource: sourceStep.call,
    ).run(<String>['build', 'push', '-C', root.path]);
    expect(exit, 0, reason: stderr.toString());
    expect(catalogStep.calls, 1);
    expect(catalogStep.generate, isTrue);
    expect(builder.catalogJson, '{"libraries":{"a.b":{}},"widgets":[]}');
  });

  test('--no-generate builds against what a previous run produced', () async {
    final builder = _FakeBuilder(Uint8List.fromList(<int>[1, 2, 3]));
    final exit = await RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
      httpClient: _pushClient(builder.archive),
      renderBundleBuilder: builder,
      renderBundleFlutterToolchain: _fakeFlutter,
      renderBundleCatalog: catalogStep.call,
      renderBundleSource: sourceStep.call,
    ).run(<String>['build', 'push', '-C', root.path, '--no-generate']);
    expect(exit, 0, reason: stderr.toString());
    expect(catalogStep.generate, isFalse);
  });

  test('an app registering no widgets of its own still pushes', () async {
    final builder = _FakeBuilder(Uint8List.fromList(<int>[1, 2, 3]));
    catalogStep = _FakeCatalog(registersWidgets: false);
    final exit = await RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
      httpClient: _pushClient(builder.archive),
      renderBundleBuilder: builder,
      renderBundleFlutterToolchain: _fakeFlutter,
      renderBundleCatalog: catalogStep.call,
      renderBundleSource: sourceStep.call,
    ).run(<String>['build', 'push', '-C', root.path]);
    expect(exit, 0, reason: stderr.toString());
    expect(
      stdout.toString(),
      contains('This app registers no widgets of its own.'),
    );
  });

  test('a refused catalog step stops the push before the build', () async {
    final builder = _FakeBuilder(Uint8List.fromList(<int>[1, 2, 3]));
    var networkCalls = 0;
    catalogStep = _FakeCatalog(
      failure: const GeneratedCatalogException('catalog_missing'),
    );
    final exit = await RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
      httpClient: _withOrigins((request) async {
        networkCalls++;
        return http.Response('', 500);
      }),
      renderBundleBuilder: builder,
      renderBundleFlutterToolchain: _fakeFlutter,
      renderBundleCatalog: catalogStep.call,
      renderBundleSource: sourceStep.call,
    ).run(<String>['build', 'push', '-C', root.path]);
    expect(exit, 1);
    expect(builder.projectRoot, isNull);
    expect(networkCalls, 0);
    expect(
      stderr.toString(),
      'No generated widget catalog. Run `dart run build_runner build`, or '
      'drop --no-generate and let the push run it.\n',
    );
  });

  test('a failed generator refuses without printing its output', () async {
    final builder = _FakeBuilder(Uint8List.fromList(<int>[1, 2, 3]));
    catalogStep = _FakeCatalog(
      failure: const GeneratedCatalogException('generate_failed'),
    );
    final exit = await RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
      httpClient: _withOrigins((request) async => http.Response('', 500)),
      renderBundleBuilder: builder,
      renderBundleFlutterToolchain: _fakeFlutter,
      renderBundleCatalog: catalogStep.call,
      renderBundleSource: sourceStep.call,
    ).run(<String>['build', 'push', '-C', root.path]);
    expect(exit, 2);
    expect(
      stderr.toString(),
      'Could not generate the widget catalog. Run '
      '`dart run build_runner build` to see why.\n',
    );
  });

  test('a key pushes as a bearer and brings no organization along', () async {
    await seedRestageConfig(
      root,
      'demo',
      'mobile',
      endpoint: 'http://api.restage.localhost:8080',
    );
    final builder = _FakeBuilder(Uint8List.fromList(<int>[1, 2, 3]));
    final authorizations = <String?>[];
    final rpcBodies = <Map<String, dynamic>>[];
    final exit = await RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
      httpClient: _pushClient(
        builder.archive,
        onAuthorization: authorizations.add,
        onRpcBody: rpcBodies.add,
      ),
      renderBundleBuilder: builder,
      renderBundleFlutterToolchain: _fakeFlutter,
      renderBundleCatalog: catalogStep.call,
      renderBundleSource: sourceStep.call,
      environment: _keyEnvironment,
    ).run(<String>['build', 'push', '-C', root.path]);
    expect(exit, 0, reason: stderr.toString());
    expect(authorizations, isNotEmpty);
    expect(authorizations, everyElement('Bearer $_key'));
    // The key names its own organization on the server, so the push sends none.
    expect(rpcBodies.map((body) => body['method']), <String>[
      'prepare',
      'commit',
    ]);
    expect(
      rpcBodies.every((body) => !body.containsKey('organizationId')),
      isTrue,
    );
  });

  test('a key is never stored and never printed', () async {
    await seedRestageConfig(
      root,
      'demo',
      'mobile',
      endpoint: 'http://api.restage.localhost:8080',
    );
    final builder = _FakeBuilder(Uint8List.fromList(<int>[1, 2, 3]));
    final exit = await RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
      httpClient: _pushClient(builder.archive),
      renderBundleBuilder: builder,
      renderBundleFlutterToolchain: _fakeFlutter,
      renderBundleCatalog: catalogStep.call,
      renderBundleSource: sourceStep.call,
      environment: _keyEnvironment,
    ).run(<String>['build', 'push', '-C', root.path]);
    expect(exit, 0, reason: stderr.toString());
    expect(await store.read(), isNotNull);
    expect((await store.read())!.kind, CredentialKind.authKey);
    expect(
      await File(p.join(root.path, 'credentials')).readAsString(),
      isNot(contains(_key)),
    );
    expect(stdout.toString(), isNot(contains(_key)));
    expect(stderr.toString(), isNot(contains(_key)));
  });

  test('the server names what a key cannot push', () async {
    await seedRestageConfig(
      root,
      'demo',
      'mobile',
      endpoint: 'http://api.restage.localhost:8080',
    );
    for (final (reason, args, message) in <(String, List<String>, String)>[
      (
        'not_a_secret_key',
        <String>[],
        'RESTAGE_API_KEY holds a publishable key. A push needs a secret key '
            'minted with the bundle-push scope.\n',
      ),
      (
        'environment_not_found',
        <String>[],
        'This key is bound to one environment and --env <slug> names '
            'another. Leave it out, or use the key for the environment it '
            'belongs to.\n',
      ),
    ]) {
      final builder = _FakeBuilder(Uint8List.fromList(<int>[1]));
      final exit = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        httpClient: _pushClient(builder.archive, prepareRefusal: reason),
        renderBundleBuilder: builder,
        renderBundleFlutterToolchain: _fakeFlutter,
        renderBundleCatalog: catalogStep.call,
        renderBundleSource: sourceStep.call,
        environment: _keyEnvironment,
      ).run(<String>['build', 'push', '-C', root.path, ...args]);
      expect(exit, 2, reason: reason);
      expect(stderr.toString(), message, reason: reason);
      stderr.clear();
    }
  });

  test('a key the target cannot push with is refused before the build', () async {
    for (final (label, client, args, message)
        in <(String, http.Client, List<String>, String)>[
          (
            'publishable',
            _pushClient(Uint8List(0), secret: false),
            <String>[],
            'RESTAGE_API_KEY holds a publishable key. A push needs a secret key '
                'minted with the bundle-push scope.\n',
          ),
          (
            'unscoped',
            _pushClient(Uint8List(0), scopes: const <String>[]),
            <String>[],
            'This key was not minted with the bundle-push scope, so it cannot '
                'push. Mint a new key with that scope.\n',
          ),
          (
            'another environment',
            _pushClient(Uint8List(0)),
            <String>['--env', 'prod'],
            'The API key belongs to a different app or environment than the one '
                'named.\n',
          ),
        ]) {
      final builder = _FakeBuilder(Uint8List.fromList(<int>[1]));
      final exit = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        httpClient: client,
        renderBundleBuilder: builder,
        renderBundleFlutterToolchain: _fakeFlutter,
        renderBundleCatalog: catalogStep.call,
        renderBundleSource: sourceStep.call,
        environment: _keyEnvironment,
      ).run(<String>['build', 'push', '-C', root.path, ...args]);
      expect(exit, 1, reason: label);
      expect(stderr.toString(), message, reason: label);
      expect(builder.projectRoot, isNull, reason: label);
      stderr.clear();
    }
  });

  test('a key target refusal from the server reads as its sentence', () async {
    final builder = _FakeBuilder(Uint8List.fromList(<int>[1]));
    final exit = await RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
      httpClient: _pushClient(builder.archive, prepareKeyMismatch: true),
      renderBundleBuilder: builder,
      renderBundleFlutterToolchain: _fakeFlutter,
      renderBundleCatalog: catalogStep.call,
      renderBundleSource: sourceStep.call,
      environment: _keyEnvironment,
    ).run(<String>['build', 'push', '-C', root.path]);
    expect(exit, 2);
    expect(
      stderr.toString(),
      'The API key belongs to a different app or environment than the one '
      'named.\n',
    );
  });

  test('a key is never sent to an endpoint the config file names', () async {
    await seedRestageConfig(
      root,
      'demo',
      'mobile',
      endpoint: 'https://api.attacker.example/',
    );
    var networkCalls = 0;
    final builder = _FakeBuilder(Uint8List.fromList(<int>[1]));
    final exit = await RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
      defaultEndpoint: Uri.parse('https://api.restage.dev/'),
      httpClient: MockClient((_) async {
        networkCalls++;
        return http.Response('', 500);
      }),
      renderBundleBuilder: builder,
      renderBundleFlutterToolchain: _fakeFlutter,
      renderBundleCatalog: catalogStep.call,
      renderBundleSource: sourceStep.call,
      environment: const <String, String>{'RESTAGE_API_KEY': _key},
    ).run(<String>['build', 'push', '-C', root.path]);
    expect(exit, 1);
    expect(networkCalls, 0);
    expect(
      stderr.toString(),
      'restage_config.yaml names https://api.attacker.example/, but a key is '
      'sent only to https://api.restage.dev/. Set RESTAGE_BACKEND_URL to push '
      'to that server with a key.\n',
    );
    expect(builder.projectRoot, isNull);
  });

  test(
    'a key goes to the built-in endpoint when nothing else is named',
    () async {
      final hosts = <String>{};
      final builder = _FakeBuilder(Uint8List.fromList(<int>[1, 2, 3]));
      final exit = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        defaultEndpoint: Uri.parse(_localApi),
        httpClient: _pushClient(
          builder.archive,
          onUrl: (url) => hosts.add(url.host),
        ),
        renderBundleBuilder: builder,
        renderBundleFlutterToolchain: _fakeFlutter,
        renderBundleCatalog: catalogStep.call,
        renderBundleSource: sourceStep.call,
        environment: const <String, String>{'RESTAGE_API_KEY': _key},
      ).run(<String>['build', 'push', '-C', root.path]);
      expect(exit, 0, reason: stderr.toString());
      expect(hosts, <String>{'api.restage.localhost'});
    },
  );

  test('origins off the API site are refused before the build', () async {
    await store.write(
      const Credential(
        endpoint: 'https://api.restage.dev/',
        kind: CredentialKind.authKey,
        authToken: 'key:private',
      ),
    );
    await seedRestageConfig(
      root,
      'demo',
      'mobile',
      endpoint: 'https://api.restage.dev/',
    );
    for (final (dashboard, bundles) in <(String, String)>[
      ('https://dashboard.attacker.example', 'https://bundles.restage.dev'),
      ('https://dashboard.restage.dev', 'https://restage.dev.attacker.example'),
      ('https://dashboard.restage.dev', 'http://localhost:8081'),
    ]) {
      final builder = _FakeBuilder(Uint8List.fromList(<int>[1]));
      final exit = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        httpClient: _withOrigins(
          (_) async => fail('no call after the origins'),
          dashboard: dashboard,
          bundles: bundles,
        ),
        renderBundleBuilder: builder,
        renderBundleFlutterToolchain: _fakeFlutter,
        renderBundleCatalog: catalogStep.call,
        renderBundleSource: sourceStep.call,
      ).run(<String>['build', 'push', '-C', root.path]);
      expect(exit, 1, reason: '$dashboard $bundles');
      expect(
        stderr.toString(),
        'Could not read where builds go from the server.\n',
        reason: '$dashboard $bundles',
      );
      expect(builder.projectRoot, isNull);
      stderr.clear();
    }
  });

  test('a refused key names the scope a push needs', () async {
    await seedRestageConfig(
      root,
      'demo',
      'mobile',
      endpoint: 'http://api.restage.localhost:8080',
    );
    final builder = _FakeBuilder(Uint8List.fromList(<int>[1, 2, 3]));
    final exit = await RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
      httpClient: _withOrigins(
        (request) async => http.Response('forbidden: no scope', 403),
      ),
      renderBundleBuilder: builder,
      renderBundleFlutterToolchain: _fakeFlutter,
      renderBundleCatalog: catalogStep.call,
      renderBundleSource: sourceStep.call,
      environment: _keyEnvironment,
    ).run(<String>['build', 'push', '-C', root.path]);
    expect(exit, 2);
    expect(
      stderr.toString(),
      'Could not upload the render bundle: the key was not accepted. A key '
      'pushes only while it holds the bundle-push scope and has not been '
      'revoked.\n',
    );
    expect(stderr.toString(), isNot(contains(_key)));
    // The refusal is the command's own sentence; no server text is shown.
    expect(stderr.toString(), isNot(contains('forbidden')));
  });

  test('a signed-in push keeps the scheme every command uses', () async {
    final builder = _FakeBuilder(Uint8List.fromList(<int>[1, 2, 3]));
    final authorizations = <String?>[];
    final exit = await RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
      httpClient: _pushClient(
        builder.archive,
        onAuthorization: authorizations.add,
      ),
      renderBundleBuilder: builder,
      renderBundleFlutterToolchain: _fakeFlutter,
      renderBundleCatalog: catalogStep.call,
      renderBundleSource: sourceStep.call,
      environment: const <String, String>{},
    ).run(<String>['build', 'push', '-C', root.path]);
    expect(exit, 0, reason: stderr.toString());
    expect(authorizations, isNotEmpty);
    expect(
      authorizations,
      everyElement('Basic ${base64Encode(utf8.encode('key:private'))}'),
    );
  });

  test('a key is refused from the command line', () async {
    final exit = await RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
    ).run(<String>['build', 'push', '-C', root.path, '--api-key', _key]);
    expect(exit, 1);
    expect(stderr.toString(), contains('api-key'));
  });

  test('no signed-in session and no key names both ways in', () async {
    final empty = FileCredentialStore(p.join(root.path, 'empty_credentials'));
    final exit = await RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: empty,
      renderBundleCatalog: catalogStep.call,
      renderBundleSource: sourceStep.call,
      environment: const <String, String>{},
    ).run(<String>['build', 'push', '-C', root.path]);
    expect(exit, 1);
    expect(
      stderr.toString(),
      'Not signed in. Run `restage login`. To push with a key, set '
      'RESTAGE_API_KEY.\n',
    );
  });

  test('the push names the commit it was built from', () async {
    final builder = _FakeBuilder(Uint8List.fromList(<int>[1, 2, 3]));
    final exit = await RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
      httpClient: _pushClient(builder.archive),
      renderBundleBuilder: builder,
      renderBundleFlutterToolchain: _fakeFlutter,
      renderBundleCatalog: catalogStep.call,
      renderBundleSource: sourceStep.call,
    ).run(<String>['build', 'push', '-C', root.path]);
    expect(exit, 0, reason: stderr.toString());
    expect(stdout.toString(), contains('Built from a91f2c3.'));
    // The source is read for the tree the build compiles.
    expect(sourceStep.projectRoot?.path, root.path);
  });

  test('a tree with local changes says so', () async {
    sourceStep = _FakeSource(
      const BundleSource(
        inRepository: true,
        commit: 'a91f2c3d4e5f60718293a4b5c6d7e8f901234567',
        dirty: true,
      ),
    );
    final builder = _FakeBuilder(Uint8List.fromList(<int>[1, 2, 3]));
    final exit = await RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
      httpClient: _pushClient(builder.archive),
      renderBundleBuilder: builder,
      renderBundleFlutterToolchain: _fakeFlutter,
      renderBundleCatalog: catalogStep.call,
      renderBundleSource: sourceStep.call,
    ).run(<String>['build', 'push', '-C', root.path]);
    expect(exit, 0, reason: stderr.toString());
    expect(
      stdout.toString(),
      contains('Built from a91f2c3 with local changes.'),
    );
  });

  test('a push from outside a repository says so', () async {
    sourceStep = _FakeSource(const BundleSource.outsideRepository());
    final builder = _FakeBuilder(Uint8List.fromList(<int>[1, 2, 3]));
    final exit = await RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
      httpClient: _pushClient(builder.archive),
      renderBundleBuilder: builder,
      renderBundleFlutterToolchain: _fakeFlutter,
      renderBundleCatalog: catalogStep.call,
      renderBundleSource: sourceStep.call,
    ).run(<String>['build', 'push', '-C', root.path]);
    expect(exit, 0, reason: stderr.toString());
    expect(
      stdout.toString(),
      contains('Built outside a repository, so no source commit was recorded.'),
    );
  });

  test('two targets at once is refused before any work', () async {
    final builder = _FakeBuilder(Uint8List.fromList(<int>[1]));
    var networkCalls = 0;
    final exit =
        await RestageCli(
          stdout: stdout,
          stderr: stderr,
          credentialStore: store,
          httpClient: _withOrigins((_) async {
            networkCalls++;
            return http.Response('', 500);
          }),
          renderBundleBuilder: builder,
          renderBundleFlutterToolchain: _fakeFlutter,
          renderBundleCatalog: catalogStep.call,
          renderBundleSource: sourceStep.call,
        ).run(<String>[
          'build',
          'push',
          '-C',
          root.path,
          '--env',
          'staging',
          '--personal',
        ]);
    expect(exit, 1);
    expect(stderr.toString(), contains('Name one target'));
    expect(builder.projectRoot, isNull);
    expect(networkCalls, 0);
    expect(catalogStep.calls, 0);
  });

  test('a key cannot push to a personal head', () async {
    final builder = _FakeBuilder(Uint8List.fromList(<int>[1]));
    final exit = await RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
      renderBundleBuilder: builder,
      renderBundleFlutterToolchain: _fakeFlutter,
      renderBundleCatalog: catalogStep.call,
      renderBundleSource: sourceStep.call,
      environment: _keyEnvironment,
    ).run(<String>['build', 'push', '-C', root.path, '--personal']);
    expect(exit, 1);
    expect(
      stderr.toString(),
      contains('A key moves the head of the environment it is bound to'),
    );
    expect(builder.projectRoot, isNull);
  });

  test('--record-git writes the receipt the push earned', () async {
    await seedRestageConfig(root, 'demo', 'mobile', organization: 'acme');
    final builder = _FakeBuilder(Uint8List.fromList(<int>[1, 2, 3]));
    Map<String, Object?>? recorded;
    final exit =
        await RestageCli(
          stdout: stdout,
          stderr: stderr,
          credentialStore: store,
          httpClient: _pushClient(
            builder.archive,
            version: 6,
            organizationId: 7,
          ),
          renderBundleBuilder: builder,
          renderBundleFlutterToolchain: _fakeFlutter,
          renderBundleCatalog: catalogStep.call,
          renderBundleSource: sourceStep.call,
          renderBundleRecorderOpener: ({required projectRoot}) async =>
              recorder,
          renderBundleReceipt:
              ({
                required recorder,
                required organizationId,
                required organization,
                required project,
                required app,
                required head,
                required version,
                required contentHash,
                required engineSetId,
                required dirty,
                required stdout,
                required stderr,
                environment,
                toolchain,
              }) async {
                recorded = <String, Object?>{
                  'organizationId': organizationId,
                  'organization': organization,
                  'project': project,
                  'app': app,
                  'head': head,
                  'version': version,
                  'contentHash': contentHash,
                  'engineSetId': engineSetId,
                  'dirty': dirty,
                  'environment': environment,
                  'toolchain': toolchain,
                };
                return true;
              },
        ).run(<String>[
          'build',
          'push',
          '-C',
          root.path,
          '--env',
          'staging',
          '--record-git',
        ]);

    expect(exit, 0, reason: stderr.toString());
    expect(sourceStep.recordGit, isTrue);
    expect(recorded, isNotNull);
    expect(recorded!['organizationId'], 7);
    expect(recorded!['organization'], 'acme');
    expect(recorded!['app'], 'mobile');
    expect(recorded!['head'], 'staging');
    expect(recorded!['environment'], 'staging');
    expect(recorded!['version'], 6);
    expect(recorded!['dirty'], isFalse);
    expect(recorded!['toolchain'], _flutterVersion);
  });

  test('a push to a personal head records no environment', () async {
    await seedRestageConfig(root, 'demo', 'mobile', organization: 'acme');
    final builder = _FakeBuilder(Uint8List.fromList(<int>[1, 2, 3]));
    String? seenEnvironment = 'unset';
    final exit =
        await RestageCli(
          stdout: stdout,
          stderr: stderr,
          credentialStore: store,
          httpClient: _pushClient(
            builder.archive,
            headReference: 'user/alice',
            organizationId: 7,
          ),
          renderBundleBuilder: builder,
          renderBundleFlutterToolchain: _fakeFlutter,
          renderBundleCatalog: catalogStep.call,
          renderBundleSource: sourceStep.call,
          renderBundleRecorderOpener: ({required projectRoot}) async =>
              recorder,
          renderBundleReceipt:
              ({
                required recorder,
                required organizationId,
                required organization,
                required project,
                required app,
                required head,
                required version,
                required contentHash,
                required engineSetId,
                required dirty,
                required stdout,
                required stderr,
                environment,
                toolchain,
              }) async {
                seenEnvironment = environment;
                return true;
              },
        ).run(<String>[
          'build',
          'push',
          '-C',
          root.path,
          '--personal',
          '--record-git',
        ]);

    expect(exit, 0, reason: stderr.toString());
    expect(seenEnvironment, isNull);
  });

  test('a repository that cannot record stops before the build', () async {
    final builder = _FakeBuilder(Uint8List.fromList(<int>[1, 2, 3]));
    var networkCalls = 0;
    final exit = await RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
      httpClient: _withOrigins((_) async {
        networkCalls++;
        return http.Response('', 500);
      }),
      renderBundleBuilder: builder,
      renderBundleFlutterToolchain: _fakeFlutter,
      renderBundleCatalog: catalogStep.call,
      renderBundleSource: sourceStep.call,
      renderBundleRecorderOpener: ({required projectRoot}) async =>
          throw const ReleaseRecorderException(
            'This app is not in a Git repository.',
          ),
    ).run(<String>['build', 'push', '-C', root.path, '--record-git']);

    expect(exit, 1);
    expect(stderr.toString(), 'This app is not in a Git repository.\n');
    expect(builder.projectRoot, isNull);
    expect(catalogStep.calls, 0);
    expect(networkCalls, 0);
  });

  test('a receipt that will not write leaves the push standing', () async {
    await seedRestageConfig(root, 'demo', 'mobile', organization: 'acme');
    final builder = _FakeBuilder(Uint8List.fromList(<int>[1, 2, 3]));
    final exit =
        await RestageCli(
          stdout: stdout,
          stderr: stderr,
          credentialStore: store,
          httpClient: _pushClient(builder.archive, organizationId: 7),
          renderBundleBuilder: builder,
          renderBundleFlutterToolchain: _fakeFlutter,
          renderBundleCatalog: catalogStep.call,
          renderBundleSource: sourceStep.call,
          renderBundleRecorderOpener: ({required projectRoot}) async =>
              recorder,
          renderBundleReceipt:
              ({
                required recorder,
                required organizationId,
                required organization,
                required project,
                required app,
                required head,
                required version,
                required contentHash,
                required engineSetId,
                required dirty,
                required stdout,
                required stderr,
                environment,
                toolchain,
              }) async => false,
        ).run(<String>[
          'build',
          'push',
          '-C',
          root.path,
          '--env',
          'staging',
          '--record-git',
        ]);

    expect(exit, 2);
    expect(stdout.toString(), contains('mobile staging version 4'));
  });

  test('--organization names the organization a push resolves', () async {
    final builder = _FakeBuilder(Uint8List.fromList(<int>[1, 2, 3]));
    int? recordedOrganizationId;
    final exit =
        await RestageCli(
          stdout: stdout,
          stderr: stderr,
          credentialStore: store,
          httpClient: _pushClient(builder.archive, organizationId: 7),
          renderBundleBuilder: builder,
          renderBundleFlutterToolchain: _fakeFlutter,
          renderBundleCatalog: catalogStep.call,
          renderBundleSource: sourceStep.call,
          renderBundleRecorderOpener: ({required projectRoot}) async =>
              recorder,
          renderBundleReceipt:
              ({
                required recorder,
                required organizationId,
                required organization,
                required project,
                required app,
                required head,
                required version,
                required contentHash,
                required engineSetId,
                required dirty,
                required stdout,
                required stderr,
                environment,
                toolchain,
              }) async {
                recordedOrganizationId = organizationId;
                return true;
              },
        ).run(<String>[
          'build',
          'push',
          '-C',
          root.path,
          '--env',
          'staging',
          '--organization',
          'acme',
          '--record-git',
        ]);

    // The configuration names no organization; the flag is what resolved one.
    expect(exit, 0, reason: stderr.toString());
    expect(recordedOrganizationId, 7);
  });

  test(
    'the receipt names the organization the service filed it under',
    () async {
      final builder = _FakeBuilder(Uint8List.fromList(<int>[1, 2, 3]));
      Map<String, Object?>? recorded;
      final exit =
          await RestageCli(
            stdout: stdout,
            stderr: stderr,
            credentialStore: store,
            httpClient: _pushClient(builder.archive),
            renderBundleBuilder: builder,
            renderBundleFlutterToolchain: _fakeFlutter,
            renderBundleCatalog: catalogStep.call,
            renderBundleSource: sourceStep.call,
            renderBundleRecorderOpener: ({required projectRoot}) async =>
                recorder,
            renderBundleReceipt:
                ({
                  required recorder,
                  required organizationId,
                  required organization,
                  required project,
                  required app,
                  required head,
                  required version,
                  required contentHash,
                  required engineSetId,
                  required dirty,
                  required stdout,
                  required stderr,
                  environment,
                  toolchain,
                }) async {
                  recorded = <String, Object?>{
                    'organizationId': organizationId,
                    'organization': organization,
                  };
                  return true;
                },
          ).run(<String>[
            'build',
            'push',
            '-C',
            root.path,
            '--env',
            'staging',
            '--record-git',
          ]);

      // The configuration names no organization; the service named one.
      expect(exit, 0, reason: stderr.toString());
      expect(recorded, <String, Object?>{
        'organizationId': 7,
        'organization': 'acme',
      });
    },
  );

  test('a key push records the receipt the service filed', () async {
    await seedRestageConfig(
      root,
      'demo',
      'mobile',
      endpoint: 'http://api.restage.localhost:8080',
    );
    final builder = _FakeBuilder(Uint8List.fromList(<int>[1, 2, 3]));
    Map<String, Object?>? recorded;
    final exit = await RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
      httpClient: _pushClient(builder.archive),
      renderBundleBuilder: builder,
      renderBundleFlutterToolchain: _fakeFlutter,
      renderBundleCatalog: catalogStep.call,
      renderBundleSource: sourceStep.call,
      renderBundleRecorderOpener: ({required projectRoot}) async => recorder,
      renderBundleReceipt:
          ({
            required recorder,
            required organizationId,
            required organization,
            required project,
            required app,
            required head,
            required version,
            required contentHash,
            required engineSetId,
            required dirty,
            required stdout,
            required stderr,
            environment,
            toolchain,
          }) async {
            recorded = <String, Object?>{
              'organizationId': organizationId,
              'organization': organization,
            };
            return true;
          },
      environment: _keyEnvironment,
    ).run(<String>['build', 'push', '-C', root.path, '--record-git']);

    // A key resolves no organization on this side; the service names one.
    expect(exit, 0, reason: stderr.toString());
    expect(recorded, <String, Object?>{
      'organizationId': 7,
      'organization': 'acme',
    });
  });

  test('build command is listed in top-level help', () async {
    final exit = await RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
    ).run(const <String>['--help']);
    expect(exit, 0);
    expect(stdout.toString(), contains('build'));
  });
}

const _key =
    'rs_sk_sandbox_staging_a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1';

const _localApi = 'http://api.restage.localhost:8080';

/// A key, and the server the environment says it may be sent to.
const _keyEnvironment = <String, String>{
  'RESTAGE_API_KEY': _key,
  'RESTAGE_BACKEND_URL': _localApi,
};

const _localDashboard = 'http://dashboard.restage.localhost:8082';
const _localBundles = 'http://bundles.restage.localhost:8081';

/// Answers the origins read a push starts with, then defers to [handler].
http.Client _withOrigins(
  MockClientHandler handler, {
  String dashboard = _localDashboard,
  String bundles = _localBundles,
  String? refusal,
}) => MockClient((request) async {
  if (request.url.path.endsWith('/renderBundleUpload') &&
      (jsonDecode(request.body) as Map<String, dynamic>)['method'] ==
          'origins') {
    if (refusal != null) {
      return http.Response(
        jsonEncode(<String, Object?>{
          'className': 'RenderBundleRejectedException',
          'data': <String, Object?>{'reason': refusal},
        }),
        400,
      );
    }
    return http.Response(
      jsonEncode(<String, Object?>{
        'dashboardOrigin': dashboard,
        'bundleOrigin': bundles,
      }),
      200,
    );
  }
  return handler(request);
});

/// Answers the calls one successful push makes.
http.Client _pushClient(
  Uint8List archive, {
  void Function(String?)? onAuthorization,
  void Function(Uri)? onUrl,
  void Function(Map<String, dynamic>)? onRpcBody,
  int version = 4,
  String headReference = 'staging',
  List<String> missingContentHashes = const <String>[],
  int? organizationId,
  String? prepareRefusal,
  bool prepareKeyMismatch = false,
  bool secret = true,
  List<String> scopes = const <String>['renderBundlesPush'],
}) => _withOrigins((request) async {
  onAuthorization?.call(request.headers['authorization']);
  onUrl?.call(request.url);
  if (request.url.port == 8081) return http.Response('', 204);
  final body = jsonDecode(request.body) as Map<String, dynamic>;
  if (body['method'] == 'listMine') {
    return http.Response(
      jsonEncode(<Object?>[
        <String, Object?>{
          'organizationId': organizationId,
          'slug': 'acme',
          'name': 'Acme',
        },
      ]),
      200,
    );
  }
  if (body['method'] == 'keyTarget') {
    return http.Response(
      jsonEncode(<String, Object?>{
        'organizationId': 7,
        'organizationSlug': 'acme',
        'projectSlug': 'demo',
        'appId': 5,
        'appSlug': 'mobile',
        'target': <String, Object?>{
          'environmentTargetId': 12,
          'namedEnvironmentId': 22,
          'environmentSlug': 'staging',
          'runtimePlane': 'sandbox',
        },
        'secret': secret,
        'scopes': scopes,
      }),
      200,
    );
  }
  onRpcBody?.call(body);
  switch (body['method']) {
    case 'prepare':
      if (prepareKeyMismatch) {
        return http.Response(
          jsonEncode(<String, Object?>{
            'className': 'TargetSelectionRefusedException',
            'data': <String, Object?>{
              'reason': 'keyTargetMismatch',
              'environmentSlug': 'staging',
            },
          }),
          400,
        );
      }
      if (prepareRefusal != null) {
        return http.Response(
          jsonEncode(<String, Object?>{
            'className': 'RenderBundleRejectedException',
            'data': <String, Object?>{'reason': prepareRefusal},
          }),
          403,
        );
      }
      return http.Response(
        jsonEncode(<String, Object?>{
          'uploadToken': 'token-1',
          'headReference': headReference,
          'expiresAt': DateTime.utc(2030).toIso8601String(),
          'blobUploadUrl':
              'http://bundles.restage.localhost:8081/render-bundles/v1/blob',
          'missingContentHashes': missingContentHashes,
          'uploadConcurrency': 3,
          'maxFileTransferBytes': 24 * 1024 * 1024,
        }),
        200,
      );
    case 'commit':
      return http.Response(
        jsonEncode(<String, Object?>{
          'version': <String, Object?>{
            'version': version,
            'contentHash': 'sha256:${'a' * 64}',
          },
          'organizationId': 7,
          'organizationSlug': 'acme',
          'headReference': headReference,
          'reactivated': false,
        }),
        200,
      );
    default:
      fail('unexpected call: ${body['method']}');
  }
});

final class _FakeSource {
  _FakeSource([
    this.source = const BundleSource(
      inRepository: true,
      commit: 'a91f2c3d4e5f60718293a4b5c6d7e8f901234567',
    ),
  ]);

  final BundleSource source;
  Directory? projectRoot;
  bool? recordGit;

  Future<BundleSource> call(
    Directory projectRoot, {
    bool recordGit = false,
  }) async {
    this.projectRoot = projectRoot;
    this.recordGit = recordGit;
    return source;
  }
}

Future<FlutterToolchain> _fakeFlutter({
  required Directory projectRoot,
  String? flagRoot,
  String? configRoot,
}) async => const FlutterToolchain(
  executable: '/sdk/bin/flutter',
  source: 'PATH',
  version: _flutterVersion,
);

/// A Flutter version no build list names ahead of time.
const _flutterVersion = '3.99.0-0.1.pre';

final class _FakeCatalog {
  _FakeCatalog({
    this.json = '{"libraries":{},"widgets":[]}',
    this.registersWidgets = true,
    this.failure,
  });

  final String json;
  final bool registersWidgets;
  final GeneratedCatalogException? failure;
  int calls = 0;
  bool? generate;
  String? flutterExecutable;

  Future<GeneratedWidgetCatalog> call({
    required Directory projectRoot,
    required bool generate,
    String? flutterExecutable,
  }) async {
    calls++;
    this.generate = generate;
    this.flutterExecutable = flutterExecutable;
    final refusal = failure;
    if (refusal != null) throw refusal;
    return GeneratedWidgetCatalog(
      json: json,
      registersWidgets: registersWidgets,
    );
  }
}

final class _FakeBuilder implements RenderBundleArtifactBuilder {
  _FakeBuilder(Uint8List payload)
    : appFiles = <String, Uint8List>{
        'index.html': Uint8List.fromList(utf8.encode('<!doctype html>')),
        renderBundleCapabilityManifestPath: Uint8List.fromList(
          utf8.encode(
            jsonEncode(<String, Object?>{
              'formatVersion': 1,
              'catalog': <String, Object?>{
                'libraries': <String, Object?>{},
                'widgets': <Object?>[],
              },
            }),
          ),
        ),
        'main.dart.wasm': payload,
      };

  /// A build that produced nothing.
  _FakeBuilder.empty() : appFiles = const <String, Uint8List>{};

  final Map<String, Uint8List> appFiles;
  Directory? projectRoot;
  String? catalogJson;
  Uri? parentOrigin;
  String? flutterExecutable;

  /// The container the command encodes from these files.
  late final Uint8List archive = encodeRenderBundleArchive(appFiles);

  @override
  Future<RenderBundleArtifact> build({
    required Directory projectRoot,
    required String catalogJson,
    required Uri parentOrigin,
    required Uri controlOrigin,
    String? flutterExecutable,
  }) async {
    this.projectRoot = projectRoot;
    this.catalogJson = catalogJson;
    this.flutterExecutable = flutterExecutable;
    this.parentOrigin = parentOrigin;
    return RenderBundleArtifact(
      appFiles: appFiles,
      engineSet: RenderBundleEngineSet.fromFiles(
        flutterVersion: _flutterVersion,
        engineRevision: 'af7e796e161ae0bb1ff0758c71a7105418bd9ded',
        files: {
          'skwasm.wasm': [1, 2, 3],
        },
      ),
    );
  }
}

final class _FailingBuilder implements RenderBundleArtifactBuilder {
  _FailingBuilder([
    this.failure = const RenderBundleBuildException('sensitive process output'),
  ]);

  final RenderBundleBuildException failure;

  @override
  Future<RenderBundleArtifact> build({
    required Directory projectRoot,
    required String catalogJson,
    required Uri parentOrigin,
    required Uri controlOrigin,
    String? flutterExecutable,
  }) => throw failure;
}
