import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/delivery_management_api.dart';
import 'package:restage_cli/src/api/surface_routing_api.dart';
import 'package:restage_cli/src/api/typed_error_renderer.dart';
import 'package:restage_cli/src/commands/authed.dart';
import 'package:restage_cli/src/commands/lifecycle_support.dart';
import 'package:restage_cli/src/commands/live_guard.dart';
import 'package:restage_cli/src/commands/measurement_page_command.dart'
    show targetCoordinateOf;
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/delivery/policy_review.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_cli/src/operations/operation.dart';
import 'package:restage_cli/src/output/held_count.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

typedef _RoutingContext = CommandIo;

/// Manages ordered audience-routing rules and defaults for any surface type.
/// Reads preserve policy bytes. Writes use whole-policy requests and retained
/// server reviews; audience mutations use their own route.
class SurfaceRoutingCommand extends Command<int> {
  /// Construct the routing command group.
  SurfaceRoutingCommand({
    required StringSink stdout,
    required StringSink stderr,
    required Interactive interactive,
    FileCredentialStore? credentialStore,
    http.Client? httpClient,
  }) {
    final context = _RoutingContext(
      stdout: stdout,
      stderr: stderr,
      interactive: interactive,
      credentialStore: credentialStore,
      httpClient: httpClient,
    );
    addSubcommand(_ListAudiencesCommand(context));
    addSubcommand(_AudienceUsageCommand(context));
    addSubcommand(_ReadCommand(context));
    addSubcommand(_ReadDeliveryDiagnosticsCommand(context));
    addSubcommand(_ReadDeliveryFlowCommand(context));
    addSubcommand(_ReadRevisionCommand(context));
    addSubcommand(_PreviewCommand(context));
    addSubcommand(_ReviewCommand(context));
    addSubcommand(_ReviewRollbackCommand(context));
    addSubcommand(_PublishCommand(context));
    addSubcommand(_RollbackCommand(context));
  }

  @override
  String get name => 'routing';

  @override
  String get description =>
      'Read, preview, publish, and roll back the routing document that '
      'decides which published version a request receives.';
}

/// Shared plumbing for one routing operation.
abstract class _RoutingSubcommand extends Command<int> {
  _RoutingSubcommand(this._io) {
    addLifecycleOptions(
      argParser,
      withType: needsSurface,
      withReason: false,
      withContractVersion: needsSurface,
    );
    if (paged) {
      argParser
        ..addOption(
          'page-size',
          help: 'Rows per page, 1 to 200. Defaults to 50.',
        )
        ..addOption('cursor', help: 'Continue from a previous page cursor.')
        ..addFlag(
          'all-pages',
          negatable: false,
          help: 'Follow every cursor and print the accumulated rows.',
        );
    }
    if (acceptsOperationId) {
      argParser.addOption(
        'operation-id',
        help:
            'Retry identity for this write, as a version 4 UUID. A repeat '
            'with the same id and the same content is the same attempt. '
            'Generated when omitted.',
      );
    }
    argParser.addFlag(
      'json',
      negatable: false,
      help: 'Print the exact result as JSON.',
    );
    addOptions(argParser);
  }

  final CommandIo _io;

  StringSink get _stdout => _io.stdout;

  StringSink get _stderr => _io.stderr;

  /// Whether this operation addresses one surface.
  bool get needsSurface => true;

  @override
  String get invocation => needsSurface
      ? 'restage surface routing $name <slug> --type <type> [arguments]'
      : 'restage surface routing $name [arguments]';

  /// Whether this operation reads a cursor-paged list.
  bool get paged => false;

  /// Whether this operation changes stored routing state.
  bool get writes => false;

  /// Whether this operation submits a replayable publication.
  bool get acceptsOperationId => false;

  /// Registers the selectors this operation needs beyond the shared set.
  void addOptions(ArgParser parser) {}

  /// The question asked when the server holds the call for a fit confirmation.
  String get fitQuestion => 'Publish anyway?';

  /// Runs the operation. Returns the process exit code.
  Future<int> invoke(SurfaceRoutingApi api, _RoutingTarget target);

