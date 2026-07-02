import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/api/discovery_api.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/config/restage_config.dart';
import 'package:restage_cli/src/credentials/credential.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/discovery/context_discovery.dart';
import 'package:restage_cli/src/init/pubspec_editor.dart'
    show
        AddDependenciesPlan,
        addDependencies,
        complexConstraintMarker,
        planAddDependencies;
import 'package:restage_cli/src/init/starter_paywall.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:path/path.dart' as p;

/// Default version constraints for the wired-in dependencies.
///
/// These pin against the currently-published shape of the SDK packages.
/// Once those packages are on pub.dev, bumping the constraints here is a
/// single-file change.
const Map<String, String> _defaultRuntimeDeps = {'restage': '^0.1.0'};
const Map<String, String> _defaultDevDeps = {
  'build_runner': '>=2.4.0 <3.0.0',
  'restage_codegen': '^0.1.0',
};

/// Bootstrap a Flutter project for Restage.
///
/// The wizard prompts for project, app, and (default) environment
/// slugs, then writes three artifacts:
///
///   1. `restage_config.yaml` at the project root.
///   2. A starter paywall under `lib/paywalls/`.
///   3. Edits to `pubspec.yaml` adding the SDK + codegen dependencies.
///
/// Each artifact has an opt-out flag (`--no-starter`, `--no-wire-deps`)
/// and the wizard can be skipped end-to-end with `--non-interactive` +
/// the per-value flags. `--dry-run` prints the planned changes without
/// writing.
///
/// Re-running is idempotent: existing artifacts are preserved (the
/// wizard prompts before overwriting; non-interactive mode keeps the
/// existing artifact).
class InitCommand extends Command<int> {
  /// Construct an init command.
  InitCommand({
    required StringSink stdout,
    required StringSink stderr,
    required Interactive interactive,
    FileCredentialStore? credentialStore,
    http.Client? httpClient,
  }) : _stdout = stdout,
       _stderr = stderr,
       _interactive = interactive,
       _credentialStore = credentialStore,
       _httpClient = httpClient {
    argParser
      ..addOption(
        'directory',
        abbr: 'C',
        defaultsTo: '.',
        help: 'Project root (defaults to the current directory).',
      )
      ..addOption('project', help: 'Project slug (skips the prompt).')
      ..addOption('app', help: 'App slug (skips the prompt).')
      ..addOption('env', help: 'Default environment slug (skips the prompt).')
      ..addOption(
        'organization',
        help: 'Organization slug (skips the organization picker).',
      )
      ..addFlag(
        'starter',
        help: 'Write a starter paywall to `lib/paywalls/`.',
        defaultsTo: true,
      )
      ..addFlag(
        'wire-deps',
        help:
            'Add `restage` (dependencies) plus `restage_codegen` '
            'and `build_runner` (dev_dependencies) to pubspec.yaml.',
        defaultsTo: true,
      )
      ..addFlag(
        'dry-run',
        negatable: false,
        help: 'Print the planned changes without writing.',
      );
  }

  final StringSink _stdout;
  final StringSink _stderr;
  final Interactive _interactive;
  final FileCredentialStore? _credentialStore;
  final http.Client? _httpClient;

  @override
  String get name => 'init';

  @override
  String get description =>
      'Bootstrap a Flutter project for Restage — writes config, a '
      'starter paywall, and pubspec wiring.';

