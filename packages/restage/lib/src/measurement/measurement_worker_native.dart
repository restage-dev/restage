import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

import 'measurement_outbox.dart';
import 'measurement_upload_client.dart';
import 'measurement_worker_delivery_protocol.dart';
import 'measurement_worker_protocol.dart';

/// Starts the native implementation selected by measurement_worker.dart.
Future<MeasurementWorkerRuntimeLaunchResult> startMeasurementWorkerRuntime({
  required MeasurementWorkerRuntimeConfiguration configuration,
}) async {
  if (!_validRuntimeConfiguration(configuration)) {
    return MeasurementWorkerRuntimeLaunchResult.unavailable(
      'invalid_worker_configuration',
    );
  }
  final state = _NativeMeasurementWorkerRuntimeState(configuration);
  try {
    await state.start();
    return MeasurementWorkerRuntimeLaunchResult.started(state);
  } on Object {
    state.dispose();
    return MeasurementWorkerRuntimeLaunchResult.unavailable(
      'native_isolate_worker_unavailable',
    );
  }
}

bool _validRuntimeConfiguration(MeasurementWorkerRuntimeConfiguration value) =>
    value.maximumSessions > 0 &&
    value.maximumSessions <= kMeasurementWorkerMaximumSessionCount &&
    value.maximumInFlightAppends > 0 &&
    value.maximumRetainedPreparedBatches > 0;

final class _NativeMeasurementWorkerRuntimeState
    implements MeasurementWorkerRuntimeState {
  _NativeMeasurementWorkerRuntimeState(this._configuration);

  final MeasurementWorkerRuntimeConfiguration _configuration;
  final Completer<SendPort> _ready = Completer<SendPort>();
  final Map<String, _NativeMeasurementWorkerSessionState> _sessions = {};
  final Map<int, _OpenPending> _opens = {};
  final Map<int, _BatchPending> _batchRequests = {};
  final Map<int, Completer<MeasurementWorkerReleaseResult>> _releases = {};
  final StreamController<MeasurementWorkerAppendAcknowledgement>
      _appendAcknowledgements = StreamController.broadcast(sync: true);

  late final ReceivePort _events;
  late final ReceivePort _errors;
  late final ReceivePort _exits;
  StreamSubscription<Object?>? _eventSubscription;
  StreamSubscription<Object?>? _errorSubscription;
  StreamSubscription<Object?>? _exitSubscription;
  Isolate? _isolate;
  SendPort? _commands;
  _ShutdownPending? _shutdown;
  bool _available = true;
  bool _disposed = false;
  int _reservedSessions = 0;
  int _pendingAppendCount = 0;
  int _pendingControlCount = 0;
  int _workerOwnedByteCount = 0;
  int _nextRequestId = 1;
  int _spawnCount = 0;

  Future<void> start() async {
    _events = ReceivePort();
    _errors = ReceivePort();
    _exits = ReceivePort();
    _eventSubscription = _events.listen(_handleWorkerEvent);
    _errorSubscription = _errors.listen((_) => _failWorker());
    _exitSubscription = _exits.listen((_) => _failWorker());
    _isolate = await Isolate.spawn<List<Object?>>(
      measurementWorkerIsolateMain,
      [_events.sendPort, _configuration.toWorkerBootstrapWire()],
      debugName: 'restage-measurement-worker',
      errorsAreFatal: true,
      onError: _errors.sendPort,
      onExit: _exits.sendPort,
    );
    _spawnCount = 1;
    _commands = await _ready.future;
  }

  @override
  bool get isAvailable => _available && !_disposed;

  @override
  int get workerOwnedByteCount => _workerOwnedByteCount;

  @override
  int get debugWorkerSpawnCount => _spawnCount;

  @override
  Stream<MeasurementWorkerAppendAcknowledgement> get appendAcknowledgements =>
      _appendAcknowledgements.stream;

  @override
  Future<MeasurementWorkerOpenSessionResult> openSession(
    MeasurementWorkerSessionRegistration registration,
  ) {
    if (!isAvailable) {
      return Future.value(
        MeasurementWorkerOpenSessionResult.of(
          MeasurementWorkerOpenSessionOutcome.unavailable,
          workerOwnedByteCount: _workerOwnedByteCount,
        ),
      );
    }
    if (_shutdown != null) {
      return Future.value(
        MeasurementWorkerOpenSessionResult.of(
          MeasurementWorkerOpenSessionOutcome.saturated,
          workerOwnedByteCount: _workerOwnedByteCount,
        ),
      );
    }
    if (_sessions.containsKey(registration.sessionId) ||
        _opens.values.any(
          (pending) => pending.registration.sessionId == registration.sessionId,
        )) {
      return Future.value(
        MeasurementWorkerOpenSessionResult.of(
          MeasurementWorkerOpenSessionOutcome.invalid,
          workerOwnedByteCount: _workerOwnedByteCount,
        ),
      );
    }
    if (_sessions.length + _reservedSessions >=
        _configuration.maximumSessions) {
      return Future.value(
        MeasurementWorkerOpenSessionResult.of(
          MeasurementWorkerOpenSessionOutcome.saturated,
          workerOwnedByteCount: _workerOwnedByteCount,
        ),
      );
    }
    final commands = _commands;
    if (commands == null) {
      return Future.value(
        MeasurementWorkerOpenSessionResult.of(
          MeasurementWorkerOpenSessionOutcome.unavailable,
          workerOwnedByteCount: _workerOwnedByteCount,
        ),
      );
    }
    final requestId = _allocateRequestId();
    final completer = Completer<MeasurementWorkerOpenSessionResult>();
    _reservedSessions += 1;
    _opens[requestId] = _OpenPending(
      registration: registration,
      completer: completer,
    );
    try {
      commands.send(
        MeasurementWorkerProtocol.register(
          requestId: requestId,
          registration: registration,
        ),
      );
    } on Object {
      _opens.remove(requestId);
      _reservedSessions -= 1;
      _failWorker();
      completer.complete(
        MeasurementWorkerOpenSessionResult.of(
          MeasurementWorkerOpenSessionOutcome.unavailable,
          workerOwnedByteCount: _workerOwnedByteCount,
        ),
      );
    }
    return completer.future;
  }

  MeasurementWorkerAppendOutcome append(
    _NativeMeasurementWorkerSessionState session,
    MeasurementWorkerAppendRecord record,
  ) {
    final commands = _commands;
    if (!isAvailable || commands == null) {
      return MeasurementWorkerAppendOutcome.unavailable;
    }
    if (_pendingAppendCount >= _configuration.maximumInFlightAppends) {
      return MeasurementWorkerAppendOutcome.saturated;
    }
    _pendingAppendCount += 1;
    session._lastTimestampMicros = record.monotonicTimestampMicros;
    try {
      commands.send(
        MeasurementWorkerProtocol.append(
          sessionId: session.sessionId,
          record: record,
        ),
      );
      return MeasurementWorkerAppendOutcome.accepted;
    } on Object {
      _pendingAppendCount -= 1;
      _failWorker();
      return MeasurementWorkerAppendOutcome.unavailable;
    }
  }

  Future<MeasurementWorkerBatchResult> requestSessionBarrier(
    _NativeMeasurementWorkerSessionState session, {
    required bool isFinal,
  }) {
    if (!isAvailable) {
      return Future.value(
        MeasurementWorkerBatchResult.of(
          MeasurementWorkerBatchOutcome.unavailable,
          workerOwnedByteCount: _workerOwnedByteCount,
        ),
      );
    }
    if (session._barrierRequestId != null || !_reserveControl()) {
      return Future.value(
        MeasurementWorkerBatchResult.of(
          MeasurementWorkerBatchOutcome.saturated,
          workerOwnedByteCount: _workerOwnedByteCount,
        ),
      );
    }
    final commands = _commands;
    if (commands == null) {
      _releaseControl();
      return Future.value(
        MeasurementWorkerBatchResult.of(
          MeasurementWorkerBatchOutcome.unavailable,
          workerOwnedByteCount: _workerOwnedByteCount,
        ),
      );
    }
    final requestId = _allocateRequestId();
    final completer = Completer<MeasurementWorkerBatchResult>();
    session._barrierRequestId = requestId;
    if (isFinal) session._status = _NativeSessionStatus.finalizing;
    _batchRequests[requestId] = _BatchPending(
      completer: completer,
      session: session,
      isFinal: isFinal,
    );
    try {
      commands.send(
        isFinal
            ? MeasurementWorkerProtocol.teardown(
                requestId: requestId,
                sessionId: session.sessionId,
              )
            : MeasurementWorkerProtocol.checkpoint(
                requestId: requestId,
                sessionId: session.sessionId,
              ),
      );
    } on Object {
      _batchRequests.remove(requestId);
      session._barrierRequestId = null;
      if (isFinal) session._status = _NativeSessionStatus.active;
      _releaseControl();
      _failWorker();
      completer.complete(
        MeasurementWorkerBatchResult.of(
          MeasurementWorkerBatchOutcome.unavailable,
          workerOwnedByteCount: _workerOwnedByteCount,
        ),
      );
    }
    return completer.future;
  }

  @override
  Future<MeasurementWorkerBatchResult> retryPreparedBatch(String batchId) {
    if (!isAvailable) return _unavailableBatchResult();
    if (_shutdown != null) return _saturatedBatchResult();
    if (!_reserveControl()) return _saturatedBatchResult();
    final commands = _commands;
    if (commands == null) {
      _releaseControl();
      return _unavailableBatchResult();
    }
    final requestId = _allocateRequestId();
    final completer = Completer<MeasurementWorkerBatchResult>();
    _batchRequests[requestId] = _BatchPending(
      completer: completer,
      session: null,
      isFinal: false,
    );
    try {
      commands.send(
        MeasurementWorkerProtocol.retry(requestId: requestId, batchId: batchId),
      );
    } on Object {
      _batchRequests.remove(requestId);
      _releaseControl();
      _failWorker();
      completer.complete(_unavailableBatchResultValue());
    }
    return completer.future;
  }

  @override
  Future<MeasurementWorkerReleaseResult> releasePreparedBatch(String batchId) {
    if (!isAvailable) return _unavailableReleaseResult();
    if (_shutdown != null) return _unavailableReleaseResult();
    if (!_reserveControl()) {
      return Future.value(
        MeasurementWorkerReleaseResult(
          outcome: MeasurementWorkerReleaseOutcome.unavailable,
          workerOwnedByteCount: _workerOwnedByteCount,
        ),
      );
    }
    final commands = _commands;
    if (commands == null) {
      _releaseControl();
      return _unavailableReleaseResult();
    }
    final requestId = _allocateRequestId();
    final completer = Completer<MeasurementWorkerReleaseResult>();
    _releases[requestId] = completer;
    try {
      commands.send(
        MeasurementWorkerProtocol.release(
          requestId: requestId,
          batchId: batchId,
        ),
      );
    } on Object {
      _releases.remove(requestId);
      _releaseControl();
      _failWorker();
      completer.complete(_unavailableReleaseResultValue());
    }
    return completer.future;
  }

  @override
  Future<MeasurementWorkerShutdownResult> shutdown() {
    if (!isAvailable) {
      return Future.value(
        MeasurementWorkerShutdownResult(
          outcome: MeasurementWorkerShutdownOutcome.unavailable,
          preparedBatches: const [],
          workerOwnedByteCount: _workerOwnedByteCount,
        ),
      );
    }
    if (_shutdown != null || !_reserveControl()) {
      return Future.value(
        MeasurementWorkerShutdownResult(
          outcome: MeasurementWorkerShutdownOutcome.saturated,
          preparedBatches: const [],
          workerOwnedByteCount: _workerOwnedByteCount,
        ),
      );
    }
    final commands = _commands;
    if (commands == null) {
      _releaseControl();
      return Future.value(
        MeasurementWorkerShutdownResult(
          outcome: MeasurementWorkerShutdownOutcome.unavailable,
          preparedBatches: const [],
          workerOwnedByteCount: _workerOwnedByteCount,
        ),
      );
    }
    final requestId = _allocateRequestId();
    final pending = _ShutdownPending(
      requestId: requestId,
      sessions: List<_NativeMeasurementWorkerSessionState>.from(
        _sessions.values,
      ),
    );
    _shutdown = pending;
    for (final session in pending.sessions) {
      if (session._status == _NativeSessionStatus.active) {
        session._status = _NativeSessionStatus.finalizing;
      }
    }
    try {
      commands.send(MeasurementWorkerProtocol.shutdown(requestId: requestId));
    } on Object {
      _shutdown = null;
      _releaseControl();
      for (final session in pending.sessions) {
        session._rollbackFinalizing();
      }
      _failWorker();
      pending.completer.complete(
        MeasurementWorkerShutdownResult(
          outcome: MeasurementWorkerShutdownOutcome.unavailable,
          preparedBatches: const [],
          workerOwnedByteCount: _workerOwnedByteCount,
        ),
      );
    }
    return pending.completer.future;
  }

  @override
  @visibleForTesting
  void debugKillWorkerForTesting() {
    _isolate?.kill(priority: Isolate.immediate);
  }

  bool _reserveControl() {
    if (_pendingControlCount >= _configuration.maximumSessions) return false;
    _pendingControlCount += 1;
    return true;
  }

  void _releaseControl() {
    if (_pendingControlCount > 0) _pendingControlCount -= 1;
  }

  int _allocateRequestId() {
    final result = _nextRequestId;
    _nextRequestId += 1;
    if (_nextRequestId > kMeasurementWorkerMaximumPortableInteger) {
      _nextRequestId = 1;
    }
    return result;
  }

  Future<MeasurementWorkerBatchResult> _unavailableBatchResult() =>
      Future.value(_unavailableBatchResultValue());

  MeasurementWorkerBatchResult _unavailableBatchResultValue() =>
      MeasurementWorkerBatchResult.of(
        MeasurementWorkerBatchOutcome.unavailable,
        workerOwnedByteCount: _workerOwnedByteCount,
      );

  Future<MeasurementWorkerBatchResult> _saturatedBatchResult() => Future.value(
        MeasurementWorkerBatchResult.of(
          MeasurementWorkerBatchOutcome.saturated,
          workerOwnedByteCount: _workerOwnedByteCount,
        ),
      );

  Future<MeasurementWorkerReleaseResult> _unavailableReleaseResult() =>
      Future.value(_unavailableReleaseResultValue());

  MeasurementWorkerReleaseResult _unavailableReleaseResultValue() =>
      MeasurementWorkerReleaseResult(
        outcome: MeasurementWorkerReleaseOutcome.unavailable,
        workerOwnedByteCount: _workerOwnedByteCount,
      );

  void _handleWorkerEvent(Object? raw) {
    if (_disposed) return;
    late MeasurementWorkerOutboundMessage message;
    try {
      message = MeasurementWorkerProtocol.decodeOutbound(raw);
    } on Object {
      _failWorker();
      return;
    }
    switch (message) {
      case MeasurementWorkerReadyMessage(:final commandPort):
        if (commandPort is! SendPort || _ready.isCompleted) {
          _failWorker();
          return;
        }
        _commands = commandPort;
        _ready.complete(commandPort);
      case MeasurementWorkerOpenedMessage(
          :final requestId,
          :final sessionId,
          :final workerOwnedByteCount,
        ):
        _workerOwnedByteCount = workerOwnedByteCount;
        final pending = _opens.remove(requestId);
        if (pending == null || pending.registration.sessionId != sessionId) {
          _failWorker();
          return;
        }
        _reservedSessions -= 1;
        final state = _NativeMeasurementWorkerSessionState(
          this,
          pending.registration,
        );
        _sessions[sessionId] = state;
        pending.completer.complete(
          MeasurementWorkerOpenSessionResult.opened(
            session: MeasurementWorkerSession.internal(state, sessionId),
            workerOwnedByteCount: _workerOwnedByteCount,
          ),
        );
      case MeasurementWorkerOpenRejectedMessage(
          :final requestId,
          :final outcome,
          :final workerOwnedByteCount,
        ):
        _workerOwnedByteCount = workerOwnedByteCount;
        final pending = _opens.remove(requestId);
        if (pending == null) {
          _failWorker();
          return;
        }
        _reservedSessions -= 1;
        pending.completer.complete(
          MeasurementWorkerOpenSessionResult.of(
            outcome,
            workerOwnedByteCount: _workerOwnedByteCount,
          ),
        );
      case MeasurementWorkerAppendAcknowledgedMessage(
          :final sessionId,
          :final outcome,
          :final workerOwnedByteCount,
        ):
        _workerOwnedByteCount = workerOwnedByteCount;
        if (_pendingAppendCount > 0) _pendingAppendCount -= 1;
        if (outcome == MeasurementWorkerAppendAcknowledgementOutcome.rejected) {
          _sessions[sessionId]?._markUnavailable();
        }
        _appendAcknowledgements.add(
          MeasurementWorkerAppendAcknowledgement(
            sessionId: sessionId,
            outcome: outcome,
            workerOwnedByteCount: _workerOwnedByteCount,
          ),
        );
      case MeasurementWorkerBatchResultMessage(
          :final requestId,
          :final outcome,
          :final batch,
          :final workerOwnedByteCount,
        ):
        _workerOwnedByteCount = workerOwnedByteCount;
        _handleBatchResult(requestId, outcome, batch);
      case MeasurementWorkerReleaseResultMessage(
          :final requestId,
          :final outcome,
          :final workerOwnedByteCount,
        ):
        _workerOwnedByteCount = workerOwnedByteCount;
        final completer = _releases.remove(requestId);
        if (completer == null) {
          _failWorker();
          return;
        }
        _releaseControl();
        completer.complete(
          MeasurementWorkerReleaseResult(
            outcome: outcome,
            workerOwnedByteCount: _workerOwnedByteCount,
          ),
        );
      case MeasurementWorkerShutdownResultMessage(
          :final requestId,
          :final outcome,
          :final workerOwnedByteCount,
        ):
        _workerOwnedByteCount = workerOwnedByteCount;
        _handleShutdownResult(requestId, outcome);
      case MeasurementWorkerFatalMessage():
        _failWorker();
    }
  }

  void _handleBatchResult(
    int requestId,
    MeasurementWorkerBatchOutcome outcome,
    MeasurementWorkerPreparedBatch? batch,
  ) {
    final shutdown = _shutdown;
    if (shutdown != null && requestId == shutdown.requestId) {
      if (outcome != MeasurementWorkerBatchOutcome.prepared || batch == null) {
        _failWorker();
        return;
      }
      shutdown.batches.add(batch);
      return;
    }
    final pending = _batchRequests.remove(requestId);
    if (pending == null) {
      _failWorker();
      return;
    }
    _releaseControl();
    final result =
        outcome == MeasurementWorkerBatchOutcome.prepared && batch != null
            ? MeasurementWorkerBatchResult.prepared(
                batch: batch,
                workerOwnedByteCount: _workerOwnedByteCount,
              )
            : MeasurementWorkerBatchResult.of(
                outcome,
                workerOwnedByteCount: _workerOwnedByteCount,
              );
    final session = pending.session;
    if (session != null) {
      session._barrierRequestId = null;
      session._onBarrierResult(result, isFinal: pending.isFinal);
    }
    pending.completer.complete(result);
  }

  void _handleShutdownResult(
    int requestId,
    MeasurementWorkerShutdownOutcome outcome,
  ) {
    final pending = _shutdown;
    if (pending == null || pending.requestId != requestId) {
      _failWorker();
      return;
    }
    _shutdown = null;
    _releaseControl();
    if (outcome == MeasurementWorkerShutdownOutcome.closed) {
      final commands = _commands;
      if (commands != null) {
        try {
          commands.send(
            MeasurementWorkerProtocol.shutdownAcknowledged(
              requestId: requestId,
            ),
          );
        } on Object {
          _isolate?.kill(priority: Isolate.immediate);
        }
      }
      for (final session in pending.sessions) {
        session._markFinalized();
        _sessions.remove(session.sessionId);
      }
      _available = false;
      pending.completer.complete(
        MeasurementWorkerShutdownResult(
          outcome: outcome,
          preparedBatches: pending.batches,
          workerOwnedByteCount: _workerOwnedByteCount,
        ),
      );
      dispose();
      return;
    }
    for (final session in pending.sessions) {
      session._rollbackFinalizing();
    }
    pending.completer.complete(
      MeasurementWorkerShutdownResult(
        outcome: outcome,
        preparedBatches: const [],
        workerOwnedByteCount: _workerOwnedByteCount,
      ),
    );
  }

  void _failWorker() {
    if (_disposed) return;
    _available = false;
    for (final session in _sessions.values) {
      session._markUnavailable();
    }
    _sessions.clear();
    for (final pending in _opens.values) {
      pending.completer.complete(
        MeasurementWorkerOpenSessionResult.of(
          MeasurementWorkerOpenSessionOutcome.unavailable,
          workerOwnedByteCount: _workerOwnedByteCount,
        ),
      );
    }
    _opens.clear();
    _reservedSessions = 0;
    for (final pending in _batchRequests.values) {
      pending.session?._markUnavailable();
      pending.completer.complete(_unavailableBatchResultValue());
    }
    _batchRequests.clear();
    for (final completer in _releases.values) {
      completer.complete(_unavailableReleaseResultValue());
    }
    _releases.clear();
    final shutdown = _shutdown;
    _shutdown = null;
    shutdown?.completer.complete(
      MeasurementWorkerShutdownResult(
        outcome: MeasurementWorkerShutdownOutcome.unavailable,
        preparedBatches: const [],
        workerOwnedByteCount: _workerOwnedByteCount,
      ),
    );
    _pendingAppendCount = 0;
    _pendingControlCount = 0;
    if (!_ready.isCompleted) {
      _ready.completeError(StateError('native measurement worker unavailable'));
    }
    dispose();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _events.close();
    _errors.close();
    _exits.close();
    unawaited(_eventSubscription?.cancel());
    unawaited(_errorSubscription?.cancel());
    unawaited(_exitSubscription?.cancel());
    unawaited(_appendAcknowledgements.close());
  }
}