  @override
  Future<int> run() async {
    return runAuthed(
      _io,
      argResults,
      OperationScope.target,
      (ctx) async {
        final context = ctx.target!;
        String? surfaceType;
        String? surfaceSlug;
        if (needsSurface) {
          final slug = resolveSingleSlug(
            argResults: argResults,
            stderr: _stderr,
          );
          if (slug == null) return 1;
          final type = resolveSurfaceTypeArg(
            argResults: argResults,
            fixedType: null,
            stderr: _stderr,
          );
          if (type == null) return 1;
          surfaceSlug = slug;
          surfaceType = type.wireName;
        }

        final int? contractVersion;
        if (needsSurface && argResults?['contract-version'] != null) {
          contractVersion = requirePositiveInt('contract-version');
          if (contractVersion == null) return 1;
        } else {
          contractVersion = null;
        }

        // The environment target id is the routing endpoint's environment: it
        // addresses one concrete target, not the named environment above it.
        final target = _RoutingTarget(
          projectSlug: context.project,
          appSlug: context.app,
          organizationId: context.organizationId,
          environmentId: context.environmentTargetId,
          surfaceType: surfaceType,
          surfaceSlug: surfaceSlug,
          contractVersion: contractVersion,
          coordinate: targetCoordinateOf(context),
        );

        if (this is LiveGuardedCommand &&
            !await confirmLiveChange(
              command: this,
              interactive: _io.interactive,
              stdout: _stdout,
              stderr: _stderr,
              runtimePlane: context.runtimePlane,
              impactLine:
                  'Routing $name for ${surfaceType ?? 'the app'} '
                  '"${surfaceSlug ?? context.app}" in ${context.environment} '
                  '(live).',
            )) {
          return 1;
        }

        try {
          return await invoke(SurfaceRoutingApi(ctx.api), target);
        } on RoutingDocumentBytesException catch (error) {
          _stderr.writeln(error);
          return 1;
        } on DeliveryManagementResponseException catch (error) {
          _stderr.writeln(error);
          return 2;
        } on RestageApiException catch (error) {
          return _reportApiFailure(error);
        } on CanonicalFormatException catch (error) {
          _stderr.writeln(
            'The service returned an invalid result: ${error.message}',
          );
          return 2;
        } on FormatException catch (error) {
          _stderr.writeln(
            'The service returned an invalid result: ${error.message}',
          );
          return 2;
        }
      },
      command: this,
      fitQuestion: fitQuestion,
    );
  }

  /// Reports a failed call. Routing's own typed refusals are surfaced in the
  /// service's terms; everything else falls through to the shared renderer.
  int _reportApiFailure(RestageApiException error) {
    switch (decodeSurfaceRoutingException(error.body)) {
      case SurfaceRoutingConflict(
        :final expectedRevisionOrdinal,
        :final actualRevisionOrdinal,
      ):
        _stderr.writeln(
          'The stored routing document has moved on. This write expected '
          '${expectedRevisionOrdinal ?? "no revision"} and the stored '
          'revision is ${actualRevisionOrdinal ?? "none"}. Re-read the '
          'document, review the difference, and retry.',
        );
        return 1;
      case SurfaceRoutingRejected(:final reason):
        _stderr.writeln('The routing service refused the request: $reason.');
        return 1;
      case null:
        final outcome = renderApiError(error);
        _stderr.writeln(outcome.message);
        return outcome.exitCode;
    }
  }

  /// Reads a required option, or prints a precise error and returns null.
  String? requireOption(String option) {
    final value = argResults?[option] as String?;
    if (value == null || value.isEmpty) {
      _stderr.writeln('--$option is required.');
      return null;
    }
    return value;
  }

  /// Reads a required positive integer option, or prints a precise error.
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

  /// Reads an optional positive integer option. Returns null when absent;
  /// [invalid] is set when the value was present and unusable.
  int? optionalPositiveInt(String option, {required void Function() invalid}) {
    final raw = argResults?[option] as String?;
    if (raw == null || raw.isEmpty) return null;
    final value = int.tryParse(raw);
    if (value == null || value <= 0) {
      _stderr.writeln('--$option must be a positive integer.');
      invalid();
      return null;
    }
    return value;
  }

  /// Reads the retry identity, generating a version 4 UUID when omitted.
  /// Returns null after a precise error when the supplied value is not one.
  String? resolveOperationId() {
    final supplied = argResults?['operation-id'] as String?;
    if (supplied == null || supplied.isEmpty) return newOperationId();
    if (!isCanonicalOperationId(supplied)) {
      _stderr.writeln('--operation-id must be a canonical version 4 UUID.');
      return null;
    }
    return supplied;
  }

  /// Reads the requested page size, or null to accept the service default.
  int? resolvePageSize({required void Function() invalid}) {
    final raw = argResults?['page-size'] as String?;
    if (raw == null || raw.isEmpty) return null;
    final value = int.tryParse(raw);
    if (value == null || value < 1 || value > 200) {
      _stderr.writeln('--page-size must be between 1 and 200.');
      invalid();
      return null;
    }
    return value;
  }

  /// Reads the canonical bytes of one file, or null after a precise error.
  Future<Uint8List?> readBytes(String option) async {
    final path = requireOption(option);
    if (path == null) return null;
    final file = File(path);
    if (!file.existsSync()) {
      _stderr.writeln('No file at `$path` for --$option.');
      return null;
    }
    try {
      final length = await file.length();
      if (length == 0) {
        writeError(
          'The --$option file must be between 1 and $kMaximumRoutingResponseBytes bytes.',
        );
        return null;
      }
      if (length > kMaximumRoutingResponseBytes) {
        writeError(
          'The --$option file exceeds the delivery response byte budget.',
        );
        return null;
      }
      return await file.readAsBytes();
    } on FileSystemException catch (error) {
      _stderr.writeln('Could not read `$path`: ${error.message}');
      return null;
    }
  }

