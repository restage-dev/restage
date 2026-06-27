import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage_cli/src/cli.dart';
import 'package:restage_cli/src/credentials/credential.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Scripted backend response.
typedef _ScriptStep =
    http.Response Function(http.Request request, int callIndex);

/// Drive the [http.Client] returned by [MockClient] with a finite
/// sequence of responses, one per call. Asserts the request matches the
/// expected `endpoint` + `method` body fields.
http.Client _scriptedClient(List<_ScriptStep> steps) {
  var index = 0;
  return MockClient((request) async {
    if (index >= steps.length) {
      fail('Unexpected backend call ${index + 1}: ${request.url}');
    }
    final step = steps[index];
    final response = step(request, index);
    index++;
    return response;
  });
}

http.Response _jsonResponse(Object? payload) =>
    http.Response(jsonEncode(payload), 200);

void main() {
  late Directory tempDir;
  late FileCredentialStore store;
  late StringBuffer stdout;
  late StringBuffer stderr;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('restage_cli_e2e_');
    store = FileCredentialStore(p.join(tempDir.path, 'credentials'));
    stdout = StringBuffer();
    stderr = StringBuffer();
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('restage login', () {
    test('happy path: start, single pending poll, success poll → persists '
        'credential and prints the user email', () async {
      final client = _scriptedClient(<_ScriptStep>[
        // 1. startDeviceAuthorization
        (req, _) {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          expect(body['method'], 'startDeviceAuthorization');
          return _jsonResponse(<String, dynamic>{
            '__className__': 'DeviceAuthorizationStart',
            'deviceCode': 'dc-secret',
            'userCode': 'ABCD-EFGH',
            'verificationUri': 'https://dash.example.com/device',
            'expiresInSeconds': 600,
            'pollIntervalSeconds': 5,
          });
        },
        // 2. exchangeDeviceCode → pending
        (req, _) {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          expect(body['method'], 'exchangeDeviceCode');
          expect(body['deviceCode'], 'dc-secret');
          return _jsonResponse(<String, dynamic>{
            '__className__': 'DeviceAuthorizationResult',
            'status': 'pending',
            'pollIntervalSeconds': 5,
          });
        },
        // 3. exchangeDeviceCode → success
        (req, _) => _jsonResponse(<String, dynamic>{
          '__className__': 'DeviceAuthorizationResult',
          'status': 'success',
          'keyId': 42,
          'key': 'secret-key-xyz',
          'userInfo': <String, dynamic>{'id': 7, 'email': 'jane@example.com'},
        }),
      ]);

      final cli = RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        defaultEndpoint: Uri.parse('https://api.example.com/'),
        httpClient: client,
        sleep: (_) async {},
        openBrowser: (_) async {},
      );
      final exit = await cli.run(const ['login']);

      expect(exit, 0, reason: stderr.toString());
      expect(stdout.toString(), contains('ABCD-EFGH'));
      expect(stdout.toString(), contains('https://dash.example.com/device'));
      expect(stdout.toString(), contains('Signed in as jane@example.com'));

      final stored = await store.read();
      expect(stored, isNotNull);
      expect(stored!.endpoint, 'https://api.example.com/');
      expect(stored.kind, CredentialKind.authKey);
      expect(stored.authToken, '42:secret-key-xyz');
    });

    test('expired grant → exit 1 and no credential persisted', () async {
      final client = _scriptedClient(<_ScriptStep>[
        (_, _) => _jsonResponse(<String, dynamic>{
          '__className__': 'DeviceAuthorizationStart',
          'deviceCode': 'dc',
          'userCode': 'XXXX-YYYY',
          'verificationUri': 'https://dash.example.com/device',
          'expiresInSeconds': 600,
          'pollIntervalSeconds': 5,
        }),
        (_, _) => _jsonResponse(<String, dynamic>{
          '__className__': 'DeviceAuthorizationResult',
          'status': 'expired',
        }),
      ]);

      final cli = RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        defaultEndpoint: Uri.parse('https://api.example.com/'),
        httpClient: client,
        sleep: (_) async {},
        openBrowser: (_) async {},
      );
      final exit = await cli.run(const ['login']);
      expect(exit, 1);
      expect(stderr.toString(), contains('expired'));
      expect(await store.read(), isNull);
    });

    test('--no-open suppresses the browser launch', () async {
      var browserOpened = false;
      final client = _scriptedClient(<_ScriptStep>[
        (_, _) => _jsonResponse(<String, dynamic>{
          '__className__': 'DeviceAuthorizationStart',
          'deviceCode': 'dc',
          'userCode': 'XXXX-YYYY',
          'verificationUri': 'https://dash.example.com/device',
          'expiresInSeconds': 600,
          'pollIntervalSeconds': 5,
        }),
        (_, _) => _jsonResponse(<String, dynamic>{
          '__className__': 'DeviceAuthorizationResult',
          'status': 'expired',
        }),
      ]);

      final cli = RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        defaultEndpoint: Uri.parse('https://api.example.com/'),
        httpClient: client,
        sleep: (_) async {},
        openBrowser: (_) async {
          browserOpened = true;
        },
      );
      await cli.run(const ['login', '--no-open']);
      expect(browserOpened, isFalse);
    });

    test('--no-browser also suppresses the launch', () async {
      var browserOpened = false;
      final client = _scriptedClient(<_ScriptStep>[
        (_, _) => _jsonResponse(<String, dynamic>{
          '__className__': 'DeviceAuthorizationStart',
          'deviceCode': 'dc',
          'userCode': 'XXXX-YYYY',
          'verificationUri': 'https://dash.example.com/device',
          'expiresInSeconds': 600,
          'pollIntervalSeconds': 5,
        }),
        (_, _) => _jsonResponse(<String, dynamic>{
          '__className__': 'DeviceAuthorizationResult',
          'status': 'expired',
        }),
      ]);

      final cli = RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        defaultEndpoint: Uri.parse('https://api.example.com/'),
        httpClient: client,
        sleep: (_) async {},
        openBrowser: (_) async {
          browserOpened = true;
        },
      );
      await cli.run(const ['login', '--no-browser']);
      expect(browserOpened, isFalse);
    });

    test('emits a "couldn\'t open browser" fallback when openBrowser '
        'throws', () async {
      final client = _scriptedClient(<_ScriptStep>[
        (_, _) => _jsonResponse(<String, dynamic>{
          '__className__': 'DeviceAuthorizationStart',
          'deviceCode': 'dc',
          'userCode': 'XXXX-YYYY',
          'verificationUri': 'https://dash.example.com/device',
          'expiresInSeconds': 600,
          'pollIntervalSeconds': 5,
        }),
        (_, _) => _jsonResponse(<String, dynamic>{
          '__className__': 'DeviceAuthorizationResult',
          'status': 'expired',
        }),
      ]);

      final cli = RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        defaultEndpoint: Uri.parse('https://api.example.com/'),
        httpClient: client,
        sleep: (_) async {},
        openBrowser: (_) async => throw Exception('no display'),
      );
      await cli.run(const ['login']);
      expect(stdout.toString(), contains("Couldn't open"));
    });

    test('uses a spinner while polling: code + elapsed time appear in '
        'output', () async {
      // Two pending polls then a success, so the spinner has a chance
      // to render an updated message between iterations.
      final client = _scriptedClient(<_ScriptStep>[
        (_, _) => _jsonResponse(<String, dynamic>{
          '__className__': 'DeviceAuthorizationStart',
          'deviceCode': 'dc',
          'userCode': 'ABCD-EFGH',
          'verificationUri': 'https://dash.example.com/device',
          'expiresInSeconds': 600,
          'pollIntervalSeconds': 1,
        }),
        (_, _) => _jsonResponse(<String, dynamic>{
          '__className__': 'DeviceAuthorizationResult',
          'status': 'pending',
        }),
        (_, _) => _jsonResponse(<String, dynamic>{
          '__className__': 'DeviceAuthorizationResult',
          'status': 'success',
          'keyId': 42,
          'key': 'abc',
          'userInfo': {'id': 7, 'email': 'jane@example.com'},
        }),
      ]);

      final cli = RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        defaultEndpoint: Uri.parse('https://api.example.com/'),
        httpClient: client,
        sleep: (_) async {},
        openBrowser: (_) async {},
      );
      final exit = await cli.run(const ['login']);
      expect(exit, 0);
      // The non-interactive spinner prints the message as plain text.
      expect(stdout.toString(), contains('ABCD-EFGH'));
    });
  });

  group('restage logout', () {
    test('with a stored credential: calls server logout and deletes the '
        'local file', () async {
      await store.write(
        const Credential(
          endpoint: 'https://api.example.com/',
          kind: CredentialKind.authKey,
          authToken: '42:abc',
        ),
      );
      var logoutCalled = false;
      final client = _scriptedClient(<_ScriptStep>[
        (req, _) {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          expect(body['method'], 'logout');
          // Authorization header is set from the stored credential —
          // capital `B` required by relic's case-sensitive parsing.
          expect(req.headers['authorization'], 'Basic NDI6YWJj');
          logoutCalled = true;
          return _jsonResponse(null);
        },
      ]);

      final cli = RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        defaultEndpoint: Uri.parse('https://api.example.com/'),
        httpClient: client,
      );
      final exit = await cli.run(const ['logout']);
      expect(exit, 0);
      expect(logoutCalled, isTrue);
      expect(stdout.toString(), contains('Signed out'));
      expect(await store.read(), isNull);
    });

    test('with no stored credential: prints "Not signed in" without '
        'contacting the server', () async {
      final client = _scriptedClient(const <_ScriptStep>[]);
      final cli = RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        defaultEndpoint: Uri.parse('https://api.example.com/'),
        httpClient: client,
      );
      final exit = await cli.run(const ['logout']);
      expect(exit, 0);
      expect(stdout.toString(), contains('Not signed in'));
    });

    test(
      'server-side logout failure still removes the local credential',
      () async {
        await store.write(
          const Credential(
            endpoint: 'https://api.example.com/',
            kind: CredentialKind.authKey,
            authToken: '42:abc',
          ),
        );
        final client = _scriptedClient(<_ScriptStep>[
          (_, _) => http.Response('boom', 500),
        ]);
        final cli = RestageCli(
          stdout: stdout,
          stderr: stderr,
          credentialStore: store,
          defaultEndpoint: Uri.parse('https://api.example.com/'),
          httpClient: client,
        );
        final exit = await cli.run(const ['logout']);
        expect(exit, 0);
        expect(stderr.toString(), contains('Server-side revoke failed'));
        expect(await store.read(), isNull);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Command registration
  // Asserts that `restage surface --help` and `restage paywall --help` list
  // the lifecycle subcommands added in this chapter. These tests do not
  // make any network calls — the help text is produced entirely by the
  // command-runner and redirected to the stdout sink via the print zone.
  // ---------------------------------------------------------------------------

  group('command registration', () {
    test('restage surface --help lists all lifecycle subcommands', () async {
      final cli = RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        defaultEndpoint: Uri.parse('https://api.example.com/'),
      );
      final exit = await cli.run(const ['surface', '--help']);
      expect(exit, 0, reason: stderr.toString());
      final out = stdout.toString();
      expect(out, contains('status'));
      expect(out, contains('kill'));
      expect(out, contains('freeze'));
      expect(out, contains('unfreeze'));
      expect(out, contains('rollback'));
    });

    test('restage paywall --help lists lifecycle subcommands alongside '
        'list and publish', () async {
      final cli = RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        defaultEndpoint: Uri.parse('https://api.example.com/'),
      );
      final exit = await cli.run(const ['paywall', '--help']);
      expect(exit, 0, reason: stderr.toString());
      final out = stdout.toString();
      expect(out, contains('list'));
      expect(out, contains('publish'));
      expect(out, contains('status'));
      expect(out, contains('kill'));
      expect(out, contains('freeze'));
      expect(out, contains('unfreeze'));
      expect(out, contains('rollback'));
    });
  });

  group('restage whoami', () {
    test('with a stored valid credential: prints the email', () async {
      await store.write(
        const Credential(
          endpoint: 'https://api.example.com/',
          kind: CredentialKind.authKey,
          authToken: '42:abc',
        ),
      );
      final client = _scriptedClient(<_ScriptStep>[
        (req, _) {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          expect(body['method'], 'whoami');
          return _jsonResponse(<String, dynamic>{
            '__className__': 'UserInfo',
            'id': 7,
            'email': 'jane@example.com',
          });
        },
      ]);
      final cli = RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        defaultEndpoint: Uri.parse('https://api.example.com/'),
        httpClient: client,
      );
      final exit = await cli.run(const ['whoami']);
      expect(exit, 0);
      expect(stdout.toString().trim(), 'jane@example.com');
    });

    test('with no stored credential: stderr + exit 1', () async {
      final client = _scriptedClient(const <_ScriptStep>[]);
      final cli = RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        defaultEndpoint: Uri.parse('https://api.example.com/'),
        httpClient: client,
      );
      final exit = await cli.run(const ['whoami']);
      expect(exit, 1);
      expect(stderr.toString(), contains('Not signed in'));
    });

    test('server returns null (credential no longer valid): exit 1 with a '
        're-login hint', () async {
      await store.write(
        const Credential(
          endpoint: 'https://api.example.com/',
          kind: CredentialKind.authKey,
          authToken: '42:abc',
        ),
      );
      final client = _scriptedClient(<_ScriptStep>[
        (_, _) => _jsonResponse(null),
      ]);
      final cli = RestageCli(
        stdout: stdout,
        stderr: stderr,
        credentialStore: store,
        defaultEndpoint: Uri.parse('https://api.example.com/'),
        httpClient: client,
      );
      final exit = await cli.run(const ['whoami']);
      expect(exit, 1);
      expect(stderr.toString(), contains('no longer accepted'));
    });
  });
}
