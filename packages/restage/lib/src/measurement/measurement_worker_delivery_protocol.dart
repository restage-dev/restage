import 'package:meta/meta.dart';

import 'measurement_outbox_protocol.dart';
import 'measurement_worker_protocol.dart';

/// The five admission predicates that must be true before delivery startup.
///
/// This is deliberately a closed value object rather than a callback. The
/// composition root proves admission before it asks a platform plugin for a
/// path, creates a worker, or constructs any delivery-owned object.
@immutable
final class MeasurementWorkerOwnedDeliveryAdmission {
  /// Creates the already-resolved admission state for one configured runtime.
  const MeasurementWorkerOwnedDeliveryAdmission({
    required this.hasEndpoint,
    required this.analyticsEnabled,
    required this.policySupported,
    required this.measurementClassAdmitted,
    required this.budgetAvailable,
  });

  /// A hosted measurement endpoint is present.
  final bool hasEndpoint;

  /// The target explicitly enables analytics collection.
  final bool analyticsEnabled;

  /// This SDK understands the target's schema and privacy policy.
  final bool policySupported;

  /// The selected point class is admitted by the resolved policy.
  final bool measurementClassAdmitted;

  /// The finite capture budget has not been exhausted.
  final bool budgetAvailable;

  /// The first fail-closed reason, or `null` only when all five predicates hold.
  MeasurementWorkerOwnedDeliveryAdmissionDenial? get denial {
    if (!hasEndpoint) {
      return MeasurementWorkerOwnedDeliveryAdmissionDenial.noEndpoint;
    }
    if (!analyticsEnabled) {
      return MeasurementWorkerOwnedDeliveryAdmissionDenial.analyticsDisabled;
    }
    if (!policySupported) {
      return MeasurementWorkerOwnedDeliveryAdmissionDenial.unsupportedPolicy;
    }
    if (!measurementClassAdmitted) {
      return MeasurementWorkerOwnedDeliveryAdmissionDenial.classDenied;
    }
    if (!budgetAvailable) {
      return MeasurementWorkerOwnedDeliveryAdmissionDenial.budgetExhausted;
    }
    return null;
  }

  /// Whether the root may resolve the application-support path and start work.
  bool get isAdmitted => denial == null;
}

/// Closed intentional no-measurement outcomes before worker startup.
enum MeasurementWorkerOwnedDeliveryAdmissionDenial {
  /// No hosted endpoint exists for this target.
  noEndpoint,

  /// The target intentionally disables analytics.
  analyticsDisabled,

  /// The schema/privacy policy is not supported by this SDK.
  unsupportedPolicy,

  /// The resolved measurement class is not admitted.
  classDenied,

  /// The finite local capture budget is exhausted.
  budgetExhausted,
}

/// Root-isolate path resolver used only before a native worker is spawned.
///
/// The resolver itself never crosses the isolate boundary. The default native
/// implementation uses `path_provider`; tests inject a pure resolver to prove
/// denied admission performs no path lookup.
abstract interface class MeasurementWorkerOwnedDeliveryPathResolver {
  /// Resolves the one application-support directory for this configured runtime.
  Future<String> resolveApplicationSupportPath();
}

/// One transient immutable header pair passed to the worker at startup.
///
/// Headers are never persisted. The composition intentionally accepts values,
/// not a provider callback, so no root-isolate closure or credential object can
/// cross into the worker. A later host-owned credential-rotation command must
/// retain this primitive-only boundary.
@immutable
final class MeasurementWorkerOwnedDeliveryHeader {
  /// Creates one syntactically safe transient header pair.
  MeasurementWorkerOwnedDeliveryHeader({
    required this.name,
    required this.value,
  }) {
    if (name.isEmpty ||
        name.contains('\r') ||
        name.contains('\n') ||
        value.contains('\r') ||
        value.contains('\n')) {
      throw ArgumentError('Invalid measurement delivery header');
    }
  }

  /// Header name.
  final String name;

  /// Header value, retained only in worker memory.
  final String value;

  List<Object?> toWorkerWire() => [name, value];

  static MeasurementWorkerOwnedDeliveryHeader fromWorkerWire(Object? value) {
    final values = _requireList(value, expectedLength: 2);
    return MeasurementWorkerOwnedDeliveryHeader(
      name: _requireString(values[0]),
      value: _requireString(values[1]),
    );
  }
}

/// Immutable primitive-only configuration for one worker-owned delivery runtime.
@immutable
final class MeasurementWorkerOwnedDeliveryConfiguration {
  /// Creates configuration that is inert until [admission] is fully admitted.
  MeasurementWorkerOwnedDeliveryConfiguration({
    required this.admission,
    required this.endpoint,
    required this.configurationFingerprint,
    required this.maximumSessions,
    List<MeasurementWorkerOwnedDeliveryHeader> headers = const [],
    this.debugTracing = false,
  }) : headers = List.unmodifiable(headers) {
    if (maximumSessions <= 0 ||
        maximumSessions > kMeasurementWorkerMaximumSessionCount ||
        configurationFingerprint.trim().isEmpty) {
      throw ArgumentError(
        'Invalid measurement worker-owned delivery configuration',
      );
    }
  }

  /// Admission proven before any native path or worker operation starts.
  final MeasurementWorkerOwnedDeliveryAdmission admission;

  /// Exact upload endpoint when admitted; absent endpoints are no-op admissions.
  final String? endpoint;

