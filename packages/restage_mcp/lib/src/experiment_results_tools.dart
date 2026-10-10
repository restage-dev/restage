import 'package:dart_mcp/server.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/api.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    as measurement;

import 'api_runner.dart';
import 'exact_target.dart';

const _targetError =
    'The declared target does not resolve to one exact authorized target.';
const _resultError = 'The service returned an invalid semantic result.';

const _runtimePlanes = ['sandbox', 'live'];

final _targetProperties = <String, Schema>{
  'organizationId': Schema.int(description: 'The organization id.'),
  'projectSlug': Schema.string(description: 'The project slug.'),
  'appSlug': Schema.string(description: 'The app slug.'),
  'environmentSlug': Schema.string(description: 'The environment slug.'),
  'environmentTargetId': Schema.int(
    description: 'The exact environment target id.',
  ),
  'runtimePlane': UntitledSingleSelectEnumSchema(
    description: 'The target runtime plane: sandbox or live.',
    values: _runtimePlanes,
  ),
};

const _targetRequired = [
  'organizationId',
  'projectSlug',
  'appSlug',
  'environmentSlug',
  'environmentTargetId',
  'runtimePlane',
];

/// Reads one experiment's results at an exact target.
final readExperimentResultsTool = Tool(
  name: 'restage_read_experiment_results',
  description:
      'Read one experiment\'s results at an exact target. Every rate, effect '
      'and interval end is a decimal beside the exact numerator and '
      'denominator it came from; the figures are the service\'s own and are '
      'returned unchanged.',
  inputSchema: Schema.object(
    properties: {
      ..._targetProperties,
      'experimentId': Schema.string(description: 'The experiment identity.'),
      'activationOrdinal': Schema.int(
        description: 'The activation ordinal the results belong to.',
      ),
      'resultDigest': Schema.string(
        description: 'The exact result digest to read.',
      ),
    },
    required: [
      ..._targetRequired,
      'experimentId',
      'activationOrdinal',
      'resultDigest',
    ],
    additionalProperties: false,
  ),
);

/// Lists the experiments at an exact target beside the results each names.
final readExperimentRosterTool = Tool(
  name: 'restage_read_experiment_roster',
  description:
      'List every experiment at an exact target beside the results its '
      'inference reference names. Every listed experiment keeps a row: one '
      'that names no evaluated result, whose read the service refuses, or '
      'that falls beyond the $kExperimentRosterResultReadBound result reads '
      'one call performs states that in its `omission` field. The figures '
      'are the service\'s own and are returned unchanged.',
  inputSchema: Schema.object(
    properties: {
      ..._targetProperties,
      'pageSize': Schema.int(
        description: 'Entries to read per page, 1..100. Defaults to 100.',
        minimum: 1,
        maximum: 100,
      ),
    },
    required: _targetRequired,
    additionalProperties: false,
  ),
);

/// Reads one experiment's results through the shared read path.
Future<CallToolResult> handleReadExperimentResults({
  required CallToolRequest request,
  required FileCredentialStore store,
  http.Client? httpClient,
}) => _withTarget(
  request: request,
  store: store,
  httpClient: httpClient,
  action: 'reading the experiment results',
  build: () => experimentResultsRequest(
    correlationId: newExperimentIdentity('correlation'),
    experimentId: request.str('experimentId'),
    activationOrdinal: request.reqInt('activationOrdinal'),
    resultDigest: request.str('resultDigest'),
  ),
  body: (api, target, first) async {
    final result = await ExperimentApi(
      api,
    ).execute(request: first, target: target);
    return jsonResult({
      'outcome': result is measurement.ExperimentAuthoringAcceptedV1
          ? 'accepted'
          : 'refused',
      'operation': result.operation.wireName,
      'result': result.toJson(),
    });
  },
);

/// Reads the roster and each entry's results through the shared read path.
Future<CallToolResult> handleReadExperimentRoster({
  required CallToolRequest request,
  required FileCredentialStore store,
  http.Client? httpClient,
}) {
  final pageSize = request.optInt('pageSize') ?? 100;
  return _withTarget(
    request: request,
    store: store,
    httpClient: httpClient,
    action: 'reading the experiment roster',
    build: () => experimentRosterPageRequest(
      correlationId: newExperimentIdentity('correlation'),
      pageSize: pageSize,
    ),
    body: (api, target, first) async {
      final drained = await ExperimentApi(api).listEveryPageWithResults(
        target: target,
        correlationId: first.correlationId,
        pageSize: pageSize,
      );
      return switch (drained) {
        ExperimentPagesAccepted(:final value) => jsonResult({
          'outcome': 'accepted',
          'roster': [for (final entry in value) _rosterRow(entry)],
        }),
        ExperimentPagesRefused(:final refusal) => jsonResult({
          'outcome': 'refused',
          'operation': refusal.operation.wireName,
          'result': refusal.toJson(),
        }),
      };
    },
  );
}

/// One roster row: the entry, its results, or why none were read.
Map<String, Object?> _rosterRow(ExperimentRosterEntry entry) => {
  'entry': entry.entry.toJson(),
  'omission': entry.omission?.name,
  'refusal': entry.refusal?.toJson(),
  'results': entry.results?.toJson(),
};

/// Builds this read's request, resolves the target, then runs [body].
///
/// A value the caller supplied that the schema refuses is reported with the
/// schema's own message, before the read opens, so a caller's own mistake is
/// never reported as a service fault.
Future<CallToolResult> _withTarget({
  required CallToolRequest request,
  required FileCredentialStore store,
  required http.Client? httpClient,
  required String action,
  required measurement.ExperimentAuthoringRequestV1 Function() build,
  required Future<CallToolResult> Function(
    RestageApi api,
    measurement.TargetCoordinate target,
    measurement.ExperimentAuthoringRequestV1 first,
  )
  body,
}) {
  final RuntimePlane runtimePlane;
  try {
    runtimePlane = RuntimePlane.fromWireName(request.str('runtimePlane'));
  } on FormatException {
    return Future.value(mcpError('The declared runtime plane is invalid.'));
  }

  final measurement.ExperimentAuthoringRequestV1 first;
  try {
    first = build();
  } on measurement.CanonicalFormatException catch (error) {
    return Future.value(mcpError(error.message));
  }

  final organizationId = request.reqInt('organizationId');
  final projectSlug = request.str('projectSlug');
  final appSlug = request.str('appSlug');
  final environmentSlug = request.str('environmentSlug');
  final environmentTargetId = request.reqInt('environmentTargetId');

  return withApi(
    store: store,
    httpClient: httpClient,
    action: action,
    surfaceNoun: 'surface',
    body: (api) async {
      final target = await resolveExactTarget(
        api: api,
        organizationId: organizationId,
        projectSlug: projectSlug,
        appSlug: appSlug,
        environmentSlug: environmentSlug,
        environmentTargetId: environmentTargetId,
        runtimePlane: runtimePlane,
      );
      if (target == null) return mcpError(_targetError);
      try {
        return await body(api, target, first);
      } on ExperimentResponseMismatchException {
        return mcpError(_resultError);
      } on ExperimentPageCursorRepeatedException {
        return mcpError(_resultError);
      } on measurement.CanonicalFormatException {
        return mcpError(_resultError);
      }
    },
  );
}
