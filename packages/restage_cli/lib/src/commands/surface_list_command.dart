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
import 'package:restage_shared/restage_shared.dart';

/// List surfaces in the current project and app.
class SurfaceListCommand extends Command<int> {
  /// Construct a generic surface list command.
  SurfaceListCommand({
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
    argParser
      ..addOption(
        'type',
        help:
            'Filter by surface category: paywall, onboarding, message, '
            'survey, general. Lists every type when left out.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Emit JSON instead of the default text output.',
      );
  }

  final CommandIo _io;

  @override
  String get name => 'list';

  @override
  String get description => 'List surfaces in the current project and app.';

  @override
  Future<int> run() async {
    final surfaceTypes = _resolveSurfaceTypes();
    if (surfaceTypes == null) return 1;

    return runAuthed(_io, argResults, OperationScope.app, (ctx) async {
      final surfaceApi = SurfaceApi(ctx.api);
      final summaries = <SurfaceSummary>[
        for (final surfaceType in surfaceTypes)
          ...await surfaceApi.list(
            project: ctx.project!,
            app: ctx.app!.slug,
            surfaceType: surfaceType,
            organizationId: ctx.organizationId,
            appId: ctx.app!.appId,
          ),
      ];
      if (argResults?['json'] as bool? ?? false) {
        _io.stdout.writeln(jsonEncode([for (final s in summaries) s.toJson()]));
      } else {
        _renderTable(summaries);
      }
      return 0;
    });
  }

  List<SurfaceType>? _resolveSurfaceTypes() {
    final raw = argResults?['type'] as String?;
    final valid = _listableSurfaceTypes.map((type) => type.wireName).join(', ');
    if (raw == null || raw.isEmpty) return _listableSurfaceTypes;
    final SurfaceType type;
    try {
      type = SurfaceType.fromWireName(raw);
    } on FormatException {
      _io.stderr.writeln('Invalid --type "$raw". Valid values: $valid.');
      return null;
    }
    if (!_listableSurfaceTypes.contains(type)) {
      _io.stderr.writeln('Invalid --type "$raw". Valid values: $valid.');
      return null;
    }
    return [type];
  }

  void _renderTable(List<SurfaceSummary> summaries) {
    _io.stdout.writeln('TYPE\tSLUG\tNAME\tDRAFT-UPDATED\tPUBLISHED');
    for (final summary in summaries) {
      final draft = summary.draftUpdatedAt.toUtc().toIso8601String();
      final published = _formatPublishedColumn(
        summary.publishedVersionByEnvironment,
      );
      _io.stdout.writeln(
        '${summary.surfaceType}\t${summary.slug}\t${summary.name}\t$draft\t$published',
      );
    }
  }

  String _formatPublishedColumn(Map<String, int?> byEnv) {
    final published = <String>[
      for (final entry in byEnv.entries)
        if (entry.value != null) '${entry.key}=${entry.value}',
    ];
    if (published.isEmpty) return '-';
    return published.join(', ');
  }
}

const _listableSurfaceTypes = <SurfaceType>[
  SurfaceType.paywall,
  SurfaceType.onboarding,
  SurfaceType.message,
  SurfaceType.survey,
  SurfaceType.general,
];
