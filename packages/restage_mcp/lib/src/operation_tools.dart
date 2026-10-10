import 'package:dart_mcp/server.dart';
import 'package:restage_cli/api.dart';

import 'api_runner.dart';
import 'tool_support.dart';

/// The operations the CLI shares, as tools bound to [ctx].
List<ToolEntry> operationTools(ToolContext ctx) => [
  for (final operation in sharedOperations)
    (toolOf(operation), (request) => _call(ctx, operation, request)),
];

/// The MCP tool for [operation].
Tool toolOf(Operation operation) {
  final scope = operation.scope;
  final properties = <String, Schema>{
    ...switch (scope) {
      OperationScope.account => const <String, Schema>{},
      OperationScope.organization => {'organizationId': organizationIdProperty},
      OperationScope.project => {
        'projectDirectory': projectDirectoryProperty,
        'organizationId': organizationIdProperty,
        'projectSlug': Schema.string(description: 'The project slug.'),
      },
      OperationScope.app => appProperties(),
      OperationScope.target => targetProperties(),
    },
    if (operation.surface) ...{
      'surfaceType': operation.readsSurface
          ? surfaceReadTypeProperty
          : surfaceTypeProperty,
      'surfaceSlug': surfaceSlugProperty,
    },
    for (final param in operation.params)
      if (!param.cliOnly) param.key: _schemaOf(param),
  };
  final scopeRequired = switch (scope) {
    OperationScope.account || OperationScope.organization => const <String>[],
    OperationScope.project => const ['projectSlug'],
    OperationScope.app => appRequired,
    OperationScope.target => targetRequired,
  };
  return Tool(
    name: operation.mcpName,
    description: operation.mcpDescription,
    inputSchema: Schema.object(
      properties: properties,
      required: [
        if (operation.surface && scope == OperationScope.target)
          ...(operation.readsSurface
              ? surfaceReadRequired
              : surfaceTargetRequired)
        else ...[
          ...scopeRequired,
          if (operation.surface) ...[
            if (!operation.readsSurface) 'surfaceType',
            'surfaceSlug',
          ],
        ],
        for (final param in operation.params)
          if (param.required && !param.cliOnly) param.key,
      ],
    ),
  );
}

Schema _schemaOf(OperationParam param) {
  final description = param.mcpHelp ?? param.help;
  if (param.allowed case final values?) {
    return UntitledSingleSelectEnumSchema(
      description: description,
      values: values,
    );
  }
  return switch (param.type) {
    ParamType.string => Schema.string(description: description),
    ParamType.integer => Schema.int(description: description),
    ParamType.boolean => Schema.bool(description: description),
    ParamType.clearable => Schema.combined(
      description: description,
      anyOf: [Schema.string(), Schema.nil()],
    ),
  };
}

Future<CallToolResult> _call(
  ToolContext ctx,
  Operation operation,
  CallToolRequest request,
) => ctx.authed('running ${operation.mcpName}', (api) async {
  final arguments = request.arguments ?? const <String, Object?>{};
  final args = OperationArgs({
    for (final param in operation.params)
      if (!param.cliOnly && arguments.containsKey(param.key))
        param.key: switch (arguments[param.key]) {
          final num value when param.type == ParamType.integer => value.toInt(),
          final value => value,
        },
  });
  final invalid = operation.validate?.call(args, (key) => key);
  if (invalid != null) return mcpError(invalid);

  final identity = !operation.surface
      ? null
      : operation.readsSurface
      ? await readIdentityOf(api, request)
      : lifecycleIdentityOf(request);
  final ToolTarget? at = operation.scope == OperationScope.target
      ? targetSelector(request)
      : null;
  final target = OperationTarget(
    api: api,
    syntax: SelectorSyntax.mcp,
    organizationId: at?.organizationId ?? request.optInt('organizationId'),
    project: request.optStr('projectSlug'),
    app: request.optStr('appSlug'),
    environment: at?.environment,
    environmentTargetId: at?.environmentTargetId,
    runtimePlane: at?.runtimePlane,
    identity: identity,
  );
  final json = operation.json(await operation.call(target, args));
  return jsonResult(switch (operation.resultKey) {
    final key? => <String, Object?>{key: json},
    null => json! as Map<String, Object?>,
  });
});
