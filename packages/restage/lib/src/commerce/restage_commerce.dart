import 'dart:async';

import 'package:restage_shared/commerce.dart'
    show
        CommerceIntentRequest,
        CommerceIntentResponse,
        CommercePurchaserStateRequest,
        CommercePurchaserStateResponse,
        CommerceReportRequest,
        CommerceReportResponse,
        EntitlementSummary,
        commerceVerificationIdentity;

import '../restage_rpc_client/restage_rpc_client.dart';
import '../restage_rpc_client/uuid_v4.dart';
import '../measurement/placement_mount_attribution.dart';
import 'commerce_report_queue.dart';
import 'commerce_store_adapter.dart';

final RegExp _commerceLogicalIdPattern = RegExp(r'^[a-z][a-z0-9._-]{0,127}$');
final RegExp _commerceCodePattern = RegExp(r'^[a-z][a-z0-9._]{0,63}$');

String _requireCommerceLogicalId(String value) {
  if (!_commerceLogicalIdPattern.hasMatch(value)) {
    throw FormatException('Invalid commerce logical identifier', value);
  }
  return value;
}

String _requireCommerceCode(String value) {
  if (!_commerceCodePattern.hasMatch(value)) {
    throw FormatException('Invalid commerce code', value);
  }
  return value;
}

/// An application- or Restage-defined logical offer selector.
///
/// It is not a raw provider product ID, offer token or identifier, promo code,
/// receipt, or provider evidence.
final class CommerceOfferId {
  factory CommerceOfferId(String value) =>
      CommerceOfferId._(_requireCommerceLogicalId(value));

  const CommerceOfferId._(this.value);

  final String value;

  @override
  bool operator ==(Object other) =>
      other is CommerceOfferId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// A Restage-defined capability code.
///
/// Unknown values are preserved for forward compatibility. Applications and
/// provider adapters must not use this type as a namespace for provider codes.
final class CommerceCapabilityCode {
  factory CommerceCapabilityCode(String value) {
    final code = _requireCommerceCode(value);
    return switch (code) {
      'purchase' => purchase,
      'restore' => restore,
      'purchaser_state.read' => purchaserStateRead,
      _ => CommerceCapabilityCode._(code, false),
    };
  }

  const CommerceCapabilityCode._(this.value, this.isKnown);

  /// The normalized Restage code.
  final String value;

  /// Whether this SDK recognizes [value].
  final bool isKnown;

  /// Initiating a purchase for a logical offer.
  static const purchase = CommerceCapabilityCode._('purchase', true);

  /// Restoring purchases through the configured commerce authority.
  static const restore = CommerceCapabilityCode._('restore', true);

  /// Reading the current Restage purchaser state.
  static const purchaserStateRead = CommerceCapabilityCode._(
    'purchaser_state.read',
    true,
  );

  @override
  bool operator ==(Object other) =>
      other is CommerceCapabilityCode && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// A normalized, Restage-defined action status.
///
/// Unknown values are preserved for forward compatibility. Provider status
/// names are mapped to Restage semantics before they reach this boundary.
final class CommerceActionStatusCode {
  factory CommerceActionStatusCode(String value) {
    final code = _requireCommerceCode(value);
    return switch (code) {
      'unavailable' => unavailable,
      'not_presented' => notPresented,
      'dismissed' => dismissed,
      'pending' => pending,
      'submitted_for_reconciliation' => submittedForReconciliation,
      'failed' => failed,
      _ => CommerceActionStatusCode._(code, false),
    };
  }

  const CommerceActionStatusCode._(this.value, this.isKnown);

  /// The normalized Restage code.
  final String value;

  /// Whether this SDK recognizes [value].
  final bool isKnown;

  /// The requested action is not available and was not started.
  static const unavailable = CommerceActionStatusCode._('unavailable', true);

  /// The action ended before any provider presentation began.
  static const notPresented = CommerceActionStatusCode._('not_presented', true);

  /// The provider presentation was dismissed before authoritative completion.
  static const dismissed = CommerceActionStatusCode._('dismissed', true);

  /// The action is still pending and grants no entitlement or fulfillment.
  static const pending = CommerceActionStatusCode._('pending', true);

  /// The action was submitted for asynchronous authority reconciliation.
  ///
  /// This is not proof of purchase, entitlement, fulfillment, refund, or
  /// refund protection. Applications wait for authoritative purchaser state.
  static const submittedForReconciliation = CommerceActionStatusCode._(
    'submitted_for_reconciliation',
    true,
  );

  /// The action ended without authoritative completion.
  static const failed = CommerceActionStatusCode._('failed', true);

  @override
  bool operator ==(Object other) =>
      other is CommerceActionStatusCode && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// A normalized, Restage-defined commerce failure code.
///
/// Unknown values are preserved for forward compatibility. Raw provider
/// errors, identifiers, and evidence do not cross this boundary.
final class CommerceFailureCode {
  factory CommerceFailureCode(String value) {
    final code = _requireCommerceCode(value);
    return switch (code) {
      'not_activated' => notActivated,
      'unsupported_capability' => unsupportedCapability,
      'invalid_request' => invalidRequest,
      'unsupported_response' => unsupportedResponse,
      _ => CommerceFailureCode._(code, false),
    };
  }

  const CommerceFailureCode._(this.value, this.isKnown);

  /// The normalized Restage code.
  final String value;

  /// Whether this SDK recognizes [value].
  final bool isKnown;

  /// Commerce has not been activated for this application.
  static const notActivated = CommerceFailureCode._('not_activated', true);

  /// The requested capability is not supported.
  static const unsupportedCapability = CommerceFailureCode._(
    'unsupported_capability',
    true,
  );

  /// The request violates the typed commerce contract.
  static const invalidRequest = CommerceFailureCode._('invalid_request', true);

  /// A response could not be mapped to recognized Restage semantics.
  static const unsupportedResponse = CommerceFailureCode._(
    'unsupported_response',
    true,
  );

  @override
  bool operator ==(Object other) =>
      other is CommerceFailureCode && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// A normalized, Restage-defined purchaser-state status.
///
/// Unknown values are preserved for forward compatibility. Provider status
/// names are mapped to Restage semantics before they reach this boundary.
final class CommercePurchaserStateStatusCode {
  factory CommercePurchaserStateStatusCode(String value) {
    final code = _requireCommerceCode(value);
    return switch (code) {
      'unavailable' => unavailable,
      'available' => available,
      'stale' => stale,
      'unknown' => unknown,
      _ => CommercePurchaserStateStatusCode._(code, false),
    };
  }

  const CommercePurchaserStateStatusCode._(this.value, this.isKnown);

  /// The normalized Restage code.
  final String value;

  /// Whether this SDK recognizes [value].
  final bool isKnown;

  /// Purchaser state cannot currently be read.
  static const unavailable = CommercePurchaserStateStatusCode._(
    'unavailable',
    true,
  );

  /// Purchaser state is current from the Restage authority.
  static const available = CommercePurchaserStateStatusCode._(
    'available',
    true,
  );

  /// Retained state may be out of date and must not authorize fulfillment.
  static const stale = CommercePurchaserStateStatusCode._('stale', true);

  /// The authority could not establish the purchaser's current state.
  static const unknown = CommercePurchaserStateStatusCode._('unknown', true);

  @override
  bool operator ==(Object other) =>
      other is CommercePurchaserStateStatusCode && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

abstract final class CommerceRequest<R extends CommerceResponse> {
  const CommerceRequest._();

  Future<R> _dispatch(RestageCommerce commerce);
}

abstract final class CommerceResponse {
  const CommerceResponse._();
}

final class CommerceAvailabilityRequest
    extends CommerceRequest<CommerceAvailability> {
  const CommerceAvailabilityRequest(this.capability, {this.offerId})
      : super._();

  final CommerceCapabilityCode capability;
  final CommerceOfferId? offerId;

  @override
  Future<CommerceAvailability> _dispatch(RestageCommerce commerce) =>
      commerce.availability(this);

  @override
  bool operator ==(Object other) =>
      other is CommerceAvailabilityRequest &&
      other.capability == capability &&
      other.offerId == offerId;

  @override
  int get hashCode => Object.hash(capability, offerId);
}

/// Requests a purchase of one logical offer.
///
/// The commerce authority resolves [offerId] to the exact purchasable
/// configuration; the request never names provider products, and device input
/// cannot widen what the authority resolved. Selection among multiple
/// purchasable alternatives under one offer is reserved for future optional
/// parameters.
final class CommercePurchaseRequest
    extends CommerceRequest<CommerceActionResult> {
  const CommercePurchaseRequest(this.offerId) : super._();

  final CommerceOfferId offerId;

  @override
  Future<CommerceActionResult> _dispatch(RestageCommerce commerce) =>
      commerce.purchase(this);

  @override
  bool operator ==(Object other) =>
      other is CommercePurchaseRequest && other.offerId == offerId;

  @override
  int get hashCode => offerId.hashCode;
}

final class CommerceRestoreRequest
    extends CommerceRequest<CommerceActionResult> {
  const CommerceRestoreRequest() : super._();

  @override
  Future<CommerceActionResult> _dispatch(RestageCommerce commerce) =>
      commerce.restore();

  @override
  bool operator ==(Object other) => other is CommerceRestoreRequest;

  @override
  int get hashCode => 0;
}

final class CommerceRefreshRequest
    extends CommerceRequest<CommercePurchaserState> {
  const CommerceRefreshRequest() : super._();

  @override
  Future<CommercePurchaserState> _dispatch(RestageCommerce commerce) =>
      commerce.refresh();

  @override
  bool operator ==(Object other) => other is CommerceRefreshRequest;

  @override
  int get hashCode => 0;
}

/// Whether a commerce capability can currently be requested.
final class CommerceAvailability extends CommerceResponse {
  CommerceAvailability._({
    required this.capability,
    required this.offerId,
    required this.available,
    required this.failureCode,
  }) : super._() {
    if (available != (failureCode == null)) {
      throw StateError('Available iff failureCode is null');
    }
    if (!capability.isKnown &&
        failureCode != CommerceFailureCode.unsupportedCapability) {
      throw StateError(
        'Unknown capability requires unsupportedCapability failure code',
      );
    }
  }