  /// Non-secret endpoint/public-key/schema configuration digest persisted by the outbox.
  final String configurationFingerprint;

  /// Maximum independently registered capture sessions in the one worker.
  final int maximumSessions;

  /// Immutable transient header values. They are never journaled.
  final List<MeasurementWorkerOwnedDeliveryHeader> headers;

  /// Test-only causal ownership trace; disabled in normal runtime configuration.
  final bool debugTracing;

  /// Whether the admitted configuration can be passed to the native worker.
  bool get isValidForStartup {
    final rawEndpoint = endpoint;
    if (rawEndpoint == null || rawEndpoint.isEmpty) return false;
    final parsed = Uri.tryParse(rawEndpoint);
    return parsed != null &&
        parsed.hasScheme &&
        (parsed.scheme == 'https' || parsed.scheme == 'http');
  }

  /// Builds only sendable primitive values after the root resolved [supportPath].
  List<Object?> toWorkerBootstrapWire(String supportPath) => [
        supportPath,
        endpoint,
        configurationFingerprint,
        [for (final header in headers) header.toWorkerWire()],
        maximumSessions,
        debugTracing,
      ];

  /// Parses the primitive-only bootstrap configuration inside the worker.
  static MeasurementWorkerOwnedDeliveryConfiguration fromWorkerBootstrapWire(
    Object? value,
  ) {
    final values = _requireList(value, expectedLength: 6);
    final rawHeaders = _requireList(values[3]);
    final configuration = MeasurementWorkerOwnedDeliveryConfiguration(
      admission: const MeasurementWorkerOwnedDeliveryAdmission(
        hasEndpoint: true,
        analyticsEnabled: true,
        policySupported: true,
        measurementClassAdmitted: true,
        budgetAvailable: true,
      ),
      endpoint: _requireString(values[1]),
      configurationFingerprint: _requireString(values[2]),
      maximumSessions: _requireInt(values[4]),
      headers: [
        for (final header in rawHeaders)
          MeasurementWorkerOwnedDeliveryHeader.fromWorkerWire(header),
      ],
      debugTracing: _requireBool(values[5]),
    );
    if (_requireString(values[0]).trim().isEmpty ||
        !configuration.isValidForStartup) {
      throw const MeasurementWorkerOwnedDeliveryProtocolException(
        'invalid_bootstrap_configuration',
      );
    }
    return configuration;
  }
}

/// Closed result of registering a capture session with the delivery worker.
@immutable
final class MeasurementWorkerOwnedDeliveryOpenSessionResult {
  const MeasurementWorkerOwnedDeliveryOpenSessionResult._({
    required this.outcome,
    required this.session,
    required this.workerOwnedByteCount,
  });

  /// Registration result shared with the capture worker contract.
  final MeasurementWorkerOpenSessionOutcome outcome;

  /// Active delivery session only when [outcome] is `opened`.
  final MeasurementWorkerOwnedDeliverySession? session;

  /// Worker-owned structural bytes reported after registration.
  final int workerOwnedByteCount;

  factory MeasurementWorkerOwnedDeliveryOpenSessionResult.opened({
    required MeasurementWorkerOwnedDeliverySession session,
    required int workerOwnedByteCount,
  }) =>
      MeasurementWorkerOwnedDeliveryOpenSessionResult._(
        outcome: MeasurementWorkerOpenSessionOutcome.opened,
        session: session,
        workerOwnedByteCount: workerOwnedByteCount,
      );

  factory MeasurementWorkerOwnedDeliveryOpenSessionResult.of(
    MeasurementWorkerOpenSessionOutcome outcome, {
    required int workerOwnedByteCount,
  }) =>
      MeasurementWorkerOwnedDeliveryOpenSessionResult._(
        outcome: outcome,
        session: null,
        workerOwnedByteCount: workerOwnedByteCount,
      );
}

/// Closed worker-owned delivery result for a checkpoint or finalization barrier.
enum MeasurementWorkerOwnedDeliveryCheckpointOutcome {
  /// The strict receipt was durable and the ready record was deleted.
  delivered(1),

  /// The exact body is durable and retained for later delivery.
  committed(2),

  /// A deterministic persisted retry is pending.
  retryScheduled(3),

  /// The record is intentionally retained without automatic egress.
  held(4),

  /// The record is retained outside automatic egress.
  quarantined(5),

  /// Local 24-hour retention removed an unacknowledged record.
  retentionExpired(6),

  /// The exact body could not fit the closed outbox record bound.
  payloadTooLarge(7),

  /// Existing journal records were preserved and the new batch was not stored.
  outboxSaturated(8),

  /// No truthful durable state transition was possible.
  persistenceFailure(9),

  /// The worker or platform became unavailable.
  unavailable(10),

  /// The session has already terminally finalized.
  finalized(11),

  /// A bounded worker control path could not accept another barrier.
  saturated(12),

  /// A durable acknowledgement exists and startup cleanup will converge.
  acknowledgedPendingCleanup(13);

  const MeasurementWorkerOwnedDeliveryCheckpointOutcome(this.wireCode);

  /// Closed primitive protocol spelling.
  final int wireCode;

  static MeasurementWorkerOwnedDeliveryCheckpointOutcome? fromWireCode(
    int value,
  ) {
    for (final candidate in values) {
      if (candidate.wireCode == value) return candidate;
    }
    return null;
  }
}

