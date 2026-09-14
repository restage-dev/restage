import 'dart:math';

import 'package:dart_mcp/server.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/api.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    as measurement;

import 'api_runner.dart';
import 'exact_target.dart';

const _targetError =
    'The declared target does not resolve to one exact authorized target.';
const _payloadError =
    'The operation payload is not the exact semantic document this operation '
    'accepts.';
const _resultError = 'The service returned an invalid semantic result.';

/// Every semantic operation, in the order the schema declares them.
final List<String> _operations = [
  for (final operation in measurement.ExperimentAuthoringOperationV1.values)
    operation.wireName,
];

const _runtimePlanes = ['sandbox', 'live'];

/// The one semantic experiment operation exposed through MCP.
///
/// The operation is a closed choice and the payload is the exact semantic
/// document that operation accepts. There is no canonical byte envelope: a
/// caller states what it means, never how the request is spelled.
final experimentApplyTool = Tool(
  name: 'restage_experiment_apply',
  description:
      'Apply one semantic experiment operation at an exact target. The '
      'operation is a closed choice and the payload is that operation\'s own '
      'semantic document. Reads and writes both go through this operation; '
      'the result reports whether the route accepted or refused it.',
  inputSchema: Schema.object(
    properties: {
      'operation': UntitledSingleSelectEnumSchema(
        description: 'The semantic operation to apply.',
        values: _operations,
      ),
      'payload': Schema.object(
        description:
            'The exact semantic payload this operation accepts. A '
            'serverDefault choice is the bare sentinel: a resolved value, '
            'reference, or source is refused before transport.',
      ),
      'idempotencyKey': Schema.string(
        description:
            'Retry identity, required for an operation that changes state and '
            'refused for one that does not.',
      ),
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
    },
    required: [
      'operation',
      'payload',
      'organizationId',
      'projectSlug',
      'appSlug',
      'environmentSlug',
      'environmentTargetId',
      'runtimePlane',
    ],
    additionalProperties: false,
  ),
);

/// Applies one semantic experiment operation through the shared API.
///
/// The public schema decodes the request, so an unknown property or a resolved
/// `serverDefault` is refused here rather than at the route. Authority stays
/// the route's: a refusal is reported as it arrives and never widened.
Future<CallToolResult> handleExperimentApply({
  required CallToolRequest request,
  required FileCredentialStore store,
  http.Client? httpClient,
}) {
  final operation = _operationFor(request.str('operation'));
  if (operation == null) {
    return Future.value(mcpError('The declared operation is unsupported.'));
  }

  final payload = request.arguments?['payload'];
  if (payload is! Map<String, Object?>) {
    return Future.value(mcpError(_payloadError));
  }

  final RuntimePlane runtimePlane;
  try {
    runtimePlane = RuntimePlane.fromWireName(request.str('runtimePlane'));
  } on FormatException {
    return Future.value(mcpError('The declared runtime plane is invalid.'));
  }

  final measurement.ExperimentAuthoringRequestV1 semanticRequest;
  try {
    final idempotencyKey = request.optStr('idempotencyKey');
    final correlationId = idempotencyKey == null
        ? _newCorrelationId()
        : experimentRetryCorrelationId(
            operation: operation,
            payload: payload,
            idempotencyKey: idempotencyKey,
          );
    semanticRequest = experimentRequest(
      operation: operation,
      correlationId: correlationId,
      payload: payload,
      idempotencyKey: idempotencyKey,
    );
  } on measurement.CanonicalFormatException catch (error) {
    // The schema's message names the offending field, which is what the caller
    // needs to fix. It also covers the envelope, not only the payload.
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
    action: 'applying the experiment operation',
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
        final result = await ExperimentApi(
          api,
        ).execute(request: semanticRequest, target: target);
        return _success(result);
      } on ExperimentResponseMismatchException {
        return mcpError(_resultError);
      } on measurement.CanonicalFormatException {
        return mcpError(_resultError);
      }
    },
  );
}

CallToolResult _success(measurement.ExperimentAuthoringResultV1 result) {
  final accepted = result is measurement.ExperimentAuthoringAcceptedV1;
  return CallToolResult(
    content: [
      TextContent(
        text: accepted
            ? 'Accepted ${result.operation.wireName}.'
            : 'Refused ${result.operation.wireName}: '
                  '${(result as measurement.ExperimentAuthoringRefusedV1).refusal.code.wireName}.',
      ),
    ],
    structuredContent: {
      'outcome': accepted ? 'accepted' : 'refused',
      'operation': result.operation.wireName,
      'result': result.toJson(),
    },
  );
}

measurement.ExperimentAuthoringOperationV1? _operationFor(String wireName) {
  for (final operation in measurement.ExperimentAuthoringOperationV1.values) {
    if (operation.wireName == wireName) return operation;
  }
  return null;
}

final _random = Random.secure();

String _newCorrelationId() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
  return 'correlation-'
      '${bytes.map((byte) => byte.toRadixString(16).padLeft(2, "0")).join()}';
}
