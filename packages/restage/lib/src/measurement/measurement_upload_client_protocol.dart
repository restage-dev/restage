import 'dart:async';
import 'dart:convert';
import 'package:meta/meta.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

import 'measurement_outbox_protocol.dart';

/// Supplies transient upload headers, including any authentication material.
///
/// Its value is never persisted by the journal. A provider may rotate an
/// in-memory credential between attempts without changing retained body bytes.
typedef MeasurementUploadHeadersProvider = FutureOr<Map<String, String>>
    Function();

const String _measurementReceiptEnvelopePrefix = '{"receiptCanonicalBase64":"';
const String _measurementReceiptEnvelopeSuffix = '"}';

/// Largest response body that can contain one bounded canonical receipt.
const int kMeasurementUploadMaximumReceiptResponseBytes =
    ((measurementIngestMaximumReceiptBytes * 4) + 2) ~/ 3 + 29;

final RegExp _exactMeasurementReceiptEnvelope = RegExp(
  r'\{"receiptCanonicalBase64":"([A-Za-z0-9_-]+)"\}',
);

/// In-memory configuration for one worker-local HTTP upload client.
@immutable
final class MeasurementUploadConfiguration {
  /// Creates one upload configuration.
  MeasurementUploadConfiguration({
    required this.endpoint,
    required this.headersProvider,
    this.contentType = 'application/json; charset=utf-8',
    this.requestTimeout = const Duration(seconds: 30),
  }) {
    if (!endpoint.hasScheme ||
        (endpoint.scheme != 'https' && endpoint.scheme != 'http') ||
        contentType.isEmpty ||
        requestTimeout <= Duration.zero) {
      throw ArgumentError('Invalid measurement upload configuration');
    }
  }

  /// Exact endpoint used only in memory by the worker-local upload client.
  final Uri endpoint;

  /// Transient headers supplied per attempt and never stored in the outbox.
  final MeasurementUploadHeadersProvider headersProvider;

  /// Content type added without transforming [MeasurementOutboxLease] bytes.
  final String contentType;

  /// Bound on an individual worker-local HTTP attempt.
  final Duration requestTimeout;
}

/// Strict decoder for the sole production receipt response envelope.
final class MeasurementUploadReceiptAcknowledgementDecoder {
  /// Creates the default exact production receipt decoder.
  const MeasurementUploadReceiptAcknowledgementDecoder();

  /// Returns a proof only when [responseBody] has the complete closed shape.
  MeasurementOutboxAcknowledgement? decode(
    List<int> responseBody,
    MeasurementOutboxRecord record,
  ) {
    try {
      if (responseBody.length > kMeasurementUploadMaximumReceiptResponseBytes) {
        return null;
      }
      final text = utf8.decode(responseBody, allowMalformed: false);
      final match = _exactMeasurementReceiptEnvelope.firstMatch(text);
      if (match == null || match.start != 0 || match.end != text.length) {
        return null;
      }
      final carrier = match.group(1)!;
      if (text !=
          '$_measurementReceiptEnvelopePrefix$carrier'
              '$_measurementReceiptEnvelopeSuffix') {
        return null;
      }
      final receipt = MeasurementIngestReceiptV1.fromBase64(carrier);
      return MeasurementOutboxAcknowledgement.fromReceipt(
        record: record,
        receipt: receipt,
      );
    } on Object {
      return null;
    }
  }
}

/// Closed result of one exact-body upload attempt.
enum MeasurementUploadOutcomeKind {
  /// The response proved the exact persisted session/sequence/body identity.
  acknowledged,

  /// A timeout, network error, or retryable server status retained the record.
  retryable,

  /// Authentication/configuration/protocol state retains the record without egress.
  paused,

  /// A permanent rejection retains the record in quarantine.
  rejected,

  /// A conflict lacks a proof that the stored identity was accepted.
  conflict,

  /// A nominal response lacked a complete exact acknowledgement proof.
  protocolFailure,

  /// The current platform cannot construct a worker-local client.
  unavailable,
}

/// Immutable result returned by [MeasurementUploadClient.send].
@immutable
final class MeasurementUploadOutcome {
  /// Creates one closed upload outcome.
  const MeasurementUploadOutcome._({
    required this.kind,
    required this.acknowledgement,
    required this.holdReason,
    required this.quarantineReason,
  });

  /// The exact response proved a strict acknowledgement identity.
  factory MeasurementUploadOutcome.acknowledged(
    MeasurementOutboxAcknowledgement acknowledgement,
  ) =>
      MeasurementUploadOutcome._(
        kind: MeasurementUploadOutcomeKind.acknowledged,
        acknowledgement: acknowledgement,
        holdReason: null,
        quarantineReason: null,
      );

  /// The exact body remains pending with a deterministic retry deadline.
  const MeasurementUploadOutcome.retryable()
      : this._(
          kind: MeasurementUploadOutcomeKind.retryable,
          acknowledgement: null,
          holdReason: null,
          quarantineReason: null,
        );

