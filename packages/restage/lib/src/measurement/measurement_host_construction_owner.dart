import 'dart:async';

import 'package:meta/meta.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';

import 'measurement_capture_capability.dart';
import 'measurement_capture_edge.dart';
import 'measurement_point_identity.dart';
import 'measurement_publication_binding_runtime.dart';
import 'measurement_rfw_presentation.dart';
import 'measurement_runtime_capture.dart';
import 'measurement_worker_delivery.dart';
import 'measurement_worker_protocol.dart';
import 'presentation_commit.dart';

/// Test-only deterministic delivery seam below the exact construction owner.
///
/// Production leaves this absent and starts the concrete parent worker runtime.
@internal
typedef MeasurementHostConstructionWorkerRuntimeStarter
    = Future<MeasurementWorkerOwnedDeliveryRuntime?> Function({
  required MeasurementWorkerOwnedDeliveryConfiguration configuration,
  required MeasurementWorkerOwnedDeliveryPathResolver pathResolver,
});

/// Exact policy/profile state understood by the construction-plane host owner.
///
/// It deliberately remains a local, test-installed value. Nothing here adds a
/// public configuration field or a production profile fetch path.
@internal
enum MeasurementHostConstructionPolicyStatus {
  /// The exact manifest privacy/capability policy is supported locally.
  supported,

  /// No exact policy was available for this publication context.
  missing,

  /// A policy described a different immutable publication context.
  stale,

  /// The exact policy is known but unsupported by this SDK build.
  unsupported,
}

/// Immutable endpoint, policy, adapter, and finite-budget profile for one
/// exact publication context.
@internal
@immutable
final class MeasurementHostConstructionProfile {
  /// Creates one local construction-plane profile.
  MeasurementHostConstructionProfile({
    required this.publicationContext,
    required this.endpoint,
    required this.analyticsEnabled,
    required this.policyStatus,
    required this.measurementClassAdmitted,
    required this.remainingSessionBudget,
    required this.deliveryAdapterAvailable,
    required this.configurationFingerprint,
    this.maximumSessions = 16,
    List<MeasurementWorkerOwnedDeliveryHeader> headers = const [],
    this.debugTracing = false,
  }) : headers = List.unmodifiable(headers) {
    if (remainingSessionBudget < 0 ||
        remainingSessionBudget > kMeasurementWorkerMaximumPortableInteger ||
        maximumSessions <= 0 ||
        maximumSessions > kMeasurementWorkerMaximumSessionCount ||
        configurationFingerprint.trim().isEmpty) {
      throw ArgumentError('Invalid Measurement construction profile');
    }
  }

  /// The only publication context this profile can admit.
  final ExactMeasurementPublicationContextRefV1 publicationContext;

  /// Optional exact Measurement ingress endpoint.
  final String? endpoint;

  /// Whether the target has opted into automatic Measurement collection.
  final bool analyticsEnabled;

  /// Exact supported/missing/stale policy state for [publicationContext].
  final MeasurementHostConstructionPolicyStatus policyStatus;

  /// Whether the resolved Measurement class is admitted by that policy.
  final bool measurementClassAdmitted;

  /// Finite number of session admissions remaining in this profile snapshot.
  ///
  /// The construction owner treats every exact snapshot as an upper bound for
  /// its shared local ledger. It atomically reserves one admission before any
  /// path lookup or worker work, refunds only a pre-registration failure, and
  /// permanently consumes the reservation once the worker accepted a session.
  final int remainingSessionBudget;

  /// Whether the one typed worker delivery adapter is available.
  final bool deliveryAdapterAvailable;

  /// Non-secret worker/outbox configuration witness.
  final String configurationFingerprint;

  /// Fixed session capacity for the one shared delivery worker.
  final int maximumSessions;

  /// Immutable transient worker headers; never persisted by the root.
  final List<MeasurementWorkerOwnedDeliveryHeader> headers;

  /// Test-only causal worker tracing.
  final bool debugTracing;

  bool get hasEndpoint => endpoint != null && endpoint!.trim().isNotEmpty;

  bool get hasFiniteBudget => remainingSessionBudget > 0;

  String get _runtimeKey => [
        endpoint ?? '',
        configurationFingerprint,
        maximumSessions.toString(),
        for (final header in headers) '${header.name}:${header.value}',
        debugTracing.toString(),
      ].join('\n');
}

