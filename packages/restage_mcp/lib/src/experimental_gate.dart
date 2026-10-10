import 'dart:io' as io;

import 'package:restage_cli/api.dart';

import 'api_runner.dart';
import 'canonical_mutation_tool.dart';
import 'experiment_activation_tool.dart';
import 'experiment_apply_tool.dart';
import 'serving_record_rebuild_tool.dart';
import 'tool_support.dart';

/// Environment variable that opts a server in to experimental tools.
///
/// Set it to `1`, `true`, or `yes` (case-insensitive) to enable them.
const experimentalOptInVariable = 'RESTAGE_EXPERIMENTAL';

const _truthy = <String>{'1', 'true', 'yes'};

/// Whether experimental tools should be registered on this server.
///
/// A tool that is not registered does not appear in the tool list, which is
/// the only inventory an MCP client consults before calling. That is the
/// point: an experimental tool whose route is not served yet must not be
/// advertised as available.
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
List<ToolEntry> experimentTools(
  ToolContext ctx, {
  ExperimentActivationApi? activation,
}) => [
  liveGuarded(ctx, (
    canonicalMutationTool,
    (request) => handleCanonicalMutation(ctx, request),
  ), planeOf: declaredPlane),
  liveGuarded(
    ctx,
    (experimentApplyTool, (request) => handleExperimentApply(ctx, request)),
    changesLive: changesLiveExperiment,
    planeOf: declaredPlane,
  ),
  liveGuarded(
    ctx,
    (
      servingRecordRebuildTool,
      (request) => handleServingRecordRebuild(ctx, request),
    ),
    changesLive: (request) => request.optBool('readinessOnly') != true,
    planeOf: declaredPlane,
  ),
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
