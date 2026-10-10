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

/// Declare the `--all` flag shared by every push command.
///
/// [noun] names what is pushed ("surface", "paywall").
void addPushAllOption(ArgParser parser, {required String noun}) =>
    parser.addFlag(
      'all',
      negatable: false,
      help:
          'Push every $noun the given .dart file produced, instead of '
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

/// Selects generated publications by canonical ID or `.dart` source path.
/// A path includes attributed publications, such as a flow containing a screen.
///
/// Multiple matches prompt in a terminal or print runnable commands in CI.
/// [pathSourceKind] filters path matches only; ID selection retains type errors.
/// Returns null after writing an error to [stderr], or throws
/// [PublicationManifestException] when the manifest cannot resolve selection.
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
        '--all pushes every surface a .dart file produced. "$argument" is '
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
      'or push them all:',
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

  const pushAll = -1;
  final choice = await interactive.select<int>(
    '$argument produced ${matches.length} surfaces. Which do you want to '
    'push?',
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
        value: pushAll,
      ),
    ],
  );
  return choice == pushAll
      ? matches
      : <SurfacePublicationManifestEntry>[matches[choice]];
}

/// Pushes [assembled] in order, stopping at the first failure.
/// Returns an exit code and reports partial progress; uploads are not atomic.
///
/// Each publication selects its plain or measurement-bound upload operation.
/// Bound uploads finalize the bundled profile under [packageRoot].
/// [onPushed] runs after each accepted upload. [noun] labels the output;
/// [onApiException] renders typed errors.
Future<int> runPush({
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
  Future<void> Function(
    AssembledSurfacePublication publication,
    SurfacePublicationUploadResult result,
  )?
  onPushed,
}) async {
  final uploader = SurfacePublicationApi(api);
  // Pushed surfaces whose stored revision is not the live one.
  final pending = <String>[];
  for (var index = 0; index < assembled.length; index += 1) {
    final publication = assembled[index];
    int stopWith(int code) {
      _reportPartialRun(assembled, pushedCount: index, stderr: stderr);
      return code;
    }

    try {
      final result = await publishAssembledSurfacePublication(
        api: uploader,
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
      if (result.activeRevision != result.storedRevision) {
        pending.add(publication.entry.publication.slug);
      }
      await onPushed?.call(publication, result);
    } on RestageApiException catch (error) {
      return stopWith(onApiException(error));
    } on SocketException {
      stderr.writeln('Could not push the generated $noun.');
      return stopWith(2);
    } on FormatException {
      stderr.writeln('Could not decode the publication response.');
      return stopWith(2);
    } on MeasurementBundledProfileFinalizeException {
      // The backend committed this publication; only the local bundled
      // profile did not land, so the run stops without retrying the upload.
      stderr.writeln(
        'The $noun was pushed, but its Measurement bundle profile could '
        'not be written.',
      );
      return stopWith(2);
    }
  }
  if (assembled.length > 1) {
    stdout.writeln('Pushed ${assembled.length} ${noun}s to $environment.');
  }
  if (pending.isEmpty) return 0;
  const publish = 'restage surface publish';
  final plane = planeFlag(
    target.target.runtimePlane,
    implicit: target.planeIsImplicit,
  );
  if (assembled.length == 1) {
    stdout.writeln(
      'Not live yet. Run `$publish ${pending.single}$plane` '
      'to publish it.',
    );
  } else {
    stdout.writeln(
      'Not live yet: ${pending.join(', ')}. Run `$publish <id>'
      '$plane` to publish one.',
    );
  }
  return 0;
}

/// Report how far a multi-surface push run got before it stopped.
void _reportPartialRun(
  List<AssembledSurfacePublication> assembled, {
  required int pushedCount,
  required StringSink stderr,
}) {
  if (assembled.length == 1) return;
  final failed = assembled[pushedCount].entry.publication.slug;
  final skipped = assembled
      .skip(pushedCount + 1)
      .map((publication) => publication.entry.publication.slug)
      .join(', ');
  stderr.writeln(
    'Pushed $pushedCount of ${assembled.length}; failed on $failed'
    '${skipped.isEmpty ? '' : '; not attempted: $skipped'}.',
  );
}
