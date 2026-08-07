import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/cli.dart';
import 'package:restage_cli/src/credentials/credential.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/render_bundles/flutter_render_bundle_builder.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '../_helpers/test_fixtures.dart';

void main() {
  late Directory root;
  late FileCredentialStore store;
  late StringBuffer stdout;
  late StringBuffer stderr;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('build_push_test_');
    store = FileCredentialStore(p.join(root.path, 'credentials'));
    stdout = StringBuffer();
    stderr = StringBuffer();
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
    final catalog = File(
      p.join(root.path, 'lib', 'src', 'widget_catalog', 'catalog.json'),
    );
    await catalog.create(recursive: true);
    await catalog.writeAsString('{"libraries":{},"widgets":[]}');
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  test('build push registers, uploads main, and prints version/hash', () async {
    final builder = _FakeBuilder(Uint8List.fromList(<int>[1, 2, 3]));
    var rpcCalls = 0;
    var uploadCalls = 0;
    final hash = CapabilitySidecar.hashBlob(builder.archive);
    final client = MockClient((request) async {
      if (request.url.port == 8081) {
        uploadCalls++;
        expect(request.method, 'POST');
        return http.Response('', 204);
      }
      rpcCalls++;
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      switch (body['method']) {
        case 'prepareUpload':
          return http.Response(
            jsonEncode(
              'http://bundles.restage.localhost:8081/render-bundles/v1/upload?projectSlug=demo&organizationId=7&channel=main',
            ),
            200,
          );
        case 'discover':
          return http.Response(
            jsonEncode(<String, Object?>{'version': 4, 'contentHash': hash}),
            200,
          );
        default:
          fail('unexpected RPC: ${body['method']}');
      }
    });

    final exit = await RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
      httpClient: client,
      renderBundleBuilder: builder,
    ).run(<String>['build', 'push', '-C', root.path]);

    expect(exit, 0, reason: stderr.toString());
    expect(rpcCalls, 2);
    expect(uploadCalls, 1);
    expect(builder.projectRoot?.path, root.path);
    expect(
      builder.parentOrigin,
      Uri.parse('http://dashboard.restage.localhost:8082'),
    );
    expect(builder.catalogJson, '{"libraries":{},"widgets":[]}');
    expect(stdout.toString(), contains('version 4'));
    expect(stdout.toString(), contains(hash));
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
      final hash = CapabilitySidecar.hashBlob(builder.archive);
      var uploadCalls = 0;
      final client = MockClient((request) async {
        if (request.url.host == 'bundles.restage.dev') {
          uploadCalls++;
          expect(request.method, 'POST');
          return http.Response('', 204);
        }
        expect(request.url.host, 'api.restage.dev');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        switch (body['method']) {
          case 'prepareUpload':
            return http.Response(
              jsonEncode(
                'https://bundles.restage.dev/render-bundles/v1/upload?projectSlug=demo&organizationId=7&channel=main',
              ),
              200,
            );
          case 'discover':
            return http.Response(
              jsonEncode(<String, Object?>{'version': 1, 'contentHash': hash}),
              200,
            );
          default:
            fail('unexpected RPC: ${body['method']}');
        }
      });

      final exit = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        httpClient: client,
        renderBundleBuilder: builder,
      ).run(<String>['build', 'push', '-C', root.path]);

      expect(exit, 0, reason: stderr.toString());
      expect(builder.parentOrigin, Uri.parse('https://dashboard.restage.dev'));
      expect(uploadCalls, 1);
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
    final builder = _FakeBuilder(Uint8List(0));
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
    'build push propagates one user channel through prepare, upload, and discover',
    () async {
      const channel = 'user/alice';
      final builder = _FakeBuilder(Uint8List.fromList(<int>[4, 5, 6]));
      final rpcBodies = <Map<String, dynamic>>[];
      var uploadCalls = 0;
      final hash = CapabilitySidecar.hashBlob(builder.archive);
      final prepared = Uri.parse('http://bundles.restage.localhost:8081')
          .replace(
            path: '/render-bundles/v1/upload',
            queryParameters: <String, String>{
              'projectSlug': 'demo',
              'organizationId': '7',
              'channel': channel,
            },
          );
      final client = MockClient((request) async {
        if (request.url.port == 8081) {
          uploadCalls++;
          expect(request.method, 'POST');
          expect(request.url, prepared);
          expect(request.url.queryParameters['channel'], channel);
          return http.Response('', 204);
        }
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        rpcBodies.add(body);
        switch (body['method']) {
          case 'prepareUpload':
            return http.Response(jsonEncode(prepared.toString()), 200);
          case 'discover':
            return http.Response(
              jsonEncode(<String, Object?>{'version': 2, 'contentHash': hash}),
              200,
            );
          default:
            fail('unexpected RPC: ${body['method']}');
        }
      });

      final exit = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        httpClient: client,
        renderBundleBuilder: builder,
      ).run(<String>['build', 'push', '-C', root.path, '--channel', channel]);

      expect(exit, 0, reason: stderr.toString());
      expect(uploadCalls, 1);
      expect(rpcBodies.map((body) => body['method']), <String>[
        'prepareUpload',
        'discover',
      ]);
      expect(
        rpcBodies.every(
          (body) => body['projectSlug'] == 'demo' && body['channel'] == channel,
        ),
        isTrue,
      );
      expect(stdout.toString(), contains('$channel version 2'));
      expect(stdout.toString(), contains(hash));
      expect(stderr.toString(), isEmpty);
    },
  );

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
    ).run(<String>['build', 'push', '-C', root.path]);

    expect(exit, 2);
    expect(networkCalls, 0);
    expect(stderr.toString(), contains('Could not build the render bundle.'));
    expect(stderr.toString(), isNot(contains('sensitive process output')));
  });

  test(
    'rejects a concurrently changed channel head without retrying success',
    () async {
      final builder = _FakeBuilder(Uint8List.fromList(<int>[7, 8, 9]));
      final changedHeadHash = CapabilitySidecar.hashBlob(const <int>[9, 8, 7]);
      var uploadCalls = 0;
      var discoverCalls = 0;
      final client = MockClient((request) async {
        if (request.url.port == 8081) {
          uploadCalls++;
          return http.Response('', 204);
        }
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        switch (body['method']) {
          case 'prepareUpload':
            return http.Response(
              jsonEncode(
                'http://bundles.restage.localhost:8081/render-bundles/v1/upload?projectSlug=demo&organizationId=7&channel=main',
              ),
              200,
            );
          case 'discover':
            discoverCalls++;
            return http.Response(
              jsonEncode(<String, Object?>{
                'version': 5,
                'contentHash': changedHeadHash,
              }),
              200,
            );
          default:
            fail('unexpected RPC: ${body['method']}');
        }
      });

      final exit = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        httpClient: client,
        renderBundleBuilder: builder,
      ).run(<String>['build', 'push', '-C', root.path]);

      expect(exit, 2);
      expect(uploadCalls, 1);
      expect(discoverCalls, 1);
      expect(stdout.toString(), isEmpty);
      expect(stderr.toString(), 'Could not upload the render bundle.\n');
      expect(stderr.toString(), isNot(contains(changedHeadHash)));
    },
  );

  test(
    'rejects an invalid channel before credentials, build, or network',
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
          ).run(<String>[
            'build',
            'push',
            '-C',
            root.path,
            '--channel',
            'user/../admin',
          ]);

      expect(exit, 1);
      expect(stderr.toString(), contains('render-bundle channel is invalid'));
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
    'local push rejects a prepared URL on any unpinned sibling port',
    () async {
      await seedRestageConfig(
        root,
        'demo',
        'mobile',
        dashboardOrigin: 'http://dashboard.restage.localhost:8083',
        renderBundleOrigin: 'http://bundles.restage.localhost:8082',
      );
      final builder = _FakeBuilder(Uint8List.fromList(<int>[1]));
      var rpcCalls = 0;
      var uploadCalls = 0;
      final client = MockClient((request) async {
        if (request.url.port == 8081) {
          uploadCalls++;
          return http.Response('', 204);
        }
        rpcCalls++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['method'], 'prepareUpload');
        return http.Response(
          jsonEncode(
            'http://bundles.restage.localhost:8081/render-bundles/v1/upload?projectSlug=demo&organizationId=7&channel=main',
          ),
          200,
        );
      });

      final exit = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        httpClient: client,
        renderBundleBuilder: builder,
      ).run(<String>['build', 'push', '-C', root.path]);

      expect(exit, 2);
      expect(builder.projectRoot?.path, root.path);
      expect(rpcCalls, 1);
      expect(uploadCalls, 0);
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

final class _FakeBuilder implements RenderBundleArtifactBuilder {
  _FakeBuilder(this.archive);

  final Uint8List archive;
  Directory? projectRoot;
  String? catalogJson;
  Uri? parentOrigin;

  @override
  Future<Uint8List> build({
    required Directory projectRoot,
    required String catalogJson,
    required Uri parentOrigin,
  }) async {
    this.projectRoot = projectRoot;
    this.catalogJson = catalogJson;
    this.parentOrigin = parentOrigin;
    return archive;
  }
}

final class _FailingBuilder implements RenderBundleArtifactBuilder {
  @override
  Future<Uint8List> build({
    required Directory projectRoot,
    required String catalogJson,
    required Uri parentOrigin,
  }) => throw const RenderBundleBuildException('sensitive process output');
}
