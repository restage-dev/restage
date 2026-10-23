import 'package:dart_mcp/server.dart';
import 'package:restage_cli/api.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    as measurement;

import 'api_runner.dart';
import 'tool_support.dart';

const _readingError = 'The service returned an invalid funnel reading.';

/// Reads one surface's funnel at an exact target.
final readSurfaceFunnelTool = Tool(
  name: 'restage_read_surface_funnel',
  description:
      "Read one surface's funnel at an exact target: per served published "
      'version, the eligible presentations, views, completions, skips and '
      'dismissals, the authored steps with their transitions, and the typed '
      'drop-off bands. Counts are integers; every rate is a decimal beside '
      'the exact numerator and denominator it came from. A count under the '
      'disclosure floor of 5 is null and reads "<5". A version, step or band '
      'held whole keeps its identity and states no counts. The figures are '
      "the service's own and are returned unchanged.",
  inputSchema: Schema.object(
    properties: {
      ...exactTargetProperties(),
      'surfaceId': Schema.string(
        description: 'The surface slug or measurement id.',
      ),
      'windowStartMicros': Schema.int(
        description:
            'Start of the window, inclusive, in microseconds since '
            'the epoch. The read starts at that UTC day; the reading '
            'states the window it read.',
      ),
      'windowEndExclusiveMicros': Schema.int(
        description:
            'End of the window, exclusive, in microseconds since '
            'the epoch. The read runs to the end of that UTC day.',
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
      ...exactTargetRequired,
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
Future<CallToolResult> handleReadSurfaceFunnel(
  ToolContext ctx,
  CallToolRequest request,
) {
  try {
    RuntimePlane.fromWireName(request.str('runtimePlane'));
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

  return ctx.authed('reading the surface funnel', (api) async {
    final target = await exactTargetCoordinate(api, request);
    if (target == null) return mcpError(exactTargetError);
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
  });
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
