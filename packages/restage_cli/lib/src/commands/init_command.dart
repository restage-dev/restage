import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/api/app_admin_api.dart';
import 'package:restage_cli/src/api/backend_sites.dart' show configuredBackend;
import 'package:restage_cli/src/api/delivery_keys_api.dart';
import 'package:restage_cli/src/api/scope_snapshot_api.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/typed_error_models.dart';
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
        AddDependenciesResult,
        addDependencies,
        complexConstraintMarker,
        planAddDependencies;
import 'package:restage_cli/src/init/starter_paywall.dart';
import 'package:restage_cli/src/render_bundles/surface_capture_source.dart'
    show SurfaceCaptureSourceException, SurfaceCaptureWrapper;
import 'package:restage_cli/src/io/interactive.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'package:restage_shared/restage_shared.dart' show canonicalServiceUrl;

/// The public repository the wired-in Restage packages come from.
const String restageGitUrl = 'https://github.com/restage-dev/restage.git';

/// A git source for the package at [path] in the Restage repository's `main`.
Map<String, Object> restageGitSource(String path) => {
  'git': {'url': restageGitUrl, 'ref': 'main', 'path': path},
};

/// The dependencies init adds, all Restage packages from the same `main`.
final Map<String, Object> initRuntimeDeps = {
  'restage': restageGitSource('packages/restage'),
  'restage_material': restageGitSource('packages/restage_material'),
};

/// The dev dependencies init adds.
final Map<String, Object> initDevDeps = {
  'build_runner': '>=2.7.0 <3.0.0',
  'restage_codegen': restageGitSource('packages/restage_codegen'),
};

/// Every Restage package an app may list, from that `main`. Init moves an
/// entry given as a version constraint to this source.
final Map<String, Object> restageSources = {
  for (final name in const [
    'restage',
    'restage_a2ui',
    'restage_codegen',
    'restage_compiler_core',
    'restage_core',
    'restage_cupertino',
    'restage_material',
    'restage_measurement_schema',
    'restage_revenuecat',
    'restage_shared',
    'restage_store_bridge',
    'restage_svg',
    'rfw_catalog_compiler',
    'rfw_catalog_schema',
  ])
    name: restageGitSource('packages/$name'),
};

/// The Flutter asset the iOS plugin reads the first-launch request from.
const String iosEarlyTemplateAsset = 'ios/Runner/restage_early.json';

