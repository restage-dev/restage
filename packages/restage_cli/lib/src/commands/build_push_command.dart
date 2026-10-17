import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/api/render_bundle_api.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/selector_syntax.dart';
import 'package:restage_cli/src/api/typed_error_models.dart';
import 'package:restage_cli/src/api/typed_error_renderer.dart'
    show targetSelectionSentence;
import 'package:restage_cli/src/commands/organization_resolution.dart';
import 'package:restage_cli/src/config/restage_config.dart';
import 'package:restage_cli/src/credentials/credential.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/receipts/release_recorder.dart';
import 'package:restage_cli/src/receipts/render_bundle_receipt.dart';
import 'package:restage_cli/src/receipts/source_boundary.dart';
import 'package:restage_cli/src/render_bundles/bundle_source.dart';
import 'package:restage_cli/src/render_bundles/flutter_render_bundle_builder.dart';
import 'package:restage_cli/src/render_bundles/flutter_toolchain.dart';
import 'package:restage_cli/src/render_bundles/generated_widget_catalog.dart';
import 'package:restage_cli/src/render_bundles/push_target.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_cli/src/render_bundles/render_bundle_archive.dart';

/// Environment variable carrying a secret key for an unattended push. It is
/// read here only; a flag or the configuration file cannot supply it.
const _apiKeyVariable = 'RESTAGE_API_KEY';

/// Environment variable naming the only server other than the built-in one a
/// key may be sent to.
const _endpointVariable = 'RESTAGE_BACKEND_URL';

/// Opens the repository a receipt is written into.
typedef ReleaseRecorderOpener =
    Future<ReleaseRecorder> Function({required Directory projectRoot});

/// Writes the receipt one push earned.
typedef RenderBundlePushReceipt =
    Future<bool> Function({
      required ReleaseRecorder recorder,
      required int organizationId,
      required String organization,
      required String project,
      required String app,
      required String head,
      required int version,
      required String contentHash,
      required String engineSetId,
      required bool dirty,
      required StringSink stdout,
      required StringSink stderr,
      String? environment,
      String? toolchain,
    });

