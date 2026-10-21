import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage_cli/api.dart';
import 'package:restage_cli/src/cli.dart';
import 'package:test/test.dart';

void main() {
  test('the compiled default endpoint is Restage Cloud', () {
    expect(defaultRestageEndpoint, 'https://api.restage.dev/');
  });

  test(
    'login with no endpoint signs in against Restage Cloud',
    () async {
      final directory = Directory.systemTemp.createTempSync('restage_cli_');
      addTearDown(() => directory.deleteSync(recursive: true));
      final requested = <Uri>[];
      final cli = RestageCli(
        credentialStore: FileCredentialStore(
          '${directory.path}/credentials.json',
        ),
        httpClient: MockClient((request) async {
          requested.add(request.url);
          return http.Response('', 503);
        }),
        sleep: (_) async {},
        openBrowser: (_) async {},
      );

      await cli.run(const ['login']);

      expect(requested, isNotEmpty);
      expect(requested.first.origin, 'https://api.restage.dev');
    },
    skip: Platform.environment['RESTAGE_BACKEND_URL']?.isNotEmpty ?? false
        ? 'RESTAGE_BACKEND_URL overrides the default'
        : false,
  );

  test('an unreachable sign-in server names how to use another', () async {
    final directory = Directory.systemTemp.createTempSync('restage_cli_');
    addTearDown(() => directory.deleteSync(recursive: true));
    final stderr = StringBuffer();
    final code = await RestageCli(
      stdout: StringBuffer(),
      stderr: stderr,
      credentialStore: FileCredentialStore(
        '${directory.path}/credentials.json',
      ),
      httpClient: MockClient(
        (request) async => throw http.ClientException('lookup failed'),
      ),
      sleep: (_) async {},
      openBrowser: (_) async {},
    ).run(const ['login', '--endpoint', 'https://api.example.dev/']);

    expect(code, 2);
    expect(
      stderr.toString(),
      startsWith('Could not reach https://api.example.dev: '),
    );
    expect(
      stderr.toString(),
      endsWith(
        'To sign in to another server, run `restage login --endpoint <url>`, '
        'or set RESTAGE_BACKEND_URL.\n',
      ),
    );
  });

  test('help names how to use another server', () async {
    final stdout = StringBuffer();
    await RestageCli(
      stdout: stdout,
      stderr: StringBuffer(),
    ).run(const ['--help']);
    expect(stdout.toString(), contains('restage login --endpoint <url>'));

    final login = StringBuffer();
    await RestageCli(
      stdout: login,
      stderr: StringBuffer(),
    ).run(const ['login', '--help']);
    expect(login.toString(), contains('RESTAGE_BACKEND_URL'));
  });
}
