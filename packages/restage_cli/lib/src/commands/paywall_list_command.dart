import 'dart:async';
import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/api/surface_api.dart';
import 'package:restage_cli/src/api/surface_models.dart';
import 'package:restage_cli/src/commands/authed.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_cli/src/operations/operation.dart';
import 'package:restage_shared/restage_shared.dart' show Surface;

/// List paywalls in the current project and app.
class PaywallListCommand extends Command<int> {
  /// Construct a list command.
  PaywallListCommand({
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
  String get name => 'list';

  @override
  String get description =>
      'Compatibility view of paywalls; use `surface list --type paywall` '
      'for the generic surface view.';

  @override
  Future<int> run() => runAuthed(_io, argResults, OperationScope.app, (
    ctx,
  ) async {
    final summaries = await SurfaceApi(ctx.api).list(
      project: ctx.project!,
      app: ctx.app!.slug,
      surfaceType: Surface.paywall,
      organizationId: ctx.organizationId,
      appId: ctx.app!.appId,
    );
    if (argResults?['json'] as bool? ?? false) {
      _io.stdout.writeln(jsonEncode([for (final s in summaries) s.toJson()]));
    } else {
      _renderTable(summaries);
    }
    return 0;
  });

  void _renderTable(List<SurfaceSummary> summaries) {
    _io.stdout.writeln('SLUG\tNAME\tDRAFT-UPDATED\tPUBLISHED');
    for (final summary in summaries) {
      final draft = summary.draftUpdatedAt.toUtc().toIso8601String();
      final published = _formatPublishedColumn(
        summary.publishedVersionByEnvironment,
      );
      _io.stdout.writeln(
        '${summary.slug}\t${summary.name}\t$draft\t$published',
      );
    }
  }

  /// Render the `PUBLISHED` column.
  ///
  /// Each `env: version` pair contributes `env=version` when the version
  /// is non-null. The whole column is a single dash (`-`) when no
  /// environment has a published version yet.
  String _formatPublishedColumn(Map<String, int?> byEnv) {
    final published = <String>[
      for (final entry in byEnv.entries)
        if (entry.value != null) '${entry.key}=${entry.value}',
    ];
    if (published.isEmpty) return '-';
    return published.join(', ');
  }
}
