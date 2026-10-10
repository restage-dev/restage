import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/api/experiment_api.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/commands/experimental_gate.dart';
import 'package:restage_cli/src/commands/authed.dart';
import 'package:restage_cli/src/commands/lifecycle_support.dart';
import 'package:restage_cli/src/commands/live_guard.dart';
import 'package:restage_cli/src/commands/measurement_page_command.dart';
import 'package:restage_cli/src/measurement/page_read.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_cli/src/operations/operation.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

/// Semantic experiment authoring, one subcommand per operation.
class ExperimentCommand extends Command<int> {
  /// Creates the experiment command and its subcommands.
  ExperimentCommand({
    required StringSink stdout,
    required StringSink stderr,
    required Interactive interactive,
    FileCredentialStore? credentialStore,
    http.Client? httpClient,
    Map<String, String>? environment,
  }) : _environment = environment {
    final context = (
      stdout: stdout,
      stderr: stderr,
      interactive: interactive,
      credentialStore: credentialStore,
      httpClient: httpClient,
    );
    for (final build in <_SubcommandFactory>[
      _DiscoverCommand.new,
      _CreateCommand.new,
      _DeleteDraftCommand.new,
      _ReadDraftCommand.new,
      _ResolveDraftCommand.new,
      _SaveCommand.new,
      _CopyCommand.new,
      _ValidateCommand.new,
      _ReviewCommand.new,
      _ActivateCommand.new,
      _PauseCommand.new,
      _ResumeCommand.new,
      _ConcludeCommand.new,
      _ReadCommand.new,
      _ArchiveCommand.new,
      _RegisterBuildCommand.new,
      _ReadinessCommand.new,
      _DeliveryOptionsCommand.new,
      _RebuildServingRecordsCommand.new,
    ]) {
      addSubcommand(build(context));
    }
    for (final read in pageReads) {
      if (!read.cliPath.startsWith('experiment ')) continue;
      addSubcommand(
        MeasurementPageCommand(
          read,
          stdout: stdout,
          stderr: stderr,
          interactive: interactive,
          credentialStore: credentialStore,
          httpClient: httpClient,
        ),
      );
    }
  }

  final Map<String, String>? _environment;

  @override
  String get name => 'experiment';

  @override
  String get description =>
      'Author, review, activate, and read experiments at one target.';

  /// Whether this host has opted in to the experimental commands.
  bool get enabled => experimentalCommandsEnabled(_environment);
}

/// Everything a subcommand needs to reach the operator and the service.
typedef _ExperimentCommandContext = ({
  StringSink stdout,
  StringSink stderr,
  Interactive interactive,
  FileCredentialStore? credentialStore,
  http.Client? httpClient,
});

typedef _SubcommandFactory =
    _ExperimentSubcommand Function(_ExperimentCommandContext context);

/// Shared plumbing for one semantic experiment operation.
abstract class _ExperimentSubcommand extends Command<int> {
  _ExperimentSubcommand(_ExperimentCommandContext context)
    : _stdout = context.stdout,
      _stderr = context.stderr,
      _interactive = context.interactive,
      _credentialStore = context.credentialStore,
      _httpClient = context.httpClient {
    addLifecycleOptions(argParser, withType: false, withReason: false);
    argParser.addFlag(
      'json',
      negatable: false,
      help: 'Print the exact semantic result as JSON.',
    );
    if (operation != null && operation!.requiresIdempotencyKey) {
      argParser.addOption(
        'idempotency-key',
        help:
            'Retry identity for this write. A repeat with the same key and the '
            'same content is the same attempt. Generated when omitted.',
      );
    }
    addOptions(argParser);
  }

  final StringSink _stdout;
  final StringSink _stderr;
  final Interactive _interactive;
  final FileCredentialStore? _credentialStore;
  final http.Client? _httpClient;

  /// The single operation this subcommand invokes, or null when it drains.
  ExperimentAuthoringOperationV1? get operation;

  /// Registers the selectors this operation's payload needs.
  void addOptions(ArgParser parser) {}

  /// Builds this operation's payload, or null after a precise error.
  Map<String, Object?>? buildPayload();

  /// Whether this operation changes live state and needs live confirmation.
  bool get changesLiveState => kLiveExperimentOperations.contains(operation);

  /// Runs an operator call instead of a semantic operation. Null when this
  /// subcommand names one.
  Future<int>? operatorCall({
    required RestageApi transport,
    required TargetCoordinate target,
    required bool asJson,
  }) => null;

  /// Runs a drain instead of one request. Null when the operation is single.
  Future<ExperimentPageDrain<Object?>>? drain(
    ExperimentApi api,
    TargetCoordinate target,
    String correlationId,
  ) => null;

  /// Renders one accepted response for a human reader.
  String renderAccepted(ExperimentAuthoringAcceptedV1 accepted) =>
      'Accepted ${accepted.operation.wireName}.';

  /// Renders one drained accumulation for a human reader.
  String renderDrained(Object? value) => 'Accepted.';

  @override
  bool get hidden {
    final owner = parent;
    return owner is ExperimentCommand && !owner.enabled;
  }

  @override
  Future<int> run() async {
    final owner = parent;
    if (owner is ExperimentCommand && !owner.enabled) {
      _stderr.writeln(experimentalCommandRefusal('experiment $name'));
      return 1;
    }

    final asJson = argResults?['json'] as bool? ?? false;
    return runAuthed(
      CommandIo(
        stdout: _stdout,
        stderr: _stderr,
        interactive: _interactive,
        credentialStore: _credentialStore,
        httpClient: _httpClient,
      ),
      argResults,
      OperationScope.target,
      (ctx) => _execute(ctx.api, ctx.target!, asJson: asJson),
    );
  }

