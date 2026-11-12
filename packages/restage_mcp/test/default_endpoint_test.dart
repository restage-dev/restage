import 'dart:convert';
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

  test('restage_login uses the backend the project names unless '
      'RESTAGE_BACKEND_URL is set', () async {
    final project = Directory.systemTemp.createTempSync('restage_mcp_app_');
    addTearDown(() => project.deleteSync(recursive: true));
    File('${project.path}/pubspec.yaml').writeAsStringSync('name: app\n');
    File(
      '${project.path}/restage_config.yaml',
    ).writeAsStringSync('endpoint: https://api-example.restage.dev/\n');
    Future<Uri> firstRequest(Map<String, String> environment) async {
      final requested = <Uri>[];
      final connection = await connectServer(
        store: FileCredentialStore('${project.path}/credentials'),
        environment: environment,
        httpClient: MockClient((request) async {
          requested.add(request.url);
          return http.Response('', 503);
        }),
        openBrowser: (_) async {},
      );
      await connection.callTool(
        CallToolRequest(
          name: 'restage_login',
          arguments: {'projectDirectory': project.path},
        ),
      );
      return requested.first;
    }

    expect(
      (await firstRequest(const {})).origin,
      'https://api-example.restage.dev',
    );
    expect(
      (await firstRequest(const {
        'RESTAGE_BACKEND_URL': 'https://env.example.dev',
      })).origin,
      'https://env.example.dev',
    );
  });

  test('restage_login refuses a server a project file names that is not '
      'Restage, and names it', () async {
    final project = Directory.systemTemp.createTempSync('restage_mcp_app_');
    addTearDown(() => project.deleteSync(recursive: true));
    File('${project.path}/pubspec.yaml').writeAsStringSync('name: app\n');
    File(
      '${project.path}/restage_config.yaml',
    ).writeAsStringSync('endpoint: https://api.restage-dev.example/\n');
    final requested = <Uri>[];
    var opened = false;
    final connection = await connectServer(
      store: FileCredentialStore('${project.path}/credentials'),
      environment: const {},
      httpClient: MockClient((request) async {
        requested.add(request.url);
        return http.Response('', 503);
      }),
      openBrowser: (_) async => opened = true,
    );

    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_login',
        arguments: {'projectDirectory': project.path},
      ),
    );

    expect(result.isError, isTrue);
    expect(requested, isEmpty);
    expect(opened, isFalse);
    final body =
        jsonDecode((result.content.single as TextContent).text)
            as Map<String, Object?>;
    expect(body['status'], 'refused');
    expect(body['refusedOrigin'], 'https://api.restage-dev.example');
    expect(body['namedBy'], 'restage_config.yaml');
    expect(
      body['message'],
      'restage_config.yaml names https://api.restage-dev.example, which is not '
      'a Restage server, so restage_login will not send a sign-in there. Try '
      '`restage login --endpoint https://api.restage-dev.example` in a '
      'terminal if you trust that server.',
    );
  });
}
