import 'package:dart_mcp/server.dart';
import 'package:restage_cli/api.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    as measurement;

import 'api_runner.dart';
import 'tool_support.dart';

const _payloadError =
    'The operation payload is not the exact semantic document this operation '
    'accepts.';
const _resultError = 'The service returned an invalid semantic result.';

/// Every semantic operation, in the order the schema declares them.
final List<String> _operations = [
  for (final operation in measurement.ExperimentAuthoringOperationV1.values)
    operation.wireName,
];

/// Applies one experiment operation through MCP.
/// `replaceDraft` takes an accepted draft result with edited `response.choices`;
/// other operations take their exact semantic document.
final experimentApplyTool = Tool(
  name: 'restage_experiment_apply',
  description:
      'Apply one semantic experiment operation at an exact target. The '
      'operation is a closed choice and the payload is that operation\'s own '
      'semantic document. For `replaceDraft`, pass the accepted result of any '
      'draft operation as `payload`. `readDeliveryOptions` returns the '
      'experiment\'s sealed audience revision and every arm\'s exact delivery '
      'publication for a route handover. Reads and writes both go through '
      'this operation; the '
      'result reports whether the route accepted or refused it.',
  inputSchema: Schema.object(
    properties: {
      'operation': UntitledSingleSelectEnumSchema(
        description: 'The semantic operation to apply.',
        values: _operations,
      ),
      'payload': Schema.object(
        description:
            'For replaceDraft, the accepted result envelope returned by a '
            'draft operation, with edited response.choices. For other '
            'operations, the exact semantic payload.',
      ),
      'idempotencyKey': Schema.string(
        description:
            'Retry identity, required for an operation that changes state and '
            'refused for one that does not.',
      ),
      'acceptFit': acceptFitProperty,
      ...exactTargetProperties(),
    },
    required: ['operation', 'payload', ...exactTargetRequired],
    additionalProperties: false,
  ),
);

/// Applies one semantic experiment operation through the shared API.
///
/// Draft results are converted before request validation and retry hashing.
/// Service refusals retain their original authority and code.
Future<CallToolResult> handleExperimentApply(
  ToolContext ctx,
  CallToolRequest request,
) {
  final operation = _operationFor(request.str('operation'));
  if (operation == null) {
    return Future.value(mcpError('The declared operation is unsupported.'));
  }

  final input = request.arguments?['payload'];
  final ({measurement.TargetCoordinate target, Map<String, Object?> payload})?
  replacement;
  try {
    replacement =
        operation == measurement.ExperimentAuthoringOperationV1.replaceDraft
        ? experimentDraftReplacement(input)
        : null;
  } on measurement.CanonicalFormatException catch (error) {
    return Future.value(mcpError(error.message));
  }
  if (operation == measurement.ExperimentAuthoringOperationV1.replaceDraft &&
      replacement == null) {
    return Future.value(
      mcpError(
        'The replacement must be the accepted result of a draft operation.',
      ),
    );
  }
  final payload = replacement?.payload ?? input;
  if (payload is! Map<String, Object?>) {
    return Future.value(mcpError(_payloadError));
  }

  try {
    RuntimePlane.fromWireName(request.str('runtimePlane'));
  } on FormatException {
    return Future.value(mcpError('The declared runtime plane is invalid.'));
  }

  final idempotencyKey = request.optStr('idempotencyKey');
  measurement.ExperimentAuthoringRequestV1 semanticRequestFor(
    Map<String, Object?> payload,
  ) => experimentRequest(
    operation: operation,
    correlationId: idempotencyKey == null
        ? _newCorrelationId()
        : experimentRetryCorrelationId(
            operation: operation,
            payload: payload,
            idempotencyKey: idempotencyKey,
          ),
    payload: payload,
    idempotencyKey: idempotencyKey,
  );

  // An opening candidate without a root opens under its own surface, which
  // needs the resolved target; everything else is checked before transport.
  final candidate =
      operation == measurement.ExperimentAuthoringOperationV1.openDraft &&
          !payload.containsKey('root')
      ? payload['initialCandidate']
      : null;
  final measurement.ExperimentExactSurfaceReferenceV1? opening;
  final measurement.ExperimentAuthoringRequestV1 checked;
  try {
    opening = candidate is Map<String, Object?>
        ? measurement.ExperimentExactSurfaceReferenceV1.fromJson(
            candidate,
            path: 'experimentAuthoringRequest.payload.initialCandidate',
          )
        : null;
    checked = semanticRequestFor(
      opening == null ? payload : ({...payload}..remove('initialCandidate')),
    );
  } on measurement.CanonicalFormatException catch (error) {
    // The schema's message names the offending field, which is what the caller
    // needs to fix. It also covers the envelope, not only the payload.
    return Future.value(mcpError(error.message));
  }

  return ctx.authed('applying the experiment operation', (api) async {
    final target = await exactTargetCoordinate(api, request);
    if (target == null) return mcpError(exactTargetError);
    if (replacement != null && replacement.target != target) {
      return mcpError(
        'The replacement draft does not match the selected target.',
      );
    }
    final semanticRequest = opening == null
        ? checked
        : semanticRequestFor({
            ...payload,
            'root': measurement.DeliveryRootIdentityV1.surface(
              measurement.PublishedSurfaceIdentityV1(
                target: target,
                surfaceId: opening.surfaceId,
              ),
            ).toJson(),
          });

    try {
      final result = await ExperimentApi(api).execute(
        request: semanticRequest,
        target: target,
        acceptFit: request.optBool('acceptFit') ?? false,
      );
      return _success(result);
    } on ExperimentResponseMismatchException {
      return mcpError(_resultError);
    } on measurement.CanonicalFormatException {
      return mcpError(_resultError);
    }
  });
}

