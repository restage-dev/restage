import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Version of the closed primitive/typed-data worker protocol.
const int kMeasurementWorkerProtocolVersion = 1;

/// Largest number of sessions one configured worker may own.
const int kMeasurementWorkerMaximumSessionCount = 64;

/// Largest precomputed route table admitted for one worker session.
const int kMeasurementWorkerMaximumRouteCount = 1024;

/// Largest number of presented point facts one worker session may retain.
const int kMeasurementWorkerMaximumPresentedPointCount = 1024;

/// Largest number of interaction counters one worker session may retain.
const int kMeasurementWorkerMaximumInteractionCounterCount = 256;

/// Maximum retained count for one worker-side fact or truncation dimension.
const int kMeasurementWorkerMaximumCounterValue = 65535;

/// Largest number of missingness entries one worker session may retain.
const int kMeasurementWorkerMaximumMissingnessEntryCount = 256;

/// Largest byte payload accepted for an exact published-context reference.
const int kMeasurementWorkerMaximumPublicationContextBytes = 64 * 1024;

/// Largest portable monotonic timestamp or sequence value.
const int kMeasurementWorkerMaximumPortableInteger = 9007199254740991;

/// Closed values accepted by a capture append.
enum MeasurementWorkerAppendValue {
  /// One exact point was successfully presented.
  presentation(1),

  /// One interaction was observed for an already precomputed point route.
  interaction(2);

  const MeasurementWorkerAppendValue(this.wireCode);

  /// Primitive protocol spelling.
  final int wireCode;

  static MeasurementWorkerAppendValue? fromWireCode(int value) {
    for (final candidate in values) {
      if (candidate.wireCode == value) return candidate;
    }
    return null;
  }
}

/// Synchronous UI-side outcome of attempting one append handoff.
enum MeasurementWorkerAppendOutcome {
  /// The record consumed one bounded handoff credit.
  accepted,

  /// No handoff credit was available, so no message was sent.
  saturated,

  /// The worker is unavailable or has crashed, so no message was sent.
  unavailable,

  /// The session is finalizing or finalized, so no message was sent.
  finalized,

  /// The caller supplied a record that is not valid for this session.
  invalid,
}

/// Worker-side result acknowledged after an accepted append is consumed.
enum MeasurementWorkerAppendAcknowledgementOutcome {
  /// The worker retained the append in its bounded aggregate state.
  recorded(1),

  /// The worker retained typed truncation rather than the appended fact value.
  truncated(2),

  /// The worker rejected a malformed or non-monotonic append.
  rejected(3);

  const MeasurementWorkerAppendAcknowledgementOutcome(this.wireCode);

  /// Primitive protocol spelling.
  final int wireCode;

  static MeasurementWorkerAppendAcknowledgementOutcome? fromWireCode(
    int value,
  ) {
    for (final candidate in values) {
      if (candidate.wireCode == value) return candidate;
    }
    return null;
  }
}

/// Immutable compact record accepted at the UI capture edge.
///
/// It deliberately carries only a precomputed route index, monotonic time, and
/// a closed value. It cannot carry event names, maps, callback arguments,
/// identities supplied by customers, codecs, or transport data.
@immutable
final class MeasurementWorkerAppendRecord {
  /// Creates one compact append record.
  MeasurementWorkerAppendRecord({
    required this.routeIndex,
    required this.monotonicTimestampMicros,
    required this.value,
  }) {
    if (routeIndex < 0 ||
        monotonicTimestampMicros < 0 ||
        monotonicTimestampMicros > kMeasurementWorkerMaximumPortableInteger) {
      throw ArgumentError('Invalid compact measurement append record');
    }
  }

  /// Precomputed immutable index into the session route table.
  final int routeIndex;

  /// Monotonic timestamp captured at the observation edge.
  final int monotonicTimestampMicros;

  /// Closed observation value.
  final MeasurementWorkerAppendValue value;
}

/// Fixed limits for one worker-owned capture session.
@immutable
final class MeasurementWorkerSessionLimits {
  /// Creates one closed set of worker session limits.
  const MeasurementWorkerSessionLimits({
    required this.maximumCounterValue,
    required this.maximumPresentedPoints,
    required this.maximumInteractionCounters,
    required this.maximumMissingnessEntries,
  })  : assert(
          maximumCounterValue > 0 &&
              maximumCounterValue <= kMeasurementWorkerMaximumCounterValue,
        ),
        assert(
          maximumPresentedPoints > 0 &&
              maximumPresentedPoints <=
                  kMeasurementWorkerMaximumPresentedPointCount,
        ),
        assert(
          maximumInteractionCounters >= 0 &&
              maximumInteractionCounters <=
                  kMeasurementWorkerMaximumInteractionCounterCount,
        ),
        assert(
          maximumMissingnessEntries >= 0 &&
              maximumMissingnessEntries <=
                  kMeasurementWorkerMaximumMissingnessEntryCount,
        );

  /// Saturation ceiling for each retained counter.
  final int maximumCounterValue;

  /// Maximum distinct successfully presented points.
  final int maximumPresentedPoints;

  /// Maximum retained interaction counters.
  final int maximumInteractionCounters;

  /// Maximum aggregate missingness states.
  final int maximumMissingnessEntries;

  List<Object?> toWire() => [
        maximumCounterValue,
        maximumPresentedPoints,
        maximumInteractionCounters,
        maximumMissingnessEntries,
      ];