/// Immutable result that never returns canonical body or receipt bytes to root.
@immutable
final class MeasurementWorkerOwnedDeliveryCheckpointResult {
  /// Creates a root-visible delivery result.
  const MeasurementWorkerOwnedDeliveryCheckpointResult({
    required this.outcome,
    required this.sequence,
    required this.isFinal,
    required this.workerOwnedByteCount,
  });

  /// Closed persistence/delivery state.
  final MeasurementWorkerOwnedDeliveryCheckpointOutcome outcome;

  /// Prepared sequence only when a worker batch was attempted.
  final int? sequence;

  /// Finality only when a worker batch was attempted.
  final bool? isFinal;

  /// Structural worker-owned bytes after the result.
  final int workerOwnedByteCount;
}

/// Closed result of discarding a session that never reached first paint.
enum MeasurementWorkerOwnedDeliveryDiscardOutcome {
  /// The worker removed an uncommitted session without a frame or outbox write.
  discarded(1),

  /// The session had already reached a terminal boundary.
  finalized(2),

  /// The worker or platform became unavailable before discard completed.
  unavailable(3),

  /// A bounded worker control path could not accept the discard command.
  saturated(4);

  const MeasurementWorkerOwnedDeliveryDiscardOutcome(this.wireCode);

  /// Closed primitive protocol spelling.
  final int wireCode;

  static MeasurementWorkerOwnedDeliveryDiscardOutcome? fromWireCode(int value) {
    for (final candidate in values) {
      if (candidate.wireCode == value) return candidate;
    }
    return null;
  }
}

/// Immutable result for an uncommitted-session discard barrier.
@immutable
final class MeasurementWorkerOwnedDeliveryDiscardResult {
  /// Creates one root-visible discard outcome.
  const MeasurementWorkerOwnedDeliveryDiscardResult({
    required this.outcome,
    required this.workerOwnedByteCount,
  });

  /// Whether no frame/outbox record was created for this session.
  final MeasurementWorkerOwnedDeliveryDiscardOutcome outcome;

  /// Structural worker-owned bytes after the discard barrier.
  final int workerOwnedByteCount;
}

/// Closed reset/cutover outcome. A runtime remains disabled in every result.
enum MeasurementWorkerOwnedDeliveryResetOutcome {
  /// Old-generation unacknowledged local records were fully purged.
  purged(1),

  /// Purge could not complete; the old runtime remains disabled.
  failed(2),

  /// The worker was absent before a truthful purge outcome was available.
  unavailable(3);

  const MeasurementWorkerOwnedDeliveryResetOutcome(this.wireCode);

  /// Closed primitive protocol spelling.
  final int wireCode;

  static MeasurementWorkerOwnedDeliveryResetOutcome? fromWireCode(int value) {
    for (final candidate in values) {
      if (candidate.wireCode == value) return candidate;
    }
    return null;
  }
}

/// Immutable result of stopping an old generation and purging its local state.
@immutable
final class MeasurementWorkerOwnedDeliveryResetResult {
  /// Creates a reset/cutover result.
  const MeasurementWorkerOwnedDeliveryResetResult({
    required this.outcome,
    required this.purgedRecordCount,
  });

  /// Closed reset result.
  final MeasurementWorkerOwnedDeliveryResetOutcome outcome;

  /// Truthful count of local records removed before any failure.
  final int purgedRecordCount;
}

/// Closed result of an orderly worker shutdown.
enum MeasurementWorkerOwnedDeliveryShutdownOutcome {
  /// The worker stopped after all already-finalized sessions were closed.
  closed(1),

  /// The worker could not reach an orderly terminal state.
  unavailable(2);

  const MeasurementWorkerOwnedDeliveryShutdownOutcome(this.wireCode);

  /// Closed primitive protocol spelling.
  final int wireCode;

  static MeasurementWorkerOwnedDeliveryShutdownOutcome? fromWireCode(
    int value,
  ) {
    for (final candidate in values) {
      if (candidate.wireCode == value) return candidate;
    }
    return null;
  }
}

/// Immutable worker shutdown result.
@immutable
final class MeasurementWorkerOwnedDeliveryShutdownResult {
  /// Creates a shutdown result.
  const MeasurementWorkerOwnedDeliveryShutdownResult(this.outcome);

  /// Closed orderly-shutdown result.
  final MeasurementWorkerOwnedDeliveryShutdownOutcome outcome;
}

/// Causal test-only trace emitted from the actual worker isolate.
enum MeasurementWorkerOwnedDeliveryDebugStage {
  /// The worker validated and canonicalized a prepared batch.
  canonicalized(1),

  /// The worker created the strict exact HTTP body and SHA-256 witnesses.
  hashedAndPrepared(2),

  /// The worker opened, recovered, or mutated the durable journal.
  journal(3),

  /// The worker-local HTTP client attempted an upload.
  http(4);

  const MeasurementWorkerOwnedDeliveryDebugStage(this.wireCode);

  /// Closed primitive protocol spelling.
  final int wireCode;

  static MeasurementWorkerOwnedDeliveryDebugStage? fromWireCode(int value) {
    for (final candidate in values) {
      if (candidate.wireCode == value) return candidate;
    }
    return null;
  }
}

