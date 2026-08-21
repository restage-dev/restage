import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:restage/src/measurement/measurement_host_construction_owner.dart';
import 'package:restage/src/measurement/measurement_host_session.dart';
import 'package:restage/src/measurement/measurement_outbox_protocol.dart';
import 'package:restage/src/measurement/measurement_worker_delivery.dart';
import 'package:restage/src/measurement/measurement_worker_protocol.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

/// Synchronous test authority proving a real Source root reaches owner
/// admission without starting an isolate inside Flutter test fake async.
///
/// The owner is deliberately denied by `analyticsEnabled: false`. That makes
/// path lookup, worker start, outbox, frame, request, and credential creation
/// impossible while preserving ordinary root rendering and callbacks. The
/// worker-backed owner tests separately qualify the real isolate runtime.
final class ConstructionOwnerHostTestHarness {
  ConstructionOwnerHostTestHarness._(
    this.owner,
    this._restore,
    this._pathResolver,
  );

  final MeasurementHostConstructionOwner owner;
  final void Function() _restore;
  final _PathProbe _pathResolver;
  Future<void>? _closeFuture;

  /// Installs a new-only authority whose exact owner denies before delivery.
  static ConstructionOwnerHostTestHarness installDenied({
    required ExactMeasurementPublicationContextRefV1 publicationContext,
    required MeasurementPublicationBindingReadPort? Function()
        hostedBindingReadPortLookup,
    String? endpoint = 'https://example.invalid/sdk/v1/measurement',
    bool analyticsEnabled = true,
    MeasurementHostConstructionPolicyStatus policyStatus =
        MeasurementHostConstructionPolicyStatus.supported,
    bool measurementClassAdmitted = true,
    int remainingSessionBudget = 1,
    bool deliveryAdapterAvailable = true,
  }) {
    final pathResolver = _PathProbe();
    final owner = MeasurementHostConstructionOwner.forTesting(
      profileReadPort: _ExactProfileReadPort(
        MeasurementHostConstructionProfile(
          publicationContext: publicationContext,
          endpoint: endpoint,
          analyticsEnabled: analyticsEnabled,
          policyStatus: policyStatus,
          measurementClassAdmitted: measurementClassAdmitted,
          remainingSessionBudget: remainingSessionBudget,
          deliveryAdapterAvailable: deliveryAdapterAvailable,
          configurationFingerprint: 'root-host-denial-test.v1',
        ),
      ),
      pathResolver: pathResolver,
    );
    var nonce = 0;
    final restore = MeasurementHostSessionConstructionRegistry.installForTest(
      MeasurementHostSessionConstructionAuthority.forWorkerOwnedDeliveryTesting(
        constructionOwner: owner,
        nonceBytesSource: () => List<int>.filled(32, ++nonce),
        hostedBindingReadPortLookup: hostedBindingReadPortLookup,
      ),
    );
    return ConstructionOwnerHostTestHarness._(owner, restore, pathResolver);
  }

  /// A denied Source root must never ask the platform for a support directory.
  int get pathLookups => _pathResolver.calls;

  /// Restores the exact registry installation and closes the inert owner once.
  Future<void> close() {
    final existing = _closeFuture;
    if (existing != null) return existing;
    _restore();
    final future = owner.close();
    _closeFuture = future;
    return future;
  }
}

/// Deterministic worker-backed authority for real Flutter Source-root tests.
///
/// It is injected below [MeasurementHostConstructionOwner] only through that
/// owner's test-only starter. Production still calls the parent concrete
/// [MeasurementWorkerOwnedDeliveryRuntime.start] path. This lets widget tests
/// exercise the exact admitted owner, first-paint, action, lifecycle, failure,
/// and disposal paths without placing an isolate-ready callback in fake async.
final class AdmittedConstructionOwnerHostTestHarness {
  AdmittedConstructionOwnerHostTestHarness._(
    this.owner,
    this.worker,
    this.lifecycle,
    this._restore,
  );

