import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:meta/meta.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

import 'measurement_worker_protocol.dart';

/// Maximum canonical request bytes admitted by the shared ingest contract.
const int kMeasurementOutboxMaximumCanonicalRequestBytes =
    measurementIngestMaximumRequestBytes;

/// Largest encoded HTTP body that can carry one canonical request.
///
/// The envelope is the unpadded base64url carrier plus its fixed JSON spelling.
/// It is derived from the owning shared-schema request bound rather than copied
/// as an unrelated literal.
const int kMeasurementOutboxMaximumHttpBodyBytes =
    ((kMeasurementOutboxMaximumCanonicalRequestBytes * 4) + 2) ~/ 3 + 29;

/// Maximum persisted canonical bytes for the receipt's binding witness.
///
/// The binding reference is already nested inside one bounded fact frame, so
/// this derives from the shared schema bound instead of creating a second
/// local admission limit.
const int kMeasurementOutboxMaximumBindingReferenceBytes =
    measurementIngestMaximumFactFrameBytes;

/// Largest complete journal record, including metadata and commit marker.
const int kMeasurementOutboxMaximumRecordBytes =
    kMeasurementOutboxMaximumHttpBodyBytes +
        kMeasurementOutboxMaximumBindingReferenceBytes +
        1024;

/// Largest combined size of all files in one outbox directory.
const int kMeasurementOutboxMaximumPendingBytes = 2 * 1024 * 1024;

/// Largest number of logical prepared batches retained by one journal.
const int kMeasurementOutboxMaximumPendingRecords = 8;

/// Largest number of fixed worker-handoff messages for this delivery kernel.
const int kMeasurementOutboxMaximumHandoffMessages = 256;

/// The delivery kernel has exactly one active lease/upload at a time.
const int kMeasurementOutboxMaximumInFlightUploads = 1;

/// Local retention for an unacknowledged prepared batch.
const Duration kMeasurementOutboxMaximumRetention = Duration(hours: 24);

/// Initial deterministic retry delay after the first failed upload.
const Duration kMeasurementOutboxInitialRetryDelay = Duration(seconds: 1);

/// Largest deterministic retry delay.
const Duration kMeasurementOutboxMaximumRetryDelay = Duration(hours: 1);

/// Largest persisted retry attempt accepted by the closed marker format.
const int kMeasurementOutboxMaximumRetryAttempt = 63;

/// Conservatively reserved state bytes for each ready record.
///
/// Retry publication can briefly retain both the old and new marker. Reserving
/// this amount at admission keeps the sum of ready, temporary, acknowledgement,
/// retry, hold, and quarantine files below the hard directory cap without
/// evicting an existing record.
const int kMeasurementOutboxMaximumReservedStateBytesPerRecord = 512;

/// Provides the current wall clock for persisted timestamps and deterministic
/// tests. Callers must return an instant in UTC or one convertible to UTC.
typedef MeasurementOutboxClock = DateTime Function();

/// Configuration already resolved by the root isolate before worker startup.
///
/// [applicationSupportPath] is deliberately a plain path. The worker journal
/// never calls a platform plugin or path provider itself. Only the non-secret
/// [configurationFingerprint] is persisted with each prepared record; endpoint
/// and authentication material remain in the in-memory upload configuration.
@immutable
final class MeasurementOutboxConfiguration {
  /// Creates an immutable worker-owned journal configuration.
  MeasurementOutboxConfiguration({
    required this.applicationSupportPath,
    required this.configurationFingerprint,
  }) {
    if (applicationSupportPath.trim().isEmpty ||
        !_isSafeFingerprint(configurationFingerprint)) {
      throw ArgumentError('Invalid measurement outbox configuration');
    }
  }

  /// Application-support directory resolved before worker startup.
  final String applicationSupportPath;

  /// Non-secret normalized endpoint/public-key/schema configuration digest.
  final String configurationFingerprint;

  /// Worker-owned journal directory below [applicationSupportPath].
  String get journalDirectory =>
      '${_stripTrailingSeparators(applicationSupportPath)}/restage/measurement/outbox-v1';
}

/// One regular file visible through an injected outbox filesystem.
@immutable
final class MeasurementOutboxFileEntry {
  /// Creates one filesystem directory entry.
  const MeasurementOutboxFileEntry({
    required this.path,
    required this.byteLength,
  });

  /// Absolute filesystem path.
  final String path;

  /// Byte size measured while listing the directory.
  final int byteLength;
}

/// Minimal filesystem boundary for the worker-owned journal.
///
/// Implementations must flush [writeAndFlush] before it completes. The store
/// only publishes a record by renaming a flushed same-directory temporary file.
/// This is intentionally narrower than a general-purpose filesystem so tests
/// can inject deterministic failure and crash controls.
abstract interface class MeasurementOutboxFileSystem {
  /// Creates [path] and needed parent directories when absent.
  Future<void> createDirectory(String path);

  /// Lists regular files directly contained by [path].
  Future<List<MeasurementOutboxFileEntry>> listDirectory(String path);

  /// Reads one file's exact bytes.
  Future<Uint8List> readBytes(String path);

  /// Writes [bytes], flushes them, and closes the file at [path].
  Future<void> writeAndFlush(String path, Uint8List bytes);

  /// Renames a file within the journal directory.
  Future<void> rename(String sourcePath, String destinationPath);

  /// Deletes one file when it exists.
  Future<void> delete(String path);
}

/// Immutable worker output accepted by the durable journal.
///
/// The batch is derived only after the worker handoff has been validated
/// against the shared ingest schema. The journal replays its exact route body
/// byte-for-byte and never adds authentication material.
@immutable
final class MeasurementOutboxPreparedBatch {
  MeasurementOutboxPreparedBatch._({
    required this.sessionId,
    required this.sequence,
    required this.isFinal,
    required List<int> exactRequestBytes,
    required this.bodySha256,
    required this.captureSessionNonce,
    required this.requestSha256,
    required this.factFrameSha256,
    required List<int> publicationBindingReferenceCanonicalBytes,
  })  : _exactRequestBytes = Uint8List.fromList(exactRequestBytes),
        _publicationBindingReferenceCanonicalBytes = Uint8List.fromList(
          publicationBindingReferenceCanonicalBytes,
        ) {
    if (!_isOpaqueIdentifier(sessionId) ||
        sequence <= 0 ||
        _exactRequestBytes.isEmpty ||
        _exactRequestBytes.length > kMeasurementOutboxMaximumHttpBodyBytes ||
        !_isCaptureSessionNonce(captureSessionNonce) ||
        !_isSha256(requestSha256) ||
        !_isSha256(factFrameSha256) ||
        _publicationBindingReferenceCanonicalBytes.isEmpty ||
        _publicationBindingReferenceCanonicalBytes.length >
            kMeasurementOutboxMaximumBindingReferenceBytes ||
        !_isSha256(bodySha256) ||
        _sha256Hex(_exactRequestBytes) != bodySha256) {
      throw ArgumentError('Invalid prepared measurement outbox batch');
    }
  }

