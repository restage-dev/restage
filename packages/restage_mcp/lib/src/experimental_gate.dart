import 'dart:io' as io;

import 'package:restage_cli/api.dart';

import 'canonical_mutation_tool.dart';
import 'experiment_activation_tool.dart';
import 'tool_support.dart';

/// Environment variable that opts a server in to experimental tools.
///
/// Set it to `1`, `true`, or `yes` (case-insensitive) to enable them.
const experimentalOptInVariable = 'RESTAGE_EXPERIMENTAL';

const _truthy = <String>{'1', 'true', 'yes'};

/// Whether experimental tools should be registered on this server.
///
/// This opt-in covers low-level canonical mutation and injected activation
/// tools. Semantic experiment operations are available by default.
///
/// [environment] defaults to the real process environment; tests pass their
/// own map so the opt-in can be exercised without mutating the process.
bool experimentalToolsEnabled([Map<String, String>? environment]) {
  final value =
      (environment ?? io.Platform.environment)[experimentalOptInVariable];
  return value != null && _truthy.contains(value.trim().toLowerCase());
}

/// The experimental tools, bound to [ctx]; the activation tool only when an
/// [activation] authority is supplied.
List<ToolEntry> experimentalTools(
  ToolContext ctx, {
  ExperimentActivationApi? activation,
}) => [
  liveGuarded(ctx, (
    canonicalMutationTool,
    (request) => handleCanonicalMutation(ctx, request),
  ), planeOf: declaredPlane),
  if (activation != null)
    liveGuarded(
      ctx,
      (
        experimentActivationTool,
        (request) =>
            handleExperimentActivation(request: request, api: activation),
      ),
      changesLive: (request) => activationPlane(request) != null,
      planeOf: activationPlane,
    ),
];
