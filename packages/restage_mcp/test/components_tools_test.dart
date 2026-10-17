import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage_cli/api.dart';
import 'package:test/test.dart';

import 'package:restage_shared/restage_shared.dart'
    show BlobSurfacePayload, SurfaceEditorState;
import 'package:restage_shared/rfw_formats.dart'
    show encodeLibraryBlob, parseLibraryFile;

import '_support/harness.dart';

String _payloadWire() {
  final payload = BlobSurfacePayload(
    minClient: 1,
    blob: encodeLibraryBlob(
      parseLibraryFile(
        'import restage.core;\nwidget main = Container(child: Text(text: args.label));\n',
      ),
    ),
    editorState: SurfaceEditorState(
      meta: {
        'slots': {
          'main': {'label': 'Hello'},
        },
      },
    ).encode(),
  );
  return "decode('${base64Encode(payload.canonicalBytes)}', 'base64')";
}

void main() {
  late Directory tempDir;
  late FileCredentialStore store;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync(
      'restage_mcp_components_test',
    );
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

  Map<String, Object?> component({bool? inAppBuild = false}) => {
    'id': 1,
    'name': 'badge',
    'scope': 'project',
    'latestVersion': 2,
    'updatedAt': '2026-10-14T00:00:00.000Z',
    'usedBy': 3,
    'onOlderVersion': 1,
    'inAppBuild': inAppBuild,
    '__className__': 'ComponentSummaryView',
  };

  test('list returns the rows with the numbers and no display text', () async {
    final calls = <Map<String, dynamic>>[];
    final connection = await connectServer(
      store: store,
      httpClient: MockClient((request) async {
        calls.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(
          jsonEncode([component()]),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_list_components',
        arguments: {'organizationId': 7, 'projectSlug': 'acme'},
      ),
    );

    expect(result.isError, isNot(true));
    expect(calls.single['projectSlug'], 'acme');
    expect(calls.single['organizationId'], 7);
    final rows = result.structuredContent!['components']! as List<dynamic>;
    final row = rows.single as Map;
    expect(row['usedBy'], 3);
    expect(row['onOlderVersion'], 1);
    expect(row['inAppBuild'], false);
    expect(row.containsKey('usage'), isFalse);
  });

  test('get reads the newest version once', () async {
    final loads = <Object?>[];
    final connection = await connectServer(
      store: store,
      httpClient: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body['method'] == 'loadVersion') loads.add(body['version']);
        final response = body['method'] == 'list'
            ? [component()]
            : {
                'componentId': 1,
                'version': body['version'],
                'payload': _payloadWire(),
                'createdAt': '2026-10-1${body['version']}T00:00:00.000Z',
              };
        return http.Response(
          jsonEncode(response),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_get_component',
        arguments: {
          'organizationId': 7,
          'projectSlug': 'acme',
          'name': 'badge',
        },
      ),
    );

    expect(result.isError, isNot(true));
    final detail = result.structuredContent!['component']! as Map;
    expect(loads, [2]);
    expect(detail['createdAt'], '2026-10-12T00:00:00.000Z');
    expect(detail['entry'], 'Container');
    expect(detail['declarations'], ['main']);
    expect(detail['imports'], ['restage.core']);
    expect(detail['slots'], {
      'main': {'label': 'Hello'},
    });
    expect(detail.containsKey('usage'), isFalse);
  });
}
