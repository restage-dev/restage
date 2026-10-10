import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/api/surface_api.dart';
import 'package:restage_cli/src/commands/authed.dart';
import 'package:restage_cli/src/commands/lifecycle_support.dart';
import 'package:restage_cli/src/commands/live_guard.dart';
import 'package:restage_cli/src/commands/surface_identity.dart';
import 'package:restage_cli/src/commands/surface_measurement_review.dart';
import 'package:restage_cli/src/commands/surface_publish_operation.dart';
import 'package:restage_cli/src/config/restage_config.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_cli/src/operations/operation.dart';
import 'package:restage_cli/src/receipts/git_repository.dart';
import 'package:restage_cli/src/receipts/release_recorder.dart';
import 'package:restage_shared/restage_shared.dart';

/// Publish one pushed revision in one exact surface family.
///
/// The revision defaults to the latest one pushed to the target environment.
/// Standalone screens require the positive manifest contract version. Flow
/// graphs and specialized paywalls use their existing non-versioned lineage.
class SurfacePublishCommand extends Command<int> implements LiveGuardedCommand {
  /// Construct a publish command.
  SurfacePublishCommand({
    required StringSink stdout,
    required StringSink stderr,
    required Interactive interactive,
    SurfaceType? fixedSurfaceType,
    FileCredentialStore? credentialStore,
    http.Client? httpClient,
    GitProcessRunner? processRunner,
  }) : _io = CommandIo(
         stdout: stdout,
         stderr: stderr,
         interactive: interactive,
         credentialStore: credentialStore,
         httpClient: httpClient,
       ),
       _fixedType = fixedSurfaceType,
       _processRunner = processRunner {
    addLifecycleOptions(
      argParser,
      withType: fixedSurfaceType == null,
      withReason: false,
      withContractVersion: true,
      withSourceKind: true,
    );
    addSurfaceMeasurementReviewOptions(argParser);
    argParser
      ..addOption(
        'revision',
        help:
            'Pushed revision to publish. Defaults to the latest revision '
            'pushed to the target environment.',
      )
      ..addOption('pushed-revision', help: 'Alias for --revision.')
      ..addOption('version', help: 'Alias for --revision.')
      ..addOption(
        'reason',
        help: 'Audit reason for this change. Defaults to a generic reason.',
      )
      ..addFlag(
        'record-git',
        help:
            'Commit a release receipt naming the source the published '
            'revision was built from. Set `recordGit` in restage_config.yaml '
            'to make it the default for the project.',
      );
  }

  final CommandIo _io;
  final SurfaceType? _fixedType;
  final GitProcessRunner? _processRunner;

  @override
  String get name => 'publish';

  @override
  String get description =>
      'Publish a pushed revision in one exact surface family; defaults to '
      'the latest pushed revision.';

