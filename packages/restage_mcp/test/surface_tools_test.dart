import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_mcp/client.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/api.dart';
import 'package:restage_mcp/restage_mcp.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

import '_support/fake_backend.dart';
import '_support/harness.dart';

Map<String, Object?> _statusView({
  String? sourceKind = 'screen',
  List<int> versions = const [2],
}) => {
  '__className__': 'SurfaceStatusView',
  'surfaceType': 'onboarding',
  'surfaceSlug': 'first-run',
  'environmentSlug': 'staging',
  'liveVersion': 2,
  'locked': false,
  'deliveryShape': 'flow',
  'sourceKind': ?sourceKind,
  'contractVersion': sourceKind == 'screen' ? 3 : null,
  'versions': [
    for (final version in versions)
      {
        '__className__': 'SurfaceVersionInfo',
        'version': version,
        'publishedAt': '2026-06-01T10:00:00.000Z',
        'contentHash': 'abc',
        'isActive': version == 2,
        'deliveryMode': 'general',
      },
  ],
};

Map<String, Object?> _history(List<int> revisions) => {
  '__className__': 'SurfaceContractFamilyView',
  'family': {
    '__className__': 'SurfaceContractFamilyReference',
    'surfaceType': 'onboarding',
    'surfaceSlug': 'first-run',
    'sourceKind': 'screen',
    'contractVersion': 3,
  },
  'payloadKind': 'blob',
  'revisions': [
    for (final revision in revisions)
      {
        '__className__': 'SurfaceContractPublishedRevisionView',
        'publishedRevision': revision,
        'publishedAt': '2026-06-29T18:17:51.000Z',
        'contentHash': 'sha-$revision',
        'minClient': 1,
        'payloadKind': 'blob',
        'isActive': false,
      },
  ],
};

Map<String, Object?> _activation(int revision) => {
  '__className__': 'SurfaceContractFamilyOperationResult',
  'family': {
    '__className__': 'SurfaceContractFamilyReference',
    'surfaceType': 'onboarding',
    'surfaceSlug': 'first-run',
    'sourceKind': 'screen',
    'contractVersion': 3,
  },
  'publishedRevision': revision,
  'activePublishedRevisionBefore': 1,
  'activePublishedRevisionAfter': revision,
  'identityFrozenAfter': false,
};

const _surface = <String, Object?>{
  'projectSlug': 'demo',
  'appSlug': 'mobile',
  'surfaceType': 'onboarding',
  'surfaceSlug': 'first-run',
  'environmentSlug': 'staging',
};

String _text(CallToolResult result) =>
    (result.content.single as TextContent).text;