  /// Reads one strict public authoring document without sending malformed input.
  Future<T?> readDocument<T>(
    String option,
    T Function(List<int>) decode,
  ) async {
    final bytes = await readBytes(option);
    if (bytes == null) return null;
    try {
      return decode(bytes);
    } on CanonicalFormatException catch (error) {
      writeError('Invalid --$option: ${error.message}');
      return null;
    } on FormatException catch (error) {
      writeError('Invalid --$option: ${error.message}');
      return null;
    }
  }

  bool requireScope(DeliveryPolicyScopeV1 scope, _RoutingTarget target) {
    try {
      requireSurfaceRoutingScope(
        scope,
        organizationId: target.organizationId,
        environmentId: target.environmentId,
        contractVersion: target.contractVersion,
        expectedTarget: target.coordinate,
      );
      return true;
    } on FormatException catch (error) {
      writeError(error.message.toString());
      return false;
    }
  }

  Future<DeliveryPolicyPublishRequestV1?> reviewedPublish(
    DeliveryPolicyReviewV1 review,
  ) async {
    try {
      return await confirmDeliveryPolicyPublish(
        review: review,
        interactive: _io.interactive,
        stdout: _stdout,
        reviewedDigest: argResults?['reviewed-digest'] as String?,
        operationId: argResults?['operation-id'] as String?,
      );
    } on DeliveryPolicyReviewRequired {
      writeError(
        'Supply --reviewed-digest ${review.digest.hex} after reviewing every warning.',
      );
      return null;
    } on FormatException catch (error) {
      writeError(error.message.toString());
      return null;
    }
  }

  Future<int> reportReview(DeliveryPolicyReviewV1 review) async {
    final out = argResults?['out'] as String?;
    if (out != null && out.isNotEmpty) {
      await File(out).writeAsBytes(review.canonicalBytes);
    }
    report(review.toJson(), [formatDeliveryPolicyReview(review)]);
    return review.refusalCodes.isEmpty ? 0 : 1;
  }

  /// Whether `--all-pages` was requested.
  bool get followAllPages => argResults?['all-pages'] as bool? ?? false;

  /// Whether `--json` was requested.
  bool get asJson => argResults?['json'] as bool? ?? false;

  /// Writes [value] as JSON, or [lines] for a human reader.
  int report(Map<String, dynamic> value, List<String> lines) {
    if (asJson) {
      _stdout.writeln(jsonEncode(value));
    } else {
      for (final line in lines) {
        _stdout.writeln(line);
      }
    }
    return 0;
  }

  /// Writes one line to stderr.
  void writeError(String message) => _stderr.writeln(message);
}

/// The complete target every routing call carries.
class _RoutingTarget {
  const _RoutingTarget({
    required this.projectSlug,
    required this.appSlug,
    required this.organizationId,
    required this.environmentId,
    required this.surfaceType,
    required this.surfaceSlug,
    required this.contractVersion,
    required this.coordinate,
  });

  final String projectSlug;
  final String appSlug;
  final int organizationId;
  final int environmentId;
  final String? surfaceType;
  final String? surfaceSlug;
  final int? contractVersion;
  final TargetCoordinate coordinate;

  String get requiredSurfaceType => surfaceType!;
  String get requiredSurfaceSlug => surfaceSlug!;
}

class _DeliveryDiagnosticsWindow {
  const _DeliveryDiagnosticsWindow({
    required this.startDayUtc,
    required this.endDayExclusiveUtc,
  });

  factory _DeliveryDiagnosticsWindow.fromUtcDates({
    required String startDate,
    required String endDateExclusive,
  }) {
    final startDayUtc = parseDeliveryDiagnosticsUtcDate(startDate);
    final endDayExclusiveUtc = parseDeliveryDiagnosticsUtcDate(
      endDateExclusive,
    );
    validateDeliveryDiagnosticsUtcWindow(
      windowStartDayUtc: startDayUtc,
      windowEndDayExclusiveUtc: endDayExclusiveUtc,
    );
    return _DeliveryDiagnosticsWindow(
      startDayUtc: startDayUtc,
      endDayExclusiveUtc: endDayExclusiveUtc,
    );
  }

  final int startDayUtc;
  final int endDayExclusiveUtc;
}

class _ListAudiencesCommand extends _RoutingSubcommand {
  _ListAudiencesCommand(super.context);

  @override
  String get name => 'list-audiences';

  @override
  String get description =>
      'List the sealed audience revisions routing rules can reference.';

  @override
  bool get needsSurface => false;