final class _OpenPending {
  const _OpenPending({required this.registration, required this.completer});

  final MeasurementWorkerSessionRegistration registration;
  final Completer<MeasurementWorkerOpenSessionResult> completer;
}

final class _BatchPending {
  const _BatchPending({
    required this.completer,
    required this.session,
    required this.isFinal,
  });

  final Completer<MeasurementWorkerBatchResult> completer;
  final _NativeMeasurementWorkerSessionState? session;
  final bool isFinal;
}

final class _ShutdownPending {
  _ShutdownPending({required this.requestId, required this.sessions});

  final int requestId;
  final List<_NativeMeasurementWorkerSessionState> sessions;
  final List<MeasurementWorkerPreparedBatch> batches = [];
  final Completer<MeasurementWorkerShutdownResult> completer = Completer();
}

enum _NativeSessionStatus { active, finalizing, finalized, unavailable }

final class _NativeMeasurementWorkerSessionState
    implements MeasurementWorkerSessionState {
  _NativeMeasurementWorkerSessionState(this._runtime, this._registration);

  final _NativeMeasurementWorkerRuntimeState _runtime;
  final MeasurementWorkerSessionRegistration _registration;
  _NativeSessionStatus _status = _NativeSessionStatus.active;
  int _lastTimestampMicros = -1;
  int? _barrierRequestId;

  String get sessionId => _registration.sessionId;

  @override
  MeasurementWorkerAppendOutcome append(MeasurementWorkerAppendRecord record) {
    if (record.routeIndex < 0 ||
        record.routeIndex >= _registration.routes.length ||
        record.monotonicTimestampMicros < _lastTimestampMicros) {
      return MeasurementWorkerAppendOutcome.invalid;
    }
    return switch (_status) {
      _NativeSessionStatus.active => _runtime.append(this, record),
      _NativeSessionStatus.finalizing ||
      _NativeSessionStatus.finalized =>
        MeasurementWorkerAppendOutcome.finalized,
      _NativeSessionStatus.unavailable =>
        MeasurementWorkerAppendOutcome.unavailable,
    };
  }

  @override
  Future<MeasurementWorkerBatchResult> checkpoint() {
    if (_status == _NativeSessionStatus.unavailable) {
      return _runtime._unavailableBatchResult();
    }
    if (_status != _NativeSessionStatus.active) {
      return Future.value(
        MeasurementWorkerBatchResult.of(
          MeasurementWorkerBatchOutcome.finalized,
          workerOwnedByteCount: _runtime.workerOwnedByteCount,
        ),
      );
    }
    return _runtime.requestSessionBarrier(this, isFinal: false);
  }

  @override
  Future<MeasurementWorkerBatchResult> teardown() {
    if (_status == _NativeSessionStatus.unavailable) {
      return _runtime._unavailableBatchResult();
    }
    if (_status != _NativeSessionStatus.active) {
      return Future.value(
        MeasurementWorkerBatchResult.of(
          MeasurementWorkerBatchOutcome.finalized,
          workerOwnedByteCount: _runtime.workerOwnedByteCount,
        ),
      );
    }
    return _runtime.requestSessionBarrier(this, isFinal: true);
  }

  void _onBarrierResult(
    MeasurementWorkerBatchResult result, {
    required bool isFinal,
  }) {
    if (!isFinal) return;
    if (result.outcome == MeasurementWorkerBatchOutcome.prepared) {
      _status = _NativeSessionStatus.finalized;
      _runtime._sessions.remove(sessionId);
      return;
    }
    _status = result.outcome == MeasurementWorkerBatchOutcome.unavailable
        ? _NativeSessionStatus.unavailable
        : _NativeSessionStatus.active;
  }

  void _markUnavailable() => _status = _NativeSessionStatus.unavailable;

  void _markFinalized() => _status = _NativeSessionStatus.finalized;

  void _rollbackFinalizing() {
    if (_status == _NativeSessionStatus.finalizing) {
      _status = _NativeSessionStatus.active;
    }
  }
}

