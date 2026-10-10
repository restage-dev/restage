import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage_cli/api.dart';
import 'package:test/test.dart';

import '_support/fake_backend.dart';
import '_support/harness.dart';

/// The build tools, in parity with `restage build push`, `restage surface
/// push` and the console: heads, the push, and the notice a surface push
/// carries when the environment's build cannot draw its app widgets.
void main() {
  late Directory tempDir;
  late FileCredentialStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('restage_mcp_builds_');
    store = FileCredentialStore('${tempDir.path}/credentials');
    await store.write(
      const Credential(
        endpoint: 'https://api.test/',
        kind: CredentialKind.authKey,
        authToken: 'keyId:key',
      ),
    );
  });

  tearDown(() => tempDir.delete(recursive: true));

  Map<String, Object?> versionView(int version, Map<String, int> libraries) =>
      <String, Object?>{
        'renderBundleId': 40 + version,
        'appId': 5,
        'version': version,
        'contentHash': 'sha256:${'0' * 64}',
        'engineSetId': '1' * 64,
        'capabilityManifestJson': jsonEncode({
          'formatVersion': 1,
          'catalog': {
            'libraries': {
              for (final entry in libraries.entries)
                entry.key: {'capabilityVersion': entry.value},
            },
            'widgets': <Object?>[],
          },
        }),
        'byteLength': 1024,
        'sourceCommit': 'a91f2c3d',
        'sourceDirty': false,
        'uploadedAt': '2030-01-01T00:00:00.000Z',
      };

  test('the build tools are listed with their required inputs', () async {
    final connection = await connectServer(
      store: store,
      httpClient: MockClient((_) async => http.Response('null', 200)),
    );
    final tools = {
      for (final tool in (await connection.listTools(ListToolsRequest())).tools)
        tool.name: tool,
    };
    expect(
      tools['restage_list_builds']!.inputSchema.properties!.keys,
      containsAll(['projectDirectory', 'projectSlug', 'appSlug']),
    );
    expect(tools['restage_push_build']!.inputSchema.required, [
      'projectDirectory',
    ]);
    expect(
      tools['restage_push_build']!.inputSchema.properties,
      contains('environmentSlug'),
    );
    expect(
      tools['restage_push_build']!.inputSchema.properties,
      contains('recordGit'),
    );
  });

  test('list_builds reads each head as the server sends it', () async {
    Map<String, dynamic>? seenBody;
    final connection = await connectServer(
      store: store,
      httpClient: MockClient((request) async {
        seenBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'appId': 5,
            'environmentHeads': [
              {
                'head': 'staging',
                'version': versionView(4, {'acme.widgets': 2}),
                'updatedAt': '2030-01-02T00:00:00.000Z',
              },
            ],
            'personalHeads': [
              {
                'head': 'user/alice',
                'version': versionView(3, {}),
                'ownerDisplayName': 'Alice',
                'updatedAt': '2030-01-01T00:00:00.000Z',
              },
            ],
          }),
          200,
        );
      }),
    );

    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_list_builds',
        arguments: {'projectSlug': 'demo', 'appSlug': 'mobile'},
      ),
    );

    expect(result.isError, isNot(true));
    expect(seenBody!['method'], 'listHeads');
    final heads = result.structuredContent!['heads'] as List<Object?>;
    expect(heads, hasLength(2));
    final staging = heads.first! as Map<String, Object?>;
    expect(staging['head'], 'staging');
    expect(staging['version'], 4);
    expect(staging['sourceCommit'], 'a91f2c3d');
    expect(staging['libraries'], {'acme.widgets': 2});
    expect(staging['updatedAt'], '2030-01-02T00:00:00.000Z');
    expect(staging['owner'], isNull);
    final alice = heads.last! as Map<String, Object?>;
    expect(alice['owner'], 'Alice');
    expect(alice['libraries'], isEmpty);
  });

  test('draft push says when the build cannot draw the surface', () async {
    final connection = await connectServer(
      store: store,
      httpClient: fakeBackend((call) async {
        if (call.method == 'coverage') {
          return http.Response(
            jsonEncode({
              'requiredLibraries': [
                {'namespace': 'acme.widgets', 'minVersion': 1},
              ],
              'headVersion': null,
              'registeredLibraries': <Object?>[],
            }),
            200,
          );
        }
        return http.Response('5', 200);
      }),
    );

    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_push_surface_draft',
        arguments: {
          'projectSlug': 'demo',
          'appSlug': 'mobile',
          'surfaceType': 'paywall',
          'surfaceSlug': 'pro',
          'environmentSlug': 'staging',
        },
      ),
    );

    expect(result.isError, isNot(true));
    expect(result.structuredContent!['revision'], 5);
    expect(
      result.structuredContent!['buildNotice'],
      'This surface uses widgets from your app (acme.widgets). The dashboard '
      'has no build of mobile for staging yet, so it cannot display them; '
      'run `restage build push --env staging`.',
    );
  });

  test('draft push stays quiet when the build covers the surface', () async {
    final connection = await connectServer(
      store: store,
      httpClient: fakeBackend((call) async {
        if (call.method == 'coverage') {
          return http.Response(
            jsonEncode({
              'requiredLibraries': [
                {'namespace': 'acme.widgets', 'minVersion': 1},
              ],
              'headVersion': 4,
              'registeredLibraries': [
                {'namespace': 'acme.widgets', 'capabilityVersion': 2},
              ],
            }),
            200,
          );
        }
        return http.Response('5', 200);
      }),
    );

    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_push_surface_draft',
        arguments: {
          'projectSlug': 'demo',
          'appSlug': 'mobile',
          'surfaceType': 'paywall',
          'surfaceSlug': 'pro',
          'environmentSlug': 'staging',
        },
      ),
    );

    expect(result.isError, isNot(true));
    expect(result.structuredContent, isNot(contains('buildNotice')));
  });

  test('push_build runs the build push with the arguments given', () async {
    List<String>? seenArgs;
    final connection = await connectServer(
      store: store,
      httpClient: MockClient((_) async => http.Response('null', 200)),
      cliRunner:
          (
            List<String> args, {
            required StringSink stdout,
            required StringSink stderr,
          }) async {
            seenArgs = args;
            stdout.writeln(
              'Pushed mobile staging version 4. Built from a91f2c3.',
            );
            return 0;
          },
    );

    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_push_build',
        arguments: {
          'projectDirectory': '/work/app',
          'environmentSlug': 'staging',
          'recordGit': true,
        },
      ),
    );

    expect(result.isError, isNot(true));
    expect(seenArgs, [
      'build',
      'push',
      '-C',
      '/work/app',
      '--env',
      'staging',
      '--record-git',
    ]);
    expect(result.structuredContent!['exitCode'], 0);
    expect(
      result.structuredContent!['output'],
      contains('Pushed mobile staging version 4'),
    );
  });

  test(
    'push_build reports a refused push as an error with its words',
    () async {
      final connection = await connectServer(
        store: store,
        httpClient: MockClient((_) async => http.Response('null', 200)),
        cliRunner:
            (
              List<String> args, {
              required StringSink stdout,
              required StringSink stderr,
            }) async {
              stderr.writeln('This credential cannot push builds.');
              return 1;
            },
      );

      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_push_build',
          arguments: {'projectDirectory': '/work/app'},
        ),
      );

      expect(result.isError, isTrue);
      expect(
        (result.content.single as TextContent).text,
        contains('This credential cannot push builds.'),
      );
    },
  );
  test('push_build never sends a key to an endpoint a project names', () async {
    final project = Directory('${tempDir.path}/app')..createSync();
    File('${project.path}/restage_config.yaml').writeAsStringSync(
      'project: demo\napp: mobile\nendpoint: https://api.attacker.example/\n',
    );
    final keyed = <Uri>[];
    final connection = await connectServer(
      store: store,
      httpClient: MockClient((request) async {
        if (request.headers['authorization'] == 'Bearer $_key') {
          keyed.add(request.url);
        }
        return http.Response('null', 200);
      }),
      environment: const {'RESTAGE_EXPERIMENTAL': '1', 'RESTAGE_API_KEY': _key},
    );

    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_push_build',
        arguments: {'projectDirectory': project.path},
      ),
    );

    expect(result.isError, isTrue);
    expect(keyed, isEmpty);
    expect(
      (result.content.single as TextContent).text,
      contains('is sent only to http://localhost:8080/'),
    );
  });

  test('push_build words a target refusal for this server', () async {
    final project = Directory('${tempDir.path}/app')..createSync();
    File(
      '${project.path}/restage_config.yaml',
    ).writeAsStringSync('project: demo\napp: mobile\n');
    final connection = await connectServer(
      store: store,
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'className': 'TargetSelectionRefusedException',
            'data': {
              'reason': 'environmentOnBothPlanes',
              'environmentSlug': 'staging',
            },
          }),
          400,
        ),
      ),
      environment: const {
        'RESTAGE_EXPERIMENTAL': '1',
        'RESTAGE_API_KEY': _key,
        'RESTAGE_BACKEND_URL': 'https://api.test/',
      },
    );

    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_push_build',
        arguments: {'projectDirectory': project.path},
      ),
    );

    expect(result.isError, isTrue);
    final text = (result.content.single as TextContent).text;
    expect(text, contains('Pass runtimePlane: sandbox or live.'));
    expect(text, isNot(contains('--plane')));
  });
}

const _key =
    'rs_sk_sandbox_staging_a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1';