/// Closed result of an exact construction profile read.
@internal
sealed class MeasurementHostConstructionProfileReadResult {
  const MeasurementHostConstructionProfileReadResult();
}

/// An exact profile was read and may be compared with the resolved binding.
@internal
final class MeasurementHostConstructionProfileReadAccepted
    extends MeasurementHostConstructionProfileReadResult {
  const MeasurementHostConstructionProfileReadAccepted(this.profile);

  final MeasurementHostConstructionProfile profile;
}

/// Exact profile resolution failed closed before any delivery construction.
@internal
final class MeasurementHostConstructionProfileReadRejected
    extends MeasurementHostConstructionProfileReadResult {
  const MeasurementHostConstructionProfileReadRejected(this.status);

  final MeasurementHostConstructionPolicyStatus status;
}

/// Reads the local profile only for one immutable publication context.
@internal
abstract interface class MeasurementHostConstructionProfileReadPort {
  /// Returns a closed exact profile result; throws are also fail-closed.
  Future<MeasurementHostConstructionProfileReadResult> readExact(
    ExactMeasurementPublicationContextRefV1 publicationContext,
  );
}

/// Test seam for a restricted assignment credential issuer.
///
/// Nothing here bridges or installs the existing assignment authority. This
/// port solely proves that any future credential path consumes the exact same
/// admission object as automatic fact capture.
@internal
abstract interface class MeasurementHostAssignmentCredentialPort {
  /// Issues an opaque credential only after its caller proved admission.
  Future<String?> issueExact(
    ExactMeasurementPublicationContextRefV1 publicationContext,
  );
}

/// The single named admission result shared by fact and credential paths.
@internal
@immutable
final class MeasurementHostConstructionAdmission {
  const MeasurementHostConstructionAdmission._({
    required this.deliveryAdmission,
    required this.provenanceAccepted,
    required this.exactProfileAccepted,
    required this.deliveryAdapterAvailable,
    required this.workerHealthy,
  });

  /// The frozen five-field worker admission consumed before startup.
  final MeasurementWorkerOwnedDeliveryAdmission deliveryAdmission;

  /// Exact binding/provenance resolution succeeded for this session.
  final bool provenanceAccepted;

  /// The local profile sealed this exact publication context and policy.
  final bool exactProfileAccepted;

  /// The one typed worker delivery adapter is available.
  final bool deliveryAdapterAvailable;

  /// No earlier worker failure or owner close has latched this path closed.
  final bool workerHealthy;

  /// The sole capture/credential admission predicate for this opening.
  bool get isAdmitted =>
      provenanceAccepted &&
      exactProfileAccepted &&
      deliveryAdapterAvailable &&
      workerHealthy &&
      deliveryAdmission.isAdmitted;
}

/// One immutable construction-plane owner for all test-installed Source roots.
///
/// It owns exactly one long-lived [MeasurementWorkerOwnedDeliveryRuntime].
/// It never reads legacy analytics identity, installs a production registry,
/// constructs a direct transport, or evaluates a current/latest publication.
@internal
final class MeasurementHostConstructionOwner {
  /// Creates the test-only construction owner used by a test new-only install.
  @visibleForTesting
  MeasurementHostConstructionOwner.forTesting({
    required MeasurementHostConstructionProfileReadPort profileReadPort,
    required MeasurementWorkerOwnedDeliveryPathResolver pathResolver,
    MeasurementHostAssignmentCredentialPort? assignmentCredentialPort,
    MeasurementCaptureMonotonicClock? monotonicClock,
    MeasurementHostConstructionWorkerRuntimeStarter? workerRuntimeStarter,
  })  : _profileReadPort = profileReadPort,
        _pathResolver = pathResolver,
        _assignmentCredentialPort = assignmentCredentialPort,
        _monotonicClock = monotonicClock ?? _StopwatchMonotonicClock(),
        _workerRuntimeStarter = workerRuntimeStarter;

