import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/api/surface_api.dart';
import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/api/delivery_management_api.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/selector_syntax.dart';
import 'package:restage_cli/src/commands/build_command.dart';
import 'package:restage_cli/src/commands/render_bundle_coverage.dart';
import 'package:restage_cli/src/api/surface_publication_api.dart';
import 'package:restage_cli/src/api/typed_error_renderer.dart';
import 'package:restage_cli/src/commands/organization_resolution.dart';
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
import 'package:restage_cli/src/render_bundles/surface_capture.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    hide RuntimePlane;

/// Push one generated surface from its exact manifest artifact closure.
/// Extra time a render gets when `--build` holds the Flutter lock first.
const _buildAllowance = Duration(minutes: 6);

class SurfacePushCommand extends Command<int> {
  /// Construct a push command.
  SurfacePushCommand({
    required StringSink stdout,
    required StringSink stderr,
    required Interactive interactive,
    FileCredentialStore? credentialStore,
    http.Client? httpClient,
    BuildCommandFactory? buildCommand,
    PublicationBundleReader? bundleReader,
    GitProcessRunner? processRunner,
    ReceiptGeneratorRunner? generator,
    SurfaceImageCapturer? imageCapturer,
  }) : _stdout = stdout,
       _stderr = stderr,
       _interactive = interactive,
       _credentialStore = credentialStore,
       _httpClient = httpClient,
       _buildCommand = buildCommand,
       _bundleReader = bundleReader,
       _processRunner = processRunner,
       _generator = generator,
       _imageCapturer = imageCapturer ?? captureSurfaceImages {
    argParser
      ..addFlag(
        'build',
        negatable: false,
        help:
            'Push the app\'s build to the same environment first, so the '
            'dashboard can display the widgets these surfaces use. A failed '
            'build does not stop the push.',
      )
      ..addOption(
        'flutter-root',
        help:
            'Flutter SDK directory the --build step builds with (overrides '
            '`flutterRoot` in restage_config.yaml).',
      )
      ..addFlag(
        'declare-assets',
        negatable: false,
        help:
            'Add the files this push writes into the app to flutter.assets '
            'in pubspec.yaml, keeping its comments. `declareAssets: true` in '
            'restage_config.yaml does the same.',
      )
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
      ..addOption(
        'name',
        help: 'A name for the pushed version, 60 characters or fewer.',
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
    addOrganizationIdOption(argParser);
  }

  final StringSink _stdout;
  final StringSink _stderr;
  final Interactive _interactive;
  final FileCredentialStore? _credentialStore;
  final http.Client? _httpClient;
  final BuildCommandFactory? _buildCommand;
  final PublicationBundleReader? _bundleReader;
  final GitProcessRunner? _processRunner;
  final ReceiptGeneratorRunner? _generator;
  final SurfaceImageCapturer _imageCapturer;

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
    final rawName = (argResults?['name'] as String?)?.trim();
    final versionName = rawName == null || rawName.isEmpty ? null : rawName;
    if ((versionName?.length ?? 0) > 60) {
      _stderr.writeln('Names are 60 characters or fewer.');
      return 1;
    }

    final directory = Directory(argResults?['directory'] as String? ?? '.');
    final loadedConfig = await loadRestageConfig(from: directory);
    final projectRoot = loadedConfig?.source.parent ?? directory.absolute;
    final project =
        (argResults?['project'] as String?) ?? loadedConfig?.config.project;
    final app = (argResults?['app'] as String?) ?? loadedConfig?.config.app;
    if (project == null || app == null) {
      _stderr.writeln(
        missingProjectContextSentence(
          hasConfig: loadedConfig != null,
          projectMissing: project == null,
        ),
      );
      return 1;
    }

    // Everything the receipt claims is checked before the first server call,
    // and the output it uploads is produced from the committed source.
    final ReleaseRecorder? recorder;
    final ReceiptSource? recordedSource;
    if (_recordGit(loadedConfig?.config)) {
      try {
        recorder = await ReleaseRecorder.open(
          projectRoot: projectRoot,
          processRunner: _processRunner,
        );
      } on ReleaseRecorderException catch (error) {
        _stderr.writeln(error.message);
        return 1;
      }
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
        push: surfacePushFollowUp,
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
      if (publication.unhandledEventsWarning != null) {
        _stderr.writeln(publication.unhandledEventsWarning);
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
      _stderr.writeln(notSignedInSentence());
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

    // Images render while the build runs, and each rides its surface's push.
    // Only a surface drawn with the app's own widgets needs one. A failed
    // render never fails the push.
    final building = argResults?['build'] as bool? ?? false;
    final stopRender = Completer<void>();
    final images =
        _imageCapturer(
          projectRoot: projectRoot,
          entries: [
            for (final publication in assembled)
              if (_drawnWithAppWidgets(publication)) publication.entry,
          ],
          flagRoot: argResults?['flutter-root'] as String?,
          configRoot: loadedConfig?.config.flutterRoot,
          // The render waits on the Flutter lock while the build holds it.
          timeout: building
              ? surfaceCaptureTimeout + _buildAllowance
              : surfaceCaptureTimeout,
          cancel: stopRender.future,
        ).catchError(
          (Object _) => const SurfaceCaptureResult(
            failure: 'rendering stopped unexpectedly',
          ),
        );

    var buildCode = 0;
    if (building) {
      buildCode = await pushBuildFirst(
        buildCommand:
            _buildCommand ??
            () => BuildCommand(
              stdout: _stdout,
              stderr: _stderr,
              credentialStore: _credentialStore,
              httpClient: _httpClient,
            ),
        project: project,
        app: app,
        organization: resolveOrganizationSlug(argResults, loadedConfig?.config),
        organizationId: organizationIdOption(argResults),
        environment: environment,
        directory: directory,
        recordGit: _recordGit(loadedConfig?.config),
        stdout: _stdout,
        stderr: _stderr,
        flutterRoot: argResults?['flutter-root'] as String?,
      );
    }

    final int code;
    try {
      code = await _runPipeline(
        credential: credential,
        apiEndpoint: apiEndpoint,
        packageRoot: projectRoot,
        project: project,
        app: app,
        environment: environment,
        preferredOrganizationSlug: resolveOrganizationSlug(
          argResults,
          loadedConfig?.config,
        ),
        runtimePlane: resolveRuntimePlane(argResults, loadedConfig?.config),
        configuredPlane: loadedConfig?.config.plane,
        config: loadedConfig?.config,
        configSource: loadedConfig?.source,
        assembled: assembled,
        buildFailed: buildCode != 0,
        declareAssets:
            (argResults?['declare-assets'] as bool? ?? false) ||
            (loadedConfig?.config.declareAssets ?? false),
        recorder: recorder,
        recordedSource: recordedSource,
        generationFingerprint: generationFingerprint,
        versionName: versionName,
        images: images,
      );
    } finally {
      // No render outlives the command: one the push no longer needs stops.
      if (!stopRender.isCompleted) stopRender.complete();
      await images;
    }
    if (buildCode == 0) return code;
    reportBuildNotPushed(
      app: app,
      environment: environment,
      surfacesPushed: code == 0,
      stderr: _stderr,
    );
    return code == 0 ? buildCode : code;
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
    required RuntimePlane? configuredPlane,
    required RestageConfig? config,
    required File? configSource,
    required List<AssembledSurfacePublication> assembled,
    required bool buildFailed,
    required bool declareAssets,
    required ReleaseRecorder? recorder,
    required ReceiptSource? recordedSource,
    required String generationFingerprint,
    required String? versionName,
    required Future<SurfaceCaptureResult> images,
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
      final ResolvedEnvironmentTargetContext target;
      try {
        target = await resolveTargetInteractively(
          api: api,
          interactive: _interactive,
          projectSlug: project,
          appSlug: app,
          environmentSlug: environment,
          organizationSlug: preferredOrganizationSlug,
          organizationId:
              organizationIdOption(argResults) ??
              (config?.organization == preferredOrganizationSlug
                  ? config?.organizationId
                  : null),
          environmentTargetId:
              config?.project == project &&
                  config?.app == app &&
                  config?.defaultEnvironment == environment &&
                  config?.organization == preferredOrganizationSlug &&
                  (organizationIdOption(argResults) == null ||
                      config?.organizationId ==
                          organizationIdOption(argResults)) &&
                  !(argResults?.wasParsed('plane') ?? false)
              ? config?.environmentTargetId
              : null,
          runtimePlane: runtimePlane,
          configuredPlane: configuredPlane,
        );
      } on TargetSelectionException catch (error) {
        _stderr.writeln(error.message);
        return 1;
      } on RestageApiException catch (error) {
        return _handleApiException(error);
      } on SocketException catch (error) {
        _stderr.writeln(backendUnreachableMessage(api.endpoint, error));
        return 2;
      }

      if (recorder == null) {
        await persistConfirmedTargetIds(
          configSource: configSource,
          config: config,
          target: target,
        );
      }

      final imageOf = _reportImages(await images, assembled);
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
        declareAssets: declareAssets,
        imageOf: imageOf,
        onPushed: (publication, result) async {
          await _reportPublicationFit(
            api: api,
            result: result,
            target: target,
            project: project,
            app: app,
          );
          if (versionName != null) {
            await SurfaceApi(api).renameVersion(
              project: project,
              app: app,
              surfaceType: publication.entry.publication.surface,
              surfaceSlug: publication.entry.publication.slug,
              environment: environment,
              version: result.storedRevision,
              label: versionName,
              environmentTargetId: target.target.environmentTargetId,
              runtimePlane: target.target.runtimePlane,
              organizationId: target.organizationId,
              contractVersion: result.family.contractVersion,
            );
          }
          final receipt = _pushReceipt(
            publication: publication,
            result: result,
            target: target,
            source: recordedSource ?? const ReceiptSource.unknown(),
            project: project,
            app: app,
            environment: environment,
            organization: preferredOrganizationSlug,
            generationFingerprint: generationFingerprint,
          );
          final relativePath = surfacePushReceiptPath(
            organization: target.organizationSlug,
            project: project,
            app: app,
            surfaceType: result.family.surfaceType,
            surfaceId: result.family.surfaceSlug,
            environment: environment,
            revision: result.storedRevision,
          );
          // Every push leaves its receipt; --record-git also commits it.
          final bool written;
          if (recorder == null) {
            written =
                await writeReceiptFile(
                  projectRoot: packageRoot,
                  receipt: receipt,
                  relativePath: relativePath,
                  stdout: _stdout,
                  stderr: _stderr,
                ) !=
                null;
          } else {
            recordedPushes.add(
              '${result.family.surfaceSlug} r${result.storedRevision}',
            );
            written = await recorder.write(
              receipt: receipt,
              relativePath: relativePath,
              stdout: _stdout,
              stderr: _stderr,
            );
          }
          if (!written) recordFailed = true;
        },
      );
      // A failed build is reported on its own, after the push.
      if (pushCode == 0 && !buildFailed) {
        await reportRenderBundleCoverage(
          api: api,
          assembled: assembled,
          project: project,
          app: app,
          environment: environment,
          target: target,
          stdout: _stdout,
          stderr: _stderr,
        );
      }
      if (recorder == null) {
        return pushCode != 0 || !recordFailed ? pushCode : 2;
      }

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

  /// Says which surfaces push without an image and why, and returns the
  /// image each of the others carries.
  Uint8List? Function(AssembledSurfacePublication) _reportImages(
    SurfaceCaptureResult images,
    List<AssembledSurfacePublication> assembled,
  ) {
    if (images.failure case final failure?) {
      if (assembled.any(_drawnWithAppWidgets)) {
        _stderr.writeln('Pushing without surface images: $failure.');
      }
      return (_) => null;
    }
    String nameOf(AssembledSurfacePublication publication) => surfaceImageName(
      surfaceType: publication.entry.publication.surface.wireName,
      slug: publication.entry.publication.slug,
    );
    for (final publication in assembled.where(_drawnWithAppWidgets)) {
      final name = nameOf(publication);
      if (images.images.containsKey(name)) continue;
      if (images.skipped[name] case final reason?) {
        _stderr.writeln(
          'Pushing ${publication.entry.publication.slug} without an image: '
          '$reason.',
        );
      }
    }
    return (publication) => _drawnWithAppWidgets(publication)
        ? images.images[nameOf(publication)]
        : null;
  }

  static bool _drawnWithAppWidgets(AssembledSurfacePublication publication) =>
      publication.payload.requiredLibraries.isNotEmpty;

  Future<void> _reportPublicationFit({
    required RestageApi api,
    required SurfacePublicationUploadResult result,
    required ResolvedEnvironmentTargetContext target,
    required String project,
    required String app,
  }) async {
    final publication = result.deliveryPublication;
    void unavailable([String? reason]) => _stdout.writeln(
      'Placement fit report unavailable for stored revision ${result.storedRevision}'
      '${reason == null ? '.' : ': $reason.'}',
    );
    if (publication == null) {
      unavailable();
      return;
    }
    final coordinate = publication.surface.target;
    if (coordinate.organizationId.value != target.organizationId ||
        coordinate.appId.value != target.appId ||
        coordinate.environmentTargetId.value !=
            target.target.environmentTargetId ||
        coordinate.namedEnvironmentId.value !=
            target.target.namedEnvironmentId ||
        coordinate.runtimePlane.name != target.target.runtimePlane.wireName) {
      unavailable();
      return;
    }
    try {
      final reader = DeliveryManagementApi(api);
      final entries = <DeliveryPolicyFitEntryV1>[];
      final continuations = <String>{};
      CanonicalDigest? authorityDigest;
      String? cursor;
      do {
        final report = await reader.readFit(
          projectSlug: project,
          appSlug: app,
          environmentTargetId: target.target.environmentTargetId,
          runtimePlane: target.target.runtimePlane,
          organizationId: target.organizationId,
          request: DeliveryPolicyFitReadRequestV1.forPublication(
            publication: publication,
            pageSize: 200,
            cursor: cursor,
          ),
        );
        if (report.refusalCode != null) {
          unavailable(report.refusalCode);
          return;
        }
        if ((authorityDigest != null &&
                authorityDigest != report.authorityDigest) ||
            (report.nextCursor != null &&
                !continuations.add(report.nextCursor!))) {
          unavailable();
          return;
        }
        authorityDigest = report.authorityDigest;
        entries.addAll(report.entries);
        cursor = report.nextCursor;
      } while (cursor != null);
      _stdout.writeln(
        'Placement fit for stored revision ${result.storedRevision}; '
        'authority ${authorityDigest.hex}:',
      );
      for (final entry in entries) {
        final root = entry.scope.root;
        final label =
            root.placement?.key.value ??
            'surface:${root.surface!.surfaceId.value} '
                '${jsonEncode(entry.scope.family.toJson())}';
        _stdout.writeln(
          '  $label: ${utf8.decode(entry.verdictCanonicalBytes)}',
        );
      }
      if (entries.isEmpty) {
        _stdout.writeln('  No qualified placement fit entries.');
      }
    } on Exception {
      unavailable();
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
    final outcome = renderApiError(error);
    _stderr.writeln(outcome.message);
    return outcome.exitCode;
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
    _stderr.writeln(environmentRequiredSentence());
    return null;
  }
}

String _validSurfaceTypeList() =>
    Surface.values.map((surface) => surface.wireName).join(', ');