  /// Adapts the immutable byte output of the frozen worker protocol.
  ///
  /// Validates a worker batch and derives the sole accepted HTTP body.
  ///
  /// This is intentionally the one off-UI-isolate conversion point. It proves
  /// all redundant worker handoff fields agree before the route body can be
  /// journaled or replayed.
  factory MeasurementOutboxPreparedBatch.fromWorkerPreparedBatch(
    MeasurementWorkerPreparedBatch batch,
  ) {
    try {
      final request = MeasurementIngestRequestV1.fromBase64(
        batch.canonicalRequestBase64,
      );
      if (!_sameBytes(request.canonicalBytes, batch.canonicalRequestBytes) ||
          request.requestSha256 != batch.requestSha256 ||
          !_sameBytes(
            request.factFrameCanonicalBytes,
            batch.canonicalFrameBytes,
          ) ||
          request.factFrameSha256 != batch.frameSha256 ||
          request.factFrame.sequence != batch.sequence ||
          request.factFrame.isFinal != batch.isFinal) {
        throw ArgumentError('Inconsistent measurement worker batch');
      }
      return MeasurementOutboxPreparedBatch._fromValidatedRequest(
        sessionId: batch.sessionId,
        request: request,
      );
    } on Object {
      throw ArgumentError('Invalid measurement worker batch');
    }
  }

  factory MeasurementOutboxPreparedBatch._fromStored({
    required String sessionId,
    required int sequence,
    required bool isFinal,
    required List<int> exactRequestBytes,
    required String bodySha256,
    required String captureSessionNonce,
    required String requestSha256,
    required String factFrameSha256,
    required List<int> publicationBindingReferenceCanonicalBytes,
  }) {
    try {
      final request = _decodeExactIngestHttpBody(exactRequestBytes);
      final expectedBinding =
          request.factFrame.publishedContext.bindingReference.canonicalBytes;
      if (_sha256Hex(exactRequestBytes) != bodySha256 ||
          request.factFrame.sequence != sequence ||
          request.factFrame.isFinal != isFinal ||
          request.factFrame.captureSessionNonce != captureSessionNonce ||
          request.requestSha256 != requestSha256 ||
          request.factFrameSha256 != factFrameSha256 ||
          !_sameBytes(
            expectedBinding,
            publicationBindingReferenceCanonicalBytes,
          )) {
        throw ArgumentError('Inconsistent stored measurement outbox batch');
      }
      return MeasurementOutboxPreparedBatch._(
        sessionId: sessionId,
        sequence: sequence,
        isFinal: isFinal,
        exactRequestBytes: exactRequestBytes,
        bodySha256: bodySha256,
        captureSessionNonce: captureSessionNonce,
        requestSha256: requestSha256,
        factFrameSha256: factFrameSha256,
        publicationBindingReferenceCanonicalBytes:
            publicationBindingReferenceCanonicalBytes,
      );
    } on Object {
      throw ArgumentError('Invalid stored measurement outbox batch');
    }
  }

  factory MeasurementOutboxPreparedBatch._fromValidatedRequest({
    required String sessionId,
    required MeasurementIngestRequestV1 request,
  }) {
    final exactRequestBytes = _encodeExactIngestHttpBody(
      request.canonicalRequestBase64,
    );
    return MeasurementOutboxPreparedBatch._(
      sessionId: sessionId,
      sequence: request.factFrame.sequence,
      isFinal: request.factFrame.isFinal,
      exactRequestBytes: exactRequestBytes,
      bodySha256: _sha256Hex(exactRequestBytes),
      captureSessionNonce: request.factFrame.captureSessionNonce,
      requestSha256: request.requestSha256,
      factFrameSha256: request.factFrameSha256,
      publicationBindingReferenceCanonicalBytes:
          request.factFrame.publishedContext.bindingReference.canonicalBytes,
    );
  }

  /// Opaque root-session coordinate, never a subject identity.
  final String sessionId;

  /// Monotone frame sequence within [sessionId].
  final int sequence;

  /// Whether this is the terminal snapshot for [sessionId].
  final bool isFinal;

  final Uint8List _exactRequestBytes;

  /// Exact prepared bytes replayed unchanged after process restart.
  Uint8List get exactRequestBytes => Uint8List.fromList(_exactRequestBytes);

  /// SHA-256 of [exactRequestBytes].
  final String bodySha256;

  /// Capture nonce the server receipt must prove.
  final String captureSessionNonce;

  /// SHA-256 of the canonical request carried by [exactRequestBytes].
  final String requestSha256;

  /// SHA-256 of the canonical fact frame carried by [exactRequestBytes].
  final String factFrameSha256;

  final Uint8List _publicationBindingReferenceCanonicalBytes;

  /// Exact publication-binding witness the receipt must repeat.
  Uint8List get publicationBindingReferenceCanonicalBytes =>
      Uint8List.fromList(_publicationBindingReferenceCanonicalBytes);
}

/// Immutable versioned record stored in a ready or temporary journal file.
@immutable
final class MeasurementOutboxRecord {
  /// Creates one durable record from a prepared batch.
  MeasurementOutboxRecord({
    required this.batch,
    required this.createdAtUtcMicros,
    required this.configurationFingerprint,
  }) {
    if (createdAtUtcMicros < 0 ||
        !_isSafeFingerprint(configurationFingerprint) ||
        encodedByteLength > kMeasurementOutboxMaximumRecordBytes) {
      throw ArgumentError('Invalid measurement outbox record');
    }
  }

  /// Immutable worker-prepared content.
  final MeasurementOutboxPreparedBatch batch;

  /// UTC creation instant persisted for retention across restarts.
  final int createdAtUtcMicros;

