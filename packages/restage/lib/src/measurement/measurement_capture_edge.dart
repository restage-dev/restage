import 'package:meta/meta.dart';

import 'measurement_point_identity.dart';
import 'measurement_worker.dart';
import 'measurement_worker_delivery_protocol.dart';

abstract interface class _MeasurementCaptureAppendPort {
  MeasurementWorkerAppendOutcome append(MeasurementWorkerAppendRecord record);
}

final class _LegacyMeasurementCaptureAppendPort
    implements _MeasurementCaptureAppendPort {
  const _LegacyMeasurementCaptureAppendPort(this._session);

  final MeasurementWorkerSession _session;

  @override
  MeasurementWorkerAppendOutcome append(MeasurementWorkerAppendRecord record) =>
      _session.append(record);
}

final class _WorkerOwnedMeasurementCaptureAppendPort
    implements _MeasurementCaptureAppendPort {
  const _WorkerOwnedMeasurementCaptureAppendPort(this._session);

  final MeasurementWorkerOwnedDeliverySession _session;

  @override
  MeasurementWorkerAppendOutcome append(MeasurementWorkerAppendRecord record) =>
      _session.append(record);
}

/// Reads monotonic microseconds from a clock initialized before capture begins.
@internal
abstract interface class MeasurementCaptureMonotonicClock {
  /// Returns the next monotonic timestamp for one captured observation.
  int readMicros();
}

/// Bounded UI-side append edge for one exact mounted Measurement publication.
///
/// This object is bound once to one identity table, one already-open worker
/// session, and one monotonic clock. Its append methods intentionally retain no
/// event payload, aggregation state, or worker lifecycle ownership.
@internal
final class MeasurementCaptureEdge {
  /// Creates one edge after identity and worker-session setup has completed.
  MeasurementCaptureEdge({
    required MeasurementPointIdentityTable pointIdentityTable,
    required MeasurementWorkerSession workerSession,
    required MeasurementCaptureMonotonicClock monotonicClock,
  })  : _pointIdentityTable = pointIdentityTable,
        _workerSession = _LegacyMeasurementCaptureAppendPort(workerSession),
        _monotonicClock = monotonicClock,
        _onWorkerUnavailable = null;

  /// Creates an edge that appends directly to the one worker-owned delivery
  /// session selected by the construction owner.
  ///
  /// This is only a compact synchronous handoff. It owns no lifecycle,
  /// aggregation, frame, outbox, transport, or recovery state.
  MeasurementCaptureEdge.workerOwnedDelivery({
    required MeasurementPointIdentityTable pointIdentityTable,
    required MeasurementWorkerOwnedDeliverySession workerSession,
    required MeasurementCaptureMonotonicClock monotonicClock,
    void Function()? onWorkerUnavailable,
  })  : _pointIdentityTable = pointIdentityTable,
        _workerSession =
            _WorkerOwnedMeasurementCaptureAppendPort(workerSession),
        _monotonicClock = monotonicClock,
        _onWorkerUnavailable = onWorkerUnavailable;

  final MeasurementPointIdentityTable _pointIdentityTable;
  final _MeasurementCaptureAppendPort _workerSession;
  final MeasurementCaptureMonotonicClock _monotonicClock;
  final void Function()? _onWorkerUnavailable;
  var _available = true;

  /// Whether this edge can make further bounded append attempts.
  bool get isAvailable => _available;

  /// Rejects future appends without reopening or replacing the worker session.
  void close() {
    _available = false;
  }

  /// Appends one successfully painted compiler-emitted point token.
  MeasurementWorkerAppendOutcome appendPresentationToken(String compactToken) =>
      _appendToken(compactToken, MeasurementWorkerAppendValue.presentation);

  /// Appends one action observation selected by a compiler-emitted point token.
  MeasurementWorkerAppendOutcome appendInteractionToken(String compactToken) =>
      _appendToken(compactToken, MeasurementWorkerAppendValue.interaction);

  /// Appends one action observation selected before host composition.
  MeasurementWorkerAppendOutcome appendInteractionIdentity(
    MeasurementPointIdentity identity,
  ) {
    try {
      if (!_available) return MeasurementWorkerAppendOutcome.unavailable;
      if (!_pointIdentityTable.accepts(identity)) {
        return MeasurementWorkerAppendOutcome.invalid;
      }
      return _appendAcceptedIdentity(
        identity,
        MeasurementWorkerAppendValue.interaction,
      );
    } on Object {
      _available = false;
      return MeasurementWorkerAppendOutcome.unavailable;
    }
  }

  MeasurementWorkerAppendOutcome _appendToken(
    String compactToken,
    MeasurementWorkerAppendValue value,
  ) {
    try {
      if (!_available) return MeasurementWorkerAppendOutcome.unavailable;
      final identity = _pointIdentityTable.resolve(compactToken);
      if (identity == null || !_pointIdentityTable.accepts(identity)) {
        return MeasurementWorkerAppendOutcome.invalid;
      }
      return _appendAcceptedIdentity(identity, value);
    } on Object {
      _available = false;
      return MeasurementWorkerAppendOutcome.unavailable;
    }
  }

  MeasurementWorkerAppendOutcome _appendAcceptedIdentity(
    MeasurementPointIdentity identity,
    MeasurementWorkerAppendValue value,
  ) {
    try {
      final outcome = _workerSession.append(
        MeasurementWorkerAppendRecord(
          routeIndex: identity.routeIndex,
          monotonicTimestampMicros: _monotonicClock.readMicros(),
          value: value,
        ),
      );
      if (outcome != MeasurementWorkerAppendOutcome.accepted &&
          outcome != MeasurementWorkerAppendOutcome.saturated) {
        _available = false;
        if (outcome == MeasurementWorkerAppendOutcome.unavailable) {
          _onWorkerUnavailable?.call();
        }
      }
      return outcome;
    } on Object {
      _available = false;
      _onWorkerUnavailable?.call();
      return MeasurementWorkerAppendOutcome.unavailable;
    }
  }
}
