import 'package:meta/meta.dart';

import 'measurement_worker_delivery_unsupported.dart'
    if (dart.library.io) 'measurement_worker_native.dart' as implementation;
import 'measurement_outbox_protocol.dart';
import 'measurement_worker_delivery_protocol.dart';
import 'measurement_worker_protocol.dart';

export 'measurement_worker_delivery_protocol.dart';

/// Closed result of trying to create a delivery runtime.
enum MeasurementWorkerOwnedDeliveryStartOutcome {
  /// One native long-lived worker is ready.
  started,

  /// An admission predicate denied collection before all delivery work.
  notAdmitted,

  /// Path resolution, isolate startup, or native outbox startup failed closed.
  unavailable,
}

/// Root-visible result of starting one delivery runtime.
final class MeasurementWorkerOwnedDeliveryStartResult {
  const MeasurementWorkerOwnedDeliveryStartResult._({
    required this.outcome,
    required this.runtime,
    required this.denial,
    required this.unavailableReason,
  });

  /// Closed startup outcome.
  final MeasurementWorkerOwnedDeliveryStartOutcome outcome;

  /// The live runtime only on [MeasurementWorkerOwnedDeliveryStartOutcome.started].
  final MeasurementWorkerOwnedDeliveryRuntime? runtime;

  /// Intentional no-measurement reason only for [MeasurementWorkerOwnedDeliveryStartOutcome.notAdmitted].
  final MeasurementWorkerOwnedDeliveryAdmissionDenial? denial;

  /// Stable fail-closed reason only for unavailable startup.
  final String? unavailableReason;

  factory MeasurementWorkerOwnedDeliveryStartResult.started(
    MeasurementWorkerOwnedDeliveryRuntime runtime,
  ) =>
      MeasurementWorkerOwnedDeliveryStartResult._(
        outcome: MeasurementWorkerOwnedDeliveryStartOutcome.started,
        runtime: runtime,
        denial: null,
        unavailableReason: null,
      );

  factory MeasurementWorkerOwnedDeliveryStartResult.notAdmitted(
    MeasurementWorkerOwnedDeliveryAdmissionDenial denial,
  ) =>
      MeasurementWorkerOwnedDeliveryStartResult._(
        outcome: MeasurementWorkerOwnedDeliveryStartOutcome.notAdmitted,
        runtime: null,
        denial: denial,
        unavailableReason: null,
      );

  factory MeasurementWorkerOwnedDeliveryStartResult.unavailable(
          String reason) =>
      MeasurementWorkerOwnedDeliveryStartResult._(
        outcome: MeasurementWorkerOwnedDeliveryStartOutcome.unavailable,
        runtime: null,
        denial: null,
        unavailableReason: reason,
      );
}

/// Internal bootstrap seam for the one worker-owned measurement outbox.
///
/// No production host constructs this runtime yet. The future host lane must
/// prove [MeasurementWorkerOwnedDeliveryConfiguration.admission] before it
/// calls this seam; this facade independently preserves that fail-closed rule.
final class MeasurementWorkerOwnedDeliveryRuntime {
  MeasurementWorkerOwnedDeliveryRuntime._(this._state);

  final MeasurementWorkerOwnedDeliveryRuntimeState _state;

  /// Wraps a deterministic worker port for construction-plane qualification.
  ///
  /// Production always enters through [start]; this factory only lets widget
  /// tests exercise the same owner and host lifecycle without coupling an
  /// isolate-ready callback to Flutter's fake-async scheduler.
  @visibleForTesting
  factory MeasurementWorkerOwnedDeliveryRuntime.fromTestingState(
    MeasurementWorkerOwnedDeliveryRuntimeState state,
  ) =>
      MeasurementWorkerOwnedDeliveryRuntime._(state);

  /// Starts one long-lived native worker only after all admission predicates hold.
  static Future<MeasurementWorkerOwnedDeliveryStartResult> start({
    required MeasurementWorkerOwnedDeliveryConfiguration configuration,
    MeasurementWorkerOwnedDeliveryPathResolver? pathResolver,
  }) async {
    final denial = configuration.admission.denial;
    if (denial != null) {
      return MeasurementWorkerOwnedDeliveryStartResult.notAdmitted(denial);
    }
    if (!configuration.isValidForStartup) {
      return MeasurementWorkerOwnedDeliveryStartResult.unavailable(
        'invalid_worker_owned_delivery_configuration',
      );
    }
    final launched = await implementation.startMeasurementWorkerOwnedDelivery(
      configuration: configuration,
      pathResolver: pathResolver,
    );
    final state = launched.state;
    if (state == null) {
      return MeasurementWorkerOwnedDeliveryStartResult.unavailable(
        launched.unavailableReason ?? 'worker_owned_delivery_unavailable',
      );
    }
    return MeasurementWorkerOwnedDeliveryStartResult.started(
      MeasurementWorkerOwnedDeliveryRuntime._(state),
    );
  }

  /// Whether the current generation can accept further compact appends.
  bool get isAvailable => _state.isAvailable;

  /// Worker-owned structural bytes last reported by the native isolate.
  int get workerOwnedByteCount => _state.workerOwnedByteCount;

  /// Exactly one native worker is spawned for a successfully started runtime.
  int get debugWorkerSpawnCount => _state.debugWorkerSpawnCount;

  /// Test-only worker-isolate identity reported at startup.
  int? get debugWorkerIsolateId => _state.debugWorkerIsolateId;

  /// Worker acknowledgements replenish the fixed 256-message UI handoff credits.
  Stream<MeasurementWorkerAppendAcknowledgement> get appendAcknowledgements =>
      _state.appendAcknowledgements;

  /// Test-only causal trace proving CPU, journal, and HTTP ownership.
  Stream<MeasurementWorkerOwnedDeliveryDebugEvent> get debugEvents =>
      _state.debugEvents;

  /// Registers one capture session before it can synchronously append records.
  Future<MeasurementWorkerOwnedDeliveryOpenSessionResult> openSession(
    MeasurementWorkerSessionRegistration registration,
  ) =>
      _state.openSession(registration);

  /// Stops the old generation before purging it for reset/cutover.
  ///
  /// The runtime remains disabled whether purge succeeds or fails. A caller may
  /// start a new generation only after receiving a truthful successful result.
  Future<MeasurementWorkerOwnedDeliveryResetResult> reset(
    MeasurementOutboxPurgeReason reason,
  ) =>
      _state.reset(reason);

  /// Stops a quiescent worker without making a UI-isolate fallback available.
  Future<MeasurementWorkerOwnedDeliveryShutdownResult> shutdown() =>
      _state.shutdown();

  /// Test-only crash control used to prove all later calls fail closed.
  void debugKillWorkerForTesting() => _state.debugKillWorkerForTesting();
}
