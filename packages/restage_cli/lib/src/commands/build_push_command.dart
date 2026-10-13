import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/api/render_bundle_api.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/commands/organization_resolution.dart';
import 'package:restage_cli/src/config/restage_config.dart';
import 'package:restage_cli/src/credentials/credential.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/receipts/release_recorder.dart';
import 'package:restage_cli/src/receipts/render_bundle_receipt.dart';
import 'package:restage_cli/src/receipts/source_boundary.dart';
import 'package:restage_cli/src/render_bundles/bundle_source.dart';
import 'package:restage_cli/src/render_bundles/flutter_render_bundle_builder.dart';
import 'package:restage_cli/src/render_bundles/generated_widget_catalog.dart';
import 'package:restage_cli/src/render_bundles/push_target.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_cli/src/render_bundles/render_bundle_archive.dart';
// ignore: implementation_imports
import 'package:restage_shared/src/render_bundle/deployed_origin_authority.dart';

/// Environment variable carrying a secret key for an unattended push. It is
/// read here only; a flag or the configuration file cannot supply it.
const _apiKeyVariable = 'RESTAGE_API_KEY';

/// Opens the repository a receipt is written into.
typedef ReleaseRecorderOpener =
    Future<ReleaseRecorder?> Function({
      required Directory projectRoot,
      required StringSink stderr,
    });

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
       _environment = environment {
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
      ..addFlag(
        'generate',
        defaultsTo: true,
        help:
            'Run the code generator first. Pass --no-generate to build against '
            'the catalog a previous run produced.',
      )
      ..addOption(
        'parent-origin',
        help:
            'Exact dashboard shell origin trusted by the render bundle. '
            'Defaults to dashboardOrigin in restage_config.yaml and, when '
            'provided, must match it exactly.',
      )
      ..addOption(
        'bundle-origin',
        help:
            'Exact isolated upload origin. Required for local and deployed '
            'uploads unless set as renderBundleOrigin in restage_config.yaml. '
            'Local uploads use a distinct second port on the same loopback '
            'host; deployed uploads use a distinct HTTPS origin.',
      );
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
    final project =
        (argResults?['project'] as String?) ?? loaded?.config.project;
    final app = (argResults?['app'] as String?) ?? loaded?.config.app;
    if (project == null || project.isEmpty || app == null || app.isEmpty) {
      _stderr.writeln(
        'No project / app context. Run `restage init` or pass '
        '--project <slug> --app <slug>.',
      );
      return 1;
    }
    final key = (_environment ?? Platform.environment)[_apiKeyVariable]?.trim();
    final withKey = key != null && key.isNotEmpty;
    final resolved = resolveBundlePushTarget(
      environment: argResults?['env'] as String?,
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
      // A key authorises one app's environment head on the server, so its
      // endpoint is the configured one and nothing about it is persisted.
      credential = Credential(
        endpoint:
            loaded?.config.endpoint?.trim() ??
            _defaultEndpoint?.toString() ??
            '',
        kind: CredentialKind.secretKey,
        authToken: key,
      );
    } else {
      final store = _credentialStore ?? FileCredentialStore.atDefaultLocation();
      credential = await store.read();
    }
    if (credential == null) {
      _stderr.writeln(
        'Not signed in. Run `restage login`, or set $_apiKeyVariable to push '
        'with a key.',
      );
      return 1;
    }
    final Uri apiEndpoint;
    try {
      apiEndpoint = resolveApiEndpoint(
        config: loaded?.config,
        credential: credential,
      );
    } on EndpointConfigurationException catch (error) {
      _stderr.writeln(error.toString());
      return 1;
    }
    final origins = resolveRenderBundleOriginTriplet(
      config: loaded?.config,
      apiEndpoint: apiEndpoint,
      renderBundleOriginOverride: argResults?['bundle-origin'] as String?,
    );
    if (origins == null) {
      _stderr.writeln(
        'A valid API, dashboard, and render-bundle origin triplet is required. '
        'Configure dashboardOrigin and renderBundleOrigin with three distinct '
        'finite restage.localhost roles or direct HTTPS siblings under '
        'restage.dev.',
      );
      return 1;
    }
    final parentOriginSource = argResults?['parent-origin'] as String?;
    var parentOrigin = origins.dashboardOrigin;
    if (parentOriginSource != null) {
      final Uri explicitParentOrigin;
      try {
        explicitParentOrigin = Uri.parse(parentOriginSource);
      } on FormatException {
        _stderr.writeln(
          'The parent origin must exactly match the configured '
          'dashboardOrigin.',
        );
        return 1;
      }
      if (!isApprovedRenderBundleOriginTriplet(
            origins.apiOrigin,
            explicitParentOrigin,
            origins.bundleOrigin,
          ) ||
          explicitParentOrigin.origin != origins.dashboardOrigin.origin) {
        _stderr.writeln(
          'The parent origin must exactly match the configured '
          'dashboardOrigin.',
        );
        return 1;
      }
      parentOrigin = Uri.parse(explicitParentOrigin.origin);
    }

    final flagOrganization = (argResults?['organization'] as String?)?.trim();
    final organizationSlug =
        flagOrganization == null || flagOrganization.isEmpty
        ? loaded?.config.organization
        : flagOrganization;
    final recordGit = argResults?['record-git'] as bool? ?? false;
    ReleaseRecorder? recorder;
    if (recordGit) {
      recorder = await _openRecorder(projectRoot: projectRoot, stderr: _stderr);
      if (recorder == null) return 1;
    }

    // Read before the catalog step: the provenance describes the source the
    // push started from, and a boundary that will not resolve costs nothing.
    final BundleSource source;
    try {
      source = await _source(projectRoot);
    } on SourceBoundaryException catch (error) {
      _stderr.writeln(error.message);
      return 1;
    }

    final GeneratedWidgetCatalog catalog;
    try {
      catalog = await _catalog(
        projectRoot: projectRoot,
        generate: argResults?['generate'] as bool? ?? true,
      );
    } on GeneratedCatalogException catch (error) {
      _stderr.writeln(_catalogFailureMessage(error));
      return error.reason == 'generate_failed' ? 2 : 1;
    }
    if (!catalog.registersWidgets) {
      _stdout.writeln(
        'This app registers no widgets of its own. The renderer carries the '
        'built-in catalogs only.',
      );
    }

    final RenderBundleArtifact artifact;
    try {
      artifact = await _builder.build(
        projectRoot: projectRoot,
        catalogJson: catalog.json,
        parentOrigin: parentOrigin,
        controlOrigin: origins.bundleOrigin,
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
    RenderBundleApi? renderBundles;
    try {
      int? organizationId;
      if (!withKey) {
        // The shared resolver can render raw backend details. Suppress that
        // sink so this upload path preserves its generic-error contract.
        final suppressedResolutionErrors = StringBuffer();
        final configuredOrganization = await resolveConfiguredOrganization(
          api: api,
          config: loaded?.config,
          stderr: suppressedResolutionErrors,
          preferredSlug: organizationSlug,
        );
        if (configuredOrganization == null) {
          _stderr.writeln('Could not resolve organization context.');
          return 1;
        }
        organizationId = configuredOrganization.organizationId;
      }
      renderBundles = RenderBundleApi(
        rpc: api,
        apiEndpoint: apiEndpoint,
        credential: credential,
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
      final moved = outcome.appFilesSent + outcome.engineFilesSent == 0
          ? 'Every file was already stored'
          : 'Moved ${outcome.appFilesSent} of '
                '${outcome.appFilesSent + outcome.appFilesHeld} app files'
                '${outcome.engineFilesSent == 0 ? '' : ' and seeded '
                          '${outcome.engineFilesSent} engine files'}';
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
        toolchain: requiredRenderBundleFlutterVersion,
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
      if (_httpClient == null) {
        renderBundles?.close();
        api.close();
      }
    }
  }

  int _reportBuildFailure([RenderBundleBuildException? error]) {
    final path = error?.detail;
    final named = path == null ? null : _engineMismatchMessage(error!, path);
    _stderr.writeln(named ?? 'Could not build the render bundle.');
    return 2;
  }
}

/// Names the engine file that puts this build on another toolchain.
String? _engineMismatchMessage(RenderBundleBuildException error, String path) =>
    switch (error.reason) {
      'engine_toolchain' =>
        'Could not build the render bundle: the engine file $path was built '
            'on another toolchain than the pinned set for this Flutter '
            'version. Build on the version the pin names.',
      'engine_incomplete' =>
        'Could not build the render bundle: the pinned engine set names '
            '$path and this build did not produce it. Build on the version '
            'the pin names.',
      _ => null,
    };

/// Renders a catalog-step failure as one line a reader can act on.
String _catalogFailureMessage(GeneratedCatalogException error) =>
    switch (error.reason) {
      'catalog_missing' =>
        'No generated widget catalog. Run `dart run build_runner build`, or '
            'drop --no-generate and let the push run it.',
      'generate_failed' =>
        'Could not generate the widget catalog. Run '
            '`dart run build_runner build` to see why.',
      'toolchain' => 'Could not find the Flutter toolchain on PATH.',
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
      'no_session' =>
        'Not signed in. Run `restage login`, or set $_apiKeyVariable to push '
            'with a key.',
      'not_a_secret_key' =>
        '$_apiKeyVariable holds a publishable key. A push needs a secret key '
            'minted with the bundle-push scope.',
      'missing_scope' =>
        'This key was not minted with the bundle-push scope, so it cannot '
            'push. Mint a new key with that scope.',
      'environment_not_found' =>
        'This key is bound to one environment and --env names another. Drop '
            '--env, or use the key for the environment it belongs to.',
      'scope_mismatch' =>
        'This key belongs to another organization, project or app than the '
            'one being pushed. Check the configuration this push ran with.',
      'personal_not_allowed' =>
        'A key moves the head of the environment it is bound to, so it has '
            'no personal head to push to.',
      'environment_head_not_permitted' =>
        'Moving an environment head takes an administrator or a key. Push to '
            'your own head, or ask an administrator.',
      'storage_limit_unavailable' =>
        'Could not read this organization\'s storage limit. A push needs it, '
            'so this one was refused. Try again; if it keeps happening the '
            'service is degraded.',
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