  Future<int> _execute(
    RestageApi transport,
    LifecycleContext context, {
    required bool asJson,
  }) async {
    final payload = buildPayload();
    if (payload == null) return 1;

    final target = _targetOf(context);
    if (changesLiveState && !await _confirmLiveExperimentChange(target)) {
      return 1;
    }

    final api = ExperimentApi(transport);

    // Built before the send, so a bad selector is reported as the operator's
    // to fix rather than blamed on the service.
    ExperimentAuthoringRequestV1? request;
    if (operation != null) {
      try {
        final resolvedOperation = operation!;
        final idempotencyKey = resolvedOperation.requiresIdempotencyKey
            ? (argResults?['idempotency-key'] as String?) ??
                  _newIdentity('idempotency')
            : null;
        final correlationId = idempotencyKey == null
            ? _newIdentity('correlation')
            : experimentRetryCorrelationId(
                operation: resolvedOperation,
                payload: payload,
                idempotencyKey: idempotencyKey,
              );
        request = experimentRequest(
          operation: resolvedOperation,
          correlationId: correlationId,
          payload: payload,
          idempotencyKey: idempotencyKey,
        );
      } on CanonicalFormatException catch (error) {
        _stderr.writeln(error.message);
        return 1;
      }
    }

    try {
      final operatorRun = operatorCall(
        transport: transport,
        target: target,
        asJson: asJson,
      );
      if (operatorRun != null) return await operatorRun;

      final drained = drain(
        api,
        target,
        request?.correlationId ?? _newIdentity('correlation'),
      );
      if (drained != null) return _reportDrain(await drained, asJson: asJson);

      final result = await api.execute(request: request!, target: target);
      return _report(result, asJson: asJson);
    } on ExperimentResponseMismatchException catch (error) {
      _stderr.writeln(error);
      return 2;
    } on ExperimentPageCursorRepeatedException catch (error) {
      _stderr.writeln(error);
      return 2;
    } on RestageApiException catch (error) {
      _stderr.writeln(
        'The experiment route did not accept the request '
        '(HTTP ${error.statusCode}). Confirm the selected target and '
        'authorization, then retry.',
      );
      return error.statusCode >= 500 ? 2 : 1;
    } on CanonicalFormatException {
      _stderr.writeln('The service returned an invalid semantic result.');
      return 2;
    }
  }

  int _report(ExperimentAuthoringResultV1 result, {required bool asJson}) {
    if (asJson) {
      _stdout.writeln(jsonEncode(result.toJson()));
    } else if (result is ExperimentAuthoringAcceptedV1) {
      _stdout.writeln(renderAccepted(result));
    } else {
      _stderr.writeln(_refusalLine(result as ExperimentAuthoringRefusedV1));
    }
    if (result is! ExperimentAuthoringRefusedV1) return 0;
    return _refusalExitCode(result.refusal);
  }

  int _reportDrain(
    ExperimentPageDrain<Object?> drained, {
    required bool asJson,
  }) {
    switch (drained) {
      case ExperimentPagesAccepted(:final value):
        if (asJson) {
          _stdout.writeln(jsonEncode(_drainJson(value)));
        } else {
          _stdout.writeln(renderDrained(value));
        }
        return 0;
      case ExperimentPagesRefused(:final refusal):
        if (asJson) {
          _stdout.writeln(jsonEncode(refusal.toJson()));
        } else {
          _stderr.writeln(_refusalLine(refusal));
        }
        return _refusalExitCode(refusal.refusal);
    }
  }

  String _refusalLine(ExperimentAuthoringRefusedV1 refused) {
    final refusal = refused.refusal;
    final headline =
        'Refused ${refused.operation.wireName}: ${refusal.code.wireName}'
        '${refusal.retryable ? " (retryable)" : ""}.';
    final locator = refusal.locator;
    return locator == null
        ? headline
        : '$headline\n${_audienceConflictLine(locator, refusal.messageKey)}';
  }

  /// Consent to change a running experiment on the live plane; `--yes` is
  /// consent, and `--non-interactive` alone fails closed.
  Future<bool> _confirmLiveExperimentChange(TargetCoordinate target) =>
      confirmLiveChange(
        command: this,
        interactive: _interactive,
        stdout: _stdout,
        stderr: _stderr,
        live: target.runtimePlane == RuntimePlane.live,
        impactLine: 'Experiment $name on the live plane.',
      );

  /// Reads a required option, or prints a precise error and returns null.
  String? requireOption(String option) {
    final value = (argResults?[option] as String?)?.trim();
    if (value != null && value.isNotEmpty) return value;
    _stderr.writeln('Required: --$option <value>.');
    return null;
  }

  /// Reads a required non-negative integer option, or null after an error.
  int? requireNonNegativeInt(String option) {
    final raw = requireOption(option);
    if (raw == null) return null;
    final value = int.tryParse(raw);
    if (value == null || value < 0) {
      _stderr.writeln('--$option must be zero or a positive integer.');
      return null;
    }
    return value;
  }

  /// Reads an optional positive integer option; null when absent or invalid.
  int? optionalPositiveInt(String option) {
    final raw = (argResults?[option] as String?)?.trim();
    if (raw == null || raw.isEmpty) return null;
    final value = int.tryParse(raw);
    if (value == null || value <= 0) {
      _stderr.writeln('--$option must be a positive integer.');
      return null;
    }
    return value;
  }

