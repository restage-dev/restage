import 'measurement_outbox_protocol.dart';

/// Builds the unsupported-platform store without resolving paths or files.
MeasurementOutboxStore createMeasurementOutboxStore({
  required MeasurementOutboxConfiguration configuration,
  required MeasurementOutboxClock clock,
  MeasurementOutboxFileSystem? fileSystem,
}) =>
    const _UnsupportedMeasurementOutboxStore();

final class _UnsupportedMeasurementOutboxStore
    implements MeasurementOutboxStore {
  const _UnsupportedMeasurementOutboxStore();

  @override
  Future<MeasurementOutboxOpenResult> open() async =>
      const MeasurementOutboxOpenResult(
        outcome: MeasurementOutboxOpenOutcome.unavailable,
        recovery: MeasurementOutboxRecovery(
          discardedTemporaryRecords: 0,
          quarantinedReadyRecords: 0,
          acknowledgedRecordsCleaned: 0,
          configurationHeldRecords: 0,
        ),
      );

  @override
  Future<MeasurementOutboxCommitResult> commit(
    MeasurementOutboxPreparedBatch batch,
  ) async =>
      const MeasurementOutboxCommitResult(
        outcome: MeasurementOutboxCommitOutcome.unavailable,
        record: null,
      );

  @override
  Future<MeasurementOutboxLease?> nextReady() async => null;

  @override
  Future<MeasurementOutboxAcknowledgementResult> acknowledge(
    MeasurementOutboxLease lease,
    MeasurementOutboxAcknowledgement acknowledgement,
  ) async =>
      const MeasurementOutboxAcknowledgementResult(
        MeasurementOutboxAcknowledgementOutcome.unavailable,
      );

  @override
  Future<MeasurementOutboxRetryResult> scheduleRetry(
    MeasurementOutboxLease lease,
  ) async =>
      const MeasurementOutboxRetryResult(
        outcome: MeasurementOutboxRetryOutcome.unavailable,
        attempt: null,
        nextRetryUtcMicros: null,
      );

  @override
  Future<MeasurementOutboxStateResult> hold(
    MeasurementOutboxLease lease,
    MeasurementOutboxHoldReason reason,
  ) async =>
      const MeasurementOutboxStateResult(
        MeasurementOutboxStateOutcome.unavailable,
      );

  @override
  Future<MeasurementOutboxStateResult> quarantine(
    MeasurementOutboxLease lease,
    MeasurementOutboxQuarantineReason reason,
  ) async =>
      const MeasurementOutboxStateResult(
        MeasurementOutboxStateOutcome.unavailable,
      );

  @override
  Future<MeasurementOutboxPurgeResult> purge(
    MeasurementOutboxPurgeReason reason,
  ) async =>
      const MeasurementOutboxPurgeResult(
        outcome: MeasurementOutboxPurgeOutcome.unavailable,
        purgedRecordCount: 0,
      );

  @override
  Future<MeasurementOutboxPurgeResult> purgeExpired() async =>
      const MeasurementOutboxPurgeResult(
        outcome: MeasurementOutboxPurgeOutcome.unavailable,
        purgedRecordCount: 0,
      );
}
