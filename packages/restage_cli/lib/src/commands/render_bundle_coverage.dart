import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:restage_cli/src/api/render_bundle_api.dart';
import 'package:restage_cli/src/api/render_bundle_coverage_sentence.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/credentials/credential.dart';
import 'package:restage_cli/src/publication/publication_assembler.dart';

/// The app widget libraries a set of publications draws with, by namespace,
/// at the newest capability version any of them needs.
Map<String, int> requiredAppLibraries(
  Iterable<AssembledSurfacePublication> assembled,
) {
  final required = <String, int>{};
  for (final publication in assembled) {
    for (final library in publication.payload.requiredLibraries) {
      final held = required[library.namespace];
      if (held == null || held < library.minVersion) {
        required[library.namespace] = library.minVersion;
      }
    }
  }
  return required;
}

/// Tells the user when the dashboard's build of [app] cannot draw what the
/// surfaces just pushed use. Says nothing when no surface uses app widgets.
Future<void> reportRenderBundleCoverage({
  required RestageApi api,
  required Uri apiEndpoint,
  required Credential credential,
  required List<AssembledSurfacePublication> assembled,
  required String project,
  required String app,
  required String environment,
  required int organizationId,
  required StringSink stdout,
  required StringSink stderr,
}) async {
  final required = requiredAppLibraries(assembled);
  if (required.isEmpty) return;
  final bundles = RenderBundleApi(
    rpc: api,
    apiEndpoint: apiEndpoint,
    credential: credential,
  );
  final RenderBundleHeadDiscovery? head;
  try {
    final heads = await bundles.listHeads(
      project: project,
      app: app,
      organizationId: organizationId,
    );
    head = heads
        .where((candidate) => candidate.head == environment)
        .firstOrNull;
  } on RenderBundleUploadException {
    stderr.writeln(
      "Could not check whether the dashboard's build of $app covers the "
      'widgets these surfaces use.',
    );
    return;
  } finally {
    bundles.close();
  }
  final sentence = renderBundleCoverageSentence(
    required: required,
    headVersion: head?.version,
    registered: head?.libraries ?? const {},
    surfaceCount: assembled.length,
    app: app,
    environment: environment,
  );
  if (sentence != null) stdout.writeln(sentence);
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
}) async {
  stdout.writeln('Pushing the build of $app to $environment first.');
  final runner = CommandRunner<int>('restage', '')..addCommand(buildCommand());
  final code = await runner.run(<String>[
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
  return code ?? 1;
}