/// One causal ownership observation from the worker isolate.
@immutable
final class MeasurementWorkerOwnedDeliveryDebugEvent {
  /// Creates a worker-owned trace event.
  const MeasurementWorkerOwnedDeliveryDebugEvent({
    required this.stage,
    required this.workerIsolateId,
  });

  /// Work performed by the worker.
  final MeasurementWorkerOwnedDeliveryDebugStage stage;

  /// `Isolate.current.hashCode` captured inside the worker.
  final int workerIsolateId;
}

/// Private implementation contract shared by native and unsupported facades.
abstract interface class MeasurementWorkerOwnedDeliveryRuntimeState {
  bool get isAvailable;

  int get workerOwnedByteCount;

  int get debugWorkerSpawnCount;

  int? get debugWorkerIsolateId;

  Stream<MeasurementWorkerAppendAcknowledgement> get appendAcknowledgements;

  Stream<MeasurementWorkerOwnedDeliveryDebugEvent> get debugEvents;

  Future<MeasurementWorkerOwnedDeliveryOpenSessionResult> openSession(
    MeasurementWorkerSessionRegistration registration,
  );

  Future<MeasurementWorkerOwnedDeliveryResetResult> reset(
    MeasurementOutboxPurgeReason reason,
  );

  Future<MeasurementWorkerOwnedDeliveryShutdownResult> shutdown();

  void debugKillWorkerForTesting();
}

/// Internal active session contract for the worker-owned delivery runtime.
abstract interface class MeasurementWorkerOwnedDeliverySessionState {
  MeasurementWorkerAppendOutcome append(MeasurementWorkerAppendRecord record);

  Future<MeasurementWorkerOwnedDeliveryCheckpointResult> checkpoint();

  Future<MeasurementWorkerOwnedDeliveryCheckpointResult> teardown();

  Future<MeasurementWorkerOwnedDeliveryDiscardResult> discard();
}

/// Handle for a session whose checkpoint and finalization never expose body bytes.
@immutable
final class MeasurementWorkerOwnedDeliverySession {
  /// Creates an internal session handle after worker registration succeeds.
  const MeasurementWorkerOwnedDeliverySession.internal(
    this._state,
    this.sessionId,
  );

  final MeasurementWorkerOwnedDeliverySessionState _state;

  /// Opaque capture session coordinate.
  final String sessionId;

  /// Synchronously sends one compact primitive append to the fixed handoff.
  MeasurementWorkerAppendOutcome append(MeasurementWorkerAppendRecord record) =>
      _state.append(record);

  /// Orders durable checkpoint preparation and one bounded upload attempt.
  Future<MeasurementWorkerOwnedDeliveryCheckpointResult> checkpoint() =>
      _state.checkpoint();

  /// Orders terminal preparation and rejects later appends locally.
  Future<MeasurementWorkerOwnedDeliveryCheckpointResult> teardown() =>
      _state.teardown();

  /// Removes an uncommitted session without preparing a fact frame.
  Future<MeasurementWorkerOwnedDeliveryDiscardResult> discard() =>
      _state.discard();
}

/// Platform result before the facade constructs a public runtime wrapper.
@immutable
final class MeasurementWorkerOwnedDeliveryRuntimeLaunchResult {
  const MeasurementWorkerOwnedDeliveryRuntimeLaunchResult._({
    required this.state,
    required this.unavailableReason,
  });

  /// Live native state only when startup succeeded.
  final MeasurementWorkerOwnedDeliveryRuntimeState? state;

  /// Stable fail-closed reason only when native startup failed.
  final String? unavailableReason;

  factory MeasurementWorkerOwnedDeliveryRuntimeLaunchResult.started(
    MeasurementWorkerOwnedDeliveryRuntimeState state,
  ) =>
      MeasurementWorkerOwnedDeliveryRuntimeLaunchResult._(
        state: state,
        unavailableReason: null,
      );

  factory MeasurementWorkerOwnedDeliveryRuntimeLaunchResult.unavailable(
    String reason,
  ) =>
      MeasurementWorkerOwnedDeliveryRuntimeLaunchResult._(
        state: null,
        unavailableReason: reason,
      );
}

/// Parsed primitive-only worker command base type.
sealed class MeasurementWorkerOwnedDeliveryInboundMessage {
  const MeasurementWorkerOwnedDeliveryInboundMessage();
}

final class MeasurementWorkerOwnedDeliveryRegisterMessage
    extends MeasurementWorkerOwnedDeliveryInboundMessage {
  const MeasurementWorkerOwnedDeliveryRegisterMessage({
    required this.requestId,
    required this.registration,
  });

  final int requestId;
  final MeasurementWorkerSessionRegistration registration;
}

final class MeasurementWorkerOwnedDeliveryAppendMessage
    extends MeasurementWorkerOwnedDeliveryInboundMessage {
  const MeasurementWorkerOwnedDeliveryAppendMessage({
    required this.sessionId,
    required this.record,
  });

  final String sessionId;
  final MeasurementWorkerAppendRecord record;
}

final class MeasurementWorkerOwnedDeliveryCheckpointMessage
    extends MeasurementWorkerOwnedDeliveryInboundMessage {
  const MeasurementWorkerOwnedDeliveryCheckpointMessage({
    required this.requestId,
    required this.sessionId,
    required this.isFinal,
  });

  final int requestId;
  final String sessionId;
  final bool isFinal;
}