  final CommerceCapabilityCode capability;
  final CommerceOfferId? offerId;
  final bool available;
  final CommerceFailureCode? failureCode;

  @override
  bool operator ==(Object other) =>
      other is CommerceAvailability &&
      other.capability == capability &&
      other.offerId == offerId &&
      other.available == available &&
      other.failureCode == failureCode;

  @override
  int get hashCode => Object.hash(capability, offerId, available, failureCode);
}

/// The normalized result of requesting a commerce action.
final class CommerceActionResult extends CommerceResponse {
  CommerceActionResult._({
    required this.status,
    CommerceFailureCode? failureCode,
  })  : failureCode = status.isKnown
            ? failureCode
            : CommerceFailureCode.unsupportedResponse,
        super._() {
    if (status.isKnown) {
      final requiresFailure = status == CommerceActionStatusCode.unavailable ||
          status == CommerceActionStatusCode.failed;
      if (requiresFailure != (this.failureCode != null)) {
        throw StateError('Failure code does not match the known action status');
      }
    }
  }

  final CommerceActionStatusCode status;
  final CommerceFailureCode? failureCode;

  @override
  bool operator ==(Object other) =>
      other is CommerceActionResult &&
      other.status == status &&
      other.failureCode == failureCode;

  @override
  int get hashCode => Object.hash(status, failureCode);
}

/// The current purchaser-state authority status.
final class CommercePurchaserState extends CommerceResponse {
  CommercePurchaserState._({
    required this.status,
    List<EntitlementSummary> entitlements = const <EntitlementSummary>[],
    this.hasProductionPurchaseHistory,
  })  : entitlements = List<EntitlementSummary>.unmodifiable(entitlements),
        super._();

  final CommercePurchaserStateStatusCode status;

  /// Entitlements last projected by the Restage authority.
  final List<EntitlementSummary> entitlements;

  /// Production purchase history for this app configuration and purchaser.
  /// Includes inactive purchases and purchases without a current entitlement.
  /// False means checked absence; null means unproven.
  final bool? hasProductionPurchaseHistory;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CommercePurchaserState ||
        other.status != status ||
        other.hasProductionPurchaseHistory != hasProductionPurchaseHistory ||
        other.entitlements.length != entitlements.length) {
      return false;
    }
    for (var index = 0; index < entitlements.length; index += 1) {
      if (other.entitlements[index] != entitlements[index]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        status,
        Object.hashAll(entitlements),
        hasProductionPurchaseHistory,
      );
}

abstract final class RestageCommerce {
  CommercePurchaserState get currentState;

  Stream<CommercePurchaserState> get states;

  Future<CommerceAvailability> availability(
    CommerceAvailabilityRequest request,
  );

  Future<CommerceActionResult> purchase(CommercePurchaseRequest request);

  Future<CommerceActionResult> restore();

  Future<CommercePurchaserState> refresh();