  /// Non-secret configuration digest captured at preparation time.
  final String configurationFingerprint;

  /// Stable file coordinate derived only from immutable record identity.
  String get fileStem => _recordFileStem(
        sessionId: batch.sessionId,
        sequence: batch.sequence,
        bodySha256: batch.bodySha256,
      );

  /// Exact size of [MeasurementOutboxRecordCodec.encode] for this record.
  int get encodedByteLength =>
      MeasurementOutboxRecordCodec.encodedByteLength(this);
}

/// Strict receipt proof required before ready-record deletion.
@immutable
final class MeasurementOutboxAcknowledgement {
  MeasurementOutboxAcknowledgement._({
    required this.sequence,
    required this.requestSha256,
    required this.factFrameSha256,
    required this.isFinal,
    required List<int> publicationBindingReferenceCanonicalBytes,
    required this.receiptSha256,
  }) : _publicationBindingReferenceCanonicalBytes = Uint8List.fromList(
          publicationBindingReferenceCanonicalBytes,
        );

  /// Returns a proof only when [receipt] proves every stored request witness.
  static MeasurementOutboxAcknowledgement? fromReceipt({
    required MeasurementOutboxRecord record,
    required MeasurementIngestReceiptV1 receipt,
  }) {
    final batch = record.batch;
    if (receipt.captureSessionNonce != batch.captureSessionNonce ||
        receipt.sequence != batch.sequence ||
        receipt.requestSha256 != batch.requestSha256 ||
        receipt.factFrameSha256 != batch.factFrameSha256 ||
        receipt.isFinal != batch.isFinal ||
        !_sameBytes(
          receipt.publicationBindingReference.canonicalBytes,
          batch.publicationBindingReferenceCanonicalBytes,
        )) {
      return null;
    }
    return MeasurementOutboxAcknowledgement._(
      sequence: receipt.sequence,
      requestSha256: receipt.requestSha256,
      factFrameSha256: receipt.factFrameSha256,
      isFinal: receipt.isFinal,
      publicationBindingReferenceCanonicalBytes:
          receipt.publicationBindingReference.canonicalBytes,
      receiptSha256: receipt.receiptSha256,
    );
  }

  /// Server-proven frame sequence.
  final int sequence;

  /// Server-proven raw request digest.
  final String requestSha256;

  /// Server-proven raw fact-frame digest.
  final String factFrameSha256;

  /// Server-proven finality.
  final bool isFinal;

  final Uint8List _publicationBindingReferenceCanonicalBytes;

  /// Server-proven exact publication-binding witness.
  Uint8List get publicationBindingReferenceCanonicalBytes =>
      Uint8List.fromList(_publicationBindingReferenceCanonicalBytes);

  /// Raw digest of the accepted canonical receipt persisted in the marker.
  final String receiptSha256;

  /// Whether this acknowledgement proves delivery of [record].
  bool matches(MeasurementOutboxRecord record) =>
      sequence == record.batch.sequence &&
      requestSha256 == record.batch.requestSha256 &&
      factFrameSha256 == record.batch.factFrameSha256 &&
      isFinal == record.batch.isFinal &&
      _sameBytes(
        _publicationBindingReferenceCanonicalBytes,
        record.batch.publicationBindingReferenceCanonicalBytes,
      ) &&
      _isSha256(receiptSha256);
}

/// A leased ready record. Leasing never removes or mutates the body.
@immutable
final class MeasurementOutboxLease {
  /// Creates one immutable ready-record lease.
  const MeasurementOutboxLease({required this.record});

  /// The exact record retained until a strict acknowledgement or explicit purge.
  final MeasurementOutboxRecord record;

  /// Stable journal coordinate for this lease.
  String get fileStem => record.fileStem;

  /// Exact prepared bytes for one upload attempt.
  Uint8List get exactRequestBytes => record.batch.exactRequestBytes;
}

/// Why a retained record is intentionally held without egress.
enum MeasurementOutboxHoldReason {
  /// A changed endpoint, key, or protocol configuration must not receive old data.
  configurationMismatch(1),

  /// Authentication or authorization no longer permits the configured route.
  authenticationFailure(2),

  /// The remote response did not prove the exact acknowledgement identity.
  protocolFailure(3);

  const MeasurementOutboxHoldReason(this.wireCode);

  /// Closed marker representation.
  final int wireCode;

  static MeasurementOutboxHoldReason? fromWireCode(int value) {
    for (final candidate in values) {
      if (candidate.wireCode == value) return candidate;
    }
    return null;
  }
}

/// Why a valid prepared record is retained but permanently removed from egress.
enum MeasurementOutboxQuarantineReason {
  /// Record or companion-marker validation failed.
  persistenceCorrupt(1),

  /// A server permanently rejected the exact prepared request.
  permanentRejection(2),

  /// A conflict lacked exact session/sequence/digest acknowledgement proof.
  conflict(3),

  /// Two different bodies claimed one session and sequence coordinate.
  duplicateSequence(4),

  /// An invalid ready filename or record was isolated during startup scanning.
  invalidReady(5);

  const MeasurementOutboxQuarantineReason(this.wireCode);

  /// Closed marker representation.
  final int wireCode;

  static MeasurementOutboxQuarantineReason? fromWireCode(int value) {
    for (final candidate in values) {
      if (candidate.wireCode == value) return candidate;
    }
    return null;
  }
}

/// Explicit local-loss reasons allowed to remove unacknowledged records.
enum MeasurementOutboxPurgeReason {
  /// A privacy reset intentionally discards local unacknowledged data.
  privacyReset,

  /// A changed endpoint/key/configuration discards the old generation.
  configurationReset,

  /// The local 24-hour retention deadline elapsed.
  retentionExpired,
}

/// Closed startup result for one journal instance.
enum MeasurementOutboxOpenOutcome {
  /// The journal directory was scanned and can accept operations.
  opened,

  /// The platform has no native durable outbox implementation.
  unavailable,

  /// Filesystem setup or recovery failed; the store remains fail-closed.
  persistenceFailure,
}

/// Recovery accounting from opening one durable journal.
@immutable
final class MeasurementOutboxRecovery {
  /// Creates deterministic recovery accounting.
  const MeasurementOutboxRecovery({
    required this.discardedTemporaryRecords,
    required this.quarantinedReadyRecords,
    required this.acknowledgedRecordsCleaned,
    required this.configurationHeldRecords,
  });