  static MeasurementWorkerSessionLimits fromWire(Object? value) {
    final values = _requireList(value, expectedLength: 4);
    final result = MeasurementWorkerSessionLimits(
      maximumCounterValue: _requireInt(values[0]),
      maximumPresentedPoints: _requireInt(values[1]),
      maximumInteractionCounters: _requireInt(values[2]),
      maximumMissingnessEntries: _requireInt(values[3]),
    );
    if (result.maximumCounterValue <= 0 ||
        result.maximumCounterValue > kMeasurementWorkerMaximumCounterValue ||
        result.maximumPresentedPoints <= 0 ||
        result.maximumPresentedPoints >
            kMeasurementWorkerMaximumPresentedPointCount ||
        result.maximumInteractionCounters < 0 ||
        result.maximumInteractionCounters >
            kMeasurementWorkerMaximumInteractionCounterCount ||
        result.maximumMissingnessEntries < 0 ||
        result.maximumMissingnessEntries >
            kMeasurementWorkerMaximumMissingnessEntryCount) {
      throw const MeasurementWorkerProtocolException('invalid_session_limits');
    }
    return result;
  }
}

/// Immutable occurrence and lineage selected before the capture edge.
@immutable
final class MeasurementWorkerRouteIdentity {
  /// Creates one precomputed route identity.
  const MeasurementWorkerRouteIdentity({
    required this.occurrenceId,
    required this.lineageId,
  });

  /// Exact occurrence digest selected by the compiler/runtime setup path.
  final String occurrenceId;

  /// Exact durable lineage selected by the compiler/runtime setup path.
  final String lineageId;

  List<Object?> toWire() => [occurrenceId, lineageId];

  static MeasurementWorkerRouteIdentity fromWire(Object? value) {
    final values = _requireList(value, expectedLength: 2);
    return MeasurementWorkerRouteIdentity(
      occurrenceId: _requireString(values[0]),
      lineageId: _requireString(values[1]),
    );
  }
}

/// Immutable registration material sent before a session can append.
///
/// The context is already canonical bytes. This class neither decodes nor
/// encodes it on the UI isolate; strict validation and canonical frame/request
/// construction are owned by the worker.
@immutable
final class MeasurementWorkerSessionRegistration {
  /// Creates one session registration.
  MeasurementWorkerSessionRegistration({
    required this.sessionId,
    required this.captureSessionNonce,
    required List<int> publicationContextCanonicalBytes,
    required List<MeasurementWorkerRouteIdentity> routes,
    required this.limits,
    required this.firstSequence,
  })  : _publicationContextCanonicalBytes = Uint8List.fromList(
          publicationContextCanonicalBytes,
        ),
        routes = List.unmodifiable(routes) {
    if (!_isOpaqueIdentifier(sessionId) ||
        !_isOpaqueIdentifier(captureSessionNonce) ||
        _publicationContextCanonicalBytes.isEmpty ||
        _publicationContextCanonicalBytes.length >
            kMeasurementWorkerMaximumPublicationContextBytes ||
        this.routes.length > kMeasurementWorkerMaximumRouteCount ||
        firstSequence <= 0 ||
        firstSequence > kMeasurementWorkerMaximumPortableInteger) {
      throw ArgumentError('Invalid measurement worker session registration');
    }
  }

  /// Opaque capture-session coordinate.
  final String sessionId;

  /// Opaque retry nonce, not a subject identity.
  final String captureSessionNonce;

  final Uint8List _publicationContextCanonicalBytes;

  /// Exact publication context bytes, defensively copied for callers.
  Uint8List get publicationContextCanonicalBytes =>
      Uint8List.fromList(_publicationContextCanonicalBytes);

  /// Immutable precomputed route table identities.
  final List<MeasurementWorkerRouteIdentity> routes;

  /// Closed bounded session limits.
  final MeasurementWorkerSessionLimits limits;

  /// Sequence used for the first prepared frame.
  final int firstSequence;

  List<Object?> toWire() => [
        sessionId,
        captureSessionNonce,
        Uint8List.fromList(_publicationContextCanonicalBytes),
        [for (final route in routes) route.toWire()],
        limits.toWire(),
        firstSequence,
      ];

  static MeasurementWorkerSessionRegistration fromWire(Object? value) {
    final values = _requireList(value, expectedLength: 6);
    final rawRoutes = _requireList(values[3]);
    return MeasurementWorkerSessionRegistration(
      sessionId: _requireString(values[0]),
      captureSessionNonce: _requireString(values[1]),
      publicationContextCanonicalBytes: _requireBytes(values[2]),
      routes: [
        for (final route in rawRoutes)
          MeasurementWorkerRouteIdentity.fromWire(route),
      ],
      limits: MeasurementWorkerSessionLimits.fromWire(values[4]),
      firstSequence: _requireInt(values[5]),
    );
  }
}

/// Per-runtime fixed capacities for the native worker kernel.
@immutable
final class MeasurementWorkerRuntimeConfiguration {
  /// Creates one bounded native worker configuration.
  const MeasurementWorkerRuntimeConfiguration({
    required this.maximumSessions,
    required this.maximumInFlightAppends,
    required this.maximumRetainedPreparedBatches,
  })  : assert(
          maximumSessions > 0 &&
              maximumSessions <= kMeasurementWorkerMaximumSessionCount,
        ),
        assert(maximumInFlightAppends > 0),
        assert(maximumRetainedPreparedBatches > 0);

  /// Maximum concurrently registered or registering sessions.
  final int maximumSessions;

  /// Maximum unacknowledged append messages allowed onto the command port.
  final int maximumInFlightAppends;

  /// Maximum immutable prepared batches retained for retry/release.
  final int maximumRetainedPreparedBatches;

  List<Object?> toWorkerBootstrapWire() => [
        maximumSessions,
        maximumRetainedPreparedBatches,
      ];
}

