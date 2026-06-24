import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage_cli/api.dart';
import 'package:test/test.dart';

import '_support/harness.dart';

/// Sentinels: if any of these reaches a tool result, the no-leak invariant is
/// broken. `deviceCode` is the pre-auth grant secret; `key`/`authToken` are the
/// session secret.
const _deviceSecret = 'DEVICE_SECRET';
const _keySecret = 'KEY_SECRET';
const _authToken = '99:$_keySecret';

const _startResponse = {
  'deviceCode': _deviceSecret,
  'userCode': 'WXYZ-1234',
  'verificationUri': 'https://verify.test/device',
  'expiresInSeconds': 300,
  'pollIntervalSeconds': 10,
};

const _pending = {'status': 'pending', 'pollIntervalSeconds': 10};
const _success = {
  'status': 'success',
  'keyId': 99,
  'key': _keySecret,
  'userInfo': {'id': 1, 'email': 'dev@acme.test'},
};
const _expired = {'status': 'expired'};

String _text(CallToolResult r) => (r.content.single as TextContent).text;

void _assertNoSecrets(CallToolResult r) {
  final blob = '${_text(r)} ${jsonEncode(r.structuredContent)}';
  expect(blob, isNot(contains(_deviceSecret)));
  expect(blob, isNot(contains(_keySecret)));
  expect(blob, isNot(contains(_authToken)));
}

