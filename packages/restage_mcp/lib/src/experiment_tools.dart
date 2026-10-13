import 'api_runner.dart';
import 'experiment_apply_tool.dart';
import 'serving_record_rebuild_tool.dart';
import 'tool_support.dart';

/// Experiment authoring and serving-record tools, available by default.
List<ToolEntry> experimentTools(ToolContext ctx) => [
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
];