  /// Torn `.tmp` files removed as uncommitted data.
  final int discardedTemporaryRecords;

  /// Invalid or duplicate ready files removed from future egress.
  final int quarantinedReadyRecords;

  /// Valid durable acknowledgement markers converged to local cleanup.
  final int acknowledgedRecordsCleaned;

  /// Old-configuration records retained without sending to a new endpoint.
  final int configurationHeldRecords;
}

/// Immutable result of [MeasurementOutboxStore.open].
@immutable
final class MeasurementOutboxOpenResult {
  /// Creates one journal startup result.
  const MeasurementOutboxOpenResult({
    required this.outcome,
    required this.recovery,
  });

  /// Startup outcome.
  final MeasurementOutboxOpenOutcome outcome;

  /// Startup recovery accounting.
  final MeasurementOutboxRecovery recovery;

  /// Whether the store may perform durable operations.
  bool get isOpened => outcome == MeasurementOutboxOpenOutcome.opened;
}

/// Closed result of admitting one new prepared batch.
enum MeasurementOutboxCommitOutcome {
  /// A complete `.ready` record was published.
  committed,

  /// The same immutable session/sequence/body identity already exists.
  duplicate,

  /// A different body already owns the supplied session/sequence coordinate.
  sequenceConflict,

  /// The request or enclosing record exceeds a hard byte bound.
  payloadTooLarge,

  /// No bounded journal capacity remains; existing records were preserved.
  outboxSaturated,

  /// The filesystem failed; no successful publication was claimed.
  persistenceFailure,

  /// The platform has no native durable outbox implementation.
  unavailable,
}

/// Immutable result of admitting one prepared batch.
@immutable
final class MeasurementOutboxCommitResult {
  /// Creates one commit result.
  const MeasurementOutboxCommitResult({
    required this.outcome,
    required this.record,
  });

  /// Admission result.
  final MeasurementOutboxCommitOutcome outcome;

  /// Published or existing record when [outcome] carries one.
  final MeasurementOutboxRecord? record;
}

/// Closed result of persisting a retry deadline.
enum MeasurementOutboxRetryOutcome {
  /// A deterministic retry marker was durably published.
  scheduled,

  /// The record expired locally before another retry could be scheduled.
  retentionExpired,

  /// The supplied lease no longer names an active ready record.
  unknownLease,

  /// A filesystem failure left the record retained without success.
  persistenceFailure,

  /// The platform has no native durable outbox implementation.
  unavailable,
}

/// Immutable result of retry scheduling.
@immutable
final class MeasurementOutboxRetryResult {
  /// Creates one retry-scheduling result.
  const MeasurementOutboxRetryResult({
    required this.outcome,
    required this.attempt,
    required this.nextRetryUtcMicros,
  });

  /// Retry result.
  final MeasurementOutboxRetryOutcome outcome;

  /// Persisted attempt, or `null` when no retry was scheduled.
  final int? attempt;

  /// Persisted UTC retry deadline, or `null` when no retry was scheduled.
  final int? nextRetryUtcMicros;
}

/// Closed result of holding or quarantining a retained ready record.
enum MeasurementOutboxStateOutcome {
  /// The record was held and is no longer eligible for automatic egress.
  held,

  /// The record was quarantined and is no longer eligible for egress.
  quarantined,

  /// The supplied lease no longer names an active ready record.
  unknownLease,

  /// A filesystem failure left the record retained without an egress claim.
  persistenceFailure,

  /// The platform has no native durable outbox implementation.
  unavailable,
}

/// Immutable result of entering a retained non-egress state.
@immutable
final class MeasurementOutboxStateResult {
  /// Creates one state-transition result.
  const MeasurementOutboxStateResult(this.outcome);

  /// State-transition result.
  final MeasurementOutboxStateOutcome outcome;
}

/// Closed result of a strict acknowledgement and local cleanup.
enum MeasurementOutboxAcknowledgementOutcome {
  /// The acknowledgement marker was durable and the ready record was deleted.
  delivered,

  /// The acknowledgement marker is durable but local cleanup will converge on restart.
  acknowledgedPendingCleanup,

  /// The response did not prove the stored session/sequence/body identity.
  acknowledgementMismatch,

  /// The supplied lease no longer names an active ready record.
  unknownLease,

  /// The acknowledgement marker could not be persisted.
  persistenceFailure,

  /// The platform has no native durable outbox implementation.
  unavailable,
}

/// Immutable result of acknowledging one lease.
@immutable
final class MeasurementOutboxAcknowledgementResult {
  /// Creates one acknowledgement result.
  const MeasurementOutboxAcknowledgementResult(this.outcome);

  /// Acknowledgement and cleanup result.
  final MeasurementOutboxAcknowledgementOutcome outcome;
}

/// Closed result of an explicit local record purge.
enum MeasurementOutboxPurgeOutcome {
  /// A privacy reset removed unacknowledged local records.
  purgedUnacknowledged,

  /// A configuration cutover removed old local records.
  configurationReset,

  /// The local 24-hour retention policy removed expired records.
  retentionExpired,

  /// Removal did not complete; [purgedRecordCount] is still truthful.
  failed,

  /// The platform has no native durable outbox implementation.
  unavailable,
}

/// Immutable accounting for an explicit local purge.
@immutable
final class MeasurementOutboxPurgeResult {
  /// Creates one local-purge result.
  const MeasurementOutboxPurgeResult({
    required this.outcome,
    required this.purgedRecordCount,
  });

  /// Truthful local-removal result. It is never a delivery acknowledgement.
  final MeasurementOutboxPurgeOutcome outcome;

  /// Number of logical records actually removed before any failure.
  final int purgedRecordCount;
}

/// Native durable-store contract used only behind the measurement worker seam.
abstract interface class MeasurementOutboxStore {
  /// Creates/scans the worker-owned journal directory.
  Future<MeasurementOutboxOpenResult> open();

  /// Publishes one validated immutable prepared batch as `.tmp` then `.ready`.
  Future<MeasurementOutboxCommitResult> commit(
    MeasurementOutboxPreparedBatch batch,
  );

  /// Returns the next due sequence-preserving lease without deleting its body.
  Future<MeasurementOutboxLease?> nextReady();

