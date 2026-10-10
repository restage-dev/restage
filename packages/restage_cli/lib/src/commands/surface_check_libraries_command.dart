import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/api/library_requirements_api.dart';
import 'package:restage_cli/src/commands/authed.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_cli/src/libraries/library_contract_check.dart';
import 'package:restage_cli/src/operations/operation.dart';
import 'package:restage_shared/restage_shared.dart'
    show libraryContractSnapshotDirectory;

/// List live versions this build's library contracts would stop rendering.
///
/// Exits 1 when any would, so it can gate a release in CI.
class SurfaceCheckLibrariesCommand extends Command<int> {
  /// Construct a check-libraries command.
  SurfaceCheckLibrariesCommand({
    required StringSink stdout,
    required StringSink stderr,
    required Interactive interactive,
    FileCredentialStore? credentialStore,
    http.Client? httpClient,
  }) : _io = CommandIo(
         stdout: stdout,
         stderr: stderr,
         interactive: interactive,
         credentialStore: credentialStore,
         httpClient: httpClient,
       ) {
    addScopeOptions(argParser, OperationScope.app);
    argParser.addFlag(
      'json',
      negatable: false,
      help: 'Emit JSON instead of the default text output.',
    );
  }

  final CommandIo _io;

  @override
  String get name => 'check-libraries';

  @override
  String get description =>
      'List versions in use, delivery rules and experiment arms that this '
      "build's library contracts would stop rendering. Exits 1 when there "
      'are any.';

  @override
  Future<int> run() async {
    final root = await libraryContractRoot(
      Directory(argResults!['directory'] as String),
    );
    final Map<String, int> since;
    try {
      since = localCompatibleSince(root);
    } on FormatException catch (error) {
      _io.stderr.writeln(error.message);
      return 1;
    }
    if (since.isEmpty) {
      _io.stdout.writeln(
        'No library contracts in $libraryContractSnapshotDirectory.',
      );
      return 0;
    }
    return runAuthed(_io, argResults, OperationScope.app, (ctx) async {
      final live = await LibraryRequirementsApi(ctx.api)
          .liveLibraryRequirements(
            project: ctx.project!,
            app: ctx.app!.slug,
            organizationId: ctx.organizationId,
          );
      final breaks = findLibraryBreaks(live: live, compatibleSince: since);
      if (argResults?['json'] as bool? ?? false) {
        _io.stdout.writeln(jsonEncode(libraryBreaksJson(breaks)));
      } else if (breaks.isEmpty) {
        _io.stdout.writeln('All versions in use render on this build.');
      } else {
        String? environment;
        for (final item in breaks) {
          if (item.version.environment != environment) {
            environment = item.version.environment;
            _io.stdout.writeln(environment);
          }
          _io.stdout.writeln('  ${item.sentence}');
        }
      }
      return breaks.isEmpty ? 0 : 1;
    });
  }
}

/// Runs `check-libraries` with [arguments] on its own, outside the full
/// command tree.
Future<int> runCheckLibraries(
  List<String> arguments, {
  required StringSink stdout,
  required StringSink stderr,
  FileCredentialStore? credentialStore,
  http.Client? httpClient,
}) async {
  final runner = CommandRunner<int>('restage', 'Restage command line.')
    ..addCommand(
      SurfaceCheckLibrariesCommand(
        stdout: stdout,
        stderr: stderr,
        interactive: const NonInteractive(),
        credentialStore: credentialStore,
        httpClient: httpClient,
      ),
    );
  return await runner.run(['check-libraries', ...arguments]) ?? 0;
}