/// Deterministically build and upload the main render bundle.
final class BuildPushCommand extends Command<int> {
  BuildPushCommand({
    required StringSink stdout,
    required StringSink stderr,
    FileCredentialStore? credentialStore,
    http.Client? httpClient,
    RenderBundleArtifactBuilder? builder,
    RenderBundleCatalogProducer? catalog,
    BundleSourceReader? source,
    ReleaseRecorderOpener? openRecorder,
    RenderBundlePushReceipt? recordReceipt,
    Uri? defaultEndpoint,
    Map<String, String>? environment,
    FlutterToolchainResolver? flutterToolchain,
  }) : _stdout = stdout,
       _stderr = stderr,
       _credentialStore = credentialStore,
       _httpClient = httpClient,
       _builder = builder ?? FlutterRenderBundleBuilder(),
       _catalog = catalog ?? readGeneratedWidgetCatalog,
       _source = source ?? readBundleSource,
       _openRecorder = openRecorder ?? ReleaseRecorder.open,
       _recordReceipt = recordReceipt ?? recordRenderBundlePush,
       _defaultEndpoint = defaultEndpoint,
       _environment = environment,
       _flutterToolchain = flutterToolchain ?? resolveBuildFlutterToolchain {
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
        'env',
        help:
            'Named environment head to move. An admin or a key moves one; '
            'leaving it out pushes to your own head.',
      )
      ..addFlag(
        'personal',
        negatable: false,
        help: 'Push to your own head, the one only you can move.',
      )
      ..addFlag(
        'record-git',
        negatable: false,
        help: 'Record this push as a release receipt in the repository.',
      )
      ..addOption(
        'directory',
        abbr: 'C',
        defaultsTo: '.',
        help: 'Directory to start the restage_config.yaml search from.',
      )
      ..addOption(
        'flutter-root',
        help:
            'Flutter SDK directory to build with (overrides `flutterRoot` in '
            'restage_config.yaml). By default the build uses the Flutter the '
            'app uses.',
      )
      ..addFlag(
        'generate',
        defaultsTo: true,
        help:
            'Run the code generator first. Pass --no-generate to build against '
            'the catalog a previous run produced.',
      );
    addOrganizationIdOption(argParser);
  }

  final StringSink _stdout;
  final StringSink _stderr;
  final FileCredentialStore? _credentialStore;
  final http.Client? _httpClient;
  final RenderBundleArtifactBuilder _builder;
  final RenderBundleCatalogProducer _catalog;
  final BundleSourceReader _source;
  final ReleaseRecorderOpener _openRecorder;
  final RenderBundlePushReceipt _recordReceipt;
  final Uri? _defaultEndpoint;
  final Map<String, String>? _environment;
  final FlutterToolchainResolver _flutterToolchain;

  @override
  String get name => 'push';

  @override
  String get description =>
      'Build twice, verify deterministic bytes, and move one head.';

  @override
  Future<int> run() async {
    final directory = Directory(argResults?['directory'] as String? ?? '.');
    final loaded = await loadRestageConfig(from: directory);
    final projectRoot = loaded?.source.parent ?? directory.absolute;
    var project = (argResults?['project'] as String?) ?? loaded?.config.project;
    var app = (argResults?['app'] as String?) ?? loaded?.config.app;
    final environment = _environment ?? Platform.environment;
    final key = environment[_apiKeyVariable]?.trim();
    final withKey = key != null && key.isNotEmpty;
    final environmentFlag = argResults?['env'] as String?;
    final resolved = resolveBundlePushTarget(
      environment: environmentFlag,
      personal: argResults?['personal'] as bool? ?? false,
      withKey: withKey,
    );
    final target = resolved.target;
    if (target == null) {
      _stderr.writeln(resolved.refusal!.message);
      return 1;
    }
    final Credential? credential;
    if (withKey) {
      // A key goes only to the built-in server or one the environment names;
      // a checked-in configuration file must never redirect it.
      final named = environment[_endpointVariable]?.trim();
      credential = Credential(
        endpoint: named != null && named.isNotEmpty
            ? named
            : _defaultEndpoint?.toString() ?? '',
        kind: CredentialKind.secretKey,
        authToken: key,
      );
    } else {
      final store = _credentialStore ?? FileCredentialStore.atDefaultLocation();
      credential = await store.read();
    }
    if (credential == null) {
      _stderr.writeln(_notSignedIn());
      return 1;
    }
    final Uri apiEndpoint;
    try {
      apiEndpoint = resolveApiEndpoint(
        config: loaded?.config,
        credential: credential,
      );
    } on EndpointMismatchException catch (error) {
      _stderr.writeln(
        withKey
            ? 'restage_config.yaml names ${error.configEndpoint}, but a key is '
                  'sent only to ${error.credentialEndpoint}. Set '
                  '$_endpointVariable to push to that server with a key.'
            : error.toString(),
      );
      return 1;
    } on EndpointConfigurationException catch (error) {
      _stderr.writeln(error.toString());
      return 1;
    }
    final RestageApi api;
    try {
      api = RestageApi(
        endpoint: apiEndpoint,
        httpClient: _httpClient,
        credential: credential,
      );
    } on InsecureEndpointException {
      _stderr.writeln('The configured endpoint is not permitted.');
      return 1;
    }
    try {
      if (withKey) {
        // The key names its own app; a project or app named here must agree.
        final ApiKeyTarget keyTarget;
        try {
          keyTarget = await readApiKeyTarget(api);
        } on RenderBundleUploadException catch (error) {
          _stderr.writeln(_uploadFailureMessage(error, withKey: true));
          return 2;
        } on SocketException {
          _stderr.writeln('Could not contact the backend.');
          return 2;
        }
        // Refuse what the key cannot push before anything is built.
        if (!keyTarget.secret) {
          _stderr.writeln(_rejectionMessage('not_a_secret_key', withKey: true));
          return 1;
        }
        if (!keyTarget.scopes.contains(renderBundlePushScope)) {
          _stderr.writeln(_rejectionMessage('missing_scope', withKey: true));
          return 1;
        }
        final namedEnvironment = target.environment;
        if ((project != null && project != keyTarget.projectSlug) ||
            (app != null && app != keyTarget.appSlug) ||
            (namedEnvironment != null &&
                namedEnvironment != keyTarget.target.environmentSlug)) {
          _stderr.writeln(
            targetSelectionSentence(
              const TargetSelectionRefused(
                reason: TargetSelectionRefusal.keyTargetMismatch,
              ),
              currentSelectorSyntax,
            ),
          );
          return 1;
        }
        project = keyTarget.projectSlug;
        app = keyTarget.appSlug;
      }
      if (project == null || project.isEmpty || app == null || app.isEmpty) {
        _stderr.writeln(
          missingProjectContextSentence(
            hasConfig: loaded != null,
            projectMissing: project == null || project.isEmpty,
          ),
        );
        return 1;
      }
      return await _push(
        api: api,
        config: loaded?.config,
        configDirectory: loaded?.source.parent,
        projectRoot: projectRoot,
        project: project,
        app: app,
        target: target,
        withKey: withKey,
      );
    } finally {
      if (_httpClient == null) api.close();
    }
  }

  Future<int> _push({
    required RestageApi api,
    required RestageConfig? config,
    required Directory? configDirectory,
    required Directory projectRoot,
    required String project,
    required String app,
    required BundlePushTarget target,
    required bool withKey,
  }) async {
    final origins = await _readOrigins(api);
    if (origins == null) return 1;

    final organizationSlug = resolveOrganizationSlug(
      argResults,
      config,
    )?.trim();
    final recordGit = argResults?['record-git'] as bool? ?? false;
    ReleaseRecorder? recorder;
    if (recordGit) {
      try {
        recorder = await _openRecorder(projectRoot: projectRoot);
      } on ReleaseRecorderException catch (error) {
        _stderr.writeln(error.message);
        return 1;
      }
    }

    // Read before the catalog step: the provenance describes the source the
    // push started from, and a boundary that will not resolve costs nothing.
    final BundleSource source;
    try {
      source = await _source(projectRoot, recordGit: recordGit);
    } on SourceBoundaryException catch (error) {
      _stderr.writeln(error.message);
      return 1;
    }

    final FlutterToolchain flutter;
    try {
      flutter = await _flutterToolchain(
        projectRoot: projectRoot,
        flagRoot: _flagFlutterRoot(),
        configRoot: _configFlutterRoot(config, configDirectory),
      );
    } on FlutterToolchainException catch (error) {
      _stderr.writeln('Could not build the render bundle. ${error.message}');
      return 1;
    }
    _stdout.writeln(
      'Building with Flutter ${flutter.version} at ${flutter.root} '
      '(${flutter.source}).',
    );

    final GeneratedWidgetCatalog catalog;
    try {
      catalog = await _catalog(
        projectRoot: projectRoot,
        generate: argResults?['generate'] as bool? ?? true,
        flutterExecutable: flutter.executable,
      );
    } on GeneratedCatalogException catch (error) {
      _stderr.writeln(_catalogFailureMessage(error));
      return error.reason == 'generate_failed' ? 2 : 1;
    }
    final renderCatalog = catalog.renderJson;
    if (renderCatalog == null) {
      _stderr.writeln(
        _catalogFailureMessage(
          const GeneratedCatalogException('render_catalog_missing'),
        ),
      );
      return 1;
    }
    if (!catalog.registersWidgets) {
      _stdout.writeln('This app registers no widgets of its own.');
    }

    final RenderBundleArtifact artifact;
    try {
      artifact = await _builder.build(
        projectRoot: projectRoot,
        catalogJson: renderCatalog,
        parentOrigin: origins.dashboardOrigin,
        controlOrigin: origins.bundleOrigin,
        flutterExecutable: flutter.executable,
      );
    } on RenderBundleBuildException catch (error) {
      return _reportBuildFailure(error);
    } on FileSystemException {
      return _reportBuildFailure();
    }
    if (artifact.appFiles.isEmpty) return _reportBuildFailure();
    final builtBytes = artifact.appFiles.values.fold<int>(
      0,
      (total, bytes) => total + bytes.length,
    );
    if (builtBytes > renderBundleMaxArchiveBytes) {
      _stderr.writeln(
        _uploadFailureMessage(
          RenderBundleUploadException.oversize(
            RenderBundleOversize(
              measuredBytes: builtBytes,
              limitBytes: renderBundleMaxArchiveBytes,
              compressed: false,
            ),
          ),
          withKey: withKey,
        ),
      );
      return 2;
    }
    RenderBundleApi? renderBundles;
    try {
      int? organizationId;
      if (!withKey) {
        // The shared resolver can render raw backend details. Suppress that
        // sink so this upload path preserves its generic-error contract.
        final suppressedResolutionErrors = StringBuffer();
        final configuredOrganization = await resolveConfiguredOrganization(
          api: api,
          config: config,
          stderr: suppressedResolutionErrors,
          preferredSlug: organizationSlug,
          organizationId: organizationIdOption(argResults),
        );
        if (configuredOrganization == null) {
          _stderr.writeln('Could not resolve organization context.');
          return 1;
        }
        organizationId = configuredOrganization.organizationId;
      }
      renderBundles = RenderBundleApi(
        rpc: api,
        trustedBundleOrigin: origins.bundleOrigin,
        uploadClient: _httpClient,
      );
      final outcome = await renderBundles.push(
        project: project,
        app: app,
        target: target,
        artifact: artifact,
        source: source,
        organizationId: organizationId,
      );
      final moved = outcome.appFilesSent == 0
          ? 'Every file was already stored'
          : 'Moved ${outcome.appFilesSent} of '
                '${outcome.appFilesSent + outcome.appFilesHeld} app files';
      _stdout.writeln(
        'Pushed $app ${outcome.headReference} version ${outcome.version}. '
        '$moved. ${describeBundleSource(source)}',
      );
      if (recorder == null) return 0;
      final head = parseRenderBundleHead(outcome.headReference);
      final written = await _recordReceipt(
        recorder: recorder,
        organizationId: outcome.organizationId,
        organization: outcome.organizationSlug,
        project: project,
        app: app,
        head: outcome.headReference,
        version: outcome.version,
        contentHash: outcome.contentHash,
        engineSetId: artifact.engineSetId,
        dirty: source.dirty,
        stdout: _stdout,
        stderr: _stderr,
        environment: head.environmentSlug,
        toolchain: artifact.flutterVersion,
      );
      // The bundle is pushed either way; only the receipt is in question.
      return written ? 0 : 2;
    } on RenderBundleUploadException catch (error) {
      _stderr.writeln(_uploadFailureMessage(error, withKey: withKey));
      return 2;
    } on RestageApiException {
      _stderr.writeln('Could not upload the render bundle.');
      return 1;
    } on SocketException {
      _stderr.writeln('Could not contact the backend.');
      return 2;
    } finally {
      if (_httpClient == null) renderBundles?.close();
    }
  }

  String? _flagFlutterRoot() {
    final root = (argResults?['flutter-root'] as String?)?.trim();
    return root == null || root.isEmpty ? null : p.absolute(root);
  }

  /// The configured SDK directory, relative to the config file that names it.
  static String? _configFlutterRoot(
    RestageConfig? config,
    Directory? configDirectory,
  ) {
    final root = config?.flutterRoot?.trim();
    if (root == null || root.isEmpty) return null;
    if (root.startsWith('~') || p.isAbsolute(root) || configDirectory == null) {
      return root;
    }
    return p.normalize(p.join(configDirectory.absolute.path, root));
  }

  /// The origins the server says a build trusts.
  Future<RenderBundleOrigins?> _readOrigins(RestageApi api) async {
    try {
      return await readRenderBundleOrigins(api);
    } on RenderBundleUploadException catch (error) {
      final status = error.statusCode;
      _stderr.writeln(
        error.reason == 'builds_unavailable'
            ? _noBuilds
            : status == null
            ? 'Could not read where builds go from the server.'
            : 'Could not read where builds go from the server (HTTP '
                  '$status).',
      );
    } on SocketException {
      _stderr.writeln('Could not contact the backend.');
    }
    return null;
  }

  int _reportBuildFailure([RenderBundleBuildException? error]) {
    _stderr.writeln(
      (error == null ? null : _buildFailureMessage(error)) ??
          'Could not build the render bundle.',
    );
    return 2;
  }
}