  /// The exact body is retained without automatic egress.
  const MeasurementUploadOutcome.paused(MeasurementOutboxHoldReason reason)
      : this._(
          kind: MeasurementUploadOutcomeKind.paused,
          acknowledgement: null,
          holdReason: reason,
          quarantineReason: null,
        );

  /// The exact body is retained in quarantine after a permanent rejection.
  const MeasurementUploadOutcome.rejected(
    MeasurementOutboxQuarantineReason reason,
  ) : this._(
          kind: MeasurementUploadOutcomeKind.rejected,
          acknowledgement: null,
          holdReason: null,
          quarantineReason: reason,
        );

  /// The exact body is retained in conflict quarantine.
  const MeasurementUploadOutcome.conflict()
      : this._(
          kind: MeasurementUploadOutcomeKind.conflict,
          acknowledgement: null,
          holdReason: null,
          quarantineReason: MeasurementOutboxQuarantineReason.conflict,
        );

  /// The response was not a valid acknowledgement for the stored identity.
  const MeasurementUploadOutcome.protocolFailure()
      : this._(
          kind: MeasurementUploadOutcomeKind.protocolFailure,
          acknowledgement: null,
          holdReason: MeasurementOutboxHoldReason.protocolFailure,
          quarantineReason: null,
        );

  /// The platform cannot create a worker-local upload client.
  const MeasurementUploadOutcome.unavailable()
      : this._(
          kind: MeasurementUploadOutcomeKind.unavailable,
          acknowledgement: null,
          holdReason: null,
          quarantineReason: null,
        );

  /// Closed upload classification.
  final MeasurementUploadOutcomeKind kind;

  /// Exact proof only for [MeasurementUploadOutcomeKind.acknowledged].
  final MeasurementOutboxAcknowledgement? acknowledgement;

  /// Retention reason only for [MeasurementUploadOutcomeKind.paused].
  final MeasurementOutboxHoldReason? holdReason;

  /// Quarantine reason only for rejected/conflict outcomes.
  final MeasurementOutboxQuarantineReason? quarantineReason;
}

/// Worker-local client that sends one exact leased body without re-encoding it.
abstract interface class MeasurementUploadClient {
  /// Sends [lease.exactRequestBytes] and returns only a closed outcome.
  Future<MeasurementUploadOutcome> send(MeasurementOutboxLease lease);
}

/// Closed result of the one-at-a-time upload coordinator.
enum MeasurementOutboxUploadOutcome {
  /// No due ready record was available.
  idle,

  /// Another lease/upload is active; no parallel I/O was started.
  busy,

  /// A strict acknowledgement marker was durable and the ready record was deleted.
  delivered,

  /// Remote acknowledgement is durable locally but restart cleanup remains.
  acknowledgedPendingCleanup,

  /// A deterministic no-jitter retry was persisted.
  retryScheduled,

  /// The record was retained without automatic egress.
  held,

  /// The record was retained in quarantine.
  quarantined,

  /// A record expired under local retention before upload.
  retentionExpired,

  /// No worker-local upload implementation is available.
  unavailable,

  /// The journal could not make a truthful durable state transition.
  persistenceFailure,
}

/// Immutable result of one coordinator drain attempt.
@immutable
final class MeasurementOutboxUploadResult {
  /// Creates one upload coordinator result.
  const MeasurementOutboxUploadResult(this.outcome);

  /// Closed coordinator result.
  final MeasurementOutboxUploadOutcome outcome;
}

/// Serializes delivery of one durable ready record at a time.
///
/// This class deliberately contains no worker spawning or UI handoff logic. It
/// is a worker-local seam that accepts an injected store, clock-owned retry
/// policy, and uploader for deterministic tests and later composition.
final class MeasurementOutboxUploadCoordinator {
  /// Creates a coordinator around one durable store and exact-byte uploader.
  MeasurementOutboxUploadCoordinator({
    required MeasurementOutboxStore store,
    required MeasurementUploadClient uploadClient,
  })  : _store = store,
        _uploadClient = uploadClient;

  final MeasurementOutboxStore _store;
  final MeasurementUploadClient _uploadClient;
  bool _uploading = false;

