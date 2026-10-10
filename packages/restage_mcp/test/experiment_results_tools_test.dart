import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

const _resultDigest =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _receiptDigest =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
const _draftDigest =
    'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';

const _experimentId = 'experiment.checkout';
const _activationOrdinal = 7;

/// The nine-place decimals and the exact pair beside every figure.
const _armResults = <Map<String, Object?>>[
  {
    'admittedCount': 5000,
    'effect': '0.000000000',
    'effectExact': {'denominator': '1', 'numerator': '0'},
    'interval': {
      'lower': '0.000000000',
      'lowerExact': {'denominator': '1', 'numerator': '0'},
      'upper': '0.000000000',
      'upperExact': {'denominator': '1', 'numerator': '0'},
    },
    'kind': 'experimentArmResult',
    'observedCount': 5000,
    'rate': '0.100000000',
    'rateExact': {'denominator': '10', 'numerator': '1'},
    'stableArmId': 'arm.control',
    'successCount': 500,
  },
  {
    'admittedCount': 5000,
    'effect': '0.005000000',
    'effectExact': {'denominator': '200', 'numerator': '1'},
    'interval': {
      'lower': '-0.000976563',
      'lowerExact': {'denominator': '1024', 'numerator': '-1'},
      'upper': '0.008789063',
      'upperExact': {'denominator': '1024', 'numerator': '9'},
    },
    'kind': 'experimentArmResult',
    'observedCount': 5000,
    'rate': '0.105000000',
    'rateExact': {'denominator': '200', 'numerator': '21'},
    'stableArmId': 'arm.variant',
    'successCount': 525,
  },
];

/// Canonical bytes of one accepted, evaluated result, built by the codec.
Uint8List _resultsAccepted(String correlationId) =>
    ExperimentAuthoringResultV1.fromJson({
      'correlationId': correlationId,
      'kind': 'accepted',
      'operation': 'readExperimentResults',
      'response': {
        'analysis': 'fixedHorizonNArmRate',
        'armResults': _armResults,
        'availability': const {'kind': 'available'},
        'designDigest': _receiptDigest,
        'epochDigest': _draftDigest,
        'experimentId': _experimentId,
        'generatedAtMicros': 1788091400000000,
        'guardrailOutcomes': const [
          {
            'guardrailId': 'guardrail.checkout-errors',
            'kind': 'experimentGuardrailOutcome',
            'outcome': 'withinBound',
          },
        ],
        'kind': 'experimentResultsView',
        'lifecycleState': 'active',
        'resultDigest': _resultDigest,
        'schemaVersion': kMeasurementSchemaVersion,
        'structuredCopyKeys': const ['experiment.result.noDecision'],
        'target': _target.toJson(),
      },
      'schemaVersion': kMeasurementSchemaVersion,
    }).canonicalBytes;

/// Canonical bytes of one accepted list page carrying one activated entry.
Uint8List _listAccepted(
  String correlationId, {
  List<String> experimentIds = const [_experimentId],
}) => ExperimentAuthoringResultV1.fromJson({
  'correlationId': correlationId,
  'kind': 'accepted',
  'operation': 'listExperiments',
  'response': {
    'experiments': [
      for (final experimentId in experimentIds)
        {
          'acceptedAtMicros': 1788091300000000,
          'activationOrdinal': _activationOrdinal,
          'archivedAtMicros': null,
          'controlPlaneOrdinal': 9,
          'experimentId': experimentId,
          'inferenceReference': const {
            'inferenceRevisionId': 'inference.checkout.v2',
            'kind': 'exact',
            'resultDigest': _resultDigest,
          },
          'integrityState': 'verified',
          'kind': 'experimentSummary',
          'label': experimentId,
          'lifecycleOrdinal': 8,
          'lifecycleState': 'active',
          'liveReadReference': {
            'activationOrdinal': _activationOrdinal,
            'experimentId': experimentId,
            'kind': 'experimentLiveReadReference',
            'receiptDigest': _receiptDigest,
            'target': _target.toJson(),
          },
          'pendingDraft': const {'kind': 'none'},
          'schemaVersion': kMeasurementSchemaVersion,
          'target': _target.toJson(),
        },
    ],
    'kind': 'experimentListView',
    'nextPageCursor': null,
    'schemaVersion': kMeasurementSchemaVersion,
    'target': _target.toJson(),
  },
  'schemaVersion': kMeasurementSchemaVersion,
}).canonicalBytes;

