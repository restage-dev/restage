import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/surface_publication_api.dart';
import 'package:restage_cli/src/api/typed_error_renderer.dart';
import 'package:restage_cli/src/commands/publish_selection.dart';
import 'package:restage_cli/src/commands/target_resolution.dart';
import 'package:restage_cli/src/config/restage_config.dart';
import 'package:restage_cli/src/credentials/credential.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_cli/src/publication/publication_assembler.dart';
import 'package:restage_cli/src/publication/publication_bundle_reader.dart';
import 'package:restage_cli/src/publication/publication_errors.dart';
import 'package:restage_cli/src/publication/publication_manifest.dart';
import 'package:restage_cli/src/receipts/git_repository.dart';
import 'package:restage_cli/src/receipts/receipt_location.dart';
import 'package:restage_cli/src/receipts/release_recorder.dart';
import 'package:restage_cli/src/receipts/release_receipt.dart';
import 'package:restage_shared/restage_shared.dart';

/// Push one generated surface from its exact manifest artifact closure.
class SurfacePushCommand extends Command<int> {
  /// Construct a push command.
  SurfacePushCommand({
    required StringSink stdout,
    required StringSink stderr,
    required Interactive interactive,
    FileCredentialStore? credentialStore,
    http.Client? httpClient,
    PublicationBundleReader? bundleReader,
    GitProcessRunner? processRunner,
    ReceiptGeneratorRunner? generator,
  }) : _stdout = stdout,
       _stderr = stderr,
       _interactive = interactive,
       _credentialStore = credentialStore,
       _httpClient = httpClient,
       _bundleReader = bundleReader,
       _processRunner = processRunner,
       _generator = generator {
    argParser
      ..addOption(
        'organization',
        help: 'Organization slug (overrides restage_config.yaml).',
      )
      ..addOption(
        'type',
        help:
            'Deprecated validation/disambiguation selector only; the generated '
            'manifest is authoritative. Values: ${_validSurfaceTypeList()}.',
      )
      ..addOption(
        'project',
        help: 'Project slug (overrides restage_config.yaml).',
      )
      ..addOption('app', help: 'App slug (overrides restage_config.yaml).')
      ..addOption(
        'env',
        help:
            'Environment slug to push to (overrides '
            'restage_config.yaml `defaultEnvironment`).',
      )
      ..addOption(
        'directory',
        abbr: 'C',
        defaultsTo: '.',
        help:
            'Directory to locate restage_config.yaml and generated publication '
            'metadata. It does not select artifacts.',
      )
      ..addFlag(
        'record-git',
        help:
            'Build from committed source and commit a release receipt naming '
            'the commit it came from. Set `recordGit` in restage_config.yaml '
            'to make it the default for the project.',
      );
    addPushAllOption(argParser, noun: 'surface');
    addRuntimePlaneOption(argParser);
  }

  final StringSink _stdout;
  final StringSink _stderr;
  final Interactive _interactive;
  final FileCredentialStore? _credentialStore;
  final http.Client? _httpClient;
  final PublicationBundleReader? _bundleReader;
  final GitProcessRunner? _processRunner;
  final ReceiptGeneratorRunner? _generator;

  @override
  String get name => 'push';

  @override
  String get description =>
      'Push a generated surface from its manifest artifact closure.';

  @override
  String get invocation => 'restage surface push <id|file.dart> [options]';

