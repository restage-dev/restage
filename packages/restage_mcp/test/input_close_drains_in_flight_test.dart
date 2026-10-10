@Timeout(Duration(seconds: 90))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('a call still in flight when input closes is answered', () async {
    final backendReached = Completer<void>();
    final releaseBackend = Completer<void>();
    final backend = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => backend.close(force: true));
    unawaited(() async {
      await for (final request in backend) {
        await request.drain<void>();
        backendReached.complete();
        await releaseBackend.future;
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'organizationId': 7,
              'session': {
                'memberships': [
                  {
                    'organizationId': 7,
                    'slug': 'acme',
                    'name': 'Acme',
                    'role': 'admin',
                  },
                ],
                'workspaceExperiences': <Object>[],
              },
              'projects': <Object>[],
              'apps': <Object>[],
              'environments': <Object>[],
              'environmentTargets': <Object>[],
              'surfaces': <Object>[],
            }),
          );
        await request.response.close();
      }
    }());

    final configDir = Directory.systemTemp.createTempSync('restage_mcp_eof');
    addTearDown(() => configDir.deleteSync(recursive: true));
    final credentials = File('${configDir.path}/restage/credentials')
      ..parent.createSync(recursive: true);
    credentials.writeAsStringSync(
      jsonEncode({
        'endpoint': 'http://127.0.0.1:${backend.port}/',
        'kind': 'authKey',
        'authToken': 'keyId:key',
      }),
    );

    final process = await Process.start(
      'dart',
      ['run', 'bin/restage_mcp.dart'],
      environment: {'XDG_CONFIG_HOME': configDir.path},
    );
    addTearDown(process.kill);
    final lines = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .map((line) => jsonDecode(line) as Map<String, Object?>)
        .asBroadcastStream();

    void send(Map<String, Object?> message) {
      process.stdin.writeln(jsonEncode(message));
    }

    send({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'initialize',
      'params': {
        'protocolVersion': '2025-06-18',
        'capabilities': <String, Object?>{},
        'clientInfo': {'name': 'eof test', 'version': '0'},
      },
    });
    send({'jsonrpc': '2.0', 'method': 'notifications/initialized'});
    await lines.firstWhere((m) => m['id'] == 1);

    final answer = lines.firstWhere((m) => m['id'] == 2);
    send({
      'jsonrpc': '2.0',
      'id': 2,
      'method': 'tools/call',
      'params': {
        'name': 'restage_list_organizations',
        'arguments': <String, Object?>{},
      },
    });
    await backendReached.future;

    // The client is done talking before the server has anything to say.
    await process.stdin.close();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    releaseBackend.complete();

    final response = await answer;
    final result = response['result']! as Map<String, Object?>;
    expect(result['isError'], isNot(true));
    final orgs =
        (result['structuredContent']! as Map)['organizations']! as List;
    expect((orgs.single as Map)['slug'], 'acme');
    expect(await process.exitCode, 0);
  });
}