final class MeasurementWorkerOwnedDeliveryDiscardMessage
    extends MeasurementWorkerOwnedDeliveryInboundMessage {
  const MeasurementWorkerOwnedDeliveryDiscardMessage({
    required this.requestId,
    required this.sessionId,
  });

  final int requestId;
  final String sessionId;
}

final class MeasurementWorkerOwnedDeliveryResetMessage
    extends MeasurementWorkerOwnedDeliveryInboundMessage {
  const MeasurementWorkerOwnedDeliveryResetMessage({
    required this.requestId,
    required this.reason,
  });

  final int requestId;
  final MeasurementOutboxPurgeReason reason;
}

final class MeasurementWorkerOwnedDeliveryShutdownMessage
    extends MeasurementWorkerOwnedDeliveryInboundMessage {
  const MeasurementWorkerOwnedDeliveryShutdownMessage({
    required this.requestId,
  });

  final int requestId;
}

/// Parsed worker-to-root event base type.
sealed class MeasurementWorkerOwnedDeliveryOutboundMessage {
  const MeasurementWorkerOwnedDeliveryOutboundMessage();
}

final class MeasurementWorkerOwnedDeliveryReadyMessage
    extends MeasurementWorkerOwnedDeliveryOutboundMessage {
  const MeasurementWorkerOwnedDeliveryReadyMessage({
    required this.commandPort,
    required this.workerIsolateId,
  });

  final Object? commandPort;
  final int workerIsolateId;
}

final class MeasurementWorkerOwnedDeliveryOpenedMessage
    extends MeasurementWorkerOwnedDeliveryOutboundMessage {
  const MeasurementWorkerOwnedDeliveryOpenedMessage({
    required this.requestId,
    required this.sessionId,
    required this.workerOwnedByteCount,
  });

  final int requestId;
  final String sessionId;
  final int workerOwnedByteCount;
}

final class MeasurementWorkerOwnedDeliveryOpenRejectedMessage
    extends MeasurementWorkerOwnedDeliveryOutboundMessage {
  const MeasurementWorkerOwnedDeliveryOpenRejectedMessage({
    required this.requestId,
    required this.outcome,
    required this.workerOwnedByteCount,
  });

  final int requestId;
  final MeasurementWorkerOpenSessionOutcome outcome;
  final int workerOwnedByteCount;
}

final class MeasurementWorkerOwnedDeliveryAppendAcknowledgedMessage
    extends MeasurementWorkerOwnedDeliveryOutboundMessage {
  const MeasurementWorkerOwnedDeliveryAppendAcknowledgedMessage({
    required this.sessionId,
    required this.outcome,
    required this.workerOwnedByteCount,
  });

  final String sessionId;
  final MeasurementWorkerAppendAcknowledgementOutcome outcome;
  final int workerOwnedByteCount;
}

final class MeasurementWorkerOwnedDeliveryCheckpointResultMessage
    extends MeasurementWorkerOwnedDeliveryOutboundMessage {
  const MeasurementWorkerOwnedDeliveryCheckpointResultMessage({
    required this.requestId,
    required this.outcome,
    required this.sequence,
    required this.isFinal,
    required this.workerOwnedByteCount,
  });

  final int requestId;
  final MeasurementWorkerOwnedDeliveryCheckpointOutcome outcome;
  final int? sequence;
  final bool? isFinal;
  final int workerOwnedByteCount;
}

final class MeasurementWorkerOwnedDeliveryDiscardResultMessage
    extends MeasurementWorkerOwnedDeliveryOutboundMessage {
  const MeasurementWorkerOwnedDeliveryDiscardResultMessage({
    required this.requestId,
    required this.outcome,
    required this.workerOwnedByteCount,
  });

  final int requestId;
  final MeasurementWorkerOwnedDeliveryDiscardOutcome outcome;
  final int workerOwnedByteCount;
}

final class MeasurementWorkerOwnedDeliveryResetResultMessage
    extends MeasurementWorkerOwnedDeliveryOutboundMessage {
  const MeasurementWorkerOwnedDeliveryResetResultMessage({
    required this.requestId,
    required this.outcome,
    required this.purgedRecordCount,
  });

  final int requestId;
  final MeasurementWorkerOwnedDeliveryResetOutcome outcome;
  final int purgedRecordCount;
}

final class MeasurementWorkerOwnedDeliveryShutdownResultMessage
    extends MeasurementWorkerOwnedDeliveryOutboundMessage {
  const MeasurementWorkerOwnedDeliveryShutdownResultMessage({
    required this.requestId,
    required this.outcome,
  });

  final int requestId;
  final MeasurementWorkerOwnedDeliveryShutdownOutcome outcome;
}

final class MeasurementWorkerOwnedDeliveryDebugMessage
    extends MeasurementWorkerOwnedDeliveryOutboundMessage {
  const MeasurementWorkerOwnedDeliveryDebugMessage({
    required this.stage,
    required this.workerIsolateId,
  });

  final MeasurementWorkerOwnedDeliveryDebugStage stage;
  final int workerIsolateId;
}

final class MeasurementWorkerOwnedDeliveryFatalMessage
    extends MeasurementWorkerOwnedDeliveryOutboundMessage {
  const MeasurementWorkerOwnedDeliveryFatalMessage();
}