/// Immutable prepared output owned by the worker until [releasePreparedBatch].
@immutable
final class MeasurementWorkerPreparedBatch {
  MeasurementWorkerPreparedBatch({
    required this.batchId,
    required this.sessionId,
    required this.isFinal,
    required this.sequence,
    required List<int> canonicalFrameBytes,
    required List<int> canonicalRequestBytes,
    required this.canonicalRequestBase64,
    required this.frameSha256,
    required this.requestSha256,
    required this.ownedByteCount,
  })  : _canonicalFrameBytes = Uint8List.fromList(canonicalFrameBytes),
        _canonicalRequestBytes = Uint8List.fromList(canonicalRequestBytes);

  /// Stable worker batch coordinate.
  final String batchId;

  /// Source worker session coordinate.
  final String sessionId;

  /// Whether this prepared snapshot terminally finalizes its session.
  final bool isFinal;

  /// Monotone capture-frame sequence.
  final int sequence;

  final Uint8List _canonicalFrameBytes;
  final Uint8List _canonicalRequestBytes;

  /// Exact canonical frame bytes, defensively copied for the delivery seam.
  Uint8List get canonicalFrameBytes => Uint8List.fromList(_canonicalFrameBytes);

  /// Exact canonical request bytes, defensively copied for the delivery seam.
  Uint8List get canonicalRequestBytes =>
      Uint8List.fromList(_canonicalRequestBytes);

  /// Exact unpadded request carrier ready for a later delivery owner.
  final String canonicalRequestBase64;

  /// SHA-256 of [canonicalFrameBytes].
  final String frameSha256;

  /// SHA-256 of [canonicalRequestBytes].
  final String requestSha256;

  /// Deterministic structural bytes retained by this worker-owned batch.
  final int ownedByteCount;

  List<Object?> toWire() => [
        batchId,
        sessionId,
        isFinal,
        sequence,
        Uint8List.fromList(_canonicalFrameBytes),
        Uint8List.fromList(_canonicalRequestBytes),
        canonicalRequestBase64,
        frameSha256,
        requestSha256,
        ownedByteCount,
      ];

  static MeasurementWorkerPreparedBatch fromWire(Object? value) {
    final values = _requireList(value, expectedLength: 10);
    return MeasurementWorkerPreparedBatch(
      batchId: _requireString(values[0]),
      sessionId: _requireString(values[1]),
      isFinal: _requireBool(values[2]),
      sequence: _requireInt(values[3]),
      canonicalFrameBytes: _requireBytes(values[4]),
      canonicalRequestBytes: _requireBytes(values[5]),
      canonicalRequestBase64: _requireString(values[6]),
      frameSha256: _requireString(values[7]),
      requestSha256: _requireString(values[8]),
      ownedByteCount: _requireInt(values[9]),
    );
  }
}

/// One worker acknowledgement for an accepted append message.
@immutable
final class MeasurementWorkerAppendAcknowledgement {
  /// Creates one append acknowledgement.
  const MeasurementWorkerAppendAcknowledgement({
    required this.sessionId,
    required this.outcome,
    required this.workerOwnedByteCount,
  });

  /// Session that consumed the bounded handoff credit.
  final String sessionId;

  /// Worker-side aggregation result.
  final MeasurementWorkerAppendAcknowledgementOutcome outcome;

  /// Structural worker-owned bytes after this acknowledgement.
  final int workerOwnedByteCount;
}

/// Result of registering one worker session.
@immutable
final class MeasurementWorkerOpenSessionResult {
  const MeasurementWorkerOpenSessionResult._({
    required this.outcome,
    required this.session,
    required this.workerOwnedByteCount,
  });

  /// The worker's closed registration result.
  final MeasurementWorkerOpenSessionOutcome outcome;

  /// Active session only when [outcome] is [MeasurementWorkerOpenSessionOutcome.opened].
  final MeasurementWorkerSession? session;

  /// Structural worker-owned bytes after the result.
  final int workerOwnedByteCount;

  factory MeasurementWorkerOpenSessionResult.opened({
    required MeasurementWorkerSession session,
    required int workerOwnedByteCount,
  }) =>
      MeasurementWorkerOpenSessionResult._(
        outcome: MeasurementWorkerOpenSessionOutcome.opened,
        session: session,
        workerOwnedByteCount: workerOwnedByteCount,
      );

  factory MeasurementWorkerOpenSessionResult.of(
    MeasurementWorkerOpenSessionOutcome outcome, {
    required int workerOwnedByteCount,
  }) =>
      MeasurementWorkerOpenSessionResult._(
        outcome: outcome,
        session: null,
        workerOwnedByteCount: workerOwnedByteCount,
      );
}

/// Closed results for worker session registration.
enum MeasurementWorkerOpenSessionOutcome {
  /// The worker owns a newly active session.
  opened(1),

  /// The configured worker-session capacity was exhausted.
  saturated(2),

  /// The worker is absent or crashed.
  unavailable(3),

  /// The registration did not satisfy the closed protocol.
  invalid(4);

  const MeasurementWorkerOpenSessionOutcome(this.wireCode);

  /// Primitive protocol spelling.
  final int wireCode;

  static MeasurementWorkerOpenSessionOutcome? fromWireCode(int value) {
    for (final candidate in values) {
      if (candidate.wireCode == value) return candidate;
    }
    return null;
  }
}

/// Closed result of checkpointing, finalizing, or retrying a prepared batch.
enum MeasurementWorkerBatchOutcome {
  /// An immutable prepared batch is available.
  prepared(1),

  /// The worker cannot retain another immutable prepared batch.
  saturated(2),

  /// The worker is absent or crashed.
  unavailable(3),

