import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/surface_api.dart';
import 'package:restage_cli/src/api/surface_models.dart';
import 'package:restage_cli/src/api/typed_error_models.dart';
import 'package:restage_cli/src/api/typed_error_renderer.dart';
import 'package:restage_cli/src/commands/surface_payload.dart';
import 'package:restage_cli/src/config/restage_config.dart';
import 'package:restage_cli/src/credentials/credential.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:path/path.dart' as p;

/// Assemble a code-authored engagement surface and publish it to an
/// environment.
///
/// Mirrors the paywall publish command, with three differences: a required
/// `--type` dimension (every surface RPC takes a surface type), a payload
/// assembled from a flow document plus its per-screen blobs (rather than a
/// single compiled blob), and a role split — `save` requires the member
/// role, `publish` requires admin. The command runs two operations:
///
///   1. `save(bytes)` — uploads the assembled draft (member role).
///   2. `publish(environmentSlug)` — snapshots the draft into the next
///      version for the named environment (admin role).
///
/// When step 1 succeeds but step 2 fails, the command surfaces a recovery
/// message so the user can finish the publish without re-running the upload.
/// The admin-role case gets a role-aware variant of that message.
class SurfacePublishCommand extends Command<int> {
  /// Construct a publish command.
  SurfacePublishCommand({
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
        'type',
        help:
            'Surface type (required): ${_validTypeList()}. Drives where the '
            'codegen output is read from (assets/<type>/...).',
      )
      ..addOption(
        'project',
        help: 'Project slug (overrides restage_config.yaml).',
      )
      ..addOption('app', help: 'App slug (overrides restage_config.yaml).')
      ..addOption(
        'env',
        help:
            'Environment slug to publish to (overrides '
            'restage_config.yaml `defaultEnvironment`).',
      )
      ..addOption(
        'path',
        help:
            'Path to the surface artifact. Flow surfaces default to '
            '<config-dir>/assets/<type>/flows/<slug>.flow.json (screen blobs '
            'resolve from the sibling <flow-dir>/../screens/); a paywall '
            'defaults to <config-dir>/assets/paywalls/<slug>.rfw.',
      )
      ..addOption(
        'directory',
        abbr: 'C',
        defaultsTo: '.',
        help:
            'Directory to start the restage_config.yaml search from. '
            'Defaults to the current working directory.',
      );
  }

  final StringSink _stdout;
  final StringSink _stderr;
  final Interactive _interactive;
  final FileCredentialStore? _credentialStore;
  final http.Client? _httpClient;

  @override
  String get name => 'publish';

  @override
  String get description =>
      'Assemble a code-authored surface and publish it to an environment.';

  @override
  Future<int> run() async {
    final rest = argResults?.rest ?? const <String>[];
    if (rest.isEmpty) {
      _stderr.writeln(
        'Missing positional argument: <slug>. Run `restage surface '
        'publish <slug> --type <${_validTypeList()}>`.',
      );
      return 1;
    }
    if (rest.length > 1) {
      _stderr.writeln(
        'Too many positional arguments. Expected exactly one <slug>.',
      );
      return 1;
    }
    final slug = rest.first;

    final surfaceType = _resolveSurfaceType(argResults?['type'] as String?);
    if (surfaceType == null) return 1;

    final store = _credentialStore ?? FileCredentialStore.atDefaultLocation();
    final credential = await store.read();
    if (credential == null) {
      _stderr.writeln('Not signed in. Run `restage login`.');
      return 1;
    }

    final loaded = await loadRestageConfig(
      from: Directory(argResults?['directory'] as String? ?? '.'),
    );
    final project =
        (argResults?['project'] as String?) ?? loaded?.config.project;
    final app = (argResults?['app'] as String?) ?? loaded?.config.app;
    if (project == null || app == null) {
      _stderr.writeln(
        'No project / app context. Run `restage init` or pass '
        '--project <slug> --app <slug>.',
      );
      return 1;
    }

    final environment = await _resolveEnvironment(
      argResults?['env'] as String?,
      loaded?.config.defaultEnvironment,
    );
    if (environment == null) return 1;

    final Uint8List bytes;
    try {
      // A paywall is a single compiled blob (assets/paywalls/<slug>.rfw); a
      // flow surface is a flow document plus its per-screen blobs. Each has its
      // own default location, both overridable with --path.
      if (surfaceType == SurfaceType.paywall) {
        final blobPath = _resolvePaywallBlobPath(
          argResults?['path'] as String?,
          loaded?.source.parent,
          slug,
        );
        // Assemble first (it validates the .rfw then its sidecar, so a missing
        // blob is reported as such); the manifest re-read for the warning is
        // then guaranteed to resolve.
        bytes = await assembleBlobSurfacePayloadBytes(blobPath);
        final capabilityWarning = publishCapabilityWarning(
          await loadCapabilityManifest(blobPath),
        );
        if (capabilityWarning != null) {
          _stderr.writeln(capabilityWarning);
        }
      } else {
        final flowPath = _resolveFlowPath(
          argResults?['path'] as String?,
          loaded?.source.parent,
          surfaceType,
          slug,
        );
        bytes = await assembleSurfacePayloadBytes(flowPath);
      }
    } on SurfacePayloadException catch (e) {
      _stderr.writeln(e.message);
      return 1;
    }

    return _runPipeline(
      credential: credential,
      slug: slug,
      surfaceType: surfaceType,
      project: project,
      app: app,
      environment: environment,
      bytes: bytes,
    );
  }