/// Strict primitive-only protocol dedicated to the worker-owned delivery seam.
abstract final class MeasurementWorkerOwnedDeliveryProtocol {
  static const int _version = 1;
  static const int _register = 1;
  static const int _append = 2;
  static const int _checkpoint = 3;
  static const int _reset = 4;
  static const int _shutdown = 5;
  static const int _discard = 6;

  static const int _ready = 101;
  static const int _opened = 102;
  static const int _openRejected = 103;
  static const int _appendAcknowledged = 104;
  static const int _checkpointResult = 105;
  static const int _resetResult = 106;
  static const int _shutdownResult = 107;
  static const int _debug = 108;
  static const int _fatal = 109;
  static const int _discardResult = 110;

  static List<Object?> register({
    required int requestId,
    required MeasurementWorkerSessionRegistration registration,
  }) =>
      [_register, _version, requestId, registration.toWire()];

  static List<Object?> append({
    required String sessionId,
    required MeasurementWorkerAppendRecord record,
  }) =>
      [
        _append,
        _version,
        sessionId,
        record.routeIndex,
        record.monotonicTimestampMicros,
        record.value.wireCode,
      ];

  static List<Object?> checkpoint({
    required int requestId,
    required String sessionId,
    required bool isFinal,
  }) =>
      [_checkpoint, _version, requestId, sessionId, isFinal];

  static List<Object?> discard({
    required int requestId,
    required String sessionId,
  }) =>
      [_discard, _version, requestId, sessionId];

  static List<Object?> reset({
    required int requestId,
    required MeasurementOutboxPurgeReason reason,
  }) =>
      [_reset, _version, requestId, reason.index];

  static List<Object?> shutdown({required int requestId}) => [
        _shutdown,
        _version,
        requestId,
      ];

  static List<Object?> ready({
    required Object commandPort,
    required int workerIsolateId,
  }) =>
      [_ready, _version, commandPort, workerIsolateId];

  static List<Object?> opened({
    required int requestId,
    required String sessionId,
    required int workerOwnedByteCount,
  }) =>
      [_opened, _version, requestId, sessionId, workerOwnedByteCount];

  static List<Object?> openRejected({
    required int requestId,
    required MeasurementWorkerOpenSessionOutcome outcome,
    required int workerOwnedByteCount,
  }) =>
      [
        _openRejected,
        _version,
        requestId,
        outcome.wireCode,
        workerOwnedByteCount,
      ];

  static List<Object?> appendAcknowledged({
    required String sessionId,
    required MeasurementWorkerAppendAcknowledgementOutcome outcome,
    required int workerOwnedByteCount,
  }) =>
      [
        _appendAcknowledged,
        _version,
        sessionId,
        outcome.wireCode,
        workerOwnedByteCount,
      ];

  static List<Object?> checkpointResult({
    required int requestId,
    required MeasurementWorkerOwnedDeliveryCheckpointOutcome outcome,
    required int? sequence,
    required bool? isFinal,
    required int workerOwnedByteCount,
  }) =>
      [
        _checkpointResult,
        _version,
        requestId,
        outcome.wireCode,
        sequence,
        isFinal,
        workerOwnedByteCount,
      ];

  static List<Object?> discardResult({
    required int requestId,
    required MeasurementWorkerOwnedDeliveryDiscardOutcome outcome,
    required int workerOwnedByteCount,
  }) =>
      [
        _discardResult,
        _version,
        requestId,
        outcome.wireCode,
        workerOwnedByteCount,
      ];

  static List<Object?> resetResult({
    required int requestId,
    required MeasurementWorkerOwnedDeliveryResetOutcome outcome,
    required int purgedRecordCount,
  }) =>
      [
        _resetResult,
        _version,
        requestId,
        outcome.wireCode,
        purgedRecordCount,
      ];

  static List<Object?> shutdownResult({
    required int requestId,
    required MeasurementWorkerOwnedDeliveryShutdownOutcome outcome,
  }) =>
      [_shutdownResult, _version, requestId, outcome.wireCode];

  static List<Object?> debug({
    required MeasurementWorkerOwnedDeliveryDebugStage stage,
    required int workerIsolateId,
  }) =>
      [_debug, _version, stage.wireCode, workerIsolateId];

  static List<Object?> fatal() => [_fatal, _version];

  static MeasurementWorkerOwnedDeliveryInboundMessage decodeInbound(
    Object? raw,
  ) {
    final values = _requireList(raw);
    final tag = _requireIntAt(values, 0);
    _requireVersion(values);
    return switch (tag) {
      _register => MeasurementWorkerOwnedDeliveryRegisterMessage(
          requestId: _requirePositiveRequestId(values, expectedLength: 4),
          registration:
              MeasurementWorkerSessionRegistration.fromWire(values[3]),
        ),
      _append => _decodeAppend(values),
      _checkpoint => MeasurementWorkerOwnedDeliveryCheckpointMessage(
          requestId: _requirePositiveRequestId(values, expectedLength: 5),
          sessionId: _requireString(values[3]),
          isFinal: _requireBool(values[4]),
        ),
      _discard => MeasurementWorkerOwnedDeliveryDiscardMessage(
          requestId: _requirePositiveRequestId(values, expectedLength: 4),
          sessionId: _requireString(values[3]),
        ),
      _reset => MeasurementWorkerOwnedDeliveryResetMessage(
          requestId: _requirePositiveRequestId(values, expectedLength: 4),
          reason: _requirePurgeReason(_requireInt(values[3])),
        ),
      _shutdown => MeasurementWorkerOwnedDeliveryShutdownMessage(
          requestId: _requirePositiveRequestId(values, expectedLength: 3),
        ),
      _ => throw const MeasurementWorkerOwnedDeliveryProtocolException(
          'unknown_inbound_tag',
        ),
    };
  }