void main() {
  late Directory tempDir;
  late FileCredentialStore store;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('restage_mcp_auth_test');
    store = FileCredentialStore('${tempDir.path}/credentials');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> writeCredential() => store.write(
    const Credential(
      endpoint: 'https://api.test/',
      kind: CredentialKind.authKey,
      authToken: _authToken,
    ),
  );

  /// A fake `auth` backend. [exchanges] are returned in order for successive
  /// `exchangeDeviceCode` polls (the last repeats); [whoamiUser] is the
  /// `whoami` body (null body when absent). Records every request body in
  /// [calls] and every opened URL in [opened].
  ({MockClient client, List<Map<String, dynamic>> calls, List<String> opened})
  fakeBackend({
    List<Map<String, dynamic>> exchanges = const [],
    Map<String, dynamic>? whoamiUser,
  }) {
    final calls = <Map<String, dynamic>>[];
    final opened = <String>[];
    var i = 0;
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      calls.add(body);
      switch (body['method']) {
        case 'startDeviceAuthorization':
          return http.Response(jsonEncode(_startResponse), 200);
        case 'exchangeDeviceCode':
          final resp =
              exchanges[i < exchanges.length ? i : exchanges.length - 1];
          i++;
          return http.Response(jsonEncode(resp), 200);
        case 'whoami':
          return http.Response(
            whoamiUser == null ? 'null' : jsonEncode(whoamiUser),
            200,
          );
        case 'logout':
          return http.Response('null', 200);
        default:
          return http.Response('null', 200);
      }
    });
    return (client: client, calls: calls, opened: opened);
  }

  /// A clock that advances by whatever [sleep] is asked to wait.
  ({DateTime Function() now, Future<void> Function(Duration) sleep})
  fakeClock() {
    var clock = DateTime.utc(2026, 1, 1, 12);
    return (now: () => clock, sleep: (d) async => clock = clock.add(d));
  }

  group('restage_login', () {
    test(
      'call 1 starts the flow, returns the URL + code, and opens the browser '
      '(never the deviceCode)',
      () async {
        final backend = fakeBackend();
        final clock = fakeClock();
        final connection = await connectServer(
          store: store,
          httpClient: backend.client,
          loginEndpoint: Uri.parse('https://api.test/'),
          sleep: clock.sleep,
          now: clock.now,
          openBrowser: (url) async => backend.opened.add(url),
        );

        final result = await connection.callTool(
          CallToolRequest(name: 'restage_login', arguments: {}),
        );

        expect(result.isError, isNot(true));
        expect(result.structuredContent!['status'], 'authorization_pending');
        expect(result.structuredContent!['userCode'], 'WXYZ-1234');
        final text = _text(result);
        expect(text, contains('https://verify.test/device'));
        expect(text, contains('WXYZ-1234'));
        expect(
          text.toLowerCase(),
          contains('again'),
        ); // "call restage_login again"
        expect(backend.opened, ['https://verify.test/device']);
        _assertNoSecrets(result);
        // Only the start call hit the backend; no polling yet.
        expect(backend.calls.map((c) => c['method']), [
          'startDeviceAuthorization',
        ]);
      },
    );

    test(
      'call 1 then call 2 completes sign-in and persists the credential',
      () async {
        final backend = fakeBackend(exchanges: [_pending, _success]);
        final clock = fakeClock();
        final connection = await connectServer(
          store: store,
          httpClient: backend.client,
          loginEndpoint: Uri.parse('https://api.test/'),
          sleep: clock.sleep,
          now: clock.now,
          openBrowser: (_) async {},
        );

        final r1 = await connection.callTool(
          CallToolRequest(name: 'restage_login', arguments: {}),
        );
        _assertNoSecrets(r1);

        final r2 = await connection.callTool(
          CallToolRequest(name: 'restage_login', arguments: {}),
        );
        expect(r2.isError, isNot(true));
        expect(r2.structuredContent!['status'], 'signed_in');
        expect(_text(r2), contains('dev@acme.test'));
        _assertNoSecrets(r2);

        // The credential is persisted to the shared store (the test may read the
        // secret; the point is the TOOL never surfaced it).
        final persisted = await store.read();
        expect(persisted!.authToken, _authToken);
        expect(persisted.endpoint, 'https://api.test/');
      },
    );

    test(
      'call 2 with no prior attempt starts a fresh flow (idempotent)',
      () async {
        final backend = fakeBackend();
        final clock = fakeClock();
        final connection = await connectServer(
          store: store,
          httpClient: backend.client,
          loginEndpoint: Uri.parse('https://api.test/'),
          sleep: clock.sleep,
          now: clock.now,
          openBrowser: (_) async {},
        );

        final result = await connection.callTool(
          CallToolRequest(name: 'restage_login', arguments: {}),
        );

        expect(result.structuredContent!['status'], 'authorization_pending');
        // No stash existed, so it started rather than polling.
        expect(backend.calls.map((c) => c['method']), [
          'startDeviceAuthorization',
        ]);
      },
    );

    test(
      'already signed in short-circuits with restage_logout guidance',
      () async {
        await writeCredential();
        final backend = fakeBackend(
          whoamiUser: {'id': 1, 'email': 'dev@acme.test'},
        );
        final connection = await connectServer(
          store: store,
          httpClient: backend.client,
          loginEndpoint: Uri.parse('https://api.test/'),
          openBrowser: (_) async {},
        );

        final result = await connection.callTool(
          CallToolRequest(name: 'restage_login', arguments: {}),
        );

        expect(result.isError, isNot(true));
        expect(result.structuredContent!['status'], 'already_signed_in');
        expect(_text(result), contains('dev@acme.test'));
        expect(_text(result).toLowerCase(), contains('restage_logout'));
        // No device authorization was started.
        expect(
          backend.calls.map((c) => c['method']),
          isNot(contains('startDeviceAuthorization')),
        );
      },
    );

    test(
      'an expired grant clears the attempt and asks to start again',
      () async {
        final backend = fakeBackend(exchanges: [_expired]);
        final clock = fakeClock();
        final connection = await connectServer(
          store: store,
          httpClient: backend.client,
          loginEndpoint: Uri.parse('https://api.test/'),
          sleep: clock.sleep,
          now: clock.now,
          openBrowser: (_) async {},
        );

        await connection.callTool(
          CallToolRequest(name: 'restage_login', arguments: {}),
        ); // start
        final r2 = await connection.callTool(
          CallToolRequest(name: 'restage_login', arguments: {}),
        ); // poll -> expired
        expect(r2.structuredContent!['status'], 'expired');
        expect(_text(r2).toLowerCase(), contains('again'));

        // The stash was cleared: a third call starts a fresh authorization.
        final r3 = await connection.callTool(
          CallToolRequest(name: 'restage_login', arguments: {}),
        );
        expect(r3.structuredContent!['status'], 'authorization_pending');
      },
    );

    test(
      'a per-call budget timeout keeps the attempt and resumes on re-call',
      () async {
        // Always pending until the 4th poll, which succeeds. The bounded per-call
        // poll budget is exhausted first, so call 2 returns "still waiting" while
        // keeping the stash; call 3 resumes the SAME grant and completes.
        final backend = fakeBackend(
          exchanges: [_pending, _pending, _pending, _success],
        );
        final clock = fakeClock();
        final connection = await connectServer(
          store: store,
          httpClient: backend.client,
          loginEndpoint: Uri.parse('https://api.test/'),
          sleep: clock.sleep,
          now: clock.now,
          openBrowser: (_) async {},
        );

        await connection.callTool(
          CallToolRequest(name: 'restage_login', arguments: {}),
        ); // start
        final r2 = await connection.callTool(
          CallToolRequest(name: 'restage_login', arguments: {}),
        ); // polls until the budget is hit
        expect(r2.structuredContent!['status'], 'authorization_pending');
        expect(_text(r2).toLowerCase(), contains('again'));
        _assertNoSecrets(r2);

        final r3 = await connection.callTool(
          CallToolRequest(name: 'restage_login', arguments: {}),
        ); // resumes the same grant -> success
        expect(r3.structuredContent!['status'], 'signed_in');
        _assertNoSecrets(r3);
        expect((await store.read())!.authToken, _authToken);
      },
    );

    test(
      'a zero poll interval from the backend cannot hang the poll loop',
      () async {
        // A hostile/buggy backend returns pending with pollIntervalSeconds: 0.
        // Without a floor, interval is Duration.zero, the injected clock never
        // advances on sleep, and the per-call budget is never crossed — an
        // infinite loop. The interval floor guarantees forward progress.
        const zeroStart = {
          'deviceCode': _deviceSecret,
          'userCode': 'WXYZ-1234',
          'verificationUri': 'https://verify.test/device',
          'expiresInSeconds': 300,
          'pollIntervalSeconds': 0,
        };
        const zeroPending = {'status': 'pending', 'pollIntervalSeconds': 0};
        var polls = 0;
        final client = MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          switch (body['method']) {
            case 'startDeviceAuthorization':
              return http.Response(jsonEncode(zeroStart), 200);
            case 'exchangeDeviceCode':
              polls++;
              return http.Response(jsonEncode(zeroPending), 200);
            default:
              return http.Response('null', 200);
          }
        });
        final clock = fakeClock();
        final connection = await connectServer(
          store: store,
          httpClient: client,
          loginEndpoint: Uri.parse('https://api.test/'),
          sleep: clock.sleep,
          now: clock.now,
          openBrowser: (_) async {},
        );

        await connection.callTool(
          CallToolRequest(name: 'restage_login', arguments: {}),
        ); // start
        final r2 = await connection.callTool(
          CallToolRequest(name: 'restage_login', arguments: {}),
        ); // poll: must terminate at the budget, not hang
        expect(r2.structuredContent!['status'], 'authorization_pending');
        // Bounded polling: budget / floored interval, not unbounded.
        expect(polls, lessThan(100));
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );
  });

  group('restage_whoami', () {
    test('reports the signed-in account', () async {
      await writeCredential();
      final backend = fakeBackend(
        whoamiUser: {'id': 1, 'email': 'dev@acme.test'},
      );
      final connection = await connectServer(
        store: store,
        httpClient: backend.client,
      );

      final result = await connection.callTool(
        CallToolRequest(name: 'restage_whoami', arguments: {}),
      );

      expect(result.isError, isNot(true));
      expect(result.structuredContent!['signedIn'], true);
      expect(result.structuredContent!['email'], 'dev@acme.test');
    });

    test('reports signed-out when there is no credential', () async {
      final connection = await connectServer(
        store: store,
        httpClient: MockClient((_) async {
          fail('the backend must not be contacted when not signed in');
        }),
      );

      final result = await connection.callTool(
        CallToolRequest(name: 'restage_whoami', arguments: {}),
      );

      expect(result.isError, isNot(true));
      expect(result.structuredContent!['signedIn'], false);
    });
  });

  group('restage_logout', () {
    test('revokes the session and removes the local credential', () async {
      await writeCredential();
      final backend = fakeBackend();
      final connection = await connectServer(
        store: store,
        httpClient: backend.client,
      );

      final result = await connection.callTool(
        CallToolRequest(name: 'restage_logout', arguments: {}),
      );

      expect(result.isError, isNot(true));
      expect(result.structuredContent!['signedOut'], true);
      expect(backend.calls.map((c) => c['method']), contains('logout'));
      expect(await store.read(), isNull); // local credential removed
    });

    test('is a no-op when not signed in', () async {
      final connection = await connectServer(
        store: store,
        httpClient: MockClient((_) async {
          fail('the backend must not be contacted when not signed in');
        }),
      );

      final result = await connection.callTool(
        CallToolRequest(name: 'restage_logout', arguments: {}),
      );

      expect(result.isError, isNot(true));
      expect(result.structuredContent!['signedOut'], true);
    });
  });
}
