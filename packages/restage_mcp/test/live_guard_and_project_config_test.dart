import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/api.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    as measurement;
import 'package:test/test.dart';

import '_support/fake_backend.dart';
import '_support/delivery_fixtures.dart' show policyReview, surfaceScope;
import '_support/harness.dart';

const _surface = <String, Object?>{
  'projectSlug': 'demo',
  'appSlug': 'mobile',
  'surfaceType': 'onboarding',
  'surfaceSlug': 'first-run',
};

const _liveRefusal =
    'This changes what a live target serves. Ask the user to approve the '
    'change, then call again with confirmLive: true.';

String _text(CallToolResult result) =>
    (result.content.single as TextContent).text;

http.Response _identityResult() => http.Response(
  jsonEncode({
    'surfaceType': 'onboarding',
    'surfaceSlug': 'first-run',
    'frozen': false,
    'affectedFamilies': <Object>[],
  }),
  200,
);

void main() {
  late Directory tempDir;
  late FileCredentialStore store;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('restage_mcp_live_guard');
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
    List<BackendCall> calls,
    Future<http.Response> Function(BackendCall call) handler, {
    String appSlug = 'mobile',
  }) => connectServer(
    store: store,
    httpClient: fakeBackend(handler, calls: calls, appSlug: appSlug),
  );

  List<String> changes(List<BackendCall> calls) => [
    for (final call in calls)
      if (call.endpoint == 'surface' && call.method != 'reviewDeliveryImpact')
        call.method,
  ];

  group('a live target', () {
    test('refuses every surface change without confirmLive', () async {
      final calls = <BackendCall>[];
      final connection = await connect(calls, (_) async => _identityResult());
      for (final (tool, extra) in [
        ('restage_kill_surface', <String, Object?>{'reason': 'broken'}),
        ('restage_freeze_surface', <String, Object?>{'reason': 'hold'}),
        ('restage_unfreeze_surface', <String, Object?>{'reason': 'resume'}),
        (
          'restage_rollback_surface',
          <String, Object?>{'reason': 'bad copy', 'toVersion': 1},
        ),
        ('restage_publish_surface', <String, Object?>{'reason': 'ship'}),
      ]) {
        final result = await connection.callTool(
          CallToolRequest(
            name: tool,
            arguments: {
              ..._surface,
              'environmentSlug': 'production',
              'runtimePlane': 'live',
              ...extra,
            },
          ),
        );
        expect(result.isError, isTrue, reason: tool);
        expect(_text(result), _liveRefusal, reason: tool);
      }
      expect(changes(calls), isEmpty);
    });

    test('resolves an unnamed plane before refusing', () async {
      final calls = <BackendCall>[];
      final connection = await connect(calls, (_) async => _identityResult());

      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_kill_surface',
          arguments: {
            ..._surface,
            'environmentSlug': 'production',
            'environmentTargetId': 44,
            'reason': 'broken',
          },
        ),
      );

      expect(_text(result), _liveRefusal);
      expect(calls.map((call) => call.method), ['resolveTarget']);
    });

    test('changes with confirmLive: true', () async {
      final calls = <BackendCall>[];
      final connection = await connect(calls, (_) async => _identityResult());

      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_kill_surface',
          arguments: {
            ..._surface,
            'environmentSlug': 'production',
            'runtimePlane': 'live',
            'reason': 'broken',
            'confirmLive': true,
          },
        ),
      );

      expect(result.isError, isNot(true), reason: _text(result));
      expect(changes(calls), ['killSurface']);
    });

    test('publish needs a written reason even with confirmLive', () async {
      final calls = <BackendCall>[];
      final connection = await connect(calls, (_) async => _identityResult());

      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_publish_surface',
          arguments: {
            ..._surface,
            'environmentSlug': 'production',
            'runtimePlane': 'live',
            'confirmLive': true,
          },
        ),
      );

      expect(result.isError, isTrue);
      expect(_text(result), contains('A live change needs a reason'));
      expect(changes(calls), isEmpty);
    });

    test('refuses a routing publish at a live target id', () async {
      final calls = <BackendCall>[];
      final connection = await connect(calls, (_) async => _identityResult());

      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_publish_routing',
          arguments: {
            ..._surface,
            'organizationId': 7,
            'environmentSlug': 'production',
            'environmentTargetId': 44,
            'reviewBase64': base64Encode(
              policyReview(surfaceScope(live: true)).canonicalBytes,
            ),
          },
        ),
      );

      expect(_text(result), _liveRefusal);
      expect(
        calls.map((call) => call.method),
        isNot(contains('publishRouting')),
      );
    });
  });

  test('a sandbox target changes without confirmLive', () async {
    final calls = <BackendCall>[];
    final connection = await connect(calls, (_) async => _identityResult());

    final result = await connection.callTool(
      CallToolRequest(
        name: 'restage_freeze_surface',
        arguments: {
          ..._surface,
          'environmentSlug': 'production',
          'runtimePlane': 'sandbox',
          'reason': 'hold',
        },
      ),
    );

    expect(result.isError, isNot(true), reason: _text(result));
    expect(changes(calls), ['setSurfaceLock']);
  });

  group('experiment changes', () {
    Map<String, Object?> exactTarget(String plane) => {
      'organizationId': 7,
      'projectSlug': 'demo',
      'appSlug': 'mobile',
      'environmentSlug': 'production',
      'environmentTargetId': plane == 'live' ? 44 : 43,
      'runtimePlane': plane,
    };

    test('a full serving-record rebuild on live needs confirmLive; the '
        'readiness read does not', () async {
      final calls = <BackendCall>[];
      final connection = await connect(
        calls,
        (_) async => http.Response(
          jsonEncode(
            jsonEncode({'produced': 0, 'missing': 0, 'sourcesReproven': true}),
          ),
          200,
        ),
      );

      final rebuild = await connection.callTool(
        CallToolRequest(
          name: 'restage_rebuild_serving_records',
          arguments: exactTarget('live'),
        ),
      );
      expect(_text(rebuild), _liveRefusal);
      expect(
        calls.map((call) => call.method),
        isNot(contains('rebuildServingRecords')),
      );

      final readiness = await connection.callTool(
        CallToolRequest(
          name: 'restage_rebuild_serving_records',
          arguments: {...exactTarget('live'), 'readinessOnly': true},
        ),
      );
      expect(readiness.isError, isNot(true), reason: _text(readiness));
      expect(
        calls.map((call) => call.method),
        contains('rebuildServingRecords'),
      );
    });

    test('an activation command for a live target needs confirmLive', () async {
      var executed = 0;
      final connection = await connectServer(
        store: store,
        httpClient: fakeBackend((_) async => _identityResult()),
        experimentActivationApi: ExperimentActivationApi(
          transport: (bytes) async {
            executed++;
            return bytes;
          },
        ),
      );
      String command(measurement.RuntimePlane plane) => base64Encode(
        measurement.CanonicalJsonCodec.encode({
          'target': measurement.TargetCoordinate(
            organizationId: measurement.OrganizationId(7),
            appId: measurement.ApplicationId(11),
            environmentTargetId: measurement.EnvironmentTargetId(44),
            namedEnvironmentId: measurement.NamedEnvironmentId(440),
            runtimePlane: plane,
          ).toJson(),
        }),
      );

      final live = await connection.callTool(
        CallToolRequest(
          name: 'restage_activate_experiment',
          arguments: {
            'canonicalCommandBase64': command(measurement.RuntimePlane.live),
          },
        ),
      );
      expect(_text(live), _liveRefusal);
      expect(executed, 0);

      await connection.callTool(
        CallToolRequest(
          name: 'restage_activate_experiment',
          arguments: {
            'canonicalCommandBase64': command(measurement.RuntimePlane.sandbox),
          },
        ),
      );
      expect(executed, 1);
    });
  });

  group('projectDirectory', () {
    Directory project(String config) {
      final directory = Directory('${tempDir.path}/app')..createSync();
      File('${directory.path}/restage_config.yaml').writeAsStringSync(config);
      return directory;
    }

    test('fills every missing selector from restage_config.yaml', () async {
      final directory = project(
        'project: demo\n'
        'app: mobile\n'
        'defaultEnvironment: production\n'
        'organization: acme\n'
        'plane: sandbox\n',
      );
      final calls = <BackendCall>[];
      final connection = await connect(
        calls,
        (_) async => http.Response(
          jsonEncode({
            'surfaceType': 'onboarding',
            'surfaceSlug': 'first-run',
            'environmentSlug': 'production',
            'locked': false,
            'deliveryShape': 'blob',
            'versions': <Object>[],
          }),
          200,
        ),
      );

      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_surface_status',
          arguments: {
            'projectDirectory': directory.path,
            'surfaceType': 'onboarding',
            'surfaceSlug': 'first-run',
          },
        ),
      );

      expect(result.isError, isNot(true), reason: _text(result));
      final status = calls.singleWhere(
        (call) => call.method == 'surfaceStatus',
      );
      expect(status.body['projectSlug'], 'demo');
      expect(status.body['appSlug'], 'mobile');
      expect(status.body['environmentSlug'], 'production');
      expect(status.body['runtimePlane'], 'sandbox');
      expect(status.body['organizationId'], 7);
    });

    test('an argument overrides the config', () async {
      final directory = project('project: demo\napp: mobile\n');
      final calls = <BackendCall>[];
      final connection = await connect(
        calls,
        (_) async => _identityResult(),
        appSlug: 'tablet',
      );

      await connection.callTool(
        CallToolRequest(
          name: 'restage_freeze_surface',
          arguments: {
            'projectDirectory': directory.path,
            'appSlug': 'tablet',
            'surfaceType': 'onboarding',
            'surfaceSlug': 'first-run',
            'environmentSlug': 'staging',
            'reason': 'hold',
          },
        ),
      );

      final lock = calls.singleWhere((call) => call.method == 'setSurfaceLock');
      expect(lock.body['projectSlug'], 'demo');
      expect(lock.body['appSlug'], 'tablet');
    });

    test('a missing selector names both ways to supply it', () async {
      final calls = <BackendCall>[];
      final connection = await connect(calls, (_) async => _identityResult());

      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_surface_status',
          arguments: {
            'appSlug': 'mobile',
            'surfaceType': 'onboarding',
            'surfaceSlug': 'first-run',
            'environmentSlug': 'staging',
          },
        ),
      );

      expect(result.isError, isTrue);
      expect(
        _text(result),
        'Missing projectSlug: pass it, or pass projectDirectory with a '
        'restage_config.yaml that sets it.',
      );
      expect(calls, isEmpty);
    });

    test('a directory with no config is refused', () async {
      final calls = <BackendCall>[];
      final connection = await connect(calls, (_) async => _identityResult());
      final empty = Directory('${tempDir.path}/empty')..createSync();

      final result = await connection.callTool(
        CallToolRequest(
          name: 'restage_surface_history',
          arguments: {
            'projectDirectory': empty.path,
            'surfaceType': 'onboarding',
            'surfaceSlug': 'first-run',
          },
        ),
      );

      expect(result.isError, isTrue);
      expect(_text(result), contains('No restage_config.yaml found'));
      expect(calls, isEmpty);
    });
  });
}