  final MeasurementHostConstructionProfileReadPort _profileReadPort;
  final MeasurementWorkerOwnedDeliveryPathResolver _pathResolver;
  final MeasurementHostAssignmentCredentialPort? _assignmentCredentialPort;
  final MeasurementCaptureMonotonicClock _monotonicClock;
  final MeasurementHostConstructionWorkerRuntimeStarter? _workerRuntimeStarter;
  final Set<MeasurementHostConstructionSession> _sessions =
      <MeasurementHostConstructionSession>{};
  final Map<ExactMeasurementPublicationContextRefV1,
          _MeasurementHostConstructionBudgetLedger>
      _budgetLedgers = <ExactMeasurementPublicationContextRefV1,
          _MeasurementHostConstructionBudgetLedger>{};

  MeasurementWorkerOwnedDeliveryRuntime? _runtime;
  Future<MeasurementWorkerOwnedDeliveryRuntime?>? _runtimeFuture;
  Future<void>? _closeFuture;
  String? _runtimeKey;
  var _workerHealthy = true;
  var _closed = false;
  var _nextSessionOrdinal = 0;

  /// The actual shared worker count, exposed only to focused qualification.
  @visibleForTesting
  int get debugWorkerSpawnCount => _runtime?.debugWorkerSpawnCount ?? 0;

  /// Whether future fact and credential admissions are latched closed.
  @visibleForTesting
  bool get debugWorkerHealthy => _isWorkerHealthy;

  /// Number of live exact host sessions attached to this owner.
  @visibleForTesting
  int get debugActiveSessionCount => _sessions.length;

  /// Remaining locally admissible sessions for one exact context.
  @visibleForTesting
  int debugRemainingSessionAdmissions(
    ExactMeasurementPublicationContextRefV1 publicationContext,
  ) =>
      _budgetLedgers[publicationContext]?.remaining ?? 0;

  /// Exposes the one runtime to focused crash qualification only.
  @visibleForTesting
  MeasurementWorkerOwnedDeliveryRuntime? get debugRuntime => _runtime;

  /// Opens one worker-backed capture session after one shared exact admission.
  Future<MeasurementHostConstructionSession?> openSession({
    required MeasurementPublicationBindingRuntimeResolvedMount resolvedMount,
    required MeasurementRuntimeRouteTable routeTable,
    required MeasurementCaptureAdmission capabilityAdmission,
    required String Function() captureSessionNonceSource,
  }) async {
    if (_closed) return null;

    final profileResult = await _readProfile(
      resolvedMount.publicationContextRef,
    );
    final admissionAttempt = _evaluateAndReserveAdmission(
      publicationContext: resolvedMount.publicationContextRef,
      capabilityAdmission: capabilityAdmission,
      profileResult: profileResult,
    );
    final admission = admissionAttempt.admission;
    final budgetReservation = admissionAttempt.budgetReservation;
    if (!admission.isAdmitted || budgetReservation == null) return null;

    final profile =
        (profileResult as MeasurementHostConstructionProfileReadAccepted)
            .profile;
    final runtime = await _runtimeFor(profile, admission);
    if (runtime == null || !_isWorkerHealthy) {
      budgetReservation.refund();
      return null;
    }

    try {
      final opened = await runtime.openSession(
        MeasurementWorkerSessionRegistration(
          sessionId: _nextSessionId(),
          captureSessionNonce: captureSessionNonceSource(),
          publicationContextCanonicalBytes:
              resolvedMount.publicationContextRef.canonicalBytes,
          routes: [
            for (final route in routeTable.routes)
              MeasurementWorkerRouteIdentity(
                occurrenceId: route.occurrenceId.hex,
                lineageId: route.lineageId.value,
              ),
          ],
          limits: const MeasurementWorkerSessionLimits(
            maximumCounterValue: kMaximumMeasurementCounterValue,
            maximumPresentedPoints: kMaximumMeasurementPresentedPointCount,
            maximumInteractionCounters:
                kMaximumMeasurementInteractionCounterCount,
            maximumMissingnessEntries: kMaximumMeasurementMissingnessEntryCount,
          ),
          firstSequence: 1,
        ),
      );
      final workerSession = opened.session;
      if (workerSession == null) {
        budgetReservation.refund();
        if (opened.outcome == MeasurementWorkerOpenSessionOutcome.unavailable) {
          _latchWorkerFailure();
        }
        return null;
      }

      budgetReservation.consume();
      final session = MeasurementHostConstructionSession._(
        owner: this,
        admission: admission,
        resolvedMount: resolvedMount,
        routeTable: routeTable,
        workerSession: workerSession,
        monotonicClock: _monotonicClock,
      );
      _sessions.add(session);
      return session;
    } on Object {
      budgetReservation.refund();
      _latchWorkerFailure();
      return null;
    }
  }