/// Canonical bytes of a typed refusal for [operation].
Uint8List _refused(String operation, String correlationId) =>
    ExperimentAuthoringResultV1.fromJson({
      'correlationId': correlationId,
      'kind': 'refused',
      'operation': operation,
      'refusal': {
        'code': 'capabilityUnavailable',
        'kind': 'experimentAuthoringRefusal',
        'messageKey': 'experiment.authoring.capabilityUnavailable',
        'retryable': false,
        'schemaVersion': kMeasurementSchemaVersion,
      },
      'schemaVersion': kMeasurementSchemaVersion,
    }).canonicalBytes;

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
    jsonEncode([
      {
        'environmentTargetId': 31,
        'namedEnvironmentId': 37,
        'environmentSlug': 'production',
        'runtimePlane': 'live',
      },
    ]),
    200,
  ),
  _ => null,
};

String _wire(List<int> bytes) => "decode('${base64Encode(bytes)}', 'base64')";

Uint8List _bytes(String wire) => Uint8List.fromList(
  base64Decode(
    wire.substring("decode('".length, wire.length - "', 'base64')".length),
  ),
);

typedef _Reply = Uint8List Function(String method, String correlationId);

/// A fake route that answers every semantic read with [reply].
http.Client _route(_Reply reply) => MockClient((request) async {
  final body = jsonDecode(request.body) as Map<String, Object?>;
  final method = body['method']! as String;
  final directory = _directory(method);
  if (directory != null) return directory;
  final sent = ExperimentAuthoringRequestV1.fromCanonicalBytes(
    _bytes(body['requestBytes']! as String),
  );
  return http.Response(
    jsonEncode(_wire(reply(method, sent.correlationId))),
    200,
  );
});

/// A route that fails the test if any semantic read reaches it.
http.Client _unreachableRoute() => MockClient((request) async {
  final body = jsonDecode(request.body) as Map<String, Object?>;
  final method = body['method']! as String;
  final directory = _directory(method);
  if (directory != null) return directory;
  fail('The semantic route was reached with $method.');
});

Uint8List _acceptedReply(String method, String correlationId) =>
    switch (method) {
      'listExperiments' => _listAccepted(correlationId),
      'readExperimentResults' => _resultsAccepted(correlationId),
      _ => _refused(method, correlationId),
    };

/// The same document with its per-call correlation identity normalised.
Map<String, Object?> _withoutCorrelation(Object? document) => {
  ...document! as Map<String, Object?>,
  'correlationId': 'correlation',
};