void main() {
  late Directory tempDir;
  late FileCredentialStore store;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('restage_mcp_surface_tools');
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

  Future<ServerConnection> connect(
    Future<http.Response> Function(BackendCall call) handler, {
    List<BackendCall>? calls,
    List<Map<String, Object?>>? organizations,
    CliRunner? cliRunner,
  }) => connectServer(
    store: store,
    httpClient: organizations == null
        ? fakeBackend(handler, calls: calls)
        : fakeBackend(handler, calls: calls, organizations: organizations),
    cliRunner: cliRunner,
  );

  test('every target-scoped surface tool takes an optional plane and '
      'target id beside the required environment', () async {
    final connection = await connect((_) async => http.Response('null', 200));
    final tools = {
      for (final t in (await connection.listTools(ListToolsRequest())).tools)
        t.name: t,
    };
    for (final name in [
      'restage_surface_status',
      'restage_surface_history',
      'restage_surface_audit',
      'restage_push_surface_draft',
      'restage_publish_surface',
      'restage_rollback_preflight',
      'restage_rollback_surface',
      'restage_kill_surface',
      'restage_freeze_surface',
      'restage_unfreeze_surface',
    ]) {
      final schema = tools[name]!.inputSchema;
      expect(schema.required, contains('surfaceSlug'), reason: name);
      expect(schema.properties, contains('surfaceType'), reason: name);
      final reads = {
        'restage_surface_status',
        'restage_surface_history',
        'restage_surface_audit',
      };
      expect(
        schema.required!.contains('surfaceType'),
        !reads.contains(name),
        reason: name,
      );
      expect(
        schema.properties!.keys,
        containsAll([
          'projectDirectory',
          'projectSlug',
          'appSlug',
          'environmentSlug',
        ]),
        reason: name,
      );
      for (final optional in [
        'runtimePlane',
        'environmentTargetId',
        'organizationId',
      ]) {
        expect(schema.properties, contains(optional), reason: name);
        expect(schema.required, isNot(contains(optional)), reason: name);
      }
    }
    expect(tools['restage_push_surface']!.inputSchema.required, [
      'projectDirectory',
      'surface',
    ]);
    expect(tools['restage_publish_surface']!.inputSchema.required, [
      'surfaceType',
      'surfaceSlug',
    ]);
    expect(
      tools['restage_kill_surface']!.inputSchema.required,
      contains('reason'),
    );
    expect(
      tools['restage_list_surfaces']!.inputSchema.required,
      isNot(contains('surfaceType')),
    );
  });

  test('status passes an exact target through without discovery and '
      'returns each version delivery mode', () async {
    final calls = <BackendCall>[];
    final connection = await connect(
      (_) async => http.Response(jsonEncode(_statusView()), 200),
      calls: calls,
    );

    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_surface_status',
        arguments: {
          ..._surface,
          'environmentTargetId': 42,
          'runtimePlane': 'sandbox',
        },
      ),
    );

    expect(result.isError, isNot(true), reason: _text(result));
    expect(calls.map((call) => call.method), ['surfaceStatus']);
    expect(calls.single.body['environmentTargetId'], 42);
    expect(calls.single.body['runtimePlane'], 'sandbox');
    final versions = result.structuredContent!['versions']! as List<dynamic>;
    expect((versions.single as Map)['deliveryMode'], 'general');
  });

  test('selectors go to the server as given, with no discovery', () async {
    final calls = <BackendCall>[];
    final connection = await connect(
      (_) async => http.Response(jsonEncode(_statusView()), 200),
      calls: calls,
    );

    final result = await connection.callTool(
      CallToolRequest(name: 'restage_surface_status', arguments: _surface),
    );

    expect(result.isError, isNot(true), reason: _text(result));
    expect(calls.map((call) => call.method), ['surfaceStatus']);
    final status = calls.single.body;
    expect(status['environmentSlug'], 'staging');
    expect(status, isNot(contains('environmentTargetId')));
    expect(status, isNot(contains('runtimePlane')));
    expect(status, isNot(contains('organizationId')));
  });

  test('the server refusals read in MCP terms', () async {
    for (final (fields, sentence) in [
      (
        {'reason': 'environmentOnBothPlanes', 'environmentSlug': 'production'},
        "Environment 'production' exists on both runtime planes. Pass "
            'runtimePlane: sandbox or live.',
      ),
      (
        {
          'reason': 'multipleOrganizations',
          'organizationSlugs': ['acme', 'beta'],
        },
        'This project is in more than one of your organizations (acme, '
            'beta). Pass organizationId.',
      ),
    ]) {
      final connection = await connect(
        (_) async => typedError('TargetSelectionRefusedException', fields),
      );

      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_kill_surface',
          arguments: {..._surface, 'reason': 'broken'},
        ),
      );

      expect(result.isError, isTrue);
      expect(_text(result), sentence);
    }
  });

  test('history lists the pushed revisions of the resolved family', () async {
    final calls = <BackendCall>[];
    final connection = await connect(
      (_) async => http.Response(jsonEncode(_history([1, 2])), 200),
      calls: calls,
    );

    final result = await connection.callTool(
      CallToolRequest(name: 'restage_surface_history', arguments: _surface),
    );

    expect(result.isError, isNot(true), reason: _text(result));
    final history = calls.single;
    expect(history.method, 'surfaceContractHistory');
    expect(history.body['surfaceSlug'], 'first-run');
    expect(history.body, isNot(contains('sourceKind')));
    expect(
      result.structuredContent!['family'],
      containsPair('contractVersion', 3),
    );
    final revisions = result.structuredContent!['revisions']! as List<dynamic>;
    expect(revisions, hasLength(2));
  });

  test('history reports a surface with no published family', () async {
    final connection = await connect(
      (_) async => typedError('SurfaceContractFamilyViolation', {
        'code': 'familyNotFound',
        'message': 'The surface has no pushed revision here.',
      }),
    );

    final result = await connection.callTool(
      CallToolRequest(name: 'restage_surface_history', arguments: _surface),
    );

    expect(result.isError, isTrue);
    expect(_text(result), 'The surface has no pushed revision here.');
  });

  test('audit reads the surface audit timeline', () async {
    final calls = <BackendCall>[];
    final connection = await connect(
      (_) async => http.Response('[]', 200),
      calls: calls,
    );

    final result = await connection.callTool(
      CallToolRequest(name: 'restage_surface_audit', arguments: _surface),
    );

    expect(result.isError, isNot(true), reason: _text(result));
    expect(calls.last.method, 'listSurfaceHistory');
    expect(calls.last.body['surfaceType'], 'onboarding');
    expect(result.structuredContent!['events'], isEmpty);
  });

  group('publish', () {
    test(
      'asks the server for the newest pushed revision with the default reason',
      () async {
        final calls = <BackendCall>[];
        final connection = await connect(
          (_) async => http.Response(jsonEncode(_activation(5)), 200),
          calls: calls,
        );

        final result = await connection.callTool(
          CallToolRequest(name: 'restage_publish_surface', arguments: _surface),
        );

        expect(result.isError, isNot(true), reason: _text(result));
        final activate = calls.singleWhere(
          (call) => call.method == 'activateSurface',
        );
        expect(activate.body['publishedRevision'], isNull);
        expect(activate.body['reason'], 'Published from the MCP server');
        expect(calls.map((call) => call.method), [
          'resolveTarget',
          'activateSurface',
        ]);
        expect(activate.body['environmentSlug'], 'staging');
        expect(activate.body, isNot(contains('contractVersion')));
        expect(result.structuredContent!['publishedRevision'], 5);
        expect(result.structuredContent!['latestPushed'], isTrue);
        expect(
          result.structuredContent!['showInApp'],
          allOf(contains('Restage.configure'), contains('<Name>Surface()')),
        );
      },
    );

    test('shows the generated widget the published revision names', () async {
      final connection = await connect(
        (_) async => http.Response(
          jsonEncode({..._activation(5), 'mountName': 'FirstRunScreenSurface'}),
          200,
        ),
      );

      final result = await connection.callTool(
        CallToolRequest(name: 'restage_publish_surface', arguments: _surface),
      );

      expect(result.isError, isNot(true), reason: _text(result));
      expect(
        result.structuredContent!['showInApp'],
        allOf(
          contains('Restage.configure'),
          contains(
            'then add FirstRunScreenSurface(...) where it should appear',
          ),
        ),
      );
    });

    test('an explicit revision and reason skip the history read', () async {
      final calls = <BackendCall>[];
      final connection = await connect(
        (_) async => http.Response(jsonEncode(_activation(2)), 200),
        calls: calls,
      );

      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_publish_surface',
          arguments: {..._surface, 'revision': 2, 'reason': 'ship it'},
        ),
      );

      expect(result.isError, isNot(true), reason: _text(result));
      expect(
        calls.map((call) => call.method),
        isNot(contains('surfaceContractHistory')),
      );
      final activate = calls.singleWhere(
        (call) => call.method == 'activateSurface',
      );
      expect(activate.body['publishedRevision'], 2);
      expect(activate.body['reason'], 'ship it');
      expect(result.structuredContent!['latestPushed'], isFalse);
    });

    test('nothing pushed reads the server refusal', () async {
      final connection = await connect(
        (_) async => typedError('SurfaceContractFamilyViolation', {
          'code': 'familyNotFound',
          'message': 'The surface has no pushed revision here.',
        }),
      );

      final result = await connection.callTool(
        CallToolRequest(name: 'restage_publish_surface', arguments: _surface),
      );

      expect(result.isError, isTrue);
      expect(_text(result), 'The surface has no pushed revision here.');
    });

    test('a non-positive revision or a receipt without a project directory '
        'is refused before any change', () async {
      final calls = <BackendCall>[];
      final connection = await connect(
        (_) async => http.Response('null', 200),
        calls: calls,
      );

      final zero = await connection.callTool(
        CallToolRequest(
          name: 'restage_publish_surface',
          arguments: {..._surface, 'revision': 0},
        ),
      );
      expect(zero.isError, isTrue);
      expect(
        _text(zero),
        'Expected a positive integer for the revision to publish.',
      );

      final receipt = await connection.callTool(
        CallToolRequest(
          name: 'restage_publish_surface',
          arguments: {..._surface, 'recordGit': true},
        ),
      );
      expect(receipt.isError, isTrue);
      expect(
        _text(receipt),
        'recordGit needs projectDirectory, the git working tree.',
      );
      expect(calls.map((call) => call.method), everyElement('resolveTarget'));
    });

    test('a role refusal reads with the shared sentence', () async {
      final connection = await connect(
        (_) async => typedError('UnauthorizedException', {
          'resource': 'surface',
        }, status: 403),
      );

      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_publish_surface',
          arguments: {..._surface, 'revision': 2},
        ),
      );

      expect(result.isError, isTrue);
      expect(
        _text(result),
        unauthorizedSentence(UnauthorizedReason.roleMissing),
      );
    });

    test('a live-plane billing refusal names the plan, not the role', () async {
      final connection = await connect(
        (_) async => typedError('UnauthorizedException', {
          'resource': 'hosted-billing-control-plane:publish',
          'reason': 'liveChangesNotAllowed',
        }, status: 403),
      );

      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_publish_surface',
          arguments: {..._surface, 'revision': 2},
        ),
      );

      expect(result.isError, isTrue);
      expect(_text(result), contains("organization's plan"));
    });
  });

  test(
    'kill, freeze and unfreeze send the reason and report the effect',
    () async {
      final calls = <BackendCall>[];
      final connection = await connect(
        (_) async => http.Response(
          jsonEncode({
            'surfaceType': 'onboarding',
            'surfaceSlug': 'first-run',
            'frozen': true,
            'affectedFamilies': <Object>[],
          }),
          200,
        ),
        calls: calls,
      );

      final kill = await connection.callTool(
        CallToolRequest(
          name: 'restage_kill_surface',
          arguments: {..._surface, 'reason': 'broken copy', 'frozen': true},
        ),
      );
      expect(kill.isError, isNot(true), reason: _text(kill));
      final killCall = calls.singleWhere(
        (call) => call.method == 'killSurface',
      );
      expect(killCall.body['reason'], 'broken copy');
      expect(killCall.body['mode'], 'frozen');
      expect(killCall.body['environmentSlug'], 'staging');
      expect(kill.structuredContent!['killed'], isTrue);

      for (final (tool, locked) in [
        ('restage_freeze_surface', true),
        ('restage_unfreeze_surface', false),
      ]) {
        calls.clear();
        final result = await connection.callTool(
          CallToolRequest(
            name: tool,
            arguments: {..._surface, 'reason': 'hold'},
          ),
        );
        expect(result.isError, isNot(true), reason: _text(result));
        final lock = calls.singleWhere(
          (call) => call.method == 'setSurfaceLock',
        );
        expect(lock.body['locked'], locked);
        expect(lock.body['reason'], 'hold');
        expect(result.structuredContent!['frozen'], locked);
      }
    },
  );

  test('a blank reason is refused before the backend on every audited '
      'mutation', () async {
    final calls = <BackendCall>[];
    final connection = await connect(
      (_) async => http.Response('null', 200),
      calls: calls,
    );
    for (final (tool, extra) in [
      ('restage_kill_surface', <String, Object?>{}),
      ('restage_freeze_surface', <String, Object?>{}),
      ('restage_unfreeze_surface', <String, Object?>{}),
      ('restage_rollback_surface', <String, Object?>{'toVersion': 1}),
    ]) {
      final result = await connection.callTool(
        CallToolRequest(
          name: tool,
          arguments: {..._surface, ...extra, 'reason': '   '},
        ),
      );
      expect(result.isError, isTrue, reason: tool);
      expect(_text(result), contains('reason'), reason: tool);
    }
    expect(calls, isEmpty);
  });

  test('rollback sends the family selectors, reason, and lock', () async {
    final calls = <BackendCall>[];
    final connection = await connect(
      (_) async => http.Response('null', 200),
      calls: calls,
    );

    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_rollback_surface',
        arguments: {
          ..._surface,
          'sourceKind': 'screen',
          'contractVersion': 3,
          'toVersion': 2,
          'reason': 'bad copy in v4',
          'freeze': true,
        },
      ),
    );

    expect(result.isError, isNot(true), reason: _text(result));
    final rollback = calls.singleWhere(
      (call) => call.method == 'rollbackSurface',
    );
    expect(rollback.body['toVersion'], 2);
    expect(rollback.body['lockAfter'], isTrue);
    expect(rollback.body['contractVersion'], 3);
    expect(result.structuredContent!['rolledBackTo'], 2);
  });

  test('rollback preflight is read-only and passes the classification '
      'through raw', () async {
    final calls = <BackendCall>[];
    final connection = await connect(
      (_) async => http.Response(
        jsonEncode({
          '__className__': 'RollbackPreflightView',
          'surfaceType': 'onboarding',
          'surfaceSlug': 'first-run',
          'environmentSlug': 'staging',
          'toVersion': 1,
          'classification': 'someFutureClassification',
          'blockingChanges': <String>[],
        }),
        200,
      ),
      calls: calls,
    );

    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_rollback_preflight',
        arguments: {..._surface, 'toVersion': 1},
      ),
    );

    expect(result.isError, isNot(true), reason: _text(result));
    expect(
      calls.where((call) => call.endpoint == 'surface').map((c) => c.method),
      ['rollbackPreflight'],
    );
    expect(
      result.structuredContent!['classification'],
      'someFutureClassification',
    );
  });

  test(
    'a typed surface refusal reads with the sentence the CLI prints',
    () async {
      final connection = await connect(
        (_) async => typedError('SurfaceNotFoundException', {
          'surfaceSlug': 'first-run',
        }),
      );

      final result = await connection.callTool(
        CallToolRequest(name: 'restage_surface_status', arguments: _surface),
      );

      expect(result.isError, isTrue);
      expect(_text(result), "Surface 'first-run' not found.");
    },
  );

  test('an invalid surfaceType is refused with the valid values', () async {
    final calls = <BackendCall>[];
    final connection = await connect(
      (_) async => http.Response('null', 200),
      calls: calls,
    );

    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_surface_status',
        arguments: {..._surface, 'surfaceType': 'bogus'},
      ),
    );

    expect(result.isError, isTrue);
    expect(_text(result), contains('onboarding'));
    expect(calls, isEmpty);
  });

  test('draft push stores a new revision and reports it', () async {
    final calls = <BackendCall>[];
    final connection = await connect((call) async {
      if (call.method == 'coverage') return http.Response('null', 500);
      return http.Response('5', 200);
    }, calls: calls);

    final result = await connection.callTool(
      CallToolRequest(name: 'restage_push_surface_draft', arguments: _surface),
    );

    expect(result.isError, isNot(true), reason: _text(result));
    final publish = calls.singleWhere((call) => call.method == 'publish');
    expect(publish.body['surfaceType'], 'onboarding');
    expect(publish.body['environmentSlug'], 'staging');
    expect(result.structuredContent!['revision'], 5);
  });

  test('draft pull returns clean base64, never the wire wrapper', () async {
    final frame = BlobSurfacePayload(
      minClient: 3,
      blob: Uint8List.fromList(<int>[1, 2, 3, 250]),
    ).canonicalBytes;
    final connection = await connect(
      (_) async => http.Response(
        jsonEncode("decode('${base64Encode(frame)}', 'base64')"),
        200,
      ),
    );

    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_pull_surface_draft',
        arguments: {
          'projectSlug': 'demo',
          'appSlug': 'mobile',
          'surfaceType': 'paywall',
          'surfaceSlug': 'pro',
        },
      ),
    );

    expect(result.isError, isNot(true), reason: _text(result));
    final encoded = result.structuredContent!['draftBase64']! as String;
    expect(base64Decode(encoded), frame);
    expect(_text(result), isNot(contains("decode('")));
  });

  test('list without a type reads every surface type', () async {
    final calls = <BackendCall>[];
    final connection = await connect(
      (_) async => http.Response('[]', 200),
      calls: calls,
    );

    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_list_surfaces',
        arguments: {'projectSlug': 'demo', 'appSlug': 'mobile'},
      ),
    );

    expect(result.isError, isNot(true), reason: _text(result));
    expect(calls.map((call) => call.body['surfaceType']).toSet(), {
      'paywall',
      'onboarding',
      'message',
      'survey',
      'general',
    });
  });

  group('status and history without a surfaceType look the type up', () {
    Future<(CallToolResult, List<BackendCall>)> call(
      String tool,
      Map<String, List<String>> slugsByType,
    ) async {
      final calls = <BackendCall>[];
      final connection = await connect((call) async {
        if (call.method == 'list') {
          final type = call.body['surfaceType']! as String;
          return http.Response(
            jsonEncode([
              for (final slug in slugsByType[type] ?? const <String>[])
                {
                  '__className__': 'SurfaceSummary',
                  'surfaceType': type,
                  'slug': slug,
                  'name': slug,
                  'draftUpdatedAt': '2026-05-01T12:34:56.000Z',
                  'publishedVersionByEnvironment': <String, int?>{},
                },
            ]),
            200,
          );
        }
        return http.Response(
          jsonEncode(
            call.method == 'surfaceStatus' ? _statusView() : _history([1]),
          ),
          200,
        );
      }, calls: calls);
      final result = await connection.callTool(
        CallToolRequest(
          name: tool,
          arguments: {..._surface}..remove('surfaceType'),
        ),
      );
      return (result, calls);
    }

    for (final tool in ['restage_surface_status', 'restage_surface_history']) {
      test('$tool resolves a unique slug', () async {
        final (result, calls) = await call(tool, {
          'onboarding': ['first-run'],
          'paywall': ['pro'],
        });
        expect(result.isError, isNot(true), reason: _text(result));
        final read = calls.singleWhere((call) => call.method != 'list');
        expect(read.body['surfaceType'], 'onboarding');
      });
    }

    test('an ambiguous slug names the types', () async {
      final (result, calls) = await call('restage_surface_status', {
        'onboarding': ['first-run'],
        'survey': ['first-run'],
      });
      expect(result.isError, isTrue);
      expect(
        _text(result),
        'Surface "first-run" exists as more than one type: onboarding, '
        'survey. Pass surfaceType to choose one.',
      );
      expect(calls.where((call) => call.method != 'list'), isEmpty);
    });
  });

  test('manifest push runs the CLI push with the selectors given', () async {
    List<String>? ran;
    final connection = await connect(
      (_) async => http.Response('null', 200),
      cliRunner: (args, {required stdout, required stderr}) async {
        ran = args;
        stdout.writeln('Pushed onboarding "first-run" r4 to production.');
        return 0;
      },
    );

    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_push_surface',
        arguments: {
          'projectDirectory': tempDir.path,
          'surface': 'first-run',
          'projectSlug': 'demo',
          'appSlug': 'mobile',
          'environmentSlug': 'production',
          'runtimePlane': 'live',
          'recordGit': true,
          'build': true,
          'flutterRoot': '/opt/flutter',
          'declareAssets': true,
        },
      ),
    );

    expect(result.isError, isNot(true), reason: _text(result));
    expect(ran, [
      'surface',
      'push',
      'first-run',
      '-C',
      tempDir.path,
      '--project',
      'demo',
      '--app',
      'mobile',
      '--env',
      'production',
      '--plane',
      'live',
      '--build',
      '--flutter-root',
      '/opt/flutter',
      '--declare-assets',
      '--record-git',
    ]);
    expect(result.structuredContent!['output'], contains('r4'));
  });

  test('a failed CLI push is an error carrying its output', () async {
    var ran = 0;
    final connection = await connect(
      (_) async => http.Response('null', 200),
      cliRunner: (args, {required stdout, required stderr}) async {
        ran += 1;
        stderr.writeln('The generated surface is stale.');
        return 1;
      },
    );

    final failed = await connection.callTool(
      CallToolRequest(
        name: 'restage_push_surface',
        arguments: {
          'projectDirectory': tempDir.path,
          'surface': 'first-run',
          'projectSlug': 'demo',
          'appSlug': 'mobile',
          'environmentSlug': 'staging',
        },
      ),
    );
    expect(failed.isError, isTrue);
    expect(_text(failed), 'The generated surface is stale.');
    expect(ran, 1);
  });
}