/// Native worker isolate entrypoint. It receives only a port and primitive
/// capacity values; no UI object, callback, codec, or transport crosses it.
@pragma('vm:entry-point')
void measurementWorkerIsolateMain(List<Object?> bootstrap) {
  if (bootstrap.length != 2 || bootstrap[0] is! SendPort) return;
  final events = bootstrap[0]! as SendPort;
  late final _MeasurementWorkerKernel kernel;
  try {
    final capacities = bootstrap[1];
    if (capacities is! List || capacities.length != 2) {
      events.send(MeasurementWorkerProtocol.fatal());
      return;
    }
    final maximumSessions = capacities[0];
    final maximumBatches = capacities[1];
    if (maximumSessions is! int ||
        maximumBatches is! int ||
        maximumSessions <= 0 ||
        maximumSessions > kMeasurementWorkerMaximumSessionCount ||
        maximumBatches <= 0) {
      events.send(MeasurementWorkerProtocol.fatal());
      return;
    }
    kernel = _MeasurementWorkerKernel(
      events: events,
      maximumSessions: maximumSessions,
      maximumRetainedPreparedBatches: maximumBatches,
    );
  } on Object {
    events.send(MeasurementWorkerProtocol.fatal());
    return;
  }
  final commands = ReceivePort();
  kernel.attach(commands);
  events.send(MeasurementWorkerProtocol.ready(commands.sendPort));
  commands.listen(kernel.handle);
}

final class _MeasurementWorkerKernel {
  _MeasurementWorkerKernel({
    required this.events,
    required this.maximumSessions,
    required this.maximumRetainedPreparedBatches,
  });

  final SendPort events;
  final int maximumSessions;
  final int maximumRetainedPreparedBatches;
  final Map<String, _WorkerSession> _sessions = {};
  final Map<String, _WorkerPreparedBatch> _prepared = {};
  ReceivePort? _commands;
  int? _shutdownRequestId;

  void attach(ReceivePort commands) {
    _commands = commands;
  }

  void handle(Object? raw) {
    late final MeasurementWorkerInboundMessage message;
    try {
      message = MeasurementWorkerProtocol.decodeInbound(raw);
    } on MeasurementWorkerProtocolException {
      events.send(MeasurementWorkerProtocol.fatal());
      _commands?.close();
      return;
    }
    try {
      if (_shutdownRequestId != null &&
          message is! MeasurementWorkerShutdownAcknowledgedMessage) {
        events.send(MeasurementWorkerProtocol.fatal());
        _commands?.close();
        return;
      }
      switch (message) {
        case MeasurementWorkerRegisterMessage():
          _register(message);
        case MeasurementWorkerAppendMessage():
          _append(message);
        case MeasurementWorkerCheckpointMessage():
          _checkpoint(message);
        case MeasurementWorkerTeardownMessage():
          _teardown(message);
        case MeasurementWorkerRetryMessage():
          _retry(message);
        case MeasurementWorkerReleaseMessage():
          _release(message);
        case MeasurementWorkerShutdownMessage():
          _shutdown(message);
        case MeasurementWorkerShutdownAcknowledgedMessage():
          _shutdownAcknowledged(message);
      }
    } on Object {
      events.send(MeasurementWorkerProtocol.fatal());
      _commands?.close();
      rethrow;
    }
  }

  void _register(MeasurementWorkerRegisterMessage message) {
    if (_sessions.length >= maximumSessions) {
      events.send(
        MeasurementWorkerProtocol.openRejected(
          requestId: message.requestId,
          outcome: MeasurementWorkerOpenSessionOutcome.saturated,
          workerOwnedByteCount: _ownedByteCount,
        ),
      );
      return;
    }
    if (_sessions.containsKey(message.registration.sessionId)) {
      events.send(
        MeasurementWorkerProtocol.openRejected(
          requestId: message.requestId,
          outcome: MeasurementWorkerOpenSessionOutcome.invalid,
          workerOwnedByteCount: _ownedByteCount,
        ),
      );
      return;
    }
    try {
      final session = _WorkerSession.fromRegistration(message.registration);
      _sessions[session.sessionId] = session;
      events.send(
        MeasurementWorkerProtocol.opened(
          requestId: message.requestId,
          sessionId: session.sessionId,
          workerOwnedByteCount: _ownedByteCount,
        ),
      );
    } on Object {
      events.send(
        MeasurementWorkerProtocol.openRejected(
          requestId: message.requestId,
          outcome: MeasurementWorkerOpenSessionOutcome.invalid,
          workerOwnedByteCount: _ownedByteCount,
        ),
      );
    }
  }

  void _append(MeasurementWorkerAppendMessage message) {
    final sessionId = message.sessionId;
    final record = message.record;
    final session = _sessions[sessionId];
    final outcome = session == null
        ? MeasurementWorkerAppendAcknowledgementOutcome.rejected
        : session.append(record);
    events.send(
      MeasurementWorkerProtocol.appendAcknowledged(
        sessionId: sessionId,
        outcome: outcome,
        workerOwnedByteCount: _ownedByteCount,
      ),
    );
  }

  void _checkpoint(MeasurementWorkerCheckpointMessage message) {
    final session = _sessions[message.sessionId];
    if (session == null) {
      _sendBatchResult(
        requestId: message.requestId,
        outcome: MeasurementWorkerBatchOutcome.finalized,
      );
      return;
    }
    _prepareAndSend(message.requestId, session, isFinal: false);
  }

  void _teardown(MeasurementWorkerTeardownMessage message) {
    final session = _sessions[message.sessionId];
    if (session == null) {
      _sendBatchResult(
        requestId: message.requestId,
        outcome: MeasurementWorkerBatchOutcome.finalized,
      );
      return;
    }
    final prepared = _prepare(session, isFinal: true);
    _sendPreparation(message.requestId, prepared);
    if (prepared.outcome == MeasurementWorkerBatchOutcome.prepared) {
      _sessions.remove(session.sessionId);
    }
  }

  void _retry(MeasurementWorkerRetryMessage message) {
    final batch = _prepared[message.batchId];
    if (batch == null) {
      _sendBatchResult(
        requestId: message.requestId,
        outcome: MeasurementWorkerBatchOutcome.unknownBatch,
      );
      return;
    }
    _sendBatchResult(
      requestId: message.requestId,
      outcome: MeasurementWorkerBatchOutcome.prepared,
      batch: batch.toPublic(),
    );
  }

  void _release(MeasurementWorkerReleaseMessage message) {
    final removed = _prepared.remove(message.batchId);
    events.send(
      MeasurementWorkerProtocol.releaseResult(
        requestId: message.requestId,
        outcome: removed == null
            ? MeasurementWorkerReleaseOutcome.unknownBatch
            : MeasurementWorkerReleaseOutcome.released,
        workerOwnedByteCount: _ownedByteCount,
      ),
    );
  }

  void _shutdown(MeasurementWorkerShutdownMessage message) {
    final orderedSessions = _sessions.values.toList()
      ..sort((left, right) => left.sessionId.compareTo(right.sessionId));
    if (_prepared.length + orderedSessions.length >
        maximumRetainedPreparedBatches) {
      events.send(
        MeasurementWorkerProtocol.shutdownResult(
          requestId: message.requestId,
          outcome: MeasurementWorkerShutdownOutcome.saturated,
          workerOwnedByteCount: _ownedByteCount,
        ),
      );
      return;
    }
    for (final session in orderedSessions) {
      final prepared = _prepare(session, isFinal: true);
      if (prepared.outcome != MeasurementWorkerBatchOutcome.prepared) {
        events.send(
          MeasurementWorkerProtocol.shutdownResult(
            requestId: message.requestId,
            outcome: MeasurementWorkerShutdownOutcome.saturated,
            workerOwnedByteCount: _ownedByteCount,
          ),
        );
        return;
      }
      _sendPreparation(message.requestId, prepared);
      _sessions.remove(session.sessionId);
    }
    events.send(
      MeasurementWorkerProtocol.shutdownResult(
        requestId: message.requestId,
        outcome: MeasurementWorkerShutdownOutcome.closed,
        workerOwnedByteCount: _ownedByteCount,
      ),
    );
    _shutdownRequestId = message.requestId;
  }

  void _shutdownAcknowledged(
    MeasurementWorkerShutdownAcknowledgedMessage message,
  ) {
    if (_shutdownRequestId != message.requestId) {
      events.send(MeasurementWorkerProtocol.fatal());
      _commands?.close();
      return;
    }
    _commands?.close();
  }

  void _prepareAndSend(
    int requestId,
    _WorkerSession session, {
    required bool isFinal,
  }) =>
      _sendPreparation(requestId, _prepare(session, isFinal: isFinal));

  _Preparation _prepare(_WorkerSession session, {required bool isFinal}) {
    if (!isFinal) {
      final checkpointId = session.checkpointBatchId;
      if (checkpointId != null) {
        final checkpoint = _prepared[checkpointId];
        if (checkpoint != null) {
          return _Preparation.prepared(checkpoint);
        }
      }
    }
    if (_prepared.length >= maximumRetainedPreparedBatches) {
      return const _Preparation.outcome(
        MeasurementWorkerBatchOutcome.saturated,
      );
    }
    if (isFinal) session.advanceForFinalization();
    final batch = _WorkerPreparedBatch.fromSession(session, isFinal: isFinal);
    _prepared[batch.batchId] = batch;
    if (!isFinal) {
      session.checkpointBatchId = batch.batchId;
    }
    return _Preparation.prepared(batch);
  }

  void _sendPreparation(int requestId, _Preparation preparation) {
    _sendBatchResult(
      requestId: requestId,
      outcome: preparation.outcome,
      batch: preparation.batch?.toPublic(),
    );
  }

