import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage_cli/api.dart';
import 'package:restage_cli/restage_cli.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    hide RuntimePlane;
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    as measurement
    show RuntimePlane;
import 'package:test/test.dart';

import '_support/harness.dart';

final _target = TargetCoordinate(
  organizationId: OrganizationId(11),
  appId: ApplicationId(23),
  environmentTargetId: EnvironmentTargetId(31),
  namedEnvironmentId: NamedEnvironmentId(37),
  runtimePlane: measurement.RuntimePlane.live,
);

const _windowStart = 1788000000000000;
const _windowEnd = 1788600000000000;

/// Each read's arguments beyond the target and window, on the tool and on
/// the command.
const _cases =
    <String, ({String tool, Map<String, Object?> args, List<String> flags})>{
      'analytics overview': (
        tool: 'restage_read_analytics_overview',
        args: {},
        flags: [],
      ),
      'analytics explore': (
        tool: 'restage_read_explore',
        args: {'dimension': 'platform'},
        flags: ['--dimension=platform'],
      ),
      'analytics surface': (
        tool: 'restage_read_surface_analytics',
        args: {
          'surfaceId': 'surface.v1.welcome',
          'surfaceRevisionIds': ['r1', 'r2'],
        },
        flags: ['--surface=surface.v1.welcome', '--version=r1', '--version=r2'],
      ),
      'analytics taps': (
        tool: 'restage_read_surface_taps',
        args: {'surfaceId': 'surface.v1.welcome', 'revisionOrdinal': 3},
        flags: ['--surface=surface.v1.welcome', '--version=3'],
      ),
      'analytics health': (
        tool: 'restage_read_data_health',
        args: {},
        flags: [],
      ),
      'experiment list': (
        tool: 'restage_read_experiments',
        args: {},
        flags: [],
      ),
      'experiment results': (
        tool: 'restage_read_experiment',
        args: {'experimentId': 'experiment.checkout'},
        flags: ['--experiment=experiment.checkout'],
      ),
      'delivery map': (
        tool: 'restage_read_delivery_map',
        args: {'allEnvironments': true, 'placement': 'named:home'},
        flags: ['--all-environments', '--placement=named:home'],
      ),
      'where': (
        tool: 'restage_where',
        args: {'surface': 'daily-check-in@2'},
        flags: ['daily-check-in@2'],
      ),
    };

const _directoryTarget = {
  'environmentTargetId': 31,
  'namedEnvironmentId': 37,
  'environmentSlug': 'production',
  'runtimePlane': 'live',
};

http.Response? _directory(String method) => switch (method) {
  'read' => http.Response(
    jsonEncode({
      'organizationId': 11,
      'session': {
        'memberships': [
          {
            'organizationId': 11,
            'slug': 'restage',
            'name': 'Restage',
            'role': 'owner',
          },
        ],
        'workspaceExperiences': <Object>[],
      },
      'projects': [
        {'id': 1, 'slug': 'checkout', 'name': 'Checkout'},
      ],
      'apps': [
        {'id': 23, 'projectId': 1, 'slug': 'app', 'name': 'App'},
      ],
      'environments': [
        {'id': 31, 'appId': 23, 'namedEnvironmentId': 37, 'slug': 'production'},
      ],
      'environmentTargets': [_directoryTarget],
      'surfaces': <Object>[],
    }),
    200,
  ),
  'listMine' => http.Response(
    jsonEncode([
      {'organizationId': 11, 'slug': 'restage', 'name': 'Restage'},
    ]),
    200,
  ),
  'listApps' => http.Response(
    jsonEncode([
      {'id': 23, 'slug': 'app', 'name': 'App'},
    ]),
    200,
  ),
  'listEnvironmentTargets' => http.Response(
    jsonEncode([_directoryTarget]),
    200,
  ),
  'resolveTarget' => http.Response(
    jsonEncode({
      'organizationId': 11,
      'organizationSlug': 'restage',
      'projectSlug': 'checkout',
      'appId': 23,
      'appSlug': 'app',
      'target': _directoryTarget,
    }),
    200,
  ),
  _ => null,
};

