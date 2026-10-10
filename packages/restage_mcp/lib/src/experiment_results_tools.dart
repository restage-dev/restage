import 'package:dart_mcp/server.dart';
import 'package:restage_cli/api.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    as measurement;

import 'api_runner.dart';
import 'tool_support.dart';

const _resultError = 'The service returned an invalid semantic result.';

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
      ...exactTargetProperties(),
      'experimentId': Schema.string(description: 'The experiment identity.'),
      'activationOrdinal': Schema.int(
        description: 'The activation ordinal the results belong to.',
      ),
      'resultDigest': Schema.string(
        description: 'The exact result digest to read.',
      ),
    },
    required: [
      ...exactTargetRequired,
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
      ...exactTargetProperties(),
      'pageSize': Schema.int(
        description: 'Entries to read per page, 1..100. Defaults to 100.',
        minimum: 1,
        maximum: 100,
      ),
    },
    required: exactTargetRequired,
    additionalProperties: false,
  ),
);

/// Reads one experiment's results through the shared read path.
Future<CallToolResult> handleReadExperimentResults(
  ToolContext ctx,
  CallToolRequest request,
) => _withTarget(
  ctx,
  request,
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
Future<CallToolResult> handleReadExperimentRoster(
  ToolContext ctx,
  CallToolRequest request,
) {
  final pageSize = request.optInt('pageSize') ?? 100;
  return _withTarget(
    ctx,
    request,
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
Future<CallToolResult> _withTarget(
  ToolContext ctx,
  CallToolRequest request, {
  required String action,
  required measurement.ExperimentAuthoringRequestV1 Function() build,
  required Future<CallToolResult> Function(
    RestageApi api,
    measurement.TargetCoordinate target,
    measurement.ExperimentAuthoringRequestV1 first,
  )
  body,
}) {
  try {
    RuntimePlane.fromWireName(request.str('runtimePlane'));
  } on FormatException {
    return Future.value(mcpError('The declared runtime plane is invalid.'));
  }

  final measurement.ExperimentAuthoringRequestV1 first;
  try {
    first = build();
  } on measurement.CanonicalFormatException catch (error) {
    return Future.value(mcpError(error.message));
  }

  return ctx.authed(action, (api) async {
    final target = await exactTargetCoordinate(api, request);
    if (target == null) return mcpError(exactTargetError);
    try {
      return await body(api, target, first);
    } on ExperimentResponseMismatchException {
      return mcpError(_resultError);
    } on ExperimentPageCursorRepeatedException {
      return mcpError(_resultError);
    } on measurement.CanonicalFormatException {
      return mcpError(_resultError);
    }
  });
}