  void _sendBatchResult({
    required int requestId,
    required MeasurementWorkerBatchOutcome outcome,
    MeasurementWorkerPreparedBatch? batch,
  }) {
    events.send(
      MeasurementWorkerProtocol.batchResult(
        requestId: requestId,
        outcome: outcome,
        batch: batch,
        workerOwnedByteCount: _ownedByteCount,
      ),
    );
  }

  int get _ownedByteCount {
    var total = 0;
    for (final session in _sessions.values) {
      total += session.structuralOwnedByteCount;
    }
    for (final batch in _prepared.values) {
      total += batch.structuralOwnedByteCount;
    }
    return total;
  }
}

final class _Preparation {
  const _Preparation._(this.outcome, this.batch);

  const _Preparation.outcome(MeasurementWorkerBatchOutcome outcome)
      : this._(outcome, null);

  _Preparation.prepared(_WorkerPreparedBatch batch)
      : this._(MeasurementWorkerBatchOutcome.prepared, batch);

  final MeasurementWorkerBatchOutcome outcome;
  final _WorkerPreparedBatch? batch;
}

final class _WorkerSession {
  _WorkerSession._({
    required this.sessionId,
    required this.captureSessionNonce,
    required this.contextCanonicalBytes,
    required this.publishedContext,
    required this.routes,
    required this.limits,
    required this.nextSequence,
  }) : _slots = List<_WorkerFactSlot>.generate(
          routes.length,
          (_) => _WorkerFactSlot(),
          growable: false,
        );

  factory _WorkerSession.fromRegistration(
    MeasurementWorkerSessionRegistration registration,
  ) {
    final contextBytes = registration.publicationContextCanonicalBytes;
    if (contextBytes.length >
            kMeasurementWorkerMaximumPublicationContextBytes ||
        registration.routes.length > kMeasurementWorkerMaximumRouteCount) {
      throw ArgumentError('Worker registration exceeds a closed capacity');
    }
    final context = ExactMeasurementPublicationContextRefV1.fromCanonicalBytes(
      contextBytes,
    );
    final routes = <_WorkerRoute>[];
    final occurrenceIds = <String>{};
    final lineageIds = <String>{};
    for (final identity in registration.routes) {
      CanonicalDigest(identity.occurrenceId);
      PointLineageId(identity.lineageId);
      if (!occurrenceIds.add(identity.occurrenceId) ||
          !lineageIds.add(identity.lineageId)) {
        throw ArgumentError(
          'Each worker route must retain a distinct identity',
        );
      }
      routes.add(
        _WorkerRoute(
          occurrenceId: identity.occurrenceId,
          lineageId: identity.lineageId,
        ),
      );
    }
    if (registration.firstSequence <= 0 ||
        registration.firstSequence > kMeasurementWorkerMaximumPortableInteger ||
        registration.captureSessionNonce.isEmpty ||
        registration.captureSessionNonce.length > 128) {
      throw ArgumentError('Invalid worker session registration');
    }
    return _WorkerSession._(
      sessionId: registration.sessionId,
      captureSessionNonce: registration.captureSessionNonce,
      contextCanonicalBytes: contextBytes,
      publishedContext: context,
      routes: List.unmodifiable(routes),
      limits: registration.limits,
      nextSequence: registration.firstSequence,
    );
  }

  static const int _fixedOwnedByteCount = 48;
  static const int _slotOwnedByteCount = 8;

  final String sessionId;
  final String captureSessionNonce;
  final Uint8List contextCanonicalBytes;
  final ExactMeasurementPublicationContextRefV1 publishedContext;
  final List<_WorkerRoute> routes;
  final MeasurementWorkerSessionLimits limits;
  final List<_WorkerFactSlot> _slots;
  int nextSequence;
  int _lastTimestampMicros = -1;
  int _presentedPointCount = 0;
  int _interactionCounterCount = 0;
  int _droppedPresentedPointCount = 0;
  int _droppedInteractionCounterCount = 0;
  String? checkpointBatchId;

  int get structuralOwnedByteCount {
    var total = _fixedOwnedByteCount +
        sessionId.length +
        captureSessionNonce.length +
        contextCanonicalBytes.length +
        (_slots.length * _slotOwnedByteCount);
    for (final route in routes) {
      total += route.structuralOwnedByteCount;
    }
    return total;
  }

  MeasurementWorkerAppendAcknowledgementOutcome append(
    MeasurementWorkerAppendRecord record,
  ) {
    if (record.routeIndex < 0 ||
        record.routeIndex >= _slots.length ||
        record.monotonicTimestampMicros < _lastTimestampMicros) {
      return MeasurementWorkerAppendAcknowledgementOutcome.rejected;
    }
    _lastTimestampMicros = record.monotonicTimestampMicros;
    _beginNewSnapshotAfterCheckpoint();
    final slot = _slots[record.routeIndex];
    if (!slot.presented) {
      if (_presentedPointCount == limits.maximumPresentedPoints) {
        if (!slot.droppedAtPresentation) {
          slot.droppedAtPresentation = true;
          _droppedPresentedPointCount = _increment(_droppedPresentedPointCount);
        }
        return MeasurementWorkerAppendAcknowledgementOutcome.truncated;
      }
      slot.presented = true;
      _presentedPointCount += 1;
      if (_interactionCounterCount == limits.maximumInteractionCounters) {
        slot.interactionTruncated = true;
        _droppedInteractionCounterCount = _increment(
          _droppedInteractionCounterCount,
        );
      } else {
        slot.hasInteractionCounter = true;
        _interactionCounterCount += 1;
      }
    }
    if (record.value == MeasurementWorkerAppendValue.interaction &&
        slot.hasInteractionCounter) {
      slot.recordInteraction(limits.maximumCounterValue);
    }
    return slot.hasInteractionCounter
        ? MeasurementWorkerAppendAcknowledgementOutcome.recorded
        : MeasurementWorkerAppendAcknowledgementOutcome.truncated;
  }

  void advanceForFinalization() {
    _beginNewSnapshotAfterCheckpoint();
  }

  Uint8List buildCanonicalFrame({required bool isFinal}) {
    final facts = <Map<String, Object?>>[];
    for (var index = 0; index < _slots.length; index += 1) {
      final slot = _slots[index];
      if (!slot.presented) continue;
      final route = routes[index];
      facts.add(slot.toJson(route));
    }
    facts.sort(
      (left, right) => _factIdentity(left).compareTo(_factIdentity(right)),
    );
    return CanonicalJsonCodec.encode({
      'bounds': {
        'maximumCounterValue': limits.maximumCounterValue,
        'maximumInteractionCounters': limits.maximumInteractionCounters,
        'maximumMissingnessEntries': limits.maximumMissingnessEntries,
        'maximumPresentedPoints': limits.maximumPresentedPoints,
      },
      'captureSessionNonce': captureSessionNonce,
      'facts': facts,
      'finality': {'kind': isFinal ? 'final' : 'pending'},
      'kind': 'measurementFactFrame',
      'missingness': const <Object?>[],
      'publishedContext': publishedContext.toJson(),
      'retryPolicy': const {'kind': 'byteIdenticalSameSequence'},
      'rootPresentation': const {'kind': 'successfulFirstPaint'},
      'schemaVersion': kMeasurementSchemaVersion,
      'sequence': nextSequence,
      'truncation': {
        'interactionCounters': {
          'droppedCount': _droppedInteractionCounterCount,
          'truncated': _droppedInteractionCounterCount > 0,
        },
        'presentedPoints': {
          'droppedCount': _droppedPresentedPointCount,
          'truncated': _droppedPresentedPointCount > 0,
        },
      },
    });
  }

  void _beginNewSnapshotAfterCheckpoint() {
    if (checkpointBatchId == null) return;
    if (nextSequence == kMeasurementWorkerMaximumPortableInteger) {
      throw StateError('Cannot advance the maximum worker frame sequence');
    }
    checkpointBatchId = null;
    nextSequence += 1;
  }

  int _increment(int value) =>
      value < limits.maximumCounterValue ? value + 1 : value;
}

String _factIdentity(Map<String, Object?> value) =>
    '${value['occurrenceId']}\u0000${value['lineageId']}';

final class _WorkerRoute {
  const _WorkerRoute({required this.occurrenceId, required this.lineageId});

  static const int _fixedOwnedByteCount = 8;

  final String occurrenceId;
  final String lineageId;

  int get structuralOwnedByteCount =>
      _fixedOwnedByteCount + occurrenceId.length + lineageId.length;
}

final class _WorkerFactSlot {
  bool presented = false;
  bool droppedAtPresentation = false;
  bool hasInteractionCounter = false;
  bool interactionTruncated = false;
  int _interactionCount = 0;
  bool _interactionSaturated = false;

  void recordInteraction(int maximum) {
    if (_interactionSaturated) return;
    if (_interactionCount == maximum) {
      _interactionSaturated = true;
      return;
    }
    _interactionCount += 1;
    if (_interactionCount == maximum) _interactionSaturated = true;
  }

  Map<String, Object?> toJson(_WorkerRoute route) {
    if (interactionTruncated) {
      return {
        'interactionState': 'transportTruncated',
        'lineageId': route.lineageId,
        'occurrenceId': route.occurrenceId,
      };
    }
    final state = _interactionSaturated
        ? 'observedCapped'
        : _interactionCount == 0
            ? 'observedZero'
            : 'observedValue';
    return {
      'interactionCount': {
        'saturated': _interactionSaturated,
        'value': _interactionCount,
      },
      'interactionState': state,
      'lineageId': route.lineageId,
      'occurrenceId': route.occurrenceId,
    };
  }
}

final class _WorkerPreparedBatch {
  _WorkerPreparedBatch._({
    required this.batchId,
    required this.sessionId,
    required this.isFinal,
    required this.sequence,
    required Uint8List canonicalFrameBytes,
    required Uint8List canonicalRequestBytes,
    required this.canonicalRequestBase64,
    required this.frameSha256,
    required this.requestSha256,
  })  : _canonicalFrameBytes = Uint8List.fromList(canonicalFrameBytes),
        _canonicalRequestBytes = Uint8List.fromList(canonicalRequestBytes);

  factory _WorkerPreparedBatch.fromSession(
    _WorkerSession session, {
    required bool isFinal,
  }) {
    final frameBytes = session.buildCanonicalFrame(isFinal: isFinal);
    final frame = MeasurementFactFrameV1.fromCanonicalBytes(frameBytes);
    final request = MeasurementIngestRequestV1.fromFactFrame(frame);
    final sequence = session.nextSequence;
    return _WorkerPreparedBatch._(
      batchId: '${session.sessionId}:$sequence',
      sessionId: session.sessionId,
      isFinal: isFinal,
      sequence: sequence,
      canonicalFrameBytes: frame.canonicalBytes,
      canonicalRequestBytes: request.canonicalBytes,
      canonicalRequestBase64: request.canonicalRequestBase64,
      frameSha256: frame.frameSha256.hex,
      requestSha256: request.requestSha256,
    );
  }

  static const int _fixedOwnedByteCount = 32;

  final String batchId;
  final String sessionId;
  final bool isFinal;
  final int sequence;
  final Uint8List _canonicalFrameBytes;
  final Uint8List _canonicalRequestBytes;
  final String canonicalRequestBase64;
  final String frameSha256;
  final String requestSha256;

  int get structuralOwnedByteCount =>
      _fixedOwnedByteCount +
      batchId.length +
      sessionId.length +
      _canonicalFrameBytes.length +
      _canonicalRequestBytes.length +
      canonicalRequestBase64.length +
      frameSha256.length +
      requestSha256.length;

  MeasurementWorkerPreparedBatch toPublic() => MeasurementWorkerPreparedBatch(
        batchId: batchId,
        sessionId: sessionId,
        isFinal: isFinal,
        sequence: sequence,
        canonicalFrameBytes: _canonicalFrameBytes,
        canonicalRequestBytes: _canonicalRequestBytes,
        canonicalRequestBase64: canonicalRequestBase64,
        frameSha256: frameSha256,
        requestSha256: requestSha256,
        ownedByteCount: structuralOwnedByteCount,
      );
}

