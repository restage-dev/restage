import 'measurement_worker_unsupported.dart'
    if (dart.library.io) 'measurement_worker_native.dart' as implementation;
import 'measurement_worker_protocol.dart';

export 'measurement_worker_protocol.dart';

/// Public internal facade for the one configured native measurement worker.
final class MeasurementWorkerRuntime {
  MeasurementWorkerRuntime._(this._state);

  final MeasurementWorkerRuntimeState _state;

  /// Starts exactly one long-lived worker for this configured runtime.
  ///
  /// Unsupported platforms return [MeasurementWorkerRuntimeStartOutcome.unavailable]
  /// rather than falling back to UI-isolate work.
  static Future<MeasurementWorkerRuntimeStartResult> start({
    required MeasurementWorkerRuntimeConfiguration configuration,
  }) async {
    final launch = await implementation.startMeasurementWorkerRuntime(
      configuration: configuration,
    );
    final state = launch.state;
    if (state == null) {
      return MeasurementWorkerRuntimeStartResult.unavailable(
        launch.unavailableReason ?? 'worker_unavailable',
      );
    }
    return MeasurementWorkerRuntimeStartResult.started(
      MeasurementWorkerRuntime._(state),
    );
  }

  /// Whether the native worker can accept further commands.
  bool get isAvailable => _state.isAvailable;

  /// Deterministic structural bytes currently retained by the worker.
  int get workerOwnedByteCount => _state.workerOwnedByteCount;

  /// Native isolate count for one configured runtime.
  int get debugWorkerSpawnCount => _state.debugWorkerSpawnCount;

  /// Worker acknowledgements that replenish bounded UI append credits.
  Stream<MeasurementWorkerAppendAcknowledgement> get appendAcknowledgements =>
      _state.appendAcknowledgements;

  /// Opens one bounded worker session.
  Future<MeasurementWorkerOpenSessionResult> openSession(
    MeasurementWorkerSessionRegistration registration,
  ) =>
      _state.openSession(registration);

  /// Returns the exact retained bytes for a same-sequence retry.
  Future<MeasurementWorkerBatchResult> retryPreparedBatch(String batchId) =>
      _state.retryPreparedBatch(batchId);

  /// Releases worker ownership after a later delivery owner has accepted bytes.
  Future<MeasurementWorkerReleaseResult> releasePreparedBatch(String batchId) =>
      _state.releasePreparedBatch(batchId);

  /// Runs ordered finalization barriers and stops the one worker isolate.
  Future<MeasurementWorkerShutdownResult> shutdown() => _state.shutdown();

  /// Test-only crash control proving future calls fail closed.
  void debugKillWorkerForTesting() => _state.debugKillWorkerForTesting();
}

/// Closed outcome of starting a runtime worker.
enum MeasurementWorkerRuntimeStartOutcome {
  /// A native worker is available.
  started,

  /// The platform cannot provide a native isolate worker.
  unavailable,
}

/// Immutable result of starting a runtime worker.
final class MeasurementWorkerRuntimeStartResult {
  const MeasurementWorkerRuntimeStartResult._({
    required this.outcome,
    required this.runtime,
    required this.unavailableReason,
  });

  /// Closed startup result.
  final MeasurementWorkerRuntimeStartOutcome outcome;

  /// Runtime only when [outcome] is [MeasurementWorkerRuntimeStartOutcome.started].
  final MeasurementWorkerRuntime? runtime;

  /// Stable fail-closed reason only when startup is unavailable.
  final String? unavailableReason;

  factory MeasurementWorkerRuntimeStartResult.started(
    MeasurementWorkerRuntime runtime,
  ) =>
      MeasurementWorkerRuntimeStartResult._(
        outcome: MeasurementWorkerRuntimeStartOutcome.started,
        runtime: runtime,
        unavailableReason: null,
      );

  factory MeasurementWorkerRuntimeStartResult.unavailable(String reason) =>
      MeasurementWorkerRuntimeStartResult._(
        outcome: MeasurementWorkerRuntimeStartOutcome.unavailable,
        runtime: null,
        unavailableReason: reason,
      );
}