  /// The target session was already finalized.
  finalized(4),

  /// The requested retained batch has already been released or never existed.
  unknownBatch(5),

  /// The command did not satisfy the closed protocol.
  invalid(6);

  const MeasurementWorkerBatchOutcome(this.wireCode);

  /// Primitive protocol spelling.
  final int wireCode;

  static MeasurementWorkerBatchOutcome? fromWireCode(int value) {
    for (final candidate in values) {
      if (candidate.wireCode == value) return candidate;
    }
    return null;
  }
}

/// Immutable result returned by a checkpoint, teardown, or retry barrier.
@immutable
final class MeasurementWorkerBatchResult {
  const MeasurementWorkerBatchResult._({
    required this.outcome,
    required this.batch,
    required this.workerOwnedByteCount,
  });

  /// Closed barrier result.
  final MeasurementWorkerBatchOutcome outcome;

  /// Prepared bytes only when [outcome] is [MeasurementWorkerBatchOutcome.prepared].
  final MeasurementWorkerPreparedBatch? batch;

  /// Structural worker-owned bytes after this result.
  final int workerOwnedByteCount;

  factory MeasurementWorkerBatchResult.prepared({
    required MeasurementWorkerPreparedBatch batch,
    required int workerOwnedByteCount,
  }) =>
      MeasurementWorkerBatchResult._(
        outcome: MeasurementWorkerBatchOutcome.prepared,
        batch: batch,
        workerOwnedByteCount: workerOwnedByteCount,
      );

  factory MeasurementWorkerBatchResult.of(
    MeasurementWorkerBatchOutcome outcome, {
    required int workerOwnedByteCount,
  }) =>
      MeasurementWorkerBatchResult._(
        outcome: outcome,
        batch: null,
        workerOwnedByteCount: workerOwnedByteCount,
      );
}

/// Closed result of releasing an acknowledged prepared batch.
enum MeasurementWorkerReleaseOutcome {
  /// The retained worker copy was released.
  released(1),

  /// No retained batch matched the supplied coordinate.
  unknownBatch(2),

  /// The worker is absent or crashed.
  unavailable(3);

  const MeasurementWorkerReleaseOutcome(this.wireCode);

  /// Primitive protocol spelling.
  final int wireCode;

  static MeasurementWorkerReleaseOutcome? fromWireCode(int value) {
    for (final candidate in values) {
      if (candidate.wireCode == value) return candidate;
    }
    return null;
  }
}

/// Immutable release result with deterministic ownership accounting.
@immutable
final class MeasurementWorkerReleaseResult {
  /// Creates one release result.
  const MeasurementWorkerReleaseResult({
    required this.outcome,
    required this.workerOwnedByteCount,
  });

  /// Closed release result.
  final MeasurementWorkerReleaseOutcome outcome;

  /// Structural worker-owned bytes after the release attempt.
  final int workerOwnedByteCount;
}

/// Closed result of orderly worker shutdown.
enum MeasurementWorkerShutdownOutcome {
  /// All active sessions were finalized in deterministic session-id order.
  closed(1),

  /// Retained prepared-batch capacity prevented a lossless shutdown.
  saturated(2),

  /// The worker is absent or crashed.
  unavailable(3);

  const MeasurementWorkerShutdownOutcome(this.wireCode);

  /// Primitive protocol spelling.
  final int wireCode;

  static MeasurementWorkerShutdownOutcome? fromWireCode(int value) {
    for (final candidate in values) {
      if (candidate.wireCode == value) return candidate;
    }
    return null;
  }
}

/// Immutable shutdown completion result.
@immutable
final class MeasurementWorkerShutdownResult {
  /// Creates one shutdown result.
  MeasurementWorkerShutdownResult({
    required this.outcome,
    required List<MeasurementWorkerPreparedBatch> preparedBatches,
    required this.workerOwnedByteCount,
  }) : preparedBatches = List.unmodifiable(preparedBatches);

  /// Closed shutdown result.
  final MeasurementWorkerShutdownOutcome outcome;

  /// Final batches prepared in deterministic session-id order.
  final List<MeasurementWorkerPreparedBatch> preparedBatches;

  /// Structural worker-owned bytes after shutdown.
  final int workerOwnedByteCount;
}

/// Private implementation contract shared by the native and unavailable façades.
abstract interface class MeasurementWorkerRuntimeState {
  /// Whether the worker can still accept commands.
  bool get isAvailable;

  /// Deterministic structural worker-owned bytes last reported by the worker.
  int get workerOwnedByteCount;

  /// Number of native isolates spawned for this configured runtime.
  int get debugWorkerSpawnCount;

  /// Acknowledgements that replenish UI append credits.
  Stream<MeasurementWorkerAppendAcknowledgement> get appendAcknowledgements;

  /// Registers one bounded session before any append is possible.
  Future<MeasurementWorkerOpenSessionResult> openSession(
    MeasurementWorkerSessionRegistration registration,
  );

  /// Retrieves a retained immutable batch for byte-identical retry.
  Future<MeasurementWorkerBatchResult> retryPreparedBatch(String batchId);

  /// Releases the worker-owned batch copy after downstream durable ownership.
  Future<MeasurementWorkerReleaseResult> releasePreparedBatch(String batchId);

  /// Finalizes active sessions through ordered barriers and closes the worker.
  Future<MeasurementWorkerShutdownResult> shutdown();

  /// Test-only crash control used to prove fail-closed propagation.
  void debugKillWorkerForTesting();
}

/// Internal active session contract.
abstract interface class MeasurementWorkerSessionState {
  MeasurementWorkerAppendOutcome append(MeasurementWorkerAppendRecord record);