  /// Reads a required positive integer option, or null after an error.
  int? requirePositiveInt(String option) {
    final raw = requireOption(option);
    if (raw == null) return null;
    final value = int.tryParse(raw);
    if (value == null || value <= 0) {
      _stderr.writeln('--$option must be a positive integer.');
      return null;
    }
    return value;
  }

  /// Reads the shared draft binding selectors, or null after an error.
  Map<String, Object?>? requireDraftBinding() {
    final draftId = requireOption('draft-id');
    final draftRevisionId = requireOption('draft-revision-id');
    final expectedCas = requireOption('expected-cas');
    if (draftId == null || draftRevisionId == null || expectedCas == null) {
      return null;
    }
    return {
      'draftId': draftId,
      'draftRevisionId': draftRevisionId,
      'expectedCas': expectedCas,
    };
  }

  /// Registers the shared draft binding selectors.
  void addDraftBindingOptions(ArgParser parser) => parser
    ..addOption('draft-id', help: 'Draft identity (required).')
    ..addOption('draft-revision-id', help: 'Draft revision (required).')
    ..addOption(
      'expected-cas',
      help: 'Compare-and-set token read with the draft (required).',
    );
}

/// Discovers authoring capability at the selected target.
class _DiscoverCommand extends _ExperimentSubcommand {
  _DiscoverCommand(super.context);

  ExperimentExactSurfaceReferenceV1? _exactSurfaceReference;

  @override
  String get name => 'discover';

  @override
  String get description =>
      'Discover authoring capability, surfaces, and metrics at one target.';

  @override
  ExperimentAuthoringOperationV1? get operation => null;

  @override
  void addOptions(ArgParser parser) => parser
    ..addOption(
      'surface-id',
      help: 'Exact published surface identity. Use with --surface-revision-id.',
    )
    ..addOption(
      'surface-revision-id',
      help:
          'Exact published surface revision. It can inspect an inactive '
          'published version without changing live delivery.',
    );

  @override
  Map<String, Object?>? buildPayload() {
    _exactSurfaceReference = null;
    final surfaceId = (argResults?['surface-id'] as String?)?.trim();
    final surfaceRevisionId = (argResults?['surface-revision-id'] as String?)
        ?.trim();
    if ((surfaceId == null || surfaceId.isEmpty) !=
        (surfaceRevisionId == null || surfaceRevisionId.isEmpty)) {
      _stderr.writeln(
        'Pass --surface-id and --surface-revision-id together, or neither.',
      );
      return null;
    }
    if (surfaceId == null || surfaceId.isEmpty) return const {};
    try {
      _exactSurfaceReference = ExperimentExactSurfaceReferenceV1.fromJson({
        'kind': 'exactSurfaceReference',
        'surfaceId': surfaceId,
        'surfaceRevisionId': surfaceRevisionId,
      });
    } on CanonicalFormatException catch (error) {
      _stderr.writeln(error.message);
      return null;
    }
    return const {};
  }

  @override
  Future<ExperimentPageDrain<Object?>>? drain(
    ExperimentApi api,
    TargetCoordinate target,
    String correlationId,
  ) => api.discoverEveryPage(
    target: target,
    correlationId: correlationId,
    exactSurfaceReference: _exactSurfaceReference,
  );

  @override
  String renderDrained(Object? value) {
    final discovery = value! as ExperimentDiscovery;
    return 'Discovered ${discovery.surfaceCapabilities.length} surfaces and '
        '${discovery.metricCapabilities.length} metrics at '
        '${discovery.organizationLabel} / ${discovery.appLabel} / '
        '${discovery.environmentLabel}.';
  }
}

/// Opens a target-bound draft.
class _CreateCommand extends _ExperimentSubcommand {
  _CreateCommand(super.context);

  @override
  String get name => 'create';

  @override
  String get description => 'Open a new draft at the selected target.';

  @override
  ExperimentAuthoringOperationV1? get operation =>
      ExperimentAuthoringOperationV1.openDraft;

  @override
  void addOptions(ArgParser parser) => parser
    ..addOption('surface-id', help: 'Optional initial candidate surface.')
    ..addOption(
      'surface-revision-id',
      help: 'Optional initial candidate surface revision.',
    );

  @override
  Map<String, Object?>? buildPayload() {
    final surfaceId = (argResults?['surface-id'] as String?)?.trim();
    final surfaceRevisionId = (argResults?['surface-revision-id'] as String?)
        ?.trim();
    if ((surfaceId == null || surfaceId.isEmpty) !=
        (surfaceRevisionId == null || surfaceRevisionId.isEmpty)) {
      _stderr.writeln(
        'Pass --surface-id and --surface-revision-id together, or neither.',
      );
      return null;
    }
    if (surfaceId == null || surfaceId.isEmpty) return const {};
    return {
      'initialCandidate': {
        'kind': 'exactSurfaceReference',
        'surfaceId': surfaceId,
        'surfaceRevisionId': surfaceRevisionId,
      },
    };
  }

  @override
  String renderAccepted(ExperimentAuthoringAcceptedV1 accepted) =>
      'Opened draft.';
}

/// Deletes one exact draft revision.
class _DeleteDraftCommand extends _ExperimentSubcommand {
  _DeleteDraftCommand(super.context);

  @override
  String get name => 'delete-draft';

  @override
  String get description => 'Delete one exact draft revision.';

  @override
  ExperimentAuthoringOperationV1? get operation =>
      ExperimentAuthoringOperationV1.deleteDraft;

