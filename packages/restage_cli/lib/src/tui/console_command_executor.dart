import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/api/selector_syntax.dart';
import 'package:restage_cli/src/cli.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_cli/src/tui/console_models.dart';

class ConsoleCommandExecutor implements ConsoleOperationExecutor {
  ConsoleCommandExecutor({
    FileCredentialStore? credentialStore,
    http.Client? httpClient,
    Directory? directory,
  }) : _credentialStore = credentialStore,
       _httpClient = httpClient,
       _directory = directory;

  final FileCredentialStore? _credentialStore;
  final http.Client? _httpClient;
  final Directory? _directory;

  @override
  Future<ConsoleOperationResult> kill({
    required ConsoleContext context,
    required ConsoleSurface surface,
    required String reason,
    required bool frozen,
    bool confirmedProduction = false,
  }) {
    return _runLifecycle(
      context: context,
      confirmedProduction: confirmedProduction,
      args: [
        'surface',
        'kill',
        ..._surfaceArgs(context, surface),
        '--reason',
        reason,
        if (frozen) '--frozen',
        if (context.runtimePlane == RuntimePlane.sandbox) '--yes',
      ],
    );
  }

  @override
  Future<ConsoleOperationResult> rollback({
    required ConsoleContext context,
    required ConsoleSurface surface,
    required String reason,
    required int toVersion,
    required bool freeze,
    bool confirmedProduction = false,
  }) {
    return _runLifecycle(
      context: context,
      confirmedProduction: confirmedProduction,
      args: [
        'surface',
        'rollback',
        ..._surfaceArgs(context, surface, familyScoped: true),
        '--reason',
        reason,
        '--to-version',
        '$toVersion',
        if (freeze) '--freeze',
        if (context.runtimePlane == RuntimePlane.sandbox) '--yes',
      ],
    );
  }

  @override
  Future<ConsoleOperationResult> rollbackPreview({
    required ConsoleContext context,
    required ConsoleSurface surface,
    required int toVersion,
  }) {
    // A pure read: no reason and no confirmation bypass on either plane.
    return _run([
      'surface',
      'rollback',
      ..._surfaceArgs(context, surface, familyScoped: true),
      '--to-version',
      '$toVersion',
      '--preview',
    ]);
  }

  @override
  Future<ConsoleOperationResult> freeze({
    required ConsoleContext context,
    required ConsoleSurface surface,
    required String reason,
    bool confirmedProduction = false,
  }) {
    return _runLifecycle(
      context: context,
      confirmedProduction: confirmedProduction,
      args: [
        'surface',
        'freeze',
        ..._surfaceArgs(context, surface),
        '--reason',
        reason,
      ],
    );
  }

  @override
  Future<ConsoleOperationResult> unfreeze({
    required ConsoleContext context,
    required ConsoleSurface surface,
    required String reason,
    bool confirmedProduction = false,
  }) {
    return _runLifecycle(
      context: context,
      confirmedProduction: confirmedProduction,
      args: [
        'surface',
        'unfreeze',
        ..._surfaceArgs(context, surface),
        '--reason',
        reason,
      ],
    );
  }

  @override
  Future<ConsoleOperationResult> push({
    required ConsoleContext context,
    required ConsoleSurface surface,
  }) {
    return _run(['surface', 'push', ..._surfaceArgs(context, surface)]);
  }

  @override
  Future<ConsoleOperationResult> publish({
    required ConsoleContext context,
    required ConsoleSurface surface,
    required String reason,
    bool confirmedProduction = false,
  }) {
    return _runLifecycle(
      context: context,
      confirmedProduction: confirmedProduction,
      args: [
        'surface',
        'publish',
        ..._surfaceArgs(context, surface, familyScoped: true),
        '--reason',
        reason,
      ],
    );
  }

  @override
  Future<ConsoleOperationResult> runCommand(List<String> arguments) =>
      _run(arguments);

  @override
  Future<ConsoleOperationResult> pushBuild({required ConsoleContext context}) {
    return _run([
      'build',
      'push',
      '--project',
      context.project,
      '--app',
      context.app,
      '--env',
      context.environment,
      if (context.organizationSlug case final organization?) ...[
        '--organization',
        organization,
      ],
    ]);
  }

  /// The shared target-selection arguments every surface lifecycle command
  /// takes: slug, type, project, app, environment, and resolved plane. A
  /// surface outside the current manifest names only its category; the server
  /// resolves its family.
  List<String> _surfaceArgs(
    ConsoleContext context,
    ConsoleSurface surface, {
    bool familyScoped = false,
  }) => [
    surface.slug,
    if (!surface.hasManifestIdentity) ...['--type', surface.surfaceType],
    if (familyScoped && surface.contractVersion != null) ...[
      '--contract-version',
      '${surface.contractVersion}',
    ],
    '--project',
    context.project,
    '--app',
    context.app,
    '--env',
    context.environment,
    '--plane',
    context.runtimePlane.wireName,
  ];

  Future<ConsoleOperationResult> _runLifecycle({
    required ConsoleContext context,
    required bool confirmedProduction,
    required List<String> args,
  }) {
    final confirmed =
        context.runtimePlane == RuntimePlane.live && confirmedProduction;
    return _run(
      args,
      interactive: confirmed
          ? const _ApprovedInteractive()
          : const NonInteractive(),
    );
  }

  Future<ConsoleOperationResult> _run(
    List<String> args, {
    Interactive interactive = const NonInteractive(),
  }) async {
    final stdout = StringBuffer();
    final stderr = StringBuffer();
    final directory = _directory;
    final commandArgs = [
      if (directory != null) ...['--directory', directory.path],
      ...args,
    ];
    final exitCode = await RestageCli(
      stdout: stdout,
      stderr: stderr,
      credentialStore: _credentialStore,
      httpClient: _httpClient,
      hasTerminal: () => false,
      interactiveFactory: (_) => interactive,
      selectorSyntax: SelectorSyntax.console,
    ).run(commandArgs);
    return ConsoleOperationResult(
      exitCode: exitCode,
      stdout: stdout.toString(),
      stderr: stderr.toString(),
    );
  }
}

class _ApprovedInteractive implements Interactive {
  const _ApprovedInteractive();

  @override
  bool get isInteractive => true;

  @override
  Future<String> prompt(String question, {String? defaultValue}) async =>
      defaultValue ?? '';

  @override
  Future<bool> confirm(String question, {bool defaultYes = false}) async =>
      question == 'Proceed?';

  @override
  Future<T> select<T>(
    String question,
    List<({String label, T value})> options, {
    T? defaultValue,
  }) async => defaultValue ?? options.first.value;

  @override
  Future<String> secret(String question) async => '';

  @override
  Spinner spinner(String message) => NonInteractive().spinner(message);
}