/// Starts the native worker-owned outbox/upload composition selected by the
/// dedicated delivery facade. The root resolves exactly one plain support path;
/// all journal, codec, hash, and HTTP ownership starts inside the spawned worker.
Future<MeasurementWorkerOwnedDeliveryRuntimeLaunchResult>
    startMeasurementWorkerOwnedDelivery({
  required MeasurementWorkerOwnedDeliveryConfiguration configuration,
  MeasurementWorkerOwnedDeliveryPathResolver? pathResolver,
}) async {
  if (!configuration.admission.isAdmitted || !configuration.isValidForStartup) {
    return MeasurementWorkerOwnedDeliveryRuntimeLaunchResult.unavailable(
      'invalid_worker_owned_delivery_configuration',
    );
  }
  final resolver = pathResolver ?? const _PathProviderSupportPathResolver();
  late final String supportPath;
  try {
    supportPath = await resolver.resolveApplicationSupportPath();
  } on Object {
    return MeasurementWorkerOwnedDeliveryRuntimeLaunchResult.unavailable(
      'application_support_path_unavailable',
    );
  }
  if (supportPath.trim().isEmpty) {
    return MeasurementWorkerOwnedDeliveryRuntimeLaunchResult.unavailable(
      'application_support_path_unavailable',
    );
  }
  final state = _NativeMeasurementWorkerOwnedDeliveryState(
    configuration: configuration,
    applicationSupportPath: supportPath,
  );
  try {
    await state.start();
    return MeasurementWorkerOwnedDeliveryRuntimeLaunchResult.started(state);
  } on Object {
    state.dispose();
    return MeasurementWorkerOwnedDeliveryRuntimeLaunchResult.unavailable(
      'native_worker_owned_delivery_unavailable',
    );
  }
}

final class _PathProviderSupportPathResolver
    implements MeasurementWorkerOwnedDeliveryPathResolver {
  const _PathProviderSupportPathResolver();

  @override
  Future<String> resolveApplicationSupportPath() async =>
      (await path_provider.getApplicationSupportDirectory()).path;
}

