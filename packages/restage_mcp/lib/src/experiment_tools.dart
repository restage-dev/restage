import 'experiment_apply_tool.dart';
import 'tool_support.dart';

/// Experiment authoring tools, available by default.
List<ToolEntry> experimentTools(ToolContext ctx) => [
  liveGuarded(
    ctx,
    (experimentApplyTool, (request) => handleExperimentApply(ctx, request)),
    changesLive: changesLiveExperiment,
    planeOf: declaredPlane,
  ),
];
