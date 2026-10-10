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
      expect(stdout.toString(), 'SLUG\nstaging\nproduction\ndev\n');
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
      expect(
        stdout.toString(),
        'ID\tENVIRONMENT\tPLANE\n12\tproduction\tsandbox\n21\tdev\tsandbox\n',
      );
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

http.Client _discoveryClient() => mockHttpClient((request) {
  final body = jsonDecode(request.body) as Map<String, dynamic>;
  expect(request.url.path, '/scope');
  expect(body['method'], 'read');
  return http.Response(_scopePayload(), 200);
}, withDefaultTargetDiscovery: false);

String _scopePayload() => jsonEncode({
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
    {'id': 1, 'slug': 'alpha', 'name': 'Alpha'},
    {'id': 2, 'slug': 'beta', 'name': 'Beta'},
  ],
  'apps': [
    {'id': 5, 'projectId': 1, 'slug': 'mobile', 'name': 'Mobile'},
    {'id': 6, 'projectId': 1, 'slug': 'tablet', 'name': 'Tablet'},
  ],
  'environments': [
    {'id': 10, 'appId': 5, 'namedEnvironmentId': 2, 'slug': 'staging'},
    {'id': 12, 'appId': 5, 'namedEnvironmentId': 4, 'slug': 'production'},
    {'id': 21, 'appId': 5, 'namedEnvironmentId': 3, 'slug': 'dev'},
  ],
  'environmentTargets': [
    {
      'environmentTargetId': 12,
      'namedEnvironmentId': 4,
      'environmentSlug': 'production',
      'runtimePlane': 'sandbox',
    },
    {
      'environmentTargetId': 21,
      'namedEnvironmentId': 3,
      'environmentSlug': 'dev',
      'runtimePlane': 'sandbox',
    },
  ],
  'surfaces': <Object>[],
});

Future<HttpServer> _serveDiscoveryBackend() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final raw = await utf8.decoder.bind(request).join();
    final body = jsonDecode(raw) as Map<String, dynamic>;
    final payload = body['method'] == 'read'
        ? jsonDecode(_scopePayload())
        : {'error': 'unexpected method ${body['method']}'};
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