  static MeasurementWorkerOwnedDeliveryOutboundMessage decodeOutbound(
    Object? raw,
  ) {
    final values = _requireList(raw);
    final tag = _requireIntAt(values, 0);
    _requireVersion(values);
    return switch (tag) {
      _ready => MeasurementWorkerOwnedDeliveryReadyMessage(
          commandPort: _requireAt(values, 2, expectedLength: 4),
          workerIsolateId: _requireNonNegativeIntAt(values, 3),
        ),
      _opened => MeasurementWorkerOwnedDeliveryOpenedMessage(
          requestId: _requirePositiveRequestId(values, expectedLength: 5),
          sessionId: _requireString(values[3]),
          workerOwnedByteCount: _requireNonNegativeIntAt(values, 4),
        ),
      _openRejected => MeasurementWorkerOwnedDeliveryOpenRejectedMessage(
          requestId: _requirePositiveRequestId(values, expectedLength: 5),
          outcome: _requireOpenOutcome(_requireInt(values[3])),
          workerOwnedByteCount: _requireNonNegativeIntAt(values, 4),
        ),
      _appendAcknowledged =>
        MeasurementWorkerOwnedDeliveryAppendAcknowledgedMessage(
          sessionId: _requireStringAt(values, 2, expectedLength: 5),
          outcome: _requireAppendOutcome(_requireInt(values[3])),
          workerOwnedByteCount: _requireNonNegativeIntAt(values, 4),
        ),
      _checkpointResult =>
        MeasurementWorkerOwnedDeliveryCheckpointResultMessage(
          requestId: _requirePositiveRequestId(values, expectedLength: 7),
          outcome: _requireCheckpointOutcome(_requireInt(values[3])),
          sequence: _requireNullableNonNegativeInt(values[4]),
          isFinal: _requireNullableBool(values[5]),
          workerOwnedByteCount: _requireNonNegativeIntAt(values, 6),
        ),
      _discardResult => MeasurementWorkerOwnedDeliveryDiscardResultMessage(
          requestId: _requirePositiveRequestId(values, expectedLength: 5),
          outcome: _requireDiscardOutcome(_requireInt(values[3])),
          workerOwnedByteCount: _requireNonNegativeIntAt(values, 4),
        ),
      _resetResult => MeasurementWorkerOwnedDeliveryResetResultMessage(
          requestId: _requirePositiveRequestId(values, expectedLength: 5),
          outcome: _requireResetOutcome(_requireInt(values[3])),
          purgedRecordCount: _requireNonNegativeIntAt(values, 4),
        ),
      _shutdownResult => MeasurementWorkerOwnedDeliveryShutdownResultMessage(
          requestId: _requirePositiveRequestId(values, expectedLength: 4),
          outcome: _requireShutdownOutcome(_requireInt(values[3])),
        ),
      _debug => MeasurementWorkerOwnedDeliveryDebugMessage(
          stage: _requireDebugStage(_requireIntAt(values, 2)),
          workerIsolateId:
              _requireNonNegativeIntAt(values, 3, expectedLength: 4),
        ),
      _fatal => _decodeFatal(values),
      _ => throw const MeasurementWorkerOwnedDeliveryProtocolException(
          'unknown_outbound_tag',
        ),
    };
  }

  static MeasurementWorkerOwnedDeliveryAppendMessage _decodeAppend(
    List<Object?> values,
  ) {
    _requireLength(values, 6);
    return MeasurementWorkerOwnedDeliveryAppendMessage(
      sessionId: _requireString(values[2]),
      record: MeasurementWorkerAppendRecord(
        routeIndex: _requireInt(values[3]),
        monotonicTimestampMicros: _requireInt(values[4]),
        value: _requireAppendValue(_requireInt(values[5])),
      ),
    );
  }

  static MeasurementWorkerOwnedDeliveryFatalMessage _decodeFatal(
    List<Object?> values,
  ) {
    _requireLength(values, 2);
    return const MeasurementWorkerOwnedDeliveryFatalMessage();
  }
}

/// Thrown only for malformed primitive worker protocol values.
final class MeasurementWorkerOwnedDeliveryProtocolException
    implements Exception {
  /// Creates a stable protocol parse failure.
  const MeasurementWorkerOwnedDeliveryProtocolException(this.code);

  /// Machine-readable failure code.
  final String code;

  @override
  String toString() => 'MeasurementWorkerOwnedDeliveryProtocolException($code)';
}

List<Object?> _requireList(Object? value, {int? expectedLength}) {
  if (value is! List) {
    throw const MeasurementWorkerOwnedDeliveryProtocolException(
      'expected_list',
    );
  }
  final result = List<Object?>.from(value);
  if (expectedLength != null && result.length != expectedLength) {
    throw const MeasurementWorkerOwnedDeliveryProtocolException(
      'invalid_length',
    );
  }
  return result;
}

Object? _requireAt(List<Object?> values, int index, {int? expectedLength}) {
  if (expectedLength != null) _requireLength(values, expectedLength);
  if (index < 0 || index >= values.length) {
    throw const MeasurementWorkerOwnedDeliveryProtocolException(
      'missing_value',
    );
  }
  return values[index];
}