  Future<MeasurementWorkerBatchResult> checkpoint();

  Future<MeasurementWorkerBatchResult> teardown();
}

/// Public handle for one worker-owned session.
@immutable
final class MeasurementWorkerSession {
  /// Creates an internal session handle after worker registration succeeds.
  const MeasurementWorkerSession.internal(this._state, this.sessionId);

  final MeasurementWorkerSessionState _state;

  /// Opaque session coordinate.
  final String sessionId;

  /// Synchronously hands one compact record to the bounded worker port.
  MeasurementWorkerAppendOutcome append(MeasurementWorkerAppendRecord record) =>
      _state.append(record);

  /// Orders a nonterminal checkpoint after prior appends.
  Future<MeasurementWorkerBatchResult> checkpoint() => _state.checkpoint();

  /// Orders finalization after prior appends and rejects later appends locally.
  Future<MeasurementWorkerBatchResult> teardown() => _state.teardown();
}

/// Platform implementation result before the public runtime wrapper is created.
@immutable
final class MeasurementWorkerRuntimeLaunchResult {
  const MeasurementWorkerRuntimeLaunchResult._({
    required this.state,
    required this.unavailableReason,
  });

  /// Live native state when startup succeeds.
  final MeasurementWorkerRuntimeState? state;

  /// Closed fail-closed reason when isolates are unavailable.
  final String? unavailableReason;

  factory MeasurementWorkerRuntimeLaunchResult.started(
    MeasurementWorkerRuntimeState state,
  ) =>
      MeasurementWorkerRuntimeLaunchResult._(
        state: state,
        unavailableReason: null,
      );

  factory MeasurementWorkerRuntimeLaunchResult.unavailable(String reason) =>
      MeasurementWorkerRuntimeLaunchResult._(
        state: null,
        unavailableReason: reason,
      );
}

/// Thrown only while parsing a malformed primitive worker message.
final class MeasurementWorkerProtocolException implements Exception {
  /// Creates one closed protocol parse failure.
  const MeasurementWorkerProtocolException(this.code);

  /// Stable machine-readable rejection code.
  final String code;

  @override
  String toString() => 'MeasurementWorkerProtocolException($code)';
}

/// Closed primitive and typed-data messages shared by the UI and worker isolates.
abstract final class MeasurementWorkerProtocol {
  static const int _ready = 1;
  static const int _register = 2;
  static const int _append = 3;
  static const int _checkpoint = 4;
  static const int _teardown = 5;
  static const int _retry = 6;
  static const int _release = 7;
  static const int _shutdown = 8;
  static const int _shutdownAcknowledged = 9;

  static const int _opened = 101;
  static const int _openRejected = 102;
  static const int _appendAcknowledged = 103;
  static const int _batchResult = 104;
  static const int _releaseResult = 105;
  static const int _shutdownResult = 106;
  static const int _fatal = 107;

  /// Builds one primitive bootstrap message. [commandPort] is a [SendPort] only
  /// at the native boundary; this protocol library does not import dart:isolate.
  static List<Object?> ready(Object commandPort) => [
        _ready,
        kMeasurementWorkerProtocolVersion,
        commandPort,
      ];

  /// Builds a closed registration message.
  static List<Object?> register({
    required int requestId,
    required MeasurementWorkerSessionRegistration registration,
  }) =>
      [
        _register,
        kMeasurementWorkerProtocolVersion,
        requestId,
        registration.toWire(),
      ];

  /// Builds the only UI hot-path command: compact primitives, no codec/hash.
  static List<Object?> append({
    required String sessionId,
    required MeasurementWorkerAppendRecord record,
  }) =>
      [
        _append,
        kMeasurementWorkerProtocolVersion,
        sessionId,
        record.routeIndex,
        record.monotonicTimestampMicros,
        record.value.wireCode,
      ];

  /// Builds one ordered checkpoint barrier.
  static List<Object?> checkpoint({
    required int requestId,
    required String sessionId,
  }) =>
      [_checkpoint, kMeasurementWorkerProtocolVersion, requestId, sessionId];

  /// Builds one ordered finalization barrier.
  static List<Object?> teardown({
    required int requestId,
    required String sessionId,
  }) =>
      [_teardown, kMeasurementWorkerProtocolVersion, requestId, sessionId];

  /// Builds one byte-identical retry request.
  static List<Object?> retry({
    required int requestId,
    required String batchId,
  }) =>
      [_retry, kMeasurementWorkerProtocolVersion, requestId, batchId];

  /// Builds one durable-ownership release request.
  static List<Object?> release({
    required int requestId,
    required String batchId,
  }) =>
      [_release, kMeasurementWorkerProtocolVersion, requestId, batchId];

  /// Builds one ordered shutdown barrier.
  static List<Object?> shutdown({required int requestId}) => [
        _shutdown,
        kMeasurementWorkerProtocolVersion,
        requestId,
      ];

  /// Acknowledges receipt of the terminal shutdown result before the native
  /// worker closes its command port.
  static List<Object?> shutdownAcknowledged({required int requestId}) => [
        _shutdownAcknowledged,
        kMeasurementWorkerProtocolVersion,
        requestId,
      ];

  /// Builds a worker-ready response.
  static List<Object?> opened({
    required int requestId,
    required String sessionId,
    required int workerOwnedByteCount,
  }) =>
      [
        _opened,
        kMeasurementWorkerProtocolVersion,
        requestId,
        sessionId,
        workerOwnedByteCount,
      ];