  @override
  Future<int> run() async {
    final results = argResults!;
    final root = Directory(results['directory'] as String).absolute;
    final pubspec = File(p.join(root.path, 'pubspec.yaml'));
    if (!pubspec.existsSync()) {
      _stderr.writeln(
        'No `pubspec.yaml` at ${root.path}. Run `restage init` from a '
        'Flutter project root, or pass `--directory <path>`.',
      );
      return 1;
    }

    final context = await _resolveInitContext(results);
    if (context == null) {
      return 1;
    }

    final config = RestageConfig(
      project: context.project,
      app: context.app,
      defaultEnvironment: context.environment,
      organization: context.organization,
      endpoint: context.endpoint,
    );

    final wantsStarter = results['starter'] as bool;
    final wantsWireDeps = results['wire-deps'] as bool;
    final dryRun = results['dry-run'] as bool;

    // Read the pubspec once; both the dry-run plan and the apply path
    // consume the same source.
    final pubspecSource = wantsWireDeps ? await pubspec.readAsString() : '';
    final pubspecPlan = wantsWireDeps
        ? planAddDependencies(
            pubspecSource,
            deps: _defaultRuntimeDeps,
            devDeps: _defaultDevDeps,
          )
        : null;

    final configFile = File(p.join(root.path, 'restage_config.yaml'));
    final starterFile = File(
      p.join(root.path, 'lib', 'paywalls', 'starter.dart'),
    );

    _printPlan(
      configFile: configFile,
      wantsStarter: wantsStarter,
      starterFile: starterFile,
      pubspecPlan: pubspecPlan,
    );

    if (dryRun) return 0;

    // Apply.
    if (configFile.existsSync()) {
      _stdout.writeln(
        'Kept existing restage_config.yaml (delete it to regenerate).',
      );
    } else {
      await writeRestageConfig(configFile, config);
      _stdout.writeln('Wrote restage_config.yaml.');
    }

    if (wantsStarter) {
      if (starterFile.existsSync()) {
        _stdout.writeln('Kept existing lib/paywalls/starter.dart.');
      } else {
        await starterFile.parent.create(recursive: true);
        await starterFile.writeAsString(starterPaywallSource('starter'));
        _stdout.writeln('Wrote lib/paywalls/starter.dart.');
      }
    }

    if (wantsWireDeps && pubspecPlan != null && !pubspecPlan.isNoOp) {
      final result = addDependencies(
        pubspecSource,
        deps: _defaultRuntimeDeps,
        devDeps: _defaultDevDeps,
      );
      await pubspec.writeAsString(result.source);
      if (result.added.isNotEmpty) {
        _stdout.writeln(
          'Updated pubspec.yaml — added: ${result.added.join(', ')}.',
        );
      }
      if (result.kept.isNotEmpty) {
        _stdout.writeln(
          'Kept existing pubspec entries: ${result.kept.join(', ')}.',
        );
      }
    } else if (wantsWireDeps) {
      _stdout.writeln('Pubspec dependencies already wired.');
    }

    _stdout
      ..writeln()
      ..writeln(
        'Next: run `dart pub get && dart run build_runner build`, then '
        '`restage paywall publish starter` to push the starter to the '
        '`${context.environment ?? '<environment>'}` environment.',
      );
    return 0;
  }

  Future<_InitContext?> _resolveInitContext(ArgResults results) async {
    final organizationFlag = _flag(results, 'organization');
    final projectFlag = _flag(results, 'project');
    final appFlag = _flag(results, 'app');
    final envFlag = _flag(results, 'env');

    final store = _credentialStore ?? FileCredentialStore.atDefaultLocation();
    final credential = await store.read();
    if (projectFlag != null && appFlag != null && envFlag != null) {
      return _InitContext(
        organization: organizationFlag,
        project: projectFlag,
        app: appFlag,
        environment: envFlag,
        endpoint: credential?.endpoint,
      );
    }

    if (credential != null) {
      final discovered = await _discoverContext(
        credential: credential,
        organizationFlag: organizationFlag,
        projectFlag: projectFlag,
        appFlag: appFlag,
        envFlag: envFlag,
      );
      if (discovered != null) return discovered;
      return null;
    }

    try {
      return _InitContext(
        organization: organizationFlag,
        project:
            projectFlag ?? await _resolveManualSlug('project', 'Project slug?'),
        app: appFlag ?? await _resolveManualSlug('app', 'App slug?'),
        environment:
            envFlag ??
            await _resolveManualSlug('env', 'Default environment slug?'),
      );
    } on NonInteractiveDefaultMissing catch (e) {
      _stderr.writeln(
        'Required: --${e.flagName ?? "value"} <slug>. Pass the value on '
        'the command line or run `restage login` to use discovery.',
      );
      return null;
    }
  }

