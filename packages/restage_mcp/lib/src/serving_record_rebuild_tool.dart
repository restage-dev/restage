import 'dart:convert';

import 'package:dart_mcp/server.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/api.dart';

import 'api_runner.dart';
import 'exact_target.dart';

const _targetError =
    'The declared target does not resolve to one exact authorized target.';
const _resultError = 'The service returned an invalid readiness report.';

const _runtimePlanes = ['sandbox', 'live'];

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
      'readinessOnly': Schema.bool(
        description:
            'Inspect what is missing without producing anything. It does not '
            're-prove sources, so only the full rebuild is the deploy '
            'readiness gate.',
      ),
    },
    required: [
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

/// Runs one rebuild or readiness read through the shared API.
///
/// The route decides: this reports the readiness it returns and never judges
/// a target ready on its own.
Future<CallToolResult> handleServingRecordRebuild({
  required CallToolRequest request,
  required FileCredentialStore store,
  http.Client? httpClient,
}) {
  final RuntimePlane runtimePlane;
  try {
    runtimePlane = RuntimePlane.fromWireName(request.str('runtimePlane'));
  } on FormatException {
    return Future.value(mcpError('The declared runtime plane is invalid.'));
  }

  final organizationId = request.reqInt('organizationId');
  final projectSlug = request.str('projectSlug');
  final appSlug = request.str('appSlug');
  final environmentSlug = request.str('environmentSlug');
  final environmentTargetId = request.reqInt('environmentTargetId');
  final readinessOnly = request.arguments?['readinessOnly'] == true;

  return withApi(
    store: store,
    httpClient: httpClient,
    action: 'rebuilding the serving records',
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
    },
  );
}
