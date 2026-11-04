import 'package:restage_cli/src/api/discovery_models.dart' show RuntimePlane;
import 'package:restage_cli/src/api/selector_syntax.dart';
import 'package:restage_cli/src/api/surface_models.dart';

// Mirrored verbatim by another client; keep the two identical.
/// What a publish means for [experiment], or with [preview] what it would
/// mean.
String runningExperimentSentence(
  SurfaceRunningExperiment experiment, {
  bool preview = false,
}) {
  final name = experiment.experimentLabel == null
      ? 'Experiment ${experiment.experimentId}'
      : 'Experiment "${experiment.experimentLabel}" '
            '(${experiment.experimentId})';
  final enrolled = experiment.audienceLabel == null
      ? 'Devices its audience admits'
      : 'Devices in its "${experiment.audienceLabel}" audience';
  final gets = preview ? 'would get this version' : 'gets this version now';
  return '$name is running on this surface. $enrolled keep their arm\'s '
      'version until it ends; every other device $gets.';
}

/// How to end [experiment] at the target the publish named, as the CLI
/// command or the MCP call the running caller makes. Arguments left null are
/// left out; [planeIsImplicit] leaves the plane to the CLI's config.
String concludeExperimentSentence(
  SurfaceRunningExperiment experiment, {
  required String project,
  required String app,
  required String environment,
  String? organizationSlug,
  int? organizationId,
  int? environmentTargetId,
  RuntimePlane? runtimePlane,
  bool planeIsImplicit = false,
  SelectorSyntax? syntax,
}) {
  syntax ??= currentSelectorSyntax;
  final id = experiment.experimentId;
  final ordinal = '${experiment.lifecycleOrdinal}';
  final command = syntax.command(
    FollowUp('experiment conclude', 'restage_experiment_apply', [
      const FollowUpArg('operation', 'concludeExperiment', mcpOnly: true),
      FollowUpArg(
        'payload',
        '{"experimentId": "$id", "expectedLifecycleOrdinal": $ordinal}',
        mcpOnly: true,
      ),
      FollowUpArg('experimentId', id, flag: 'experiment-id', cliOnly: true),
      FollowUpArg(
        'expectedLifecycleOrdinal',
        ordinal,
        flag: 'expected-lifecycle-ordinal',
        cliOnly: true,
      ),
      if (organizationSlug != null)
        FollowUpArg(
          'organization',
          organizationSlug,
          flag: 'organization',
          cliOnly: true,
        ),
      if (organizationId != null)
        FollowUpArg('organizationId', '$organizationId', mcpOnly: true),
      FollowUpArg('projectSlug', project, flag: 'project'),
      FollowUpArg('appSlug', app, flag: 'app'),
      FollowUpArg('environmentSlug', environment, flag: 'env'),
      if (environmentTargetId != null)
        FollowUpArg(
          'environmentTargetId',
          '$environmentTargetId',
          mcpOnly: true,
        ),
      if (runtimePlane != null)
        FollowUpArg(
          'runtimePlane',
          runtimePlane.wireName,
          flag: 'plane',
          mcpOnly: planeIsImplicit,
        ),
    ]),
  );
  return 'Try $command to end it.';
}