  Future<_InitContext?> _discoverContext({
    required Credential credential,
    required String? organizationFlag,
    required String? projectFlag,
    required String? appFlag,
    required String? envFlag,
  }) async {
    final RestageApi api;
    try {
      api = RestageApi(
        endpoint: Uri.parse(credential.endpoint),
        httpClient: _httpClient,
        credential: credential,
      );
    } on InsecureEndpointException catch (e) {
      _stderr.writeln(e.toString());
      return null;
    }

    try {
      final discovery = DiscoveryApi(api);
      final organization = await resolveActiveOrganization(
        api: discovery,
        interactive: _interactive,
        stderr: _stderr,
        preferredSlug: organizationFlag,
      );
      if (organization == null) return null;

      final project = await _pickDiscovered(
        preferredSlug: projectFlag,
        options: await discovery.listProjects(organization.organizationId),
        prompt: 'Which project?',
        missingFlag: '--project <slug>',
        slugOf: (project) => project.slug,
        labelOf: (project) => '${project.name} (${project.slug})',
      );
      if (project == null) return null;

      final app = await _pickDiscovered(
        preferredSlug: appFlag,
        options: await discovery.listApps(
          organizationId: organization.organizationId,
          projectSlug: project.slug,
        ),
        prompt: 'Which app?',
        missingFlag: '--app <slug>',
        slugOf: (app) => app.slug,
        labelOf: (app) => '${app.name} (${app.slug})',
      );
      if (app == null) return null;

      final environment = await _pickDiscovered(
        preferredSlug: envFlag,
        options: await discovery.listEnvironments(
          organizationId: organization.organizationId,
          projectSlug: project.slug,
        ),
        prompt: 'Which default environment?',
        missingFlag: '--env <slug>',
        slugOf: (environment) => environment.slug,
        labelOf: (environment) => environment.slug,
        allowEmpty: true,
      );

      return _InitContext(
        organization: organization.slug,
        project: project.slug,
        app: app.slug,
        environment: environment?.slug,
        endpoint: credential.endpoint,
      );
    } on RestageApiException catch (e) {
      _stderr.writeln('Could not discover your Restage context: ${e.body}');
      return null;
    } on SocketException catch (e) {
      _stderr.writeln('Could not contact the backend: $e');
      return null;
    } finally {
      if (_httpClient == null) api.close();
    }
  }

  Future<T?> _pickDiscovered<T>({
    required String? preferredSlug,
    required List<T> options,
    required String prompt,
    required String missingFlag,
    required String Function(T value) slugOf,
    required String Function(T value) labelOf,
    bool allowEmpty = false,
  }) async {
    if (preferredSlug != null && preferredSlug.isNotEmpty) {
      for (final option in options) {
        if (slugOf(option) == preferredSlug) return option;
      }
      _stderr.writeln('No option found for $missingFlag: $preferredSlug.');
      return null;
    }
    return pickOne<T>(
      interactive: _interactive,
      stderr: _stderr,
      prompt: prompt,
      options: [
        for (final option in options) (label: labelOf(option), value: option),
      ],
      missingFlag: missingFlag,
      allowEmpty: allowEmpty,
    );
  }

  String? _flag(ArgResults results, String optionName) {
    final value = results[optionName] as String?;
    if (value == null || value.isEmpty) return null;
    return value;
  }

  Future<String> _resolveManualSlug(String optionName, String prompt) async {
    try {
      return await _interactive.prompt(prompt);
    } on NonInteractiveDefaultMissing catch (e) {
      throw NonInteractiveDefaultMissing(e.question, flagName: optionName);
    }
  }

  void _printPlan({
    required File configFile,
    required bool wantsStarter,
    required File starterFile,
    required AddDependenciesPlan? pubspecPlan,
  }) {
    _stdout.writeln('Planned changes:');
    _stdout.writeln(
      '  ${configFile.existsSync() ? 'keep' : 'create'} ${configFile.path} '
      '(restage_config.yaml)',
    );
    if (wantsStarter) {
      _stdout.writeln(
        '  ${starterFile.existsSync() ? 'keep' : 'create'} ${starterFile.path}',
      );
    }
    if (pubspecPlan != null && !pubspecPlan.isNoOp) {
      _stdout.writeln('  update pubspec.yaml:');
      for (final entry in pubspecPlan.dependenciesToAdd.entries) {
        _stdout.writeln('    dependencies: + ${entry.key}: ${entry.value}');
      }
      for (final entry in pubspecPlan.dependenciesToKeep.entries) {
        _stdout.writeln(
          '    dependencies: = ${entry.key}: '
          '${_renderConstraint(entry.value)} (kept)',
        );
      }
      for (final entry in pubspecPlan.devDependenciesToAdd.entries) {
        _stdout.writeln('    dev_dependencies: + ${entry.key}: ${entry.value}');
      }
      for (final entry in pubspecPlan.devDependenciesToKeep.entries) {
        _stdout.writeln(
          '    dev_dependencies: = ${entry.key}: '
          '${_renderConstraint(entry.value)} (kept)',
        );
      }
    } else if (pubspecPlan != null) {
      _stdout.writeln('  pubspec.yaml: already wired (no-op)');
    }
    _stdout.writeln();
  }

  /// Render the right-hand side of a dependency entry, replacing the
  /// sentinel used for non-string constraints with a human-readable
  /// pointer.
  String _renderConstraint(String value) =>
      value == complexConstraintMarker ? '(see pubspec)' : value;
}

class _InitContext {
  const _InitContext({
    required this.project,
    required this.app,
    this.environment,
    this.organization,
    this.endpoint,
  });

  final String? organization;
  final String project;
  final String app;
  final String? environment;
  final String? endpoint;
}
