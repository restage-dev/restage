import 'dart:async';

import 'package:meta/meta.dart';

/// How a caller names its selectors, so a shared sentence points at the
/// argument that caller actually has.
@experimental
enum SelectorSyntax {
  /// The `restage` command line.
  cli(
    organization: '--organization <slug>',
    plane: '--plane <sandbox|live>, or set `plane` in restage_config.yaml',
    signIn: 'Run `restage login` to refresh it.',
  ),

  /// The Restage MCP server.
  mcp(
    organization: 'organizationId',
    plane: 'runtimePlane: sandbox or live',
    signIn: 'Sign in again with restage_login.',
  );

  const SelectorSyntax({
    required this.organization,
    required this.plane,
    required this.signIn,
  });

  /// How this caller names the organization.
  final String organization;

  /// How this caller names the runtime plane.
  final String plane;

  /// What this caller does to replace a stale credential.
  final String signIn;
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