  /// Writes a durable exact acknowledgement marker before deleting `.ready`.
  Future<MeasurementOutboxAcknowledgementResult> acknowledge(
    MeasurementOutboxLease lease,
    MeasurementOutboxAcknowledgement acknowledgement,
  );

  /// Persists deterministic retry state after a retryable failed upload.
  Future<MeasurementOutboxRetryResult> scheduleRetry(
    MeasurementOutboxLease lease,
  );

  /// Retains [lease] without egress after an authentication/configuration failure.
  Future<MeasurementOutboxStateResult> hold(
    MeasurementOutboxLease lease,
    MeasurementOutboxHoldReason reason,
  );

  /// Retains [lease] without egress after permanent or corrupt failure.
  Future<MeasurementOutboxStateResult> quarantine(
    MeasurementOutboxLease lease,
    MeasurementOutboxQuarantineReason reason,
  );

  /// Explicitly removes local unacknowledged records for a truthful purge reason.
  Future<MeasurementOutboxPurgeResult> purge(
    MeasurementOutboxPurgeReason reason,
  );

  /// Applies the fixed 24-hour local retention policy.
  Future<MeasurementOutboxPurgeResult> purgeExpired();
}

/// Optional worker-owned scheduling read for a durable outbox.
///
/// The delivery worker uses this only after a completed operation to set one
/// timer for the next persisted retry deadline. It is deliberately separate
/// from [MeasurementOutboxStore] so focused fake stores do not accidentally
/// claim a retry schedule they do not implement.
abstract interface class MeasurementOutboxRetrySchedule {
  /// Time until the next sequence-eligible ready record, or `null` when none
  /// can become eligible without a new commit or an explicit state change.
  Future<Duration?> nextReadyDelay();
}

/// Closed marker kinds written beside immutable ready records.
enum MeasurementOutboxMarkerKind {
  /// Server delivery was proven before local record deletion.
  acknowledged(1),

  /// A deterministic retry deadline was persisted.
  retry(2),

  /// The record is retained without automatic egress.
  held(3),

  /// The record is retained but permanently removed from egress.
  quarantined(4);

  const MeasurementOutboxMarkerKind(this.wireCode);

  /// Closed marker representation.
  final int wireCode;

  static MeasurementOutboxMarkerKind? fromWireCode(int value) {
    for (final candidate in values) {
      if (candidate.wireCode == value) return candidate;
    }
    return null;
  }
}

/// Strict state marker associated with one immutable prepared record.
@immutable
final class MeasurementOutboxMarker {
  /// Creates one closed marker.
  MeasurementOutboxMarker._({
    required this.kind,
    required this.sessionId,
    required this.sequence,
    required this.bodySha256,
    required this.attempt,
    required this.nextRetryUtcMicros,
    required this.reasonCode,
    required this.receiptSha256,
  }) {
    if (!_isOpaqueIdentifier(sessionId) ||
        sequence <= 0 ||
        !_isSha256(bodySha256) ||
        attempt < 0 ||
        attempt > kMeasurementOutboxMaximumRetryAttempt ||
        nextRetryUtcMicros < 0 ||
        !_isValidMarkerShape(this)) {
      throw ArgumentError('Invalid measurement outbox marker');
    }
  }

  /// Creates a durable exact acknowledgement marker.
  factory MeasurementOutboxMarker.acknowledgement({
    required MeasurementOutboxRecord record,
    required MeasurementOutboxAcknowledgement acknowledgement,
  }) {
    if (!acknowledgement.matches(record)) {
      throw ArgumentError('Acknowledgement does not match outbox record');
    }
    return MeasurementOutboxMarker._(
      kind: MeasurementOutboxMarkerKind.acknowledged,
      sessionId: record.batch.sessionId,
      sequence: record.batch.sequence,
      bodySha256: record.batch.bodySha256,
      attempt: 0,
      nextRetryUtcMicros: 0,
      reasonCode: 0,
      receiptSha256: acknowledgement.receiptSha256,
    );
  }

  /// Creates a durable deterministic retry marker.
  factory MeasurementOutboxMarker.retry({
    required MeasurementOutboxRecord record,
    required int attempt,
    required int nextRetryUtcMicros,
  }) =>
      MeasurementOutboxMarker._(
        kind: MeasurementOutboxMarkerKind.retry,
        sessionId: record.batch.sessionId,
        sequence: record.batch.sequence,
        bodySha256: record.batch.bodySha256,
        attempt: attempt,
        nextRetryUtcMicros: nextRetryUtcMicros,
        reasonCode: 0,
        receiptSha256: null,
      );

  /// Creates a durable held-record marker.
  factory MeasurementOutboxMarker.hold({
    required MeasurementOutboxRecord record,
    required MeasurementOutboxHoldReason reason,
  }) =>
      MeasurementOutboxMarker._(
        kind: MeasurementOutboxMarkerKind.held,
        sessionId: record.batch.sessionId,
        sequence: record.batch.sequence,
        bodySha256: record.batch.bodySha256,
        attempt: 0,
        nextRetryUtcMicros: 0,
        reasonCode: reason.wireCode,
        receiptSha256: null,
      );

  /// Creates a durable quarantined-record marker.
  factory MeasurementOutboxMarker.quarantine({
    required MeasurementOutboxRecord record,
    required MeasurementOutboxQuarantineReason reason,
  }) =>
      MeasurementOutboxMarker._(
        kind: MeasurementOutboxMarkerKind.quarantined,
        sessionId: record.batch.sessionId,
        sequence: record.batch.sequence,
        bodySha256: record.batch.bodySha256,
        attempt: 0,
        nextRetryUtcMicros: 0,
        reasonCode: reason.wireCode,
        receiptSha256: null,
      );

  /// Marker type.
  final MeasurementOutboxMarkerKind kind;

  /// Opaque root-session coordinate.
  final String sessionId;

  /// Frame sequence.
  final int sequence;

  /// Exact prepared-body digest.
  final String bodySha256;

  /// Retry count only for [MeasurementOutboxMarkerKind.retry].
  final int attempt;

  /// UTC retry deadline only for [MeasurementOutboxMarkerKind.retry].
  final int nextRetryUtcMicros;

  /// Closed hold/quarantine reason code, otherwise zero.
  final int reasonCode;

  /// Raw receipt digest only for an acknowledgement marker.
  final String? receiptSha256;

