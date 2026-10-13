import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:meta/meta.dart';
import 'package:restage_cli/src/render_bundles/push_target.dart';
import 'package:restage_cli/src/api/auth_api.dart';
import 'package:restage_cli/src/api/render_bundle_api.dart';
import 'package:restage_cli/src/api/render_bundle_coverage_sentence.dart';
import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/selector_syntax.dart';
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
    String? sentence({required bool ownBuildCovers}) =>
        renderBundleCoverageSentence(
          required: required,
          headVersion: last?.headVersion,
          registered: last?.registered ?? const {},
          surfaceCount: surfaceCount,
          app: app,
          environment: environment,
          ownBuildCovers: ownBuildCovers,
        );
    if (sentence(ownBuildCovers: false) == null) return null;
    return sentence(
      ownBuildCovers: await _ownBuildCovers(
        api: api,
        bundles: bundles,
        project: project,
        app: app,
        organizationId: organizationId,
        required: required,
      ),
    );
  } finally {
    bundles.close();
  }
}

/// Whether the signed-in user's own build of [app] registers [required]. A
/// key has no build of its own, and a failed read counts as not covering.
Future<bool> _ownBuildCovers({
  required RestageApi api,
  required RenderBundleApi bundles,
  required String project,
  required String app,
  required int? organizationId,
  required Map<String, int> required,
}) async {
  try {
    final me = (await AuthApi(api).whoami())?.id;
    if (me == null) return false;
    final heads = await bundles.listHeads(
      project: project,
      app: app,
      organizationId: organizationId,
    );
    final own = heads.where((head) => head.ownerUserInfoId == me).firstOrNull;
    if (own == null) return false;
    return required.entries.every(
      (entry) => (own.libraries[entry.key] ?? 0) >= entry.value,
    );
  } on Object {
    return false;
  }
}

/// Builds the `build` command a push runs first under `--build`.
typedef BuildCommandFactory = Command<int> Function();

/// Pushes the app's build to [environment] before the surfaces go. A failed
/// build does not stop them: the build only feeds dashboard previews.
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
  String? flutterRoot,
  int? organizationId,
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
      if (organizationId != null) '--organization-id=$organizationId',
      '--env',
      environment,
      '-C',
      directory.path,
      if (recordGit) '--record-git',
      if (flutterRoot != null) ...<String>['--flutter-root', flutterRoot],
    ]);
  } on UsageException catch (error) {
    stderr.writeln(error.message);
    code = 1;
  }
  return code ?? 1;
}

/// Says what is and is not live after a push whose build failed.
void reportBuildNotPushed({
  required String app,
  required String environment,
  required bool surfacesPushed,
  required StringSink stderr,
}) {
  final syntax = currentSelectorSyntax;
  final retry =
      '${syntax.run.toLowerCase()} '
      '${syntax.command(pushBuildFollowUp(environment))}';
  stderr.writeln(
    '${surfacesPushed ? 'The surfaces were pushed, but the build of $app '
              'was not.' : 'The build of $app was not pushed either.'} '
    'Devices render surfaces with the widgets compiled into the app, so '
    'they do not need it; the dashboard cannot preview app widgets until a '
    'build of $app reaches $environment. Fix the build error above, then '
    '$retry.',
  );
}