  @override
  void addOptions(ArgParser parser) => addDraftBindingOptions(parser);

  @override
  Map<String, Object?>? buildPayload() => requireDraftBinding();

  @override
  String renderAccepted(ExperimentAuthoringAcceptedV1 accepted) =>
      'Deleted draft.';
}

/// Reads one exact draft revision.
class _ReadDraftCommand extends _ExperimentSubcommand {
  _ReadDraftCommand(super.context);

  @override
  String get name => 'read-draft';

  @override
  String get description => 'Read one exact draft revision.';

  @override
  ExperimentAuthoringOperationV1? get operation =>
      ExperimentAuthoringOperationV1.readDraft;

  @override
  void addOptions(ArgParser parser) => addDraftBindingOptions(parser);

  @override
  Map<String, Object?>? buildPayload() => requireDraftBinding();

  @override
  String renderAccepted(ExperimentAuthoringAcceptedV1 accepted) =>
      'Read draft.';
}

/// Reads the draft a stable identity currently names.
class _ResolveDraftCommand extends _ExperimentSubcommand {
  _ResolveDraftCommand(super.context);

  @override
  String get name => 'resolve-draft';

  @override
  String get description =>
      'Read a draft by its identity, with the binding a write needs.';

  @override
  ExperimentAuthoringOperationV1? get operation =>
      ExperimentAuthoringOperationV1.resolveDraft;

  @override
  void addOptions(ArgParser parser) =>
      parser.addOption('draft-id', help: 'Draft identity (required).');

  @override
  Map<String, Object?>? buildPayload() {
    final draftId = requireOption('draft-id');
    if (draftId == null) return null;
    return {'draftId': draftId};
  }

  @override
  String renderAccepted(ExperimentAuthoringAcceptedV1 accepted) =>
      'Resolved draft.';
}

/// Replaces a draft's complete choices.
class _SaveCommand extends _ExperimentSubcommand {
  _SaveCommand(super.context);

  @override
  String get name => 'save';

  @override
  String get description => "Replace a draft's complete choices.";

  @override
  ExperimentAuthoringOperationV1? get operation =>
      ExperimentAuthoringOperationV1.replaceDraft;

  @override
  void addOptions(ArgParser parser) {
    addDraftBindingOptions(parser);
    parser.addOption(
      'replacement',
      help: 'Path to the complete draft choices as JSON (required).',
    );
  }

  @override
  Map<String, Object?>? buildPayload() {
    final binding = requireDraftBinding();
    final path = requireOption('replacement');
    if (binding == null || path == null) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(File(path).readAsStringSync());
    } on FileSystemException {
      _stderr.writeln('Could not read the replacement file.');
      return null;
    } on FormatException {
      _stderr.writeln('The replacement file is not valid JSON.');
      return null;
    }
    if (decoded is! Map<String, Object?>) {
      _stderr.writeln('The replacement file must contain a JSON object.');
      return null;
    }
    return {...binding, 'replacement': decoded};
  }

  @override
  String renderAccepted(ExperimentAuthoringAcceptedV1 accepted) =>
      'Saved draft.';
}

/// Copies a draft from one target to the selected target.
class _CopyCommand extends _ExperimentSubcommand {
  _CopyCommand(super.context);

  @override
  String get name => 'copy';

  @override
  String get description =>
      'Copy a draft from a source target to the selected target.';

  @override
  ExperimentAuthoringOperationV1? get operation =>
      ExperimentAuthoringOperationV1.copyDraftToTarget;

  @override
  void addOptions(ArgParser parser) => parser
    ..addOption('source-draft-id', help: 'Source draft identity (required).')
    ..addOption(
      'source-draft-revision-id',
      help: 'Source draft revision (required).',
    )
    ..addOption(
      'source-expected-cas',
      help: 'Source compare-and-set token (required).',
    )
    ..addOption(
      'source-organization-id',
      help: 'Source organization id (required).',
    )
    ..addOption('source-app-id', help: 'Source app id (required).')
    ..addOption(
      'source-environment-target-id',
      help: 'Source environment target id (required).',
    )
    ..addOption(
      'source-named-environment-id',
      help: 'Source named environment id (required).',
    )
    ..addOption(
      'source-plane',
      allowed: const ['sandbox', 'live'],
      help: 'Source runtime plane (required).',
    );

  @override
  Map<String, Object?>? buildPayload() {
    final draftId = requireOption('source-draft-id');
    final draftRevisionId = requireOption('source-draft-revision-id');
    final expectedCas = requireOption('source-expected-cas');
    final organizationId = requirePositiveInt('source-organization-id');
    final appId = requirePositiveInt('source-app-id');
    final environmentTargetId = requirePositiveInt(
      'source-environment-target-id',
    );
    final namedEnvironmentId = requirePositiveInt(
      'source-named-environment-id',
    );
    final plane = requireOption('source-plane');
    if (draftId == null ||
        draftRevisionId == null ||
        expectedCas == null ||
        organizationId == null ||
        appId == null ||
        environmentTargetId == null ||
        namedEnvironmentId == null ||
        plane == null) {
      return null;
    }
    return {
      'sourceDraft': {
        'draftId': draftId,
        'draftRevisionId': draftRevisionId,
        'expectedCas': expectedCas,
      },
      'sourceTarget': TargetCoordinate(
        organizationId: OrganizationId(organizationId),
        appId: ApplicationId(appId),
        environmentTargetId: EnvironmentTargetId(environmentTargetId),
        namedEnvironmentId: NamedEnvironmentId(namedEnvironmentId),
        runtimePlane: plane == 'live'
            ? RuntimePlane.live
            : RuntimePlane.sandbox,
      ).toJson(),
    };
  }

