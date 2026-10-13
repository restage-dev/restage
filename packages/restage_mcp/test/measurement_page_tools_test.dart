import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage_cli/api.dart';
import 'package:restage_cli/restage_cli.dart';
import 'package:restage_cli/src/tui/console_command_executor.dart';
import 'package:restage_cli/src/tui/console_models.dart';
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
const _context = ConsoleContext(
  organizationSlug: 'restage',
  project: 'checkout',
  appId: 23,
  app: 'app',
  environmentTargetId: 31,
  namedEnvironmentId: 37,
  environment: 'production',
  runtimePlane: RuntimePlane.live,
);
const _targetFlags = [
  '--organization=restage',
  '--project=checkout',
  '--app=app',
  '--env=production',
  '--plane=live',
];
final _windowFlags = [
  '--from=${DateTime.fromMicrosecondsSinceEpoch(_windowStart, isUtc: true).toIso8601String()}',
  '--until=${DateTime.fromMicrosecondsSinceEpoch(_windowEnd, isUtc: true).toIso8601String()}',
];

/// Each read's arguments beyond the target and window, on the tool and on
/// the command.
const _cases =
    <String, ({String tool, Map<String, Object?> args, List<String> flags})>{
      'analytics overview': (
        tool: 'restage_read_analytics_overview',
        args: {'granularity': 'week'},
        flags: ['--granularity=week'],
      ),
      'analytics explore': (
        tool: 'restage_read_explore',
        args: {
          'dimension': 'countryPlatform',
          'surfaceId': 'surface.v1.welcome',
          'granularity': 'month',
        },
        flags: [
          '--dimension=countryPlatform',
          '--surface=surface.v1.welcome',
          '--granularity=month',
        ],
      ),
      'analytics surface': (
        tool: 'restage_read_surface_analytics',
        args: {
          'surfaceId': 'surface.v1.welcome',
          'surfaceRevisionIds': ['r1', 'r2'],
          'granularity': 'week',
        },
        flags: [
          '--surface=surface.v1.welcome',
          '--version=r1',
          '--version=r2',
          '--granularity=week',
        ],
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
        args: {
          'allEnvironments': true,
          'placement': 'named:home',
          'surfaceSlug': 'daily-check-in',
        },
        flags: [
          '--all-environments',
          '--placement=named:home',
          '--surface=daily-check-in',
          '--by=surface',
        ],
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
      'project: configured-project\n'
      'app: configured-app\n'
      'defaultEnvironment: development\n'
      'organization: configured-organization\n'
      'organizationId: 41\n'
      'environmentTargetId: 61\n'
      'plane: sandbox\n',
    );
  });

  tearDown(() {
    home.deleteSync(recursive: true);
    project.deleteSync(recursive: true);
  });

  http.Client route({TargetCoordinate? answersFor, String? reply}) =>
      MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, Object?>;
        final method = body['method']! as String;
        if (method == 'resolveTarget') {
          expect(body['projectSlug'], 'checkout');
          expect(body['appSlug'], 'app');
          expect(body['environmentSlug'], 'production');
          expect(body['runtimePlane'], 'live');
          if (body['organizationId'] case final int id) {
            expect(id, 11);
          } else {
            expect(body['organizationSlug'], 'restage');
          }
          if (body['environmentTargetId'] case final int id) {
            expect(id, 31);
          }
        }
        final directory = _directory(method);
        if (directory != null) return directory;
        sent.add(body);
        return http.Response(
          jsonEncode(reply ?? _reply(answersFor ?? _target)),
          200,
        );
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
    String? reply,
    Map<String, String> environment = const {},
  }) async {
    final connection = await connectServer(
      store: store,
      httpClient: route(answersFor: answersFor, reply: reply),
      environment: environment,
    );
    return connection.callTool(
      CallToolRequest(name: name, arguments: arguments),
    );
  }

  Future<({int code, String out, String err})> runCli(
    List<String> arguments, {
    TargetCoordinate? answersFor,
    String? reply,
  }) async {
    final stdout = StringBuffer();
    final stderr = StringBuffer();
    final code =
        await RestageCli(
          stdout: stdout,
          stderr: stderr,
          credentialStore: store,
          httpClient: route(answersFor: answersFor, reply: reply),
        ).run([
          '--non-interactive',
          '--yes',
          ...arguments,
          ..._targetFlags,
          '--directory=${project.path}',
        ]);
    return (code: code, out: stdout.toString(), err: stderr.toString());
  }

  Future<ConsoleOperationResult> runConsole(
    List<String> arguments, {
    TargetCoordinate? answersFor,
    String? reply,
  }) => ConsoleCommandExecutor(
    credentialStore: store,
    httpClient: route(answersFor: answersFor, reply: reply),
    directory: project,
  ).runCommand(arguments, context: _context);

  Future<Map<String, Object?>> expectParity(
    String path, {
    Map<String, Object?> extraArgs = const {},
    List<String> extraFlags = const [],
    bool withWindow = true,
    String? reply,
  }) async {
    final fixture = _cases[path]!;
    final tool = await callTool(fixture.tool, {
      ...targetArguments(),
      if (withWindow) ...{
        'windowStartMicros': _windowStart,
        'windowEndExclusiveMicros': _windowEnd,
      },
      ...fixture.args,
      ...extraArgs,
    }, reply: reply);
    final toolRequest = sent.single;
    sent.clear();
    final arguments = [
      ...path.split(' '),
      ...fixture.flags,
      ...extraFlags,
      if (withWindow) ..._windowFlags,
      '--json',
    ];
    final cli = await runCli(arguments, reply: reply);
    expect(cli.code, 0, reason: cli.err);
    expect(sent.single, toolRequest, reason: 'CLI request');
    sent.clear();
    final console = await runConsole(arguments, reply: reply);

    expect(console.exitCode, 0, reason: console.stderr);
    expect(tool.isError, isNot(true));
    final emitted = (tool.content.single as TextContent).text;
    expect(emitted, reply ?? _reply(_target));
    expect(cli.out.trim(), emitted);
    expect(console.stdout.trim(), emitted);
    expect(console.stderr, cli.err);
    expect(sent.single, toolRequest, reason: 'TUI request');
    return toolRequest;
  }

  Future<void> expectMismatchParity(String path, {bool allApps = false}) async {
    final fixture = _cases[path]!;
    final other = TargetCoordinate(
      organizationId: OrganizationId(12),
      appId: ApplicationId(24),
      environmentTargetId: EnvironmentTargetId(32),
      namedEnvironmentId: NamedEnvironmentId(38),
      runtimePlane: measurement.RuntimePlane.sandbox,
    );
    final tool = await callTool(fixture.tool, {
      ...targetArguments(),
      'windowStartMicros': _windowStart,
      'windowEndExclusiveMicros': _windowEnd,
      ...fixture.args,
      if (allApps) 'allApps': true,
    }, answersFor: other);
    final toolRequest = sent.single;
    sent.clear();
    final arguments = [
      ...path.split(' '),
      ...fixture.flags,
      if (allApps) '--all-apps',
      ..._windowFlags,
      '--json',
    ];
    final cli = await runCli(arguments, answersFor: other);
    expect(sent.single, toolRequest);
    sent.clear();
    final console = await runConsole(arguments, answersFor: other);

    expect(tool.isError, isTrue);
    expect(cli.code, 2);
    expect(console.exitCode, cli.code);
    expect(cli.out, isEmpty);
    expect(console.stdout, isEmpty);
    expect(console.stderr, cli.err);
    expect((tool.content.single as TextContent).text, cli.err.trim());
    expect(sent.single, toolRequest);
  }

  test('every read and option has a CLI, TUI and tool parity case', () {
    expect(
      {for (final read in pageReads) read.cliPath: read.mcpName},
      {for (final entry in _cases.entries) entry.key: entry.value.tool},
    );
    for (final read in pageReads) {
      final fixture = _cases[read.cliPath]!;
      for (final param in read.params) {
        if (param.key == 'allApps') continue;
        if (!param.cliOnly) {
          expect(fixture.args, contains(param.key), reason: read.cliPath);
        }
        if (!param.positional) {
          expect(
            fixture.flags.any(
              (flag) =>
                  flag == '--${param.cli}' ||
                  flag.startsWith('--${param.cli}='),
            ),
            isTrue,
            reason: '${read.cliPath} --${param.cli}',
          );
        }
      }
    }
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

      test('${entry.value.tool} matches CLI and selected TUI target', () async {
        final request = await expectParity(entry.key);
        expect(request['method'], read.method);
        expect(request['organizationId'], 11);
        expect(request['appId'], 23);
        expect(request['environmentTargetId'], 31);
        expect(request['namedEnvironmentId'], 37);
        expect(request['runtimePlane'], 'live');
      });

      test('${entry.value.tool} preserves a typed refusal', () async {
        await expectParity(
          entry.key,
          reply: jsonEncode({
            'kind': 'refused',
            'reason': 'notServed',
            'detail': 'Nothing yet.',
            'schemaVersion': 1,
            'target': _target.toJson(),
          }),
        );
      });

      test('${entry.value.tool} preserves an unavailable figure', () async {
        await expectParity(
          entry.key,
          reply: jsonEncode({
            'kind': 'served',
            'projections': [
              {
                'document': {
                  'kind': 'page',
                  'figure': {
                    'kind': 'unavailable',
                    'reason': 'currencyRateUnavailable',
                  },
                },
              },
            ],
            'schemaVersion': 1,
            'surfaceTypes': <Object?>[],
            'target': _target.toJson(),
          }),
        );
      });

      test('${entry.value.tool} refuses a reply for another target', () async {
        await expectMismatchParity(entry.key);
      });
    }
  });

  test('allApps reads every app and matches CLI and TUI', () async {
    final request = await expectParity(
      'analytics overview',
      extraArgs: {'allApps': true},
      extraFlags: ['--all-apps'],
    );

    expect(request['method'], 'readOverviewAppsPage');
    expect(request.containsKey('appId'), isFalse);
    expect(request.containsKey('environmentTargetId'), isFalse);
    expect(request['organizationId'], 11);
    expect(request['namedEnvironmentId'], 37);
    expect(request['runtimePlane'], 'live');
    expect(request['granularity'], 'week');
  });

  test('experiment results can read the whole run on all paths', () async {
    final request = await expectParity('experiment results', withWindow: false);

    expect(request.containsKey('windowStartMicros'), isFalse);
    expect(request.containsKey('windowEndExclusiveMicros'), isFalse);
  });

  test(
    'allApps refuses a reply naming another app\'s own environment',
    () async {
      await expectMismatchParity('analytics overview', allApps: true);
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
      final cli = await runCli([
        'analytics',
        'explore',
        '--dimension=countrySurface',
      ]);
      final console = await runConsole([
        'analytics',
        'explore',
        '--dimension=countrySurface',
      ]);
      expect(cli.code, isNonZero);
      expect(console.exitCode, cli.code);
      expect(console.stderr, cli.err);
      expect(cli.err, contains('dimension'));
      expect(sent, isEmpty);
    });

    test('a window that ends before it starts is refused', () async {
      final tool = await callTool('restage_read_data_health', {
        ...targetArguments(),
        'windowStartMicros': _windowEnd,
        'windowEndExclusiveMicros': _windowStart,
      });

      expect(tool.isError, isTrue);
      final arguments = [
        'analytics',
        'health',
        '--from=${DateTime.fromMicrosecondsSinceEpoch(_windowEnd, isUtc: true).toIso8601String()}',
        '--until=${DateTime.fromMicrosecondsSinceEpoch(_windowStart, isUtc: true).toIso8601String()}',
      ];
      final cli = await runCli(arguments);
      final console = await runConsole(arguments);
      expect(cli.code, isNonZero);
      expect(console.exitCode, cli.code);
      expect(console.stderr, cli.err);
      expect((tool.content.single as TextContent).text, cli.err.trim());
      expect(sent, isEmpty);
    });
  });
}
