import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/api/paywall_api.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/surface_models.dart';
import 'package:restage_cli/src/api/typed_error_renderer.dart';
import 'package:restage_cli/src/commands/surface_payload.dart';
import 'package:restage_cli/src/config/restage_config.dart';
import 'package:restage_cli/src/credentials/credential.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:path/path.dart' as p;

/// Upload a compiled `.rfw` for a paywall and publish it to an
/// environment.
///
/// The backend's publish endpoint snapshots the existing draft into a
/// new version row; bytes are uploaded separately via `save`. The
/// command runs those two operations as a sequence:
///
///   1. `save(bytes)` — replaces the draft on the server.
///   2. `publish(environmentSlug)` — snapshots the draft into the next
///      version for the named environment.
///
/// When step 1 succeeds but step 2 fails (transport or backend), the
/// command surfaces a "draft was uploaded but publish failed; retry
/// with `restage paywall publish <name>`" message so the user can
/// recover without re-running the upload.
class PaywallPublishCommand extends Command<int> {
  /// Construct a publish command.
  PaywallPublishCommand({
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
            'Path to the compiled `.rfw` (default: '
            '<config-dir>/assets/paywalls/<name>.rfw).',
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
      'Upload a compiled paywall and publish it to an environment.';

  @override
  Future<int> run() async {
    final rest = argResults?.rest ?? const <String>[];
    if (rest.isEmpty) {
      _stderr.writeln(
        'Missing positional argument: <name>. Run `restage paywall '
        'publish <name>`.',
      );
      return 1;
    }
    if (rest.length > 1) {
      _stderr.writeln(
        'Too many positional arguments. Expected exactly one '
        '<name>.',
      );
      return 1;
    }
    final paywallName = rest.first;

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

    final rfwPath = _resolveRfwPath(
      argResults?['path'] as String?,
      loaded?.source.parent,
      paywallName,
    );
    final file = File(rfwPath);
    if (!file.existsSync()) {
      _stderr.writeln(
        'Compiled paywall not found at $rfwPath. Generate the `.rfw` '
        'with `dart run build_runner build` and retry, or override the '
        'path with --path <file>.',
      );
      return 1;
    }
    final bytes = await file.readAsBytes();

    final CapabilityManifest manifest;
    try {
      manifest = await loadCapabilityManifest(rfwPath);
    } on SurfacePayloadException catch (e) {
      _stderr.writeln(e.message);
      return 1;
    }

    final capabilityWarning = publishCapabilityWarning(manifest);
    if (capabilityWarning != null) {
      _stderr.writeln(capabilityWarning);
    }

    return _runPipeline(
      credential: credential,
      paywall: paywallName,
      project: project,
      app: app,
      environment: environment,
      bytes: bytes,
      minClient: manifest.builtInFloor,
      requiredLibraries: manifest.requiredLibraries,
    );
  }

  /// Run save + publish.
  ///
  /// The two-step shape carries a partial-state risk: a transient
  /// publish failure leaves the server with an updated draft but no
  /// new published version. The command surfaces that case so the user
  /// can retry the publish without re-running save.
  Future<int> _runPipeline({
    required Credential credential,
    required String paywall,
    required String project,
    required String app,
    required String environment,
    required Uint8List bytes,
    required int minClient,
    required List<LibraryRequirement> requiredLibraries,
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
      final paywallApi = PaywallApi(api);

      try {
        await paywallApi.save(
          project: project,
          app: app,
          paywall: paywall,
          bytes: bytes,
          minClient: minClient,
          requiredLibraries: requiredLibraries,
        );
      } on RestageApiException catch (e) {
        return _handleApiException(e, stage: _Stage.save, paywall: paywall);
      } on SocketException catch (e) {
        _stderr.writeln('Could not upload the paywall draft: $e');
        return 2;
      }

      try {
        final version = await paywallApi.publish(
          project: project,
          app: app,
          paywall: paywall,
          environment: environment,
        );
        _stdout.writeln(
          'Published $paywall to $environment as version $version.',
        );
        return 0;
      } on RestageApiException catch (e) {
        return _handleApiException(
          e,
          stage: _Stage.publish,
          paywall: paywall,
          environment: environment,
        );
      } on SocketException catch (e) {
        _stderr
          ..writeln('Could not publish: $e')
          ..writeln(
            'The draft is on the server. Re-run `restage paywall publish '
            '$paywall --env $environment` to retry (the command re-uploads '
            'your current local `.rfw` and publishes it).',
          );
        return 2;
      }
    } finally {
      if (_httpClient == null) api.close();
    }
  }

  /// Resolve the environment slug.
  ///
  /// Priority: explicit `--env`, then `defaultEnvironment` from the
  /// config, then an interactive prompt (`Environment slug:` with the
  /// config's default), then a non-interactive failure
  /// (`required: --env <slug>`).
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

  /// Resolve where to read the compiled `.rfw` from.
  ///
  /// Explicit `--path` wins. Otherwise: the config's directory (or
  /// the current directory when no config) joined with
  /// `assets/paywalls/<name>.rfw`.
  String _resolveRfwPath(
    String? fromFlag,
    Directory? configDir,
    String paywallName,
  ) {
    if (fromFlag != null && fromFlag.isNotEmpty) {
      return p.absolute(fromFlag);
    }
    final root = configDir ?? Directory.current;
    return p.join(root.path, 'assets', 'paywalls', '$paywallName.rfw');
  }

  int _handleApiException(
    RestageApiException e, {
    required _Stage stage,
    required String paywall,
    String? environment,
  }) {
    // Paywalls publish through the generic surface endpoint, so its typed
    // exceptions are what surface here. Decode them and present the same
    // paywall-flavoured phrasing for the three cases the publish path surfaces
    // uniquely. Other typed exceptions fall through to the shared renderer.
    final typed = decodeSurfaceTypedException(e.body);
    switch (typed) {
      case SurfacePublishConflict(:final surfaceSlug, :final environmentSlug):
        _stderr.writeln(
          'A concurrent publish race conflicted with the publish of '
          '`$surfaceSlug` to `$environmentSlug`. Retry with `restage '
          'paywall publish $paywall`.',
        );
        return 1;
      case SurfaceNotFound(:final surfaceSlug):
        _stderr.writeln(
          'Paywall `$surfaceSlug` not found. (If you saved it just '
          'before publishing, the row may have been deleted '
          'mid-flight; re-run the publish.)',
        );
        return 1;
      case SurfaceEnvironmentNotFound(:final environmentSlug):
        _stderr.writeln(
          'Environment `$environmentSlug` not found under the resolved '
          'app. Check `restage_config.yaml` or pass `--env <slug>`.',
        );
        if (stage == _Stage.publish) {
          _stderr.writeln(
            _draftUploadedHint(paywall: paywall, environment: environment),
          );
        }
        return 1;
      case null:
        break;
    }
    final outcome = renderGenericTypedError(e);
    if (outcome != null) {
      // System-level outcomes (exit 2) for the publish stage append a
      // hint that the draft was already uploaded so the user can retry
      // just the publish.
      if (outcome.exitCode == 2 && stage == _Stage.publish) {
        _stderr
          ..writeln(
            'Could not publish: ${outcome.message.replaceFirst('Could not contact the backend: ', '')}',
          )
          ..writeln(
            _draftUploadedHint(paywall: paywall, environment: environment),
          );
      } else {
        _stderr.writeln(outcome.message);
      }
      return outcome.exitCode;
    }
    _stderr.writeln(typed?.toString() ?? e.toString());
    return 1;
  }

  String _draftUploadedHint({
    required String paywall,
    required String? environment,
  }) {
    final envFragment = environment == null ? '' : ' --env $environment';
    return 'The draft is on the server. Re-run `restage paywall publish '
        '$paywall$envFragment` to retry (the command re-uploads your '
        'current local `.rfw` and publishes it).';
  }
}

enum _Stage { save, publish }
