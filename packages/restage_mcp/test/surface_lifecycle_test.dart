import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage_cli/api.dart';
import 'package:test/test.dart';

import '_support/harness.dart';

/// The surface-family tools: list / status / history / publish, the read-only
/// rollback preview, and the rollback mutation. Kept in deliberate parity with
/// the CLI's `surface` command group — both are thin consumers of the same
/// backend RPC and the same auth/role model.
void main() {
  late Directory tempDir;
  late FileCredentialStore store;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('restage_mcp_surface_test');
    store = FileCredentialStore('${tempDir.path}/credentials');
    await store.write(
      const Credential(
        endpoint: 'https://api.test/',
        kind: CredentialKind.authKey,
        authToken: 'keyId:key',
      ),
    );
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Map<String, Object?> statusView() => {
    '__className__': 'SurfaceStatusView',
    'surfaceType': 'onboarding',
    'surfaceSlug': 'first-run',
    'environmentSlug': 'staging',
    'liveVersion': 2,
    'locked': false,
    'deliveryShape': 'flow',
    'versions': [
      {
        '__className__': 'SurfaceVersionInfo',
        'version': 2,
        'publishedAt': '2026-06-01T10:00:00.000Z',
        'contentHash': 'abc',
        'isActive': true,
        'deliveryMode': 'general',
      },
      {
        '__className__': 'SurfaceVersionInfo',
        'version': 1,
        'publishedAt': '2026-05-01T08:00:00.000Z',
        'contentHash': 'aaa',
        'isActive': false,
        'deliveryMode': 'typed',
      },
    ],
  };

  test('tools/list exposes the surface-family tools with the right '
      'schemas', () async {
    final connection = await connectServer(
      store: store,
      httpClient: MockClient((_) async => http.Response('null', 200)),
    );
    final tools = {
      for (final t in (await connection.listTools(ListToolsRequest())).tools)
        t.name: t,
    };

    expect(
      tools['restage_list_surfaces']!.inputSchema.required,
      containsAll(['projectSlug', 'appSlug', 'surfaceType']),
    );
    for (final name in [
      'restage_surface_status',
      'restage_surface_history',
      'restage_publish_surface',
    ]) {
      expect(
        tools[name]!.inputSchema.required,
        containsAll([
          'projectSlug',
          'appSlug',
          'surfaceType',
          'surfaceSlug',
          'environmentSlug',
        ]),
        reason: name,
      );
    }
    expect(
      tools['restage_rollback_preflight']!.inputSchema.required,
      containsAll([
        'projectSlug',
        'appSlug',
        'surfaceType',
        'surfaceSlug',
        'environmentSlug',
        'toVersion',
      ]),
    );
    expect(
      tools['restage_rollback_surface']!.inputSchema.required,
      containsAll([
        'projectSlug',
        'appSlug',
        'surfaceType',
        'surfaceSlug',
        'environmentSlug',
        'toVersion',
        'reason',
      ]),
    );
    // The preview is its own read-only tool; it must not require a reason.
    expect(
      tools['restage_rollback_preflight']!.inputSchema.required,
      isNot(contains('reason')),
    );
    // organizationId stays optional across the family.
    for (final name in [
      'restage_list_surfaces',
      'restage_surface_status',
      'restage_rollback_surface',
    ]) {
      expect(tools[name]!.inputSchema.properties, contains('organizationId'));
      expect(
        tools[name]!.inputSchema.required,
        isNot(contains('organizationId')),
      );
    }
  });

  test('surface_status hits surface.surfaceStatus and returns deliveryMode '
      'per version', () async {
    Map<String, dynamic>? seenBody;
    final connection = await connectServer(
      store: store,
      httpClient: MockClient((request) async {
        seenBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode(statusView()), 200);
      }),
    );

    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_surface_status',
        arguments: {
          'projectSlug': 'demo',
          'appSlug': 'mobile',
          'surfaceType': 'onboarding',
          'surfaceSlug': 'first-run',
          'environmentSlug': 'staging',
        },
      ),
    );

    expect(result.isError, isNot(true));
    expect(seenBody!['method'], 'surfaceStatus');
    expect(seenBody!['surfaceType'], 'onboarding');
    final payload = result.structuredContent!;
    expect(payload['liveVersion'], 2);
    expect(payload['deliveryShape'], 'flow');
    final versions = payload['versions']! as List<dynamic>;
    expect((versions[0] as Map<String, dynamic>)['deliveryMode'], 'general');
    expect((versions[1] as Map<String, dynamic>)['deliveryMode'], 'typed');
  });

  test('rollback_preflight is read-only: calls only rollbackPreflight and '
      'returns the classification + blocking changes', () async {
    final calledMethods = <String>[];
    final connection = await connectServer(
      store: store,
      httpClient: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        calledMethods.add(body['method'] as String);
        return http.Response(
          jsonEncode({
            '__className__': 'RollbackPreflightView',
            'surfaceType': 'onboarding',
            'surfaceSlug': 'first-run',
            'environmentSlug': 'staging',
            'toVersion': 1,
            'classification': 'contractChange',
            'blockingChanges': [r'minClientRaised @ $.minClient: floor up'],
          }),
          200,
        );
      }),
    );

    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_rollback_preflight',
        arguments: {
          'projectSlug': 'demo',
          'appSlug': 'mobile',
          'surfaceType': 'onboarding',
          'surfaceSlug': 'first-run',
          'environmentSlug': 'staging',
          'toVersion': 1,
        },
      ),
    );

    expect(result.isError, isNot(true));
    expect(calledMethods, ['rollbackPreflight']);
    final payload = result.structuredContent!;
    expect(payload['classification'], 'contractChange');
    expect(payload['blockingChanges'], [
      r'minClientRaised @ $.minClient: floor up',
    ]);
  });

  test('rollback_surface calls rollbackSurface with toVersion, reason, and '
      'lockAfter', () async {
    Map<String, dynamic>? seenBody;
    final connection = await connectServer(
      store: store,
      httpClient: MockClient((request) async {
        seenBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('null', 200);
      }),
    );

    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_rollback_surface',
        arguments: {
          'projectSlug': 'demo',
          'appSlug': 'mobile',
          'surfaceType': 'survey',
          'surfaceSlug': 'nps',
          'environmentSlug': 'staging',
          'toVersion': 3,
          'reason': 'bad copy in v4',
          'freeze': true,
        },
      ),
    );

    expect(result.isError, isNot(true));
    expect(seenBody!['method'], 'rollbackSurface');
    expect(seenBody!['surfaceType'], 'survey');
    expect(seenBody!['toVersion'], 3);
    expect(seenBody!['reason'], 'bad copy in v4');
    expect(seenBody!['lockAfter'], true);
    expect(result.structuredContent!['rolledBackTo'], 3);
  });

  test(
    'list_surfaces and surface_history pass the surface type through',
    () async {
      final seenMethods = <String, String>{};
      final connection = await connectServer(
        store: store,
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          seenMethods[body['method'] as String] =
              body['surfaceType'] as String? ?? '';
          return http.Response('[]', 200);
        }),
      );

      final list = await connection.callTool(
        CallToolRequest(
          name: 'restage_list_surfaces',
          arguments: {
            'projectSlug': 'demo',
            'appSlug': 'mobile',
            'surfaceType': 'message',
          },
        ),
      );
      expect(list.isError, isNot(true));

      final history = await connection.callTool(
        CallToolRequest(
          name: 'restage_surface_history',
          arguments: {
            'projectSlug': 'demo',
            'appSlug': 'mobile',
            'surfaceType': 'message',
            'surfaceSlug': 'promo',
            'environmentSlug': 'staging',
          },
        ),
      );
      expect(history.isError, isNot(true));

      expect(seenMethods['list'], 'message');
      expect(seenMethods['listSurfaceHistory'], 'message');
    },
  );

  test('publish_surface returns the new version number', () async {
    Map<String, dynamic>? seenBody;
    final connection = await connectServer(
      store: store,
      httpClient: MockClient((request) async {
        seenBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('5', 200);
      }),
    );

    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_publish_surface',
        arguments: {
          'projectSlug': 'demo',
          'appSlug': 'mobile',
          'surfaceType': 'onboarding',
          'surfaceSlug': 'first-run',
          'environmentSlug': 'staging',
        },
      ),
    );

    expect(result.isError, isNot(true));
    expect(seenBody!['method'], 'publish');
    expect(result.structuredContent!['version'], 5);
  });

  test('a typed surface error renders surface-neutral wording, not paywall '
      'wording', () async {
    final notFoundBody = jsonEncode({
      'className': 'SurfaceNotFoundException',
      'data': {
        '__className__': 'SurfaceNotFoundException',
        'surfaceSlug': 'first-run',
      },
    });
    final connection = await connectServer(
      store: store,
      httpClient: MockClient((_) async => http.Response(notFoundBody, 400)),
    );

    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_surface_status',
        arguments: {
          'projectSlug': 'demo',
          'appSlug': 'mobile',
          'surfaceType': 'onboarding',
          'surfaceSlug': 'first-run',
          'environmentSlug': 'staging',
        },
      ),
    );

    expect(result.isError, isTrue);
    final text = (result.content.single as TextContent).text;
    expect(text, contains('first-run'));
    expect(text, isNot(contains('paywall')));
  });

  test('rollback_surface rejects an empty or whitespace-only reason without '
      'calling the backend — the reason is the audit record', () async {
    var backendCalled = false;
    final connection = await connectServer(
      store: store,
      httpClient: MockClient((_) async {
        backendCalled = true;
        return http.Response('null', 200);
      }),
    );

    for (final reason in ['', '   ']) {
      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_rollback_surface',
          arguments: {
            'projectSlug': 'demo',
            'appSlug': 'mobile',
            'surfaceType': 'survey',
            'surfaceSlug': 'nps',
            'environmentSlug': 'staging',
            'toVersion': 3,
            'reason': reason,
          },
        ),
      );
      expect(result.isError, isTrue);
      final text = (result.content.single as TextContent).text;
      expect(text, contains('reason'));
    }
    expect(backendCalled, isFalse);
  });

  test(
    'missing or mistyped arguments from a host that skips schema '
    'validation return a clean tool error, never a protocol-level throw',
    () async {
      var backendCalled = false;
      final connection = await connectServer(
        store: store,
        httpClient: MockClient((_) async {
          backendCalled = true;
          return http.Response('null', 200);
        }),
      );

      // Missing surfaceType (read before the guarded body).
      final noType = await connection.callTool(
        CallToolRequest(
          name: 'restage_surface_status',
          arguments: {
            'projectSlug': 'demo',
            'appSlug': 'mobile',
            'surfaceSlug': 'x',
            'environmentSlug': 'staging',
          },
        ),
      );
      expect(noType.isError, isTrue);

      // Missing toVersion on the rollback mutation.
      final noVersion = await connection.callTool(
        CallToolRequest(
          name: 'restage_rollback_surface',
          arguments: {
            'projectSlug': 'demo',
            'appSlug': 'mobile',
            'surfaceType': 'survey',
            'surfaceSlug': 'nps',
            'environmentSlug': 'staging',
            'reason': 'bad copy',
          },
        ),
      );
      expect(noVersion.isError, isTrue);

      // String-typed toVersion on the rollback mutation.
      final stringVersion = await connection.callTool(
        CallToolRequest(
          name: 'restage_rollback_surface',
          arguments: {
            'projectSlug': 'demo',
            'appSlug': 'mobile',
            'surfaceType': 'survey',
            'surfaceSlug': 'nps',
            'environmentSlug': 'staging',
            'toVersion': 'three',
            'reason': 'bad copy',
          },
        ),
      );
      expect(stringVersion.isError, isTrue);

      expect(backendCalled, isFalse);
    },
  );

  test('rollback_preflight passes an unrecognized classification through '
      'raw instead of laundering it to "unknown"', () async {
    final preflightView = jsonEncode({
      '__className__': 'RollbackPreflightView',
      'surfaceType': 'onboarding',
      'surfaceSlug': 'first-run',
      'environmentSlug': 'staging',
      'toVersion': 1,
      'classification': 'someFutureClassification',
      'blockingChanges': <String>[],
    });
    final connection = await connectServer(
      store: store,
      httpClient: MockClient((_) async => http.Response(preflightView, 200)),
    );

    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_rollback_preflight',
        arguments: {
          'projectSlug': 'demo',
          'appSlug': 'mobile',
          'surfaceType': 'onboarding',
          'surfaceSlug': 'first-run',
          'environmentSlug': 'staging',
          'toVersion': 1,
        },
      ),
    );

    expect(result.isError, isNot(true));
    expect(
      result.structuredContent!['classification'],
      'someFutureClassification',
    );
  });

  test('an invalid surfaceType returns a clean tool error naming the valid '
      'values, without calling the backend', () async {
    var backendCalled = false;
    final connection = await connectServer(
      store: store,
      httpClient: MockClient((_) async {
        backendCalled = true;
        return http.Response('null', 200);
      }),
    );

    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_surface_status',
        arguments: {
          'projectSlug': 'demo',
          'appSlug': 'mobile',
          'surfaceType': 'bogus',
          'surfaceSlug': 'x',
          'environmentSlug': 'staging',
        },
      ),
    );

    expect(result.isError, isTrue);
    final text = (result.content.single as TextContent).text;
    expect(text, contains('onboarding'));
    expect(text, contains('paywall'));
    expect(backendCalled, isFalse);
  });
}