void main() {
  late Directory home;
  late Directory project;
  late FileCredentialStore store;

  setUp(() async {
    home = Directory.systemTemp.createTempSync('restage_mcp_results_home');
    project = Directory.systemTemp.createTempSync(
      'restage_mcp_results_project',
    );
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

  /// Calls [tool] against a route answering with [reply].
  Future<CallToolResult> callTool(
    String tool,
    Map<String, Object?> arguments, {
    _Reply reply = _acceptedReply,
  }) async {
    final connection = await connectServer(
      store: store,
      httpClient: _route(reply),
    );
    return connection.callTool(
      CallToolRequest(name: tool, arguments: arguments),
    );
  }

  /// Runs `restage experiment <arguments>` against the same fake route.
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
          httpClient: _route(reply),
          environment: const {'RESTAGE_EXPERIMENTAL': '1'},
        ).run([
          '--non-interactive',
          '--yes',
          'experiment',
          ...arguments,
          '--directory=${project.path}',
        ]);
    return (code: code, out: stdout.toString(), err: stderr.toString());
  }

  group('the tool schemas', () {
    test('ask for an exact target and refuse unknown properties', () async {
      final connection = await connectServer(
        store: store,
        httpClient: _route(_acceptedReply),
      );
      final tools = await connection.listTools(ListToolsRequest());

      for (final name in [
        'restage_read_experiment_results',
        'restage_read_experiment_roster',
      ]) {
        final schema =
            tools.tools.singleWhere((tool) => tool.name == name).inputSchema
                as Map<String, Object?>;
        expect(schema['additionalProperties'], isFalse, reason: name);
        expect(
          schema['required'],
          containsAll(<String>[
            'organizationId',
            'projectSlug',
            'appSlug',
            'environmentSlug',
            'environmentTargetId',
            'runtimePlane',
          ]),
          reason: name,
        );
      }
    });

    test('are not registered without the host opt-in', () async {
      final connection = await connectServer(
        store: store,
        httpClient: _route(_acceptedReply),
        environment: const {},
      );
      final tools = await connection.listTools(ListToolsRequest());

      expect(
        tools.tools.map((tool) => tool.name),
        isNot(
          anyElement(
            anyOf(
              'restage_read_experiment_results',
              'restage_read_experiment_roster',
            ),
          ),
        ),
      );
    });
  });

  group('a value the caller supplied', () {
    test('is named as the caller\'s own, and reaches no route', () async {
      final connection = await connectServer(
        store: store,
        httpClient: _unreachableRoute(),
      );

      final tool = await connection.callTool(
        CallToolRequest(
          name: 'restage_read_experiment_results',
          arguments: {
            ...targetArguments(),
            'experimentId': _experimentId,
            'activationOrdinal': _activationOrdinal,
            'resultDigest': 'not-a-digest',
          },
        ),
      );

      expect(tool.isError, isTrue);
      final text = (tool.content.single as TextContent).text;
      expect(text, contains('resultDigest'));
      expect(text, isNot(contains('service')));
    });

    test('is refused at the page-size bound before any read', () async {
      final connection = await connectServer(
        store: store,
        httpClient: _unreachableRoute(),
      );

      final tool = await connection.callTool(
        CallToolRequest(
          name: 'restage_read_experiment_roster',
          arguments: {...targetArguments(), 'pageSize': 250},
        ),
      );

      expect(tool.isError, isTrue);
      final text = (tool.content.single as TextContent).text;
      expect(text, contains('pageSize'));
      expect(text, isNot(contains('service')));
    });

    test('has the page-size bound stated in the schema', () async {
      final connection = await connectServer(
        store: store,
        httpClient: _route(_acceptedReply),
      );
      final tools = await connection.listTools(ListToolsRequest());

      final schema =
          tools.tools
                  .singleWhere(
                    (tool) => tool.name == 'restage_read_experiment_roster',
                  )
                  .inputSchema
              as Map<String, Object?>;
      final pageSize =
          (schema['properties']! as Map<String, Object?>)['pageSize']!
              as Map<String, Object?>;
      expect(pageSize['minimum'], 1);
      expect(pageSize['maximum'], 100);
    });
  });

  group('the results read', () {
    test('answers with the exact document the command prints', () async {
      final tool = await callTool('restage_read_experiment_results', {
        ...targetArguments(),
        'experimentId': _experimentId,
        'activationOrdinal': _activationOrdinal,
        'resultDigest': _resultDigest,
      });
      final cli = await runCli([
        'results',
        '--experiment-id=$_experimentId',
        '--activation-ordinal=$_activationOrdinal',
        '--result-digest=$_resultDigest',
        '--json',
      ]);

      expect(cli.code, 0, reason: cli.err);
      expect(tool.isError, isNot(true));
      expect(tool.structuredContent!['outcome'], 'accepted');
      // The one reuse contract: the tool surfaces the command's own document.
      // Each read mints its own correlation identity, so it is normalised
      // before the comparison.
      expect(
        jsonEncode(_withoutCorrelation(tool.structuredContent!['result'])),
        jsonEncode(_withoutCorrelation(jsonDecode(cli.out))),
      );
    });

    test('keeps every decimal beside the exact pair it came from', () async {
      final tool = await callTool('restage_read_experiment_results', {
        ...targetArguments(),
        'experimentId': _experimentId,
        'activationOrdinal': _activationOrdinal,
        'resultDigest': _resultDigest,
      });

      final result = tool.structuredContent!['result']! as Map<String, Object?>;
      final response = result['response']! as Map<String, Object?>;
      final arms = response['armResults']! as List<Object?>;
      expect(arms, hasLength(2));
      final variant = arms[1]! as Map<String, Object?>;
      expect(variant['rate'], '0.105000000');
      expect(variant['rateExact'], {'denominator': '200', 'numerator': '21'});
      expect(variant['effect'], '0.005000000');
      expect(variant['effectExact'], {'denominator': '200', 'numerator': '1'});
      final interval = variant['interval']! as Map<String, Object?>;
      expect(interval['lower'], '-0.000976563');
      expect(interval['lowerExact'], {
        'denominator': '1024',
        'numerator': '-1',
      });
      expect(interval['upper'], '0.008789063');
      expect(interval['upperExact'], {'denominator': '1024', 'numerator': '9'});
    });

    test('reports a refusal as the route stated it', () async {
      final tool = await callTool('restage_read_experiment_results', {
        ...targetArguments(),
        'experimentId': _experimentId,
        'activationOrdinal': _activationOrdinal,
        'resultDigest': _resultDigest,
      }, reply: _refused);

      expect(tool.structuredContent!['outcome'], 'refused');
      final result = tool.structuredContent!['result']! as Map<String, Object?>;
      expect(
        (result['refusal']! as Map<String, Object?>)['code'],
        'capabilityUnavailable',
      );
    });
  });

  group('the roster read', () {
    test('answers with the exact roster the command prints', () async {
      final tool = await callTool(
        'restage_read_experiment_roster',
        targetArguments(),
      );
      final cli = await runCli(['list', '--results', '--json']);

      expect(cli.code, 0, reason: cli.err);
      expect(tool.structuredContent!['outcome'], 'accepted');
      expect(
        jsonEncode(tool.structuredContent!['roster']),
        jsonEncode(jsonDecode(cli.out)),
      );
    });

    test('carries each entry beside the results it names', () async {
      final tool = await callTool(
        'restage_read_experiment_roster',
        targetArguments(),
      );

      final roster = tool.structuredContent!['roster']! as List<Object?>;
      expect(roster, hasLength(1));
      final row = roster.single! as Map<String, Object?>;
      final entry = row['entry']! as Map<String, Object?>;
      expect(entry['experimentId'], _experimentId);
      final results = row['results']! as Map<String, Object?>;
      expect(results['kind'], 'experimentResultsView');
      expect(results['resultDigest'], _resultDigest);
    });

    test('keeps the rows around an entry whose read is refused', () async {
      var reads = 0;
      final tool = await callTool(
        'restage_read_experiment_roster',
        targetArguments(),
        reply: (method, correlationId) => switch (method) {
          'listExperiments' => _listAccepted(
            correlationId,
            experimentIds: const ['experiment.a', 'experiment.b'],
          ),
          _ =>
            ++reads == 1
                ? _refused(method, correlationId)
                : _resultsAccepted(correlationId),
        },
      );

      final roster = tool.structuredContent!['roster']! as List<Object?>;
      expect(tool.structuredContent!['outcome'], 'accepted');
      expect(roster, hasLength(2));
      final first = roster.first! as Map<String, Object?>;
      expect(first['results'], isNull);
      expect(first['omission'], 'refused');
      expect(
        ((first['refusal']! as Map<String, Object?>)['refusal']!
            as Map<String, Object?>)['code'],
        'capabilityUnavailable',
      );
      final second = roster.last! as Map<String, Object?>;
      expect(
        (second['results']! as Map<String, Object?>)['kind'],
        'experimentResultsView',
      );
      expect(second['omission'], isNull);
    });

    test('reports a refused page as the route stated it', () async {
      final tool = await callTool(
        'restage_read_experiment_roster',
        targetArguments(),
        reply: _refused,
      );

      expect(tool.structuredContent!['outcome'], 'refused');
      expect(tool.structuredContent!['operation'], 'listExperiments');
    });
  });
}