  /// Validate the `--type` flag into a [SurfaceType].
  ///
  /// Required (no default): an explicit type beats a silent wrong-type
  /// publish, and the type drives artifact-path resolution. A missing or
  /// invalid value fails with a crisp error listing the valid values.
  SurfaceType? _resolveSurfaceType(String? raw) {
    if (raw == null || raw.isEmpty) {
      _stderr.writeln('Required: --type <${_validTypeList()}>.');
      return null;
    }
    final SurfaceType type;
    try {
      type = SurfaceType.fromWireName(raw);
    } on FormatException {
      _stderr.writeln(
        'Invalid --type "$raw". Valid values: ${_validTypeList()}.',
      );
      return null;
    }
    if (!_publishableSurfaceTypes.contains(type)) {
      _stderr.writeln(
        'Invalid --type "$raw". Valid values: ${_validTypeList()}.',
      );
      return null;
    }
    return type;
  }

  /// Run save + publish.
  ///
  /// The two-step shape carries a partial-state risk: a publish failure
  /// after a successful save leaves the server with an updated draft but no
  /// new published version. The command surfaces that case so the user can
  /// retry without re-running save — with a role-aware variant when the
  /// publish failed because it requires the admin role.
  Future<int> _runPipeline({
    required Credential credential,
    required String slug,
    required SurfaceType surfaceType,
    required String project,
    required String app,
    required String environment,
    required Uint8List bytes,
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
      return 1;
    }
    try {
      final surfaceApi = SurfaceApi(api);

      try {
        await surfaceApi.save(
          project: project,
          app: app,
          surfaceType: surfaceType,
          surfaceSlug: slug,
          bytes: bytes,
        );
      } on RestageApiException catch (e) {
        return _handleApiException(
          e,
          stage: _Stage.save,
          slug: slug,
          surfaceType: surfaceType,
        );
      } on SocketException catch (e) {
        _stderr.writeln('Could not upload the surface draft: $e');
        return 2;
      }

      try {
        final version = await surfaceApi.publish(
          project: project,
          app: app,
          surfaceType: surfaceType,
          surfaceSlug: slug,
          environment: environment,
        );
        _stdout.writeln(
          'Published $slug (${surfaceType.wireName}) to $environment as '
          'version $version.',
        );
        return 0;
      } on RestageApiException catch (e) {
        return _handleApiException(
          e,
          stage: _Stage.publish,
          slug: slug,
          surfaceType: surfaceType,
          environment: environment,
        );
      } on SocketException catch (e) {
        _stderr
          ..writeln('Could not publish: $e')
          ..writeln(
            _draftUploadedHint(
              slug: slug,
              surfaceType: surfaceType,
              environment: environment,
            ),
          );
        return 2;
      }
    } finally {
      if (_httpClient == null) api.close();
    }
  }

  /// Resolve the environment slug.
  ///
  /// Priority: explicit `--env`, then `defaultEnvironment` from the config,
  /// then an interactive prompt, then a non-interactive failure.
  Future<String?> _resolveEnvironment(
    String? fromFlag,
    String? fromConfig,
  ) async {
    if (fromFlag != null && fromFlag.isNotEmpty) return fromFlag;
    if (fromConfig != null && fromConfig.isNotEmpty) return fromConfig;
    if (_interactive.isInteractive) {
      return _interactive.prompt('Environment slug?');
    }
    _stderr.writeln(
      'Required: --env <slug>. Set `defaultEnvironment` in '
      'restage_config.yaml or pass --env on the command line.',
    );
    return null;
  }

  /// Resolve where to read the flow JSON from.
  ///
  /// Explicit `--path` wins. Otherwise: the config's directory (or the
  /// current directory when no config) joined with
  /// `assets/<type>/flows/<slug>.flow.json`.
  String _resolveFlowPath(
    String? fromFlag,
    Directory? configDir,
    SurfaceType surfaceType,
    String slug,
  ) {
    if (fromFlag != null && fromFlag.isNotEmpty) {
      return p.absolute(fromFlag);
    }
    final root = configDir ?? Directory.current;
    return p.join(
      root.path,
      'assets',
      surfaceType.wireName,
      'flows',
      '$slug.flow.json',
    );
  }

