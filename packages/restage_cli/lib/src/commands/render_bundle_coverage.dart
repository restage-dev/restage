import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta/meta.dart';
import 'package:restage_cli/src/api/render_bundle_api.dart';
import 'package:restage_cli/src/api/render_bundle_coverage_sentence.dart';
import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/commands/target_resolution.dart';
import 'package:restage_cli/src/publication/publication_assembler.dart';
import 'package:restage_shared/restage_shared.dart';

/// Tells the user when the environment's build of [app] cannot draw the app
/// widgets the surfaces just pushed use. Says nothing when none use any.
Future<void> reportRenderBundleCoverage({
  required RestageApi api,
  required List<AssembledSurfacePublication> assembled,
  required String project,
  required String app,
  required String environment,
  required ResolvedEnvironmentTargetContext target,
  required StringSink stdout,
  required StringSink stderr,
}) async {
  final surfaces = <(Surface, String)>[
    for (final publication in assembled)
      if (publication.payload.requiredLibraries.isNotEmpty)
        (
          publication.entry.publication.surface,
          publication.entry.publication.slug,
        ),
  ];
  if (surfaces.isEmpty) return;
  try {
    final sentence = await _coverageSentence(
      api: api,
      project: project,
      app: app,
      surfaces: surfaces,
      environment: environment,
      environmentTargetId: target.target.environmentTargetId,
      runtimePlane: target.target.runtimePlane,
      organizationId: target.organizationId,
    );
    if (sentence != null) stdout.writeln(sentence);
  } on RenderBundleUploadException {
    stderr.writeln(
      "Could not check whether the dashboard's build of $app covers the "
      'widgets these surfaces use.',
    );
  }
}

/// What a draft push adds when the environment's build cannot draw the
/// surface's app widgets, or null. A refused read adds nothing.
@experimental
Future<String?> draftCoverageNotice({
  required RestageApi api,
  required String project,
  required String app,
  required Surface surfaceType,
  required String surfaceSlug,
  required String environment,
  required int? environmentTargetId,
  required RuntimePlane? runtimePlane,
  required int? organizationId,
}) async {
  try {
    return await _coverageSentence(
      api: api,
      project: project,
      app: app,
      surfaces: [(surfaceType, surfaceSlug)],
      environment: environment,
      environmentTargetId: environmentTargetId,
      runtimePlane: runtimePlane,
      organizationId: organizationId,
    );
  } on RenderBundleUploadException {
    return null;
  }
}

/// Asks the server whether the environment's build covers each surface, and
/// words the combined answer.
Future<String?> _coverageSentence({
  required RestageApi api,
  required String project,
  required String app,
  required List<(Surface, String)> surfaces,
  required String environment,
  required int? environmentTargetId,
  required RuntimePlane? runtimePlane,
  required int? organizationId,
}) async {
  final bundles = RenderBundleApi(rpc: api);
  try {
    final required = <String, int>{};
    var surfaceCount = 0;
    RenderBundleCoverageDiscovery? last;
    for (final (type, slug) in surfaces) {
      final coverage = last = await bundles.coverage(
        project: project,
        app: app,
        surfaceType: type,
        surfaceSlug: slug,
        environment: environment,
        environmentTargetId: environmentTargetId,
        runtimePlane: runtimePlane,
        organizationId: organizationId,
      );
      if (coverage.required.isNotEmpty) surfaceCount++;
      for (final entry in coverage.required.entries) {
        final held = required[entry.key];
        if (held == null || held < entry.value) {
          required[entry.key] = entry.value;
        }
      }
    }
    return renderBundleCoverageSentence(
      required: required,
      headVersion: last?.headVersion,
      registered: last?.registered ?? const {},
      surfaceCount: surfaceCount,
      app: app,
      environment: environment,
    );
  } finally {
    bundles.close();
  }
}

/// Builds the `build` command a push runs first under `--build`.
typedef BuildCommandFactory = Command<int> Function();

/// Pushes the app's build to [environment] before the surfaces go.
Future<int> pushBuildFirst({
  required BuildCommandFactory buildCommand,
  required String project,
  required String app,
  required String? organization,
  required String environment,
  required Directory directory,
  required bool recordGit,
  required StringSink stdout,
  required StringSink stderr,
}) async {
  stdout.writeln('Pushing the build of $app to $environment first.');
  final runner = CommandRunner<int>('restage', '')..addCommand(buildCommand());
  int? code;
  try {
    code = await runner.run(<String>[
      'build',
      'push',
      '--project',
      project,
      '--app',
      app,
      if (organization != null) ...<String>['--organization', organization],
      '--env',
      environment,
      '-C',
      directory.path,
      if (recordGit) '--record-git',
    ]);
  } on UsageException catch (error) {
    stderr.writeln(error.message);
    code = 1;
  }
  if (code != 0) {
    stderr.writeln('The build push failed, so nothing else was pushed.');
  }
  return code ?? 1;
}