/// The overrides that keep every Restage package on that `main`, including
/// packages added later that ask for these by version.
final Map<String, Object> initOverrides = {
  'restage': restageGitSource('packages/restage'),
  'restage_material': restageGitSource('packages/restage_material'),
  'rfw_catalog_schema': restageGitSource('packages/rfw_catalog_schema'),
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
            'Your app\'s publishable key (rs_pk_...). Without it, a signed-in '
            'init keeps the key build.yaml has, or mints a public key for the '
            'environment. Written to build.yaml, '
            'so the app sends its first request before Dart starts and '
            'Restage.configure uses it by default. In an app with an iOS '
            'folder, ios/Runner/restage_early.json is also listed under '
            'flutter assets in pubspec.yaml, with or without --add-deps.',
      )
      ..addFlag(
        'starter',
        help: 'Write a starter `@Paywall` to `lib/paywalls/`.',
        defaultsTo: true,
      )
      ..addFlag(
        'add-deps',
        help:
            'Add `restage` and `restage_material` (dependencies), '
            '`restage_codegen` and `build_runner` (dev_dependencies), and the '
            'overrides they need to pubspec.yaml. Restage packages come from '
            'the main branch of github.com/restage-dev/restage.',
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

    final force = results['force'] as bool;
    final configFile = File(p.join(root.path, 'restage_config.yaml'));
    final existing = await _readConfig(configFile);
    final retarget =
        existing != null && !force && _namesNewTarget(results, existing);

    final context = await _resolveInitContext(
      results,
      seed: retarget ? existing : null,
    );
    if (context == null) {
      return _failureExit;
    }

    final previewWrapper = _flag(results, 'preview-wrapper');
    final config = existing != null && retarget
        ? _retargeted(existing, context, previewWrapper)
        : RestageConfig(
            project: context.project,
            app: context.app,
            defaultEnvironment: context.environment,
            organization: context.organization,
            endpoint: context.endpoint,
            plane: context.plane,
            previewWrapper: previewWrapper,
            organizationId: context.organizationId,
            appId: context.appId,
            environmentTargetId: context.environmentTargetId,
            namedEnvironmentId: context.namedEnvironmentId,
          );

    final wantsStarter = results['starter'] as bool;
    final wantsDeps = results['add-deps'] as bool;
    final dryRun = results['dry-run'] as bool;

    final buildYamlFile = File(p.join(root.path, 'build.yaml'));
    final buildYamlSource = buildYamlFile.existsSync()
        ? await buildYamlFile.readAsString()
        : null;
    final sdkKey = results['sdk-key'] as String?;
    // Signed in with no key given or kept in build.yaml, init mints one.
    final keptBuildYaml = planBuildYaml(buildYamlSource);
    final mintsKey =
        sdkKey == null &&
        context.credential != null &&
        context.environment != null &&
        keptBuildYaml.action != StateBuildInputsAction.manual &&
        !keptBuildYaml.hasApiKey;
    final plannedKey = sdkKey ?? (mintsKey ? _mintedKeyPlaceholder : null);
    // With a key, the service URL comes from the sign-in, else the backend
    // every other command uses; init names it when it isn't the sign-in's.
    final signedInUrl = context.endpoint;
    final serviceUrl = plannedKey == null
        ? null
        : canonicalServiceUrl(
            signedInUrl ??
                (await configuredBackend(
                  credentialStore: _credentialStore,
                )).toString(),
          );
    // Delivery keys go only into a build that has a publishable key.
    final delivery = plannedKey != null || keptBuildYaml.hasApiKey
        ? await _readDeliveryKeys(context)
        : (keys: const <String>[], note: null);
    var buildYamlPlan = planBuildYaml(
      buildYamlSource,
      apiKey: plannedKey,
      baseUrl: serviceUrl,
      deliveryKeys: delivery.keys,
    );
    final hasIos = Directory(p.join(root.path, 'ios', 'Runner')).existsSync();

    var assets = [if (hasIos && buildYamlPlan.hasApiKey) iosEarlyTemplateAsset];
    // The iOS asset is listed whether or not init adds dependencies.
    final editsPubspec = wantsDeps || assets.isNotEmpty;
    final deps = wantsDeps ? initRuntimeDeps : const <String, Object>{};
    final devDeps = wantsDeps ? initDevDeps : const <String, Object>{};
    final overrides = wantsDeps ? initOverrides : const <String, Object>{};
    final sources = wantsDeps ? restageSources : const <String, Object>{};
    // Read the pubspec once; both the dry-run plan and the apply path
    // consume the same source.
    final pubspecSource = editsPubspec ? await pubspec.readAsString() : '';
    // A pubspec the editor can't walk is refused before anything is written.
    if (editsPubspec && _parsesWithoutMap(pubspecSource)) {
      _stderr.writeln(
        'pubspec.yaml does not parse as a map of keys, so init changed '
        'nothing. Try fixing it, then run init again.',
      );
      return 1;
    }
    if (editsPubspec) {
      if (_nonMapBlock(pubspecSource) case final key?) {
        _stderr.writeln(
          'pubspec.yaml gives `$key` as something other than a map of '
          'entries, so init changed nothing. Try writing it as a map, then '
          'run init again.',
        );
        return 1;
      }
    }
    AddDependenciesPlan? pubspecPlan;
    try {
      pubspecPlan = editsPubspec
          ? planAddDependencies(
              pubspecSource,
              deps: deps,
              devDeps: devDeps,
              overrides: overrides,
              sources: sources,
              flutterAssets: assets,
            )
          : null;
    } on FormatException catch (error) {
      _stderr.writeln(
        'pubspec.yaml does not parse, so init changed nothing: '
        '${_describe(error)}. Try fixing that line, then run init again.',
      );
      return 1;
    }

    final starterFile = File(
      p.join(root.path, 'lib', 'paywalls', 'starter.dart'),
    );
    final gitignoreFile = File(p.join(root.path, '.gitignore'));
    final gitignoreExists = gitignoreFile.existsSync();
    final gitignoreSource = gitignoreExists
        ? await gitignoreFile.readAsString()
        : '';
    final gitignorePlan = planPortableOutputIgnores(gitignoreSource);
    final manifestFile = File(p.join(root.path, androidMainManifestPath));
    final manifestUpdate = manifestFile.existsSync()
        ? addAndroidInternetPermission(await manifestFile.readAsString())
        : null;

    final configAction = !configFile.existsSync()
        ? 'create'
        : force || retarget
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
      mintsKeyFor: mintsKey
          ? '`${context.environment}` (${context.plane.wireName})'
          : null,
    );

    if (dryRun) return 0;

    final configExists = configFile.existsSync();
    final writesConfig =
        !configExists ||
        force ||
        retarget ||
        (_interactive.isInteractive &&
            await _interactive.confirm(
              'restage_config.yaml already exists. Update it with these '
              'values?',
            ));

    // Composed and checked before anything is written or minted.
    AddDependenciesResult? composePubspec() =>
        pubspecPlan != null && !pubspecPlan.isNoOp
        ? addDependencies(
            pubspecSource,
            deps: deps,
            devDeps: devDeps,
            overrides: overrides,
            sources: sources,
            flutterAssets: assets,
          )
        : null;
    var pubspecResult = composePubspec();
    if (pubspecResult != null && !_parsesAsMap(pubspecResult.source)) {
      _stderr.writeln(_unsafePubspec);
      return 1;
    }

    // What init says about the key after writing build.yaml.
    String? keyNote;
    var key = sdkKey;
    if (mintsKey) {
      String? minted;
      // A kept config may name another target than discovery found.
      if (writesConfig || _sameTarget(existing, context)) {
        final outcome = await _mintPublicKey(context);
        minted = outcome.key;
        keyNote = outcome.note;
      } else {
        keyNote = _keptOtherTargetNote(existing, context);
      }
      key = minted;
      buildYamlPlan = planBuildYaml(
        buildYamlSource,
        apiKey: minted,
        baseUrl: minted == null ? null : serviceUrl,
        deliveryKeys: minted == null ? const [] : delivery.keys,
      );
      final nextAssets = [
        if (hasIos && buildYamlPlan.hasApiKey) iosEarlyTemplateAsset,
      ];
      if (nextAssets.length != assets.length) {
        assets = nextAssets;
        pubspecPlan = wantsDeps || assets.isNotEmpty
            ? planAddDependencies(
                pubspecSource,
                deps: deps,
                devDeps: devDeps,
                overrides: overrides,
                sources: sources,
                flutterAssets: assets,
              )
            : null;
        pubspecResult = composePubspec();
        if (pubspecResult != null && !_parsesAsMap(pubspecResult.source)) {
          _stderr.writeln(_unsafePubspec);
          return 1;
        }
      }
    }

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

    await _applyBuildYaml(
      buildYamlFile,
      buildYamlPlan,
      apiKey: key,
      baseUrl: key == null ? null : serviceUrl,
      deliveryKeys: key == null && !keptBuildYaml.hasApiKey
          ? const []
          : delivery.keys,
    );
    if (delivery.note case final note?) {
      _stdout.writeln(note);
    } else if (buildYamlPlan.hasApiKey && !buildYamlPlan.hasDeliveryKeys) {
      _stdout.writeln(_noDeliveryKeysNote(context));
    }
    if (keyNote != null) {
      _stdout.writeln(keyNote);
    } else if (!buildYamlPlan.hasApiKey) {
      _stdout.writeln(_noKeyNote(context));
    } else if (serviceUrl != null &&
        signedInUrl == null &&
        buildYamlPlan.written.contains('the service URL')) {
      _stdout.writeln(
        "You aren't signed in, so build.yaml uses $serviceUrl as the service "
        'URL. If your app uses another server, try replacing `base_url` '
        'under $deliveryOptionsBuilderKey in build.yaml with its URL.',
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

    if (!configExists) {
      await writeRestageConfig(configFile, config);
      _stdout.writeln('Wrote restage_config.yaml.');
      _reportEndpoint(context);
    } else if (writesConfig) {
      await _updateConfig(configFile, config, retarget ? null : existing);
      _stdout.writeln(
        retarget
            ? 'Updated the target in restage_config.yaml to match your flags. '
                  'Other settings are unchanged.'
            : 'Updated restage_config.yaml.',
      );
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

    if (pubspecResult case final result?) {
      await pubspec.writeAsString(result.source);
      if (result.converted.isNotEmpty) {
        _stdout.writeln(
          'Moved ${result.converted.join(', ')} from pub.dev to the main '
          'branch of github.com/restage-dev/restage, so every Restage '
          'package comes from one commit.',
        );
      }
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

    // A listed asset must exist before the first build writes it.
    final placeholder = File(p.join(root.path, iosEarlyTemplateAsset));
    if (hasIos &&
        !placeholder.existsSync() &&
        _listsAsset(await pubspec.readAsString(), iosEarlyTemplateAsset)) {
      await placeholder.writeAsString('{}\n');
      _stdout.writeln(
        'Wrote an empty $iosEarlyTemplateAsset; the next build fills it.',
      );
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

  Future<void> _applyBuildYaml(
    File file,
    StateBuildInputsPlan plan, {
    String? apiKey,
    String? baseUrl,
    List<String> deliveryKeys = const [],
  }) async {
    final written = _joined(plan.written);
    switch (plan.action) {
      case StateBuildInputsAction.create:
        await file.writeAsString(plan.source);
        _stdout.writeln('Wrote build.yaml: $written.');
      case StateBuildInputsAction.update:
        await file.writeAsString(plan.source);
        _stdout.writeln('Updated build.yaml: $written.');
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
        if (apiKey != null || baseUrl != null || deliveryKeys.isNotEmpty) {
          _stdout.writeln(
            'and these options under '
            'targets.\$default.builders.$deliveryOptionsBuilderKey.options:',
          );
          if (apiKey != null) _stdout.writeln('  api_key: $apiKey');
          if (baseUrl != null) _stdout.writeln('  base_url: $baseUrl');
          if (deliveryKeys.isNotEmpty) {
            _stdout.writeln('  delivery_keys:');
            for (final key in deliveryKeys) {
              _stdout.writeln('    - $key');
            }
          }
        }
    }
    for (final option in plan.kept) {
      if (option == 'delivery_keys') {
        _stdout.writeln(
          'build.yaml sets delivery_keys under $deliveryOptionsBuilderKey to '
          'something other than a list, so it was kept. Try listing the keys '
          '`restage keys delivery` prints there.',
        );
        continue;
      }
      final given = option == 'api_key' ? apiKey : baseUrl;
      _stdout.writeln(
        'build.yaml already sets a different $option under '
        '$deliveryOptionsBuilderKey, so it was kept. Try replacing it there '
        'with `$option: $given` if you meant to change it.',
      );
    }
  }

  /// The app's delivery keys when discovery signed in, else none.
  Future<({List<String> keys, String? note})> _readDeliveryKeys(
    _InitContext context,
  ) async {
    final credential = context.credential;
    if (credential == null) return (keys: const <String>[], note: null);
    final api = RestageApi(
      endpoint: Uri.parse(credential.endpoint),
      httpClient: _httpClient,
      credential: credential,
    );
    String failed(String reason) =>
        "Could not read the app's delivery keys, so build.yaml lists none. "
        '$reason\nTry running ${_command(initFollowUp)} again.';
    try {
      final keys = await DeliveryKeysApi(api).list(
        project: context.project,
        app: context.app,
        organizationId: context.organizationId,
      );
      return (keys: keys, note: null);
    } on RestageApiException catch (e) {
      return (keys: const <String>[], note: failed(renderApiError(e).message));
    } on FormatException catch (e) {
      return (keys: const <String>[], note: failed('${e.message}.'));
    } on TypeError {
      return (
        keys: const <String>[],
        note: failed('The response held no keys.'),
      );
    } on SocketException catch (e) {
      return (
        keys: const <String>[],
        note: failed(backendUnreachableMessage(api.endpoint, e)),
      );
    } on http.ClientException catch (e) {
      return (
        keys: const <String>[],
        note: failed(backendUnreachableMessage(api.endpoint, e)),
      );
    } finally {
      if (_httpClient == null) api.close();
    }
  }

  /// Why delivered versions will not render without delivery keys, and how
  /// to add them.
  static String _noDeliveryKeysNote(_InitContext context) {
    final keys = _command(
      const FollowUp('keys delivery', 'restage_delivery_keys'),
    );
    final how = context.credential == null
        ? 'Try ${_command(loginFollowUp)}, then run ${_command(initFollowUp)} '
              'again, or list'
        : 'Try listing';
    return 'build.yaml has a publishable key but no delivery keys, so the app '
        'refuses every delivered version and shows its compiled widgets. '
        '$how each `<organizationId>:<key>` line $keys prints, after its '
        'first line, under delivery_keys in build.yaml.';
  }

  /// Planned in place of the key a signed-in init mints.
  static const _mintedKeyPlaceholder = 'rs_pk_...';

  static const _unsafePubspec =
      'Could not update pubspec.yaml safely, so init changed nothing. Try '
      'adding the entries `restage init --dry-run` lists by hand, then run '
      'init again.';

  /// Why a kept config that names another target got no key.
  static String _keptOtherTargetNote(
    RestageConfig? existing,
    _InitContext context,
  ) {
    final kept = existing?.defaultEnvironment;
    final problem =
        'restage_config.yaml was kept and does not name the '
        '`${context.environment}` environment init found, so init minted no '
        "publishable key and the first-launch request isn't built into the "
        'app.';
    if (existing == null || kept == null) {
      return '$problem Try `restage init --force` to update the config and '
          'mint a key for it.';
    }
    final flags = [
      if (existing.organization case final org?
          when org != context.organization)
        '--organization $org',
      if (existing.project != context.project) '--project ${existing.project}',
      if (existing.app != context.app) '--app ${existing.app}',
      '--env $kept',
      if (existing.plane case final plane? when plane != context.plane)
        '--plane ${plane.wireName}',
    ];
    return '$problem Try `restage init ${flags.join(' ')}` to mint a key for '
        'the environment in restage_config.yaml.';
  }

  /// Whether [existing] names the target [context] resolved.
  static bool _sameTarget(RestageConfig? existing, _InitContext context) =>
      existing != null &&
      existing.project == context.project &&
      existing.app == context.app &&
      existing.defaultEnvironment == context.environment &&
      (existing.plane == null || existing.plane == context.plane) &&
      (existing.organization == null ||
          existing.organization == context.organization);

  /// Mints a public key at [context]'s environment. A refusal or an
  /// unreachable backend leaves init to finish without a key.
  Future<({String? key, String note})> _mintPublicKey(
    _InitContext context,
  ) async {
    final credential = context.credential!;
    final api = RestageApi(
      endpoint: Uri.parse(credential.endpoint),
      httpClient: _httpClient,
      credential: credential,
    );
    String failed(String reason) =>
        "Could not mint a publishable key, so the first-launch request isn't "
        'built into the app. $reason\nTry running ${_command(initFollowUp)} '
        'again, or ${_command(_initWithKey)} with your app\'s publishable '
        'key.';
    try {
      final result = await AppAdminApi(api).mintPublicKey(
        project: context.project,
        app: context.app,
        environment: context.environment!,
        environmentTargetId: context.environmentTargetId,
        runtimePlane: context.plane,
        organizationId: context.organizationId,
      );
      final key = result['plaintext'];
      final view = result['view'];
      if (key is! String || key.isEmpty) {
        return (key: null, note: failed('The response held no key.'));
      }
      final id = view is Map ? view['id'] : null;
      return (
        key: key,
        note:
            'Minted public key${id == null ? '' : ' $id'} for '
            '`${context.environment}` (${context.plane.wireName}) and wrote '
            'it to build.yaml.',
      );
    } on RestageApiException catch (e) {
      if (decodeGenericTypedException(e.body) case UnauthorizedAccess(
        reason: UnauthorizedReason.roleMissing,
      )) {
        return (
          key: null,
          note:
              'Could not mint a publishable key: only an organization admin '
              "can mint one, so the first-launch request isn't built into the "
              "app. Try asking an admin for the app's publishable key, then "
              'run ${_command(_initWithKey)}.',
        );
      }
      return (key: null, note: failed(renderApiError(e).message));
    } on FormatException catch (e) {
      return (key: null, note: failed('${e.message}.'));
    } on SocketException catch (e) {
      return (
        key: null,
        note: failed(backendUnreachableMessage(api.endpoint, e)),
      );
    } on http.ClientException catch (e) {
      return (
        key: null,
        note: failed(backendUnreachableMessage(api.endpoint, e)),
      );
    } finally {
      if (_httpClient == null) api.close();
    }
  }

  static const _initWithKey = FollowUp('init', 'restage_init', [
    FollowUpArg('sdkKey', 'rs_pk_...', flag: 'sdk-key'),
  ]);

  static String _command(FollowUp next) => currentSelectorSyntax.command(next);

  /// Why build.yaml has no key when init did not try to mint one.
  static String _noKeyNote(_InitContext context) {
    const missing =
        "No publishable key, so the first-launch request isn't built into "
        'the app.';
    final init = _command(initFollowUp);
    final withKey = _command(_initWithKey);
    if (context.endpoint == null) {
      return '$missing Try ${_command(loginFollowUp)}, then run $init again '
          'to mint one, or $withKey.';
    }
    if (context.credential == null) {
      return '$missing Try running $init again once Restage is reachable, or '
          '$withKey.';
    }
    if (context.environment == null) {
      return '$missing This app has no environment to mint one for. Try '
          'adding an environment in the dashboard, then run $init again.';
    }
    return '$missing Try $withKey when you set up hosted delivery.';
  }

  static String _joined(List<String> parts) => parts.length < 2
      ? parts.join()
      : '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';

  void _reportEndpoint(_InitContext context) {
    final endpoint = context.endpoint;
    if (endpoint == null) return;
    _stdout.writeln('Set endpoint: $endpoint (from your stored sign-in).');
  }

  /// Writes [config] over [file], keeping the settings init does not ask
  /// about from [existing].
  Future<void> _updateConfig(
    File file,
    RestageConfig config,
    RestageConfig? existing,
  ) async {
    if (existing == null) {
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

  /// Resolves the target, taking selectors no flag passes from [seed].
  Future<_InitContext?> _resolveInitContext(
    ArgResults results, {
    RestageConfig? seed,
  }) async {
    final organizationFlag =
        _flag(results, 'organization') ?? seed?.organization;
    final projectFlag = _flag(results, 'project') ?? seed?.project;
    final appFlag = _flag(results, 'app') ?? seed?.app;
    final envFlag = _flag(results, 'env') ?? seed?.defaultEnvironment;

    final store = _credentialStore ?? FileCredentialStore.atDefaultLocation();
    final credential = await store.read();
    final explicitPlane = _planeFlag(results) ?? seed?.plane;
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
        credential: credential,
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

  /// The config in [file], or null when it is missing or does not parse.
  Future<RestageConfig?> _readConfig(File file) async {
    if (!file.existsSync()) return null;
    try {
      return RestageConfig.fromYaml(await file.readAsString());
    } on RestageConfigFormatException {
      return null;
    }
  }

  /// Whether a target flag names a value [existing] does not hold.
  bool _namesNewTarget(ArgResults results, RestageConfig existing) {
    bool differs(String flag, String? current) {
      final value = _flag(results, flag);
      return value != null && value != current;
    }

    final plane = _planeFlag(results);
    return differs('organization', existing.organization) ||
        differs('project', existing.project) ||
        differs('app', existing.app) ||
        differs('env', existing.defaultEnvironment) ||
        (plane != null && plane != existing.plane);
  }

  /// [existing] with its target replaced by [context]. Ids for a target that
  /// changed are dropped unless [context] resolved new ones.
  RestageConfig _retargeted(
    RestageConfig existing,
    _InitContext context,
    String? previewWrapper,
  ) {
    final sameOrganization = context.organization == existing.organization;
    final sameApp =
        sameOrganization &&
        context.project == existing.project &&
        context.app == existing.app;
    return RestageConfig(
      project: context.project,
      app: context.app,
      defaultEnvironment: context.environment,
      organization: context.organization,
      endpoint: context.endpoint ?? existing.endpoint,
      plane: context.plane,
      recordGit: existing.recordGit,
      declareAssets: existing.declareAssets,
      flutterRoot: existing.flutterRoot,
      previewWrapper: previewWrapper ?? existing.previewWrapper,
      organizationId:
          context.organizationId ??
          (sameOrganization ? existing.organizationId : null),
      appId: context.appId ?? (sameApp ? existing.appId : null),
      environmentTargetId: context.environmentTargetId,
      namedEnvironmentId: context.namedEnvironmentId,
    );
  }

  RuntimePlane? _planeFlag(ArgResults results) => results.wasParsed('plane')
      ? RuntimePlane.fromWireName(results['plane'] as String)
      : null;

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
    required String? mintsKeyFor,
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
        _stdout.writeln(
          '    dependencies: + ${entry.key}: ${_renderSource(entry.value)}',
        );
      }
      for (final entry in pubspecPlan.dependenciesToKeep.entries) {
        _stdout.writeln(
          '    dependencies: = ${entry.key}: '
          '${_renderConstraint(entry.value)} (kept)',
        );
      }
      for (final entry in pubspecPlan.devDependenciesToAdd.entries) {
        _stdout.writeln(
          '    dev_dependencies: + ${entry.key}: '
          '${_renderSource(entry.value)}',
        );
      }
      for (final entry in pubspecPlan.devDependenciesToKeep.entries) {
        _stdout.writeln(
          '    dev_dependencies: = ${entry.key}: '
          '${_renderConstraint(entry.value)} (kept)',
        );
      }
      for (final name in pubspecPlan.toConvert) {
        _stdout.writeln('    $name: pub.dev -> git main');
      }
      for (final asset in pubspecPlan.assetsToAdd) {
        _stdout.writeln('    flutter assets: + $asset');
      }
      for (final entry in pubspecPlan.overridesToAdd.entries) {
        _stdout.writeln(
          '    dependency_overrides: + ${entry.key}: '
          '${_renderSource(entry.value)}',
        );
      }
      for (final entry in pubspecPlan.overridesToKeep.entries) {
        _stdout.writeln(
          '    dependency_overrides: = ${entry.key}: '
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
    final buildYamlChanges = buildYamlPlan.written.isEmpty
        ? 'track Restage state files'
        : _joined(buildYamlPlan.written);
    _stdout.writeln(
      '  $buildYamlAction ${buildYamlFile.path} ($buildYamlChanges)',
    );
    if (mintsKeyFor != null) {
      _stdout.writeln(
        '  mint a public key for $mintsKeyFor and write it to build.yaml',
      );
    }
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

  static bool _listsAsset(String pubspec, String asset) {
    try {
      final assets = (loadYaml(pubspec) as YamlMap?)?['flutter']?['assets'];
      return assets is YamlList && assets.contains(asset);
    } on Object {
      return false;
    }
  }

  // The first block init edits that holds entries but isn't a map, or null.
  static String? _nonMapBlock(String source) {
    final Object? doc;
    try {
      doc = loadYaml(source);
    } on YamlException {
      return null;
    }
    if (doc is! YamlMap) return null;
    for (final key in const [
      'dependencies',
      'dev_dependencies',
      'dependency_overrides',
      'flutter',
    ]) {
      final value = doc[key];
      final empty =
          value == null ||
          (value is String && value.isEmpty) ||
          (value is YamlList && value.isEmpty);
      if (!empty && value is! YamlMap) return key;
    }
    return null;
  }

  // The parse error's message without its final period, with its line.
  static String _describe(FormatException error) {
    final message = error.message.replaceFirst(RegExp(r'\.+$'), '');
    final line = error is YamlException ? error.span?.start.line : null;
    return line == null ? message : '$message at line ${line + 1}';
  }

  // A YAML parse error is reported with its line by the plan instead.
  static bool _parsesWithoutMap(String source) {
    try {
      return loadYaml(source) is! YamlMap;
    } on YamlException {
      return false;
    }
  }

  static bool _parsesAsMap(String source) {
    try {
      return loadYaml(source) is YamlMap;
    } on YamlException {
      return false;
    }
  }

  /// Render a constraint or a git source as one short phrase.
  String _renderSource(Object value) => switch (value) {
    {'git': {'ref': final Object ref, 'path': final Object path}} =>
      'git $ref ($path)',
    _ => '$value',
  };
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
    this.credential,
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

  /// The sign-in discovery succeeded with, or null when it did not run.
  final Credential? credential;
}
