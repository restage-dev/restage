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
    tempDir = await Directory.systemTemp.createTemp('status_cmd_');
    store = FileCredentialStore(p.join(tempDir.path, 'credentials'));
    stdout = StringBuffer();
    stderr = StringBuffer();
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('prints identity, endpoint, and active config context', () async {
    await seedCredential(store, endpoint: 'https://api.example.com/');
    await File(p.join(tempDir.path, 'restage_config.yaml')).writeAsString('''
project: alpha
app: mobile
defaultEnvironment: staging
organization: default
endpoint: https://api.example.com/
''');

    final exitCode = await RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
      httpClient: _whoamiClient(),
    ).run(['status', '-C', tempDir.path]);

    expect(exitCode, 0);
    final out = stdout.toString();
    expect(out, contains('signed in as dev@example.com'));
    expect(out, contains('endpoint: https://api.example.com/'));
    expect(out, contains('organization: default'));
    expect(out, contains('project: alpha'));
    expect(out, contains('app: mobile'));
    expect(out, contains('environment: staging'));
  });

  test('not signed in exits 1', () async {
    final exitCode = await RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
    ).run(['status', '-C', tempDir.path]);

    expect(exitCode, 1);
    expect(stderr.toString(), contains('restage login'));
  });

  test(
    'fails before HTTP when config endpoint differs from credential',
    () async {
      await seedCredential(store, endpoint: 'https://safe.example.com/');
      await File(p.join(tempDir.path, 'restage_config.yaml')).writeAsString('''
project: alpha
app: mobile
endpoint: https://evil.example.com/
''');

      final exitCode = await RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        httpClient: mockHttpClient((request) {
          fail(
            'HTTP request should not be made before endpoint mismatch fails',
          );
        }),
      ).run(['status', '-C', tempDir.path]);

      expect(exitCode, 1);
      expect(
        stderr.toString(),
        contains('restage login --endpoint https://evil.example.com/'),
      );
      expect(stdout.toString(), isEmpty);
    },
  );

  test('fails before HTTP when config endpoint is malformed', () async {
    await seedCredential(store, endpoint: 'https://safe.example.com/');
    await File(p.join(tempDir.path, 'restage_config.yaml')).writeAsString('''
project: alpha
app: mobile
endpoint: https://[bad
''');

    final exitCode = await RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: store,
      httpClient: mockHttpClient((request) {
        fail('HTTP request should not be made with malformed config endpoint');
      }),
    ).run(['status', '-C', tempDir.path]);

    expect(exitCode, 1);
    expect(
      stderr.toString(),
      contains('Invalid endpoint in restage_config.yaml'),
    );
    expect(stdout.toString(), isEmpty);
  });
}

http.Client _whoamiClient() {
  return mockHttpClient((request) {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    expect(body['method'], 'whoami');
    return http.Response(
      jsonEncode({'id': 42, 'email': 'dev@example.com'}),
      200,
    );
  });
}