  /// Builds a worker registration rejection response.
  static List<Object?> openRejected({
    required int requestId,
    required MeasurementWorkerOpenSessionOutcome outcome,
    required int workerOwnedByteCount,
  }) =>
      [
        _openRejected,
        kMeasurementWorkerProtocolVersion,
        requestId,
        outcome.wireCode,
        workerOwnedByteCount,
      ];

  /// Builds one worker append acknowledgement.
  static List<Object?> appendAcknowledged({
    required String sessionId,
    required MeasurementWorkerAppendAcknowledgementOutcome outcome,
    required int workerOwnedByteCount,
  }) =>
      [
        _appendAcknowledged,
        kMeasurementWorkerProtocolVersion,
        sessionId,
        outcome.wireCode,
        workerOwnedByteCount,
      ];

  /// Builds one prepared/rejected barrier result.
  static List<Object?> batchResult({
    required int requestId,
    required MeasurementWorkerBatchOutcome outcome,
    required MeasurementWorkerPreparedBatch? batch,
    required int workerOwnedByteCount,
  }) =>
      [
        _batchResult,
        kMeasurementWorkerProtocolVersion,
        requestId,
        outcome.wireCode,
        batch?.toWire(),
        workerOwnedByteCount,
      ];

  /// Builds one prepared-batch release result.
  static List<Object?> releaseResult({
    required int requestId,
    required MeasurementWorkerReleaseOutcome outcome,
    required int workerOwnedByteCount,
  }) =>
      [
        _releaseResult,
        kMeasurementWorkerProtocolVersion,
        requestId,
        outcome.wireCode,
        workerOwnedByteCount,
      ];

  /// Builds one orderly shutdown completion result.
  static List<Object?> shutdownResult({
    required int requestId,
    required MeasurementWorkerShutdownOutcome outcome,
    required int workerOwnedByteCount,
  }) =>
      [
        _shutdownResult,
        kMeasurementWorkerProtocolVersion,
        requestId,
        outcome.wireCode,
        workerOwnedByteCount,
      ];

  /// Builds one generic fail-closed worker-failure notification.
  static List<Object?> fatal() => [_fatal, kMeasurementWorkerProtocolVersion];

  /// Strictly parses a UI-to-worker primitive message.
  static MeasurementWorkerInboundMessage decodeInbound(Object? raw) {
    final values = _requireList(raw);
    final tag = _requireIntAt(values, 0);
    _requireVersion(values);
    return switch (tag) {
      _register => MeasurementWorkerRegisterMessage(
          requestId: _requirePositiveRequestId(values, expectedLength: 4),
          registration:
              MeasurementWorkerSessionRegistration.fromWire(values[3]),
        ),
      _append => _decodeAppend(values),
      _checkpoint => MeasurementWorkerCheckpointMessage(
          requestId: _requirePositiveRequestId(values, expectedLength: 4),
          sessionId: _requireString(values[3]),
        ),
      _teardown => MeasurementWorkerTeardownMessage(
          requestId: _requirePositiveRequestId(values, expectedLength: 4),
          sessionId: _requireString(values[3]),
        ),
      _retry => MeasurementWorkerRetryMessage(
          requestId: _requirePositiveRequestId(values, expectedLength: 4),
          batchId: _requireString(values[3]),
        ),
      _release => MeasurementWorkerReleaseMessage(
          requestId: _requirePositiveRequestId(values, expectedLength: 4),
          batchId: _requireString(values[3]),
        ),
      _shutdown => MeasurementWorkerShutdownMessage(
          requestId: _requirePositiveRequestId(values, expectedLength: 3),
        ),
      _shutdownAcknowledged => MeasurementWorkerShutdownAcknowledgedMessage(
          requestId: _requirePositiveRequestId(values, expectedLength: 3),
        ),
      _ => throw const MeasurementWorkerProtocolException('unknown_command'),
    };
  }

  /// Strictly parses a worker-to-UI primitive message.
  static MeasurementWorkerOutboundMessage decodeOutbound(Object? raw) {
    final values = _requireList(raw);
    final tag = _requireIntAt(values, 0);
    _requireVersion(values);
    return switch (tag) {
      _ready => MeasurementWorkerReadyMessage(
          commandPort: _valueAt(values, 2, expectedLength: 3),
        ),
      _opened => MeasurementWorkerOpenedMessage(
          requestId: _requirePositiveRequestId(values, expectedLength: 5),
          sessionId: _requireString(values[3]),
          workerOwnedByteCount: _requireNonNegativeInt(values[4]),
        ),
      _openRejected => MeasurementWorkerOpenRejectedMessage(
          requestId: _requirePositiveRequestId(values, expectedLength: 5),
          outcome: _requireOpenOutcome(values[3]),
          workerOwnedByteCount: _requireNonNegativeInt(values[4]),
        ),
      _appendAcknowledged => MeasurementWorkerAppendAcknowledgedMessage(
          sessionId: _requireStringAt(values, 2, expectedLength: 5),
          outcome: _requireAppendAcknowledgementOutcome(values[3]),
          workerOwnedByteCount: _requireNonNegativeInt(values[4]),
        ),
      _batchResult => MeasurementWorkerBatchResultMessage(
          requestId: _requirePositiveRequestId(values, expectedLength: 6),
          outcome: _requireBatchOutcome(values[3]),
          batch: values[4] == null
              ? null
              : MeasurementWorkerPreparedBatch.fromWire(values[4]),
          workerOwnedByteCount: _requireNonNegativeInt(values[5]),
        ),
      _releaseResult => MeasurementWorkerReleaseResultMessage(
          requestId: _requirePositiveRequestId(values, expectedLength: 5),
          outcome: _requireReleaseOutcome(values[3]),
          workerOwnedByteCount: _requireNonNegativeInt(values[4]),
        ),
      _shutdownResult => MeasurementWorkerShutdownResultMessage(
          requestId: _requirePositiveRequestId(values, expectedLength: 5),
          outcome: _requireShutdownOutcome(values[3]),
          workerOwnedByteCount: _requireNonNegativeInt(values[4]),
        ),
      _fatal => _decodeFatal(values),
      _ => throw const MeasurementWorkerProtocolException('unknown_event'),
    };
  }