  @override
  Future<int> run() async {
    final rest = argResults?.rest ?? const <String>[];
    if (rest.isEmpty) {
      _stderr.writeln(
        'Missing positional argument: <id|file.dart>. Run `restage surface '
        'push <id>`, or name the .dart file the surface is declared in.',
      );
      return 1;
    }
    if (rest.length > 1) {
      _stderr.writeln(
        'Too many positional arguments. Expected exactly one '
        '<id|file.dart>.',
      );
      return 1;
    }
    final selector = rest.single;
    // A `.dart` path selects by file; anything else is the id itself.
    if (!selector.endsWith('.dart') && !isValidSurfaceSlug(selector)) {
      _stderr.writeln(
        'Refusing the id `$selector`. $surfaceSlugRefusalMessage',
      );
      return 1;
    }

    final type = _parseType(argResults?['type'] as String?);
    if (argResults?['type'] != null && type == null) return 1;

    final directory = Directory(argResults?['directory'] as String? ?? '.');
    final loadedConfig = await loadRestageConfig(from: directory);
    final projectRoot = loadedConfig?.source.parent ?? directory.absolute;
    final project =
        (argResults?['project'] as String?) ?? loadedConfig?.config.project;
    final app = (argResults?['app'] as String?) ?? loadedConfig?.config.app;
    if (project == null || app == null) {
      _stderr.writeln(
        'No project / app context. Run `restage init` or pass '
        '--project <slug> --app <slug>.',
      );
      return 1;
    }

    // Everything the receipt claims is checked before the first server call,
    // and the output it uploads is produced from the committed source.
    final ReleaseRecorder? recorder;
    final ReceiptSource? recordedSource;
    if (_recordGit(loadedConfig?.config)) {
      recorder = await ReleaseRecorder.open(
        projectRoot: projectRoot,
        stderr: _stderr,
        processRunner: _processRunner,
      );
      if (recorder == null) return 1;
      recordedSource = await recorder.buildFromCommittedSource(
        stdout: _stdout,
        stderr: _stderr,
        generator: _generator,
      );
      if (recordedSource == null) return 1;
    } else {
      recorder = null;
      recordedSource = null;
    }

    final List<AssembledSurfacePublication> assembled;
    final String generationFingerprint;
    try {
      final manifest = await SurfacePublicationManifestLoader().load(
        projectRoot: projectRoot,
      );
      generationFingerprint = manifest.outputIndex.generationFingerprint;
      final entries = await resolvePublicationEntries(
        manifest: manifest,
        argument: selector,
        all: argResults?['all'] as bool? ?? false,
        type: type,
        interactive: _interactive,
        stderr: _stderr,
        commandLine: 'restage surface push',
      );
      if (entries == null) return 1;
      // Everything is assembled before any network work, so a broken
      // closure fails the whole invocation instead of half-pushing.
      final assembler = SurfacePublicationAssembler(
        bundleReader: _bundleReader,
      );
      assembled = <AssembledSurfacePublication>[
        for (final entry in entries)
          await assembler.assemble(loaded: manifest, entry: entry),
      ];
    } on PublicationException catch (error) {
      _stderr.writeln(error.message);
      return 1;
    }

    for (final publication in assembled) {
      if (publication.capabilityWarning != null) {
        _stderr.writeln(publication.capabilityWarning);
      }
    }
    // The closure guard is per entry, so it has to hold across a multi-entry
    // set and not only the single-entry one.
    for (final publication in assembled) {
      if (publication.measurementUpload != null &&
          publication.hasMixedMeasurementSourceClosure) {
        _stderr.writeln(
          'The generated Measurement closure mixes bundled and non-bundled '
          'source bundle placements. Re-run `dart run build_runner build` and '
          'retry.',
        );
        return 1;
      }
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
        config: loadedConfig?.config,
        credential: credential,
      );
    } on EndpointConfigurationException catch (error) {
      _stderr.writeln(error.toString());
      return 1;
    }

    final environment = await _resolveEnvironment(
      argResults?['env'] as String?,
      loadedConfig?.config.defaultEnvironment,
    );
    if (environment == null) return 1;