  @override
  Future<int> run() async {
    final slug = resolveSingleSlug(argResults: argResults, stderr: _io.stderr);
    if (slug == null) return 1;

    final identity = await resolveSurfaceLifecycleIdentity(
      argResults: argResults,
      fixedSurfaceType: _fixedType,
      slug: slug,
      stderr: _io.stderr,
    );
    if (identity == null) return 1;

    final explicit = _explicitRevision();
    if (!explicit.valid) return 1;

    final reasonFlag = (argResults?['reason'] as String?)?.trim();
    final reason = reasonFlag == null || reasonFlag.isEmpty
        ? kDefaultPublishReason
        : reasonFlag;

    // The repository is checked before anything reaches the server, so a
    // publication is never made with no way to record it.
    final directory = Directory(argResults?['directory'] as String? ?? '.');
    final loadedConfig = await loadRestageConfig(from: directory);
    final ReleaseRecorder? recorder;
    if (_recordGit(loadedConfig?.config)) {
      try {
        recorder = await ReleaseRecorder.open(
          projectRoot: loadedConfig?.source.parent ?? directory.absolute,
          processRunner: _processRunner,
        );
      } on ReleaseRecorderException catch (error) {
        _io.stderr.writeln(error.message);
        return 1;
      }
    } else {
      recorder = null;
    }

    return runAuthed(_io, argResults, OperationScope.target, (ctx) async {
      final target = ctx.target!;
      final confirmed = await confirmLiveChange(
        command: this,
        interactive: _io.interactive,
        stdout: _io.stdout,
        stderr: _io.stderr,
        runtimePlane: target.runtimePlane,
        impactLine:
            'Publish ${identity.surface.wireName} "$slug" at '
            '${explicit.revision == null ? 'the latest pushed revision' : 'r${explicit.revision}'} '
            'in ${target.environment} (live).',
      );
      if (!confirmed) return 1;
      final surfaces = SurfaceApi(ctx.api);
      final impact = await reviewSurfaceMeasurement(
        io: _io,
        arguments: argResults!,
        api: surfaces,
        target: target,
        identity: identity,
        operation: 'surfaceActivate',
        reason: reason,
        publishedRevision: explicit.revision,
      );
      if (impact.exitCode case final code?) return code;
      final (:recorded, publication: _) = await publishSurface(
        api: surfaces,
        identity: identity,
        at: target.family,
        revision: explicit.revision,
        reason: reason,
        measurementProceed: impact.proceed,
        record: recorder == null
            ? null
            : (recorder: recorder, target: target.resolved),
        stdout: _io.stdout,
        stderr: _io.stderr,
        onPublished: (published) {
          final (:family, :revision, :latest, :result) = published;
          if (latest) {
            _io.stdout.writeln(
              'Latest pushed revision for "$slug" in ${target.environment}: '
              'r$revision.',
            );
          }
          final sourceKind = result.sourceKind == null
              ? family.sourceKind
              : SurfaceSourceKind.fromWireName(result.sourceKind!);
          final active = result.activeRevisionAfter == null
              ? 'inactive'
              : 'r${result.activeRevisionAfter}';
          _io.stdout
            ..writeln(
              'Published "$slug" at r$revision in ${target.environment} '
              '(${describeFamily(sourceKind, result.contractVersion ?? family.contractVersion)}).',
            )
            ..writeln('Active revision: $active   frozen: ${result.frozen}')
            ..writeln(
              mountGuide(sourceKind, slug, mountName: result.mountName),
            );
        },
      );
      return recorded == false ? 2 : 0;
    });
  }

  /// Whether this invocation records a release receipt.
  bool _recordGit(RestageConfig? config) {
    final results = argResults;
    if (results != null && results.wasParsed('record-git')) {
      return results['record-git'] as bool;
    }
    return config?.recordGit ?? false;
  }

  /// The revision named on the command line, if any.
  ///
  /// A null revision alongside a true [valid] means no flag was passed and
  /// the server activates the newest pushed revision.
  ({bool valid, int? revision}) _explicitRevision() {
    final values = <String, String?>{
      '--revision': argResults?['revision'] as String?,
      '--pushed-revision': argResults?['pushed-revision'] as String?,
      '--version': argResults?['version'] as String?,
    };
    final provided = values.entries
        .where((entry) => entry.value != null && entry.value!.trim().isNotEmpty)
        .toList(growable: false);
    if (provided.isEmpty) return (valid: true, revision: null);
    final parsed = <String, int?>{
      for (final entry in provided)
        entry.key: int.tryParse(entry.value!.trim()),
    };
    if (parsed.values.any((value) => value == null || value < 1)) {
      _io.stderr.writeln(
        'Expected a positive integer for the revision to publish.',
      );
      return (valid: false, revision: null);
    }
    final distinct = parsed.values.toSet();
    if (distinct.length != 1) {
      _io.stderr.writeln('Revision flags must agree; pass only one revision.');
      return (valid: false, revision: null);
    }
    return (valid: true, revision: distinct.single);
  }
}