  Future<MeasurementHostConstructionProfileReadResult> _readProfile(
    ExactMeasurementPublicationContextRefV1 publicationContext,
  ) async {
    try {
      return await _profileReadPort.readExact(publicationContext);
    } on Object {
      return const MeasurementHostConstructionProfileReadRejected(
        MeasurementHostConstructionPolicyStatus.missing,
      );
    }
  }

  _MeasurementHostConstructionAdmissionAttempt _evaluateAndReserveAdmission({
    required ExactMeasurementPublicationContextRefV1 publicationContext,
    required MeasurementCaptureAdmission capabilityAdmission,
    required MeasurementHostConstructionProfileReadResult profileResult,
  }) {
    final profile = switch (profileResult) {
      MeasurementHostConstructionProfileReadAccepted(:final profile) => profile,
      MeasurementHostConstructionProfileReadRejected() => null,
    };
    final exactProfileAccepted =
        profile != null && profile.publicationContext == publicationContext;
    final policySupported = capabilityAdmission.admitted &&
        exactProfileAccepted &&
        profile.policyStatus ==
            MeasurementHostConstructionPolicyStatus.supported &&
        profile.deliveryAdapterAvailable &&
        _isWorkerHealthy;
    final canReserveBudget = policySupported && profile.hasFiniteBudget;
    final budgetReservation = canReserveBudget
        ? _reserveBudget(publicationContext, profile.remainingSessionBudget)
        : null;
    final admission = MeasurementHostConstructionAdmission._(
      deliveryAdmission: MeasurementWorkerOwnedDeliveryAdmission(
        hasEndpoint: profile?.hasEndpoint == true,
        analyticsEnabled: profile?.analyticsEnabled == true,
        policySupported: policySupported,
        measurementClassAdmitted: profile?.measurementClassAdmitted == true,
        budgetAvailable: budgetReservation != null,
      ),
      provenanceAccepted: capabilityAdmission.admitted,
      exactProfileAccepted: exactProfileAccepted,
      deliveryAdapterAvailable: profile?.deliveryAdapterAvailable == true,
      workerHealthy: _isWorkerHealthy,
    );
    return _MeasurementHostConstructionAdmissionAttempt(
      admission: admission,
      budgetReservation: budgetReservation,
    );
  }

  _MeasurementHostConstructionBudgetReservation? _reserveBudget(
    ExactMeasurementPublicationContextRefV1 publicationContext,
    int profileRemainingSessionBudget,
  ) {
    final ledger = _budgetLedgers.putIfAbsent(
      publicationContext,
      () => _MeasurementHostConstructionBudgetLedger(
        profileRemainingSessionBudget,
      ),
    )..tightenTo(profileRemainingSessionBudget);
    return ledger.tryReserve()
        ? _MeasurementHostConstructionBudgetReservation._(ledger)
        : null;
  }

  Future<MeasurementWorkerOwnedDeliveryRuntime?> _runtimeFor(
    MeasurementHostConstructionProfile profile,
    MeasurementHostConstructionAdmission admission,
  ) {
    final existingKey = _runtimeKey;
    if (existingKey != null && existingKey != profile._runtimeKey) {
      return Future<MeasurementWorkerOwnedDeliveryRuntime?>.value();
    }
    final existing = _runtimeFuture;
    if (existing != null) return existing;

    _runtimeKey = profile._runtimeKey;
    final started = _startRuntime(profile, admission.deliveryAdmission);
    _runtimeFuture = started;
    return started;
  }