  @override
  bool get paged => true;

  @override
  Future<int> invoke(SurfaceRoutingApi api, _RoutingTarget target) async {
    var invalid = false;
    final pageSize = resolvePageSize(invalid: () => invalid = true);
    if (invalid) return 1;

    final collected = <RoutingAudience>[];
    var cursor = argResults?['cursor'] as String?;
    RoutingAudiencePage page;
    do {
      page = await api.listAudiences(
        projectSlug: target.projectSlug,
        appSlug: target.appSlug,
        environmentId: target.environmentId,
        organizationId: target.organizationId,
        pageSize: pageSize ?? 50,
        cursor: cursor,
      );
      collected.addAll(page.audiences);
      cursor = page.nextCursor;
    } while (followAllPages && !page.lastPage && cursor != null);

    return report(
      {
        'audiences': [for (final a in collected) a.toJson()],
        'lastPage': page.lastPage,
        'nextCursor': page.nextCursor,
      },
      [
        for (final audience in collected)
          '${audience.authorityId}\t${audience.revisionId}\t'
              '${audience.revisionOrdinal}\t${audience.label}',
        if (collected.isEmpty) 'No audiences at this target.',
        if (!page.lastPage && page.nextCursor != null)
          'More rows: pass --cursor ${page.nextCursor}.',
      ],
    );
  }
}

class _AudienceUsageCommand extends _RoutingSubcommand {
  _AudienceUsageCommand(super.context);

  @override
  String get name => 'audience-usage';

  @override
  String get description =>
      'List the experiments and routing documents that reference one '
      'audience revision.';

  @override
  bool get needsSurface => false;

  @override
  bool get paged => true;

  @override
  void addOptions(ArgParser parser) => parser.addOption(
    'audience-revision-id',
    help: 'The exact sealed audience revision to report on (required).',
  );

  @override
  Future<int> invoke(SurfaceRoutingApi api, _RoutingTarget target) async {
    final revisionId = requireOption('audience-revision-id');
    if (revisionId == null) return 1;
    var invalid = false;
    final pageSize = resolvePageSize(invalid: () => invalid = true);
    if (invalid) return 1;

    final experiments = <RoutingExperimentConsumer>[];
    final routing = <RoutingAudienceConsumer>[];
    var cursor = argResults?['cursor'] as String?;
    RoutingAudienceUsage usage;
    do {
      usage = await api.listAudienceUsage(
        projectSlug: target.projectSlug,
        appSlug: target.appSlug,
        environmentId: target.environmentId,
        organizationId: target.organizationId,
        audienceRevisionId: revisionId,
        pageSize: pageSize ?? 50,
        cursor: cursor,
      );
      experiments.addAll(usage.experiments);
      routing.addAll(usage.routing);
      cursor = usage.nextCursor;
    } while (followAllPages && !usage.lastPage && cursor != null);

    return report(
      {
        'experiments': [for (final e in experiments) e.toJson()],
        'routing': [for (final r in routing) r.toJson()],
        'lastPage': usage.lastPage,
        'nextCursor': usage.nextCursor,
      },
      [
        for (final consumer in experiments)
          'experiment\t${consumer.ownerAuthorityKind}\t'
              '${consumer.ownerAuthorityId}\t${consumer.ownerRevisionId}\t'
              '${consumer.lifecycle?.name ?? "unknown"}',
        for (final consumer in routing)
          'routing\t${consumer.surfaceType} ${consumer.surfaceSlug}\t'
              'revision ${consumer.revisionOrdinal}\t'
              '${consumer.routeIds.join(",")}\t'
              '${consumer.lifecycle?.name ?? "unknown"}',
        if (experiments.isEmpty && routing.isEmpty)
          'Nothing references this audience revision.',
        if (!usage.lastPage && usage.nextCursor != null)
          'More rows: pass --cursor ${usage.nextCursor}.',
      ],
    );
  }
}

class _ReadCommand extends _RoutingSubcommand {
  _ReadCommand(super.context);

  @override
  String get name => 'read';

  @override
  String get description =>
      'Read the stored routing document and the revision it sits at.';

  @override
  void addOptions(ArgParser parser) => parser.addOption(
    'out',
    help: 'Write the canonical document bytes to this file.',
  );

  @override
  Future<int> invoke(SurfaceRoutingApi api, _RoutingTarget target) async {
    final read = await api.readRouting(
      projectSlug: target.projectSlug,
      appSlug: target.appSlug,
      surfaceType: target.requiredSurfaceType,
      surfaceSlug: target.requiredSurfaceSlug,
      environmentId: target.environmentId,
      organizationId: target.organizationId,
      contractVersion: target.contractVersion,
    );

    final out = argResults?['out'] as String?;
    final bytes = read.documentBytes;
    if (out != null && out.isNotEmpty && bytes != null) {
      await File(out).writeAsBytes(bytes);
    }

    return report(read.toJson(), [
      if (read.empty)
        'No routing document at this target. Publish with '
            '--expect-no-revision.'
      else
        'Revision ${read.revisionOrdinal}, ${bytes?.length ?? 0} bytes.',
      if (out != null && out.isNotEmpty && bytes != null) 'Written to $out.',
    ]);
  }
}