const _noBuilds = 'This server does not accept builds.';

String _notSignedIn() =>
    '${notSignedInSentence()} To push with a key, set $_apiKeyVariable.';

/// How to let the push run the code generator, worded for the caller.
String _letPushGenerate() => currentSelectorSyntax == SelectorSyntax.mcp
    ? 'leave generate unset and let the push run it'
    : 'drop --no-generate and let the push run it';

/// Turns a build failure into the sentence a reader can act on. Its detail
/// is the generated build project it is about.
String? _buildFailureMessage(RenderBundleBuildException error) {
  final project = error.detail;
  return switch (error.reason) {
    'project_identity' =>
      'Could not build the render bundle: pubspec.yaml does not name this '
          'app. Run the push from the app\'s directory.',
    'factories_missing' =>
      'Could not build the render bundle: lib/user_factories.g.dart is '
          'missing. Run `dart run build_runner build`, or ${_letPushGenerate()}.',
    'output_root' =>
      'Could not build the render bundle: the output_root in build.yaml is '
          'not a package-relative path. Fix it and push again.',
    'dependencies_unresolved' =>
      'Could not build the render bundle: this app\'s dependencies are not '
          'resolved. Run `flutter pub get` and push again.',
    'render_host_missing' =>
      'Could not build the render bundle: no restage version could be read '
          'from this app\'s dependencies. Add restage, run `flutter pub get` '
          'and push again.',
    'dependencies_failed' =>
      'Could not build the render bundle: its dependencies did not resolve. '
          'Run `flutter pub get` in ${project ?? 'the build directory'} to '
          'see why.',
    'catalog_contract' =>
      'Could not build the render bundle: the widget catalog could not be '
          'read.',
    'flutter_not_found' => 'Could not find a Flutter SDK. ${flutterRootFix()}',
    'flutter_version_unavailable' =>
      'Could not build the render bundle: `flutter --version` did not '
          'answer.',
    'flutter_build_failed' =>
      'Could not build the render bundle: `flutter build web` failed. Run '
          '`flutter build web --wasm` in '
          '${project ?? 'the build directory'} to see why.',
    'loader_contract' =>
      'Could not build the render bundle: Flutter built a web loader this '
          'CLI cannot serve. Update the restage CLI and push again.',
    'non_deterministic_output' =>
      'Could not build the render bundle: two builds of the same source '
          'differed.',
    'engine_missing' =>
      'Could not build the render bundle: `flutter build web` wrote no '
          'engine files. ${flutterRootFix()}',
    _ => null,
  };
}