  /// Whether this marker names exactly [record].
  bool matches(MeasurementOutboxRecord record) =>
      sessionId == record.batch.sessionId &&
      sequence == record.batch.sequence &&
      bodySha256 == record.batch.bodySha256;
}

/// Strict parse error for the closed record and marker formats.
final class MeasurementOutboxCodecException implements Exception {
  /// Creates one machine-readable codec failure.
  const MeasurementOutboxCodecException(this.code);

  /// Stable reason without record contents.
  final String code;

  @override
  String toString() => 'MeasurementOutboxCodecException($code)';
}

/// Fixed closed binary codec for one immutable prepared record.
abstract final class MeasurementOutboxRecordCodec {
  static const int _version = 2;
  static const int _fixedHeaderLength = 138;
  static const int _integrityDigestLength = 32;
  static const List<int> _magic = <int>[82, 83, 79, 66, 88, 50, 0, 2];
  static const List<int> _commitMarker = <int>[
    82,
    83,
    79,
    66,
    45,
    67,
    79,
    77,
    77,
    73,
    84,
    45,
    86,
    50,
  ];

  /// Fixed format version used by this journal implementation.
  static int get version => _version;

  /// Size of the fixed portion before metadata and exact body bytes.
  static int get fixedHeaderLength => _fixedHeaderLength;

  /// Exact byte size for [record].
  static int encodedByteLength(MeasurementOutboxRecord record) =>
      _fixedHeaderLength +
      utf8.encode(record.batch.sessionId).length +
      utf8.encode(record.configurationFingerprint).length +
      utf8.encode(record.batch.captureSessionNonce).length +
      record.batch.publicationBindingReferenceCanonicalBytes.length +
      record.batch.exactRequestBytes.length +
      _integrityDigestLength +
      _commitMarker.length;

  /// Encodes one complete immutable record, including its commit marker.
  static Uint8List encode(MeasurementOutboxRecord record) {
    final sessionBytes = utf8.encode(record.batch.sessionId);
    final fingerprintBytes = utf8.encode(record.configurationFingerprint);
    final nonceBytes = utf8.encode(record.batch.captureSessionNonce);
    final bindingBytes = record.batch.publicationBindingReferenceCanonicalBytes;
    final body = record.batch.exactRequestBytes;
    final length = encodedByteLength(record);
    if (sessionBytes.length > 128 ||
        fingerprintBytes.length > 128 ||
        nonceBytes.length > 128 ||
        bindingBytes.length > kMeasurementOutboxMaximumBindingReferenceBytes ||
        body.length > kMeasurementOutboxMaximumHttpBodyBytes ||
        length > kMeasurementOutboxMaximumRecordBytes) {
      throw const MeasurementOutboxCodecException('record_too_large');
    }
    final bytes = Uint8List(length);
    final data = ByteData.sublistView(bytes);
    bytes.setRange(0, _magic.length, _magic);
    data
      ..setUint16(8, _version, Endian.big)
      ..setUint16(10, sessionBytes.length, Endian.big)
      ..setUint16(12, fingerprintBytes.length, Endian.big)
      ..setUint16(14, nonceBytes.length, Endian.big)
      ..setUint8(16, record.batch.isFinal ? 1 : 0)
      ..setUint8(17, 0)
      ..setUint64(18, record.batch.sequence, Endian.big)
      ..setInt64(26, record.createdAtUtcMicros, Endian.big)
      ..setUint32(34, body.length, Endian.big)
      ..setUint32(38, bindingBytes.length, Endian.big);
    bytes
      ..setRange(42, 74, _sha256Bytes(record.batch.bodySha256))
      ..setRange(74, 106, _sha256Bytes(record.batch.requestSha256))
      ..setRange(106, 138, _sha256Bytes(record.batch.factFrameSha256));
    var cursor = _fixedHeaderLength;
    bytes.setRange(cursor, cursor + sessionBytes.length, sessionBytes);
    cursor += sessionBytes.length;
    bytes.setRange(cursor, cursor + fingerprintBytes.length, fingerprintBytes);
    cursor += fingerprintBytes.length;
    bytes.setRange(cursor, cursor + nonceBytes.length, nonceBytes);
    cursor += nonceBytes.length;
    bytes.setRange(cursor, cursor + bindingBytes.length, bindingBytes);
    cursor += bindingBytes.length;
    bytes.setRange(cursor, cursor + body.length, body);
    cursor += body.length;
    bytes.setRange(
      cursor,
      cursor + _integrityDigestLength,
      _sha256DigestBytes(Uint8List.sublistView(bytes, 0, cursor)),
    );
    cursor += _integrityDigestLength;
    bytes.setRange(cursor, cursor + _commitMarker.length, _commitMarker);
    return bytes;
  }

