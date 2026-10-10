import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:restage_cli/src/api/render_bundle_api.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/commands/organization_resolution.dart';
import 'package:restage_cli/src/config/restage_config.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/render_bundles/flutter_render_bundle_builder.dart';
import 'package:restage_cli/src/render_bundles/render_bundle_archive.dart';
import 'package:restage_shared/restage_shared.dart';
// ignore: implementation_imports
import 'package:restage_shared/src/render_bundle/deployed_origin_authority.dart';

/// Deterministically build and upload the main render bundle.
final class BuildPushCommand extends Command<int> {
  BuildPushCommand({
    required StringSink stdout,
    required StringSink stderr,
    FileCredentialStore? credentialStore,
    http.Client? httpClient,
    RenderBundleArtifactBuilder? builder,
  }) : _stdout = stdout,
       _stderr = stderr,
       _credentialStore = credentialStore,
       _httpClient = httpClient,
       _builder = builder ?? FlutterRenderBundleBuilder() {
    argParser
      ..addOption(
        'project',
        help: 'Project slug (overrides restage_config.yaml).',
      )
      ..addOption(
        'channel',
        defaultsTo: renderBundleMainChannel,
        help: 'Render-bundle channel (`main` or `user/<handle>`).',
      )
      ..addOption(
        'directory',
        abbr: 'C',
        defaultsTo: '.',
        help: 'Directory to start the restage_config.yaml search from.',
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

  @override
  String get name => 'push';

  @override
  String get description =>
      'Build twice, verify deterministic bytes, and upload one channel.';

  @override
  Future<int> run() async {
    final channel =
        argResults?['channel'] as String? ?? renderBundleMainChannel;
    if (!isValidRenderBundleChannel(channel)) {
      _stderr.writeln('The render-bundle channel is invalid.');
      return 1;
    }
    final directory = Directory(argResults?['directory'] as String? ?? '.');
    final loaded = await loadRestageConfig(from: directory);
    final projectRoot = loaded?.source.parent ?? directory.absolute;
    final project =
        (argResults?['project'] as String?) ?? loaded?.config.project;
    if (project == null || project.isEmpty) {
      _stderr.writeln(
        'No project context. Run `restage init` or pass --project <slug>.',
      );
      return 1;
    }
    final catalogFile = File(
      p.join(projectRoot.path, 'lib', 'src', 'widget_catalog', 'catalog.json'),
    );
    if (!catalogFile.existsSync()) {
      _stderr.writeln('No generated widget catalog found.');
      return 1;
    }

    final store = _credentialStore ?? FileCredentialStore.atDefaultLocation();
    final credential = await store.read();
    if (credential == null) {
      _stderr.writeln('Not signed in. Run `restage login`.');
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

    final Uint8List archive;
    try {
      archive = await _builder.build(
        projectRoot: projectRoot,
        catalogJson: await catalogFile.readAsString(),
        parentOrigin: parentOrigin,
      );
    } on RenderBundleBuildException {
      return _reportBuildFailure();
    } on FileSystemException {
      return _reportBuildFailure();
    }
    if (archive.isEmpty) return _reportBuildFailure();
    if (archive.length > renderBundleMaxArchiveBytes) {
      _stderr.writeln(
        _uploadFailureMessage(
          RenderBundleUploadException.oversize(
            RenderBundleOversize(
              measuredBytes: archive.length,
              limitBytes: renderBundleMaxArchiveBytes,
              compressed: false,
            ),
          ),
        ),
      );
      return 2;
    }
    final uploadArchive = Uint8List.fromList(archive).asUnmodifiableView();
    final uploadedContentHash = CapabilitySidecar.hashBlob(uploadArchive);

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
      // The shared resolver can render raw backend details. Suppress that sink
      // so this upload lane preserves its generic-error contract.
      final suppressedResolutionErrors = StringBuffer();
      final configuredOrganization = await resolveConfiguredOrganization(
        api: api,
        config: loaded?.config,
        stderr: suppressedResolutionErrors,
      );
      if (configuredOrganization == null) {
        _stderr.writeln('Could not resolve organization context.');
        return 1;
      }
      renderBundles = RenderBundleApi(
        rpc: api,
        apiEndpoint: apiEndpoint,
        credential: credential,
        trustedBundleOrigin: origins.bundleOrigin,
        uploadClient: _httpClient,
      );
      await renderBundles.upload(
        project: project,
        channel: channel,
        organizationId: configuredOrganization.organizationId,
        archive: uploadArchive,
      );
      final snapshot = await renderBundles.discover(
        project: project,
        channel: channel,
        organizationId: configuredOrganization.organizationId,
      );
      if (snapshot == null) {
        // The archive reached storage; only the read-back failed.
        _stderr.writeln(
          'Uploaded render bundle $channel ($uploadedContentHash), but the '
          'channel head could not be read back, so what $channel points at is '
          'unconfirmed. The bundle is stored; pushing again would upload the '
          'same bytes.',
        );
        return 2;
      }
      if (snapshot.contentHash != uploadedContentHash) {
        // The archive is stored; a concurrent push selected its own version
        // after this one. Re-running would upload the same bytes again.
        _stderr.writeln(
          'Uploaded render bundle $channel ($uploadedContentHash), but '
          '$channel now points at version ${snapshot.version} '
          '(${snapshot.contentHash}) from another push.',
        );
        return 2;
      }
      _stdout.writeln(
        'Uploaded render bundle $channel version ${snapshot.version} '
        '(${snapshot.contentHash}).',
      );
      return 0;
    } on RenderBundleUploadException catch (error) {
      _stderr.writeln(_uploadFailureMessage(error));
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

  int _reportBuildFailure() {
    _stderr.writeln('Could not build the render bundle.');
    return 2;
  }
}

/// Renders an upload failure as one line a reader can act on.
String _uploadFailureMessage(RenderBundleUploadException error) {
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
  if (status == null) return 'Could not upload the render bundle.';
  final reason = _uploadStatusReason(status, error.transferBytes);
  return reason == null
      ? 'Could not upload the render bundle (HTTP $status).'
      : 'Could not upload the render bundle (HTTP $status: $reason).';
}

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
  409 => 'another version was selected for this channel concurrently',
  413 =>
    'something between this machine and the service refused the body size'
        '${transferBytes == null ? '' : ', which was $transferBytes '
                  'compressed bytes'}',
  415 => 'the content type or encoding was not accepted',
  429 => 'too many requests; an upload for this account may already be running',
  503 => 'the service is unavailable or busy; retry shortly',
  _ => null,
};