class _ReadDeliveryDiagnosticsCommand extends _RoutingSubcommand {
  _ReadDeliveryDiagnosticsCommand(super.context);

  @override
  String get name => 'delivery-diagnostics';

  @override
  String get description =>
      'Read observed served-default and recorded-refusal diagnostics for one '
      'whole UTC-day window.';

  @override
  void addOptions(ArgParser parser) => parser
    ..addOption(
      'start-date',
      help: 'First UTC date included, as YYYY-MM-DD (required).',
    )
    ..addOption(
      'end-date-exclusive',
      help:
          'First UTC date excluded, as YYYY-MM-DD (required). The window may '
          'span at most the retained Measurement period.',
    );

  @override
  Future<int> invoke(SurfaceRoutingApi api, _RoutingTarget target) async {
    final startDate = requireOption('start-date');
    final endDateExclusive = requireOption('end-date-exclusive');
    if (startDate == null || endDateExclusive == null) return 1;

    final _DeliveryDiagnosticsWindow window;
    try {
      window = _DeliveryDiagnosticsWindow.fromUtcDates(
        startDate: startDate,
        endDateExclusive: endDateExclusive,
      );
    } on FormatException catch (error) {
      writeError('Invalid UTC date window: ${error.message}');
      return 1;
    }

    final diagnostics = await api.readDeliveryDiagnostics(
      projectSlug: target.projectSlug,
      appSlug: target.appSlug,
      surfaceType: target.requiredSurfaceType,
      surfaceSlug: target.requiredSurfaceSlug,
      environmentId: target.environmentId,
      organizationId: target.organizationId,
      windowStartDayUtc: window.startDayUtc,
      windowEndDayExclusiveUtc: window.endDayExclusiveUtc,
      contractVersion: target.contractVersion,
    );
    return report(
      diagnostics.toJson(),
      _renderDeliveryDiagnostics(diagnostics),
    );
  }
}

class _ReadDeliveryFlowCommand extends _RoutingSubcommand {
  _ReadDeliveryFlowCommand(super.context);

  @override
  String get name => 'delivery-flow';

  @override
  String get description =>
      'Show who saw which version of a surface over whole UTC days: each '
      'rule\'s views by version, each experiment\'s, then everyone else.';

  @override
  void addOptions(ArgParser parser) => parser
    ..addOption(
      'start-date',
      help: 'First UTC date included, as YYYY-MM-DD (required).',
    )
    ..addOption(
      'end-date-exclusive',
      help:
          'First UTC date excluded, as YYYY-MM-DD (required). The window may '
          'span at most the retained Measurement period.',
    );

  @override
  Future<int> invoke(SurfaceRoutingApi api, _RoutingTarget target) async {
    final startDate = requireOption('start-date');
    final endDateExclusive = requireOption('end-date-exclusive');
    if (startDate == null || endDateExclusive == null) return 1;

    final _DeliveryDiagnosticsWindow window;
    try {
      window = _DeliveryDiagnosticsWindow.fromUtcDates(
        startDate: startDate,
        endDateExclusive: endDateExclusive,
      );
    } on FormatException catch (error) {
      writeError('Invalid UTC date window: ${error.message}');
      return 1;
    }

    final flow = await api.readDeliveryFlow(
      projectSlug: target.projectSlug,
      appSlug: target.appSlug,
      surfaceType: target.requiredSurfaceType,
      surfaceSlug: target.requiredSurfaceSlug,
      environmentId: target.environmentId,
      organizationId: target.organizationId,
      windowStartDayUtc: window.startDayUtc,
      windowEndDayExclusiveUtc: window.endDayExclusiveUtc,
      contractVersion: target.contractVersion,
    );
    return report(flow.toJson(), _renderDeliveryFlow(flow));
  }
}

List<String> _renderDeliveryFlow(DeliveryFlowRead flow) {
  final cells = flow.shownCells;
  return [
    'UTC window: ${_formatUtcDay(flow.windowStartDayUtc)} through '
        '${_formatUtcDay(flow.windowEndDayExclusiveUtc)} (end exclusive).',
    if (flow.cells.isEmpty)
      'No views in this period.'
    else ...[
      for (final cell in cells)
        '${_flowSource(cell)}, v${cell.version}: '
            '${countText(cell.views, approx: cell.approxViews)}',
      _flowTotal(flow),
    ],
  ];
}

