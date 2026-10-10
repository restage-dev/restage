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

/// The one target every fixture in this file addresses.
final _target = TargetCoordinate(
  organizationId: OrganizationId(11),
  appId: ApplicationId(23),
  environmentTargetId: EnvironmentTargetId(31),
  namedEnvironmentId: NamedEnvironmentId(37),
  runtimePlane: measurement.RuntimePlane.live,
);

const _surfaceId = 'surface.v1.welcome';
const _revisionId = 'surface-revision.v1.welcome.3';
const _windowStart = 1788000000000000;
const _windowEnd = 1788600000000000;

/// One funnel reading, built through the contract's own constructors.
SurfaceFunnelViewV1 _view() => SurfaceFunnelViewV1.of(
  target: _target,
  surfaceId: _surfaceId,
  surfaceType: 'onboarding',
  windowStartMicros: _windowStart,
  windowEndExclusiveMicros: _windowEnd,
  asOfMicros: 1788600000000001,
  disclosureFloor: 5,
  versions: [
    SurfaceFunnelVersionV1.of(
      surfaceRevisionId: _revisionId,
      revisionOrdinal: 3,
      publishedAtMicros: 1787900000000000,
      status: SurfaceFunnelVersionStatusV1.available,
      disclosure: SurfaceFunnelDisclosureV1.disclosed,
      counts: SurfaceFunnelCountsV1.of(
        eligibleRoots: 5000,
        views: 5000,
        completions: 525,
        skips: 240,
        dismissals: 310,
        reachedAnotherStep: 4100,
        completeRoots: 4900,
        pendingRoots: 60,
        unavailableRoots: 40,
        path: 'counts',
      ),
      unattributedDismissals: 12,
      flowId: 'welcome',
      flowVersion: 3,
      flowContentHash: 'f' * 64,
      initialStateId: 'intro',
      stateTransitions: const {
        'intro': ['plan'],
        'plan': <String>[],
      },
      steps: [
        SurfaceFunnelStepV1.of(
          stateId: 'intro',
          screenArtifactId: 'intro-screen',
          screenContentHash: 'a' * 64,
          screenVersion: 3,
          disclosure: SurfaceFunnelDisclosureV1.disclosed,
          counts: SurfaceFunnelCountsV1.of(
            eligibleRoots: 5000,
            views: 4900,
            completions: 0,
            skips: 100,
            dismissals: 180,
            reachedAnotherStep: 4100,
            completeRoots: 4900,
            pendingRoots: 60,
            unavailableRoots: 40,
            path: 'counts',
          ),
          transitionTargets: const ['plan'],
          path: 'step',
        ),
      ],
      bands: [
        SurfaceFunnelBandV1.of(
          point: MeasurementBreakdownPointV1(
            kindV1: MeasurementBreakdownPointKindV1.pageIndex,
            reference: '0',
            label: 'Intro',
            authoredOrder: 0,
          ),
          disclosure: SurfaceFunnelDisclosureV1.disclosed,
          counts: SurfaceFunnelBandCountsV1.of(
            eligibleRoots: 5000,
            reach: 4900,
            occurrences: 5100,
            continued: 4100,
            completeRoots: 4900,
            pendingRoots: 60,
            unavailableRoots: 40,
            path: 'band',
          ),
          path: 'band',
        ),
      ],
      path: 'version',
    ),
  ],
);

