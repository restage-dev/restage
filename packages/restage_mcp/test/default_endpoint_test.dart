import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage_cli/api.dart';
import 'package:test/test.dart';

import '_support/harness.dart';

void main() {
  test(
    'restage_login with no endpoint signs in against Restage Cloud',
    () async {
      final directory = Directory.systemTemp.createTempSync('restage_mcp_');
      addTearDown(() => directory.deleteSync(recursive: true));
      final requested = <Uri>[];
      final connection = await connectServer(
        store: FileCredentialStore('${directory.path}/credentials'),
        httpClient: MockClient((request) async {
          requested.add(request.url);
          return http.Response('', 503);
        }),
        openBrowser: (_) async {},
      );

      await connection.callTool(
        CallToolRequest(name: 'restage_login', arguments: {}),
      );

      expect(requested, isNotEmpty);
      expect(requested.first.origin, 'https://api.restage.dev');
    },
    skip: Platform.environment['RESTAGE_BACKEND_URL']?.isNotEmpty ?? false
        ? 'RESTAGE_BACKEND_URL overrides the default'
        : false,
  );
}