  Future<MeasurementWorkerOwnedDeliveryRuntime?> _startRuntime(
    MeasurementHostConstructionProfile profile,
    MeasurementWorkerOwnedDeliveryAdmission admission,
  ) async {
    final configuration = MeasurementWorkerOwnedDeliveryConfiguration(
      admission: admission,
      endpoint: profile.endpoint,
      configurationFingerprint: profile.configurationFingerprint,
      maximumSessions: profile.maximumSessions,
      headers: profile.headers,
      debugTracing: profile.debugTracing,
    );
    MeasurementWorkerOwnedDeliveryRuntime? runtime;
    try {
      final starter = _workerRuntimeStarter;
      if (starter != null) {
        runtime = await starter(
          configuration: configuration,
          pathResolver: _pathResolver,
        );
      } else {
        runtime = (await MeasurementWorkerOwnedDeliveryRuntime.start(
          configuration: configuration,
          pathResolver: _pathResolver,
        ))
            .runtime;
      }
    } on Object {
      _latchWorkerFailure();
      return null;
    }
    if (runtime == null || !runtime.isAvailable) {
      _latchWorkerFailure();
      return null;
    }
    _runtime = runtime;
    return runtime;
  }

  bool get _isWorkerHealthy =>
      !_closed && _workerHealthy && (_runtime == null || _runtime!.isAvailable);

  void _latchWorkerFailure() {
    if (!_workerHealthy) return;
    _workerHealthy = false;
    for (final session in List<MeasurementHostConstructionSession>.of(
      _sessions,
    )) {
      session._closeCaptureEdge();
    }
  }

  void _release(MeasurementHostConstructionSession session) {
    _sessions.remove(session);
  }

  bool _admissionRemainsUsable(
    MeasurementHostConstructionAdmission admission,
  ) =>
      admission.isAdmitted && _isWorkerHealthy;

  Future<String?> _issueAssignmentCredential(
    MeasurementHostConstructionAdmission admission,
    ExactMeasurementPublicationContextRefV1 publicationContext,
  ) async {
    if (!_admissionRemainsUsable(admission)) return null;
    final port = _assignmentCredentialPort;
    if (port == null) return null;
    try {
      return await port.issueExact(publicationContext);
    } on Object {
      _latchWorkerFailure();
      return null;
    }
  }

  void _observeDeliveryResult(
    MeasurementWorkerOwnedDeliveryCheckpointResult result,
  ) {
    if (result.outcome ==
        MeasurementWorkerOwnedDeliveryCheckpointOutcome.unavailable) {
      _latchWorkerFailure();
    }
  }

  String _nextSessionId() {
    _nextSessionOrdinal += 1;
    return 'measurement-host.$_nextSessionOrdinal';
  }

  /// Finalizes all live sessions, then closes the one owned worker exactly once.
  Future<void> close() {
    final existing = _closeFuture;
    if (existing != null) return existing;
    _closed = true;
    final future = _closeActive();
    _closeFuture = future;
    return future;
  }

  Future<void> _closeActive() async {
    final sessions = List<MeasurementHostConstructionSession>.of(_sessions);
    await Future.wait<void>([
      for (final session in sessions) session.teardown(),
    ]);
    final runtimeFuture = _runtimeFuture;
    final runtime = runtimeFuture == null ? _runtime : await runtimeFuture;
    if (runtime == null) return;
    await runtime.shutdown();
  }
}