String _reply(TargetCoordinate target) => jsonEncode({
  'kind': 'served',
  'projections': [
    {
      'document': {'kind': 'page', 'figure': 12},
    },
  ],
  'schemaVersion': 1,
  'surfaceTypes': <Object?>[],
  'target': target.toJson(),
});

void main() {
  late Directory home;
  late Directory project;
  late FileCredentialStore store;
  late List<Map<String, Object?>> sent;

  setUp(() async {
    sent = [];
    home = Directory.systemTemp.createTempSync('restage_mcp_pages_home');
    project = Directory.systemTemp.createTempSync('restage_mcp_pages_project');
    store = FileCredentialStore('${home.path}/credentials');
    await store.write(
      const Credential(
        endpoint: 'http://localhost:8080/',
        kind: CredentialKind.authKey,
        authToken: 'keyId:key',
      ),
    );
    File('${project.path}/restage_config.yaml').writeAsStringSync(
      'project: checkout\n'
      'app: app\n'
      'defaultEnvironment: production\n'
      'organization: restage\n',
    );
  });

  tearDown(() {
    home.deleteSync(recursive: true);
    project.deleteSync(recursive: true);
  });

  http.Client route({TargetCoordinate? answersFor}) =>
      MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, Object?>;
        final method = body['method']! as String;
        final directory = _directory(method);
        if (directory != null) return directory;
        sent.add(body);
        return http.Response(jsonEncode(_reply(answersFor ?? _target)), 200);
      });

  Map<String, Object?> targetArguments() => {
    'organizationId': 11,
    'projectSlug': 'checkout',
    'appSlug': 'app',
    'environmentSlug': 'production',
    'environmentTargetId': 31,
    'runtimePlane': 'live',
  };

  Future<CallToolResult> callTool(
    String name,
    Map<String, Object?> arguments, {
    TargetCoordinate? answersFor,
    Map<String, String> environment = const {'RESTAGE_EXPERIMENTAL': '1'},
  }) async {
    final connection = await connectServer(
      store: store,
      httpClient: route(answersFor: answersFor),
      environment: environment,
    );
    return connection.callTool(
      CallToolRequest(name: name, arguments: arguments),
    );
  }

  Future<({int code, String out, String err})> runCli(
    List<String> arguments,
  ) async {
    final stdout = StringBuffer();
    final stderr = StringBuffer();
    final code =
        await RestageCli(
          stdout: stdout,
          stderr: stderr,
          credentialStore: store,
          httpClient: route(),
        ).run([
          '--non-interactive',
          '--yes',
          ...arguments,
          '--directory=${project.path}',
        ]);
    return (code: code, out: stdout.toString(), err: stderr.toString());
  }

  test('every read has a tool and a command', () {
    expect(
      {for (final read in pageReads) read.cliPath: read.mcpName},
      {for (final entry in _cases.entries) entry.key: entry.value.tool},
    );
  });

  group('the tool list', () {
    test('has every read without any host opt-in', () async {
      final connection = await connectServer(
        store: store,
        httpClient: route(),
        environment: const {},
      );
      final tools = await connection.listTools(ListToolsRequest());
      final names = tools.tools.map((tool) => tool.name);

      expect(names, containsAll(_cases.values.map((c) => c.tool)));
      expect(names, isNot(contains('restage_read_experiment_results')));
      expect(names, isNot(contains('restage_read_experiment_roster')));
    });

    test(
      'asks for an exact target and each read\'s required arguments',
      () async {
        final connection = await connectServer(
          store: store,
          httpClient: route(),
        );
        final tools = (await connection.listTools(ListToolsRequest())).tools;

        for (final read in pageReads) {
          final schema =
              tools.singleWhere((tool) => tool.name == read.mcpName).inputSchema
                  as Map<String, Object?>;
          expect(schema['additionalProperties'], isFalse, reason: read.mcpName);
          expect(
            schema['required'],
            containsAll(<String>[
              'organizationId',
              'projectSlug',
              'appSlug',
              'environmentSlug',
              'environmentTargetId',
              'runtimePlane',
              for (final param in read.params)
                if (param.required) param.key,
            ]),
            reason: read.mcpName,
          );
        }
      },
    );
  });

  group('each read', () {
    for (final entry in _cases.entries) {
      final read = pageReads.singleWhere((r) => r.cliPath == entry.key);

      test('${entry.value.tool} emits the reply the command emits', () async {
        final tool = await callTool(entry.value.tool, {
          ...targetArguments(),
          'windowStartMicros': _windowStart,
          'windowEndExclusiveMicros': _windowEnd,
          ...entry.value.args,
        });
        final toolRequest = sent.single;
        sent.clear();
        final cli = await runCli([
          ...entry.key.split(' '),
          ...entry.value.flags,
          '--from=${DateTime.fromMicrosecondsSinceEpoch(_windowStart, isUtc: true).toIso8601String()}',
          '--until=${DateTime.fromMicrosecondsSinceEpoch(_windowEnd, isUtc: true).toIso8601String()}',
          '--json',
        ]);

        expect(cli.code, 0, reason: cli.err);
        expect(tool.isError, isNot(true));
        final emitted = (tool.content.single as TextContent).text;
        expect(emitted, cli.out.trim());
        expect(emitted, _reply(_target));
        expect(sent.single, toolRequest, reason: 'one request on both paths');
        expect(toolRequest['method'], read.method);
      });
    }
  });

  test('allApps reads every app and matches the command', () async {
    final tool = await callTool('restage_read_analytics_overview', {
      ...targetArguments(),
      'allApps': true,
      'windowStartMicros': _windowStart,
      'windowEndExclusiveMicros': _windowEnd,
    });
    final toolRequest = sent.single;
    sent.clear();
    final cli = await runCli([
      'analytics',
      'overview',
      '--all-apps',
      '--from=${DateTime.fromMicrosecondsSinceEpoch(_windowStart, isUtc: true).toIso8601String()}',
      '--until=${DateTime.fromMicrosecondsSinceEpoch(_windowEnd, isUtc: true).toIso8601String()}',
      '--json',
    ]);

    expect(cli.code, 0, reason: cli.err);
    expect((tool.content.single as TextContent).text, cli.out.trim());
    expect(sent.single, toolRequest);
    expect(toolRequest['method'], 'readOverviewAppsPage');
    expect(toolRequest.containsKey('appId'), isFalse);
  });

  test(
    'allApps refuses a reply naming another app\'s own environment',
    () async {
      final other = TargetCoordinate(
        organizationId: OrganizationId(12),
        appId: ApplicationId(24),
        environmentTargetId: EnvironmentTargetId(32),
        namedEnvironmentId: NamedEnvironmentId(38),
        runtimePlane: measurement.RuntimePlane.live,
      );
      final tool = await callTool('restage_read_analytics_overview', {
        ...targetArguments(),
        'allApps': true,
        'windowStartMicros': _windowStart,
        'windowEndExclusiveMicros': _windowEnd,
      }, answersFor: other);

      expect(tool.isError, isTrue);
    },
  );

  group('a value the caller supplied', () {
    test('is named as the caller\'s own and reaches no route', () async {
      final tool = await callTool('restage_read_explore', {
        ...targetArguments(),
        'dimension': 'countrySurface',
      });

      expect(tool.isError, isTrue);
      expect((tool.content.single as TextContent).text, contains('dimension'));
      expect(sent, isEmpty);
    });

    test('a window that ends before it starts is refused', () async {
      final tool = await callTool('restage_read_data_health', {
        ...targetArguments(),
        'windowStartMicros': _windowEnd,
        'windowEndExclusiveMicros': _windowStart,
      });

      expect(tool.isError, isTrue);
      expect(sent, isEmpty);
    });
  });

  test('a reply for another target is refused', () async {
    final other = TargetCoordinate(
      organizationId: OrganizationId(12),
      appId: ApplicationId(23),
      environmentTargetId: EnvironmentTargetId(31),
      namedEnvironmentId: NamedEnvironmentId(37),
      runtimePlane: measurement.RuntimePlane.live,
    );
    final tool = await callTool('restage_read_data_health', {
      ...targetArguments(),
    }, answersFor: other);

    expect(tool.isError, isTrue);
  });
}
