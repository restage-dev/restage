import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage_cli/api.dart';
import 'package:test/test.dart';

import '_support/harness.dart';

/// Security: `restage_login` hands the backend's verification URL to the OS
/// browser opener and surfaces the (public) userCode. It must fail closed if a
/// buggy/hostile backend returns an unsupported-scheme URL (so it can't drive
/// `open`/`xdg-open` to a file:// or custom-scheme target) or aliases its own
/// (secret) deviceCode into a public field.
void main() {
  late Directory tempDir;
  late FileCredentialStore store;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('restage_mcp_login_guard');
    store = FileCredentialStore('${tempDir.path}/credentials');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  ({MockClient client, List<String> opened}) startWith(
    Map<String, dynamic> startResponse,
    List<String> opened,
  ) {
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (body['method'] == 'startDeviceAuthorization') {
        return http.Response(jsonEncode(startResponse), 200);
      }
      return http.Response('null', 200);
    });
    return (client: client, opened: opened);
  }

  test('a non-http(s) verification URL is refused and never opened', () async {
    final opened = <String>[];
    final backend = startWith({
      'deviceCode': 'DEVICE_SECRET',
      'userCode': 'WXYZ-1234',
      'verificationUri': 'file:///etc/passwd',
      'expiresInSeconds': 300,
      'pollIntervalSeconds': 10,
    }, opened);
    final connection = await connectServer(
      store: store,
      httpClient: backend.client,
      loginEndpoint: Uri.parse('https://api.test/'),
      openBrowser: (url) async => opened.add(url),
    );

    final result = await connection.callTool(
      CallToolRequest(name: 'restage_login', arguments: {}),
    );

    expect(result.isError, isTrue);
    // The dangerous URL was NEVER handed to the OS opener.
    expect(opened, isEmpty);
    final text = (result.content.single as TextContent).text;
    expect(text, isNot(contains('file:///etc/passwd')));
  });

  test(
    'a deviceCode aliased into a public field is refused (no leak)',
    () async {
      final opened = <String>[];
      final backend = startWith({
        'deviceCode': 'DEVICE_SECRET',
        'userCode':
            'CODE-DEVICE_SECRET', // the secret grant aliased into userCode
        'verificationUri': 'https://verify.test/device',
        'expiresInSeconds': 300,
        'pollIntervalSeconds': 10,
      }, opened);
      final connection = await connectServer(
        store: store,
        httpClient: backend.client,
        loginEndpoint: Uri.parse('https://api.test/'),
        openBrowser: (url) async => opened.add(url),
      );

      final result = await connection.callTool(
        CallToolRequest(name: 'restage_login', arguments: {}),
      );

      expect(result.isError, isTrue);
      final blob =
          '${(result.content.single as TextContent).text} '
          '${jsonEncode(result.structuredContent)}';
      expect(blob, isNot(contains('DEVICE_SECRET')));
    },
  );

  test('a normal https verification URL still works', () async {
    final opened = <String>[];
    final backend = startWith({
      'deviceCode': 'DEVICE_SECRET',
      'userCode': 'WXYZ-1234',
      'verificationUri': 'https://verify.test/device',
      'expiresInSeconds': 300,
      'pollIntervalSeconds': 10,
    }, opened);
    final connection = await connectServer(
      store: store,
      httpClient: backend.client,
      loginEndpoint: Uri.parse('https://api.test/'),
      openBrowser: (url) async => opened.add(url),
    );

    final result = await connection.callTool(
      CallToolRequest(name: 'restage_login', arguments: {}),
    );

    expect(result.isError, isNot(true));
    expect(result.structuredContent!['status'], 'authorization_pending');
    expect(opened, ['https://verify.test/device']);
  });

  test('a success email that aliases the device grant is not surfaced', () async {
    // The backend's success response sets userInfo.email to the deviceCode (a
    // secret it generated). Sign-in still completes, but the aliased value must
    // not be surfaced as the email.
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      switch (body['method']) {
        case 'startDeviceAuthorization':
          return http.Response(
            jsonEncode({
              'deviceCode': 'DEVICE_SECRET',
              'userCode': 'WXYZ-1234',
              'verificationUri': 'https://verify.test/device',
              'expiresInSeconds': 300,
              'pollIntervalSeconds': 10,
            }),
            200,
          );
        case 'exchangeDeviceCode':
          return http.Response(
            jsonEncode({
              'status': 'success',
              'keyId': 99,
              'key': 'KEY_SECRET',
              'userInfo': {'id': 1, 'email': 'DEVICE_SECRET'},
            }),
            200,
          );
        default:
          return http.Response('null', 200);
      }
    });
    var clock = DateTime.utc(2026, 1, 1, 12);
    final connection = await connectServer(
      store: store,
      httpClient: client,
      loginEndpoint: Uri.parse('https://api.test/'),
      now: () => clock,
      sleep: (d) async => clock = clock.add(d),
      openBrowser: (_) async {},
    );

    await connection.callTool(
      CallToolRequest(name: 'restage_login', arguments: {}),
    ); // start
    final r2 = await connection.callTool(
      CallToolRequest(name: 'restage_login', arguments: {}),
    ); // poll -> success

    expect(r2.structuredContent!['status'], 'signed_in');
    final blob =
        '${(r2.content.single as TextContent).text} '
        '${jsonEncode(r2.structuredContent)}';
    expect(blob, isNot(contains('DEVICE_SECRET')));
    expect(blob, isNot(contains('KEY_SECRET')));
  });
}
