import 'dart:convert';

import 'package:dart_mcp/server.dart';
import 'package:restage_cli/api.dart';

import 'api_runner.dart';
import 'tool_support.dart';

const _resultError = 'The service returned an invalid readiness report.';

/// The operator route that fills a target's missing serving records.
final servingRecordRebuildTool = Tool(
  name: 'restage_rebuild_serving_records',
  description:
      'Produce the serving records an experiment target lacks and report what '
      'is left, per surface. The full rebuild also re-proves the sources '
      'behind the records it finds, which is what makes it the deploy '
      'readiness gate; readinessOnly only counts what is missing. '
      'Authorized at the same floor as an experiment activation.',
  inputSchema: Schema.object(
    properties: {
      ...exactTargetProperties(),
      'readinessOnly': Schema.bool(
        description:
            'Inspect what is missing without producing anything. It does not '
            're-prove sources, so only the full rebuild is the deploy '
            'readiness gate.',
      ),
    },
    required: [...exactTargetRequired],
    additionalProperties: false,
  ),
);

/// Runs one rebuild or readiness read through the shared API.
///
/// The route decides: this reports the readiness it returns and never judges
/// a target ready on its own.
Future<CallToolResult> handleServingRecordRebuild(
  ToolContext ctx,
  CallToolRequest request,
) {
  try {
    RuntimePlane.fromWireName(request.str('runtimePlane'));
  } on FormatException {
    return Future.value(mcpError('The declared runtime plane is invalid.'));
  }

  final readinessOnly = request.arguments?['readinessOnly'] == true;

  return ctx.authed('rebuilding the serving records', (api) async {
    final target = await exactTargetCoordinate(api, request);
    if (target == null) return mcpError(exactTargetError);

    final response = await api.call(
      'experimentActivation',
      'rebuildServingRecords',
      <String, dynamic>{
        'organizationId': target.organizationId.value,
        'appId': target.appId.value,
        'environmentTargetId': target.environmentTargetId.value,
        'namedEnvironmentId': target.namedEnvironmentId.value,
        'runtimePlane': target.runtimePlane.wireName,
        'readinessOnly': readinessOnly,
      },
    );
    final Map<String, Object?> readiness;
    try {
      readiness = jsonDecode(response as String) as Map<String, Object?>;
    } on Object {
      return mcpError(_resultError);
    }
    // Readiness answers presence, not truth: saying only "ready" would read
    // as the re-proven verdict, which only a rebuild produces.
    final caveat = readiness['sourcesReproven'] == true
        ? 'sources re-proven'
        : 'records present; sources not re-proven — run rebuild';
    return CallToolResult(
      content: [
        TextContent(
          text:
              'Produced ${readiness['produced']}, superseded '
              '${readiness['superseded'] ?? 0}; '
              '${readiness['missing']} still missing a current record '
              '($caveat).',
        ),
      ],
      structuredContent: readiness,
    );
  });
}