String _flowTotal(DeliveryFlowRead flow) {
  final head =
      '${countText(flow.totalViews, approx: flow.approxTotalViews)} views';
  final notRecorded = flow.notRecordedViews;
  final approxNotRecorded = flow.approxNotRecordedViews;
  final anyNotRecorded =
      flow.cells.any((cell) => cell.source == 'notRecorded') &&
      (notRecorded == null || notRecorded > 0);
  return anyNotRecorded
      ? '$head, ${countText(notRecorded, approx: approxNotRecorded)} not recorded'
      : head;
}

String _flowSource(DeliveryFlowCell cell) => switch (cell.source) {
  'rule' => 'Rule ${cell.routeId}',
  'experiment' => switch (cell.experimentLabel) {
    final label? => 'Experiment $label',
    null => 'Unnamed experiment',
  },
  'earlierExperiments' => 'Earlier experiments',
  'everyoneElse' => 'Everyone else',
  _ => 'Not recorded',
};

List<String> _renderDeliveryDiagnostics(
  MeasurementDeliveryDiagnosticsV1 diagnostics,
) => [
  'UTC window: ${_formatUtcDay(diagnostics.windowStartDayUtc)} through '
      '${_formatUtcDay(diagnostics.windowEndDayExclusiveUtc)} (end exclusive).',
  'Disclosure floor: ${diagnostics.disclosureFloor}.',
  'These are observed decision counts.',
  ..._renderDiagnosticsSection(
    label: 'Served default presentations',
    section: diagnostics.servedDefaults,
  ),
  ..._renderDiagnosticsSection(
    label: 'Recorded server refusals',
    section: diagnostics.recordedRefusals,
  ),
];

List<String> _renderDiagnosticsSection({
  required String label,
  required MeasurementDeliveryDiagnosticsSectionV1 section,
}) => [
  '$label (${section.population.wireName}; ${section.coverage.wireName}; '
      '${section.availability.wireName}).',
  '  ${_coverageText(section.coverage)}',
  '  ${_availabilityText(section.availability)}',
  if (section.availability ==
          MeasurementDeliveryDiagnosticsAvailabilityV1.disclosed &&
      section.reasons.isEmpty)
    '  No observed reasons are present in this disclosed population.',
  for (final reason in section.reasons)
    '  ${reason.reason}: ${countText(reason.observedCount)}',
];

String _coverageText(MeasurementDeliveryDiagnosticsCoverageV1 coverage) =>
    switch (coverage) {
      MeasurementDeliveryDiagnosticsCoverageV1.observedAdmittedPresentations =>
        'Coverage: retained, server-admitted presentations only; refusal '
            'requests are outside this population.',
      MeasurementDeliveryDiagnosticsCoverageV1.observedRecordedServerRefusals =>
        'Coverage: server refusal decisions whose aggregate recording '
            'succeeded; this is not a census of all requests.',
    };

String _availabilityText(MeasurementDeliveryDiagnosticsAvailabilityV1 value) =>
    switch (value) {
      MeasurementDeliveryDiagnosticsAvailabilityV1.unavailable =>
        'State: unavailable; no retained observation is available, so no '
            'count is stated.',
      MeasurementDeliveryDiagnosticsAvailabilityV1.held =>
        'State: held; every named count is withheld at the disclosure floor.',
      MeasurementDeliveryDiagnosticsAvailabilityV1.partiallyHeld =>
        'State: partially held; stated counts cleared the disclosure floor and '
            'the other named counts remain held.',
      MeasurementDeliveryDiagnosticsAvailabilityV1.disclosed =>
        'State: disclosed; every named count is stated.',
    };

String _formatUtcDay(int micros) {
  final date = DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true);
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

class _ReadRevisionCommand extends _RoutingSubcommand {
  _ReadRevisionCommand(super.context);

  @override
  String get name => 'read-revision';

  @override
  String get description =>
      'Read one earlier revision of the routing document, so a restore can '
      'be reviewed before it is asked for.';

  @override
  void addOptions(ArgParser parser) => parser
    ..addOption('revision-ordinal', help: 'The revision to read (required).')
    ..addOption(
      'out',
      help: 'Write the canonical document bytes to this file.',
    );

  @override
  Future<int> invoke(SurfaceRoutingApi api, _RoutingTarget target) async {
    final ordinal = requirePositiveInt('revision-ordinal');
    if (ordinal == null) return 1;

    final read = await api.readRoutingRevision(
      projectSlug: target.projectSlug,
      appSlug: target.appSlug,
      surfaceType: target.requiredSurfaceType,
      surfaceSlug: target.requiredSurfaceSlug,
      environmentId: target.environmentId,
      organizationId: target.organizationId,
      revisionOrdinal: ordinal,
      contractVersion: target.contractVersion,
    );

    final out = argResults?['out'] as String?;
    if (out != null && out.isNotEmpty) {
      await File(out).writeAsBytes(read.documentBytes);
    }

    return report(read.toJson(), [
      'Revision ${read.revisionOrdinal}, ${read.documentBytes.length} bytes, '
          'published ${read.publishedAt.toIso8601String()}.',
      if (out != null && out.isNotEmpty) 'Written to $out.',
    ]);
  }
}