  final MeasurementHostConstructionOwner owner;
  final DeterministicMeasurementDeliveryWorker worker;
  final ConstructionOwnerLifecycleProbe lifecycle;
  final void Function() _restore;
  Future<void>? _closeFuture;

  /// Installs one admitted new-only owner with one deterministic worker port.
  static AdmittedConstructionOwnerHostTestHarness install({
    required ExactMeasurementPublicationContextRefV1 publicationContext,
    required MeasurementPublicationBindingReadPort? Function()
        hostedBindingReadPortLookup,
    int remainingSessionBudget = 16,
  }) {
    final worker = DeterministicMeasurementDeliveryWorker();
    final lifecycle = ConstructionOwnerLifecycleProbe();
    final owner = MeasurementHostConstructionOwner.forTesting(
      profileReadPort: _ExactProfileReadPort(
        MeasurementHostConstructionProfile(
          publicationContext: publicationContext,
          endpoint: 'https://example.invalid/sdk/v1/measurement',
          analyticsEnabled: true,
          policyStatus: MeasurementHostConstructionPolicyStatus.supported,
          measurementClassAdmitted: true,
          remainingSessionBudget: remainingSessionBudget,
          deliveryAdapterAvailable: true,
          configurationFingerprint: 'root-host-deterministic-worker.v1',
        ),
      ),
      pathResolver: _PathProbe(),
      workerRuntimeStarter: ({required configuration, required pathResolver}) {
        worker.start(configuration);
        return Future<MeasurementWorkerOwnedDeliveryRuntime?>.value(
          MeasurementWorkerOwnedDeliveryRuntime.fromTestingState(worker),
        );
      },
    );
    var nonce = 0;
    final restore = MeasurementHostSessionConstructionRegistry.installForTest(
      MeasurementHostSessionConstructionAuthority.forWorkerOwnedDeliveryTesting(
        constructionOwner: owner,
        nonceBytesSource: () => List<int>.filled(32, ++nonce),
        hostedBindingReadPortLookup: hostedBindingReadPortLookup,
        lifecycleRegistrar: lifecycle,
      ),
    );
    return AdmittedConstructionOwnerHostTestHarness._(
      owner,
      worker,
      lifecycle,
      restore,
    );
  }

  /// Fails the owned worker; later facts and credentials must remain closed.
  void failWorker() {
    owner.debugRuntime?.debugKillWorkerForTesting();
  }

  /// Restores the exact test installation and closes the owner once.
  Future<void> close() {
    final existing = _closeFuture;
    if (existing != null) return existing;
    _restore();
    final future = owner.close();
    _closeFuture = future;
    return future;
  }
}

/// Test-visible lifecycle source that models one root-owned registration.
final class ConstructionOwnerLifecycleProbe
    implements MeasurementHostSessionLifecycleRegistrar {
  void Function(AppLifecycleState state)? _callback;
  var registrations = 0;
  var unregistrations = 0;

  @override
  MeasurementHostSessionLifecycleRegistration register(
    void Function(AppLifecycleState state) callback,
  ) {
    registrations += 1;
    _callback = callback;
    return _ConstructionOwnerLifecycleRegistration(this);
  }

  /// Delivers one app-lifecycle transition to the active root session.
  void emit(AppLifecycleState state) => _callback?.call(state);
}

final class _ConstructionOwnerLifecycleRegistration
    implements MeasurementHostSessionLifecycleRegistration {
  _ConstructionOwnerLifecycleRegistration(this._probe);

  final ConstructionOwnerLifecycleProbe _probe;
  var _active = true;

  @override
  void unregister() {
    if (!_active) return;
    _active = false;
    _probe
      .._callback = null
      ..unregistrations += 1;
  }
}