final class _NativeMeasurementWorkerOwnedDeliveryState
    implements MeasurementWorkerOwnedDeliveryRuntimeState {
  _NativeMeasurementWorkerOwnedDeliveryState({
    required this.configuration,
    required this.applicationSupportPath,
  });

  final MeasurementWorkerOwnedDeliveryConfiguration configuration;
  final String applicationSupportPath;
  final Completer<SendPort> _ready = Completer<SendPort>();
  final Map<String, _NativeWorkerOwnedDeliverySessionState> _sessions = {};
  final Map<int, _WorkerOwnedDeliveryOpenPending> _opens = {};
  final Map<int, _WorkerOwnedDeliveryCheckpointPending> _checkpoints = {};
  final Map<int, _WorkerOwnedDeliveryDiscardPending> _discards = {};
  final Map<int, Completer<MeasurementWorkerOwnedDeliveryResetResult>> _resets =
      {};
  final Map<int, Completer<MeasurementWorkerOwnedDeliveryShutdownResult>>
      _shutdowns = {};
  final StreamController<MeasurementWorkerAppendAcknowledgement>
      _appendAcknowledgements = StreamController.broadcast(sync: true);
  final StreamController<MeasurementWorkerOwnedDeliveryDebugEvent>
      _debugEvents = StreamController.broadcast(sync: true);

  late final ReceivePort _events;
  late final ReceivePort _errors;
  late final ReceivePort _exits;
  StreamSubscription<Object?>? _eventSubscription;
  StreamSubscription<Object?>? _errorSubscription;
  StreamSubscription<Object?>? _exitSubscription;
  Isolate? _isolate;
  SendPort? _commands;
  bool _available = true;
  bool _stopping = false;
  bool _disposed = false;
  int _pendingAppendCount = 0;
  int _pendingControlCount = 0;
  int _workerOwnedByteCount = 0;
  int _nextRequestId = 1;
  int _spawnCount = 0;
  int? _workerIsolateId;

  Future<void> start() async {
    _events = ReceivePort();
    _errors = ReceivePort();
    _exits = ReceivePort();
    _eventSubscription = _events.listen(_handleWorkerEvent);
    _errorSubscription = _errors.listen((_) => _failWorker());
    _exitSubscription = _exits.listen((_) => _failWorker());
    _isolate = await Isolate.spawn<List<Object?>>(
      measurementWorkerOwnedDeliveryIsolateMain,
      [
        _events.sendPort,
        configuration.toWorkerBootstrapWire(applicationSupportPath),
      ],
      debugName: 'restage-measurement-outbox-worker',
      errorsAreFatal: true,
      onError: _errors.sendPort,
      onExit: _exits.sendPort,
    );
    _spawnCount = 1;
    _commands = await _ready.future;
  }

  @override
  bool get isAvailable => _available && !_stopping && !_disposed;

  @override
  int get workerOwnedByteCount => _workerOwnedByteCount;

  @override
  int get debugWorkerSpawnCount => _spawnCount;

  @override
  int? get debugWorkerIsolateId => _workerIsolateId;

  @override
  Stream<MeasurementWorkerAppendAcknowledgement> get appendAcknowledgements =>
      _appendAcknowledgements.stream;

  @override
  Stream<MeasurementWorkerOwnedDeliveryDebugEvent> get debugEvents =>
      _debugEvents.stream;

  @override
  Future<MeasurementWorkerOwnedDeliveryOpenSessionResult> openSession(
    MeasurementWorkerSessionRegistration registration,
  ) {
    if (!isAvailable || _commands == null) {
      return Future.value(
        MeasurementWorkerOwnedDeliveryOpenSessionResult.of(
          MeasurementWorkerOpenSessionOutcome.unavailable,
          workerOwnedByteCount: _workerOwnedByteCount,
        ),
      );
    }
    if (_sessions.containsKey(registration.sessionId) ||
        _opens.values.any(
          (pending) => pending.registration.sessionId == registration.sessionId,
        ) ||
        _sessions.length + _opens.length >= configuration.maximumSessions) {
      return Future.value(
        MeasurementWorkerOwnedDeliveryOpenSessionResult.of(
          _sessions.length + _opens.length >= configuration.maximumSessions
              ? MeasurementWorkerOpenSessionOutcome.saturated
              : MeasurementWorkerOpenSessionOutcome.invalid,
          workerOwnedByteCount: _workerOwnedByteCount,
        ),
      );
    }
    final requestId = _allocateRequestId();
    final completer =
        Completer<MeasurementWorkerOwnedDeliveryOpenSessionResult>();
    _opens[requestId] = _WorkerOwnedDeliveryOpenPending(
      registration: registration,
      completer: completer,
    );
    try {
      _commands!.send(
        MeasurementWorkerOwnedDeliveryProtocol.register(
          requestId: requestId,
          registration: registration,
        ),
      );
    } on Object {
      _opens.remove(requestId);
      _failWorker();
      completer.complete(_unavailableOpenResult());
    }
    return completer.future;
  }

  MeasurementWorkerAppendOutcome append(
    _NativeWorkerOwnedDeliverySessionState session,
    MeasurementWorkerAppendRecord record,
  ) {
    final commands = _commands;
    if (!isAvailable || commands == null) {
      return MeasurementWorkerAppendOutcome.unavailable;
    }
    if (_pendingAppendCount >= kMeasurementOutboxMaximumHandoffMessages) {
      return MeasurementWorkerAppendOutcome.saturated;
    }
    _pendingAppendCount += 1;
    session._lastTimestampMicros = record.monotonicTimestampMicros;
    try {
      commands.send(
        MeasurementWorkerOwnedDeliveryProtocol.append(
          sessionId: session.sessionId,
          record: record,
        ),
      );
      return MeasurementWorkerAppendOutcome.accepted;
    } on Object {
      _pendingAppendCount -= 1;
      _failWorker();
      return MeasurementWorkerAppendOutcome.unavailable;
    }
  }

  Future<MeasurementWorkerOwnedDeliveryCheckpointResult> requestCheckpoint(
    _NativeWorkerOwnedDeliverySessionState session, {
    required bool isFinal,
  }) {
    if (!isAvailable || session._barrierRequestId != null) {
      return Future.value(
        _checkpointResult(
          isAvailable
              ? MeasurementWorkerOwnedDeliveryCheckpointOutcome.saturated
              : MeasurementWorkerOwnedDeliveryCheckpointOutcome.unavailable,
        ),
      );
    }
    final commands = _commands;
    if (commands == null || !_reserveControl()) {
      return Future.value(
        _checkpointResult(
          commands == null
              ? MeasurementWorkerOwnedDeliveryCheckpointOutcome.unavailable
              : MeasurementWorkerOwnedDeliveryCheckpointOutcome.saturated,
        ),
      );
    }
    final requestId = _allocateRequestId();
    final completer =
        Completer<MeasurementWorkerOwnedDeliveryCheckpointResult>();
    session._barrierRequestId = requestId;
    if (isFinal) {
      session._status = _NativeWorkerOwnedDeliverySessionStatus.finalizing;
    }
    _checkpoints[requestId] = _WorkerOwnedDeliveryCheckpointPending(
      session: session,
      isFinal: isFinal,
      completer: completer,
    );
    try {
      commands.send(
        MeasurementWorkerOwnedDeliveryProtocol.checkpoint(
          requestId: requestId,
          sessionId: session.sessionId,
          isFinal: isFinal,
        ),
      );
    } on Object {
      _checkpoints.remove(requestId);
      session._barrierRequestId = null;
      if (isFinal) {
        session._status = _NativeWorkerOwnedDeliverySessionStatus.active;
      }
      _releaseControl();
      _failWorker();
      completer.complete(
        _checkpointResult(
          MeasurementWorkerOwnedDeliveryCheckpointOutcome.unavailable,
        ),
      );
    }
    return completer.future;
  }

  Future<MeasurementWorkerOwnedDeliveryDiscardResult> requestDiscard(
    _NativeWorkerOwnedDeliverySessionState session,
  ) {
    if (!isAvailable || session._barrierRequestId != null) {
      return Future.value(
        _discardResult(
          isAvailable
              ? MeasurementWorkerOwnedDeliveryDiscardOutcome.saturated
              : MeasurementWorkerOwnedDeliveryDiscardOutcome.unavailable,
        ),
      );
    }
    final commands = _commands;
    if (commands == null || !_reserveControl()) {
      return Future.value(
        _discardResult(
          commands == null
              ? MeasurementWorkerOwnedDeliveryDiscardOutcome.unavailable
              : MeasurementWorkerOwnedDeliveryDiscardOutcome.saturated,
        ),
      );
    }
    final requestId = _allocateRequestId();
    final completer = Completer<MeasurementWorkerOwnedDeliveryDiscardResult>();
    session
      .._barrierRequestId = requestId
      .._status = _NativeWorkerOwnedDeliverySessionStatus.discarding;
    _discards[requestId] = _WorkerOwnedDeliveryDiscardPending(
      session: session,
      completer: completer,
    );
    try {
      commands.send(
        MeasurementWorkerOwnedDeliveryProtocol.discard(
          requestId: requestId,
          sessionId: session.sessionId,
        ),
      );
    } on Object {
      _discards.remove(requestId);
      session
        .._barrierRequestId = null
        .._status = _NativeWorkerOwnedDeliverySessionStatus.unavailable;
      _releaseControl();
      _failWorker();
      completer.complete(
        _discardResult(
          MeasurementWorkerOwnedDeliveryDiscardOutcome.unavailable,
        ),
      );
    }
    return completer.future;
  }

  @override
  Future<MeasurementWorkerOwnedDeliveryResetResult> reset(
    MeasurementOutboxPurgeReason reason,
  ) {
    if (!isAvailable) return Future.value(_unavailableResetResult());
    final commands = _commands;
    if (commands == null) return Future.value(_unavailableResetResult());
    _stopping = true;
    for (final session in _sessions.values) {
      session._markUnavailable();
    }
    final requestId = _allocateRequestId();
    final completer = Completer<MeasurementWorkerOwnedDeliveryResetResult>();
    _resets[requestId] = completer;
    try {
      commands.send(
        MeasurementWorkerOwnedDeliveryProtocol.reset(
          requestId: requestId,
          reason: reason,
        ),
      );
    } on Object {
      _resets.remove(requestId);
      _failWorker();
      completer.complete(_unavailableResetResult());
    }
    return completer.future;
  }

  @override
  Future<MeasurementWorkerOwnedDeliveryShutdownResult> shutdown() {
    if (!isAvailable) {
      return Future.value(
        const MeasurementWorkerOwnedDeliveryShutdownResult(
          MeasurementWorkerOwnedDeliveryShutdownOutcome.unavailable,
        ),
      );
    }
    final commands = _commands;
    if (commands == null || _shutdowns.isNotEmpty) {
      return Future.value(
        const MeasurementWorkerOwnedDeliveryShutdownResult(
          MeasurementWorkerOwnedDeliveryShutdownOutcome.unavailable,
        ),
      );
    }
    _stopping = true;
    final requestId = _allocateRequestId();
    final completer = Completer<MeasurementWorkerOwnedDeliveryShutdownResult>();
    _shutdowns[requestId] = completer;
    try {
      commands.send(
        MeasurementWorkerOwnedDeliveryProtocol.shutdown(requestId: requestId),
      );
    } on Object {
      _shutdowns.remove(requestId);
      _failWorker();
      completer.complete(
        const MeasurementWorkerOwnedDeliveryShutdownResult(
          MeasurementWorkerOwnedDeliveryShutdownOutcome.unavailable,
        ),
      );
    }
    return completer.future;
  }

  @override
  @visibleForTesting
  void debugKillWorkerForTesting() {
    _isolate?.kill(priority: Isolate.immediate);
  }

  bool _reserveControl() {
    if (_pendingControlCount >= configuration.maximumSessions) return false;
    _pendingControlCount += 1;
    return true;
  }

  void _releaseControl() {
    if (_pendingControlCount > 0) _pendingControlCount -= 1;
  }

  int _allocateRequestId() {
    final result = _nextRequestId;
    _nextRequestId += 1;
    if (_nextRequestId > kMeasurementWorkerMaximumPortableInteger) {
      _nextRequestId = 1;
    }
    return result;
  }

  void _handleWorkerEvent(Object? raw) {
    if (_disposed) return;
    late final MeasurementWorkerOwnedDeliveryOutboundMessage message;
    try {
      message = MeasurementWorkerOwnedDeliveryProtocol.decodeOutbound(raw);
    } on Object {
      _failWorker();
      return;
    }
    switch (message) {
      case MeasurementWorkerOwnedDeliveryReadyMessage(
          :final commandPort,
          :final workerIsolateId,
        ):
        if (commandPort is! SendPort || _ready.isCompleted) {
          _failWorker();
          return;
        }
        _commands = commandPort;
        _workerIsolateId = workerIsolateId;
        _ready.complete(commandPort);
      case MeasurementWorkerOwnedDeliveryOpenedMessage(
          :final requestId,
          :final sessionId,
          :final workerOwnedByteCount,
        ):
        _workerOwnedByteCount = workerOwnedByteCount;
        final pending = _opens.remove(requestId);
        if (pending == null || pending.registration.sessionId != sessionId) {
          _failWorker();
          return;
        }
        final state = _NativeWorkerOwnedDeliverySessionState(
          this,
          pending.registration,
        );
        _sessions[sessionId] = state;
        pending.completer.complete(
          MeasurementWorkerOwnedDeliveryOpenSessionResult.opened(
            session: MeasurementWorkerOwnedDeliverySession.internal(
              state,
              sessionId,
            ),
            workerOwnedByteCount: _workerOwnedByteCount,
          ),
        );
      case MeasurementWorkerOwnedDeliveryOpenRejectedMessage(
          :final requestId,
          :final outcome,
          :final workerOwnedByteCount,
        ):
        _workerOwnedByteCount = workerOwnedByteCount;
        final pending = _opens.remove(requestId);
        if (pending == null) {
          _failWorker();
          return;
        }
        pending.completer.complete(
          MeasurementWorkerOwnedDeliveryOpenSessionResult.of(
            outcome,
            workerOwnedByteCount: _workerOwnedByteCount,
          ),
        );
      case MeasurementWorkerOwnedDeliveryAppendAcknowledgedMessage(
          :final sessionId,
          :final outcome,
          :final workerOwnedByteCount,
        ):
        _workerOwnedByteCount = workerOwnedByteCount;
        if (_pendingAppendCount > 0) _pendingAppendCount -= 1;
        if (outcome == MeasurementWorkerAppendAcknowledgementOutcome.rejected) {
          _sessions[sessionId]?._markUnavailable();
        }
        _appendAcknowledgements.add(
          MeasurementWorkerAppendAcknowledgement(
            sessionId: sessionId,
            outcome: outcome,
            workerOwnedByteCount: _workerOwnedByteCount,
          ),
        );
      case MeasurementWorkerOwnedDeliveryCheckpointResultMessage(
          :final requestId,
          :final outcome,
          :final sequence,
          :final isFinal,
          :final workerOwnedByteCount,
        ):
        _workerOwnedByteCount = workerOwnedByteCount;
        final pending = _checkpoints.remove(requestId);
        if (pending == null) {
          _failWorker();
          return;
        }
        _releaseControl();
        final result = MeasurementWorkerOwnedDeliveryCheckpointResult(
          outcome: outcome,
          sequence: sequence,
          isFinal: isFinal,
          workerOwnedByteCount: _workerOwnedByteCount,
        );
        pending.session._onCheckpointResult(result, isFinal: pending.isFinal);
        pending.completer.complete(result);
      case MeasurementWorkerOwnedDeliveryDiscardResultMessage(
          :final requestId,
          :final outcome,
          :final workerOwnedByteCount,
        ):
        _workerOwnedByteCount = workerOwnedByteCount;
        final pending = _discards.remove(requestId);
        if (pending == null) {
          _failWorker();
          return;
        }
        _releaseControl();
        final result = MeasurementWorkerOwnedDeliveryDiscardResult(
          outcome: outcome,
          workerOwnedByteCount: _workerOwnedByteCount,
        );
        pending.session._onDiscardResult(result);
        pending.completer.complete(result);
      case MeasurementWorkerOwnedDeliveryResetResultMessage(
          :final requestId,
          :final outcome,
          :final purgedRecordCount,
        ):
        final pending = _resets.remove(requestId);
        if (pending == null) {
          _failWorker();
          return;
        }
        _available = false;
        pending.complete(
          MeasurementWorkerOwnedDeliveryResetResult(
            outcome: outcome,
            purgedRecordCount: purgedRecordCount,
          ),
        );
        dispose();
      case MeasurementWorkerOwnedDeliveryShutdownResultMessage(
          :final requestId,
          :final outcome,
        ):
        final pending = _shutdowns.remove(requestId);
        if (pending == null) {
          _failWorker();
          return;
        }
        _available = false;
        pending.complete(MeasurementWorkerOwnedDeliveryShutdownResult(outcome));
        dispose();
      case MeasurementWorkerOwnedDeliveryDebugMessage(
          :final stage,
          :final workerIsolateId,
        ):
        _debugEvents.add(
          MeasurementWorkerOwnedDeliveryDebugEvent(
            stage: stage,
            workerIsolateId: workerIsolateId,
          ),
        );
      case MeasurementWorkerOwnedDeliveryFatalMessage():
        _failWorker();
    }
  }

  MeasurementWorkerOwnedDeliveryCheckpointResult _checkpointResult(
    MeasurementWorkerOwnedDeliveryCheckpointOutcome outcome,
  ) =>
      MeasurementWorkerOwnedDeliveryCheckpointResult(
        outcome: outcome,
        sequence: null,
        isFinal: null,
        workerOwnedByteCount: _workerOwnedByteCount,
      );

  MeasurementWorkerOwnedDeliveryDiscardResult _discardResult(
    MeasurementWorkerOwnedDeliveryDiscardOutcome outcome,
  ) =>
      MeasurementWorkerOwnedDeliveryDiscardResult(
        outcome: outcome,
        workerOwnedByteCount: _workerOwnedByteCount,
      );

  MeasurementWorkerOwnedDeliveryOpenSessionResult _unavailableOpenResult() =>
      MeasurementWorkerOwnedDeliveryOpenSessionResult.of(
        MeasurementWorkerOpenSessionOutcome.unavailable,
        workerOwnedByteCount: _workerOwnedByteCount,
      );

  MeasurementWorkerOwnedDeliveryResetResult _unavailableResetResult() =>
      const MeasurementWorkerOwnedDeliveryResetResult(
        outcome: MeasurementWorkerOwnedDeliveryResetOutcome.unavailable,
        purgedRecordCount: 0,
      );

  void _failWorker() {
    if (_disposed) return;
    _available = false;
    _stopping = true;
    for (final session in _sessions.values) {
      session._markUnavailable();
    }
    _sessions.clear();
    for (final pending in _opens.values) {
      pending.completer.complete(_unavailableOpenResult());
    }
    _opens.clear();
    for (final pending in _checkpoints.values) {
      pending.session._markUnavailable();
      pending.completer.complete(
        _checkpointResult(
          MeasurementWorkerOwnedDeliveryCheckpointOutcome.unavailable,
        ),
      );
    }
    _checkpoints.clear();
    for (final pending in _discards.values) {
      pending.session._markUnavailable();
      pending.completer.complete(
        _discardResult(
          MeasurementWorkerOwnedDeliveryDiscardOutcome.unavailable,
        ),
      );
    }
    _discards.clear();
    for (final pending in _resets.values) {
      pending.complete(_unavailableResetResult());
    }
    _resets.clear();
    for (final pending in _shutdowns.values) {
      pending.complete(
        const MeasurementWorkerOwnedDeliveryShutdownResult(
          MeasurementWorkerOwnedDeliveryShutdownOutcome.unavailable,
        ),
      );
    }
    _shutdowns.clear();
    _pendingAppendCount = 0;
    _pendingControlCount = 0;
    if (!_ready.isCompleted) {
      _ready.completeError(
        StateError('measurement delivery worker unavailable'),
      );
    }
    dispose();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _events.close();
    _errors.close();
    _exits.close();
    unawaited(_eventSubscription?.cancel());
    unawaited(_errorSubscription?.cancel());
    unawaited(_exitSubscription?.cancel());
    unawaited(_appendAcknowledgements.close());
    unawaited(_debugEvents.close());
  }
}

final class _WorkerOwnedDeliveryOpenPending {
  const _WorkerOwnedDeliveryOpenPending({
    required this.registration,
    required this.completer,
  });

  final MeasurementWorkerSessionRegistration registration;
  final Completer<MeasurementWorkerOwnedDeliveryOpenSessionResult> completer;
}

final class _WorkerOwnedDeliveryCheckpointPending {
  const _WorkerOwnedDeliveryCheckpointPending({
    required this.session,
    required this.isFinal,
    required this.completer,
  });

  final _NativeWorkerOwnedDeliverySessionState session;
  final bool isFinal;
  final Completer<MeasurementWorkerOwnedDeliveryCheckpointResult> completer;
}

final class _WorkerOwnedDeliveryDiscardPending {
  const _WorkerOwnedDeliveryDiscardPending({
    required this.session,
    required this.completer,
  });

  final _NativeWorkerOwnedDeliverySessionState session;
  final Completer<MeasurementWorkerOwnedDeliveryDiscardResult> completer;
}

enum _NativeWorkerOwnedDeliverySessionStatus {
  active,
  finalizing,
  discarding,
  finalized,
  unavailable,
}

