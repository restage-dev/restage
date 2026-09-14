import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/api/experiment_api.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/commands/experimental_gate.dart';
import 'package:restage_cli/src/commands/lifecycle_support.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
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
      _ListCommand.new,
      _ReadCommand.new,
      _ResultsCommand.new,
      _ArchiveCommand.new,
    ]) {
      addSubcommand(build(context));
    }
  }

  final Map<String, String>? _environment;

  @override
  String get name => 'experiment';

  @override
  String get description =>
      'Author, review, activate, and read experiments at one target.';

  @override
  bool get hidden => !enabled;

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
  bool get changesLiveState => false;

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
  Future<int> run() async {
    final owner = parent;
    if (owner is ExperimentCommand && !owner.enabled) {
      _stderr.writeln(experimentalCommandRefusal('experiment $name'));
      return 1;
    }

    final asJson = argResults?['json'] as bool? ?? false;
    final context = await loadLifecycleContext(
      argResults: argResults,
      interactive: _interactive,
      stderr: _stderr,
      credentialStore: _credentialStore,
      httpClient: _httpClient,
    );
    if (context == null) return 1;

    final payload = buildPayload();
    if (payload == null && operation != null) return 1;

    final target = _targetOf(context);
    if (changesLiveState && !await _confirmLiveExperimentChange(target)) {
      return 1;
    }

    final RestageApi transport;
    try {
      transport = RestageApi(
        endpoint: context.apiEndpoint,
        httpClient: _httpClient,
        credential: context.credential,
      );
    } on InsecureEndpointException catch (error) {
      _stderr.writeln(error);
      return 1;
    }

    final api = ExperimentApi(transport);

    // Built before the send, so a bad selector is reported as the operator's
    // to fix rather than blamed on the service.
    ExperimentAuthoringRequestV1? request;
    if (operation != null) {
      try {
        final resolvedOperation = operation!;
        final resolvedPayload = payload!;
        final idempotencyKey = resolvedOperation.requiresIdempotencyKey
            ? (argResults?['idempotency-key'] as String?) ??
                  _newIdentity('idempotency')
            : null;
        final correlationId = idempotencyKey == null
            ? _newIdentity('correlation')
            : experimentRetryCorrelationId(
                operation: resolvedOperation,
                payload: resolvedPayload,
                idempotencyKey: idempotencyKey,
              );
        request = experimentRequest(
          operation: resolvedOperation,
          correlationId: correlationId,
          payload: resolvedPayload,
          idempotencyKey: idempotencyKey,
        );
      } on CanonicalFormatException catch (error) {
        _stderr.writeln(error.message);
        if (_httpClient == null) transport.close();
        return 1;
      }
    }

    try {
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
    } finally {
      if (_httpClient == null) transport.close();
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

  String _refusalLine(ExperimentAuthoringRefusedV1 refused) =>
      'Refused ${refused.operation.wireName}: '
      '${refused.refusal.code.wireName}'
      '${refused.refusal.retryable ? " (retryable)" : ""}.';

  /// Consent to change a running experiment on the live plane.
  ///
  /// Distinct from `confirmDestructive`, which guards destructive surface
  /// lifecycle operations and refuses `--yes` outright. Activation is not
  /// destructive, so an explicit `--yes` is consent here. `--non-interactive`
  /// says how to prompt, not that the operator agreed, so it fails closed.
  Future<bool> _confirmLiveExperimentChange(TargetCoordinate target) async {
    if (target.runtimePlane != RuntimePlane.live) return true;
    if (globalResults?['yes'] as bool? ?? false) return true;
    if (!_interactive.isInteractive) {
      _stderr.writeln(
        'This changes live experiment state. Run interactively, or pass --yes.',
      );
      return false;
    }
    return _interactive.confirm('Change live experiment state?');
  }

  /// Reads a required option, or prints a precise error and returns null.
  String? requireOption(String option) {
    final value = (argResults?[option] as String?)?.trim();
    if (value != null && value.isNotEmpty) return value;
    _stderr.writeln('Required: --$option <value>.');
    return null;
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

  @override
  String get name => 'discover';

  @override
  String get description =>
      'Discover authoring capability, surfaces, and metrics at one target.';

  @override
  ExperimentAuthoringOperationV1? get operation => null;

  @override
  Map<String, Object?>? buildPayload() => null;

  @override
  Future<ExperimentPageDrain<Object?>>? drain(
    ExperimentApi api,
    TargetCoordinate target,
    String correlationId,
  ) => api.discoverEveryPage(target: target, correlationId: correlationId);

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
    return 'Validated draft: ${view.issues.length} issues.';
  }
}

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
class _ActivateCommand extends _ExperimentSubcommand {
  _ActivateCommand(super.context);

  @override
  String get name => 'activate';

  @override
  String get description => 'Activate a reviewed draft.';

  @override
  ExperimentAuthoringOperationV1? get operation =>
      ExperimentAuthoringOperationV1.activateDraft;

  @override
  bool get changesLiveState => true;

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
abstract class _TransitionCommand extends _ExperimentSubcommand {
  _TransitionCommand(super.context);

  @override
  bool get changesLiveState => true;

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

/// Lists experiments and drafts at the selected target.
class _ListCommand extends _ExperimentSubcommand {
  _ListCommand(super.context);

  @override
  String get name => 'list';

  @override
  String get description =>
      'List experiments and drafts at the selected target.';

  @override
  ExperimentAuthoringOperationV1? get operation => null;

  @override
  Map<String, Object?>? buildPayload() => null;

  @override
  Future<ExperimentPageDrain<Object?>>? drain(
    ExperimentApi api,
    TargetCoordinate target,
    String correlationId,
  ) => api.listEveryPage(target: target, correlationId: correlationId);

  @override
  String renderDrained(Object? value) {
    final entries = value! as List<ExperimentListEntryV1>;
    if (entries.isEmpty) return 'No experiments at this target.';
    return entries.map((entry) => entry.experimentId.value).join('\n');
  }
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

/// Reads one experiment's results.
class _ResultsCommand extends _ExperimentSubcommand {
  _ResultsCommand(super.context);

  @override
  String get name => 'results';

  @override
  String get description => "Read one experiment's results.";

  @override
  ExperimentAuthoringOperationV1? get operation =>
      ExperimentAuthoringOperationV1.readExperimentResults;

  @override
  void addOptions(ArgParser parser) => parser
    ..addOption('experiment-id', help: 'Experiment identity (required).')
    ..addOption(
      'activation-ordinal',
      help: 'Activation ordinal the results belong to (required).',
    )
    ..addOption('result-digest', help: 'Result digest to read (required).');

  @override
  Map<String, Object?>? buildPayload() {
    final experimentId = requireOption('experiment-id');
    final activationOrdinal = requirePositiveInt('activation-ordinal');
    final resultDigest = requireOption('result-digest');
    if (experimentId == null ||
        activationOrdinal == null ||
        resultDigest == null) {
      return null;
    }
    return {
      'activationOrdinal': activationOrdinal,
      'experimentId': experimentId,
      'resultDigest': resultDigest,
    };
  }

  @override
  String renderAccepted(ExperimentAuthoringAcceptedV1 accepted) =>
      'Read results.';
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

final _random = Random.secure();

String _newIdentity(String prefix) {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '$prefix-$hex';
}
