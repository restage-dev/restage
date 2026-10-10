import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/api/surface_api.dart';
import 'package:restage_cli/src/api/surface_models.dart';
import 'package:restage_cli/src/commands/authed.dart';
import 'package:restage_cli/src/commands/lifecycle_support.dart';
import 'package:restage_cli/src/commands/surface_identity.dart';
import 'package:restage_cli/src/commands/surface_publish_operation.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_cli/src/operations/operation.dart';
import 'package:restage_shared/restage_shared.dart';

/// Show immutable revision history for one exact generated surface family.
class SurfaceHistoryCommand extends Command<int> {
  /// Construct a history command.
  SurfaceHistoryCommand({
    required StringSink stdout,
    required StringSink stderr,
    required Interactive interactive,
    SurfaceType? fixedSurfaceType,
    FileCredentialStore? credentialStore,
    http.Client? httpClient,
  }) : _io = CommandIo(
         stdout: stdout,
         stderr: stderr,
         interactive: interactive,
         credentialStore: credentialStore,
         httpClient: httpClient,
       ),
       _fixedType = fixedSurfaceType {
    addLifecycleOptions(
      argParser,
      withType: fixedSurfaceType == null,
      withReason: false,
      withContractVersion: true,
      withSourceKind: true,
    );
    argParser.addFlag(
      'json',
      negatable: false,
      help: 'Emit JSON instead of the default tab-separated table.',
    );
  }

  final CommandIo _io;
  final SurfaceType? _fixedType;

  @override
  String get name => 'history';

  @override
  String get description => 'Show pushed revisions for a surface family.';

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

    return runAuthed(_io, argResults, OperationScope.target, (ctx) async {
      final history = await familyHistory(
        api: SurfaceApi(ctx.api),
        identity: identity,
        at: ctx.target!.family,
      );
      if (argResults?['json'] as bool? ?? false) {
        _io.stdout.writeln(jsonEncode(history.toJson()));
      } else {
        _writeFamilyHistoryTable(_io.stdout, history);
      }
      return 0;
    });
  }

  void _writeFamilyHistoryTable(
    StringSink stdout,
    SurfaceContractFamilyHistoryResult history,
  ) {
    final active = history.activePublishedRevision == null
        ? '— (none)'
        : 'r${history.activePublishedRevision}';
    stdout.writeln(
      'family: ${history.family.familyAddress}  '
      'active: $active  payload: ${history.payloadKind ?? '—'}',
    );
    stdout.writeln(
      'REVISION\tACTIVE\tPUSHED AT\tCONTENT HASH\tMIN CLIENT\tPAYLOAD',
    );
    for (final revision in history.revisions) {
      stdout.writeln(
        'r${revision.publishedRevision}\t${revision.isActive}\t'
        '${revision.publishedAt.toUtc().toIso8601String()}\t'
        '${revision.contentHash}\t${revision.minClient}\t'
        '${revision.payloadKind}',
      );
    }
  }
}