    return _runPipeline(
      credential: credential,
      apiEndpoint: apiEndpoint,
      packageRoot: projectRoot,
      project: project,
      app: app,
      environment: environment,
      preferredOrganizationSlug:
          (argResults?['organization'] as String?) ??
          loadedConfig?.config.organization,
      runtimePlane: runtimePlaneFromArgs(argResults),
      assembled: assembled,
      recorder: recorder,
      recordedSource: recordedSource,
      generationFingerprint: generationFingerprint,
    );
  }

  /// Whether this invocation records a release receipt.
  bool _recordGit(RestageConfig? config) {
    final results = argResults;
    if (results != null && results.wasParsed('record-git')) {
      return results['record-git'] as bool;
    }
    return config?.recordGit ?? false;
  }

  Surface? _parseType(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return Surface.fromWireName(raw);
    } on FormatException {
      _stderr.writeln(
        'Invalid --type "$raw". Valid values: ${_validSurfaceTypeList()}.',
      );
      return null;
    }
  }

  Future<int> _runPipeline({
    required Credential credential,
    required Uri apiEndpoint,
    required Directory packageRoot,
    required String project,
    required String app,
    required String environment,
    required String? preferredOrganizationSlug,
    required RuntimePlane? runtimePlane,
    required List<AssembledSurfacePublication> assembled,
    required ReleaseRecorder? recorder,
    required ReceiptSource? recordedSource,
    required String generationFingerprint,
  }) async {
    final RestageApi api;
    try {
      api = RestageApi(
        endpoint: apiEndpoint,
        httpClient: _httpClient,
        credential: credential,
      );
    } on InsecureEndpointException catch (error) {
      _stderr.writeln(error.toString());
      return 1;
    }

    try {
      final target = await resolveEnvironmentTargetContext(
        api: api,
        interactive: _interactive,
        stderr: _stderr,
        projectSlug: project,
        appSlug: app,
        environmentSlug: environment,
        preferredOrganizationSlug: preferredOrganizationSlug,
        runtimePlane: runtimePlane,
      );
      if (target == null) return 1;

      var recordFailed = false;
      final recordedPushes = <String>[];
      final pushCode = await runPush(
        api: api,
        assembled: assembled,
        packageRoot: packageRoot,
        project: project,
        app: app,
        environment: environment,
        target: target,
        noun: 'surface',
        describe: (publication) =>
            'Pushed ${publication.entry.publication.slug} '
            '(${publication.entry.publication.surface.wireName})',
        onApiException: _handleApiException,
        stdout: _stdout,
        stderr: _stderr,
        onPushed: recorder == null
            ? null
            : (publication, result) async {
                recordedPushes.add(
                  '${result.family.surfaceSlug} r${result.storedRevision}',
                );
                final written = await recorder.write(
                  receipt: _pushReceipt(
                    publication: publication,
                    result: result,
                    target: target,
                    source: recordedSource!,
                    project: project,
                    app: app,
                    environment: environment,
                    organization: preferredOrganizationSlug,
                    generationFingerprint: generationFingerprint,
                  ),
                  relativePath: surfacePushReceiptPath(
                    organization: target.organizationSlug,
                    project: project,
                    app: app,
                    surfaceType: result.family.surfaceType,
                    surfaceId: result.family.surfaceSlug,
                    environment: environment,
                    revision: result.storedRevision,
                  ),
                  stdout: _stdout,
                  stderr: _stderr,
                );
                if (!written) recordFailed = true;
              },
      );
      if (recorder == null) return pushCode;

      // The receipts are already on disk, so the commit happens whether or
      // not the run reached every surface it was given.
      final committed = await recorder.commit(
        message: _receiptCommitMessage(recordedPushes, environment),
        stdout: _stdout,
        stderr: _stderr,
      );
      if (pushCode != 0) return pushCode;
      return committed && !recordFailed ? 0 : 2;
    } finally {
      if (_httpClient == null) api.close();
    }
  }

  /// The receipt for one accepted push.
  ReleaseReceipt _pushReceipt({
    required AssembledSurfacePublication publication,
    required SurfacePublicationUploadResult result,
    required ResolvedEnvironmentTargetContext target,
    required ReceiptSource source,
    required String project,
    required String app,
    required String environment,
    required String? organization,
    required String generationFingerprint,
  }) => ReleaseReceipt(
    operation: ReceiptOperation.surfacePush,
    recordedAt: DateTime.now(),
    target: ReceiptTarget(
      organization: target.organizationSlug,
      organizationId: target.organizationId,
      project: project,
      app: app,
      environment: environment,
      environmentTargetId: target.target.environmentTargetId,
      runtimePlane: target.target.runtimePlane.wireName,
    ),
    surface: ReceiptSurface(
      type: result.family.surfaceType,
      id: result.family.surfaceSlug,
      sourceKind: result.family.sourceKind,
      contractVersion: result.family.contractVersion,
    ),
    revision: ReceiptRevision(
      stored: result.storedRevision,
      activeAfter: result.activeRevision,
      identityFrozen: result.identityFrozen,
    ),
    artifacts: [
      for (final artifact in publication.entry.artifacts)
        ReceiptArtifact(path: artifact.path, contentHash: artifact.contentHash),
    ],
    generationFingerprint: generationFingerprint,
    source: source,
  );

  /// The message for the one commit an invocation makes.
  String _receiptCommitMessage(List<String> pushes, String environment) {
    if (pushes.length == 1) {
      return 'restage: push ${pushes.single} to $environment';
    }
    return 'restage: push ${pushes.length} surfaces to $environment\n\n'
        '${pushes.join('\n')}';
  }

  int _handleApiException(RestageApiException error) {
    final outcome = renderGenericTypedError(error);
    if (outcome != null) {
      _stderr.writeln(outcome.message);
      return outcome.exitCode;
    }
    _stderr.writeln('Could not push the generated surface.');
    return 1;
  }

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
}

String _validSurfaceTypeList() =>
    Surface.values.map((surface) => surface.wireName).join(', ');