/// Deterministic worker port used only below the real construction owner.
final class DeterministicMeasurementDeliveryWorker
    implements MeasurementWorkerOwnedDeliveryRuntimeState {
  final Map<String, _DeterministicDeliverySession> _sessions =
      <String, _DeterministicDeliverySession>{};
  final appendRecords = <MeasurementWorkerAppendRecord>[];
  var _available = true;
  var _maximumSessions = 0;
  var starts = 0;
  var checkpointCalls = 0;
  var finalizationCalls = 0;
  var discardCalls = 0;

  @override
  bool get isAvailable => _available;

  @override
  int get workerOwnedByteCount => appendRecords.length;

  @override
  int get debugWorkerSpawnCount => starts;

  @override
  int? get debugWorkerIsolateId => null;

  @override
  Stream<MeasurementWorkerAppendAcknowledgement> get appendAcknowledgements =>
      const Stream<MeasurementWorkerAppendAcknowledgement>.empty();

  @override
  Stream<MeasurementWorkerOwnedDeliveryDebugEvent> get debugEvents =>
      const Stream<MeasurementWorkerOwnedDeliveryDebugEvent>.empty();

  /// Captures the one owner-approved configuration before the fake starts.
  void start(MeasurementWorkerOwnedDeliveryConfiguration configuration) {
    if (!configuration.admission.isAdmitted ||
        !configuration.isValidForStartup) {
      throw StateError('Deterministic worker received an inadmissible start');
    }
    starts += 1;
    _maximumSessions = configuration.maximumSessions;
  }

  @override
  Future<MeasurementWorkerOwnedDeliveryOpenSessionResult> openSession(
    MeasurementWorkerSessionRegistration registration,
  ) {
    if (!_available) {
      return Future<MeasurementWorkerOwnedDeliveryOpenSessionResult>.value(
        MeasurementWorkerOwnedDeliveryOpenSessionResult.of(
          MeasurementWorkerOpenSessionOutcome.unavailable,
          workerOwnedByteCount: workerOwnedByteCount,
        ),
      );
    }
    if (_sessions.length >= _maximumSessions ||
        _sessions.containsKey(registration.sessionId)) {
      return Future<MeasurementWorkerOwnedDeliveryOpenSessionResult>.value(
        MeasurementWorkerOwnedDeliveryOpenSessionResult.of(
          MeasurementWorkerOpenSessionOutcome.saturated,
          workerOwnedByteCount: workerOwnedByteCount,
        ),
      );
    }
    final state = _DeterministicDeliverySession(this, registration.sessionId);
    _sessions[registration.sessionId] = state;
    return Future<MeasurementWorkerOwnedDeliveryOpenSessionResult>.value(
      MeasurementWorkerOwnedDeliveryOpenSessionResult.opened(
        session: MeasurementWorkerOwnedDeliverySession.internal(
          state,
          registration.sessionId,
        ),
        workerOwnedByteCount: workerOwnedByteCount,
      ),
    );
  }

  @override
  Future<MeasurementWorkerOwnedDeliveryResetResult> reset(
    MeasurementOutboxPurgeReason reason,
  ) async {
    _available = false;
    return const MeasurementWorkerOwnedDeliveryResetResult(
      outcome: MeasurementWorkerOwnedDeliveryResetOutcome.purged,
      purgedRecordCount: 0,
    );
  }

  @override
  Future<MeasurementWorkerOwnedDeliveryShutdownResult> shutdown() async {
    _available = false;
    for (final session in _sessions.values) {
      session._available = false;
    }
    _sessions.clear();
    return const MeasurementWorkerOwnedDeliveryShutdownResult(
      MeasurementWorkerOwnedDeliveryShutdownOutcome.closed,
    );
  }

  @override
  void debugKillWorkerForTesting() {
    _available = false;
    for (final session in _sessions.values) {
      session._available = false;
    }
  }

  MeasurementWorkerAppendOutcome _append(
    _DeterministicDeliverySession session,
    MeasurementWorkerAppendRecord record,
  ) {
    if (!_available || !session._available) {
      return MeasurementWorkerAppendOutcome.unavailable;
    }
    appendRecords.add(record);
    return MeasurementWorkerAppendOutcome.accepted;
  }

  Future<MeasurementWorkerOwnedDeliveryCheckpointResult> _checkpoint(
    _DeterministicDeliverySession session, {
    required bool isFinal,
  }) {
    if (!_available || !session._available) {
      return Future<MeasurementWorkerOwnedDeliveryCheckpointResult>.value(
        const MeasurementWorkerOwnedDeliveryCheckpointResult(
          outcome: MeasurementWorkerOwnedDeliveryCheckpointOutcome.unavailable,
          sequence: null,
          isFinal: null,
          workerOwnedByteCount: 0,
        ),
      );
    }
    checkpointCalls += 1;
    if (isFinal) {
      finalizationCalls += 1;
      session._available = false;
      _sessions.remove(session.sessionId);
    }
    return Future<MeasurementWorkerOwnedDeliveryCheckpointResult>.value(
      MeasurementWorkerOwnedDeliveryCheckpointResult(
        outcome: MeasurementWorkerOwnedDeliveryCheckpointOutcome.delivered,
        sequence: checkpointCalls,
        isFinal: isFinal,
        workerOwnedByteCount: workerOwnedByteCount,
      ),
    );
  }

  Future<MeasurementWorkerOwnedDeliveryDiscardResult> _discard(
    _DeterministicDeliverySession session,
  ) {
    if (!_available || !session._available) {
      return Future<MeasurementWorkerOwnedDeliveryDiscardResult>.value(
        const MeasurementWorkerOwnedDeliveryDiscardResult(
          outcome: MeasurementWorkerOwnedDeliveryDiscardOutcome.unavailable,
          workerOwnedByteCount: 0,
        ),
      );
    }
    discardCalls += 1;
    session._available = false;
    _sessions.remove(session.sessionId);
    return Future<MeasurementWorkerOwnedDeliveryDiscardResult>.value(
      MeasurementWorkerOwnedDeliveryDiscardResult(
        outcome: MeasurementWorkerOwnedDeliveryDiscardOutcome.discarded,
        workerOwnedByteCount: workerOwnedByteCount,
      ),
    );
  }
}

