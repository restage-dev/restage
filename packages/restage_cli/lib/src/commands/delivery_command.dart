import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:restage_cli/src/api/delivery_management_api.dart';
import 'package:restage_cli/src/api/surface_routing_api.dart'
    show SurfaceRoutingTypedException;
import 'package:restage_cli/src/commands/authed.dart';
import 'package:restage_cli/src/commands/delivery_sample_command.dart';
import 'package:restage_cli/src/commands/live_guard.dart';
import 'package:restage_cli/src/commands/measurement_page_command.dart';
import 'package:restage_cli/src/measurement/page_read.dart' show pageReads;
import 'package:restage_cli/src/delivery/delivery_operations.dart';
import 'package:restage_cli/src/credentials/file_credential_store.dart';
import 'package:restage_cli/src/io/interactive.dart';
import 'package:restage_cli/src/operations/operation.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';

/// Target-bound delivery reads and reviewed authoring operations.
class DeliveryCommand extends Command<int> {
  /// Uses the existing target, credential, and RPC owners.
  DeliveryCommand({
    required StringSink stdout,
    required StringSink stderr,
    required Interactive interactive,
    FileCredentialStore? credentialStore,
    http.Client? httpClient,
  }) {
    final io = CommandIo(
      stdout: stdout,
      stderr: stderr,
      interactive: interactive,
      credentialStore: credentialStore,
      httpClient: httpClient,
    );
    addSubcommand(DeliverySampleCommand(io));
    final placements = _DeliveryGroup(
      'placements',
      'Read the authoritative placement directory.',
    );
    final plan = _DeliveryGroup(
      'plan',
      'Read, simulate, review, publish, and undo complete delivery plans.',
    );
    for (final operation in DeliveryOperation.values) {
      if (operation.name.startsWith('placementSample')) {
        continue;
      }
      final command = operation.mutates
          ? _DeliveryMutationCommand(operation, io)
          : _DeliverySubcommand(operation, io);
      final path = operation.cliPath.split(' ');
      switch (path[1]) {
        case 'placements':
          placements.addSubcommand(command);
        case 'plan':
          plan.addSubcommand(command);
        default:
          addSubcommand(command);
      }
    }
    addSubcommand(placements);
    addSubcommand(plan);
    for (final read in pageReads) {
      if (!read.cliPath.startsWith('delivery ')) continue;
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

  @override
  String get name => 'delivery';

  @override
  String get description =>
      'Read delivery decisions and author reviewed changes.';
}

class _DeliveryGroup extends Command<int> {
  _DeliveryGroup(this.name, this.description);
  @override
  final String name;
  @override
  final String description;
}

class _DeliveryMutationCommand extends _DeliverySubcommand
    implements LiveGuardedCommand {
  _DeliveryMutationCommand(super.operation, super.io);
}

class _DeliverySubcommand extends Command<int> {
  _DeliverySubcommand(this.operation, this.io) {
    addScopeOptions(argParser, OperationScope.target);
    argParser.addFlag(
      'json',
      negatable: false,
      help: 'Print the complete public result JSON unchanged.',
    );
    if (operation.name.startsWith('deliveryPolicy') &&
        operation != DeliveryOperation.deliveryPolicyPublish) {
      argParser
        ..addOption(
          'scope',
          help: 'Canonical exact root and family scope JSON file.',
        )
        ..addOption(
          'placement',
          help:
              'Exact named:<slug> or default:<surface-type>:<slug> placement scope.',
        );
    }
    switch (operation) {
      case DeliveryOperation.placementList:
        argParser
          ..addOption(
            'page-size',
            defaultsTo: '50',
            help: 'Directory rows per page from 1 to 200.',
          )
          ..addOption(
            'cursor',
            help: 'Exact opaque continuation returned by the previous page.',
          );
      case DeliveryOperation.placementRead:
        argParser
          ..addOption(
            'key',
            help:
                'Exact named:<slug> or default:<surface-type>:<slug> placement.',
          )
          ..addOption(
            'query',
            help: 'Optional canonical UTC observed-history query JSON file.',
          )
          ..addOption(
            'history-cursor',
            help:
                'Exact policy-history continuation returned by this placement.',
          );
      case DeliveryOperation.placementObservedHistory:
        argParser.addOption(
          'query',
          help:
              'Canonical placement query with UTC bounds and hour or day bucket.',
        );
      case DeliveryOperation.placementSimulate:
        argParser
          ..addMultiOption(
            'key',
            help:
                'Explicit placement keys to probe in order. At most 200 unique keys.',
          )
          ..addOption(
            'inputs',
            help: 'Canonical public simulation inputs JSON file.',
          )
          ..addOption('cursor', help: 'Exact opaque simulation continuation.');
      case DeliveryOperation.deliveryPolicyHistory:
        argParser
          ..addOption(
            'before-ordinal',
            help: 'Exclusive ordinal continuation returned by history.',
          )
          ..addOption(
            'page-size',
            help: 'Requested history page size. Omit for complete history.',
          );
      case DeliveryOperation.deliveryPolicyFit:
        argParser
          ..addOption(
            'publication',
            help:
                'Canonical exact publication reference JSON file for inverse fit.',
          )
          ..addOption('page-size', help: 'Optional positive fit page size.')
          ..addOption('cursor', help: 'Exact opaque fit continuation.');
      case DeliveryOperation.deliveryPolicySimulate:
        argParser.addOption(
          'inputs',
          help: 'Canonical public simulation inputs JSON file.',
        );
      case DeliveryOperation.deliveryPolicyReview:
        argParser
          ..addOption(
            'plan',
            help: 'Canonical complete candidate plan JSON file.',
          )
          ..addOption(
            'reason',
            help: 'Operator-written reason for this complete plan.',
          )
          ..addOption(
            'expected-head-ordinal',
            help: 'Expected current policy revision ordinal.',
          )
          ..addFlag(
            'expect-no-head',
            negatable: false,
            help: 'Review the first policy for this exact scope.',
          )
          ..addOption('out', help: 'Write the exact server review JSON here.');
      case DeliveryOperation.deliveryPolicyPublish:
        argParser
          ..addOption('review', help: 'Canonical server review JSON file.')
          ..addOption(
            'operation-id',
            help:
                'Canonical lowercase UUIDv4 for this exact publication attempt.',
          )
          ..addOption(
            'acknowledgement',
            help:
                'Canonical exact measurement warning acknowledgement JSON file.',
          );
      case DeliveryOperation.deliveryPolicyUndoReview:
        argParser
          ..addOption(
            'restore-ordinal',
            help:
                'Immutable revision ordinal whose complete plan will be restored.',
          )
          ..addOption(
            'reason',
            help: 'Operator-written reason for the restoration.',
          )
          ..addOption(
            'expected-head-ordinal',
            help: 'Expected current policy revision ordinal.',
          )
          ..addFlag(
            'expect-no-head',
            negatable: false,
            help: 'Expect no current policy head.',
          )
          ..addOption(
            'out',
            help: 'Write the complete restoration review JSON here.',
          );
      default:
        break;
    }
  }

  final DeliveryOperation operation;
  final CommandIo io;

  @override
  String get name => operation.cliPath.split(' ').last;

  @override
  String get description => switch (operation) {
    DeliveryOperation.placementList =>
      'List reported placements and authored samples at the exact target.',
    DeliveryOperation.placementRead =>
      'Read one exact placement and its qualified policy and history.',
    DeliveryOperation.placementObservedHistory =>
      'Read successful first-paint observations with explicit source coverage.',
    DeliveryOperation.placementSimulate =>
      'Probe placement selection and subsequent surface delivery without enrollment.',
    DeliveryOperation.deliveryPolicyRead =>
      'Read the complete current delivery policy for an exact scope.',
    DeliveryOperation.deliveryPolicyTimeline =>
      'Read local starts and rule ordering from the serving authority.',
    DeliveryOperation.deliveryPolicyHistory =>
      'Read immutable complete policy revisions and their continuation.',
    DeliveryOperation.deliveryPolicyFit =>
      'Read authoritative fit for an exact scope or pushed publication.',
    DeliveryOperation.deliveryPolicySimulate =>
      'Simulate one exact policy with explicitly supplied public inputs.',
    DeliveryOperation.deliveryPolicyReview =>
      'Freeze a complete candidate plan and its measurement impact review.',
    DeliveryOperation.deliveryPolicyPublish =>
      'Publish only an exact server review and acknowledged warning set.',
    DeliveryOperation.deliveryPolicyUndoReview =>
      'Review restoration of an immutable complete plan before publication.',
    _ => throw ArgumentError.value(operation, 'operation'),
  };

  String? _option(String key) =>
      argResults!.options.contains(key) ? (argResults?[key] as String?) : null;

  String _required(String key) {
    final value = _option(key);
    if (value == null || value.isEmpty) {
      throw FormatException('Required: --$key.');
    }
    return value;
  }

  int? _integer(String key, {bool required = false}) {
    final raw = required ? _required(key) : _option(key);
    if (raw == null) return null;
    final value = int.tryParse(raw);
    if (value == null || value < 1) {
      throw FormatException('--$key must be a positive integer.');
    }
    return value;
  }

  Future<Uint8List> _file(String key) => readDeliveryFile(
    _required(key),
    maximumBytes: kMaximumPlacementManagementRequestBytes,
  );

  Future<DeliveryPolicyScopeV1> _scope(TargetCoordinate target) async {
    final path = _option('scope');
    final placement = _option('placement');
    if ((path == null) == (placement == null)) {
      throw const FormatException(
        'Select exactly one --scope or --placement. Surface scopes must name their exact family.',
      );
    }
    return path != null
        ? DeliveryPolicyScopeV1.fromCanonicalBytes(await _file('scope'))
        : DeliveryPolicyScopeV1(
            root: DeliveryRootIdentityV1.placement(
              PlacementIdentityV1(
                target: target,
                key: PlacementKeyV1.parse(placement!),
              ),
            ),
            family: const DeliveryFamilySelectorV1.none(),
          );
  }

  Future<DeliverySimulationInputsV1> _inputs() async {
    final bytes = await _file('inputs');
    return verifyCanonicalRoundTrip(
      DeliverySimulationInputsV1.fromJson(decodeCanonicalObject(bytes)),
      bytes,
      path: 'deliverySimulationInputs',
    );
  }

  int? _expectedHead() {
    final ordinal = _integer('expected-head-ordinal');
    final absent = argResults?['expect-no-head'] as bool? ?? false;
    if (absent == (ordinal != null)) {
      throw const FormatException(
        'Select exactly one --expected-head-ordinal or --expect-no-head.',
      );
    }
    return ordinal;
  }

  Future<CanonicalValue> _request(TargetCoordinate target) async {
    switch (operation) {
      case DeliveryOperation.placementList:
        return PlacementDirectoryRequestV1(
          target: target,
          cursor: _option('cursor'),
          limit: _integer('page-size')!,
        );
      case DeliveryOperation.placementRead:
        return PlacementReadRequestV1(
          target: target,
          key: PlacementKeyV1.parse(_required('key')),
          historyCursor: _option('history-cursor'),
          observedHistory: _option('query') == null
              ? null
              : PlacementObservedHistoryQueryV1.fromCanonicalBytes(
                  await _file('query'),
                ),
        );
      case DeliveryOperation.placementObservedHistory:
        return PlacementObservedHistoryReadRequestV1(
          target: target,
          query: PlacementObservedHistoryQueryV1.fromCanonicalBytes(
            await _file('query'),
          ),
        );
      case DeliveryOperation.placementSimulate:
        return PlacementSimulationPageRequestV1(
          target: target,
          keys: (argResults?['key'] as List<String>)
              .map(PlacementKeyV1.parse)
              .toList(),
          inputs: await _inputs(),
          cursor: _option('cursor'),
        );
      case DeliveryOperation.deliveryPolicyRead:
        return DeliveryPolicyReadRequestV1(scope: await _scope(target));
      case DeliveryOperation.deliveryPolicyTimeline:
        return DeliveryPolicyTimelineRequestV1(scope: await _scope(target));
      case DeliveryOperation.deliveryPolicyHistory:
        return DeliveryPolicyHistoryRequestV1(
          scope: await _scope(target),
          beforeOrdinal: _integer('before-ordinal'),
          pageSize: _integer('page-size'),
        );
      case DeliveryOperation.deliveryPolicyFit:
        if (_option('publication') != null) {
          if (_option('scope') != null || _option('placement') != null) {
            throw const FormatException(
              'Select one publication or policy scope.',
            );
          }
          return DeliveryPolicyFitReadRequestV1.forPublication(
            publication: DeliveryPublicationReferenceV1.fromCanonicalBytes(
              await _file('publication'),
            ),
            pageSize: _integer('page-size'),
            cursor: _option('cursor'),
          );
        }
        return DeliveryPolicyFitReadRequestV1.forScope(
          scope: await _scope(target),
          pageSize: _integer('page-size'),
          cursor: _option('cursor'),
        );
      case DeliveryOperation.deliveryPolicySimulate:
        return DeliveryPolicySimulationRequestV1(
          scope: await _scope(target),
          inputs: await _inputs(),
        );
      case DeliveryOperation.deliveryPolicyReview:
        _required('out');
        final plan = DeliveryPolicyPlanV1.fromCanonicalBytes(
          await _file('plan'),
        );
        if ((_option('scope') != null || _option('placement') != null) &&
            await _scope(target) != plan.scope) {
          throw const FormatException('The plan is for another policy scope.');
        }
        return DeliveryPolicyReviewRequestV1(
          scope: plan.scope,
          expectedHeadOrdinal: _expectedHead(),
          candidatePlan: plan,
          reason: _required('reason'),
        );
      case DeliveryOperation.deliveryPolicyPublish:
        final review = DeliveryPolicyReviewV1.fromCanonicalBytes(
          await _file('review'),
        );
        final ackBytes = _option('acknowledgement') == null
            ? null
            : await _file('acknowledgement');
        final ack = ackBytes == null
            ? null
            : verifyCanonicalRoundTrip(
                DeliveryMeasurementImpactAcknowledgementV1.fromJson(
                  decodeCanonicalObject(ackBytes),
                ),
                ackBytes,
                path: 'deliveryMeasurementImpactAcknowledgement',
              );
        return DeliveryPolicyPublishRequestV1(
          reviewRef: review.reviewRef,
          operationId: _required('operation-id'),
          measurementAcknowledgement: ack,
        );
      case DeliveryOperation.deliveryPolicyUndoReview:
        _required('out');
        return DeliveryPolicyUndoReviewRequestV1(
          scope: await _scope(target),
          expectedHeadOrdinal: _expectedHead(),
          restoreOrdinal: _integer('restore-ordinal', required: true)!,
          reason: _required('reason'),
        );
      default:
        throw ArgumentError.value(operation, 'operation');
    }
  }

  @override
  Future<int> run() async {
    try {
      return await runAuthed(io, argResults, OperationScope.target, (
        context,
      ) async {
        final selected = context.target!;
        final target = targetCoordinateOf(selected);
        final request = await _request(target);
        if (this is LiveGuardedCommand &&
            !await confirmLiveChange(
              command: this,
              interactive: io.interactive,
              stdout: io.stdout,
              stderr: io.stderr,
              runtimePlane: selected.runtimePlane,
              impactLine:
                  'Delivery $name for ${selected.app} in ${selected.environment} (live).',
            )) {
          return 1;
        }
        final result = await DeliveryManagementApi(context.api).invoke(
          operation: operation,
          projectSlug: selected.project,
          appSlug: selected.app,
          target: target,
          request: request,
        );
        if (_option('out') case final out?) {
          await File(out).writeAsBytes(result.canonicalBytes, flush: true);
        }
        if (argResults?['json'] == true) {
          io.stdout.writeln(utf8.decode(result.canonicalBytes));
        } else {
          io.stdout.writeln(
            'Delivery ${selected.project}/${selected.app}/${selected.environment} '
            '(${selected.runtimePlane.wireName}); target '
            '${target.environmentTargetId.value}, organization '
            '${target.organizationId.value}.',
          );
          io.stdout.writeln(_resultSummary(result));
          io.stdout.writeln(
            const JsonEncoder.withIndent('  ').convert(result.toJson()),
          );
        }
        return switch (result) {
          DeliveryPolicyPublishResultV1 value
              when value.outcome == 'conflict' || value.outcome == 'refused' =>
            1,
          DeliveryPolicyReviewV1 value when value.refusalCodes.isNotEmpty => 1,
          _ => 0,
        };
      });
    } on DeliveryManagementResponseException catch (error) {
      io.stderr.writeln(error);
      return 2;
    } on SurfaceRoutingTypedException catch (error) {
      io.stderr.writeln(error);
      return 1;
    } on CanonicalFormatException catch (error) {
      io.stderr.writeln(error);
      return 1;
    } on FormatException catch (error) {
      io.stderr.writeln(error.message);
      return 1;
    } on FileSystemException {
      io.stderr.writeln('Could not read or write the supplied delivery file.');
      return 1;
    } on ArgumentError catch (error) {
      io.stderr.writeln(error.message);
      return 1;
    }
  }
}

String _resultSummary(CanonicalValue result) => switch (result) {
  PlacementDirectoryPageV1 value =>
    'Directory ${value.status.name}; ${value.items.length} placements; '
        'reporting cutoff ${_utc(value.reportingCutoffMicros)}.',
  PlacementReadV1 value =>
    '${value.key.value}: ${value.status.name}; authority '
        '${value.authorityStatus.name}; experiment requirement '
        '${value.placementExperimentRequirement.name}.',
  PlacementObservedHistoryV1 value =>
    'Observed authenticated first paints for ${value.placement.value}; '
        '${value.coverage.name}; UTC ${_utc(value.requestedFromMicros)} '
        'to ${_utc(value.requestedUntilMicros)}.',
  PlacementSimulationPageV1 value =>
    'Read-only placement and surface probes: ${value.status.name}; '
        '${value.probes.length} returned probes.',
  DeliveryPolicyReadV1 value =>
    '${_scopeLabel(value.scope)}: ${value.revision == null ? 'no policy' : 'revision ${value.revision!.ordinal}'}.',
  DeliveryPolicyHistoryV1 value =>
    '${_scopeLabel(value.scope)}: ${value.revisions.length} complete revisions; '
        'next before ordinal ${value.nextBeforeOrdinal ?? 'none'}.',
  DeliveryPolicyTimelineV1 value =>
    '${_scopeLabel(value.policy.scope)} local starts: '
        '${value.plan?.snapshots.map((snapshot) => snapshot.effectiveFromLocal?.toJson()['value'] ?? 'baseline').join(', ') ?? 'no policy'}.',
  DeliveryPolicyFitReadV1 value =>
    'Fit authority ${value.authorityDigest.hex}; '
        '${value.refusalCode ?? '${value.entries.length} qualified entries'}.',
  DeliveryPolicySimulationV1 value =>
    '${_scopeLabel(value.scope)} simulation: ${value.reason}.',
  DeliveryPolicyReviewV1 value =>
    '${_scopeLabel(value.scope)} review ${value.digest.hex}; '
        'measurement warnings ${value.measurementImpact.warningCodes.join(', ')}; '
        'refusals ${value.refusalCodes.join(', ')}.',
  DeliveryPolicyPublishResultV1 value =>
    'Publication ${value.outcome}${value.refusalCode == null ? '' : ': ${value.refusalCode}'}.',
  _ => throw ArgumentError.value(result, 'result'),
};

String _scopeLabel(DeliveryPolicyScopeV1 scope) =>
    scope.root.placement?.key.value ??
    'surface:${scope.root.surface!.surfaceId.value} '
        '${jsonEncode(scope.family.toJson())}';

String _utc(int micros) =>
    DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true).toIso8601String();

/// Reads only the supplied file, bounding allocation before reading its bytes.
Future<Uint8List> readDeliveryFile(
  String path, {
  required int maximumBytes,
}) async {
  final file = await File(path).open();
  try {
    final length = await file.length();
    if (length < 1 || length > maximumBytes) {
      throw const FormatException('The supplied file exceeds its byte limit.');
    }
    final bytes = await file.read(length);
    if (bytes.length != length || (await file.read(1)).isNotEmpty) {
      throw const FormatException(
        'The supplied file changed while being read.',
      );
    }
    return bytes;
  } finally {
    await file.close();
  }
}