  @override
  String renderAccepted(ExperimentAuthoringAcceptedV1 accepted) =>
      'Copied draft to the selected target.';
}

/// Validates a draft without changing it.
class _ValidateCommand extends _ExperimentSubcommand {
  _ValidateCommand(super.context);

  @override
  String get name => 'validate';

  @override
  String get description => 'Validate a draft without changing it.';

  @override
  ExperimentAuthoringOperationV1? get operation =>
      ExperimentAuthoringOperationV1.validateDraft;

  @override
  void addOptions(ArgParser parser) => addDraftBindingOptions(parser);

  @override
  Map<String, Object?>? buildPayload() => requireDraftBinding();

  @override
  String renderAccepted(ExperimentAuthoringAcceptedV1 accepted) {
    final view = accepted.response as ExperimentValidationViewV1;
    return [
      'Validated draft: ${view.issues.length} issues.',
      ..._conflictLines(view.issues),
    ].join('\n');
  }
}

/// One line per issue that names an experiment already holding the audience.
Iterable<String> _conflictLines(
  Iterable<ExperimentValidationIssueV1> issues,
) sync* {
  for (final issue in issues) {
    final locator = issue.locator;
    if (locator == null) continue;
    yield _audienceConflictLine(locator, issue.messageKey);
  }
}

/// One human-readable rendering of the typed audience-conflict diagnostic.
String _audienceConflictLine(
  ExperimentAudienceConflictLocatorV1 locator,
  String messageKey,
) =>
    'Audience held by ${locator.conflictingExperimentId} '
    '(its revision ${locator.conflictingAudienceRef.revisionId.value}, '
    'this draft ${locator.proposedAudienceRef.revisionId.value}): '
    '$messageKey';

/// Issues an immutable review for a draft.
class _ReviewCommand extends _ExperimentSubcommand {
  _ReviewCommand(super.context);

  @override
  String get name => 'review';

  @override
  String get description => 'Issue an immutable review for a draft.';

  @override
  ExperimentAuthoringOperationV1? get operation =>
      ExperimentAuthoringOperationV1.reviewDraft;

  @override
  void addOptions(ArgParser parser) => addDraftBindingOptions(parser);

  @override
  Map<String, Object?>? buildPayload() => requireDraftBinding();

  @override
  String renderAccepted(ExperimentAuthoringAcceptedV1 accepted) =>
      'Issued review.';
}

/// Activates a reviewed draft.
class _ActivateCommand extends _ExperimentSubcommand
    implements LiveGuardedCommand {
  _ActivateCommand(super.context);

  @override
  String get name => 'activate';

  @override
  String get description => 'Activate a reviewed draft.';

  @override
  ExperimentAuthoringOperationV1? get operation =>
      ExperimentAuthoringOperationV1.activateDraft;

  @override
  void addOptions(ArgParser parser) {
    addDraftBindingOptions(parser);
    parser
      ..addOption('review-id', help: 'Review identity to activate (required).')
      ..addOption(
        'review-digest',
        help: 'Review record digest to activate (required).',
      );
  }

  @override
  Map<String, Object?>? buildPayload() {
    final binding = requireDraftBinding();
    final reviewId = requireOption('review-id');
    final recordDigest = requireOption('review-digest');
    if (binding == null || reviewId == null || recordDigest == null) {
      return null;
    }
    return {
      ...binding,
      'reviewReference': {
        'kind': 'experimentReviewReference',
        'recordDigest': recordDigest,
        'reviewId': reviewId,
        'schemaVersion': kMeasurementSchemaVersion,
      },
    };
  }

  @override
  String renderAccepted(ExperimentAuthoringAcceptedV1 accepted) =>
      'Activated experiment.';
}

/// Shared shape for the three lifecycle transitions.
abstract class _TransitionCommand extends _ExperimentSubcommand
    implements LiveGuardedCommand {
  _TransitionCommand(super.context);

  @override
  void addOptions(ArgParser parser) => parser
    ..addOption('experiment-id', help: 'Experiment identity (required).')
    ..addOption(
      'expected-lifecycle-ordinal',
      help: 'Lifecycle ordinal this transition expects (required).',
    );

  @override
  Map<String, Object?>? buildPayload() {
    final experimentId = requireOption('experiment-id');
    final ordinal = requirePositiveInt('expected-lifecycle-ordinal');
    if (experimentId == null || ordinal == null) return null;
    return {'expectedLifecycleOrdinal': ordinal, 'experimentId': experimentId};
  }
}

/// Pauses an active experiment.
class _PauseCommand extends _TransitionCommand {
  _PauseCommand(super.context);

  @override
  String get name => 'pause';

  @override
  String get description => 'Pause an active experiment.';

  @override
  ExperimentAuthoringOperationV1? get operation =>
      ExperimentAuthoringOperationV1.pauseExperiment;

  @override
  String renderAccepted(ExperimentAuthoringAcceptedV1 accepted) =>
      'Paused experiment.';
}

/// Resumes a paused experiment.
class _ResumeCommand extends _TransitionCommand {
  _ResumeCommand(super.context);

  @override
  String get name => 'resume';

  @override
  String get description => 'Resume a paused experiment.';

  @override
  ExperimentAuthoringOperationV1? get operation =>
      ExperimentAuthoringOperationV1.resumeExperiment;

