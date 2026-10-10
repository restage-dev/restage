import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage_cli/api.dart';
import 'package:test/test.dart';

import '_support/harness.dart';

void main() {
  late Directory tempDir;
  late FileCredentialStore store;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('restage_mcp_platforms_test');
    store = FileCredentialStore('${tempDir.path}/credentials');
    await store.write(
      const Credential(
        endpoint: 'https://api.test/',
        kind: CredentialKind.authKey,
        authToken: 'keyId:SUPERSECRET',
      ),
    );
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('read_platforms makes the one read and states every cell', () async {
    final calls = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      calls.add(body);
      return http.Response(
        jsonEncode({
          'appId': 5,
          'androidPackage': 'com.acme.android',
          'environments': [
            {
              'namedEnvironmentId': 1,
              'slug': 'dev',
              'displayName': 'Development',
            },
          ],
          'cells': [
            {
              'namedEnvironmentId': 1,
              'platform': 'android',
              'lastSeenAt': '2026-10-08T12:00:00.000Z',
              'appBuild': 96,
              'appVersion': '2.4.0',
              'sdkVersion': '2.1.0',
              'recentPresentations': 200,
              'recentFallbacks': 30,
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final connection = await connectServer(store: store, httpClient: client);

    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_read_platforms',
        arguments: {
          'organizationId': 7,
          'projectSlug': 'mobile',
          'appSlug': 'lumen',
        },
      ),
    );

    expect(result.isError, isNot(true));
    expect(calls.single['method'], 'readPlatforms');
    expect(calls.single['organizationId'], 7);
    expect(calls.single['appSlug'], 'lumen');
    final report = result.structuredContent!;
    expect(report['seen'], 1);
    expect(report['cells'], 3);
    final platforms = (report['platforms']! as List)
        .cast<Map<String, Object?>>();
    expect(
      [for (final p in platforms) p['platform']],
      ['ios', 'android', 'web'],
    );
    expect(platforms[1]['identifier'], 'com.acme.android');
    final cell = (platforms[1]['environments']! as List).single as Map;
    expect(cell, {
      'environment': 'dev',
      'environmentName': 'Development',
      'seen': true,
      'lastSeenHourUtc': '2026-10-08T12:00:00.000Z',
      'appVersion': '2.4.0',
      'appBuild': 96,
      'sdkVersion': '2.1.0',
      'presentationsLast7Days': 200,
      'fallbacksLast7Days': 30,
      'fallbackShare': 0.15,
    });
    expect(
      (platforms[0]['environments']! as List).single,
      containsPair('seen', false),
    );
  });
}