class _PreviewCommand extends _RoutingSubcommand {
  _PreviewCommand(super.context);

  @override
  String get name => 'preview';

  @override
  String get description =>
      'Simulate a current complete policy request using retained server authority.';

  @override
  void addOptions(ArgParser parser) => parser.addOption(
    'document',
    help: 'Canonical DeliveryPolicySimulationRequestV1 file (required).',
  );

  @override
  Future<int> invoke(SurfaceRoutingApi api, _RoutingTarget target) async {
    final request = await readDocument(
      'document',
      DeliveryPolicySimulationRequestV1.fromCanonicalBytes,
    );
    if (request == null || !requireScope(request.scope, target)) return 1;
    final preview = await api.previewRouting(
      projectSlug: target.projectSlug,
      appSlug: target.appSlug,
      surfaceType: target.requiredSurfaceType,
      surfaceSlug: target.requiredSurfaceSlug,
      environmentId: target.environmentId,
      organizationId: target.organizationId,
      documentBytes: request.canonicalBytes,
      expectedTarget: target.coordinate,
    );
    return report(preview.toJson(), [
      const JsonEncoder.withIndent('  ').convert(preview.simulation!.toJson()),
    ]);
  }
}

class _ReviewCommand extends _RoutingSubcommand implements LiveGuardedCommand {
  _ReviewCommand(super.context);

  @override
  String get name => 'review';

  @override
  String get description =>
      'Freeze one complete candidate policy and its original source impact review.';

  @override
  bool get writes => true;

  @override
  void addOptions(ArgParser parser) => parser
    ..addOption(
      'request',
      help:
          'Canonical DeliveryPolicyReviewRequestV1 file (required). A rule '
          'may carry an optional name of 1 to 60 characters.',
    )
    ..addOption(
      'out',
      help: 'Write the complete original server review here (required).',
    );

  @override
  Future<int> invoke(SurfaceRoutingApi api, _RoutingTarget target) async {
    if (requireOption('out') == null) return 1;
    final request = await readDocument(
      'request',
      DeliveryPolicyReviewRequestV1.fromCanonicalBytes,
    );
    if (request == null || !requireScope(request.scope, target)) return 1;
    final review = await api.reviewRouting(
      projectSlug: target.projectSlug,
      appSlug: target.appSlug,
      surfaceType: target.requiredSurfaceType,
      surfaceSlug: target.requiredSurfaceSlug,
      environmentId: target.environmentId,
      organizationId: target.organizationId,
      request: request,
      expectedTarget: target.coordinate,
    );
    return reportReview(review);
  }
}

class _PublishCommand extends _RoutingSubcommand implements LiveGuardedCommand {
  _PublishCommand(super.context);

  @override
  String get name => 'publish';

  @override
  String get description =>
      'Publish only an original server review and its exact acknowledged warning set.';

  @override
  bool get writes => true;

  @override
  bool get acceptsOperationId => true;

  @override
  void addOptions(ArgParser parser) => parser
    ..addOption(
      'review',
      aliases: ['document'],
      help: 'Canonical original DeliveryPolicyReviewV1 file (required).',
    )
    ..addOption(
      'reviewed-digest',
      help:
          'Exact digest of the complete review whose measurement warnings you approved.',
    )
    ..addOption(
      'expected-revision-ordinal',
      help: 'Optional expected head; must match the original server review.',
    )
    ..addFlag(
      'expect-no-revision',
      negatable: false,
      help:
          'Optional first-publication assertion; must match the original review.',
    );

  @override
  Future<int> invoke(SurfaceRoutingApi api, _RoutingTarget target) async {
    final review = await readDocument(
      'review',
      DeliveryPolicyReviewV1.fromCanonicalBytes,
    );
    if (review == null || !requireScope(review.scope, target)) return 1;
    final expectNone = argResults?['expect-no-revision'] as bool? ?? false;
    final ordinal = argResults?['expected-revision-ordinal'] as String?;
    if (expectNone && ordinal != null) {
      writeError('Pass only one expected-head assertion.');
      return 1;
    }
    if (expectNone && review.expectedHeadOrdinal != null) {
      writeError('The server review expects an existing revision.');
      return 1;
    }
    if (ordinal != null) {
      final expected = requirePositiveInt('expected-revision-ordinal');
      if (expected == null) return 1;
      if (expected != review.expectedHeadOrdinal) {
        writeError(
          'The expected revision differs from the original server review.',
        );
        return 1;
      }
    }
    final request = await reviewedPublish(review);
    if (request == null) return 1;
    final result = await api.publishRouting(
      projectSlug: target.projectSlug,
      appSlug: target.appSlug,
      surfaceType: target.requiredSurfaceType,
      surfaceSlug: target.requiredSurfaceSlug,
      environmentId: target.environmentId,
      organizationId: target.organizationId,
      documentBytes: request.canonicalBytes,
      expectedRevisionOrdinal: review.expectedHeadOrdinal,
      operationId: request.operationId,
      expectedTarget: target.coordinate,
    );
    return report(
      {...result.toJson(), 'operationId': request.operationId},
      [
        '${result.outcome?.name ?? "unknown"} at revision ${result.revisionOrdinal}.',
      ],
    );
  }
}