  @override
  String renderAccepted(ExperimentAuthoringAcceptedV1 accepted) =>
      'Resumed experiment.';
}

/// Concludes an experiment.
class _ConcludeCommand extends _TransitionCommand {
  _ConcludeCommand(super.context);

  @override
  String get name => 'conclude';

  @override
  String get description => 'Conclude an experiment.';

  @override
  ExperimentAuthoringOperationV1? get operation =>
      ExperimentAuthoringOperationV1.concludeExperiment;

  @override
  String renderAccepted(ExperimentAuthoringAcceptedV1 accepted) =>
      'Concluded experiment.';
}

/// Reads one accepted experiment.
class _ReadCommand extends _ExperimentSubcommand {
  _ReadCommand(super.context);

  @override
  String get name => 'read';

  @override
  String get description => 'Read one accepted experiment.';

  @override
  ExperimentAuthoringOperationV1? get operation =>
      ExperimentAuthoringOperationV1.readExperiment;

  @override
  void addOptions(ArgParser parser) => parser.addOption(
    'experiment-id',
    help: 'Experiment identity (required).',
  );

  @override
  Map<String, Object?>? buildPayload() {
    final experimentId = requireOption('experiment-id');
    if (experimentId == null) return null;
    return {'experimentId': experimentId};
  }

  @override
  String renderAccepted(ExperimentAuthoringAcceptedV1 accepted) =>
      'Read experiment.';
}

/// Reads what one finished experiment can hand to delivery.
class _DeliveryOptionsCommand extends _ExperimentSubcommand {
  _DeliveryOptionsCommand(super.context);

  @override
  String get name => 'delivery-options';

  @override
  String get description =>
      'Read the surface, audience and per-arm delivery publication one '
      'experiment offers.';

  @override
  ExperimentAuthoringOperationV1? get operation =>
      ExperimentAuthoringOperationV1.readDeliveryOptions;

  @override
  void addOptions(ArgParser parser) => parser.addOption(
    'experiment-id',
    help: 'Experiment identity (required).',
  );

  @override
  Map<String, Object?>? buildPayload() {
    final experimentId = requireOption('experiment-id');
    if (experimentId == null) return null;
    return {'experimentId': experimentId};
  }

  @override
  String renderAccepted(ExperimentAuthoringAcceptedV1 accepted) {
    final view = accepted.response as ExperimentDeliveryOptionsViewV1;
    return [
      '${view.surfaceSlug} (${view.surfaceType.value}) for '
          '${view.audienceLabel}, revision '
          '${view.audienceRevisionId.value}',
      for (final arm in view.arms)
        '  ${arm.stableArmId.value}  ${arm.label}  '
            '${_deliveryArmPublication(arm)}',
    ].join('\n');
  }
}

String _deliveryArmPublication(ExperimentDeliveryArmV1 arm) => switch (arm) {
  ExperimentArmDeliveryV1(:final publishedVersion) =>
    'version $publishedVersion',
  ExperimentSurfaceContractArmDeliveryV1(
    :final contractVersion,
    :final publishedRevision,
  ) =>
    'revision $publishedRevision (contract $contractVersion)',
};

/// Registers what one installed app build can supply.
class _RegisterBuildCommand extends _ExperimentSubcommand {
  _RegisterBuildCommand(super.context);

  @override
  String get name => 'register-build';

  @override
  String get description =>
      'Register what one installed app build reports for a context schema.';

  @override
  ExperimentAuthoringOperationV1? get operation =>
      ExperimentAuthoringOperationV1.registerBuildCapabilities;

  @override
  void addOptions(ArgParser parser) => parser
    ..addOption('platform', help: 'Platform of the installed build (required).')
    ..addOption(
      'app-build-ordinal',
      help: 'Build number of the installed build (required).',
    )
    ..addOption(
      'sdk-api-level',
      help: 'Assignment API level that build ships (required).',
    )
    ..addOption(
      'context-schema-id',
      help: 'Context schema identity (required).',
    )
    ..addOption(
      'context-schema-revision-id',
      help: 'Exact context schema revision (required).',
    )
    ..addOption(
      'context-schema-digest',
      help: 'Semantic digest of that revision (required).',
    );

  @override
  Map<String, Object?>? buildPayload() {
    final platform = requireOption('platform');
    final appBuildOrdinal = requireNonNegativeInt('app-build-ordinal');
    final sdkApiLevel = requirePositiveInt('sdk-api-level');
    final schemaId = requireOption('context-schema-id');
    final revisionId = requireOption('context-schema-revision-id');
    final digest = requireOption('context-schema-digest');
    if (platform == null ||
        appBuildOrdinal == null ||
        sdkApiLevel == null ||
        schemaId == null ||
        revisionId == null ||
        digest == null) {
      return null;
    }
    return {
      'appBuildOrdinal': appBuildOrdinal,
      'contextSchemaRef': {
        'contextSchemaId': schemaId,
        'revisionId': revisionId,
        'semanticDigest': digest,
      },
      'platform': platform,
      'sdkApiLevel': sdkApiLevel,
    };
  }

  @override
  String renderAccepted(ExperimentAuthoringAcceptedV1 accepted) {
    final view = accepted.response as ExperimentBuildCapabilityViewV1;
    final reports = view.providedAttributeIds.map((id) => id.value).join(', ');
    return '${view.storedNow ? 'Registered' : 'Already registered'} '
        '${view.platform.value} ${view.appBuildOrdinal}: $reports.';
  }
}

