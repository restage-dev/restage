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
    await seedRestageConfig(
      root,
      'demo',
      'mobile',
      dashboardOrigin: 'http://dashboard.restage.localhost:8082',
      renderBundleOrigin: 'http://bundles.restage.localhost:8081',
    );
    // A recorder over a repository that answers without a real Git.
    recorder = (await ReleaseRecorder.open(
      projectRoot: root,
      stderr: StringBuffer(),
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
    ))!;
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
      renderBundleCatalog: catalogStep.call,
      renderBundleSource: sourceStep.call,
    ).run(<String>['build', 'push', '-C', root.path, '--env', 'staging']);
    expect(exit, 0, reason: stderr.toString());
    expect(calls, <String>['prepare', 'commit']);
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

  test(
    'deployed config pins the dashboard parent and bundle authority',
    () async {
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
        dashboardOrigin: 'https://dashboard.restage.dev',
        renderBundleOrigin: 'https://bundles.restage.dev',
      );
      final builder = _FakeBuilder(Uint8List.fromList(<int>[1, 2, 3]));
      final client = MockClient((request) async {
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
                'engineUploadUrl':
                    'https://bundles.restage.dev/render-bundles/v1/engine-file',
                'missingContentHashes': <String>[],
                'missingEnginePaths': <String>[],
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
      });

      final exit = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        httpClient: client,
        renderBundleBuilder: builder,
        renderBundleCatalog: catalogStep.call,
        renderBundleSource: sourceStep.call,
      ).run(<String>['build', 'push', '-C', root.path, '--env', 'staging']);

      expect(exit, 0, reason: stderr.toString());
      expect(builder.parentOrigin, Uri.parse('https://dashboard.restage.dev'));
      expect(stdout.toString(), contains('mobile staging version 1'));
      expect(stderr.toString(), isEmpty);
    },
  );

  test('matching explicit parent and bundle overrides are accepted', () async {
    await seedRestageConfig(
      root,
      'demo',
      'mobile',
      dashboardOrigin: 'http://dashboard.restage.localhost:8082',
    );
    final builder = _FakeBuilder.empty();
    var networkCalls = 0;

    final exit =
        await RestageCli(
          stdout: stdout,
          stderr: stderr,
          credentialStore: store,
          httpClient: MockClient((_) async {
            networkCalls++;
            return http.Response('', 500);
          }),
          renderBundleBuilder: builder,
          renderBundleCatalog: catalogStep.call,
          renderBundleSource: sourceStep.call,
        ).run(<String>[
          'build',
          'push',
          '-C',
          root.path,
          '--parent-origin',
          'http://dashboard.restage.localhost:8082/',
          '--bundle-origin',
          'http://bundles.restage.localhost:8081',
        ]);

    expect(exit, 2);
    expect(
      builder.parentOrigin,
      Uri.parse('http://dashboard.restage.localhost:8082'),
    );
    expect(networkCalls, 0);
  });

  test(
    'explicit parent must match configured dashboard before build or network',
    () async {
      for (final parentOrigin in <String>[
        'http://127.0.0.1:8083',
        'http://127.0.0.1:8082/shell',
        'not-an-origin',
      ]) {
        final builder = _FakeBuilder(Uint8List.fromList(<int>[1]));
        var networkCalls = 0;

        final exit =
            await RestageCli(
              stdout: stdout,
              stderr: stderr,
              credentialStore: store,
              httpClient: MockClient((_) async {
                networkCalls++;
                return http.Response('', 500);
              }),
              renderBundleBuilder: builder,
              renderBundleCatalog: catalogStep.call,
              renderBundleSource: sourceStep.call,
            ).run(<String>[
              'build',
              'push',
              '-C',
              root.path,
              '--parent-origin',
              parentOrigin,
            ]);

        expect(exit, 1, reason: parentOrigin);
        expect(
          stderr.toString(),
          'The parent origin must exactly match the configured '
          'dashboardOrigin.\n',
          reason: parentOrigin,
        );
        expect(builder.projectRoot, isNull, reason: parentOrigin);
        expect(networkCalls, 0, reason: parentOrigin);
        stderr.clear();
      }
    },
  );

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
      final client = MockClient((request) async {
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
            'engineUploadUrl':
                'http://bundles.restage.localhost:8081/render-bundles/v1/'
                'engine-file',
            'missingContentHashes': <String>[
              CapabilitySidecar.hashBlob(builder.appFiles['index.html']!),
            ],
            'missingEnginePaths': <String>[],
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
        renderBundleCatalog: catalogStep.call,
        renderBundleSource: sourceStep.call,
      ).run(<String>['build', 'push', '-C', root.path]);

      expect(exit, 2);
      expect(uploadCalls, 1);
      expect(stdout.toString(), isEmpty);
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
      httpClient: MockClient((_) async {
        networkCalls++;
        return http.Response('', 500);
      }),
      renderBundleBuilder: builder,
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
      httpClient: MockClient((_) async {
        networkCalls++;
        return http.Response('', 500);
      }),
      renderBundleBuilder: _FailingBuilder(),
      renderBundleCatalog: catalogStep.call,
      renderBundleSource: sourceStep.call,
    ).run(<String>['build', 'push', '-C', root.path]);

    expect(exit, 2);
    expect(networkCalls, 0);
    expect(stderr.toString(), contains('Could not build the render bundle.'));
    expect(stderr.toString(), isNot(contains('sensitive process output')));
  });

  test('an engine file the pin does not cover is named', () async {
    final exit = await RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
      httpClient: MockClient((_) async => http.Response('', 500)),
      renderBundleBuilder: _FailingBuilder(
        const RenderBundleBuildException(
          'engine_incomplete',
          detail: 'chromium/canvaskit.wasm',
        ),
      ),
      renderBundleCatalog: catalogStep.call,
      renderBundleSource: sourceStep.call,
    ).run(<String>['build', 'push', '-C', root.path]);

    expect(exit, 2);
    expect(
      stderr.toString(),
      'Could not build the render bundle: the pinned engine set names '
      'chromium/canvaskit.wasm and this build did not produce it. Build on '
      'the version the pin names.\n',
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

  test('a boundary that will not resolve refuses before the catalog', () async {
    var networkCalls = 0;
    final builder = _FakeBuilder(Uint8List.fromList(<int>[1, 2, 3]));
    final exit = await RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
      httpClient: MockClient((_) async {
        networkCalls++;
        return http.Response('', 500);
      }),
      renderBundleBuilder: builder,
      renderBundleCatalog: catalogStep.call,
      renderBundleSource: (_) async =>
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
            httpClient: MockClient((_) async {
              networkCalls++;
              return http.Response('', 500);
            }),
            renderBundleBuilder: builder,
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

  test(
    'deployed push requires the complete config triplet before build',
    () async {
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
        dashboardOrigin: 'https://dashboard.restage.dev',
      );
      final builder = _FakeBuilder(Uint8List.fromList(<int>[1]));
      var networkCalls = 0;

      final exit = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        httpClient: MockClient((_) async {
          networkCalls++;
          return http.Response('', 500);
        }),
        renderBundleBuilder: builder,
        renderBundleCatalog: catalogStep.call,
        renderBundleSource: sourceStep.call,
      ).run(<String>['build', 'push', '-C', root.path]);

      expect(exit, 1);
      expect(
        stderr.toString(),
        'A valid API, dashboard, and render-bundle origin triplet is required. '
        'Configure dashboardOrigin and renderBundleOrigin with three distinct '
        'finite restage.localhost roles or direct HTTPS siblings under '
        'restage.dev.\n',
      );
      expect(builder.projectRoot, isNull);
      expect(networkCalls, 0);
    },
  );

  test(
    'deployed push rejects incomplete or deceptive origin triplets',
    () async {
      for (final unsafe in <(String, String, String, String)>[
        (
          'arbitrary cross-site',
          'https://api.example.com/',
          'https://dashboard.example.com',
          'https://upload.example.com',
        ),
        (
          'public suffix siblings',
          'https://api.github.io/',
          'https://dashboard.github.io',
          'https://upload.github.io',
        ),
        (
          'cross-site dashboard origin',
          'https://api.restage.dev/',
          'https://dashboard.example.com',
          'https://bundles.restage.dev',
        ),
        (
          'cross-site bundle origin',
          'https://api.restage.dev/',
          'https://dashboard.restage.dev',
          'https://upload.example.com',
        ),
        (
          'nested dashboard host',
          'https://api.restage.dev/',
          'https://nested.dashboard.restage.dev',
          'https://bundles.restage.dev',
        ),
        (
          'deceptive suffix',
          'https://api.restage.dev.evil.test/',
          'https://dashboard.restage.dev.evil.test',
          'https://upload.restage.dev.evil.test',
        ),
        (
          'non-origin dashboard URL',
          'https://api.restage.dev/',
          'https://dashboard.restage.dev/shell',
          'https://bundles.restage.dev',
        ),
      ]) {
        await store.write(
          Credential(
            endpoint: unsafe.$2,
            kind: CredentialKind.authKey,
            authToken: 'key:private',
          ),
        );
        await seedRestageConfig(
          root,
          'demo',
          'mobile',
          dashboardOrigin: unsafe.$3,
          renderBundleOrigin: unsafe.$4,
        );
        final builder = _FakeBuilder(Uint8List.fromList(<int>[1]));
        var networkCalls = 0;

        final exit = await RestageCli(
          stdout: stdout,
          stderr: stderr,
          credentialStore: store,
          httpClient: MockClient((_) async {
            networkCalls++;
            return http.Response('', 500);
          }),
          renderBundleBuilder: builder,
          renderBundleCatalog: catalogStep.call,
          renderBundleSource: sourceStep.call,
        ).run(<String>['build', 'push', '-C', root.path]);

        expect(exit, 1, reason: unsafe.$1);
        expect(builder.projectRoot, isNull, reason: unsafe.$1);
        expect(networkCalls, 0, reason: unsafe.$1);
        stderr.clear();
      }
    },
  );

  test(
    'local push requires the complete config triplet before build or network',
    () async {
      await seedRestageConfig(root, 'demo', 'mobile');
      final builder = _FakeBuilder(Uint8List.fromList(<int>[1]));
      var networkCalls = 0;

      final exit = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        httpClient: MockClient((_) async {
          networkCalls++;
          return http.Response('', 500);
        }),
        renderBundleBuilder: builder,
        renderBundleCatalog: catalogStep.call,
        renderBundleSource: sourceStep.call,
      ).run(<String>['build', 'push', '-C', root.path]);

      expect(exit, 1);
      expect(
        stderr.toString(),
        'A valid API, dashboard, and render-bundle origin triplet is required. '
        'Configure dashboardOrigin and renderBundleOrigin with three distinct '
        'finite restage.localhost roles or direct HTTPS siblings under '
        'restage.dev.\n',
      );
      expect(builder.projectRoot, isNull);
      expect(networkCalls, 0);
    },
  );

  test(
    'deployed push rejects an origin collision before build or network',
    () async {
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
        dashboardOrigin: 'https://api.restage.dev',
        renderBundleOrigin: 'https://bundles.restage.dev',
      );
      final builder = _FakeBuilder(Uint8List.fromList(<int>[1]));
      var networkCalls = 0;

      final exit = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        httpClient: MockClient((_) async {
          networkCalls++;
          return http.Response('', 500);
        }),
        renderBundleBuilder: builder,
        renderBundleCatalog: catalogStep.call,
        renderBundleSource: sourceStep.call,
      ).run(<String>['build', 'push', '-C', root.path]);

      expect(exit, 1);
      expect(
        stderr.toString(),
        'A valid API, dashboard, and render-bundle origin triplet is required. '
        'Configure dashboardOrigin and renderBundleOrigin with three distinct '
        'finite restage.localhost roles or direct HTTPS siblings under '
        'restage.dev.\n',
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
      httpClient: MockClient((request) async {
        networkCalls++;
        return http.Response('', 500);
      }),
      renderBundleBuilder: builder,
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
      httpClient: MockClient((request) async => http.Response('', 500)),
      renderBundleBuilder: builder,
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
      dashboardOrigin: 'http://dashboard.restage.localhost:8082',
      renderBundleOrigin: 'http://bundles.restage.localhost:8081',
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
      renderBundleCatalog: catalogStep.call,
      renderBundleSource: sourceStep.call,
      environment: const <String, String>{'RESTAGE_API_KEY': 'rs_sk_example'},
    ).run(<String>['build', 'push', '-C', root.path]);
    expect(exit, 0, reason: stderr.toString());
    expect(authorizations, isNotEmpty);
    expect(authorizations, everyElement('Bearer rs_sk_example'));
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
      dashboardOrigin: 'http://dashboard.restage.localhost:8082',
      renderBundleOrigin: 'http://bundles.restage.localhost:8081',
    );
    final builder = _FakeBuilder(Uint8List.fromList(<int>[1, 2, 3]));
    final exit = await RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
      httpClient: _pushClient(builder.archive),
      renderBundleBuilder: builder,
      renderBundleCatalog: catalogStep.call,
      renderBundleSource: sourceStep.call,
      environment: const <String, String>{'RESTAGE_API_KEY': 'rs_sk_example'},
    ).run(<String>['build', 'push', '-C', root.path]);
    expect(exit, 0, reason: stderr.toString());
    expect(await store.read(), isNotNull);
    expect((await store.read())!.kind, CredentialKind.authKey);
    expect(
      await File(p.join(root.path, 'credentials')).readAsString(),
      isNot(contains('rs_sk_example')),
    );
    expect(stdout.toString(), isNot(contains('rs_sk_example')));
    expect(stderr.toString(), isNot(contains('rs_sk_example')));
  });

  test('a refused key names the scope a push needs', () async {
    await seedRestageConfig(
      root,
      'demo',
      'mobile',
      endpoint: 'http://api.restage.localhost:8080',
      dashboardOrigin: 'http://dashboard.restage.localhost:8082',
      renderBundleOrigin: 'http://bundles.restage.localhost:8081',
    );
    final builder = _FakeBuilder(Uint8List.fromList(<int>[1, 2, 3]));
    final exit = await RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
      httpClient: MockClient(
        (request) async => http.Response('forbidden: no scope', 403),
      ),
      renderBundleBuilder: builder,
      renderBundleCatalog: catalogStep.call,
      renderBundleSource: sourceStep.call,
      environment: const <String, String>{'RESTAGE_API_KEY': 'rs_sk_example'},
    ).run(<String>['build', 'push', '-C', root.path]);
    expect(exit, 2);
    expect(
      stderr.toString(),
      'Could not upload the render bundle: the key was not accepted. A key '
      'pushes only while it holds the bundle-push scope and has not been '
      'revoked.\n',
    );
    expect(stderr.toString(), isNot(contains('rs_sk_example')));
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
    final exit =
        await RestageCli(
          stdout: stdout,
          stderr: stderr,
          credentialStore: store,
        ).run(<String>[
          'build',
          'push',
          '-C',
          root.path,
          '--api-key',
          'rs_sk_example',
        ]);
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
      'Not signed in. Run `restage login`, or set RESTAGE_API_KEY to push '
      'with a key.\n',
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
          httpClient: MockClient((_) async {
            networkCalls++;
            return http.Response('', 500);
          }),
          renderBundleBuilder: builder,
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
      renderBundleCatalog: catalogStep.call,
      renderBundleSource: sourceStep.call,
      environment: const <String, String>{'RESTAGE_API_KEY': 'rs_sk_example'},
    ).run(<String>['build', 'push', '-C', root.path, '--personal']);
    expect(exit, 1);
    expect(
      stderr.toString(),
      contains('A key moves the head of the environment it is bound to'),
    );
    expect(builder.projectRoot, isNull);
  });

  test('--record-git writes the receipt the push earned', () async {
    await seedRestageConfig(
      root,
      'demo',
      'mobile',
      organization: 'acme',
      dashboardOrigin: 'http://dashboard.restage.localhost:8082',
      renderBundleOrigin: 'http://bundles.restage.localhost:8081',
    );
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
          renderBundleCatalog: catalogStep.call,
          renderBundleSource: sourceStep.call,
          renderBundleRecorderOpener:
              ({required projectRoot, required stderr}) async => recorder,
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
    expect(recorded, isNotNull);
    expect(recorded!['organizationId'], 7);
    expect(recorded!['organization'], 'acme');
    expect(recorded!['app'], 'mobile');
    expect(recorded!['head'], 'staging');
    expect(recorded!['environment'], 'staging');
    expect(recorded!['version'], 6);
    expect(recorded!['dirty'], isFalse);
    expect(recorded!['toolchain'], requiredRenderBundleFlutterVersion);
  });

  test('a push to a personal head records no environment', () async {
    await seedRestageConfig(
      root,
      'demo',
      'mobile',
      organization: 'acme',
      dashboardOrigin: 'http://dashboard.restage.localhost:8082',
      renderBundleOrigin: 'http://bundles.restage.localhost:8081',
    );
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
          renderBundleCatalog: catalogStep.call,
          renderBundleSource: sourceStep.call,
          renderBundleRecorderOpener:
              ({required projectRoot, required stderr}) async => recorder,
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
      httpClient: MockClient((_) async {
        networkCalls++;
        return http.Response('', 500);
      }),
      renderBundleBuilder: builder,
      renderBundleCatalog: catalogStep.call,
      renderBundleSource: sourceStep.call,
      renderBundleRecorderOpener:
          ({required projectRoot, required stderr}) async {
            stderr.writeln('This app is not in a Git repository.');
            return null;
          },
    ).run(<String>['build', 'push', '-C', root.path, '--record-git']);

    expect(exit, 1);
    expect(stderr.toString(), 'This app is not in a Git repository.\n');
    expect(builder.projectRoot, isNull);
    expect(catalogStep.calls, 0);
    expect(networkCalls, 0);
  });

  test('a receipt that will not write leaves the push standing', () async {
    await seedRestageConfig(
      root,
      'demo',
      'mobile',
      organization: 'acme',
      dashboardOrigin: 'http://dashboard.restage.localhost:8082',
      renderBundleOrigin: 'http://bundles.restage.localhost:8081',
    );
    final builder = _FakeBuilder(Uint8List.fromList(<int>[1, 2, 3]));
    final exit =
        await RestageCli(
          stdout: stdout,
          stderr: stderr,
          credentialStore: store,
          httpClient: _pushClient(builder.archive, organizationId: 7),
          renderBundleBuilder: builder,
          renderBundleCatalog: catalogStep.call,
          renderBundleSource: sourceStep.call,
          renderBundleRecorderOpener:
              ({required projectRoot, required stderr}) async => recorder,
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
          renderBundleCatalog: catalogStep.call,
          renderBundleSource: sourceStep.call,
          renderBundleRecorderOpener:
              ({required projectRoot, required stderr}) async => recorder,
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
            renderBundleCatalog: catalogStep.call,
            renderBundleSource: sourceStep.call,
            renderBundleRecorderOpener:
                ({required projectRoot, required stderr}) async => recorder,
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
      dashboardOrigin: 'http://dashboard.restage.localhost:8082',
      renderBundleOrigin: 'http://bundles.restage.localhost:8081',
    );
    final builder = _FakeBuilder(Uint8List.fromList(<int>[1, 2, 3]));
    Map<String, Object?>? recorded;
    final exit = await RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
      httpClient: _pushClient(builder.archive),
      renderBundleBuilder: builder,
      renderBundleCatalog: catalogStep.call,
      renderBundleSource: sourceStep.call,
      renderBundleRecorderOpener:
          ({required projectRoot, required stderr}) async => recorder,
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
      environment: const <String, String>{'RESTAGE_API_KEY': 'rs_sk_example'},
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

/// Answers the calls one successful push makes.
http.Client _pushClient(
  Uint8List archive, {
  void Function(String?)? onAuthorization,
  void Function(Map<String, dynamic>)? onRpcBody,
  int version = 4,
  String headReference = 'staging',
  List<String> missingContentHashes = const <String>[],
  int? organizationId,
  String? prepareRefusal,
}) => MockClient((request) async {
  onAuthorization?.call(request.headers['authorization']);
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
  onRpcBody?.call(body);
  switch (body['method']) {
    case 'prepare':
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
          'engineUploadUrl':
              'http://bundles.restage.localhost:8081/render-bundles/v1/'
              'engine-file',
          'missingContentHashes': missingContentHashes,
          'missingEnginePaths': <String>[],
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

  Future<BundleSource> call(Directory projectRoot) async {
    this.projectRoot = projectRoot;
    return source;
  }
}

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

  Future<GeneratedWidgetCatalog> call({
    required Directory projectRoot,
    required bool generate,
  }) async {
    calls++;
    this.generate = generate;
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

  /// The container the command encodes from these files.
  late final Uint8List archive = encodeRenderBundleArchive(appFiles);

  @override
  Future<RenderBundleArtifact> build({
    required Directory projectRoot,
    required String catalogJson,
    required Uri parentOrigin,
    required Uri controlOrigin,
  }) async {
    this.projectRoot = projectRoot;
    this.catalogJson = catalogJson;
    this.parentOrigin = parentOrigin;
    return RenderBundleArtifact(
      appFiles: appFiles,
      engineFiles: const <String, Uint8List>{},
      engineSetId: 'a' * 64,
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
  }) => throw failure;
}
