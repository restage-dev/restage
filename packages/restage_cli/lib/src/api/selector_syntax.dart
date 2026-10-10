import 'dart:async';

import 'package:meta/meta.dart';

/// How a caller names its selectors, so a shared sentence points at the
/// argument that caller actually has.
@experimental
enum SelectorSyntax {
  /// The `restage` command line.
  cli(
    organization: '--organization <slug>',
    project: '--project <slug>',
    app: '--app <slug>',
    environment: '--env <slug>',
    plane: '--plane <sandbox|live>, or set `plane` in restage_config.yaml',
    signIn: 'Run `restage login` to refresh it.',
    surfaceType: '--type <type>',
    run: 'Run',
  ),

  /// The full-screen console, whose command line runs `/restage ...`.
  console(
    organization: '--organization <slug>',
    project: '--project <slug>',
    app: '--app <slug>',
    environment: '--env <slug>',
    plane: '--plane <sandbox|live>, or set `plane` in restage_config.yaml',
    signIn: 'Run `restage login` in a terminal to refresh it.',
    surfaceType: '--type <type>',
    run: 'Type',
  ),

  /// The Restage MCP server.
  mcp(
    organization: 'organizationId',
    project: 'projectSlug',
    app: 'appSlug',
    environment: 'environmentSlug',
    plane: 'runtimePlane: sandbox or live',
    signIn: 'Sign in again with restage_login.',
    surfaceType: 'surfaceType',
    run: 'Call',
  );

  const SelectorSyntax({
    required this.organization,
    required this.project,
    required this.app,
    required this.environment,
    required this.plane,
    required this.signIn,
    required this.surfaceType,
    required this.run,
  });

  /// How this caller names the organization.
  final String organization;

  /// How this caller names the project.
  final String project;

  /// How this caller names the app.
  final String app;

  /// How this caller names the environment.
  final String environment;

  /// How this caller names the runtime plane.
  final String plane;

  /// What this caller does to replace a stale credential.
  final String signIn;

  /// How this caller names a surface type.
  final String surfaceType;

  /// The verb that starts a [command] sentence.
  final String run;

  /// [next] as this caller runs it: a `restage` command line, or a tool call.
  String command(FollowUp next) {
    final args = [
      for (final arg in next.args)
        if (this == mcp ? !arg.cliOnly : !arg.mcpOnly) arg,
    ];
    final line =
        'restage ${next.cli}${[for (final arg in args)
          if (arg.flag == null) ' ${arg.value}' else if (arg.value == null) ' --${arg.flag}' else ' --${arg.flag} ${arg.value}'].join()}';
    return switch (this) {
      cli => '`$line`',
      console => '`/$line`',
      mcp =>
        args.isEmpty
            ? next.tool
            : '${next.tool} with ${[for (final arg in args) '${arg.key}: ${arg.value ?? true}'].join(', ')}',
    };
  }
}

/// One argument of a [FollowUp].
@experimental
@immutable
class FollowUpArg {
  /// An argument the CLI takes as `--flag value`, or as the positional
  /// argument when [flag] is null. A null [value] is a boolean flag.
  const FollowUpArg(
    this.key,
    this.value, {
    this.flag,
    this.cliOnly = false,
    this.mcpOnly = false,
  });

  /// The MCP argument name.
  final String key;

  /// The value, or null for a flag that is set.
  final String? value;

  /// The CLI flag, or null for the positional argument.
  final String? flag;

  /// Whether only the CLI names it.
  final bool cliOnly;

  /// Whether only a tool call names it.
  final bool mcpOnly;
}

/// Sets a project up for Restage.
const initFollowUp = FollowUp('init', 'restage_init');

/// Signs in.
const loginFollowUp = FollowUp('login', 'restage_login');

/// The sentence for a caller with no stored credential.
String notSignedInSentence([SelectorSyntax? syntax]) {
  syntax ??= currentSelectorSyntax;
  return 'Not signed in. ${syntax.run} ${syntax.command(loginFollowUp)}.';
}

/// The sentence for a call that names no project and app.
String noProjectContextSentence([SelectorSyntax? syntax]) {
  syntax ??= currentSelectorSyntax;
  return 'No project / app context. ${syntax.run} '
      '${syntax.command(initFollowUp)}, or pass ${syntax.project} and '
      '${syntax.app}.';
}

/// The sentence for a call that resolved no project or app: the key the
/// project's restage_config.yaml lacks, or [noProjectContextSentence] when
/// there is no config.
String missingProjectContextSentence({
  required bool hasConfig,
  required bool projectMissing,
  SelectorSyntax? syntax,
}) {
  syntax ??= currentSelectorSyntax;
  if (!hasConfig) return noProjectContextSentence(syntax);
  return missingConfigKeySentence(projectMissing ? 'project' : 'app', syntax);
}

/// The sentence for a restage_config.yaml that does not set [key], which is
/// `project` or `app`.
String missingConfigKeySentence(String key, [SelectorSyntax? syntax]) {
  syntax ??= currentSelectorSyntax;
  final argument = key == 'app' ? syntax.app : syntax.project;
  return 'restage_config.yaml has no `$key`. Add `$key: <slug>` to it, or '
      'pass $argument.';
}

/// The sentence for a call that names no environment.
String environmentRequiredSentence([SelectorSyntax? syntax]) {
  syntax ??= currentSelectorSyntax;
  return 'Required: ${syntax.environment}. Set `defaultEnvironment` in '
      'restage_config.yaml, or pass ${syntax.environment}.';
}

/// A command to run next, named for whichever caller reads it.
@experimental
@immutable
class FollowUp {
  /// Construct a follow-up for the CLI command [cli] and the MCP [tool].
  const FollowUp(this.cli, this.tool, [this.args = const []]);

  /// The CLI command path, such as `surface publish`.
  final String cli;

  /// The MCP tool name.
  final String tool;

  /// The arguments, in CLI order.
  final List<FollowUpArg> args;
}

final Object _selectorSyntaxKey = Object();

/// Zone values that word sentences rendered inside the zone for [syntax].
@experimental
Map<Object?, Object?> selectorSyntaxZoneValues(SelectorSyntax syntax) =>
    <Object?, Object?>{_selectorSyntaxKey: syntax};

/// The wording in effect: [SelectorSyntax.cli] unless the running zone set
/// another through [selectorSyntaxZoneValues].
@experimental
SelectorSyntax get currentSelectorSyntax =>
    Zone.current[_selectorSyntaxKey] as SelectorSyntax? ?? SelectorSyntax.cli;

/// A selector that names no single target, with the sentence to show.
@experimental
class TargetSelectionException implements Exception {
  /// Construct with the user-facing [message].
  const TargetSelectionException(this.message);

  /// The user-facing sentence.
  final String message;

  @override
  String toString() => message;
}