  Future<R> perform<R extends CommerceResponse>(CommerceRequest<R> request);
}

final class _RetainedCommerceStateStream
    extends Stream<CommercePurchaserState> {
  _RetainedCommerceStateStream(this._state);

  CommercePurchaserState _state;
  final StreamController<CommercePurchaserState> _updates =
      StreamController<CommercePurchaserState>.broadcast(sync: true);

  void emit(CommercePurchaserState state) {
    _state = state;
    _updates.add(state);
  }

  @override
  bool get isBroadcast => true;

  @override
  StreamSubscription<CommercePurchaserState> listen(
    void Function(CommercePurchaserState event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final controller = StreamController<CommercePurchaserState>(sync: true);
    final updates = _updates.stream.listen(
      controller.add,
      onDone: controller.close,
    );
    controller.onCancel = updates.cancel;
    final subscription = controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
    controller.add(_state);
    return subscription;
  }
}

final class _RestageCommerce implements RestageCommerce {
  _RestageCommerce() {
    _currentState = _unavailableCommerceState();
    _states = _RetainedCommerceStateStream(_currentState);
    _engine = _InactiveCommerceEngine(_currentState);
  }

  late CommercePurchaserState _currentState;
  late final _RetainedCommerceStateStream _states;
  late _CommerceEngine _engine;

  void activate(
    CommerceStoreAdapter adapter, {
    required RestageRpcClient? Function() rpcClientProvider,
    required Future<String> Function() applicationAnonymousTokenProvider,
    CommerceRuntimeContext? Function()? runtimeContextProvider,
    required Future<CommerceReportQueue> Function() reportQueueFactory,
    CommerceAttemptDeadline attemptDeadline = const CommerceAttemptDeadline(),
    DateTime Function() clock = DateTime.now,
  }) {
    final engine = _engine;
    if (engine is _StoreAdapterCommerceEngine) {
      if (identical(engine.adapter, adapter)) return;
      throw StateError('Commerce is already activated');
    }
    _engine = _StoreAdapterCommerceEngine(
      adapter: adapter,
      rpcClientProvider: rpcClientProvider,
      applicationAnonymousTokenProvider: applicationAnonymousTokenProvider,
      runtimeContextProvider: runtimeContextProvider,
      reportQueueFactory: reportQueueFactory,
      onState: _setState,
      attemptDeadline: attemptDeadline,
      clock: clock,
    );
  }

  void configurationChanged() => _engine.configurationChanged();

  void identityChanged() => _engine.identityChanged();

  void foregrounded() => _engine.foregrounded();

  /// Completes once every engine retired so far has settled.
  Future<void> _retired = Future<void>.value();

  Future<void> debugReset() {
    final engine = _engine;
    // Detached retirement must not inherit the caller's zone.
    _retired = Zone.root.run(
      () => Future.wait<void>(<Future<void>>[_retired, engine.dispose()]),
    );
    final unavailable = _unavailableCommerceState();
    if (_currentState != unavailable) _setState(unavailable);
    _engine = _InactiveCommerceEngine(_currentState);
    return _retired;
  }

  void _setState(CommercePurchaserState state) {
    _currentState = state;
    _states.emit(state);
  }

  CommerceStoreAdapter? get debugStoreAdapter {
    final engine = _engine;
    return engine is _StoreAdapterCommerceEngine ? engine.adapter : null;
  }

  @override
  CommercePurchaserState get currentState => _currentState;

  @override
  Stream<CommercePurchaserState> get states => _states;

  @override
  Future<CommerceAvailability> availability(
    CommerceAvailabilityRequest request,
  ) =>
      _engine.availability(request);

  @override
  Future<CommerceActionResult> purchase(CommercePurchaseRequest request) =>
      _engine.purchase(request);

  @override
  Future<CommerceActionResult> restore() => _engine.restore();

  @override
  Future<CommercePurchaserState> refresh() => _engine.refresh();

  @override
  Future<R> perform<R extends CommerceResponse>(CommerceRequest<R> request) =>
      request._dispatch(this);
}

abstract interface class _CommerceEngine {
  Future<CommerceAvailability> availability(
    CommerceAvailabilityRequest request,
  );

  Future<CommerceActionResult> purchase(CommercePurchaseRequest request);

  Future<CommerceActionResult> restore();

  Future<CommercePurchaserState> refresh();

  void configurationChanged();

  void identityChanged();

  void foregrounded();

  /// Stops new work; completes once work already started has settled.
  Future<void> dispose();
}

final class _InactiveCommerceEngine implements _CommerceEngine {
  const _InactiveCommerceEngine(this._currentState);

  final CommercePurchaserState _currentState;

  @override
  Future<CommerceAvailability> availability(
    CommerceAvailabilityRequest request,
  ) async {
    final CommerceFailureCode failureCode;
    if (!request.capability.isKnown) {
      failureCode = CommerceFailureCode.unsupportedCapability;
    } else if (request.offerId != null &&
        request.capability != CommerceCapabilityCode.purchase) {
      failureCode = CommerceFailureCode.invalidRequest;
    } else {
      failureCode = CommerceFailureCode.notActivated;
    }
    return CommerceAvailability._(
      capability: request.capability,
      offerId: request.offerId,
      available: false,
      failureCode: failureCode,
    );
  }

  @override
  Future<CommerceActionResult> purchase(
    CommercePurchaseRequest request,
  ) async =>
      _unavailableAction(CommerceFailureCode.notActivated);

  @override
  Future<CommerceActionResult> restore() async =>
      _unavailableAction(CommerceFailureCode.notActivated);

  @override
  Future<CommercePurchaserState> refresh() async => _currentState;

  @override
  void configurationChanged() {}

  @override
  void identityChanged() {}

  @override
  void foregrounded() {}

  @override
  Future<void> dispose() async {}
}

/// Configuration and purchaser identity captured before a commerce operation.
/// Binds retained evidence to its original context. Only the fingerprint is
/// safe to persist; the endpoint and credential are not.
final class CommerceRuntimeContext {
  CommerceRuntimeContext({
    required this.configurationFingerprint,
    required Future<String?> Function() applicationAnonymousTokenProvider,
    bool Function()? isCurrent,
  })  : _applicationAnonymousTokenProvider = applicationAnonymousTokenProvider,
        _isCurrent = isCurrent ?? _alwaysCurrent {
    if (configurationFingerprint.isEmpty) {
      throw ArgumentError.value(
        configurationFingerprint,
        'configurationFingerprint',
        'must not be empty',
      );
    }
  }

  final String configurationFingerprint;
  final Future<String?> Function() _applicationAnonymousTokenProvider;
  final bool Function() _isCurrent;

  Future<String?> applicationAnonymousToken() =>
      _applicationAnonymousTokenProvider();

  bool get isCurrent => _isCurrent();
}

bool _alwaysCurrent() => true;

final class _PendingCommerceAdmission {
  _PendingCommerceAdmission({
    required this.transaction,
    required this.context,
    required Future<String?> Function() applicationAnonymousTokenProvider,
    this.requestDrainAfterPersist = true,
  }) : _applicationAnonymousTokenProvider = applicationAnonymousTokenProvider {
    _tokenResolution = _applicationAnonymousTokenProvider();
  }

  CommerceStoreTransaction transaction;
  final CommerceRuntimeContext context;
  final Future<String?> Function() _applicationAnonymousTokenProvider;
  final bool requestDrainAfterPersist;
  CommerceReportRecord? record;
  final List<_RetainedCommerceTransaction> observedCompletions =
      <_RetainedCommerceTransaction>[];
  Future<String?>? _tokenResolution;
  String? applicationAnonymousToken;
  int retryAttempt = 0;
  DateTime nextRetryAt = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  bool inFlight = false;
  final Completer<CommerceReportRecord> durableRecord =
      Completer<CommerceReportRecord>();

  Future<String?> resolveApplicationAnonymousToken() =>
      _tokenResolution ??= _applicationAnonymousTokenProvider();

  void clearUnresolvedToken() => _tokenResolution = null;

  void observeCompletion(_RetainedCommerceTransaction retained) {
    if (!retained.matchesObservation(
      transaction,
      context.configurationFingerprint,
    )) {
      return;
    }
    for (final observed in observedCompletions) {
      if (observed.matchesReport(retained.report)) {
        observed.shareCompletionWith(retained);
        return;
      }
    }
    // Ownership may still be unresolved. Keep each saved owner's reference
    // separate until admission identifies the matching queued subject.
    observedCompletions.add(retained);
  }

  void retainCompletionTransaction(CommerceStoreTransaction candidate) {
    if (!transaction.requiresDeviceCompletion &&
        candidate.requiresDeviceCompletion) {
      transaction = candidate;
    }
  }

  void scheduleRetry(DateTime now) {
    nextRetryAt = now.add(
      commerceReportRetryDelay(retryAttempt),
    );
    retryAttempt += 1;
  }
}

final class _RetainedCommerceTransaction {
  _RetainedCommerceTransaction(this.report, this._transaction);

  final CommerceReportRecord report;
  CommerceStoreTransaction _transaction;
  bool _deviceCompleted = false;
  _RetainedCommerceTransaction? _sharedCompletion;

  _RetainedCommerceTransaction get _completion {
    final shared = _sharedCompletion;
    if (shared == null) return this;
    return _sharedCompletion = shared._completion;
  }

  CommerceStoreTransaction get transaction => _completion._transaction;
  bool get deviceCompleted => _completion._deviceCompleted;
  set deviceCompleted(bool value) => _completion._deviceCompleted = value;

  void retainCompletionTransaction(CommerceStoreTransaction candidate) {
    final completion = _completion;
    if (!completion._deviceCompleted &&
        !completion._transaction.requiresDeviceCompletion &&
        candidate.requiresDeviceCompletion) {
      completion._transaction = candidate;
    }
  }

  void shareCompletionWith(_RetainedCommerceTransaction other) {
    if (!matchesReport(other.report)) return;
    final completion = _completion;
    final shared = other._completion;
    if (identical(completion, shared)) return;
    completion._deviceCompleted |= shared._deviceCompleted;
    completion.retainCompletionTransaction(shared._transaction);
    // Redirect existing observers, including a native finish already awaiting
    // its provider, so subsequent success and instance preference stay shared.
    shared._sharedCompletion = completion;
  }

  bool matchesObservation(
    CommerceStoreTransaction candidate,
    String configurationFingerprint,
  ) =>
      report.configurationFingerprint == configurationFingerprint &&
      report.store == candidate.store &&
      report.storeTransactionId ==
          _nonEmptyOrNull(candidate.storeTransactionId) &&
      report.storeProductId == candidate.storeProductId &&
      candidate.storeVerificationData != null &&
      commerceVerificationIdentity(
              report.store.value, report.storeVerificationData) ==
          commerceVerificationIdentity(
              candidate.store.value, candidate.storeVerificationData!);

  bool matchesReport(CommerceReportRecord candidate) =>
      report.hasSameProviderIdentity(candidate);
}

final class _OwnedQueryMember {
  _OwnedQueryMember(this.transaction);

  CommerceStoreTransaction transaction;
  int? attemptGeneration;
  _PendingCommerceAdmission? completionAdmission;

  void retainCompletionTransaction(CommerceStoreTransaction candidate) {
    if (!transaction.requiresDeviceCompletion &&
        candidate.requiresDeviceCompletion) {
      transaction = candidate;
    }
  }
}

/// Bounds each commerce network or store attempt.
class CommerceAttemptDeadline {
  /// Creates a deadline that expires each attempt after [timeout].
  const CommerceAttemptDeadline([this.timeout = const Duration(seconds: 15)]);

  /// How long one attempt may take.
  final Duration timeout;

  /// Returns [attempt], failing with a [TimeoutException] once it expires.
  Future<T> bound<T>(Future<T> attempt) => attempt.timeout(timeout);
}

extension _BoundedAttempt<T> on Future<T> {
  Future<T> within(CommerceAttemptDeadline deadline) => deadline.bound(this);
}

final class _StoreAdapterCommerceEngine implements _CommerceEngine {
  _StoreAdapterCommerceEngine({
    required this.adapter,
    required RestageRpcClient? Function() rpcClientProvider,
    required Future<String> Function() applicationAnonymousTokenProvider,
    CommerceRuntimeContext? Function()? runtimeContextProvider,
    required Future<CommerceReportQueue> Function() reportQueueFactory,
    required void Function(CommercePurchaserState) onState,
    CommerceAttemptDeadline attemptDeadline = const CommerceAttemptDeadline(),
    DateTime Function() clock = DateTime.now,
  })  : _rpcClientProvider = rpcClientProvider,
        _runtimeContextProvider = runtimeContextProvider ??
            (() => CommerceRuntimeContext(
                  configurationFingerprint: _defaultConfigurationFingerprint,
                  applicationAnonymousTokenProvider: () async =>
                      applicationAnonymousTokenProvider(),
                )),
        _reportQueueFactory = reportQueueFactory,
        _onState = onState,
        _attemptDeadline = attemptDeadline,
        _clock = clock {
    _transactions = adapter.transactions.listen(
      _recordTransactionFromStore,
      onError: (Object _, StackTrace __) {},
    );
    _requestDrain();
    _requestOwnedRecovery();
  }

  static const String _subscriptionProductKind = 'autoRenewableSubscription';
  static const String _defaultConfigurationFingerprint =
      'unscoped-commerce-test-context';

  final CommerceStoreAdapter adapter;
  final RestageRpcClient? Function() _rpcClientProvider;
  final CommerceRuntimeContext? Function() _runtimeContextProvider;
  final Future<CommerceReportQueue> Function() _reportQueueFactory;
  final void Function(CommercePurchaserState) _onState;
  final CommerceAttemptDeadline _attemptDeadline;
  final DateTime Function() _clock;
  final Map<String, _RetainedCommerceTransaction> _transactionsByReportId =
      <String, _RetainedCommerceTransaction>{};
  final Map<String, _PendingCommerceAdmission> _pendingAdmissions =
      <String, _PendingCommerceAdmission>{};
  final Set<_PendingCommerceAdmission> _unresolvedAdmissions =
      <_PendingCommerceAdmission>{};
  final Set<String> _inFlightReportIds = <String>{};
  final Set<String> _ownedQueryReservedReportIds = <String>{};
  final Map<String, Future<CommerceReportResponse?>> _reportAttemptsById =
      <String, Future<CommerceReportResponse?>>{};

  late final StreamSubscription<CommerceStoreTransaction> _transactions;
  Future<CommerceReportQueue>? _queueFuture;
  Future<void> _operations = Future<void>.value();
  Future<void>? _drainInFlight;
  bool _drainRequested = false;
  Timer? _retryTimer;
  bool _ownedRecoveryInFlight = false;
  bool _ownedRecoveryRequested = false;
  int _ownedRecoveryAttempt = 0;
  DateTime? _nextOwnedRecoveryAt;
  int _ownedQueryGeneration = 0;
  bool _ownedSnapshotCurrent = false;
  CommerceRuntimeContext? _ownedSnapshotContext;
  String? _ownedSnapshotConfigurationFingerprint;
  String? _ownedSnapshotApplicationAnonymousToken;
  List<EntitlementSummary> _ownedSnapshotEntitlements =
      const <EntitlementSummary>[];
  bool? _ownedSnapshotHasProductionPurchaseHistory;
  bool _hasObservedProductionPurchaseHistory = false;
  int _stateEpoch = 0;
  int _statePublicationRevision = 0;
  DateTime? _lastPublishedPurchaserStateAt;
  late CommercePurchaserState _lastPublishedPurchaserState = _staleState();
  bool _disposed = false;

  @override
  Future<CommerceAvailability> availability(
    CommerceAvailabilityRequest request,
  ) async {
    final CommerceFailureCode? failureCode;
    if (!request.capability.isKnown || !adapter.store.isKnown) {
      failureCode = CommerceFailureCode.unsupportedCapability;
    } else if (request.offerId != null &&
        request.capability != CommerceCapabilityCode.purchase) {
      failureCode = CommerceFailureCode.invalidRequest;
    } else {
      failureCode = null;
    }
    return CommerceAvailability._(
      capability: request.capability,
      offerId: request.offerId,
      available: failureCode == null,
      failureCode: failureCode,
    );
  }

  @override
  Future<CommerceActionResult> purchase(CommercePurchaseRequest request) {
    final mountContext = MountAttributionEventContext.bound?.capture();
    final capturedCommerceContext =
        mountContext == null ? null : _currentContext();
    return _run(() async {
      if (_disposed || !adapter.store.isKnown) {
        return _unavailableAction(CommerceFailureCode.unsupportedCapability);
      }
      try {
        await _queue();
      } on Object {
        return _unavailableAction(CommerceFailureCode.unsupportedCapability);
      }

      final context =
          mountContext == null ? _currentContext() : capturedCommerceContext;
      final token = await _applicationAnonymousToken(context);
      final client = _rpcClientProvider();
      if (context == null ||
          !context.isCurrent ||
          token == null ||
          !isValidUuidV4(token) ||
          client == null) {
        return _failedAction(CommerceFailureCode.unsupportedResponse);
      }
      final intentId = generateUuidV4();
      if (mountContext != null && !mountContext.isAdmitted) {
        return _failedAction(CommerceFailureCode.unsupportedResponse);
      }
      final mount = mountContext?.snapshot;
      final selectedSurface = mount?.attribution.actualSurface;
      final response = await client
          .createCommerceIntent(
            CommerceIntentRequest(
              intentId: intentId,
              offerId: request.offerId.value,
              store: adapter.store.value,
              appAnonymousToken: token,
              surfaceId: selectedSurface?.surfaceIdentity.surfaceId.value,
              surfaceKind: mount?.selectedDocument?.surfaceType.wireName,
              variantSlug: mount?.selectedDocument?.surfaceSlug,
              publishedVersion:
                  mount?.attribution.actualPublication?.publishedVersion,
              attribution: mount?.attribution,
              routingSelectionReceipt: mount?.routingSelectionReceipt,
              assignment: mount?.assignment,
            ),
          )
          .within(_attemptDeadline);
      if (response == null ||
          response.intentId != intentId ||
          response.status != 'ready' ||
          !context.isCurrent) {
        return _failedAction(CommerceFailureCode.unsupportedResponse);
      }
      final resolved = response.resolved;
      if (resolved.productKind != _subscriptionProductKind ||
          resolved.offerSignature != null) {
        return _failedAction(CommerceFailureCode.unsupportedCapability);
      }

      final products = await adapter.queryProducts({resolved.storeProductId});
      if (!context.isCurrent) {
        return _failedAction(CommerceFailureCode.unsupportedResponse);
      }
      final product = _matchingProduct(products, response);
      if (product == null) {
        return _failedAction(CommerceFailureCode.unsupportedResponse);
      }
      final presented = await adapter.startPurchase(
        CommerceStorePurchasable(
          product: product,
          applicationAccountToken: resolved.appAccountToken,
        ),
      );
      return CommerceActionResult._(
        status: presented
            ? CommerceActionStatusCode.pending
            : CommerceActionStatusCode.notPresented,
      );
    }).catchError(
      (Object _) => _failedAction(CommerceFailureCode.unsupportedResponse),
    );
  }

  @override
  Future<CommerceActionResult> restore() => _run(() async {
        if (_disposed) {
          return _unavailableAction(CommerceFailureCode.unsupportedCapability);
        }
        try {
          final state = await _refresh();
          if (state.status != CommercePurchaserStateStatusCode.available) {
            return _failedAction(CommerceFailureCode.unsupportedResponse);
          }
          return CommerceActionResult._(
            status: CommerceActionStatusCode.submittedForReconciliation,
          );
        } on Object {
          return _failedAction(CommerceFailureCode.unsupportedResponse);
        }
      });

  @override
  Future<CommercePurchaserState> refresh() => _run(_refresh);

  Future<CommercePurchaserState> _refresh() async {
    if (_disposed) return _staleState();
    final epoch = _stateEpoch;
    final context = _currentContext();
    final queryGeneration = ++_ownedQueryGeneration;
    _clearOwnedSnapshot();
    _emit(_staleState());
    final publicationRevision = _statePublicationRevision;
    String? token;
    try {
      token = await _applicationAnonymousToken(
        context,
      ).within(_attemptDeadline);
    } on Object {
      return _lastPublishedPurchaserState;
    }
    final client = _rpcClientProvider();
    if (context == null ||
        !context.isCurrent ||
        token == null ||
        !isValidUuidV4(token) ||
        client == null) {
      return _lastPublishedPurchaserState;
    }
    _bindOwnedScope(context, token);
    try {
      final queried = await adapter.queryOwnedTransactions().within(
            _attemptDeadline,
          );
      if (!_isCurrentOwnedAttempt(context, epoch, queryGeneration)) {
        return _staleState();
      }
      final members = <String, _OwnedQueryMember>{};
      for (final transaction in queried) {
        if (!_isReportableTransaction(transaction)) {
          throw StateError('Owned transaction snapshot is incomplete');
        }
        final key = _transactionKey(
          transaction,
          context.configurationFingerprint,
          token,
        );
        members
            .putIfAbsent(key, () => _OwnedQueryMember(transaction))
            .retainCompletionTransaction(transaction);
      }
      final reportResults = await Future.wait([
        for (final member in members.values)
          _verifyOwnedQueryMember(
            member,
            context: context,
            applicationAnonymousToken: token,
            epoch: epoch,
            queryGeneration: queryGeneration,
          ),
      ]).within(_attemptDeadline);
      if (!_isCurrentOwnedAttempt(context, epoch, queryGeneration)) {
        return _staleState();
      }
      if (members.values.any(
        (member) => member.attemptGeneration != queryGeneration,
      )) {
        throw StateError('Owned transaction attempt was not query-scoped');
      }
      final scopedEntitlements = <EntitlementSummary>[];
      final reportedStates = <CommercePurchaserStateResponse>[];
      for (final response in reportResults) {
        final verified = response?.verifiedPurchaseState;
        if (response?.outcome != 'verified' ||
            verified == null ||
            verified.status != 'current') {
          throw StateError('Owned transaction was not freshly verified');
        }
        reportedStates.addAll([response!.purchaserState, verified]);
        scopedEntitlements.addAll(verified.entitlements);
        _rememberProductionPurchaseHistory([response.purchaserState, verified]);
      }
      final knownTransactionIds = await _knownTransactionIds(
        context,
        token,
      ).within(_attemptDeadline);
      if (!_isCurrentOwnedAttempt(context, epoch, queryGeneration)) {
        return _staleState();
      }
      final response = await client
          .fetchCommercePurchaserState(
            CommercePurchaserStateRequest(
              appAnonymousToken: token,
              knownStoreTransactionIds: knownTransactionIds,
            ),
          )
          .within(_attemptDeadline);
      if (!_isCurrentOwnedAttempt(context, epoch, queryGeneration)) {
        return _staleState();
      }
      if (response == null) {
        throw StateError('Canonical purchaser state is unavailable');
      }
      if (response.status != 'current') {
        _clearOwnedSnapshot();
        return _emitFreshState(
          response,
          context: context,
          applicationAnonymousToken: token,
          additionalPurchaseStates: reportedStates,
        );
      }
      _rememberProductionPurchaseHistory([response, ...reportedStates]);
      final lastPublishedAt = _lastPublishedPurchaserStateAt;
      if (lastPublishedAt != null &&
          response.retrievedAt.isBefore(lastPublishedAt)) {
        _clearOwnedSnapshot();
        return _publishObservedProductionPurchaseHistory();
      }
      _ownedSnapshotCurrent = true;
      _ownedSnapshotContext = context;
      _ownedSnapshotConfigurationFingerprint = context.configurationFingerprint;
      _ownedSnapshotApplicationAnonymousToken = token;
      _ownedSnapshotEntitlements = List<EntitlementSummary>.unmodifiable(
        scopedEntitlements,
      );
      _ownedSnapshotHasProductionPurchaseHistory = _mergeProductionHistory(
        reportedStates.map(_productionPurchaseHistory),
      );
      final state = _emitFreshState(
        response,
        context: context,
        applicationAnonymousToken: token,
      );
      _ownedRecoveryAttempt = 0;
      _nextOwnedRecoveryAt = null;
      return state;
    } on Object {
      if (!_isCurrentOwnedAttempt(context, epoch, queryGeneration)) {
        return _staleState();
      }
      _clearOwnedSnapshot();
      return _emitStaleIfUnchanged(publicationRevision);
    }
  }

  @override
  void configurationChanged() {
    final context = _currentContext();
    if (context != null &&
        _ownedSnapshotCurrent &&
        (_ownedSnapshotContext?.isCurrent ?? false) &&
        _ownedSnapshotConfigurationFingerprint ==
            context.configurationFingerprint) {
      _retryPendingAdmissions();
      _requestDrain();
      _scheduleRetryWake();
      return;
    }
    _invalidateState(
      resetProductionHistory: context == null ||
          _ownedSnapshotConfigurationFingerprint !=
              context.configurationFingerprint,
    );
    _retryPendingAdmissions();
    _requestDrain();
    _requestOwnedRecovery(force: true);
    _scheduleRetryWake();
  }

  @override
  void identityChanged() {
    _invalidateState();
    _retryPendingAdmissions();
    _requestDrain();
    _requestOwnedRecovery(force: true);
    _scheduleRetryWake();
  }

  @override
  void foregrounded() {
    _retryPendingAdmissions();
    _requestDrain();
    _requestOwnedRecovery(force: true);
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _retryTimer?.cancel();
    await _transactions.cancel();
    while (_inFlight.isNotEmpty) {
      await Future.wait(_inFlight.toList());
    }
  }

  /// Background work that [dispose] waits for.
  final Set<Future<void>> _inFlight = <Future<void>>{};

  void _track(Future<void> work) {
    late final Future<void> settled;
    settled = work.catchError((Object _) {}).whenComplete(
          () => _inFlight.remove(settled),
        );
    _inFlight.add(settled);
  }

  CommerceStoreProduct? _matchingProduct(
    List<CommerceStoreProduct> products,
    CommerceIntentResponse response,
  ) {
    final resolved = response.resolved;
    final matches = products.where(
      (product) =>
          product.store == adapter.store &&
          product.storeProductId == resolved.storeProductId &&
          product.kind == CommerceStoreProductKind.subscription &&
          product.basePlanId == resolved.basePlanId &&
          product.storeOfferIdentifier == resolved.storeOfferIdentifier,
    );
    return matches.length == 1 ? matches.single : null;
  }

  void _recordTransactionFromStore(CommerceStoreTransaction transaction) {
    if (!_isReportableTransaction(transaction)) return;
    final context = _currentContext();
    if (context == null || !context.isCurrent) return;
    final admission = _PendingCommerceAdmission(
      transaction: transaction,
      context: context,
      applicationAnonymousTokenProvider: () =>
          _applicationAnonymousToken(context),
    );
    _captureObservedCompletions(admission);
    _unresolvedAdmissions.add(admission);
    _admit(admission);
  }

  void _captureObservedCompletions(_PendingCommerceAdmission admission) {
    final observed = <_RetainedCommerceTransaction>[
      ..._transactionsByReportId.values,
      for (final pending in <_PendingCommerceAdmission>{
        ..._unresolvedAdmissions,
        ..._pendingAdmissions.values,
      })
        ...pending.observedCompletions,
    ];
    for (final retained in observed) {
      admission.observeCompletion(retained);
    }
  }

  bool _isReportableTransaction(CommerceStoreTransaction transaction) {
    if (_disposed || transaction.store != adapter.store) return false;
    if (transaction.store != CommerceStore.appStore &&
        transaction.store != CommerceStore.playStore) {
      return false;
    }
    if (transaction.status != CommerceStoreTransactionStatus.purchased &&
        transaction.status != CommerceStoreTransactionStatus.restored) {
      return false;
    }
    final verificationData = transaction.storeVerificationData;
    if (verificationData == null ||
        verificationData.isEmpty ||
        transaction.storeProductId.isEmpty) {
      return false;
    }
    try {
      commerceVerificationIdentity(transaction.store.value, verificationData);
    } on FormatException {
      return false;
    }
    final transactionId = _nonEmptyOrNull(transaction.storeTransactionId);
    return transaction.store != CommerceStore.appStore || transactionId != null;
  }

  String _transactionKey(
    CommerceStoreTransaction transaction,
    String configurationFingerprint,
    String applicationAnonymousToken,
  ) =>
      '$configurationFingerprint\u0000$applicationAnonymousToken\u0000'
      '${transaction.store.value}\u0000'
      '${transaction.storeTransactionId ?? commerceVerificationIdentity(transaction.store.value, transaction.storeVerificationData!)}'
      '\u0000${transaction.storeProductId}'
      '\u0000${commerceVerificationIdentity(transaction.store.value, transaction.storeVerificationData!)}';

  void _admit(_PendingCommerceAdmission admission) {
    if (_disposed ||
        admission.inFlight ||
        admission.nextRetryAt.isAfter(_now())) {
      return;
    }
    admission.inFlight = true;
    _track(_admitPending(admission));
  }

  Future<void> _admitPending(_PendingCommerceAdmission admission) async {
    try {
      var record = admission.record;
      if (record == null) {
        final context = admission.context;
        var token = admission.applicationAnonymousToken;
        if (token == null) {
          token = await admission.resolveApplicationAnonymousToken();
          if (token != null && isValidUuidV4(token)) {
            admission.applicationAnonymousToken = token;
          }
        }
        if (token == null || !isValidUuidV4(token)) {
          if (!context.isCurrent) {
            _removeAdmission(admission);
          } else {
            admission.clearUnresolvedToken();
            _retryAdmission(admission);
          }
          return;
        }
        final key = _transactionKey(
          admission.transaction,
          context.configurationFingerprint,
          token,
        );
        final existing = _pendingAdmissions[key];
        if (existing != null && !identical(existing, admission)) {
          existing.retainCompletionTransaction(admission.transaction);
          for (final observed in admission.observedCompletions) {
            existing.observeCompletion(observed);
          }
          _removeAdmission(admission);
          return;
        }
        _unresolvedAdmissions.remove(admission);
        _pendingAdmissions[key] = admission;
        record = CommerceReportRecord(
          reportId: generateUuidV4(),
          store: admission.transaction.store,
          storeVerificationData: admission.transaction.storeVerificationData!,
          storeProductId: admission.transaction.storeProductId,
          storeTransactionId: _nonEmptyOrNull(
            admission.transaction.storeTransactionId,
          ),
          applicationAnonymousToken: token,
          configurationFingerprint: context.configurationFingerprint,
        );
        admission.record = record;
      }
      final queued = await (await _queue()).enqueue(record);
      if (_disposed) return;
      if (!admission.requestDrainAfterPersist) {
        _ownedQueryReservedReportIds
          ..remove(record.reportId)
          ..add(queued.reportId);
      }
      _retainTransactionForReport(queued, admission);
      if (!admission.durableRecord.isCompleted) {
        admission.durableRecord.complete(queued);
      }
      _removeAdmission(admission);
      if (admission.requestDrainAfterPersist) _requestDrain();
      _scheduleRetryWake();
    } on Object {
      _retryAdmission(admission);
    } finally {
      admission.inFlight = false;
      if (_containsAdmission(admission)) _scheduleRetryWake();
    }
  }

  bool _containsAdmission(_PendingCommerceAdmission admission) =>
      _unresolvedAdmissions.contains(admission) ||
      _pendingAdmissions.values.any((value) => identical(value, admission));

  void _removeAdmission(_PendingCommerceAdmission admission) {
    _unresolvedAdmissions.remove(admission);
    _pendingAdmissions.removeWhere((_, value) => identical(value, admission));
  }

  void _retryAdmission(_PendingCommerceAdmission admission) {
    if (_disposed) return;
    admission.scheduleRetry(_now());
  }

  void _retainTransactionForReport(
    CommerceReportRecord report,
    _PendingCommerceAdmission admission,
  ) {
    var retained = _transactionsByReportId[report.reportId];
    if (retained == null || !retained.matchesReport(report)) {
      retained = _RetainedCommerceTransaction(report, admission.transaction);
      _transactionsByReportId[report.reportId] = retained;
    }
    for (final observed in admission.observedCompletions) {
      observed.shareCompletionWith(retained);
    }
    retained.retainCompletionTransaction(admission.transaction);
    // An observation can predate the first durable admission. Attach the new
    // reference before retirement can remove this report's collection root.
    // Pending observations retain it only until their own admission settles.
    for (final pending in <_PendingCommerceAdmission>{
      ..._unresolvedAdmissions,
      ..._pendingAdmissions.values,
    }) {
      pending.observeCompletion(retained);
    }
  }

  void _retryPendingAdmissions() {
    final now = _now();
    final admissions = <_PendingCommerceAdmission>{
      ..._unresolvedAdmissions,
      ..._pendingAdmissions.values,
    };
    for (final admission in admissions) {
      if (!admission.nextRetryAt.isAfter(now)) _admit(admission);
    }
  }

  Future<CommerceReportRecord> _durableReportForOwnedMember(
    _OwnedQueryMember member, {
    required CommerceRuntimeContext context,
    required String applicationAnonymousToken,
  }) {
    final transaction = member.transaction;
    final key = _transactionKey(
      transaction,
      context.configurationFingerprint,
      applicationAnonymousToken,
    );
    var admission = _pendingAdmissions[key];
    if (admission == null) {
      admission = _PendingCommerceAdmission(
        transaction: transaction,
        context: context,
        applicationAnonymousTokenProvider: () async =>
            applicationAnonymousToken,
        requestDrainAfterPersist: false,
      )
        ..applicationAnonymousToken = applicationAnonymousToken
        ..record = CommerceReportRecord(
          reportId: generateUuidV4(),
          store: transaction.store,
          storeVerificationData: transaction.storeVerificationData!,
          storeProductId: transaction.storeProductId,
          storeTransactionId: _nonEmptyOrNull(
            transaction.storeTransactionId,
          ),
          applicationAnonymousToken: applicationAnonymousToken,
          configurationFingerprint: context.configurationFingerprint,
        );
      _pendingAdmissions[key] = admission;
      _ownedQueryReservedReportIds.add(admission.record!.reportId);
    } else {
      admission.retainCompletionTransaction(transaction);
    }
    // Keep this member's observed completion live across fresh report UUIDs.
    for (final observed in member.completionAdmission?.observedCompletions ??
        const <_RetainedCommerceTransaction>[]) {
      admission.observeCompletion(observed);
    }
    member.completionAdmission = admission;
    _captureObservedCompletions(admission);
    _admit(admission);
    return admission.durableRecord.future;
  }

  Future<CommerceReportResponse?> _verifyOwnedQueryMember(
    _OwnedQueryMember member, {
    required CommerceRuntimeContext context,
    required String applicationAnonymousToken,
    required int epoch,
    required int queryGeneration,
  }) async {
    String? reservedReportId;
    try {
      var record = await _durableReportForOwnedMember(
        member,
        context: context,
        applicationAnonymousToken: applicationAnonymousToken,
      );
      if (_ownedQueryReservedReportIds.contains(record.reportId)) {
        reservedReportId = record.reportId;
      }
      while (true) {
        final collision = _reportAttemptsById[record.reportId];
        if (collision == null) break;
        await collision.within(_attemptDeadline);
        record = await _durableReportForOwnedMember(
          member,
          context: context,
          applicationAnonymousToken: applicationAnonymousToken,
        );
        if (reservedReportId != record.reportId) {
          _ownedQueryReservedReportIds.remove(reservedReportId);
          reservedReportId = null;
        }
        if (_ownedQueryReservedReportIds.contains(record.reportId)) {
          reservedReportId = record.reportId;
        }
      }
      if (!_isCurrentOwnedAttempt(context, epoch, queryGeneration)) {
        throw StateError('Owned transaction query context changed');
      }
      member.attemptGeneration = queryGeneration;
      _ownedQueryReservedReportIds.remove(record.reportId);
      reservedReportId = null;
      return await _startReportAttempt(
        record,
        context: context,
        epoch: epoch,
        publishPurchaserState: false,
      );
    } finally {
      member.completionAdmission = null;
      final reserved = reservedReportId;
      if (reserved != null && _ownedQueryReservedReportIds.remove(reserved)) {
        _requestDrain();
        _scheduleRetryWake();
      }
    }
  }

  void _requestDrain() {
    if (_disposed) return;
    _drainRequested = true;
    if (_drainInFlight != null) return;
    Future<void>? drain;
    drain = _drain().whenComplete(() {
      if (identical(_drainInFlight, drain)) {
        _drainInFlight = null;
        if (_drainRequested && !_disposed) _requestDrain();
      }
    });
    _drainInFlight = drain;
    _track(drain);
  }

  Future<void> _drain() async {
    while (!_disposed && _drainRequested) {
      _drainRequested = false;
      await _flushDueReports();
    }
  }

  Future<void> _flushDueReports() async {
    if (_disposed) return;
    final scope = _currentContext();
    if (scope == null || !scope.isCurrent || _rpcClientProvider() == null) {
      await _scheduleNextRetry();
      return;
    }

    final CommerceReportQueue queue;
    final List<CommerceReportRecord> reports;
    try {
      queue = await _queue();
      reports = await queue.due();
    } on Object {
      await _scheduleNextRetry();
      return;
    }

    for (final report in reports) {
      if (_disposed) return;
      final context = _currentContext();
      if (context == null ||
          !context.isCurrent ||
          context.configurationFingerprint != report.configurationFingerprint) {
        continue;
      }
      if (_rpcClientProvider() == null) break;
      if (_reportAttemptsById.containsKey(report.reportId) ||
          _ownedQueryReservedReportIds.contains(report.reportId)) {
        continue;
      }
      final epoch = _stateEpoch;
      await _startReportAttempt(
        report,
        context: context,
        epoch: epoch,
        publishPurchaserState: true,
        requireDurableDue: true,
      );
    }
    await _scheduleNextRetry(queue);
  }

  Future<CommerceReportResponse?> _startReportAttempt(
    CommerceReportRecord report, {
    required CommerceRuntimeContext context,
    required int epoch,
    required bool publishPurchaserState,
    bool requireDurableDue = false,
  }) {
    final active = _reportAttemptsById[report.reportId];
    if (active != null) return active;
    late Future<CommerceReportResponse?> attempt;
    attempt = _performReportAttempt(
      report,
      context: context,
      epoch: epoch,
      publishPurchaserState: publishPurchaserState,
      requireDurableDue: requireDurableDue,
    ).whenComplete(() {
      if (identical(_reportAttemptsById[report.reportId], attempt)) {
        _reportAttemptsById.remove(report.reportId);
        _inFlightReportIds.remove(report.reportId);
        _scheduleRetryWake();
      }
    });
    _reportAttemptsById[report.reportId] = attempt;
    _inFlightReportIds.add(report.reportId);
    return attempt;
  }

  Future<CommerceReportResponse?> _performReportAttempt(
    CommerceReportRecord report, {
    required CommerceRuntimeContext context,
    required int epoch,
    required bool publishPurchaserState,
    required bool requireDurableDue,
  }) async {
    final queue = await _queue();
    var currentReport = report;
    if (requireDurableDue) {
      // An earlier sender can acknowledge or reschedule this saved due entry.
      final due = await queue.due();
      final live = due.where(
        (candidate) => candidate.reportId == report.reportId,
      );
      if (live.isEmpty) return null;
      currentReport = live.single;
    }
    if (!_isCurrentAttempt(context, epoch) ||
        context.configurationFingerprint !=
            currentReport.configurationFingerprint) {
      await _scheduleRetry(queue, currentReport.reportId);
      return null;
    }
    final client = _rpcClientProvider();
    if (client == null ||
        !_isCurrentAttempt(context, epoch) ||
        context.configurationFingerprint !=
            currentReport.configurationFingerprint) {
      await _scheduleRetry(queue, currentReport.reportId);
      return null;
    }
    final CommerceReportResponse? response;
    try {
      response = await client
          .reportCommerce(
            CommerceReportRequest(
              reportId: currentReport.reportId,
              intentId: currentReport.intentId,
              store: currentReport.store.value,
              storeVerificationData: currentReport.storeVerificationData,
              storeProductId: currentReport.storeProductId,
              storeTransactionId: currentReport.storeTransactionId,
              appAnonymousToken: currentReport.applicationAnonymousToken,
            ),
          )
          .within(_attemptDeadline);
    } on Object {
      await _scheduleRetry(queue, currentReport.reportId);
      return null;
    }
    if (_disposed || !_isCurrentAttempt(context, epoch)) {
      await _scheduleRetry(queue, currentReport.reportId);
      return response;
    }
    if (response != null) {
      await _emitReportStateIfCurrent(
        currentReport,
        context,
        epoch,
        response,
        publishPurchaserState: publishPurchaserState,
      );
    }
    if (!_isCurrentAttempt(context, epoch)) {
      await _scheduleRetry(queue, currentReport.reportId);
      return response;
    }
    if (response == null ||
        response.outcome == 'unknown' ||
        response.outcome == 'pending') {
      await _scheduleRetry(queue, currentReport.reportId);
      return response;
    }
    if (response.outcome == 'verified' &&
        currentReport.store == CommerceStore.appStore) {
      final retained = _transactionsByReportId[currentReport.reportId];
      if (retained != null &&
          !retained.deviceCompleted &&
          retained.transaction.requiresDeviceCompletion) {
        try {
          await adapter.completeTransaction(retained.transaction);
          retained.deviceCompleted = true;
        } on Object {
          await _scheduleRetry(queue, currentReport.reportId);
          return response;
        }
        if (!_isCurrentAttempt(context, epoch)) {
          await _scheduleRetry(queue, currentReport.reportId);
          return response;
        }
      }
    }
    await _acknowledge(queue, currentReport.reportId);
    return response;
  }

  Future<void> _emitReportStateIfCurrent(
    CommerceReportRecord report,
    CommerceRuntimeContext context,
    int epoch,
    CommerceReportResponse response, {
    required bool publishPurchaserState,
  }) async {
    final currentSubject = publishPurchaserState
        ? await _isCurrentReportSubject(report, context, epoch)
        : _isCurrentAttempt(context, epoch) &&
            _hasCurrentOwnedScope(context, report.applicationAnonymousToken);
    if (!currentSubject) return;
    _bindOwnedScope(context, report.applicationAnonymousToken);
    final verified =
        response.outcome == 'verified' ? response.verifiedPurchaseState : null;
    final additionalPurchaseStates = [if (verified != null) verified];
    if (publishPurchaserState &&
        _hasCurrentOwnedSnapshot(context, report.applicationAnonymousToken)) {
      _emitFreshState(
        response.purchaserState,
        context: context,
        applicationAnonymousToken: report.applicationAnonymousToken,
        additionalPurchaseStates: additionalPurchaseStates,
      );
    } else {
      _rememberProductionPurchaseHistory([
        response.purchaserState,
        ...additionalPurchaseStates,
      ]);
      _publishObservedProductionPurchaseHistory();
    }
  }

  Future<bool> _isCurrentReportSubject(
    CommerceReportRecord report,
    CommerceRuntimeContext context,
    int epoch,
  ) async {
    if (!_isCurrentAttempt(context, epoch)) return false;
    final token = await _applicationAnonymousToken(context);
    return token == report.applicationAnonymousToken &&
        _isCurrentAttempt(context, epoch);
  }

  bool _isCurrentAttempt(CommerceRuntimeContext context, int epoch) {
    if (_disposed || epoch != _stateEpoch || !context.isCurrent) return false;
    final current = _currentContext();
    return current != null &&
        current.isCurrent &&
        current.configurationFingerprint == context.configurationFingerprint;
  }

  bool _isCurrentOwnedAttempt(
    CommerceRuntimeContext context,
    int epoch,
    int queryGeneration,
  ) =>
      queryGeneration == _ownedQueryGeneration &&
      _isCurrentAttempt(context, epoch);

  Future<void> _acknowledge(CommerceReportQueue queue, String reportId) async {
    try {
      await queue.acknowledge(reportId);
      _transactionsByReportId.remove(reportId);
    } on Object {
      await _scheduleRetry(queue, reportId);
    }
  }

  Future<void> _scheduleRetry(
    CommerceReportQueue queue,
    String reportId,
  ) async {
    try {
      await queue.scheduleRetry(reportId);
    } on Object {
      return;
    }
  }

  DateTime _now() => _clock().toUtc();

  void _scheduleRetryWake() => _startBackground(_scheduleNextRetry);

  Future<void> _scheduleNextRetry([CommerceReportQueue? readyQueue]) async {
    _retryTimer?.cancel();
    if (_disposed) return;

    DateTime? next;
    void consider(DateTime candidate) {
      if (next == null || candidate.isBefore(next!)) next = candidate;
    }

    for (final admission in <_PendingCommerceAdmission>{
      ..._unresolvedAdmissions,
      ..._pendingAdmissions.values,
    }) {
      if (!admission.inFlight) consider(admission.nextRetryAt);
    }
    final recoveryAt = _nextOwnedRecoveryAt;
    if (recoveryAt != null && !_ownedRecoveryInFlight) consider(recoveryAt);

    final context = _currentContext();
    if (context != null && context.isCurrent && _rpcClientProvider() != null) {
      try {
        final queue = readyQueue ?? await _queue();
        final records = await queue.open();
        if (context.isCurrent) {
          for (final record in records) {
            if (record.configurationFingerprint ==
                    context.configurationFingerprint &&
                !_inFlightReportIds.contains(record.reportId) &&
                !_ownedQueryReservedReportIds.contains(record.reportId)) {
              consider(record.nextRetryAt);
            }
          }
        }
      } on Object {
        // A pending admission retries queue creation with the same backoff.
      }
    }

    final retryAt = next;
    if (retryAt == null || _disposed) return;
    final delay = retryAt.difference(_now());
    _retryTimer = Timer(delay.isNegative ? Duration.zero : delay, () {
      final retryOwnedRecovery = _isOwnedRecoveryDue();
      _retryPendingAdmissions();
      _requestDrain();
      if (retryOwnedRecovery) _requestOwnedRecovery();
      _scheduleRetryWake();
    });
  }

  bool _isOwnedRecoveryDue() {
    final retryAt = _nextOwnedRecoveryAt;
    return retryAt != null && !retryAt.isAfter(_now());
  }

  void _requestOwnedRecovery({bool force = false}) {
    if (_disposed ||
        (!force && (_nextOwnedRecoveryAt?.isAfter(_now()) ?? false))) {
      return;
    }
    _ownedRecoveryRequested = true;
    if (_ownedRecoveryInFlight) return;
    final context = _currentContext();
    if (context == null || !context.isCurrent) {
      return;
    }
    _ownedRecoveryRequested = false;
    _ownedRecoveryInFlight = true;
    _track(_recoverOwnedPurchases());
  }

  Future<void> _recoverOwnedPurchases() async {
    try {
      final state = await _run(_refresh);
      if (state.status != CommercePurchaserStateStatusCode.available) {
        throw StateError('Owned purchase recovery is not current');
      }
      _ownedRecoveryAttempt = 0;
      _nextOwnedRecoveryAt = null;
    } on Object {
      _nextOwnedRecoveryAt = _now().add(
        commerceReportRetryDelay(_ownedRecoveryAttempt),
      );
      _ownedRecoveryAttempt += 1;
    } finally {
      _ownedRecoveryInFlight = false;
      if (_ownedRecoveryRequested && !_disposed) {
        _requestOwnedRecovery(force: true);
      } else if (_nextOwnedRecoveryAt != null) {
        _scheduleRetryWake();
      }
    }
  }

  Future<List<String>> _knownTransactionIds(
    CommerceRuntimeContext context,
    String applicationAnonymousToken,
  ) async {
    if (!context.isCurrent) return const <String>[];
    try {
      final records = await (await _queue()).open();
      if (!context.isCurrent) return const <String>[];
      return records
          .where(
            (record) =>
                record.configurationFingerprint ==
                    context.configurationFingerprint &&
                record.applicationAnonymousToken == applicationAnonymousToken,
          )
          .map((record) => record.storeTransactionId)
          .whereType<String>()
          .toSet()
          .toList(growable: false);
    } on Object {
      return const <String>[];
    }
  }

  CommerceRuntimeContext? _currentContext() {
    try {
      return _runtimeContextProvider();
    } on Object {
      return null;
    }
  }

  Future<String?> _applicationAnonymousToken(
    CommerceRuntimeContext? context,
  ) async {
    if (context == null) return null;
    try {
      return await context.applicationAnonymousToken();
    } on Object {
      return null;
    }
  }

  Future<CommerceReportQueue> _queue() {
    final current = _queueFuture;
    if (current != null) return current;
    final future = Future<CommerceReportQueue>.sync(_reportQueueFactory).then((
      queue,
    ) async {
      await queue.open();
      return queue;
    });
    _queueFuture = future;
    unawaited(
      future.then<void>(
        (_) {},
        onError: (Object _, StackTrace __) {
          if (identical(_queueFuture, future)) _queueFuture = null;
        },
      ),
    );
    return future;
  }

  void _invalidateState({bool resetProductionHistory = true}) {
    _stateEpoch += 1;
    _ownedQueryGeneration += 1;
    _clearOwnedSnapshot(clearScope: resetProductionHistory);
    if (resetProductionHistory) _hasObservedProductionPurchaseHistory = false;
    _lastPublishedPurchaserStateAt = null;
    _lastPublishedPurchaserState = _staleState();
    _emit(_lastPublishedPurchaserState);
  }

  CommercePurchaserState _emitFreshState(
    CommercePurchaserStateResponse response, {
    required CommerceRuntimeContext context,
    required String applicationAnonymousToken,
    Iterable<CommercePurchaserStateResponse> additionalPurchaseStates =
        const [],
  }) {
    _rememberProductionPurchaseHistory([response, ...additionalPurchaseStates]);
    final last = _lastPublishedPurchaserStateAt;
    if (last != null && response.retrievedAt.isBefore(last)) {
      return _publishObservedProductionPurchaseHistory();
    }
    _lastPublishedPurchaserStateAt = response.retrievedAt;
    _lastPublishedPurchaserState = _project(
      _withOwnedSnapshot(
        response,
        context: context,
        applicationAnonymousToken: applicationAnonymousToken,
        hasProductionPurchaseHistory: _mergeProductionHistory([
          if (_hasObservedProductionPurchaseHistory) true,
          _productionPurchaseHistory(response),
          ...additionalPurchaseStates.map(_productionPurchaseHistory),
          if (_hasCurrentOwnedSnapshot(context, applicationAnonymousToken))
            _ownedSnapshotHasProductionPurchaseHistory,
        ]),
      ),
    );
    return _emit(_lastPublishedPurchaserState);
  }

  bool _hasCurrentOwnedSnapshot(
    CommerceRuntimeContext context,
    String applicationAnonymousToken,
  ) =>
      _ownedSnapshotCurrent &&
      _hasCurrentOwnedScope(context, applicationAnonymousToken);

  bool _hasCurrentOwnedScope(
    CommerceRuntimeContext context,
    String applicationAnonymousToken,
  ) =>
      (_ownedSnapshotContext?.isCurrent ?? false) &&
      _ownedSnapshotConfigurationFingerprint ==
          context.configurationFingerprint &&
      _ownedSnapshotApplicationAnonymousToken == applicationAnonymousToken &&
      context.isCurrent;

  CommercePurchaserStateResponse _withOwnedSnapshot(
    CommercePurchaserStateResponse canonical, {
    required CommerceRuntimeContext context,
    required String applicationAnonymousToken,
    required bool? hasProductionPurchaseHistory,
  }) {
    return CommercePurchaserStateResponse(
      status: canonical.status,
      entitlements: _selectEntitlements([
        ...canonical.entitlements,
        if (_hasCurrentOwnedSnapshot(context, applicationAnonymousToken))
          ..._ownedSnapshotEntitlements,
      ], hasProductionPurchaseHistory: hasProductionPurchaseHistory),
      retrievedAt: canonical.retrievedAt,
      hasProductionPurchaseHistory: hasProductionPurchaseHistory,
    );
  }

  void _bindOwnedScope(CommerceRuntimeContext context, String token) {
    if (_ownedSnapshotConfigurationFingerprint != null &&
        (_ownedSnapshotConfigurationFingerprint !=
                context.configurationFingerprint ||
            _ownedSnapshotApplicationAnonymousToken != token)) {
      _clearOwnedSnapshot();
      _hasObservedProductionPurchaseHistory = false;
    }
    if (!_ownedSnapshotCurrent) _ownedSnapshotContext = context;
    _ownedSnapshotConfigurationFingerprint = context.configurationFingerprint;
    _ownedSnapshotApplicationAnonymousToken = token;
  }

  void _clearOwnedSnapshot({bool clearScope = false}) {
    _ownedSnapshotCurrent = false;
    if (clearScope) {
      _ownedSnapshotContext = null;
      _ownedSnapshotConfigurationFingerprint = null;
      _ownedSnapshotApplicationAnonymousToken = null;
    }
    _ownedSnapshotEntitlements = const <EntitlementSummary>[];
    _ownedSnapshotHasProductionPurchaseHistory = null;
  }

  void _rememberProductionPurchaseHistory(
    Iterable<CommercePurchaserStateResponse> states,
  ) {
    if (states.any((state) => _productionPurchaseHistory(state) == true)) {
      _hasObservedProductionPurchaseHistory = true;
    }
  }

  CommercePurchaserState _publishObservedProductionPurchaseHistory() {
    final previous = _lastPublishedPurchaserState;
    if (!_hasObservedProductionPurchaseHistory ||
        previous.hasProductionPurchaseHistory == true) {
      return previous;
    }
    return _emit(CommercePurchaserState._(
      status: previous.status,
      entitlements: _selectEntitlements(
        previous.entitlements,
        hasProductionPurchaseHistory: true,
      ),
      hasProductionPurchaseHistory: true,
    ));
  }

  CommercePurchaserState _emitStaleIfUnchanged(int publicationRevision) {
    if (publicationRevision != _statePublicationRevision) {
      return _lastPublishedPurchaserState;
    }
    return _emit(_staleState());
  }

  CommercePurchaserState _project(CommercePurchaserStateResponse response) {
    return CommercePurchaserState._(
      status: switch (response.status) {
        'current' => CommercePurchaserStateStatusCode.available,
        'stale' => CommercePurchaserStateStatusCode.stale,
        _ => CommercePurchaserStateStatusCode.unknown,
      },
      entitlements: response.entitlements,
      hasProductionPurchaseHistory: response.hasProductionPurchaseHistory,
    );
  }

  CommercePurchaserState _staleState() => CommercePurchaserState._(
        status: CommercePurchaserStateStatusCode.stale,
        hasProductionPurchaseHistory:
            _hasObservedProductionPurchaseHistory ? true : null,
      );

  CommercePurchaserState _emit(CommercePurchaserState state) {
    if (!_disposed) {
      _lastPublishedPurchaserState = state;
      _statePublicationRevision += 1;
      _onState(state);
    }
    return state;
  }

  Future<T> _run<T>(Future<T> Function() operation) {
    final result = _operations.then((_) => operation());
    _operations = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  void _startBackground(Future<void> Function() operation) {
    _track(operation());
  }
}

List<EntitlementSummary> _selectEntitlements(
  Iterable<EntitlementSummary> candidates, {
  required bool? hasProductionPurchaseHistory,
}) {
  final selected = <String, EntitlementSummary>{};
  for (final candidate in candidates) {
    if (candidate.providerEnvironment == 'sandbox' &&
        hasProductionPurchaseHistory == true) {
      continue;
    }
    final current = selected[candidate.entitlementId];
    if (current == null || _compareEntitlements(candidate, current) < 0) {
      selected[candidate.entitlementId] = candidate;
    }
  }
  final result = selected.values.toList(growable: false)
    ..sort((left, right) => left.entitlementId.compareTo(right.entitlementId));
  return result;
}

bool? _productionPurchaseHistory(CommercePurchaserStateResponse state) {
  if (state.hasProductionPurchaseHistory == true ||
      state.entitlements.any(
        (entitlement) => entitlement.providerEnvironment == 'production',
      )) {
    return true;
  }
  return state.status == 'current' ? state.hasProductionPurchaseHistory : null;
}

bool? _mergeProductionHistory(Iterable<bool?> facts) {
  bool? result = false;
  for (final fact in facts) {
    if (fact == true) return true;
    if (fact == null) result = null;
  }
  return result;
}

int _compareEntitlements(EntitlementSummary left, EntitlementSummary right) {
  if (left.isEntitled != right.isEntitled) return left.isEntitled ? -1 : 1;
  final leftUnbounded = left.expiresAtMs == null;
  final rightUnbounded = right.expiresAtMs == null;
  if (leftUnbounded != rightUnbounded) return leftUnbounded ? -1 : 1;
  if (!leftUnbounded) {
    final byExpiry = right.expiresAtMs!.compareTo(left.expiresAtMs!);
    if (byExpiry != 0) return byExpiry;
  }
  var result = left.productId.compareTo(right.productId);
  if (result != 0) return result;
  result = left.source.compareTo(right.source);
  if (result != 0) return result;
  return left.status.compareTo(right.status);
}

CommercePurchaserState _unavailableCommerceState() => CommercePurchaserState._(
      status: CommercePurchaserStateStatusCode.unavailable,
    );

CommerceActionResult _unavailableAction(CommerceFailureCode failureCode) =>
    CommerceActionResult._(
      status: CommerceActionStatusCode.unavailable,
      failureCode: failureCode,
    );

CommerceActionResult _failedAction(CommerceFailureCode failureCode) =>
    CommerceActionResult._(
      status: CommerceActionStatusCode.failed,
      failureCode: failureCode,
    );

String? _nonEmptyOrNull(String? value) =>
    value == null || value.isEmpty ? null : value;

final _RestageCommerce _restageCommerceInstance = _RestageCommerce();

RestageCommerce get restageCommerceInstance => _restageCommerceInstance;

void activateRestageCommerce(
  CommerceStoreAdapter adapter, {
  required RestageRpcClient? Function() rpcClientProvider,
  required Future<String> Function() applicationAnonymousTokenProvider,
  CommerceRuntimeContext? Function()? runtimeContextProvider,
  Future<CommerceReportQueue> Function() reportQueueFactory =
      createCommerceReportQueue,
  CommerceAttemptDeadline attemptDeadline = const CommerceAttemptDeadline(),
  DateTime Function() clock = DateTime.now,
}) =>
    _restageCommerceInstance.activate(
      adapter,
      rpcClientProvider: rpcClientProvider,
      applicationAnonymousTokenProvider: applicationAnonymousTokenProvider,
      runtimeContextProvider: runtimeContextProvider,
      reportQueueFactory: reportQueueFactory,
      attemptDeadline: attemptDeadline,
      clock: clock,
    );

void notifyRestageCommerceConfigurationChanged() =>
    _restageCommerceInstance.configurationChanged();

void notifyRestageCommerceIdentityChanged() =>
    _restageCommerceInstance.identityChanged();

void notifyRestageCommerceForegrounded() =>
    _restageCommerceInstance.foregrounded();

/// Resets commerce; completes once the stopped engine's work has settled.
Future<void> debugResetRestageCommerce() =>
    _restageCommerceInstance.debugReset();

CommerceStoreAdapter? get debugRestageCommerceAdapter =>
    _restageCommerceInstance.debugStoreAdapter;