/// One exact root session attached to a shared construction owner.
@internal
final class MeasurementHostConstructionSession
    implements
        MeasurementPresentationCaptureSink,
        MeasurementRfwPresentationCaptureBinder {
  MeasurementHostConstructionSession._({
    required MeasurementHostConstructionOwner owner,
    required MeasurementHostConstructionAdmission admission,
    required MeasurementPublicationBindingRuntimeResolvedMount resolvedMount,
    required MeasurementRuntimeRouteTable routeTable,
    required MeasurementWorkerOwnedDeliverySession workerSession,
    required MeasurementCaptureMonotonicClock monotonicClock,
  })  : _owner = owner,
        _admission = admission,
        _resolvedMount = resolvedMount,
        _routeTable = routeTable,
        _workerSession = workerSession,
        _monotonicClock = monotonicClock;

  final MeasurementHostConstructionOwner _owner;
  final MeasurementHostConstructionAdmission _admission;
  final MeasurementPublicationBindingRuntimeResolvedMount _resolvedMount;
  final MeasurementRuntimeRouteTable _routeTable;
  final MeasurementWorkerOwnedDeliverySession _workerSession;
  final MeasurementCaptureMonotonicClock _monotonicClock;
  final Map<String, _MeasurementPreboundRoute> _routesByCarrier =
      <String, _MeasurementPreboundRoute>{};
  final Set<MeasurementCaptureEdge> _captureEdges = <MeasurementCaptureEdge>{};

  var _active = true;
  var _successfulFirstPaint = false;
  Future<MeasurementWorkerOwnedDeliveryCheckpointResult?>? _teardownFuture;
  Future<void>? _discardFuture;

  /// The immutable admission shared with restricted credential issuance.
  @visibleForTesting
  MeasurementHostConstructionAdmission get debugAdmission => _admission;

  @override
  MeasurementCaptureEdge? bindPresentation({
    required List<String> pointTokens,
    required List<String> routeCarriers,
  }) {
    if (!_active ||
        !_owner._admissionRemainsUsable(_admission) ||
        pointTokens.isEmpty ||
        pointTokens.length != routeCarriers.length ||
        pointTokens.length > kMaximumMeasurementRuntimeRouteCount) {
      return null;
    }
    try {
      final prebound = <MeasurementPreboundPointToken>[];
      for (var index = 0; index < pointTokens.length; index += 1) {
        final compactToken = pointTokens[index];
        final rawCarrier = routeCarriers[index];
        if (!rawCarrier.endsWith('.$compactToken')) return null;
        final route = _routeTable.resolveOpaqueRoute(
          context: _routeTable.mountedArtifactContext,
          token: OpaqueMeasurementEventSlotToken(rawCarrier),
        );
        if (route == null) return null;
        prebound.add(
          MeasurementPreboundPointToken(
            compactToken: compactToken,
            route: route,
          ),
        );
      }
      final table = MeasurementPointIdentityTable.fromPreboundTokens(
        tokens: prebound,
      );
      final edge = MeasurementCaptureEdge.workerOwnedDelivery(
        pointIdentityTable: table,
        workerSession: _workerSession,
        monotonicClock: _monotonicClock,
        onWorkerUnavailable: _owner._latchWorkerFailure,
      );
      for (var index = 0; index < routeCarriers.length; index += 1) {
        final identity = table.resolve(pointTokens[index]);
        if (identity == null) return null;
        _routesByCarrier[routeCarriers[index]] = _MeasurementPreboundRoute(
          edge: edge,
          identity: identity,
        );
      }
      _captureEdges.add(edge);
      return edge;
    } on Object {
      return null;
    }
  }

  /// Uses only a prebound raw-carrier lookup followed by a compact append.
  ///
  /// Carrier syntax and exact route membership were proven during
  /// [bindPresentation], outside the action callback/append edge.
  void recordInteractionCarrier(String rawCarrier) {
    if (!_active || !_owner._admissionRemainsUsable(_admission)) return;
    final route = _routesByCarrier[rawCarrier];
    if (route == null) return;
    route.edge.appendInteractionIdentity(route.identity);
  }

  @override
  void recordSuccessfulPresentation(
    MeasurementSuccessfulPresentationFact fact,
  ) {
    if (!_active || !_owner._admissionRemainsUsable(_admission)) {
      throw StateError('Measurement construction session is unavailable');
    }
    if (fact.context.publishedSurfaceRevision !=
        _resolvedMount.publishedSurfaceRevision) {
      throw ArgumentError.value(
        fact,
        'fact',
        'Successful paint must match the exact resolved publication',
      );
    }
    _successfulFirstPaint = true;
  }

  /// Schedules one nonblocking worker checkpoint after backgrounding.
  Future<MeasurementWorkerOwnedDeliveryCheckpointResult?> checkpoint() async {
    if (!_active ||
        !_successfulFirstPaint ||
        !_owner._admissionRemainsUsable(_admission)) {
      return null;
    }
    final result = await _workerSession.checkpoint();
    _owner._observeDeliveryResult(result);
    return result;
  }

  /// Finalizes after a successful paint, or discards an uncommitted session.
  Future<MeasurementWorkerOwnedDeliveryCheckpointResult?> teardown() {
    final existing = _teardownFuture;
    if (existing != null) return existing;
    final future = _teardownActive();
    _teardownFuture = future;
    return future;
  }

  Future<MeasurementWorkerOwnedDeliveryCheckpointResult?>
      _teardownActive() async {
    if (!_active) {
      await _discardFuture;
      return null;
    }
    _active = false;
    _closeCaptureEdge();
    try {
      if (!_successfulFirstPaint) {
        await _discardUncommitted();
        return null;
      }
      final result = await _workerSession.teardown();
      _owner._observeDeliveryResult(result);
      return result;
    } finally {
      _owner._release(this);
    }
  }

  /// Called by the first-paint route handle only before a successful commit.
  void abortBeforeSuccessfulPaint() {
    if (!_active || _successfulFirstPaint) return;
    _active = false;
    _closeCaptureEdge();
    unawaited(_discardUncommitted().whenComplete(() => _owner._release(this)));
  }

  Future<void> _discardUncommitted() {
    final existing = _discardFuture;
    if (existing != null) return existing;
    final future = _workerSession.discard().then<void>((result) {
      if (result.outcome !=
              MeasurementWorkerOwnedDeliveryDiscardOutcome.discarded &&
          result.outcome !=
              MeasurementWorkerOwnedDeliveryDiscardOutcome.finalized) {
        _owner._latchWorkerFailure();
      }
    });
    _discardFuture = future;
    return future;
  }

  void _closeCaptureEdge() {
    for (final edge in _captureEdges) {
      edge.close();
    }
  }

  /// Uses the same stored admission; no second predicate is evaluated.
  Future<String?> issueAssignmentCredential() =>
      _owner._issueAssignmentCredential(
        _admission,
        _resolvedMount.publicationContextRef,
      );
}