/// Reads the target's audiences and what one of them needs to run.
class _ReadinessCommand extends _ExperimentSubcommand {
  _ReadinessCommand(super.context);

  @override
  String get name => 'readiness';

  @override
  String get description =>
      'List this target\'s audiences, and what one of them needs to run.';

  @override
  ExperimentAuthoringOperationV1? get operation =>
      ExperimentAuthoringOperationV1.readExperimentReadiness;

  @override
  void addOptions(ArgParser parser) => parser
    ..addOption(
      'page-size',
      help: 'Audiences to read, 1..100. Defaults to 100.',
    )
    ..addOption('page-cursor', help: 'Continue a previous page.')
    ..addOption('audience-id', help: 'Audience to assess.')
    ..addOption('audience-revision-id', help: 'Exact revision to assess.')
    ..addOption('audience-digest', help: 'Semantic digest of that revision.');

  @override
  Map<String, Object?>? buildPayload() {
    final pageSize = optionalPositiveInt('page-size');
    if (pageSize == null && argResults?['page-size'] != null) return null;
    final audienceId = argResults?['audience-id'] as String?;
    final revisionId = argResults?['audience-revision-id'] as String?;
    final digest = argResults?['audience-digest'] as String?;
    final named = <String?>[audienceId, revisionId, digest];
    // Half a reference names no revision of any audience, and completing it
    // from elsewhere is the guess this refuses to make.
    if (named.any((value) => value != null) &&
        named.any((value) => value == null)) {
      _stderr.writeln(
        'Naming an audience needs --audience-id, --audience-revision-id and '
        '--audience-digest together.',
      );
      return null;
    }
    return {
      if (audienceId != null)
        'audienceRef': {
          'policyId': audienceId,
          'revisionId': revisionId,
          'semanticDigest': digest,
        },
      if (argResults?['page-cursor'] case final String cursor)
        'pageCursor': cursor,
      'pageSize': pageSize ?? 100,
    };
  }

  @override
  String renderAccepted(ExperimentAuthoringAcceptedV1 accepted) {
    final view = accepted.response as ExperimentReadinessViewV1;
    final lines = <String>[
      for (final option in view.audiences)
        '${option.reference.revisionId.value}  ${option.label} '
            '(revision ${option.revisionOrdinal})',
    ];
    if (lines.isEmpty) lines.add('No audiences at this target.');
    if (view.readiness case final readiness?) {
      lines
        ..add('')
        ..addAll(_readinessLines(readiness));
    }
    return lines.join('\n');
  }

  List<String> _readinessLines(ExperimentAudienceReadinessV1 readiness) {
    if (readiness.contextSchemaRef == null) {
      return const [
        'Ready to activate. This audience compares nothing an app build '
            'reports.',
      ];
    }
    final builds = readiness.registeredBuilds
        .map((build) => '${build.platform.value} ${build.appBuildOrdinal}')
        .join(', ');
    return <String>[
      readiness.activationBlocked
          ? 'Cannot be activated yet.'
          : 'Ready to activate.',
      'Registered builds: ${builds.isEmpty ? 'none' : builds}',
      for (final attribute in readiness.attributes)
        '  ${attribute.assignmentAttributeId.value}: '
            '${_supplyOf(readiness, attribute)}',
    ];
  }

  String _supplyOf(
    ExperimentAudienceReadinessV1 readiness,
    ExperimentAttributeReadinessV1 attribute,
  ) => switch (attribute.supply) {
    ExperimentAttributeSupplyV1.registered => 'reported by every build',
    ExperimentAttributeSupplyV1.appDeclaredValue =>
      'supplied by your app while it runs, so an experiment cannot compare '
          'it yet',
    ExperimentAttributeSupplyV1.missingRegistration => switch (readiness
        .buildsMissing(attribute)) {
      final missing when missing.isEmpty => 'reported by no registered build',
      final missing =>
        'not reported by ${missing.map((build) => '${build.platform.value} '
            '${build.appBuildOrdinal}').join(', ')}',
    },
  };
}

/// Archives or restores an experiment.
class _ArchiveCommand extends _ExperimentSubcommand {
  _ArchiveCommand(super.context);

  @override
  String get name => 'archive';

  @override
  String get description => 'Archive or restore an experiment.';

  @override
  ExperimentAuthoringOperationV1? get operation =>
      ExperimentAuthoringOperationV1.setExperimentArchived;

  @override
  void addOptions(ArgParser parser) => parser
    ..addOption('experiment-id', help: 'Experiment identity (required).')
    ..addOption(
      'expected-control-plane-ordinal',
      help: 'Control-plane ordinal this change expects (required).',
    )
    ..addFlag(
      'archived',
      defaultsTo: true,
      help: 'Archive the experiment. Pass --no-archived to restore it.',
    );

  @override
  Map<String, Object?>? buildPayload() {
    final experimentId = requireOption('experiment-id');
    final ordinal = requirePositiveInt('expected-control-plane-ordinal');
    if (experimentId == null || ordinal == null) return null;
    return {
      'archived': argResults?['archived'] as bool? ?? true,
      'expectedControlPlaneOrdinal': ordinal,
      'experimentId': experimentId,
    };
  }

  @override
  String renderAccepted(ExperimentAuthoringAcceptedV1 accepted) =>
      (argResults?['archived'] as bool? ?? true)
      ? 'Archived experiment.'
      : 'Restored experiment.';
}