void _requireLength(List<Object?> values, int expectedLength) {
  if (values.length != expectedLength) {
    throw const MeasurementWorkerOwnedDeliveryProtocolException(
      'invalid_length',
    );
  }
}

void _requireVersion(List<Object?> values) {
  if (_requireIntAt(values, 1) != 1) {
    throw const MeasurementWorkerOwnedDeliveryProtocolException(
      'unsupported_version',
    );
  }
}

int _requirePositiveRequestId(
  List<Object?> values, {
  required int expectedLength,
}) {
  final value = _requireIntAt(values, 2, expectedLength: expectedLength);
  if (value <= 0) {
    throw const MeasurementWorkerOwnedDeliveryProtocolException(
      'invalid_request_id',
    );
  }
  return value;
}

int _requireIntAt(List<Object?> values, int index, {int? expectedLength}) =>
    _requireInt(_requireAt(values, index, expectedLength: expectedLength));

int _requireNonNegativeIntAt(
  List<Object?> values,
  int index, {
  int? expectedLength,
}) {
  final value = _requireIntAt(values, index, expectedLength: expectedLength);
  if (value < 0) {
    throw const MeasurementWorkerOwnedDeliveryProtocolException(
      'negative_integer',
    );
  }
  return value;
}

int _requireInt(Object? value) {
  if (value is! int) {
    throw const MeasurementWorkerOwnedDeliveryProtocolException(
      'expected_integer',
    );
  }
  return value;
}

String _requireStringAt(
  List<Object?> values,
  int index, {
  int? expectedLength,
}) =>
    _requireString(_requireAt(values, index, expectedLength: expectedLength));

String _requireString(Object? value) {
  if (value is! String) {
    throw const MeasurementWorkerOwnedDeliveryProtocolException(
      'expected_string',
    );
  }
  return value;
}

bool _requireBool(Object? value) {
  if (value is! bool) {
    throw const MeasurementWorkerOwnedDeliveryProtocolException(
      'expected_boolean',
    );
  }
  return value;
}

int? _requireNullableNonNegativeInt(Object? value) {
  if (value == null) return null;
  final result = _requireInt(value);
  if (result < 0) {
    throw const MeasurementWorkerOwnedDeliveryProtocolException(
      'negative_integer',
    );
  }
  return result;
}

bool? _requireNullableBool(Object? value) {
  if (value == null) return null;
  return _requireBool(value);
}

MeasurementWorkerAppendValue _requireAppendValue(int code) =>
    MeasurementWorkerAppendValue.fromWireCode(code) ??
    (throw const MeasurementWorkerOwnedDeliveryProtocolException(
      'invalid_append_value',
    ));

MeasurementWorkerOpenSessionOutcome _requireOpenOutcome(int code) =>
    MeasurementWorkerOpenSessionOutcome.fromWireCode(code) ??
    (throw const MeasurementWorkerOwnedDeliveryProtocolException(
      'invalid_open_outcome',
    ));

MeasurementWorkerAppendAcknowledgementOutcome _requireAppendOutcome(int code) =>
    MeasurementWorkerAppendAcknowledgementOutcome.fromWireCode(code) ??
    (throw const MeasurementWorkerOwnedDeliveryProtocolException(
      'invalid_append_outcome',
    ));

MeasurementWorkerOwnedDeliveryCheckpointOutcome _requireCheckpointOutcome(
  int code,
) =>
    MeasurementWorkerOwnedDeliveryCheckpointOutcome.fromWireCode(code) ??
    (throw const MeasurementWorkerOwnedDeliveryProtocolException(
      'invalid_checkpoint_outcome',
    ));

MeasurementWorkerOwnedDeliveryDiscardOutcome _requireDiscardOutcome(int code) =>
    MeasurementWorkerOwnedDeliveryDiscardOutcome.fromWireCode(code) ??
    (throw const MeasurementWorkerOwnedDeliveryProtocolException(
      'invalid_discard_outcome',
    ));

MeasurementWorkerOwnedDeliveryResetOutcome _requireResetOutcome(int code) =>
    MeasurementWorkerOwnedDeliveryResetOutcome.fromWireCode(code) ??
    (throw const MeasurementWorkerOwnedDeliveryProtocolException(
      'invalid_reset_outcome',
    ));

MeasurementWorkerOwnedDeliveryShutdownOutcome _requireShutdownOutcome(
  int code,
) =>
    MeasurementWorkerOwnedDeliveryShutdownOutcome.fromWireCode(code) ??
    (throw const MeasurementWorkerOwnedDeliveryProtocolException(
      'invalid_shutdown_outcome',
    ));

MeasurementWorkerOwnedDeliveryDebugStage _requireDebugStage(int code) =>
    MeasurementWorkerOwnedDeliveryDebugStage.fromWireCode(code) ??
    (throw const MeasurementWorkerOwnedDeliveryProtocolException(
      'invalid_debug_stage',
    ));

MeasurementOutboxPurgeReason _requirePurgeReason(int index) {
  if (index < 0 || index >= MeasurementOutboxPurgeReason.values.length) {
    throw const MeasurementWorkerOwnedDeliveryProtocolException(
      'invalid_purge_reason',
    );
  }
  return MeasurementOutboxPurgeReason.values[index];
}
