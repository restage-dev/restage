import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/api/scope_snapshot_api.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/api/selector_syntax.dart';
import 'package:restage_cli/src/commands/target_resolution.dart';
import 'package:restage_cli/src/config/config_target_check.dart'
    show noOrganizationSentence;
import 'package:restage_cli/src/config/restage_config.dart';
import 'package:restage_cli/src/credentials/credential.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/discovery/context_discovery.dart';
import 'package:restage_cli/src/init/build_yaml_editor.dart';
import 'package:restage_cli/src/init/gitignore_editor.dart';
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
/// These pin against the current package contract. Bumping the constraints
/// here keeps newly initialized projects on the same SDK/toolchain release.
const Map<String, String> _defaultRuntimeDeps = {'restage': '^2.0.0'};
const Map<String, String> _defaultDevDeps = {
  'build_runner': '>=2.4.0 <3.0.0',
  'restage_codegen': '^2.0.0',
};

/// Initializes Restage configuration, dependencies and a starter paywall.
/// Also adds portable-output ignore rules and state inputs in `build.yaml`.
///
/// `--no-starter` and `--no-add-deps` skip those changes. Use
/// `--non-interactive` with explicit values, or `--dry-run` to preview writes.
/// Existing artifacts are retained; configuration updates require confirmation
/// or `--force`. Added `.gitignore` rules can be removed or negated.
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
      ..addOption(
        'plane',
        allowed: runtimePlaneWireNames,
        defaultsTo: 'sandbox',
        help: 'Default runtime plane: sandbox or live.',
      )
      ..addFlag(
        'starter',
        help: 'Write a starter `@Paywall` to `lib/paywalls/`.',
        defaultsTo: true,
      )
      ..addFlag(
        'add-deps',
        help:
            'Add `restage` (dependencies) plus `restage_codegen` '
            'and `build_runner` (dev_dependencies) to pubspec.yaml.',
        defaultsTo: true,
      )
      ..addFlag(
        'force',
        negatable: false,
        help: 'Update an existing restage_config.yaml without asking.',
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
      'Set up a Flutter project for Restage: writes config, a starter '
      'paywall, pubspec dependencies, and build-output ignores.';

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
      plane: RuntimePlane.fromWireName(results['plane'] as String),
      organizationId: context.organizationId,
      appId: context.appId,
      environmentTargetId: context.environmentTargetId,
      namedEnvironmentId: context.namedEnvironmentId,
    );

    final wantsStarter = results['starter'] as bool;
    final wantsDeps = results['add-deps'] as bool;
    final dryRun = results['dry-run'] as bool;
    final force = results['force'] as bool;

    // Read the pubspec once; both the dry-run plan and the apply path
    // consume the same source.
    final pubspecSource = wantsDeps ? await pubspec.readAsString() : '';
    final pubspecPlan = wantsDeps
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
    final gitignoreFile = File(p.join(root.path, '.gitignore'));
    final gitignoreExists = gitignoreFile.existsSync();
    final gitignoreSource = gitignoreExists
        ? await gitignoreFile.readAsString()
        : '';
    final gitignorePlan = planPortableOutputIgnores(gitignoreSource);
    final buildYamlFile = File(p.join(root.path, 'build.yaml'));
    final buildYamlPlan = planStateBuildInputs(
      buildYamlFile.existsSync() ? await buildYamlFile.readAsString() : null,
    );

    final configAction = !configFile.existsSync()
        ? 'create'
        : force
        ? 'update'
        : _interactive.isInteractive
        ? 'ask to update'
        : 'keep';

    _printPlan(
      configFile: configFile,
      configAction: configAction,
      wantsStarter: wantsStarter,
      starterFile: starterFile,
      pubspecPlan: pubspecPlan,
      gitignoreFile: gitignoreFile,
      gitignoreExists: gitignoreExists,
      gitignorePlan: gitignorePlan,
      buildYamlFile: buildYamlFile,
      buildYamlPlan: buildYamlPlan,
    );

    if (dryRun) return 0;

    // Apply.
    if (gitignorePlan.isNoOp) {
      _stdout.writeln(
        'Kept the existing .gitignore rule for Restage build output.',
      );
    } else {
      await gitignoreFile.writeAsString(gitignorePlan.source);
      _stdout.writeln(
        '${gitignoreExists ? 'Updated' : 'Wrote'} .gitignore to ignore '
        'Restage build output.',
      );
    }

    await _applyBuildYaml(buildYamlFile, buildYamlPlan);

    if (!configFile.existsSync()) {
      await writeRestageConfig(configFile, config);
      _stdout.writeln('Wrote restage_config.yaml.');
      _reportEndpoint(context);
    } else if (force ||
        (_interactive.isInteractive &&
            await _interactive.confirm(
              'restage_config.yaml already exists. Update it with these '
              'values?',
            ))) {
      await _updateConfig(configFile, config);
      _stdout.writeln('Updated restage_config.yaml.');
      _reportEndpoint(context);
    } else if (_interactive.isInteractive) {
      _stdout.writeln('Kept existing restage_config.yaml.');
    } else {
      _stdout.writeln(
        'Kept existing restage_config.yaml. Pass --force to update it.',
      );
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

    if (wantsDeps && pubspecPlan != null && !pubspecPlan.isNoOp) {
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
    } else if (wantsDeps) {
      _stdout.writeln('Pubspec dependencies already wired.');
    }

    _stdout.writeln();
    final syntax = currentSelectorSyntax;
    String push(String surface) => syntax.command(
      FollowUp('surface push', 'restage_push_surface', [
        FollowUpArg('surface', surface),
      ]),
    );
    if (wantsStarter) {
      final publish = syntax.command(
        const FollowUp('surface publish', 'restage_publish_surface', [
          FollowUpArg('surfaceSlug', 'starter'),
          FollowUpArg('surfaceType', 'paywall', flag: 'type', mcpOnly: true),
        ]),
      );
      _stdout.writeln(
        'Next: run `dart pub get && dart run build_runner build`, then '
        '${push('starter')} to push the starter to the '
        '`${context.environment ?? '<environment>'}` environment, and '
        '$publish to make it live.',
      );
    } else {
      _stdout.writeln(
        'Next: run `dart pub get && dart run build_runner build`, then '
        '${push('<id>')} to push a surface.',
      );
    }
    return 0;
  }

  Future<void> _applyBuildYaml(File file, StateBuildInputsPlan plan) async {
    switch (plan.action) {
      case StateBuildInputsAction.create:
        await file.writeAsString(plan.source);
        _stdout.writeln(
          "Wrote build.yaml so builds track Restage's state files.",
        );
      case StateBuildInputsAction.update:
        await file.writeAsString(plan.source);
        _stdout.writeln(
          "Updated build.yaml so builds track Restage's state files.",
        );
      case StateBuildInputsAction.keep:
        _stdout.writeln(
          "Kept build.yaml; it already tracks Restage's state files.",
        );
      case StateBuildInputsAction.manual:
        _stdout.writeln(
          'Could not update build.yaml safely. Add these entries to its '
          'additional_public_assets list:',
        );
        for (final entry in restageStateBuildInputs) {
          _stdout.writeln('  - $entry');
        }
    }
  }

  void _reportEndpoint(_InitContext context) {
    final endpoint = context.endpoint;
    if (endpoint == null) return;
    _stdout.writeln('Set endpoint: $endpoint (from your stored sign-in).');
  }

  /// Writes [config] over [file], keeping the settings init does not ask
  /// about when the existing file parses.
  Future<void> _updateConfig(File file, RestageConfig config) async {
    final RestageConfig existing;
    try {
      existing = RestageConfig.fromYaml(await file.readAsString());
    } on RestageConfigFormatException {
      await writeRestageConfig(file, config);
      return;
    }
    final merged = RestageConfig(
      project: config.project,
      app: config.app,
      defaultEnvironment: config.defaultEnvironment,
      organization: config.organization,
      endpoint: config.endpoint,
      plane: config.plane,
      organizationId: config.organizationId,
      appId: config.appId,
      environmentTargetId: config.environmentTargetId,
      namedEnvironmentId: config.namedEnvironmentId,
      recordGit: existing.recordGit,
      declareAssets: existing.declareAssets,
    );
    final flutterRoot = existing.flutterRoot;
    await file.writeAsString(
      '${merged.toYaml()}'
      '${flutterRoot == null ? '' : 'flutterRoot: $flutterRoot\n'}',
    );
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
        plane: RuntimePlane.fromWireName(results['plane'] as String),
      );
      if (discovered != null) return discovered;
      return null;
    }

    _stderr.writeln(
      'Not signed in. To pick your organization, project and app instead of '
      'typing their slugs: create them in the dashboard, run `restage login`, '
      'then run `restage init` again.',
    );
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
      _stderr.writeln('Required: --${e.flagName ?? "value"} <slug>.');
      return null;
    }
  }

  Future<_InitContext?> _discoverContext({
    required Credential credential,
    required String? organizationFlag,
    required String? projectFlag,
    required String? appFlag,
    required String? envFlag,
    required RuntimePlane plane,
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
      var scope = await readProgrammaticScope(api);
      final organization = await _pickDiscovered(
        preferredSlug: organizationFlag,
        options: scope.organizations,
        prompt: 'Which organization?',
        missingFlag: '--organization <slug>',
        emptyMessage:
            '${noOrganizationSentence(api.endpoint)}\nThen run '
            '`restage init` again.',
        slugOf: (organization) => organization.slug,
        labelOf: (organization) =>
            '${organization.name} (${organization.slug})',
      );
      if (organization == null) return null;
      if (scope.organizationId != organization.organizationId) {
        scope = await readProgrammaticScope(
          api,
          organizationId: organization.organizationId,
        );
      }

      final project = await _pickDiscovered(
        preferredSlug: projectFlag,
        options: scope.projects,
        prompt: 'Which project?',
        missingFlag: '--project <slug>',
        slugOf: (project) => project.slug,
        labelOf: (project) => '${project.name} (${project.slug})',
      );
      if (project == null) return null;

      final app = await _pickDiscovered(
        preferredSlug: appFlag,
        options: scope.apps(project.slug),
        prompt: 'Which app?',
        missingFlag: '--app <slug>',
        slugOf: (app) => app.slug,
        labelOf: (app) => '${app.name} (${app.slug})',
      );
      if (app == null) return null;

      final environment = await _pickDiscovered(
        preferredSlug: envFlag,
        options: scope
            .environments(project.slug)
            .where((environment) => environment.appId == app.appId)
            .toList(),
        prompt: 'Which default environment?',
        missingFlag: '--env <slug>',
        slugOf: (environment) => environment.slug,
        labelOf: (environment) => environment.slug,
        allowEmpty: true,
      );

      final targets = environment == null
          ? <EnvironmentTargetSummary>[]
          : scope
                .targets(
                  projectSlug: project.slug,
                  appSlug: app.slug,
                  runtimePlane: plane,
                )
                .where((target) => target.environmentSlug == environment.slug)
                .toList();
      final selectedTarget = targets.length == 1 ? targets.single : null;

      return _InitContext(
        organization: organization.slug,
        project: project.slug,
        app: app.slug,
        environment: environment?.slug,
        endpoint: credential.endpoint,
        organizationId: organization.organizationId,
        appId: app.appId,
        environmentTargetId: selectedTarget?.environmentTargetId,
        namedEnvironmentId: selectedTarget?.namedEnvironmentId,
      );
    } on RestageApiException catch (e) {
      _stderr.writeln('Could not discover your Restage context: ${e.body}');
      return null;
    } on SocketException catch (e) {
      _stderr.writeln(backendUnreachableMessage(api.endpoint, e));
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
    String? emptyMessage,
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
      emptyMessage: emptyMessage,
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
    required String configAction,
    required bool wantsStarter,
    required File starterFile,
    required AddDependenciesPlan? pubspecPlan,
    required File gitignoreFile,
    required bool gitignoreExists,
    required PortableOutputIgnorePlan gitignorePlan,
    required File buildYamlFile,
    required StateBuildInputsPlan buildYamlPlan,
  }) {
    _stdout.writeln('Planned changes:');
    _stdout.writeln(
      '  $configAction ${configFile.path} '
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
    _stdout.writeln(
      '  ${gitignorePlan.isNoOp
          ? 'keep'
          : gitignoreExists
          ? 'update'
          : 'create'} ${gitignoreFile.path} (.gitignore build-output rule)',
    );
    final buildYamlAction = switch (buildYamlPlan.action) {
      StateBuildInputsAction.create => 'create',
      StateBuildInputsAction.update ||
      StateBuildInputsAction.manual => 'update',
      StateBuildInputsAction.keep => 'keep',
    };
    _stdout.writeln(
      '  $buildYamlAction ${buildYamlFile.path} (track Restage state files)',
    );
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
    this.organizationId,
    this.appId,
    this.environmentTargetId,
    this.namedEnvironmentId,
  });

  final String? organization;
  final String project;
  final String app;
  final String? environment;
  final String? endpoint;
  final int? organizationId;
  final int? appId;
  final int? environmentTargetId;
  final int? namedEnvironmentId;
}