final class _NativeWorkerOwnedDeliverySessionState
    implements MeasurementWorkerOwnedDeliverySessionState {
  _NativeWorkerOwnedDeliverySessionState(this._runtime, this._registration);

  final _NativeMeasurementWorkerOwnedDeliveryState _runtime;
  final MeasurementWorkerSessionRegistration _registration;
  _NativeWorkerOwnedDeliverySessionStatus _status =
      _NativeWorkerOwnedDeliverySessionStatus.active;
  int _lastTimestampMicros = -1;
  int? _barrierRequestId;

  String get sessionId => _registration.sessionId;

  @override
  MeasurementWorkerAppendOutcome append(MeasurementWorkerAppendRecord record) {
    if (record.routeIndex < 0 ||
        record.routeIndex >= _registration.routes.length ||
        record.monotonicTimestampMicros < _lastTimestampMicros) {
      return MeasurementWorkerAppendOutcome.invalid;
    }
    return switch (_status) {
      _NativeWorkerOwnedDeliverySessionStatus.active => _runtime.append(
          this,
          record,
        ),
      _NativeWorkerOwnedDeliverySessionStatus.finalizing ||
      _NativeWorkerOwnedDeliverySessionStatus.discarding ||
      _NativeWorkerOwnedDeliverySessionStatus.finalized =>
        MeasurementWorkerAppendOutcome.finalized,
      _NativeWorkerOwnedDeliverySessionStatus.unavailable =>
        MeasurementWorkerAppendOutcome.unavailable,
    };
  }

  @override
  Future<MeasurementWorkerOwnedDeliveryCheckpointResult> checkpoint() {
    if (_status == _NativeWorkerOwnedDeliverySessionStatus.unavailable) {
      return Future.value(
        _runtime._checkpointResult(
          MeasurementWorkerOwnedDeliveryCheckpointOutcome.unavailable,
        ),
      );
    }
    if (_status != _NativeWorkerOwnedDeliverySessionStatus.active) {
      return Future.value(
        _runtime._checkpointResult(
          MeasurementWorkerOwnedDeliveryCheckpointOutcome.finalized,
        ),
      );
    }
    return _runtime.requestCheckpoint(this, isFinal: false);
  }

  @override
  Future<MeasurementWorkerOwnedDeliveryCheckpointResult> teardown() {
    if (_status == _NativeWorkerOwnedDeliverySessionStatus.unavailable) {
      return Future.value(
        _runtime._checkpointResult(
          MeasurementWorkerOwnedDeliveryCheckpointOutcome.unavailable,
        ),
      );
    }
    if (_status != _NativeWorkerOwnedDeliverySessionStatus.active) {
      return Future.value(
        _runtime._checkpointResult(
          MeasurementWorkerOwnedDeliveryCheckpointOutcome.finalized,
        ),
      );
    }
    return _runtime.requestCheckpoint(this, isFinal: true);
  }

  @override
  Future<MeasurementWorkerOwnedDeliveryDiscardResult> discard() {
    if (_status == _NativeWorkerOwnedDeliverySessionStatus.unavailable) {
      return Future.value(
        _runtime._discardResult(
          MeasurementWorkerOwnedDeliveryDiscardOutcome.unavailable,
        ),
      );
    }
    if (_status != _NativeWorkerOwnedDeliverySessionStatus.active) {
      return Future.value(
        _runtime._discardResult(
          MeasurementWorkerOwnedDeliveryDiscardOutcome.finalized,
        ),
      );
    }
    return _runtime.requestDiscard(this);
  }

  void _onCheckpointResult(
    MeasurementWorkerOwnedDeliveryCheckpointResult result, {
    required bool isFinal,
  }) {
    _barrierRequestId = null;
    if (!isFinal) return;
    _status = result.outcome ==
            MeasurementWorkerOwnedDeliveryCheckpointOutcome.unavailable
        ? _NativeWorkerOwnedDeliverySessionStatus.unavailable
        : _NativeWorkerOwnedDeliverySessionStatus.finalized;
    _runtime._sessions.remove(sessionId);
  }

  void _onDiscardResult(MeasurementWorkerOwnedDeliveryDiscardResult result) {
    _barrierRequestId = null;
    _status = result.outcome ==
            MeasurementWorkerOwnedDeliveryDiscardOutcome.unavailable
        ? _NativeWorkerOwnedDeliverySessionStatus.unavailable
        : _NativeWorkerOwnedDeliverySessionStatus.finalized;
    _runtime._sessions.remove(sessionId);
  }

  void _markUnavailable() =>
      _status = _NativeWorkerOwnedDeliverySessionStatus.unavailable;
}

/// Native entrypoint for the one long-lived aggregation/outbox/upload worker.
///
/// The bootstrap receives a root-owned [SendPort], a plain support path, and
/// immutable primitive configuration. It deliberately receives no plugin,
/// codec, HTTP client, file handle, preferences object, callback, or UI value.
@pragma('vm:entry-point')
void measurementWorkerOwnedDeliveryIsolateMain(List<Object?> bootstrap) {
  unawaited(_runMeasurementWorkerOwnedDeliveryIsolate(bootstrap));
}

Future<void> _runMeasurementWorkerOwnedDeliveryIsolate(
  List<Object?> bootstrap,
) async {
  if (bootstrap.length != 2 || bootstrap[0] is! SendPort) return;
  final events = bootstrap[0]! as SendPort;
  try {
    final rawConfiguration = bootstrap[1];
    if (rawConfiguration is! List ||
        rawConfiguration.length != 6 ||
        rawConfiguration[0] is! String) {
      events.send(MeasurementWorkerOwnedDeliveryProtocol.fatal());
      return;
    }
    final supportPath = rawConfiguration[0]! as String;
    final configuration =
        MeasurementWorkerOwnedDeliveryConfiguration.fromWorkerBootstrapWire(
      rawConfiguration,
    );
    final outbox = createMeasurementOutboxStore(
      configuration: MeasurementOutboxConfiguration(
        applicationSupportPath: supportPath,
        configurationFingerprint: configuration.configurationFingerprint,
      ),
      clock: DateTime.now,
    );
    final opened = await outbox.open();
    if (!opened.isOpened) {
      events.send(MeasurementWorkerOwnedDeliveryProtocol.fatal());
      return;
    }
    final headers = <String, String>{};
    for (final header in configuration.headers) {
      if (headers.containsKey(header.name)) {
        events.send(MeasurementWorkerOwnedDeliveryProtocol.fatal());
        return;
      }
      headers[header.name] = header.value;
    }
    final workerIsolateId = Isolate.current.hashCode;
    late final _MeasurementWorkerOwnedDeliveryKernel kernel;
    final uploadClient = _WorkerOwnedTracingUploadClient(
      delegate: createMeasurementUploadClient(
        configuration: MeasurementUploadConfiguration(
          endpoint: Uri.parse(configuration.endpoint!),
          headersProvider: () => headers,
        ),
      ),
      onSend: () => kernel.trace(MeasurementWorkerOwnedDeliveryDebugStage.http),
    );
    kernel = _MeasurementWorkerOwnedDeliveryKernel(
      events: events,
      store: outbox,
      uploadCoordinator: MeasurementOutboxUploadCoordinator(
        store: outbox,
        uploadClient: uploadClient,
      ),
      maximumSessions: configuration.maximumSessions,
      workerIsolateId: workerIsolateId,
      debugTracing: configuration.debugTracing,
    );
    final commands = ReceivePort();
    kernel.attach(commands);
    events.send(
      MeasurementWorkerOwnedDeliveryProtocol.ready(
        commandPort: commands.sendPort,
        workerIsolateId: workerIsolateId,
      ),
    );
    commands.listen(kernel.handle);
    kernel.start();
  } on Object {
    events.send(MeasurementWorkerOwnedDeliveryProtocol.fatal());
  }
}

final class _MeasurementWorkerOwnedDeliveryKernel {
  _MeasurementWorkerOwnedDeliveryKernel({
    required this.events,
    required this.store,
    required this.uploadCoordinator,
    required this.maximumSessions,
    required this.workerIsolateId,
    required this.debugTracing,
  });

  final SendPort events;
  final MeasurementOutboxStore store;
  final MeasurementOutboxUploadCoordinator uploadCoordinator;
  final int maximumSessions;
  final int workerIsolateId;
  final bool debugTracing;
  final Map<String, _WorkerSession> _sessions = {};
  Future<void> _commandTail = Future<void>.value();
  ReceivePort? _commands;
  Timer? _retryTimer;
  bool _closed = false;

  void attach(ReceivePort commands) {
    _commands = commands;
  }

  void start() => _enqueue(() async {
        trace(MeasurementWorkerOwnedDeliveryDebugStage.journal);
        await _drainAndSchedule();
      });

  void handle(Object? raw) => _enqueue(() => _handle(raw));

  void _enqueue(Future<void> Function() operation) {
    _commandTail = _commandTail
        .then<void>((_) => operation())
        .onError((Object _, StackTrace __) => _fatal());
  }

  Future<void> _handle(Object? raw) async {
    if (_closed) return;
    late final MeasurementWorkerOwnedDeliveryInboundMessage message;
    try {
      message = MeasurementWorkerOwnedDeliveryProtocol.decodeInbound(raw);
    } on Object {
      _fatal();
      return;
    }
    switch (message) {
      case MeasurementWorkerOwnedDeliveryRegisterMessage():
        _register(message);
      case MeasurementWorkerOwnedDeliveryAppendMessage():
        _append(message);
      case MeasurementWorkerOwnedDeliveryCheckpointMessage():
        await _checkpoint(message);
      case MeasurementWorkerOwnedDeliveryDiscardMessage():
        _discard(message);
      case MeasurementWorkerOwnedDeliveryResetMessage():
        await _reset(message);
      case MeasurementWorkerOwnedDeliveryShutdownMessage():
        await _shutdown(message);
    }
  }

  void _register(MeasurementWorkerOwnedDeliveryRegisterMessage message) {
    if (_sessions.length >= maximumSessions) {
      _sendOpenRejected(
        requestId: message.requestId,
        outcome: MeasurementWorkerOpenSessionOutcome.saturated,
      );
      return;
    }
    if (_sessions.containsKey(message.registration.sessionId)) {
      _sendOpenRejected(
        requestId: message.requestId,
        outcome: MeasurementWorkerOpenSessionOutcome.invalid,
      );
      return;
    }
    try {
      final session = _WorkerSession.fromRegistration(message.registration);
      _sessions[session.sessionId] = session;
      events.send(
        MeasurementWorkerOwnedDeliveryProtocol.opened(
          requestId: message.requestId,
          sessionId: session.sessionId,
          workerOwnedByteCount: _ownedByteCount,
        ),
      );
    } on Object {
      _sendOpenRejected(
        requestId: message.requestId,
        outcome: MeasurementWorkerOpenSessionOutcome.invalid,
      );
    }
  }

  void _append(MeasurementWorkerOwnedDeliveryAppendMessage message) {
    final session = _sessions[message.sessionId];
    final outcome = session == null
        ? MeasurementWorkerAppendAcknowledgementOutcome.rejected
        : session.append(message.record);
    events.send(
      MeasurementWorkerOwnedDeliveryProtocol.appendAcknowledged(
        sessionId: message.sessionId,
        outcome: outcome,
        workerOwnedByteCount: _ownedByteCount,
      ),
    );
  }

  Future<void> _checkpoint(
    MeasurementWorkerOwnedDeliveryCheckpointMessage message,
  ) async {
    final session = _sessions[message.sessionId];
    if (session == null) {
      _sendCheckpointResult(
        requestId: message.requestId,
        outcome: MeasurementWorkerOwnedDeliveryCheckpointOutcome.finalized,
        sequence: null,
        isFinal: null,
      );
      return;
    }
    final result = await _prepareAndDeliver(session, isFinal: message.isFinal);
    if (message.isFinal) _sessions.remove(session.sessionId);
    _sendCheckpointResult(
      requestId: message.requestId,
      outcome: result.outcome,
      sequence: result.sequence,
      isFinal: result.isFinal,
    );
  }