TargetCoordinate _targetOf(LifecycleContext context) => TargetCoordinate(
  organizationId: OrganizationId(context.organizationId),
  appId: ApplicationId(context.appId),
  environmentTargetId: EnvironmentTargetId(context.environmentTargetId),
  namedEnvironmentId: NamedEnvironmentId(context.namedEnvironmentId),
  runtimePlane: context.runtimePlane.wireName == 'live'
      ? RuntimePlane.live
      : RuntimePlane.sandbox,
);

/// A service fault exits 2; anything the operator can act on exits 1.
int _refusalExitCode(ExperimentAuthoringRefusalV1 refusal) =>
    refusal.retryable ||
        refusal.code == ExperimentAuthoringRefusalCodeV1.integrityFailure
    ? 2
    : 1;

Object? _drainJson(Object? value) => switch (value) {
  final ExperimentDiscovery discovery => {
    'actionAvailability': [
      for (final availability in discovery.actionAvailability)
        availability.toJson(),
    ],
    'appLabel': discovery.appLabel,
    'environmentLabel': discovery.environmentLabel,
    'metricCapabilities': [
      for (final capability in discovery.metricCapabilities)
        capability.toJson(),
    ],
    'namedEnvironments': [
      for (final option in discovery.namedEnvironments) option.toJson(),
    ],
    'organizationLabel': discovery.organizationLabel,
    'runtimePlanes': [
      for (final option in discovery.runtimePlanes) option.toJson(),
    ],
    'surfaceCapabilities': [
      for (final capability in discovery.surfaceCapabilities)
        capability.toJson(),
    ],
    'target': discovery.target.toJson(),
  },
  final List<ExperimentListEntryV1> entries => [
    for (final entry in entries) entry.toJson(),
  ],
  _ => value,
};

String _newIdentity(String prefix) => newExperimentIdentity(prefix);

/// Produces the serving records a target lacks, or counts what is missing.
class _RebuildServingRecordsCommand extends _ExperimentSubcommand
    implements LiveGuardedCommand {
  _RebuildServingRecordsCommand(super.context);

  @override
  String get name => 'rebuild-serving-records';

  @override
  String get description =>
      'Produce the serving records this target lacks and report what is '
      'left. Exits non-zero while any experiment is still missing one.';

  @override
  ExperimentAuthoringOperationV1? get operation => null;

  @override
  void addOptions(ArgParser parser) {
    parser.addFlag(
      'readiness-only',
      negatable: false,
      help:
          'Inspect what is missing without producing anything. This does not '
          're-prove sources, so only the full rebuild is the deploy readiness '
          'gate.',
    );
  }

  @override
  Map<String, Object?>? buildPayload() => const {};

  bool get _readinessOnly => argResults?['readiness-only'] as bool? ?? false;

  @override
  bool get changesLiveState => !_readinessOnly;

  @override
  Future<int>? operatorCall({
    required RestageApi transport,
    required TargetCoordinate target,
    required bool asJson,
  }) => _run(transport: transport, target: target, asJson: asJson);

  Future<int> _run({
    required RestageApi transport,
    required TargetCoordinate target,
    required bool asJson,
  }) async {
    final response = await transport.call(
      'experimentActivation',
      'rebuildServingRecords',
      <String, dynamic>{
        'organizationId': target.organizationId.value,
        'appId': target.appId.value,
        'environmentTargetId': target.environmentTargetId.value,
        'namedEnvironmentId': target.namedEnvironmentId.value,
        'runtimePlane': target.runtimePlane.wireName,
        'readinessOnly': _readinessOnly,
      },
    );
    final Map<String, Object?> readiness;
    try {
      readiness = jsonDecode(response as String) as Map<String, Object?>;
    } on Object {
      _stderr.writeln('The service returned an invalid readiness report.');
      return 2;
    }
    if (asJson) {
      _stdout.writeln(jsonEncode(readiness));
    } else {
      _stdout.writeln(_render(readiness));
    }
    return (readiness['ready'] as bool? ?? false) ? 0 : 1;
  }

  String _render(Map<String, Object?> readiness) {
    final surfaces = (readiness['surfaces'] as List<Object?>? ?? const [])
        .cast<Map<String, Object?>>();
    final unrecoverable =
        (readiness['unrecoverable'] as List<Object?>? ?? const [])
            .cast<Map<String, Object?>>();
    // A readiness read answers whether records are present, never whether
    // their sources still say what the records say. Saying only "ready" would
    // read as the stronger verdict it is not.
    final reproven = readiness['sourcesReproven'] == true;
    final present = readiness['ready'] == true;
    var nominated = 0;
    for (final surface in surfaces) {
      nominated += surface['nominated']! as int;
    }
    final lines = <String>[
      if (reproven)
        present
            ? 'Ready: every nominated experiment holds a current record and '
                  'its sources re-prove it.'
            : 'Not ready: see what is missing or unprovable below.'
      else
        '${readiness['missing']} of $nominated nominated experiments hold no '
            'current record. Records present; sources not re-proven — run '
            'rebuild.',
      'Produced ${readiness['produced']}, superseded '
          '${readiness['superseded'] ?? 0}.',
      for (final entry in unrecoverable)
        '  Unprovable: ${entry['experimentId']} (${entry['reason']}).',
    ];
    for (final surface in surfaces) {
      lines.add(
        '  ${surface['surfaceType']}/${surface['surfaceSlug']}: '
        '${surface['nominated']} nominated, ${surface['missing']} missing, '
        '${surface['produced']} produced, '
        '${surface['superseded'] ?? 0} superseded.',
      );
    }
    return lines.join('\n');
  }
}