  /// Strictly decodes one fully committed record.
  static MeasurementOutboxRecord decode(List<int> suppliedBytes) {
    final bytes = Uint8List.fromList(suppliedBytes);
    if (bytes.length <
            _fixedHeaderLength +
                _integrityDigestLength +
                _commitMarker.length ||
        bytes.length > kMeasurementOutboxMaximumRecordBytes) {
      throw const MeasurementOutboxCodecException('invalid_record_length');
    }
    if (!_matchesAt(bytes, 0, _magic)) {
      throw const MeasurementOutboxCodecException('invalid_record_magic');
    }
    final data = ByteData.sublistView(bytes);
    if (data.getUint16(8, Endian.big) != _version) {
      throw const MeasurementOutboxCodecException('unsupported_record_version');
    }
    final sessionLength = data.getUint16(10, Endian.big);
    final fingerprintLength = data.getUint16(12, Endian.big);
    final nonceLength = data.getUint16(14, Endian.big);
    final flags = data.getUint8(16);
    if (flags & ~1 != 0 || data.getUint8(17) != 0) {
      throw const MeasurementOutboxCodecException('invalid_record_flags');
    }
    if (sessionLength == 0 ||
        sessionLength > 128 ||
        fingerprintLength == 0 ||
        fingerprintLength > 128 ||
        nonceLength == 0 ||
        nonceLength > 128) {
      throw const MeasurementOutboxCodecException('invalid_record_header');
    }
    final sequence = data.getUint64(18, Endian.big);
    final createdAtUtcMicros = data.getInt64(26, Endian.big);
    final bodyLength = data.getUint32(34, Endian.big);
    final bindingLength = data.getUint32(38, Endian.big);
    if (sequence == 0 ||
        createdAtUtcMicros < 0 ||
        bodyLength == 0 ||
        bodyLength > kMeasurementOutboxMaximumHttpBodyBytes ||
        bindingLength == 0 ||
        bindingLength > kMeasurementOutboxMaximumBindingReferenceBytes ||
        _fixedHeaderLength +
                sessionLength +
                fingerprintLength +
                nonceLength +
                bindingLength +
                bodyLength +
                _integrityDigestLength +
                _commitMarker.length !=
            bytes.length) {
      throw const MeasurementOutboxCodecException('invalid_record_bounds');
    }
    if (!_matchesAt(
      bytes,
      bytes.length - _commitMarker.length,
      _commitMarker,
    )) {
      throw const MeasurementOutboxCodecException('invalid_commit_marker');
    }
    final integrityOffset =
        bytes.length - _integrityDigestLength - _commitMarker.length;
    if (!_matchesAt(
      bytes,
      integrityOffset,
      _sha256DigestBytes(Uint8List.sublistView(bytes, 0, integrityOffset)),
    )) {
      throw const MeasurementOutboxCodecException('record_integrity_mismatch');
    }
    final bodySha256 = _hex(bytes.sublist(42, 74));
    final requestSha256 = _hex(bytes.sublist(74, 106));
    final factFrameSha256 = _hex(bytes.sublist(106, 138));
    var cursor = _fixedHeaderLength;
    final sessionBytes = bytes.sublist(cursor, cursor + sessionLength);
    cursor += sessionLength;
    final fingerprintBytes = bytes.sublist(cursor, cursor + fingerprintLength);
    cursor += fingerprintLength;
    final nonceBytes = bytes.sublist(cursor, cursor + nonceLength);
    cursor += nonceLength;
    final bindingBytes = bytes.sublist(cursor, cursor + bindingLength);
    cursor += bindingLength;
    final body = bytes.sublist(cursor, cursor + bodyLength);
    final sessionId = _decodeUtf8(sessionBytes, 'invalid_record_session');
    final configurationFingerprint = _decodeUtf8(
      fingerprintBytes,
      'invalid_record_fingerprint',
    );
    final captureSessionNonce = _decodeUtf8(
      nonceBytes,
      'invalid_record_capture_nonce',
    );
    if (_sha256Hex(body) != bodySha256) {
      throw const MeasurementOutboxCodecException('body_digest_mismatch');
    }
    try {
      return MeasurementOutboxRecord(
        batch: MeasurementOutboxPreparedBatch._fromStored(
          sessionId: sessionId,
          sequence: sequence,
          isFinal: flags == 1,
          exactRequestBytes: body,
          bodySha256: bodySha256,
          captureSessionNonce: captureSessionNonce,
          requestSha256: requestSha256,
          factFrameSha256: factFrameSha256,
          publicationBindingReferenceCanonicalBytes: bindingBytes,
        ),
        createdAtUtcMicros: createdAtUtcMicros,
        configurationFingerprint: configurationFingerprint,
      );
    } on ArgumentError {
      throw const MeasurementOutboxCodecException('invalid_record_content');
    }
  }
}

/// Fixed closed binary codec for acknowledgement and state markers.
abstract final class MeasurementOutboxMarkerCodec {
  static const int _version = 2;
  static const int _fixedHeaderLength = 99;
  static const List<int> _magic = <int>[82, 83, 79, 77, 88, 50, 0, 2];
  static const List<int> _commitMarker = <int>[
    82,
    83,
    79,
    77,
    45,
    67,
    79,
    77,
    77,
    73,
    84,
    45,
    86,
    50,
  ];

  /// Encodes one complete marker with a strict commit marker.
  static Uint8List encode(MeasurementOutboxMarker marker) {
    final sessionBytes = utf8.encode(marker.sessionId);
    if (sessionBytes.length > 128) {
      throw const MeasurementOutboxCodecException('marker_too_large');
    }
    final bytes = Uint8List(
      _fixedHeaderLength + sessionBytes.length + _commitMarker.length,
    );
    final data = ByteData.sublistView(bytes);
    bytes.setRange(0, _magic.length, _magic);
    data
      ..setUint16(8, _version, Endian.big)
      ..setUint8(10, marker.kind.wireCode)
      ..setUint16(11, sessionBytes.length, Endian.big)
      ..setUint8(13, marker.reasonCode)
      ..setUint8(14, 0)
      ..setUint64(15, marker.sequence, Endian.big)
      ..setUint64(23, marker.nextRetryUtcMicros, Endian.big)
      ..setUint32(31, marker.attempt, Endian.big);
    bytes
      ..setRange(35, 67, _sha256Bytes(marker.bodySha256))
      ..setRange(
        67,
        99,
        marker.receiptSha256 == null
            ? Uint8List(32)
            : _sha256Bytes(marker.receiptSha256!),
      )
      ..setRange(
        _fixedHeaderLength,
        _fixedHeaderLength + sessionBytes.length,
        sessionBytes,
      )
      ..setRange(
        bytes.length - _commitMarker.length,
        bytes.length,
        _commitMarker,
      );
    return bytes;
  }