final class _DeterministicDeliverySession
    implements MeasurementWorkerOwnedDeliverySessionState {
  _DeterministicDeliverySession(this._worker, this.sessionId);

  final DeterministicMeasurementDeliveryWorker _worker;
  final String sessionId;
  var _available = true;

  @override
  MeasurementWorkerAppendOutcome append(MeasurementWorkerAppendRecord record) =>
      _worker._append(this, record);

  @override
  Future<MeasurementWorkerOwnedDeliveryCheckpointResult> checkpoint() =>
      _worker._checkpoint(this, isFinal: false);

  @override
  Future<MeasurementWorkerOwnedDeliveryCheckpointResult> teardown() =>
      _worker._checkpoint(this, isFinal: true);

  @override
  Future<MeasurementWorkerOwnedDeliveryDiscardResult> discard() =>
      _worker._discard(this);
}

final class _ExactProfileReadPort
    implements MeasurementHostConstructionProfileReadPort {
  const _ExactProfileReadPort(this._profile);

  final MeasurementHostConstructionProfile _profile;

  @override
  Future<MeasurementHostConstructionProfileReadResult> readExact(
    ExactMeasurementPublicationContextRefV1 publicationContext,
  ) =>
      Future<MeasurementHostConstructionProfileReadResult>.value(
        publicationContext == _profile.publicationContext
            ? MeasurementHostConstructionProfileReadAccepted(_profile)
            : const MeasurementHostConstructionProfileReadRejected(
                MeasurementHostConstructionPolicyStatus.stale,
              ),
      );
}

final class _PathProbe implements MeasurementWorkerOwnedDeliveryPathResolver {
  var calls = 0;

  @override
  Future<String> resolveApplicationSupportPath() {
    calls += 1;
    throw StateError('Denied construction must not resolve a support path');
  }
}