http.Response? _directory(String method) => switch (method) {
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

const _directoryTarget = {
  'environmentTargetId': 31,
  'namedEnvironmentId': 37,
  'environmentSlug': 'production',
  'runtimePlane': 'live',
};

String _wire(List<int> bytes) => "decode('${base64Encode(bytes)}', 'base64')";

typedef _Reply = Object? Function(Map<String, Object?> arguments);

/// A fake route that answers the funnel read with [reply].
http.Client _route(_Reply reply) => MockClient((request) async {
  final body = jsonDecode(request.body) as Map<String, Object?>;
  final method = body['method']! as String;
  final directory = _directory(method);
  if (directory != null) return directory;
  if (method != 'readSurfaceFunnel') {
    fail('The funnel route was reached with $method.');
  }
  final answer = reply(body);
  if (answer is int) return http.Response('', answer);
  return http.Response(jsonEncode(answer), 200);
});

/// A route that fails the test if the funnel read reaches it.
http.Client _unreachableRoute() => MockClient((request) async {
  final body = jsonDecode(request.body) as Map<String, Object?>;
  final method = body['method']! as String;
  final directory = _directory(method);
  if (directory != null) return directory;
  fail('The funnel route was reached with $method.');
});

Object? _acceptedReply(Map<String, Object?> arguments) =>
    _wire(_view().canonicalBytes);

void main() {
  late Directory home;
  late Directory project;
  late FileCredentialStore store;
  late List<Map<String, Object?>> sent;

  setUp(() async {
    sent = [];
    home = Directory.systemTemp.createTempSync('restage_mcp_funnel_home');
    project = Directory.systemTemp.createTempSync('restage_mcp_funnel_project');
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

  Map<String, Object?> targetArguments() => {
    'organizationId': 11,
    'projectSlug': 'checkout',
    'appSlug': 'app',
    'environmentSlug': 'production',
    'environmentTargetId': 31,
    'runtimePlane': 'live',
  };

  Map<String, Object?> readArguments() => {
    ...targetArguments(),
    'surfaceId': _surfaceId,
    'windowStartMicros': _windowStart,
    'windowEndExclusiveMicros': _windowEnd,
  };

  _Reply recording(_Reply inner) => (arguments) {
    sent.add(arguments);
    return inner(arguments);
  };

  Future<CallToolResult> callTool(
    Map<String, Object?> arguments, {
    _Reply reply = _acceptedReply,
  }) async {
    final connection = await connectServer(
      store: store,
      httpClient: _route(recording(reply)),
    );
    return connection.callTool(
      CallToolRequest(
        name: 'restage_read_surface_funnel',
        arguments: arguments,
      ),
    );
  }

  /// Runs `restage surface results <arguments>` against the same fake route.
  Future<({int code, String out, String err})> runCli(
    List<String> arguments, {
    _Reply reply = _acceptedReply,
  }) async {
    final stdout = StringBuffer();
    final stderr = StringBuffer();
    final code =
        await RestageCli(
          stdout: stdout,
          stderr: stderr,
          credentialStore: store,
          httpClient: _route(recording(reply)),
        ).run([
          '--non-interactive',
          '--yes',
          'surface',
          'results',
          ...arguments,
          '--directory=${project.path}',
        ]);
    return (code: code, out: stdout.toString(), err: stderr.toString());
  }

  List<String> cliWindow() => [
    _surfaceId,
    '--from=${DateTime.fromMicrosecondsSinceEpoch(_windowStart, isUtc: true).toIso8601String()}',
    '--until=${DateTime.fromMicrosecondsSinceEpoch(_windowEnd, isUtc: true).toIso8601String()}',
  ];

  group('the tool schema', () {
    test('asks for an exact target and refuses unknown properties', () async {
      final connection = await connectServer(
        store: store,
        httpClient: _route(_acceptedReply),
      );
      final tools = await connection.listTools(ListToolsRequest());

      final schema =
          tools.tools
                  .singleWhere(
                    (tool) => tool.name == 'restage_read_surface_funnel',
                  )
                  .inputSchema
              as Map<String, Object?>;
      expect(schema['additionalProperties'], isFalse);
      expect(
        schema['required'],
        containsAll(<String>[
          'organizationId',
          'projectSlug',
          'appSlug',
          'environmentSlug',
          'environmentTargetId',
          'runtimePlane',
          'surfaceId',
          'windowStartMicros',
          'windowEndExclusiveMicros',
        ]),
      );
    });

    test('is registered without any host opt-in', () async {
      final connection = await connectServer(
        store: store,
        httpClient: _route(_acceptedReply),
        environment: const {},
      );
      final tools = await connection.listTools(ListToolsRequest());

      expect(
        tools.tools.map((tool) => tool.name),
        contains('restage_read_surface_funnel'),
      );
    });
  });

  group('a value the caller supplied', () {
    test("is named as the caller's own, and reaches no route", () async {
      final connection = await connectServer(
        store: store,
        httpClient: _unreachableRoute(),
      );

      final tool = await connection.callTool(
        CallToolRequest(
          name: 'restage_read_surface_funnel',
          arguments: {
            ...readArguments(),
            'windowEndExclusiveMicros': _windowStart,
          },
        ),
      );

      expect(tool.isError, isTrue);
      final text = (tool.content.single as TextContent).text;
      expect(text, contains('windowEndExclusiveMicros'));
      expect(text, isNot(contains('service')));
    });

    test('is refused at the version bound before any read', () async {
      final connection = await connectServer(
        store: store,
        httpClient: _unreachableRoute(),
      );

      final tool = await connection.callTool(
        CallToolRequest(
          name: 'restage_read_surface_funnel',
          arguments: {
            ...readArguments(),
            'surfaceRevisionIds': [_revisionId, _revisionId],
          },
        ),
      );

      expect(tool.isError, isTrue);
      final text = (tool.content.single as TextContent).text;
      expect(text, contains('surfaceRevisionIds'));
      expect(text, isNot(contains('service')));
    });

    test('is named by the command before the read opens', () async {
      final cli = await runCli([
        _surfaceId,
        '--from=2026-09-02T00:00:00Z',
        '--until=2026-09-01T00:00:00Z',
      ], reply: (arguments) => fail('The funnel route was reached.'));

      expect(cli.code, 1);
      expect(cli.err, contains('windowEndExclusiveMicros'));
    });
  });

  group('the funnel read', () {
    test('emits the exact reading the command emits', () async {
      final tool = await callTool(readArguments());
      final cli = await runCli([...cliWindow(), '--json']);

      expect(cli.code, 0, reason: cli.err);
      expect(tool.isError, isNot(true));
      // The one reuse contract, over what each surface actually wrote. The two
      // differ only in how they lay JSON out, so each emitted text is read back
      // through the contract and the canonical bytes are compared.
      final emitted = (tool.content.single as TextContent).text;
      final byTool = SurfaceFunnelViewV1.fromJson(
        jsonDecode(emitted) as Map<String, Object?>,
      );
      final byCommand = SurfaceFunnelViewV1.fromJson(
        jsonDecode(cli.out) as Map<String, Object?>,
      );
      expect(byTool.canonicalBytes, byCommand.canonicalBytes);
      // The tool's two channels agree, so a reader of either sees one answer.
      expect(
        jsonEncode(tool.structuredContent),
        jsonEncode(jsonDecode(emitted)),
      );
    });

    test('keeps every decimal beside the exact pair it came from', () async {
      final tool = await callTool(readArguments());

      final version =
          (tool.structuredContent!['versions']! as List<Object?>).single!
              as Map<String, Object?>;
      final counts = version['counts']! as Map<String, Object?>;
      final conversion = counts['conversionRate']! as Map<String, Object?>;
      expect(conversion['decimal'], '0.105000000');
      expect(conversion['numerator'], 525);
      expect(conversion['denominator'], 5000);
      expect(conversion['exact'], {'denominator': '200', 'numerator': '21'});

      final band =
          (version['bands']! as List<Object?>).single! as Map<String, Object?>;
      final dropOff =
          (band['counts']! as Map<String, Object?>)['dropOffRate']!
              as Map<String, Object?>;
      expect(dropOff['numerator'], 800);
      expect(dropOff['denominator'], 4900);
      expect(dropOff['decimal'], '0.163265306');
    });

    test('addresses the target and window the caller named', () async {
      await callTool({
        ...readArguments(),
        'surfaceRevisionIds': [_revisionId],
      });

      final request = sent.last;
      expect(request['organizationId'], 11);
      expect(request['appId'], 23);
      expect(request['environmentTargetId'], 31);
      expect(request['namedEnvironmentId'], 37);
      expect(request['runtimePlane'], 'live');
      expect(request['surfaceId'], _surfaceId);
      expect(request['windowStartMicros'], _windowStart);
      expect(request['windowEndExclusiveMicros'], _windowEnd);
      expect(request['surfaceRevisionIds'], [_revisionId]);
    });

    test('refuses a reading bound to another surface', () async {
      final wrong = SurfaceFunnelViewV1.of(
        target: _target,
        surfaceId: 'surface.v1.other',
        windowStartMicros: _windowStart,
        windowEndExclusiveMicros: _windowEnd,
        asOfMicros: _windowEnd + 1,
        disclosureFloor: 5,
        versions: const [],
      );
      final tool = await callTool(
        readArguments(),
        reply: (arguments) => _wire(wrong.canonicalBytes),
      );

      expect(tool.isError, isTrue);
      expect(
        (tool.content.single as TextContent).text,
        contains('invalid funnel reading'),
      );
    });

    test('prints a human summary without --json', () async {
      final cli = await runCli(cliWindow());

      expect(cli.code, 0, reason: cli.err);
      expect(cli.out, contains('Funnel for $_surfaceId (onboarding)'));
      expect(cli.out, contains('views 5000 of 5000'));
      expect(cli.out, contains('conversion 0.105000000 (525/5000)'));
      expect(cli.out, contains('Intro: reach 4900 of 5000'));
      expect(cli.out, contains('drop-off 0.163265306 (800/4900)'));
    });
  });
}
