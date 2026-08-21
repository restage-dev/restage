import 'dart:io';

import 'package:args/args.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/surface_publication_api.dart';
import 'package:restage_cli/src/commands/publication_upload.dart';
import 'package:restage_cli/src/commands/target_resolution.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_cli/src/publication/publication_assembler.dart';
import 'package:restage_cli/src/publication/publication_manifest.dart';
import 'package:restage_shared/restage_shared.dart';

/// Declare the `--all` flag shared by every publish command.
///
/// [noun] names what is published ("surface", "paywall").
void addPublishAllOption(ArgParser parser, {required String noun}) =>
    parser.addFlag(
      'all',
      negatable: false,
      help:
          'Publish every $noun the given .dart file produced, instead of '
          'choosing one. A flow counts the file of every screen it contains, '
          'so this can be wider than what the file declares.',
    );

/// Whether [argument] addresses a Dart source file rather than a surface id.
///
/// A `.dart` suffix selects file resolution. Nothing forbids an id ending in
/// `.dart` — ids are only required to be path-safe — so such an id is not
/// addressable this way and has to be renamed. That is the whole cost of
/// keeping the rule one a developer can predict without consulting anything.
bool _isDartSourceArgument(String argument) => argument.endsWith('.dart');

/// Resolve which generated publications one publish invocation addresses.
///
/// The id stays the canonical key; a `.dart` path is a convenience resolved
/// through the generated manifest. A path selects everything the manifest
/// ATTRIBUTES to that file, which is wider than what the file declares: name
/// a screen inside a flow and you select the flow that publishes it.
///
/// When that is more than one surface this asks rather than guesses:
/// interactively where there is a terminal, and with a listing of runnable
/// commands where there is not, so a CI run fails with instructions instead
/// of blocking on a prompt.
///
/// [pathSourceKind] narrows a path match, so a file that produced an
/// unrelated surface alongside the wanted one does not abort the run. The id
/// lane deliberately does not take it: an id names one publication, and
/// telling the developer that exact publication is the wrong kind beats
/// telling them nothing matched.
///
/// Returns null after writing a user-facing message to [stderr] when the
/// caller should exit non-zero. Throws [PublicationManifestException] for a
/// manifest that cannot answer the question at all.
Future<List<SurfacePublicationManifestEntry>?> resolvePublicationEntries({
  required LoadedSurfacePublicationManifest manifest,
  required String argument,
  required bool all,
  required Surface? type,
  SurfaceSourceKind? pathSourceKind,
  required Interactive interactive,
  required StringSink stderr,
  required String commandLine,
}) async {
  if (!_isDartSourceArgument(argument)) {
    if (all) {
      stderr.writeln(
        '--all publishes every surface a .dart file produced. "$argument" is '
        'a surface id, which already names exactly one. Drop --all, or pass '
        'the file the surface is declared in.',
      );
      return null;
    }
    return <SurfacePublicationManifestEntry>[
      manifest.select(slug: argument, type: type),
    ];
  }

  final matches = manifest.selectByPath(
    path: argument,
    type: type,
    sourceKind: pathSourceKind,
  );
  if (all || matches.length == 1) return matches;

  if (!interactive.isInteractive) {
    final countBySlug = <String, int>{};
    for (final entry in matches) {
      countBySlug.update(
        entry.publication.slug,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    stderr.writeln(
      '$argument produced ${matches.length} surfaces. Name the one you want, '
      'or publish them all:',
    );
    for (final entry in matches) {
      // A slug is unique only within a surface category, so a slug that
      // repeats here needs --type to name one surface. Printing a command
      // that would itself fail as ambiguous is worse than printing nothing.
      final needsType = countBySlug[entry.publication.slug]! > 1;
      stderr.writeln(
        '  $commandLine ${entry.publication.slug}'
        '${needsType ? ' --type ${entry.publication.surface.wireName}' : ''}'
        '   # ${entry.publication.surface.wireName}',
      );
    }
    stderr.writeln('  $commandLine $argument --all');
    return null;
  }

  const publishAll = -1;
  final choice = await interactive.select<int>(
    '$argument produced ${matches.length} surfaces. Which do you want to '
    'publish?',
    <({String label, int value})>[
      for (var index = 0; index < matches.length; index += 1)
        (
          label:
              '${matches[index].publication.surface.wireName}/'
              '${matches[index].publication.slug}',
          value: index,
        ),
      (
        label: 'all ${matches.length} surfaces produced by $argument',
        value: publishAll,
      ),
    ],
  );
  return choice == publishAll
      ? matches
      : <SurfacePublicationManifestEntry>[matches[choice]];
}

/// Publish [assembled] in order against one already-resolved target.
///
/// There is no batch publish, so a run over several surfaces is not atomic.
/// It stops at the first failure and reports exactly how far it got rather
/// than leaving that to be reconstructed from the surfaces' live state.
///
/// Returns the process exit code. [noun] names what is being published in the
/// output; [onApiException] renders the command's typed-error handling.
///
/// Each publication goes out through the operation its own optional
/// measurement candidate selects, so a measurement-bound surface takes the
/// bound operation and finalizes its local bundled profile under
/// [packageRoot], while an ordinary one takes the plain publish.
Future<int> runPublishRun({
  required RestageApi api,
  required List<AssembledSurfacePublication> assembled,
  required Directory packageRoot,
  required String project,
  required String app,
  required String environment,
  required ResolvedEnvironmentTargetContext target,
  required String noun,
  required String Function(AssembledSurfacePublication) describe,
  required int Function(RestageApiException) onApiException,
  required StringSink stdout,
  required StringSink stderr,
}) async {
  final publisher = SurfacePublicationApi(api);
  for (var index = 0; index < assembled.length; index += 1) {
    final publication = assembled[index];
    int stopWith(int code) {
      _reportPartialRun(assembled, publishedCount: index, stderr: stderr);
      return code;
    }

    try {
      final result = await publishAssembledSurfacePublication(
        api: publisher,
        assembled: publication,
        packageRoot: packageRoot,
        project: project,
        app: app,
        environment: environment,
        environmentTargetId: target.target.environmentTargetId,
        runtimePlane: target.target.runtimePlane,
        organizationId: target.organizationId,
      );
      stdout.writeln(
        '${describe(publication)} to $environment; ${result.stateDescription}',
      );
    } on RestageApiException catch (error) {
      return stopWith(onApiException(error));
    } on SocketException {
      stderr.writeln('Could not publish the generated $noun.');
      return stopWith(2);
    } on FormatException {
      stderr.writeln('Could not decode the publication response.');
      return stopWith(2);
    } on MeasurementBundledProfileFinalizeException {
      // The backend committed this publication; only the local bundled
      // profile did not land, so the run stops without retrying the upload.
      stderr.writeln(
        'The $noun was published, but its Measurement bundle profile could '
        'not be written.',
      );
      return stopWith(2);
    }
  }
  if (assembled.length > 1) {
    stdout.writeln('Published ${assembled.length} ${noun}s to $environment.');
  }
  return 0;
}

/// Report how far a multi-surface publish run got before it stopped.
void _reportPartialRun(
  List<AssembledSurfacePublication> assembled, {
  required int publishedCount,
  required StringSink stderr,
}) {
  if (assembled.length == 1) return;
  final failed = assembled[publishedCount].entry.publication.slug;
  final skipped = assembled
      .skip(publishedCount + 1)
      .map((publication) => publication.entry.publication.slug)
      .join(', ');
  stderr.writeln(
    'Published $publishedCount of ${assembled.length}; failed on $failed'
    '${skipped.isEmpty ? '' : '; not attempted: $skipped'}.',
  );
}