  void _discard(MeasurementWorkerOwnedDeliveryDiscardMessage message) {
    final session = _sessions.remove(message.sessionId);
    final outcome = session == null
        ? MeasurementWorkerOwnedDeliveryDiscardOutcome.finalized
        : MeasurementWorkerOwnedDeliveryDiscardOutcome.discarded;
    events.send(
      MeasurementWorkerOwnedDeliveryProtocol.discardResult(
        requestId: message.requestId,
        outcome: outcome,
        workerOwnedByteCount: _ownedByteCount,
      ),
    );
  }

  Future<_WorkerOwnedDeliveryPreparedResult> _prepareAndDeliver(
    _WorkerSession session, {
    required bool isFinal,
  }) async {
    late final _WorkerPreparedBatch workerBatch;
    try {
      if (isFinal) session.advanceForFinalization();
      workerBatch = _WorkerPreparedBatch.fromSession(session, isFinal: isFinal);
      if (!isFinal) session.checkpointBatchId = workerBatch.batchId;
      trace(MeasurementWorkerOwnedDeliveryDebugStage.canonicalized);
    } on Object {
      return _WorkerOwnedDeliveryPreparedResult(
        outcome:
            MeasurementWorkerOwnedDeliveryCheckpointOutcome.persistenceFailure,
        sequence: null,
        isFinal: null,
      );
    }

    late final MeasurementOutboxPreparedBatch batch;
    try {
      batch = MeasurementOutboxPreparedBatch.fromWorkerPreparedBatch(
        workerBatch.toPublic(),
      );
      trace(MeasurementWorkerOwnedDeliveryDebugStage.hashedAndPrepared);
    } on Object {
      return _WorkerOwnedDeliveryPreparedResult(
        outcome:
            MeasurementWorkerOwnedDeliveryCheckpointOutcome.persistenceFailure,
        sequence: workerBatch.sequence,
        isFinal: workerBatch.isFinal,
      );
    }

    trace(MeasurementWorkerOwnedDeliveryDebugStage.journal);
    final committed = await store.commit(batch);
    switch (committed.outcome) {
      case MeasurementOutboxCommitOutcome.committed ||
            MeasurementOutboxCommitOutcome.duplicate:
        final uploaded = await uploadCoordinator.uploadNext();
        await _scheduleNextDelivery();
        return _WorkerOwnedDeliveryPreparedResult(
          outcome: _checkpointOutcomeForUpload(uploaded.outcome),
          sequence: workerBatch.sequence,
          isFinal: workerBatch.isFinal,
        );
      case MeasurementOutboxCommitOutcome.payloadTooLarge:
        return _WorkerOwnedDeliveryPreparedResult(
          outcome:
              MeasurementWorkerOwnedDeliveryCheckpointOutcome.payloadTooLarge,
          sequence: workerBatch.sequence,
          isFinal: workerBatch.isFinal,
        );
      case MeasurementOutboxCommitOutcome.outboxSaturated:
        return _WorkerOwnedDeliveryPreparedResult(
          outcome:
              MeasurementWorkerOwnedDeliveryCheckpointOutcome.outboxSaturated,
          sequence: workerBatch.sequence,
          isFinal: workerBatch.isFinal,
        );
      case MeasurementOutboxCommitOutcome.persistenceFailure:
        return _WorkerOwnedDeliveryPreparedResult(
          outcome: MeasurementWorkerOwnedDeliveryCheckpointOutcome
              .persistenceFailure,
          sequence: workerBatch.sequence,
          isFinal: workerBatch.isFinal,
        );
      case MeasurementOutboxCommitOutcome.unavailable:
        return _WorkerOwnedDeliveryPreparedResult(
          outcome: MeasurementWorkerOwnedDeliveryCheckpointOutcome.unavailable,
          sequence: workerBatch.sequence,
          isFinal: workerBatch.isFinal,
        );
      case MeasurementOutboxCommitOutcome.sequenceConflict:
        return _WorkerOwnedDeliveryPreparedResult(
          outcome: MeasurementWorkerOwnedDeliveryCheckpointOutcome
              .persistenceFailure,
          sequence: workerBatch.sequence,
          isFinal: workerBatch.isFinal,
        );
    }
  }

  Future<void> _drainAndSchedule() async {
    if (_closed) return;
    await uploadCoordinator.uploadNext();
    await _scheduleNextDelivery();
  }

  Future<void> _scheduleNextDelivery() async {
    _retryTimer?.cancel();
    _retryTimer = null;
    if (_closed || store is! MeasurementOutboxRetrySchedule) return;
    final delay =
        await (store as MeasurementOutboxRetrySchedule).nextReadyDelay();
    if (_closed || delay == null) return;
    _retryTimer = Timer(delay, () => _enqueue(_drainAndSchedule));
  }

  Future<void> _reset(
    MeasurementWorkerOwnedDeliveryResetMessage message,
  ) async {
    _closed = true;
    _retryTimer?.cancel();
    final result = await uploadCoordinator.purge(message.reason);
    final outcome = switch (result.outcome) {
      MeasurementOutboxPurgeOutcome.purgedUnacknowledged ||
      MeasurementOutboxPurgeOutcome.configurationReset ||
      MeasurementOutboxPurgeOutcome.retentionExpired =>
        MeasurementWorkerOwnedDeliveryResetOutcome.purged,
      MeasurementOutboxPurgeOutcome.failed =>
        MeasurementWorkerOwnedDeliveryResetOutcome.failed,
      MeasurementOutboxPurgeOutcome.unavailable =>
        MeasurementWorkerOwnedDeliveryResetOutcome.unavailable,
    };
    events.send(
      MeasurementWorkerOwnedDeliveryProtocol.resetResult(
        requestId: message.requestId,
        outcome: outcome,
        purgedRecordCount: result.purgedRecordCount,
      ),
    );
    _commands?.close();
  }

  Future<void> _shutdown(
    MeasurementWorkerOwnedDeliveryShutdownMessage message,
  ) async {
    var outcome = MeasurementWorkerOwnedDeliveryShutdownOutcome.closed;
    final sessions = _sessions.values.toList()
      ..sort((left, right) => left.sessionId.compareTo(right.sessionId));
    for (final session in sessions) {
      final result = await _prepareAndDeliver(session, isFinal: true);
      if (!_isDurablyRetained(result.outcome)) {
        outcome = MeasurementWorkerOwnedDeliveryShutdownOutcome.unavailable;
        break;
      }
    }
    _sessions.clear();
    _closed = true;
    _retryTimer?.cancel();
    events.send(
      MeasurementWorkerOwnedDeliveryProtocol.shutdownResult(
        requestId: message.requestId,
        outcome: outcome,
      ),
    );
    _commands?.close();
  }

  bool _isDurablyRetained(
    MeasurementWorkerOwnedDeliveryCheckpointOutcome outcome,
  ) =>
      switch (outcome) {
        MeasurementWorkerOwnedDeliveryCheckpointOutcome.delivered ||
        MeasurementWorkerOwnedDeliveryCheckpointOutcome.committed ||
        MeasurementWorkerOwnedDeliveryCheckpointOutcome.retryScheduled ||
        MeasurementWorkerOwnedDeliveryCheckpointOutcome.held ||
        MeasurementWorkerOwnedDeliveryCheckpointOutcome.quarantined ||
        MeasurementWorkerOwnedDeliveryCheckpointOutcome
              .acknowledgedPendingCleanup =>
          true,
        MeasurementWorkerOwnedDeliveryCheckpointOutcome.retentionExpired ||
        MeasurementWorkerOwnedDeliveryCheckpointOutcome.payloadTooLarge ||
        MeasurementWorkerOwnedDeliveryCheckpointOutcome.outboxSaturated ||
        MeasurementWorkerOwnedDeliveryCheckpointOutcome.persistenceFailure ||
        MeasurementWorkerOwnedDeliveryCheckpointOutcome.unavailable ||
        MeasurementWorkerOwnedDeliveryCheckpointOutcome.finalized ||
        MeasurementWorkerOwnedDeliveryCheckpointOutcome.saturated =>
          false,
      };

  MeasurementWorkerOwnedDeliveryCheckpointOutcome _checkpointOutcomeForUpload(
    MeasurementOutboxUploadOutcome outcome,
  ) =>
      switch (outcome) {
        MeasurementOutboxUploadOutcome.delivered =>
          MeasurementWorkerOwnedDeliveryCheckpointOutcome.delivered,
        MeasurementOutboxUploadOutcome.acknowledgedPendingCleanup =>
          MeasurementWorkerOwnedDeliveryCheckpointOutcome
              .acknowledgedPendingCleanup,
        MeasurementOutboxUploadOutcome.retryScheduled =>
          MeasurementWorkerOwnedDeliveryCheckpointOutcome.retryScheduled,
        MeasurementOutboxUploadOutcome.held =>
          MeasurementWorkerOwnedDeliveryCheckpointOutcome.held,
        MeasurementOutboxUploadOutcome.quarantined =>
          MeasurementWorkerOwnedDeliveryCheckpointOutcome.quarantined,
        MeasurementOutboxUploadOutcome.retentionExpired =>
          MeasurementWorkerOwnedDeliveryCheckpointOutcome.retentionExpired,
        MeasurementOutboxUploadOutcome.idle ||
        MeasurementOutboxUploadOutcome.busy =>
          MeasurementWorkerOwnedDeliveryCheckpointOutcome.committed,
        MeasurementOutboxUploadOutcome.unavailable =>
          MeasurementWorkerOwnedDeliveryCheckpointOutcome.unavailable,
        MeasurementOutboxUploadOutcome.persistenceFailure =>
          MeasurementWorkerOwnedDeliveryCheckpointOutcome.persistenceFailure,
      };

  void _sendOpenRejected({
    required int requestId,
    required MeasurementWorkerOpenSessionOutcome outcome,
  }) {
    events.send(
      MeasurementWorkerOwnedDeliveryProtocol.openRejected(
        requestId: requestId,
        outcome: outcome,
        workerOwnedByteCount: _ownedByteCount,
      ),
    );
  }

  void _sendCheckpointResult({
    required int requestId,
    required MeasurementWorkerOwnedDeliveryCheckpointOutcome outcome,
    required int? sequence,
    required bool? isFinal,
  }) {
    events.send(
      MeasurementWorkerOwnedDeliveryProtocol.checkpointResult(
        requestId: requestId,
        outcome: outcome,
        sequence: sequence,
        isFinal: isFinal,
        workerOwnedByteCount: _ownedByteCount,
      ),
    );
  }

  void trace(MeasurementWorkerOwnedDeliveryDebugStage stage) {
    if (!debugTracing) return;
    events.send(
      MeasurementWorkerOwnedDeliveryProtocol.debug(
        stage: stage,
        workerIsolateId: workerIsolateId,
      ),
    );
  }

  int get _ownedByteCount => _sessions.values.fold<int>(
        0,
        (total, session) => total + session.structuralOwnedByteCount,
      );

  void _fatal() {
    if (_closed) return;
    _closed = true;
    _retryTimer?.cancel();
    events.send(MeasurementWorkerOwnedDeliveryProtocol.fatal());
    _commands?.close();
  }
}

final class _WorkerOwnedDeliveryPreparedResult {
  const _WorkerOwnedDeliveryPreparedResult({
    required this.outcome,
    required this.sequence,
    required this.isFinal,
  });

  final MeasurementWorkerOwnedDeliveryCheckpointOutcome outcome;
  final int? sequence;
  final bool? isFinal;
}

final class _WorkerOwnedTracingUploadClient implements MeasurementUploadClient {
  const _WorkerOwnedTracingUploadClient({
    required this.delegate,
    required this.onSend,
  });

  final MeasurementUploadClient delegate;
  final void Function() onSend;

  @override
  Future<MeasurementUploadOutcome> send(MeasurementOutboxLease lease) async {
    onSend();
    return delegate.send(lease);
  }
}
