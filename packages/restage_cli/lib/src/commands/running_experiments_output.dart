import 'package:restage_cli/src/api/running_experiment_sentences.dart';
import 'package:restage_cli/src/api/surface_models.dart';
import 'package:restage_cli/src/commands/lifecycle_support.dart';

/// Writes what each running experiment means for a publish at [target] to
/// [sink], with the command that ends it at the same target.
void writeRunningExperiments(
  StringSink sink,
  List<SurfaceRunningExperiment> experiments, {
  required LifecycleContext target,
  bool preview = false,
}) {
  for (final experiment in experiments) {
    sink
      ..writeln(runningExperimentSentence(experiment, preview: preview))
      ..writeln(
        concludeExperimentSentence(
          experiment,
          project: target.project,
          app: target.app,
          environment: target.environment,
          organizationSlug: target.organizationSlug,
          organizationId: target.organizationId,
          environmentTargetId: target.environmentTargetId,
          runtimePlane: target.runtimePlane,
          planeIsImplicit: target.planeIsImplicit,
        ),
      );
  }
}