  /// Drains at most one due ready record and never starts a parallel upload.
  Future<MeasurementOutboxUploadResult> uploadNext() async {
    if (_uploading) {
      return const MeasurementOutboxUploadResult(
        MeasurementOutboxUploadOutcome.busy,
      );
    }
    _uploading = true;
    try {
      final retention = await _store.purgeExpired();
      if (retention.outcome == MeasurementOutboxPurgeOutcome.unavailable) {
        return const MeasurementOutboxUploadResult(
          MeasurementOutboxUploadOutcome.unavailable,
        );
      }
      if (retention.outcome == MeasurementOutboxPurgeOutcome.failed) {
        return const MeasurementOutboxUploadResult(
          MeasurementOutboxUploadOutcome.persistenceFailure,
        );
      }
      if (retention.purgedRecordCount > 0) {
        return const MeasurementOutboxUploadResult(
          MeasurementOutboxUploadOutcome.retentionExpired,
        );
      }
      final lease = await _store.nextReady();
      if (lease == null) {
        return const MeasurementOutboxUploadResult(
          MeasurementOutboxUploadOutcome.idle,
        );
      }
      final upload = await _uploadClient.send(lease);
      return await switch (upload.kind) {
        MeasurementUploadOutcomeKind.acknowledged =>
          _acknowledge(lease, upload.acknowledgement!),
        MeasurementUploadOutcomeKind.retryable => _scheduleRetry(lease),
        MeasurementUploadOutcomeKind.paused ||
        MeasurementUploadOutcomeKind.protocolFailure =>
          _hold(lease, upload.holdReason!),
        MeasurementUploadOutcomeKind.rejected ||
        MeasurementUploadOutcomeKind.conflict =>
          _quarantine(lease, upload.quarantineReason!),
        MeasurementUploadOutcomeKind.unavailable =>
          const MeasurementOutboxUploadResult(
            MeasurementOutboxUploadOutcome.unavailable,
          ),
      };
    } finally {
      _uploading = false;
    }
  }

  /// Stops new delivery work before an explicit reset or configuration cutover.
  Future<MeasurementOutboxPurgeResult> purge(
    MeasurementOutboxPurgeReason reason,
  ) async {
    if (_uploading) {
      return const MeasurementOutboxPurgeResult(
        outcome: MeasurementOutboxPurgeOutcome.failed,
        purgedRecordCount: 0,
      );
    }
    return _store.purge(reason);
  }

  Future<MeasurementOutboxUploadResult> _acknowledge(
    MeasurementOutboxLease lease,
    MeasurementOutboxAcknowledgement acknowledgement,
  ) async {
    final result = await _store.acknowledge(lease, acknowledgement);
    return MeasurementOutboxUploadResult(
      switch (result.outcome) {
        MeasurementOutboxAcknowledgementOutcome.delivered =>
          MeasurementOutboxUploadOutcome.delivered,
        MeasurementOutboxAcknowledgementOutcome.acknowledgedPendingCleanup =>
          MeasurementOutboxUploadOutcome.acknowledgedPendingCleanup,
        MeasurementOutboxAcknowledgementOutcome.unavailable =>
          MeasurementOutboxUploadOutcome.unavailable,
        MeasurementOutboxAcknowledgementOutcome.acknowledgementMismatch ||
        MeasurementOutboxAcknowledgementOutcome.unknownLease ||
        MeasurementOutboxAcknowledgementOutcome.persistenceFailure =>
          MeasurementOutboxUploadOutcome.persistenceFailure,
      },
    );
  }

  Future<MeasurementOutboxUploadResult> _scheduleRetry(
    MeasurementOutboxLease lease,
  ) async {
    final result = await _store.scheduleRetry(lease);
    return MeasurementOutboxUploadResult(
      switch (result.outcome) {
        MeasurementOutboxRetryOutcome.scheduled =>
          MeasurementOutboxUploadOutcome.retryScheduled,
        MeasurementOutboxRetryOutcome.retentionExpired =>
          MeasurementOutboxUploadOutcome.retentionExpired,
        MeasurementOutboxRetryOutcome.unavailable =>
          MeasurementOutboxUploadOutcome.unavailable,
        MeasurementOutboxRetryOutcome.unknownLease ||
        MeasurementOutboxRetryOutcome.persistenceFailure =>
          MeasurementOutboxUploadOutcome.persistenceFailure,
      },
    );
  }

  Future<MeasurementOutboxUploadResult> _hold(
    MeasurementOutboxLease lease,
    MeasurementOutboxHoldReason reason,
  ) async {
    final result = await _store.hold(lease, reason);
    return MeasurementOutboxUploadResult(
      switch (result.outcome) {
        MeasurementOutboxStateOutcome.held =>
          MeasurementOutboxUploadOutcome.held,
        MeasurementOutboxStateOutcome.unavailable =>
          MeasurementOutboxUploadOutcome.unavailable,
        MeasurementOutboxStateOutcome.quarantined ||
        MeasurementOutboxStateOutcome.unknownLease ||
        MeasurementOutboxStateOutcome.persistenceFailure =>
          MeasurementOutboxUploadOutcome.persistenceFailure,
      },
    );
  }

  Future<MeasurementOutboxUploadResult> _quarantine(
    MeasurementOutboxLease lease,
    MeasurementOutboxQuarantineReason reason,
  ) async {
    final result = await _store.quarantine(lease, reason);
    return MeasurementOutboxUploadResult(
      switch (result.outcome) {
        MeasurementOutboxStateOutcome.quarantined =>
          MeasurementOutboxUploadOutcome.quarantined,
        MeasurementOutboxStateOutcome.unavailable =>
          MeasurementOutboxUploadOutcome.unavailable,
        MeasurementOutboxStateOutcome.held ||
        MeasurementOutboxStateOutcome.unknownLease ||
        MeasurementOutboxStateOutcome.persistenceFailure =>
          MeasurementOutboxUploadOutcome.persistenceFailure,
      },
    );
  }
}
