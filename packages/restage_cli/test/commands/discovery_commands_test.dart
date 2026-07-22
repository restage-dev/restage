import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:restage_cli/src/cli.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../_helpers/test_fixtures.dart';

void main() {
  late Directory tempDir;
  late FileCredentialStore store;
  late StringBuffer stdout;
  late StringBuffer stderr;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('discovery_cmd_');
    store = FileCredentialStore(p.join(tempDir.path, 'credentials'));
    stdout = StringBuffer();
    stderr = StringBuffer();
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('restage projects lists project slugs and names', () async {
    await seedCredential(store);

    final exitCode = await RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
      httpClient: _discoveryClient(),
    ).run(['projects', '-C', tempDir.path]);

    expect(exitCode, 0);
    expect(stdout.toString(), contains('alpha\tAlpha'));
    expect(stdout.toString(), contains('beta\tBeta'));
  });

  test(
    'restage apps resolves the project from config and lists apps',
    () async {
      await seedCredential(store);
      await seedRestageConfig(tempDir, 'alpha', 'mobile');

      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        httpClient: _discoveryClient(),
      ).run(['apps', '-C', tempDir.path]);

      expect(exitCode, 0);
      expect(stdout.toString(), contains('mobile\tMobile'));
      expect(stdout.toString(), contains('tablet\tTablet'));
    },
  );

  test(
    'restage envs resolves the project from config and lists env slugs',
    () async {
      await seedCredential(store);
      await seedRestageConfig(tempDir, 'alpha', 'mobile');

      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        httpClient: _discoveryClient(),
      ).run(['envs', '-C', tempDir.path]);

      expect(exitCode, 0);
      expect(stdout.toString(), 'staging\nproduction\n');
    },
  );

  test(
    'restage targets resolves project + app and prints stable target rows',
    () async {
      await seedCredential(store);
      await seedRestageConfig(tempDir, 'alpha', 'mobile');

      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        httpClient: _discoveryClient(),
      ).run(['targets', '--plane', 'sandbox', '-C', tempDir.path]);

      expect(exitCode, 0);
      expect(stdout.toString(), '12\tproduction\tsandbox\n21\tdev\tsandbox\n');
    },
  );

  test(
    'restage envs keeps the owned HTTP client alive through the body',
    () async {
      final server = await _serveDiscoveryBackend();
      addTearDown(() async => server.close(force: true));
      await seedCredential(store, endpoint: 'http://127.0.0.1:${server.port}/');
      await seedRestageConfig(tempDir, 'alpha', 'mobile');

      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
      ).run(['--non-interactive', 'envs', '-C', tempDir.path]);

      expect(exitCode, 0);
      expect(stdout.toString(), contains('staging'));
      expect(stdout.toString(), contains('production'));
    },
  );
}

http.Client _discoveryClient() {
  return mockHttpClient((request) {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    switch (body['method'] as String?) {
      case 'listMine':
        return http.Response(
          jsonEncode([
            {
              'organizationId': 7,
              'slug': 'default',
              'name': 'Default',
              'role': 'owner',
            },
          ]),
          200,
        );
      case 'listProjects':
        expect(body['organizationId'], 7);
        return http.Response(
          jsonEncode([
            {'slug': 'alpha', 'name': 'Alpha'},
            {'slug': 'beta', 'name': 'Beta'},
          ]),
          200,
        );
      case 'listApps':
        expect(body['organizationId'], 7);
        expect(body['projectSlug'], 'alpha');
        return http.Response(
          jsonEncode([
            {'id': 5, 'slug': 'mobile', 'name': 'Mobile'},
            {'id': 6, 'slug': 'tablet', 'name': 'Tablet'},
          ]),
          200,
        );
      case 'listEnvironments':
        expect(body['organizationId'], 7);
        expect(body['projectSlug'], 'alpha');
        return http.Response(
          jsonEncode([
            {'slug': 'staging'},
            {'slug': 'production'},
          ]),
          200,
        );
      case 'listEnvironmentTargets':
        expect(body['organizationId'], 7);
        expect(body['projectSlug'], 'alpha');
        expect(body['appSlug'], 'mobile');
        expect(body['appId'], 5);
        expect(body['runtimePlane'], 'sandbox');
        return http.Response(
          jsonEncode([
            {
              'environmentTargetId': 21,
              'namedEnvironmentId': 3,
              'environmentSlug': 'dev',
              'runtimePlane': 'sandbox',
            },
            {
              'environmentTargetId': 12,
              'namedEnvironmentId': 4,
              'environmentSlug': 'production',
              'runtimePlane': 'sandbox',
            },
          ]),
          200,
        );
      default:
        fail('Unexpected method ${body['method']}');
    }
  }, withDefaultTargetDiscovery: false);
}

Future<HttpServer> _serveDiscoveryBackend() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final raw = await utf8.decoder.bind(request).join();
    final body = jsonDecode(raw) as Map<String, dynamic>;
    final payload = switch (body['method'] as String?) {
      'listMine' => [
        {
          'organizationId': 7,
          'slug': 'default',
          'name': 'Default',
          'role': 'owner',
        },
      ],
      'listProjects' => [
        {'slug': 'alpha', 'name': 'Alpha'},
      ],
      'listEnvironments' => [
        {'slug': 'staging'},
        {'slug': 'production'},
      ],
      _ => {'error': 'unexpected method ${body['method']}'},
    };
    if (payload is Map<String, dynamic> && payload.containsKey('error')) {
      request.response.statusCode = HttpStatus.badRequest;
    } else {
      request.response.statusCode = HttpStatus.ok;
    }
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(payload));
    await request.response.close();
  });
  return server;
}