CallToolResult _success(measurement.ExperimentAuthoringResultV1 result) {
  final accepted = result is measurement.ExperimentAuthoringAcceptedV1;
  return CallToolResult(
    content: [TextContent(text: _resultText(result))],
    structuredContent: {
      'outcome': accepted ? 'accepted' : 'refused',
      'operation': result.operation.wireName,
      'result': result.toJson(),
    },
  );
}

/// Renders the semantic result without making any delivery decision locally.
String _resultText(measurement.ExperimentAuthoringResultV1 result) {
  if (result case measurement.ExperimentAuthoringAcceptedV1(
    response: final measurement.ExperimentDeliveryOptionsViewV1 view,
  )) {
    final arms = view.arms
        .map(
          (arm) =>
              '${arm.label} (${arm.stableArmId.value}) '
              '${_deliveryArmPublication(arm)}',
        )
        .join(', ');
    return 'Delivery options for ${view.audienceLabel} '
        '(${view.audienceRevisionId.value}) on ${view.surfaceSlug} '
        '(${view.surfaceType.value}): $arms.';
  }
  if (result is measurement.ExperimentAuthoringAcceptedV1) {
    return 'Accepted ${result.operation.wireName}.';
  }
  final refused = result as measurement.ExperimentAuthoringRefusedV1;
  final locator = refused.refusal.locator;
  final conflict = locator == null
      ? ''
      : ' Audience held by ${locator.conflictingExperimentId} '
            '(its revision ${locator.conflictingAudienceRef.revisionId.value}, '
            'this draft ${locator.proposedAudienceRef.revisionId.value}).';
  return 'Refused ${result.operation.wireName}: '
      '${refused.refusal.code.wireName}.$conflict';
}

String _deliveryArmPublication(measurement.ExperimentDeliveryArmV1 arm) =>
    switch (arm) {
      measurement.ExperimentArmDeliveryV1(:final publishedVersion) =>
        'version $publishedVersion',
      measurement.ExperimentSurfaceContractArmDeliveryV1(
        :final contractVersion,
        :final publishedRevision,
      ) =>
        'revision $publishedRevision (contract $contractVersion)',
    };

/// Whether the call's operation changes what a target serves.
bool changesLiveExperiment(CallToolRequest request) {
  final operation = _operationFor(request.optStr('operation') ?? '');
  return operation != null && kLiveExperimentOperations.contains(operation);
}

measurement.ExperimentAuthoringOperationV1? _operationFor(String wireName) {
  for (final operation in measurement.ExperimentAuthoringOperationV1.values) {
    if (operation.wireName == wireName) return operation;
  }
  return null;
}

String _newCorrelationId() => newExperimentIdentity('correlation');