/// Renders a catalog-step failure as one line a reader can act on.
String _catalogFailureMessage(GeneratedCatalogException error) =>
    switch (error.reason) {
      'catalog_missing' =>
        'No generated widget catalog. Run `dart run build_runner build`, or '
            '${_letPushGenerate()}.',
      'generate_failed' =>
        'Could not generate the widget catalog. Run '
            '`dart run build_runner build` to see why.',
      'render_catalog_missing' => renderCatalogMissingMessage,
      'toolchain' => 'Could not find a Flutter SDK. ${flutterRootFix()}',
      _ => 'Could not read the generated widget catalog.',
    };

/// Renders an upload failure as one line a reader can act on.
String _uploadFailureMessage(
  RenderBundleUploadException error, {
  required bool withKey,
}) {
  if (error.incomplete) {
    return 'Could not finish the push: the files kept going missing between '
        'preparing and completing it. The bytes are stored; pushing again '
        'would send only what is still missing.';
  }
  final storage = error.storage;
  if (storage != null) return _storageMessage(storage);
  final targetSelection = error.targetSelection;
  if (targetSelection != null) {
    return targetSelectionSentence(targetSelection, currentSelectorSyntax);
  }
  final refused = error.reason;
  if (refused != null) {
    final named = _rejectionMessage(refused, withKey: withKey);
    if (named != null) return named;
  }
  final staged = error.staged;
  if (staged != null) {
    return 'Could not upload the render bundle: this organization would hold '
        '${staged.heldBytes} bytes staged, over the ${staged.limitBytes} byte '
        'limit (${staged.limitBytes ~/ (1024 * 1024)} MiB).';
  }
  final oversize = error.oversize;
  if (oversize != null) {
    final subject = oversize.compressed ? 'compressed to' : 'built';
    return 'Could not upload the render bundle: $subject '
        '${oversize.measuredBytes} bytes, over the ${oversize.limitBytes} byte '
        'limit (${oversize.limitBytes ~/ (1024 * 1024)} MiB).';
  }
  final status = error.statusCode;
  if (withKey && (status == 401 || status == 403)) {
    return 'Could not upload the render bundle: the key was not accepted. A '
        'key pushes only while it holds the bundle-push scope and has not '
        'been revoked.';
  }
  // Every refusal reaches the reader as a reason, even one with no sentence.
  if (refused != null) {
    return status == null
        ? 'Could not upload the render bundle (refused: $refused).'
        : 'Could not upload the render bundle (HTTP $status, refused: '
              '$refused).';
  }
  if (status == null) return 'Could not upload the render bundle.';
  final reason = _uploadStatusReason(status, error.transferBytes);
  return reason == null
      ? 'Could not upload the render bundle (HTTP $status).'
      : 'Could not upload the render bundle (HTTP $status: $reason).';
}

