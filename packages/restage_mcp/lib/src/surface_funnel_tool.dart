import 'package:dart_mcp/server.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/api.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    as measurement;

import 'api_runner.dart';
import 'exact_target.dart';

const _targetError =
    'The declared target does not resolve to one exact authorized target.';
const _readingError = 'The service returned an invalid funnel reading.';

const _runtimePlanes = ['sandbox', 'live'];

/// Reads one surface's funnel at an exact target.
final readSurfaceFunnelTool = Tool(
  name: 'restage_read_surface_funnel',
  description:
      "Read one surface's funnel at an exact target: per served published "
      'version, the eligible presentations, views, completions, skips and '
      'dismissals, the authored steps with their transitions, and the typed '
      'drop-off bands. Counts are integers; every rate is a decimal beside '
      'the exact numerator and denominator it came from. A group under the '
      "reading's disclosure floor keeps its identity and states no numbers. "
      "The figures are the service's own and are returned unchanged.",
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
      'surfaceId': Schema.string(
        description: 'The surface identity, as discovery reports it.',
      ),
      'windowStartMicros': Schema.int(
        description:
            'Start of the window, inclusive, in microseconds since '
            'the epoch.',
      ),
      'windowEndExclusiveMicros': Schema.int(
        description:
            'End of the window, exclusive, in microseconds since '
            'the epoch.',
      ),
      'surfaceRevisionIds': Schema.list(
        description:
            'Read only these published versions, at most '
            '${measurement.kSurfaceFunnelMaximumVersions}. Omit for every '
            'version served in the window.',
        items: Schema.string(),
      ),
    },
    required: [
      'organizationId',
      'projectSlug',
      'appSlug',
      'environmentSlug',
      'environmentTargetId',
      'runtimePlane',
      'surfaceId',
      'windowStartMicros',
      'windowEndExclusiveMicros',
    ],
    additionalProperties: false,
  ),
);

/// Reads one surface's funnel through the shared read path.
///
/// The selection is built before the read opens, so a value the caller
/// supplied that the contract refuses comes back with the contract's own
/// message naming the field, never as a service fault.
Future<CallToolResult> handleReadSurfaceFunnel({
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

  final measurement.SurfaceFunnelSelectionV1 selection;
  try {
    selection = measurement.SurfaceFunnelSelectionV1(
      surfaceId: request.str('surfaceId'),
      windowStartMicros: request.reqInt('windowStartMicros'),
      windowEndExclusiveMicros: request.reqInt('windowEndExclusiveMicros'),
      surfaceRevisionIds: _versions(request),
    );
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
    action: 'reading the surface funnel',
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
        final view = await SurfaceFunnelApi(
          api,
        ).read(target: target, selection: selection);
        return jsonResult(view.toJson());
      } on SurfaceFunnelMismatchException {
        return mcpError(_readingError);
      } on measurement.CanonicalFormatException {
        return mcpError(_readingError);
      }
    },
  );
}

/// Reads the optional version selection, absent when the caller named none.
List<String>? _versions(CallToolRequest request) {
  final raw = (request.arguments ?? const {})['surfaceRevisionIds'];
  if (raw == null) return null;
  if (raw is! List) {
    throw const measurement.CanonicalFormatException(
      'surfaceRevisionIds must be a list of version identities',
    );
  }
  return [
    for (final value in raw)
      if (value is String)
        value
      else
        throw const measurement.CanonicalFormatException(
          'surfaceRevisionIds must be a list of version identities',
        ),
  ];
}