final class _MeasurementPreboundRoute {
  const _MeasurementPreboundRoute({required this.edge, required this.identity});

  final MeasurementCaptureEdge edge;
  final MeasurementPointIdentity identity;
}

/// The one final admission result plus its already-reserved local budget slot.
final class _MeasurementHostConstructionAdmissionAttempt {
  const _MeasurementHostConstructionAdmissionAttempt({
    required this.admission,
    required this.budgetReservation,
  });

  final MeasurementHostConstructionAdmission admission;
  final _MeasurementHostConstructionBudgetReservation? budgetReservation;
}

/// Shared monotonically-tightening local budget for one exact context.
///
/// A newly read profile may lower the remaining count, but cannot raise this
/// owner's already-observed upper bound. That makes stale or concurrent reads
/// fail closed rather than accidentally minting another admission.
final class _MeasurementHostConstructionBudgetLedger {
  _MeasurementHostConstructionBudgetLedger(this._upperBound);

  int _upperBound;
  var _reserved = 0;
  var _consumed = 0;

  int get remaining {
    final unbounded = _upperBound - _reserved - _consumed;
    return unbounded > 0 ? unbounded : 0;
  }

  void tightenTo(int snapshotRemaining) {
    if (snapshotRemaining < _upperBound) {
      _upperBound = snapshotRemaining;
    }
  }

  bool tryReserve() {
    if (_consumed + _reserved >= _upperBound) return false;
    _reserved += 1;
    return true;
  }

  void consumeReservation() {
    if (_reserved <= 0) {
      throw StateError('Measurement session budget reservation was not held');
    }
    _reserved -= 1;
    _consumed += 1;
  }

  void refundReservation() {
    if (_reserved <= 0) {
      throw StateError('Measurement session budget reservation was not held');
    }
    _reserved -= 1;
  }
}

/// One idempotent owner-local reservation for a pre-registration attempt.
final class _MeasurementHostConstructionBudgetReservation {
  _MeasurementHostConstructionBudgetReservation._(this._ledger);

  final _MeasurementHostConstructionBudgetLedger _ledger;
  var _settled = false;

  void consume() {
    if (_settled) return;
    _settled = true;
    _ledger.consumeReservation();
  }

  void refund() {
    if (_settled) return;
    _settled = true;
    _ledger.refundReservation();
  }
}

final class _StopwatchMonotonicClock
    implements MeasurementCaptureMonotonicClock {
  _StopwatchMonotonicClock() : _stopwatch = Stopwatch()..start();

  final Stopwatch _stopwatch;
  var _lastMicros = 0;

  @override
  int readMicros() {
    final elapsed = _stopwatch.elapsedMicroseconds;
    if (elapsed > _lastMicros) {
      _lastMicros = elapsed;
    } else {
      _lastMicros += 1;
    }
    return _lastMicros;
  }
}