  /// Resolve where to read the paywall blob from.
  ///
  /// Explicit `--path` wins. Otherwise: the config's directory (or the current
  /// directory when no config) joined with `assets/paywalls/<slug>.rfw`.
  String _resolvePaywallBlobPath(
    String? fromFlag,
    Directory? configDir,
    String slug,
  ) {
    if (fromFlag != null && fromFlag.isNotEmpty) {
      return p.absolute(fromFlag);
    }
    final root = configDir ?? Directory.current;
    return p.join(root.path, 'assets', 'paywalls', '$slug.rfw');
  }

  int _handleApiException(
    RestageApiException e, {
    required _Stage stage,
    required String slug,
    required SurfaceType surfaceType,
    String? environment,
  }) {
    // Surface-specific typed errors get bespoke phrasing.
    final typed = decodeSurfaceTypedException(e.body);
    switch (typed) {
      case SurfacePublishConflict(:final surfaceSlug, :final environmentSlug):
        _stderr.writeln(
          'A concurrent publish race conflicted with the publish of '
          '`$surfaceSlug` to `$environmentSlug`. Retry with `restage '
          'surface publish $slug --type ${surfaceType.wireName}`.',
        );
        return 1;
      case SurfaceNotFound(:final surfaceSlug):
        _stderr.writeln(
          'Surface `$surfaceSlug` not found. (If you saved it just before '
          'publishing, the row may have been deleted mid-flight; re-run the '
          'publish.)',
        );
        return 1;
      case SurfaceEnvironmentNotFound(:final environmentSlug):
        _stderr.writeln(
          'Environment `$environmentSlug` not found under the resolved app. '
          'Check `restage_config.yaml` or pass `--env <slug>`.',
        );
        if (stage == _Stage.publish) {
          _stderr.writeln(
            _draftUploadedHint(
              slug: slug,
              surfaceType: surfaceType,
              environment: environment,
            ),
          );
        }
        return 1;
      case null:
        break;
    }

    // The role split (member saves, admin publishes): a member who uploaded
    // the draft is denied at publish. Surface that honestly rather than the
    // generic "not authorised" message — the draft is already on the server.
    if (stage == _Stage.publish && _isAuthorizationFailure(e)) {
      final envFragment = environment == null ? '' : ' --env $environment';
      _stderr.writeln(
        'Draft uploaded. Publishing requires an admin role; an admin can run '
        '`restage surface publish $slug --type ${surfaceType.wireName}'
        '$envFragment` to publish it.',
      );
      return 1;
    }

    final outcome = renderGenericTypedError(e);
    if (outcome != null) {
      // System-level outcomes (exit 2) for the publish stage append a hint
      // that the draft was already uploaded so the user can retry the
      // publish.
      if (outcome.exitCode == 2 && stage == _Stage.publish) {
        _stderr
          ..writeln(
            'Could not publish: '
            '${outcome.message.replaceFirst('Could not contact the backend: ', '')}',
          )
          ..writeln(
            _draftUploadedHint(
              slug: slug,
              surfaceType: surfaceType,
              environment: environment,
            ),
          );
      } else {
        _stderr.writeln(outcome.message);
      }
      return outcome.exitCode;
    }
    _stderr.writeln(typed?.toString() ?? e.toString());
    return 1;
  }

  /// True when [e] is the backend's authorization rejection (the typed
  /// `UnauthorizedException`), as opposed to credential rot (a bare
  /// 401/403). Used to detect the admin-role denial at publish. Reuses the
  /// shared transport decoder that the generic renderer is already built on.
  bool _isAuthorizationFailure(RestageApiException e) =>
      decodeGenericTypedException(e.body) is UnauthorizedAccess;

  String _draftUploadedHint({
    required String slug,
    required SurfaceType surfaceType,
    required String? environment,
  }) {
    final envFragment = environment == null ? '' : ' --env $environment';
    final artifact = surfaceType == SurfaceType.paywall
        ? 'paywall blob'
        : 'flow';
    return 'The draft is on the server. Re-run `restage surface publish '
        '$slug --type ${surfaceType.wireName}$envFragment` to retry (the '
        'command re-uploads your current local $artifact and publishes it).';
  }
}

/// Surface types this command can publish: the flow surfaces (onboarding /
/// message / survey), assembled from a flow document plus its per-screen
/// blobs, and a paywall, assembled from a single compiled blob.
const _publishableSurfaceTypes = <SurfaceType>{
  SurfaceType.onboarding,
  SurfaceType.message,
  SurfaceType.survey,
  SurfaceType.paywall,
};

/// The comma-separated list of valid `--type` values
/// (`onboarding, message, survey`).
String _validTypeList() =>
    _publishableSurfaceTypes.map((t) => t.wireName).join(', ');

enum _Stage { save, publish }
