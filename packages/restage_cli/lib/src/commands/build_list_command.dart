import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/render_bundles/push_target.dart';
import 'package:restage_cli/src/api/selector_syntax.dart';
import 'package:restage_cli/src/api/render_bundle_api.dart';
import 'package:restage_cli/src/commands/authed.dart';
import 'package:restage_cli/src/commands/organization_resolution.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_cli/src/operations/operation.dart';

/// Lists the app's builds: one per environment, one per person.
final class BuildListCommand extends Command<int> {
  BuildListCommand({
    required StringSink stdout,
    required StringSink stderr,
    FileCredentialStore? credentialStore,
    http.Client? httpClient,
  }) : _stdout = stdout,
       _stderr = stderr,
       _credentialStore = credentialStore,
       _httpClient = httpClient {
    argParser
      ..addOption(
        'project',
        help: 'Project slug (overrides restage_config.yaml).',
      )
      ..addOption('app', help: 'App slug (overrides restage_config.yaml).')
      ..addOption(
        'organization',
        help: 'Organization slug (overrides restage_config.yaml).',
      )
      ..addOption(
        'directory',
        abbr: 'C',
        defaultsTo: '.',
        help: 'Directory to start the restage_config.yaml search from.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Emit JSON instead of the default tab-separated table.',
      );
  }

  final StringSink _stdout;
  final StringSink _stderr;
  final FileCredentialStore? _credentialStore;
  final http.Client? _httpClient;

  @override
  String get name => 'list';

  @override
  String get description =>
      "List the app's builds for each environment and each person.";

  @override
  Future<int> run() => runAuthed(
    CommandIo(
      stdout: _stdout,
      stderr: _stderr,
      interactive: const NonInteractive(),
      credentialStore: _credentialStore,
      httpClient: _httpClient,
    ),
    argResults,
    OperationScope.account,
    (ctx) async {
      final project =
          (argResults?['project'] as String?) ?? ctx.config?.project;
      final app = (argResults?['app'] as String?) ?? ctx.config?.app;
      if (project == null || app == null) {
        _stderr.writeln(
          missingProjectContextSentence(
            hasConfig: ctx.config != null,
            projectMissing: project == null,
          ),
        );
        return 1;
      }
      final organizationId = await resolveRequiredOrganizationId(
        api: ctx.api,
        config: ctx.config,
        stderr: _stderr,
        preferredSlug: argResults?['organization'] as String?,
      );
      if (organizationId == null) return 1;
      final bundles = RenderBundleApi(rpc: ctx.api, uploadClient: _httpClient);
      try {
        final heads = await bundles.listHeads(
          project: project,
          app: app,
          organizationId: organizationId,
        );
        if (argResults?['json'] as bool? ?? false) {
          _stdout.writeln(
            jsonEncode([for (final head in heads) head.toJson()]),
          );
          return 0;
        }
        if (heads.isEmpty) {
          _stdout.writeln(
            'No builds yet. ${currentSelectorSyntax.run} '
            '${currentSelectorSyntax.command(pushBuildFollowUp('<slug>'))} '
            'to push one.',
          );
          return 0;
        }
        for (final head in heads) {
          final commit = head.sourceCommit;
          final source = commit == null
              ? '-'
              : '${commit.length > 7 ? commit.substring(0, 7) : commit}'
                    '${head.sourceDirty ? ' (local changes)' : ''}';
          _stdout.writeln(
            [
              head.head,
              'version ${head.version}',
              source,
              head.updatedAt.toUtc().toIso8601String(),
              ?head.ownerDisplayName,
            ].join('\t'),
          );
        }
        return 0;
      } on RenderBundleUploadException {
        _stderr.writeln('Could not list the builds.');
        return 1;
      } finally {
        if (_httpClient == null) bundles.close();
      }
    },
  );
}
