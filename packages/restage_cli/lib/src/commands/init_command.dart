import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/api/scope_snapshot_api.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/typed_error_renderer.dart';
import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/api/selector_syntax.dart';
import 'package:restage_cli/src/commands/target_resolution.dart';
import 'package:restage_cli/src/config/config_target_check.dart'
    show noOrganizationSentence;
import 'package:restage_cli/src/config/restage_config.dart';
import 'package:restage_cli/src/credentials/credential.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/discovery/context_discovery.dart';
import 'package:restage_cli/src/init/android_manifest_editor.dart';
import 'package:restage_cli/src/init/build_yaml_editor.dart';
import 'package:restage_cli/src/init/gitignore_editor.dart';
import 'package:restage_cli/src/init/pubspec_editor.dart'
    show
        AddDependenciesPlan,
        addDependencies,
        complexConstraintMarker,
        planAddDependencies;
import 'package:restage_cli/src/init/starter_paywall.dart';
import 'package:restage_cli/src/render_bundles/surface_capture_source.dart'
    show SurfaceCaptureSourceException, SurfaceCaptureWrapper;
import 'package:restage_cli/src/io/interactive.dart';
import 'package:path/path.dart' as p;

/// Default version constraints for the wired-in dependencies.
///
/// These pin against the current package contract. Bumping the constraints
/// here keeps newly initialized projects on the same SDK/toolchain release.
const Map<String, String> _defaultRuntimeDeps = {
  'restage': '^2.0.0',
  'restage_material': '^2.0.0',
};
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
        'preview-wrapper',
        help:
            'An existing function in lib/ that wraps push images with what '
            'your app provides above its screens, such as a theme: '
            'lib/restage_preview.dart#wrapPreview.',
      )
      ..addOption(
        'plane',
        allowed: runtimePlaneWireNames,
        help:
            'Default runtime plane: sandbox or live. Without it, the plane '
            'the environment is on, sandbox first.',
      )
      ..addOption(
        'sdk-key',
        help:
            'Your app\'s publishable key (rs_pk_...). Written to build.yaml so '
            'the startup request is built into the app.',
      )
      ..addFlag(
        'early-request',
        help:
            'Build the startup request into the app so it is sent before '
            'Dart starts. Turn off only for an app that cannot use it.',
        defaultsTo: true,
      )
      ..addFlag(
        'starter',
        help: 'Write a starter `@Paywall` to `lib/paywalls/`.',
        defaultsTo: true,
      )
      ..addFlag(
        'add-deps',
        help:
            'Add `restage` and `restage_material` (dependencies) plus '
            '`restage_codegen` and `build_runner` (dev_dependencies) to '
            'pubspec.yaml.',
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

    if (_flag(results, 'preview-wrapper') case final wrapper?) {
      try {
        SurfaceCaptureWrapper.parse(wrapper, projectRoot: root);
      } on SurfaceCaptureSourceException catch (error) {
        _stderr.writeln('--preview-wrapper: ${error.reason}.');
        return 1;
      }
    }

    final context = await _resolveInitContext(results);
    if (context == null) {
      return _failureExit;
    }

    final config = RestageConfig(
      project: context.project,
      app: context.app,
      defaultEnvironment: context.environment,
      organization: context.organization,
      endpoint: context.endpoint,
      plane: context.plane,
      previewWrapper: _flag(results, 'preview-wrapper'),
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
    final buildYamlSource = buildYamlFile.existsSync()
        ? await buildYamlFile.readAsString()
        : null;
    final stateInputsPlan = planStateBuildInputs(buildYamlSource);
    final earlyPlan = planEarlyRequestOptions(
      stateInputsPlan.source,
      baseUrl: context.endpoint,
      apiKey: results['sdk-key'] as String?,
      enabled: results['early-request'] as bool,
    );
    final buildYamlPlan = earlyPlan.action == StateBuildInputsAction.keep
        ? stateInputsPlan
        : StateBuildInputsPlan(
            earlyPlan.action == StateBuildInputsAction.manual
                ? StateBuildInputsAction.manual
                : stateInputsPlan.action == StateBuildInputsAction.create
                ? StateBuildInputsAction.create
                : StateBuildInputsAction.update,
            earlyPlan.source,
          );

    final manifestFile = File(p.join(root.path, androidMainManifestPath));
    final manifestUpdate = manifestFile.existsSync()
        ? addAndroidInternetPermission(await manifestFile.readAsString())
        : null;

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
      manifestFile: manifestFile,
      manifestUpdate: manifestUpdate,
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
    if (results['early-request'] as bool && results['sdk-key'] == null) {
      _stdout.writeln(
        'Next: add your publishable key under '
        'targets.\$default.builders.$earlyRequestBuilderKey.options in '
        'build.yaml as api_key (the key you pass to Restage.configure), or '
        're-run with --sdk-key rs_pk_... Builds stop until it is set, '
        'unless you pass --no-early-request.',
      );
    }

    if (manifestUpdate != null) {
      await manifestFile.writeAsString(manifestUpdate);
      _stdout.writeln(
        'Added the INTERNET permission to '
        'android/app/src/main/AndroidManifest.xml. Release builds can now '
        'reach Restage.',
      );
    } else if (manifestFile.existsSync()) {
      _stdout.writeln('AndroidManifest.xml already allows network access.');
    }

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
    if (config.previewWrapper == null) {
      _stdout.writeln(
        'If your surfaces need something your app provides above them, such '
        'as a theme, add `previewWrapper: lib/restage_preview.dart#wrapPreview` '
        'to restage_config.yaml (or pass --preview-wrapper), where '
        '`wrapPreview` is `Widget wrapPreview(Widget child)`.',
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
      flutterRoot: existing.flutterRoot,
      previewWrapper: config.previewWrapper ?? existing.previewWrapper,
    );
    await writeRestageConfig(file, merged);
  }

  /// Exit code when init stops: 1 for a refusal, 2 for a system error.
  int _failureExit = 1;

  static const _unchecked =
      'Continuing with the slugs you passed; they were not checked.';

  Future<_InitContext?> _resolveInitContext(ArgResults results) async {
    final organizationFlag = _flag(results, 'organization');
    final projectFlag = _flag(results, 'project');
    final appFlag = _flag(results, 'app');
    final envFlag = _flag(results, 'env');

    final store = _credentialStore ?? FileCredentialStore.atDefaultLocation();
    final credential = await store.read();
    final explicitPlane = results.wasParsed('plane')
        ? RuntimePlane.fromWireName(results['plane'] as String)
        : null;
    final flagsContext = _InitContext(
      organization: organizationFlag,
      project: projectFlag ?? '',
      app: appFlag ?? '',
      environment: envFlag,
      endpoint: credential?.endpoint,
      plane: explicitPlane ?? RuntimePlane.sandbox,
    );
    final allFlags = projectFlag != null && appFlag != null && envFlag != null;
    if (allFlags && credential == null) {
      _stderr.writeln(_unchecked);
      return flagsContext;
    }

    if (credential != null) {
      var unreachable = false;
      final discovered = await _discoverContext(
        credential: credential,
        organizationFlag: organizationFlag,
        projectFlag: projectFlag,
        appFlag: appFlag,
        envFlag: envFlag,
        explicitPlane: explicitPlane,
        onUnreachable: () => unreachable = true,
      );
      if (discovered != null) return discovered;
      // With every selector given, an unreachable backend still initializes
      // from the flags alone; a refusal or a bad credential does not.
      if (allFlags && unreachable) {
        _stderr.writeln(_unchecked);
        return flagsContext;
      }
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
        plane: explicitPlane ?? RuntimePlane.sandbox,
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
    required RuntimePlane? explicitPlane,
    required void Function() onUnreachable,
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

      final targets = scope.targets(
        projectSlug: project.slug,
        appSlug: app.slug,
      );
      final choice = await _chooseEnvironment(
        targets: targets,
        envFlag: envFlag,
        explicitPlane: explicitPlane,
      );
      if (choice == null) return null;
      final selectedTarget = choice.target;

      return _InitContext(
        organization: organization.slug,
        project: project.slug,
        app: app.slug,
        environment: selectedTarget?.environmentSlug,
        plane: choice.plane,
        endpoint: credential.endpoint,
        organizationId: organization.organizationId,
        appId: app.appId,
        environmentTargetId: selectedTarget?.environmentTargetId,
        namedEnvironmentId: selectedTarget?.namedEnvironmentId,
      );
    } on RestageApiException catch (e) {
      final outcome = renderApiError(e);
      _failureExit = outcome.exitCode;
      _stderr.writeln(outcome.message);
      return null;
    } on FormatException catch (e) {
      _failureExit = 2;
      _stderr.writeln('Could not discover your Restage context: ${e.message}');
      return null;
    } on SocketException catch (e) {
      onUnreachable();
      _failureExit = 2;
      _stderr.writeln(backendUnreachableMessage(api.endpoint, e));
      return null;
    } on http.ClientException catch (e) {
      onUnreachable();
      _failureExit = 2;
      _stderr.writeln(backendUnreachableMessage(api.endpoint, e));
      return null;
    } finally {
      if (_httpClient == null) api.close();
    }
  }

  /// The target `init` records. Slugs repeat across planes, so a named
  /// environment is one slug on the plane it is chosen on.
  Future<({EnvironmentTargetSummary? target, RuntimePlane plane})?>
  _chooseEnvironment({
    required List<EnvironmentTargetSummary> targets,
    required String? envFlag,
    required RuntimePlane? explicitPlane,
  }) async {
    if (targets.isEmpty) {
      return (target: null, plane: explicitPlane ?? RuntimePlane.sandbox);
    }
    if (envFlag != null) {
      final named = targets.where((t) => t.environmentSlug == envFlag);
      if (named.isEmpty) {
        final existing = {for (final t in targets) t.environmentSlug};
        _stderr.writeln(
          'No environment `$envFlag` in this app. '
          'Environments: ${existing.join(', ')}.',
        );
        return null;
      }
      final RuntimePlane plane;
      if (explicitPlane != null) {
        plane = explicitPlane;
      } else if (named.any((t) => t.runtimePlane == RuntimePlane.sandbox)) {
        plane = RuntimePlane.sandbox;
      } else {
        plane = named.first.runtimePlane;
      }
      final match = named.where((t) => t.runtimePlane == plane).firstOrNull;
      if (match == null) {
        final other = named.first.runtimePlane.name;
        _stderr.writeln(
          '`$envFlag` has no ${plane.name} environment. Pass --plane $other.',
        );
        return null;
      }
      return (target: match, plane: plane);
    }

    final plane =
        explicitPlane ??
        (targets.any((t) => t.runtimePlane == RuntimePlane.sandbox)
            ? RuntimePlane.sandbox
            : targets.first.runtimePlane);
    final seen = <String>{};
    final onPlane = [
      for (final target in targets)
        if (target.runtimePlane == plane && seen.add(target.environmentSlug))
          target,
    ];
    if (onPlane.isEmpty) {
      final other = targets.first.runtimePlane.name;
      _stderr.writeln(
        'This app has no ${plane.name} environment. Pass --plane $other.',
      );
      return null;
    }
    if (onPlane.length == 1) return (target: onPlane.single, plane: plane);
    if (_interactive.isInteractive) {
      final picked = await _interactive.select<EnvironmentTargetSummary>(
        'Which default environment?',
        [
          for (final target in onPlane)
            (label: target.environmentSlug, value: target),
        ],
      );
      return (target: picked, plane: plane);
    }
    final first = onPlane.first;
    _stdout.writeln(
      'Using environment `${first.environmentSlug}` (${plane.name}). Pass '
      '--env <slug> to choose another: '
      '${onPlane.map((t) => t.environmentSlug).join(', ')}.',
    );
    return (target: first, plane: plane);
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
    required File manifestFile,
    required String? manifestUpdate,
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
    if (manifestFile.existsSync()) {
      _stdout.writeln(
        '  ${manifestUpdate == null ? 'keep' : 'update'} ${manifestFile.path} '
        '(Add the INTERNET permission for release builds)',
      );
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
    required this.plane,
    this.environment,
    this.organization,
    this.endpoint,
    this.organizationId,
    this.appId,
    this.environmentTargetId,
    this.namedEnvironmentId,
  });

  final String? organization;
  final RuntimePlane plane;
  final String project;
  final String app;
  final String? environment;
  final String? endpoint;
  final int? organizationId;
  final int? appId;
  final int? environmentTargetId;
  final int? namedEnvironmentId;
}
