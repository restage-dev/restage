import 'dart:async';

import 'package:meta/meta.dart';
import 'package:restage_cli/src/config/config_target_check.dart'
    show noOrganizationSentence;
import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/scope_snapshot_api.dart';
import 'package:restage_cli/src/api/selector_syntax.dart';
import 'package:restage_cli/src/commands/surface_identity.dart';

/// How much of the target an operation names.
@experimental
enum OperationScope {
  /// The signed-in account.
  account,

  /// One organization.
  organization,

  /// One project.
  project,

  /// One app.
  app,

  /// One exact environment target.
  target,
}

/// The type of an operation parameter.
@experimental
enum ParamType {
  /// A string.
  string,

  /// An integer.
  integer,

  /// A boolean flag.
  boolean,

  /// A string that must be stated, where null (`none` on the CLI) clears it.
  clearable,
}

/// One parameter an operation accepts on the CLI and over MCP.
@experimental
@immutable
class OperationParam {
  /// Construct a parameter. [key] is the MCP argument name.
  const OperationParam(
    this.key, {
    required this.help,
    this.cli,
    this.type = ParamType.string,
    this.required = false,
    this.allowed,
    this.positional = false,
    this.mcpHelp,
    this.cliOnly = false,
    this.mcpOnly = false,
  });

  /// The MCP argument name and the key the operation reads.
  final String key;

  /// The CLI flag name, or a positional's usage such as `slot <name>`.
  final String? cli;

  /// Value type.
  final ParamType type;

  /// Whether a value is required.
  final bool required;

  /// The accepted values, when closed.
  final List<String>? allowed;

  /// Whether the CLI takes it as the single positional argument.
  final bool positional;

  /// CLI help text.
  final String help;

  /// MCP description, when it differs from [help].
  final String? mcpHelp;

  /// Whether only the CLI accepts it.
  final bool cliOnly;

  /// Whether only MCP accepts it.
  final bool mcpOnly;
}

/// The arguments one call supplies, keyed by [OperationParam.key]. A present
/// key may hold null.
@experimental
class OperationArgs {
  /// Construct from [values].
  const OperationArgs(this.values);

  /// The supplied values.
  final Map<String, Object?> values;

  /// Whether [key] was supplied.
  bool has(String key) => values.containsKey(key);

  /// A required string.
  String str(String key) => values[key]! as String;

  /// An optional string.
  String? optStr(String key) => values[key] as String?;

  /// A required integer.
  int integer(String key) => values[key]! as int;

  /// An optional integer.
  int? optInt(String key) => values[key] as int?;

  /// An optional boolean.
  bool? optBool(String key) => values[key] as bool?;
}

/// The resolved scope one call runs against.
@experimental
class OperationTarget {
  /// Construct a resolved scope.
  const OperationTarget({
    required this.api,
    required this.syntax,
    this.organizationId,
    this.project,
    this.app,
    this.appId,
    this.environment,
    this.environmentTargetId,
    this.runtimePlane,
    this.planeIsImplicit = true,
    this.identity,
    this.snapshot,
  });

  /// Authenticated backend client.
  final RestageApi api;

  /// How the caller names its selectors.
  final SelectorSyntax syntax;

  /// The organization, when named or resolved.
  final int? organizationId;

  /// Project slug.
  final String? project;

  /// App slug.
  final String? app;

  /// Numeric app id, when resolved.
  final int? appId;

  /// Environment slug.
  final String? environment;

  /// Exact environment target id.
  final int? environmentTargetId;

  /// Runtime plane of the target.
  final RuntimePlane? runtimePlane;

  /// Whether a CLI follow-up reaches the target without `--plane`.
  final bool planeIsImplicit;

  /// The surface a surface operation names.
  final SurfaceLifecycleIdentity? identity;

  /// The scope already admitted while resolving this call, if held.
  final ProgrammaticScopeSnapshot? snapshot;

  /// [organizationId], or the caller's only organization.
  Future<int> organization() async {
    if (organizationId case final id?) return id;
    final organizations =
        (snapshot ?? await readProgrammaticScope(api)).organizations;
    if (organizations.length == 1) return organizations.single.organizationId;
    throw TargetSelectionException(
      organizations.isEmpty
          ? noOrganizationSentence
          : 'You belong to multiple organizations. Pass '
                '${syntax.organization}.',
    );
  }
}

/// A table column: its header and the row key it reads.
typedef OperationColumn = ({String header, String key});

/// Writes an operation's value for a person on the CLI.
typedef CliRender =
    FutureOr<void> Function(
      StringSink out,
      Object? value,
      OperationArgs args,
      OperationTarget target,
    );

/// One operation the CLI and the MCP server both expose.
@experimental
@immutable
class Operation {
  /// Construct an operation.
  const Operation({
    required this.cliPath,
    required this.mcpName,
    required this.description,
    required this.mcpDescription,
    required this.scope,
    required this.call,
    this.surface = false,
    this.readsSurface = false,
    this.params = const [],
    this.resultKey,
    this.columns,
    this.emptyNote,
    this.validate,
    this.render,
    this.toJson,
  });

  /// The CLI command path, such as `products list`.
  final String cliPath;

  /// The MCP tool name.
  final String mcpName;

  /// CLI description.
  final String description;

  /// MCP tool description.
  final String mcpDescription;

  /// What the call is scoped to.
  final OperationScope scope;

  /// Whether the call names one surface (a positional id and a type).
  final bool surface;

  /// Whether a surface call only reads, so the surface type may be left out
  /// and looked up by id.
  final bool readsSurface;

  /// The parameters beyond the scope.
  final List<OperationParam> params;

  /// The backend call.
  final Future<Object?> Function(OperationTarget target, OperationArgs args)
  call;

  /// The key MCP returns the value under; null returns the value itself.
  final String? resultKey;

  /// Table columns for a list, or record lines for one row.
  final List<OperationColumn>? columns;

  /// What the CLI says in place of an empty list.
  final String? emptyNote;

  /// A cross-parameter check, worded with [name] for each parameter key.
  final String? Function(OperationArgs args, String Function(String key) name)?
  validate;

  /// CLI text output, when [columns] do not describe it.
  final CliRender? render;

  /// The JSON form of the value, when it is not JSON already.
  final Object? Function(Object? value)? toJson;

  /// The JSON form of [value].
  Object? json(Object? value) => toJson == null ? value : toJson!(value);
}