  /// Strictly decodes one committed marker.
  static MeasurementOutboxMarker decode(List<int> suppliedBytes) {
    final bytes = Uint8List.fromList(suppliedBytes);
    if (bytes.length < _fixedHeaderLength + _commitMarker.length) {
      throw const MeasurementOutboxCodecException('invalid_marker_length');
    }
    if (!_matchesAt(bytes, 0, _magic)) {
      throw const MeasurementOutboxCodecException('invalid_marker_magic');
    }
    final data = ByteData.sublistView(bytes);
    if (data.getUint16(8, Endian.big) != _version) {
      throw const MeasurementOutboxCodecException('unsupported_marker_version');
    }
    final kind = MeasurementOutboxMarkerKind.fromWireCode(data.getUint8(10));
    final sessionLength = data.getUint16(11, Endian.big);
    final reasonCode = data.getUint8(13);
    if (kind == null ||
        sessionLength == 0 ||
        sessionLength > 128 ||
        data.getUint8(14) != 0 ||
        bytes.length !=
            _fixedHeaderLength + sessionLength + _commitMarker.length ||
        !_matchesAt(
          bytes,
          bytes.length - _commitMarker.length,
          _commitMarker,
        )) {
      throw const MeasurementOutboxCodecException('invalid_marker_header');
    }
    final sequence = data.getUint64(15, Endian.big);
    final nextRetryUtcMicros = data.getUint64(23, Endian.big);
    final attempt = data.getUint32(31, Endian.big);
    final bodySha256 = _hex(bytes.sublist(35, 67));
    final receiptDigestBytes = bytes.sublist(67, 99);
    if (kind != MeasurementOutboxMarkerKind.acknowledged &&
        receiptDigestBytes.any((value) => value != 0)) {
      throw const MeasurementOutboxCodecException('invalid_marker_receipt');
    }
    final sessionId = _decodeUtf8(
      bytes.sublist(_fixedHeaderLength, _fixedHeaderLength + sessionLength),
      'invalid_marker_session',
    );
    try {
      return MeasurementOutboxMarker._(
        kind: kind,
        sessionId: sessionId,
        sequence: sequence,
        bodySha256: bodySha256,
        attempt: attempt,
        nextRetryUtcMicros: nextRetryUtcMicros,
        reasonCode: reasonCode,
        receiptSha256: kind == MeasurementOutboxMarkerKind.acknowledged
            ? _hex(receiptDigestBytes)
            : null,
      );
    } on ArgumentError {
      throw const MeasurementOutboxCodecException('invalid_marker_content');
    }
  }
}

/// Computes the deterministic no-jitter delay for one persisted retry attempt.
Duration measurementOutboxRetryDelay(int attempt) {
  if (attempt < 0 || attempt > kMeasurementOutboxMaximumRetryAttempt) {
    throw ArgumentError.value(attempt, 'attempt');
  }
  final seconds = attempt >= 12 ? 3600 : 1 << attempt;
  return Duration(seconds: seconds);
}

/// Creates a default system clock for native store construction.
DateTime measurementOutboxSystemClock() => DateTime.now().toUtc();

/// Returns the deterministic filename stem for one record identity.
String measurementOutboxRecordFileStem(MeasurementOutboxRecord record) =>
    record.fileStem;

String _recordFileStem({
  required String sessionId,
  required int sequence,
  required String bodySha256,
}) =>
    'batch-${_sha256Hex(utf8.encode('$sessionId\u0000$sequence\u0000$bodySha256'))}';

bool _isValidMarkerShape(MeasurementOutboxMarker marker) =>
    switch (marker.kind) {
      MeasurementOutboxMarkerKind.acknowledged => marker.attempt == 0 &&
          marker.nextRetryUtcMicros == 0 &&
          marker.reasonCode == 0 &&
          _isSha256(marker.receiptSha256 ?? ''),
      MeasurementOutboxMarkerKind.retry => marker.nextRetryUtcMicros > 0 &&
          marker.reasonCode == 0 &&
          marker.receiptSha256 == null,
      MeasurementOutboxMarkerKind.held => marker.attempt == 0 &&
          marker.nextRetryUtcMicros == 0 &&
          MeasurementOutboxHoldReason.fromWireCode(marker.reasonCode) != null &&
          marker.receiptSha256 == null,
      MeasurementOutboxMarkerKind.quarantined => marker.attempt == 0 &&
          marker.nextRetryUtcMicros == 0 &&
          MeasurementOutboxQuarantineReason.fromWireCode(marker.reasonCode) !=
              null &&
          marker.receiptSha256 == null,
    };

bool _isOpaqueIdentifier(String value) =>
    value.isNotEmpty &&
    value.length <= 128 &&
    RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(value);

bool _isSafeFingerprint(String value) =>
    value.isNotEmpty &&
    value.length <= 128 &&
    RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(value);

bool _isSha256(String value) => RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

bool _isCaptureSessionNonce(String value) =>
    RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(value);

const String _ingestHttpBodyPrefix = '{"canonicalRequestBase64":"';
const String _ingestHttpBodySuffix = '"}';
final RegExp _exactIngestHttpBody = RegExp(
  r'\{"canonicalRequestBase64":"([A-Za-z0-9_-]+)"\}',
);

Uint8List _encodeExactIngestHttpBody(String canonicalRequestBase64) =>
    Uint8List.fromList(
      utf8.encode(
        '$_ingestHttpBodyPrefix$canonicalRequestBase64$_ingestHttpBodySuffix',
      ),
    );

MeasurementIngestRequestV1 _decodeExactIngestHttpBody(List<int> supplied) {
  if (supplied.isEmpty ||
      supplied.length > kMeasurementOutboxMaximumHttpBodyBytes) {
    throw ArgumentError('Invalid measurement HTTP body length');
  }
  final body = utf8.decode(supplied, allowMalformed: false);
  final match = _exactIngestHttpBody.firstMatch(body);
  if (match == null || match.start != 0 || match.end != body.length) {
    throw ArgumentError('Invalid measurement HTTP body spelling');
  }
  final request = MeasurementIngestRequestV1.fromBase64(match.group(1)!);
  if (!_sameBytes(
    _encodeExactIngestHttpBody(request.canonicalRequestBase64),
    supplied,
  )) {
    throw ArgumentError('Noncanonical measurement HTTP body');
  }
  return request;
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

String _sha256Hex(List<int> bytes) => crypto.sha256.convert(bytes).toString();

Uint8List _sha256DigestBytes(List<int> bytes) =>
    Uint8List.fromList(crypto.sha256.convert(bytes).bytes);

Uint8List _sha256Bytes(String hex) => Uint8List.fromList([
      for (var index = 0; index < hex.length; index += 2)
        int.parse(hex.substring(index, index + 2), radix: 16),
    ]);

String _hex(List<int> bytes) =>
    bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();

bool _matchesAt(Uint8List bytes, int offset, List<int> expected) {
  if (offset < 0 || offset + expected.length > bytes.length) return false;
  for (var index = 0; index < expected.length; index += 1) {
    if (bytes[offset + index] != expected[index]) return false;
  }
  return true;
}

String _decodeUtf8(List<int> bytes, String code) {
  try {
    return utf8.decode(bytes, allowMalformed: false);
  } on FormatException {
    throw MeasurementOutboxCodecException(code);
  }
}

String _stripTrailingSeparators(String value) {
  var result = value;
  while (result.length > 1 && (result.endsWith('/') || result.endsWith('\\'))) {
    result = result.substring(0, result.length - 1);
  }
  return result;
}
