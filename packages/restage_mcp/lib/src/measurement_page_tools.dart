import 'package:dart_mcp/server.dart';
import 'package:restage_cli/api.dart';

import 'api_runner.dart';
import 'tool_support.dart';

const _readingError =
    'The service returned a reading that is not for this target.';

/// One tool per dashboard page read, from the definitions the CLI shares.
List<ToolEntry> measurementPageTools(ToolContext ctx) => [
  for (final read in pageReads)
    (_toolFor(read), (request) => _handleRead(ctx, read, request)),
];

Tool _toolFor(PageRead read) => Tool(
  name: read.mcpName,
  description: read.mcpDescription,
  inputSchema: Schema.object(
    properties: {
      ...exactTargetProperties(),
      'windowStartMicros': Schema.int(
        description:
            'Start of the window, inclusive, in microseconds since the '
            'epoch. The read starts at that UTC day. Defaults to '
            '$kPageReadDefaultWindowDays days before the end.'
            '${read.optionalWindow ? ' Omit both ends to read the whole run.' : ''}',
      ),
      'windowEndExclusiveMicros': Schema.int(
        description:
            'End of the window, exclusive, in microseconds since the epoch. '
            'The read runs to the end of that UTC day. Defaults to now.',
      ),
      for (final param in read.params)
        if (!param.cliOnly) param.key: _schemaFor(param),
    },
    required: [
      ...exactTargetRequired,
      for (final param in read.params)
        if (param.required && !param.cliOnly) param.key,
    ],
    additionalProperties: false,
  ),
);

Schema _schemaFor(PageParam param) => switch (param.kind) {
  PageParamKind.integer => Schema.int(description: param.help, minimum: 1),
  PageParamKind.flag => Schema.bool(description: param.help),
  PageParamKind.stringList => Schema.list(
    description: param.help,
    items: Schema.string(),
  ),
  PageParamKind.string when param.allowed != null =>
    UntitledSingleSelectEnumSchema(
      description: param.help,
      values: param.allowed!,
    ),
  PageParamKind.string => Schema.string(description: param.help),
};

/// Reads one page and returns the service's reply unchanged.
Future<CallToolResult> _handleRead(
  ToolContext ctx,
  PageRead read,
  CallToolRequest request,
) {
  try {
    RuntimePlane.fromWireName(request.str('runtimePlane'));
  } on FormatException {
    return Future.value(mcpError('The declared runtime plane is invalid.'));
  }

  final Map<String, Object?> values;
  final PageWindowMicros? window;
  try {
    values = _valuesOf(read, request);
    window = resolvePageWindow(
      read,
      startMicros: request.optInt('windowStartMicros'),
      endMicros: request.optInt('windowEndExclusiveMicros'),
      now: DateTime.now(),
    );
  } on FormatException catch (error) {
    return Future.value(mcpError(error.message));
  }

  return ctx.authed('reading ${read.cliPath}', (api) async {
    final target = await exactTargetCoordinate(api, request);
    if (target == null) return mcpError(exactTargetError);
    try {
      final reply = await MeasurementPageApi(api).read(
        read.select(values),
        PageRequest(target: target, values: values, window: window),
      );
      return CallToolResult(content: [TextContent(text: reply)]);
    } on MeasurementPageMismatchException {
      return mcpError(_readingError);
    }
  });
}

Map<String, Object?> _valuesOf(PageRead read, CallToolRequest request) {
  final arguments = request.arguments ?? const <String, Object?>{};
  final values = <String, Object?>{};
  for (final param in read.params) {
    if (param.cliOnly) continue;
    final raw = arguments[param.key];
    if (raw == null) {
      if (param.required) throw FormatException('${param.key} is required');
      continue;
    }
    switch (param.kind) {
      case PageParamKind.integer:
        if (raw is! num || raw != raw.toInt() || raw < 1) {
          throw FormatException('${param.key} must be a whole number.');
        }
        values[param.key] = raw.toInt();
      case PageParamKind.flag:
        if (raw is! bool) {
          throw FormatException('${param.key} must be true or false.');
        }
        if (raw) values[param.key] = true;
      case PageParamKind.stringList:
        if (raw is! List || raw.any((value) => value is! String)) {
          throw FormatException('${param.key} must be a list of strings.');
        }
        if (raw.isNotEmpty) values[param.key] = raw.cast<String>();
      case PageParamKind.string:
        if (raw is! String || (param.allowed?.contains(raw) == false)) {
          throw FormatException('${param.key} is not a valid value.');
        }
        values[param.key] = param.parse?.call(raw) ?? raw;
    }
  }
  return values;
}