/// Names what the attempt removed and what still holds the space a push needs.
String _storageMessage(RenderBundleStorageRefusal storage) {
  final holders = storage.holders
      .map(
        (holder) =>
            '${_holderName(holder.kind)} ${holder.label} at version '
            '${holder.version} (${holder.byteLength} bytes)',
      )
      .join(', ');
  final removed = switch (storage.evictedVersionIds.length) {
    0 => 'Nothing could be removed',
    1 => 'One version no head pointed at was removed',
    final count => '$count versions no head pointed at were removed',
  };
  final held = holders.isEmpty
      ? 'the push is larger than the room this organization has'
      : 'what remains is held by $holders';
  return 'Could not push: this organization holds ${storage.usedBytes} of '
      '${storage.limitBytes} bytes and the push needs '
      '${storage.neededBytes} more. $removed; $held.';
}

String _holderName(String kind) => switch (kind) {
  'environmentHead' => 'the head',
  'personalHead' => 'the personal head',
  'replacedVersion' => 'the version replaced by',
  _ => 'a protected version,',
};

/// Turns one short refusal into the sentence it stands for.
String? _rejectionMessage(String reason, {required bool withKey}) =>
    switch (reason) {
      'no_session' => _notSignedIn(),
      'not_a_secret_key' =>
        '$_apiKeyVariable holds a publishable key. A push needs a secret key '
            'minted with the bundle-push scope.',
      'missing_scope' =>
        'This key was not minted with the bundle-push scope, so it cannot '
            'push. Mint a new key with that scope.',
      'environment_not_found' =>
        'This key is bound to one environment and '
            '${currentSelectorSyntax.environment} names another. Leave it out, '
            'or use the key for the environment it belongs to.',
      'scope_mismatch' =>
        'This key belongs to another organization, project or app than the '
            'one being pushed. Check the configuration this push ran with.',
      'personal_not_allowed' => keyHasNoPersonalHeadSentence(),
      'environment_head_not_permitted' =>
        'Moving an environment head takes an administrator or a key. Push to '
            'your own head, or ask an administrator.',
      'storage_limit_unavailable' =>
        'Could not read this organization\'s storage limit. A push needs it, '
            'so this one was refused. Try again; if it keeps happening the '
            'service is degraded.',
      'builds_unavailable' => _noBuilds,
      'engine_not_released' =>
        'Could not upload the render bundle: this build\'s Flutter engine is '
            'not one Flutter published, so the dashboard cannot load it. '
            'Build with a released Flutter SDK; a custom or local engine is '
            'not supported for previews.',
      'upload_unavailable' =>
        'The upload service did not answer, so nothing was stored. Try '
            'again; if it keeps happening the service is degraded.',
      'upload_key_unavailable' =>
        'The service could not mint the credential an upload needs, so '
            'nothing was stored. Try again; if it keeps happening the service '
            'is degraded.',
      _ => null,
    };

/// Reads a refusal status. A request crosses intermediaries the service does
/// not control, so each reading must hold for either source.
String? _uploadStatusReason(int status, int? transferBytes) => switch (status) {
  400 =>
    'the request was rejected before the bundle was stored; retry, and '
        'rebuild only if it keeps happening',
  401 =>
    'the stored credential was not accepted, or this account is no longer a '
        'member of the organization',
  403 =>
    'the request was refused; the organization may be suspended, or a network '
        'policy in front of the service may be blocking it',
  404 => 'the project or the upload address was not found',
  408 =>
    'the body did not arrive within the two-minute upload deadline; a faster '
        'connection or a smaller bundle will finish in time',
  409 => 'another version was selected for this head concurrently',
  413 =>
    'something between this machine and the service refused the body size'
        '${transferBytes == null ? '' : ', which was $transferBytes '
                  'compressed bytes'}',
  415 => 'the content type or encoding was not accepted',
  429 => 'too many requests; an upload for this account may already be running',
  503 => 'the service is unavailable or busy; retry shortly',
  _ => null,
};