  static MeasurementWorkerAppendMessage _decodeAppend(List<Object?> values) {
    if (values.length != 6) {
      throw const MeasurementWorkerProtocolException('invalid_append_length');
    }
    final value = MeasurementWorkerAppendValue.fromWireCode(
      _requireInt(values[5]),
    );
    if (value == null) {
      throw const MeasurementWorkerProtocolException('invalid_append_value');
    }
    return MeasurementWorkerAppendMessage(
      sessionId: _requireString(values[2]),
      record: MeasurementWorkerAppendRecord(
        routeIndex: _requireInt(values[3]),
        monotonicTimestampMicros: _requireInt(values[4]),
        value: value,
      ),
    );
  }

  static MeasurementWorkerFatalMessage _decodeFatal(List<Object?> values) {
    if (values.length != 2) {
      throw const MeasurementWorkerProtocolException('invalid_fatal_length');
    }
    return const MeasurementWorkerFatalMessage();
  }
}

/// Parsed UI-to-worker command base type.
sealed class MeasurementWorkerInboundMessage {
  const MeasurementWorkerInboundMessage();
}

/// Parsed session-registration command.
final class MeasurementWorkerRegisterMessage
    extends MeasurementWorkerInboundMessage {
  const MeasurementWorkerRegisterMessage({
    required this.requestId,
    required this.registration,
  });

  final int requestId;
  final MeasurementWorkerSessionRegistration registration;
}

/// Parsed compact append command.
final class MeasurementWorkerAppendMessage
    extends MeasurementWorkerInboundMessage {
  const MeasurementWorkerAppendMessage({
    required this.sessionId,
    required this.record,
  });

  final String sessionId;

  final MeasurementWorkerAppendRecord record;
}

/// Parsed checkpoint barrier command.
final class MeasurementWorkerCheckpointMessage
    extends MeasurementWorkerInboundMessage {
  const MeasurementWorkerCheckpointMessage({
    required this.requestId,
    required this.sessionId,
  });

  final int requestId;
  final String sessionId;
}

/// Parsed finalization barrier command.
final class MeasurementWorkerTeardownMessage
    extends MeasurementWorkerInboundMessage {
  const MeasurementWorkerTeardownMessage({
    required this.requestId,
    required this.sessionId,
  });

  final int requestId;
  final String sessionId;
}

/// Parsed retained-batch retry command.
final class MeasurementWorkerRetryMessage
    extends MeasurementWorkerInboundMessage {
  const MeasurementWorkerRetryMessage({
    required this.requestId,
    required this.batchId,
  });

  final int requestId;
  final String batchId;
}

/// Parsed retained-batch release command.
final class MeasurementWorkerReleaseMessage
    extends MeasurementWorkerInboundMessage {
  const MeasurementWorkerReleaseMessage({
    required this.requestId,
    required this.batchId,
  });

  final int requestId;
  final String batchId;
}

/// Parsed worker shutdown command.
final class MeasurementWorkerShutdownMessage
    extends MeasurementWorkerInboundMessage {
  const MeasurementWorkerShutdownMessage({required this.requestId});

  final int requestId;
}

/// UI acknowledgement that permits a successfully shut down worker to exit.
final class MeasurementWorkerShutdownAcknowledgedMessage
    extends MeasurementWorkerInboundMessage {
  const MeasurementWorkerShutdownAcknowledgedMessage({
    required this.requestId,
  });

  final int requestId;
}

/// Parsed worker-to-UI event base type.
sealed class MeasurementWorkerOutboundMessage {
  const MeasurementWorkerOutboundMessage();
}

/// Worker startup event containing a native command port.
final class MeasurementWorkerReadyMessage
    extends MeasurementWorkerOutboundMessage {
  const MeasurementWorkerReadyMessage({required this.commandPort});

  final Object? commandPort;
}

/// Successful worker session registration event.
final class MeasurementWorkerOpenedMessage
    extends MeasurementWorkerOutboundMessage {
  const MeasurementWorkerOpenedMessage({
    required this.requestId,
    required this.sessionId,
    required this.workerOwnedByteCount,
  });

  final int requestId;
  final String sessionId;
  final int workerOwnedByteCount;
}

/// Rejected worker session registration event.
final class MeasurementWorkerOpenRejectedMessage
    extends MeasurementWorkerOutboundMessage {
  const MeasurementWorkerOpenRejectedMessage({
    required this.requestId,
    required this.outcome,
    required this.workerOwnedByteCount,
  });

  final int requestId;
  final MeasurementWorkerOpenSessionOutcome outcome;
  final int workerOwnedByteCount;
}

/// Append acknowledgement event.
final class MeasurementWorkerAppendAcknowledgedMessage
    extends MeasurementWorkerOutboundMessage {
  const MeasurementWorkerAppendAcknowledgedMessage({
    required this.sessionId,
    required this.outcome,
    required this.workerOwnedByteCount,
  });

  final String sessionId;
  final MeasurementWorkerAppendAcknowledgementOutcome outcome;
  final int workerOwnedByteCount;
}