class _RollbackCommand extends _RoutingSubcommand
    implements LiveGuardedCommand {
  _RollbackCommand(super.context);

  @override
  String get fitQuestion => 'Roll back anyway?';

  @override
  String get name => 'rollback';

  @override
  String get description =>
      'Review and restore only the selected route. Structured schedules require a whole-policy review.';

  @override
  bool get writes => true;

  @override
  bool get acceptsOperationId => true;

  bool get onlyReview => argResults?['review-only'] as bool? ?? false;

  @override
  void addOptions(ArgParser parser) => parser
    ..addOption('route-id', help: 'The original route to restore (required).')
    ..addOption(
      'prior-revision-ordinal',
      help: 'Revision to restore the route from (required).',
    )
    ..addOption(
      'expected-revision-ordinal',
      help: 'Expected current whole-policy ordinal (required).',
    )
    ..addOption(
      'reviewed-digest',
      help:
          'Digest of the complete returned review whose warnings you approved.',
    )
    ..addFlag(
      'review-only',
      negatable: false,
      help: 'Return the original route-restoration review without publishing.',
    )
    ..addOption(
      'out',
      help: 'Write the original route-restoration review here.',
    );

  @override
  Future<int> invoke(SurfaceRoutingApi api, _RoutingTarget target) async {
    final routeId = requireOption('route-id');
    if (routeId == null) return 1;
    final prior = requirePositiveInt('prior-revision-ordinal');
    if (prior == null) return 1;
    final expected = requirePositiveInt('expected-revision-ordinal');
    if (expected == null) return 1;
    final review = await api.reviewRouteRollback(
      projectSlug: target.projectSlug,
      appSlug: target.appSlug,
      surfaceType: target.requiredSurfaceType,
      surfaceSlug: target.requiredSurfaceSlug,
      environmentId: target.environmentId,
      organizationId: target.organizationId,
      routeId: routeId,
      priorRevisionOrdinal: prior,
      expectedRevisionOrdinal: expected,
      contractVersion: target.contractVersion,
      expectedTarget: target.coordinate,
    );
    final out = argResults?['out'] as String?;
    if (out != null && out.isNotEmpty) {
      await File(out).writeAsBytes(review.canonicalBytes);
    }
    if (onlyReview) return reportReview(review);
    final request = await reviewedPublish(review);
    if (request == null) return 1;
    final result = await api.rollbackRoute(
      projectSlug: target.projectSlug,
      appSlug: target.appSlug,
      surfaceType: target.requiredSurfaceType,
      surfaceSlug: target.requiredSurfaceSlug,
      environmentId: target.environmentId,
      organizationId: target.organizationId,
      routeId: routeId,
      priorRevisionOrdinal: prior,
      expectedRevisionOrdinal: expected,
      contractVersion: target.contractVersion,
      operationId: request.operationId,
      reviewedPublishRequest: request,
      expectedTarget: target.coordinate,
    );
    return report(
      {...result.toJson(), 'operationId': request.operationId},
      [
        '${result.outcome?.name ?? "unknown"} at revision ${result.revisionOrdinal}.',
      ],
    );
  }
}

class _ReviewRollbackCommand extends _RollbackCommand {
  _ReviewRollbackCommand(super.context);

  @override
  String get name => 'review-rollback';

  @override
  String get description =>
      'Read the complete server review for restoring only one original route.';

  @override
  bool get onlyReview => true;

  @override
  bool get acceptsOperationId => false;

  @override
  void addOptions(ArgParser parser) => parser
    ..addOption('route-id', help: 'The original route to review (required).')
    ..addOption(
      'prior-revision-ordinal',
      help: 'Revision to restore the route from (required).',
    )
    ..addOption(
      'expected-revision-ordinal',
      help: 'Expected current whole-policy ordinal (required).',
    )
    ..addOption('out', help: 'Write the complete original server review here.');
}

final _operationIdShape = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

final _random = Random.secure();

/// Whether [value] is the canonical version 4 UUID the service accepts.
@experimental
bool isCanonicalOperationId(String value) => _operationIdShape.hasMatch(value);

/// Mint one retry identity as a canonical version 4 UUID.
@experimental
String newOperationId() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