/// Checkpoint, finalization, or retry result event.
final class MeasurementWorkerBatchResultMessage
    extends MeasurementWorkerOutboundMessage {
  const MeasurementWorkerBatchResultMessage({
    required this.requestId,
    required this.outcome,
    required this.batch,
    required this.workerOwnedByteCount,
  });

  final int requestId;
  final MeasurementWorkerBatchOutcome outcome;
  final MeasurementWorkerPreparedBatch? batch;
  final int workerOwnedByteCount;
}

/// Prepared-batch release result event.
final class MeasurementWorkerReleaseResultMessage
    extends MeasurementWorkerOutboundMessage {
  const MeasurementWorkerReleaseResultMessage({
    required this.requestId,
    required this.outcome,
    required this.workerOwnedByteCount,
  });

  final int requestId;
  final MeasurementWorkerReleaseOutcome outcome;
  final int workerOwnedByteCount;
}

/// Shutdown completion event.
final class MeasurementWorkerShutdownResultMessage
    extends MeasurementWorkerOutboundMessage {
  const MeasurementWorkerShutdownResultMessage({
    required this.requestId,
    required this.outcome,
    required this.workerOwnedByteCount,
  });

  final int requestId;
  final MeasurementWorkerShutdownOutcome outcome;
  final int workerOwnedByteCount;
}

/// Fatal worker event; no error object crosses the protocol boundary.
final class MeasurementWorkerFatalMessage
    extends MeasurementWorkerOutboundMessage {
  const MeasurementWorkerFatalMessage();
}

MeasurementWorkerOpenSessionOutcome _requireOpenOutcome(Object? value) {
  final result = MeasurementWorkerOpenSessionOutcome.fromWireCode(
    _requireInt(value),
  );
  if (result == null) {
    throw const MeasurementWorkerProtocolException('invalid_open_outcome');
  }
  return result;
}

MeasurementWorkerAppendAcknowledgementOutcome
    _requireAppendAcknowledgementOutcome(Object? value) {
  final result = MeasurementWorkerAppendAcknowledgementOutcome.fromWireCode(
    _requireInt(value),
  );
  if (result == null) {
    throw const MeasurementWorkerProtocolException('invalid_append_ack');
  }
  return result;
}

MeasurementWorkerBatchOutcome _requireBatchOutcome(Object? value) {
  final result = MeasurementWorkerBatchOutcome.fromWireCode(_requireInt(value));
  if (result == null) {
    throw const MeasurementWorkerProtocolException('invalid_batch_outcome');
  }
  return result;
}

MeasurementWorkerReleaseOutcome _requireReleaseOutcome(Object? value) {
  final result = MeasurementWorkerReleaseOutcome.fromWireCode(
    _requireInt(value),
  );
  if (result == null) {
    throw const MeasurementWorkerProtocolException('invalid_release_outcome');
  }
  return result;
}

MeasurementWorkerShutdownOutcome _requireShutdownOutcome(Object? value) {
  final result = MeasurementWorkerShutdownOutcome.fromWireCode(
    _requireInt(value),
  );
  if (result == null) {
    throw const MeasurementWorkerProtocolException('invalid_shutdown_outcome');
  }
  return result;
}

int _requirePositiveRequestId(
  List<Object?> values, {
  required int expectedLength,
}) {
  final value = _requireIntAt(values, 2, expectedLength: expectedLength);
  if (value <= 0 || value > kMeasurementWorkerMaximumPortableInteger) {
    throw const MeasurementWorkerProtocolException('invalid_request_id');
  }
  return value;
}

void _requireVersion(List<Object?> values) {
  if (_requireIntAt(values, 1) != kMeasurementWorkerProtocolVersion) {
    throw const MeasurementWorkerProtocolException(
      'unsupported_protocol_version',
    );
  }
}

Object? _valueAt(
  List<Object?> values,
  int index, {
  required int expectedLength,
}) {
  if (values.length != expectedLength || index < 0 || index >= values.length) {
    throw const MeasurementWorkerProtocolException('invalid_message_length');
  }
  return values[index];
}

int _requireIntAt(List<Object?> values, int index, {int? expectedLength}) {
  if ((expectedLength != null && values.length != expectedLength) ||
      index < 0 ||
      index >= values.length) {
    throw const MeasurementWorkerProtocolException('invalid_message_length');
  }
  return _requireInt(values[index]);
}

int _requireInt(Object? value) {
  if (value is! int) {
    throw const MeasurementWorkerProtocolException('expected_int');
  }
  return value;
}

int _requireNonNegativeInt(Object? value) {
  final result = _requireInt(value);
  if (result < 0) {
    throw const MeasurementWorkerProtocolException('expected_non_negative_int');
  }
  return result;
}

String _requireString(Object? value) {
  if (value is! String) {
    throw const MeasurementWorkerProtocolException('expected_string');
  }
  return value;
}

String _requireStringAt(
  List<Object?> values,
  int index, {
  required int expectedLength,
}) =>
    _requireString(_valueAt(values, index, expectedLength: expectedLength));

bool _requireBool(Object? value) {
  if (value is! bool) {
    throw const MeasurementWorkerProtocolException('expected_bool');
  }
  return value;
}

Uint8List _requireBytes(Object? value) {
  if (value is! Uint8List) {
    throw const MeasurementWorkerProtocolException('expected_typed_data');
  }
  return Uint8List.fromList(value);
}

List<Object?> _requireList(Object? value, {int? expectedLength}) {
  if (value is! List) {
    throw const MeasurementWorkerProtocolException('expected_list');
  }
  if (expectedLength != null && value.length != expectedLength) {
    throw const MeasurementWorkerProtocolException('invalid_list_length');
  }
  return List<Object?>.from(value);
}

bool _isOpaqueIdentifier(String value) =>
    value.isNotEmpty &&
    value.length <= 128 &&
    RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(value);
