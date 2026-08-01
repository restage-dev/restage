part of 'in_app_purchase_gateway.dart';

/// Configure-owned lifecycle for the bundled native billing gateway.
///
/// This class is internal to the SDK. It owns the only long-lived purchase
/// listener, native recovery drains, durable intent creation, and the
/// per-evidence processing barrier used by transaction reporting.
final class PurchaseCoordinator implements PurchaseCoordinatorDelegate {
  PurchaseCoordinator({
    required InAppPurchaseGateway gateway,
    required Set<String> knownSubscriptionProductIds,
    required Future<String?> Function() anonymousTokenProvider,
    required RestageRpcClient? Function() rpcClientProvider,
    required String store,
    required int epoch,
    required bool Function(int epoch) isCurrentEpoch,
    List<PurchasePlatformAdapter>? platformAdapters,
    Future<void> Function(
      StoreTransactionEvidence evidence,
      PurchaseProcessingContext context,
    )? evidenceProcessor,
    String Function()? purchaseIntentIdGenerator,
    String Function()? reportIdGenerator,
    Future<void> Function(String token)? authoritativeTokenReplacer,
    void Function(List<EntitlementSummary> entitlements)? entitlementReconciler,
    Future<void> Function()? entitlementSync,
    Future<bool> Function(String productId)? subscriptionVerifier,
    void Function(
      PurchaseOutcomeSucceeded outcome,
      PurchaseAttributionSnapshot attribution,
    )? delayedSuccessEmitter,
    Duration Function(int retryIndex)? retryDelayPolicy,
    Future<void> Function(Duration delay)? delay,
    int maxReportAttempts = 3,
    int maxFinishAttempts = 3,
    Duration finishAttemptTimeout = const Duration(seconds: 15),
    int markerCapacity = 256,
  })  : _gateway = gateway,
        _knownSubscriptionProductIds =
            Set.unmodifiable(knownSubscriptionProductIds),
        _anonymousTokenProvider = anonymousTokenProvider,
        _rpcClientProvider = rpcClientProvider,
        _store = store,
        _epoch = epoch,
        _isCurrentEpoch = isCurrentEpoch,
        _platformAdapters = platformAdapters ??
            debugPlatformAdapterFactory?.call(
              gateway._plugin,
              knownSubscriptionProductIds,
            ) ??
            _defaultPlatformAdapters(
              gateway._plugin,
              knownSubscriptionProductIds,
            ),
        _evidenceProcessorOverride =
            evidenceProcessor ?? debugEvidenceProcessor,
        _purchaseIntentIdGenerator =
            purchaseIntentIdGenerator ?? AnonymousTokenStore.generateUuidV4,
        _reportIdGenerator = reportIdGenerator ??
            debugReportIdGenerator ??
            AnonymousTokenStore.generateUuidV4,
        _authoritativeTokenReplacer =
            authoritativeTokenReplacer ?? _ignoreAuthoritativeToken,
        _entitlementReconciler = entitlementReconciler ?? _ignoreEntitlements,
        _entitlementSync = entitlementSync ?? _ignoreSync,
        _subscriptionVerifierOverride = subscriptionVerifier,
        _delayedSuccessEmitter = delayedSuccessEmitter ?? _ignoreDelayedSuccess,
        _retryDelayPolicy = retryDelayPolicy ??
            debugRetryDelayPolicy ??
            _defaultRetryDelayPolicy(),
        _delay = delay ?? debugDelay ?? Future<void>.delayed,
        _maxReportAttempts = max(1, maxReportAttempts),
        _maxFinishAttempts = max(1, maxFinishAttempts),
        _finishAttemptTimeout = finishAttemptTimeout,
        _acceptedEvidence = _BoundedMarkerMap(markerCapacity),
        _completedEvidence = _BoundedMarkerSet(markerCapacity);

  /// Test-only override for native recovery construction.
  @internal
  static List<PurchasePlatformAdapter> Function(
    InAppPurchase plugin,
    Set<String> knownSubscriptionProductIds,
  )? debugPlatformAdapterFactory;

  /// Test-only processor used to observe controlled transaction races.
  @internal
  static Future<void> Function(
    StoreTransactionEvidence evidence,
    PurchaseProcessingContext context,
  )? debugEvidenceProcessor;

  /// Test-only deterministic report-id source.
  @internal
  static String Function()? debugReportIdGenerator;

  /// Test-only deterministic retry schedule.
  @internal
  static Duration Function(int retryIndex)? debugRetryDelayPolicy;

  /// Test-only delay executor.
  @internal
  static Future<void> Function(Duration delay)? debugDelay;

  final InAppPurchaseGateway _gateway;
  final Set<String> _knownSubscriptionProductIds;
  final Future<String?> Function() _anonymousTokenProvider;
  final RestageRpcClient? Function() _rpcClientProvider;
  final String _store;
  final int _epoch;
  final bool Function(int epoch) _isCurrentEpoch;
  final List<PurchasePlatformAdapter> _platformAdapters;
  final Future<void> Function(
    StoreTransactionEvidence evidence,
    PurchaseProcessingContext context,
  )? _evidenceProcessorOverride;
  final String Function() _purchaseIntentIdGenerator;
  final String Function() _reportIdGenerator;
  final Future<void> Function(String token) _authoritativeTokenReplacer;
  final void Function(List<EntitlementSummary> entitlements)
      _entitlementReconciler;
  final Future<void> Function() _entitlementSync;
  final Future<bool> Function(String productId)? _subscriptionVerifierOverride;
  final void Function(
    PurchaseOutcomeSucceeded outcome,
    PurchaseAttributionSnapshot attribution,
  ) _delayedSuccessEmitter;
  final Duration Function(int retryIndex) _retryDelayPolicy;
  final Future<void> Function(Duration delay) _delay;
  final int _maxReportAttempts;
  final int _maxFinishAttempts;
  final Duration _finishAttemptTimeout;

  final Map<String, _PurchaseAttempt> _attemptsByProduct = {};
  final Set<String> _preparingProducts = <String>{};
  final Map<String, Future<void>> _evidenceInFlight = {};
  final Set<String> _verifiedSubscriptionProductIds = <String>{};
  final _BoundedMarkerMap<_AcceptedEvidenceState> _acceptedEvidence;
  final _BoundedMarkerSet _completedEvidence;

  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  _RestoreAttempt? _restoreAttempt;
  bool _active = false;

  bool get _isActive => _active && _isCurrentEpoch(_epoch);

  /// Installs the listener synchronously, then schedules configure drains.
  void start() {
    if (_active) return;
    _active = true;
    _purchaseSubscription = _gateway._plugin.purchaseStream.listen(
      _handlePurchaseBatch,
      onError: _handlePurchaseStreamError,
    );
    _gateway._purchaseCoordinator = this;
    BundledPurchaseOwnership.install(_gateway);
    for (final adapter in _platformAdapters) {
      if (adapter.drainOnConfigure) {
        scheduleMicrotask(() => _drain(adapter));
      }
    }
  }

  /// Invalidates all epoch-guarded work and removes the listener immediately.
  void cancel() {
    if (!_active) return;
    _active = false;
    if (identical(_gateway._purchaseCoordinator, this)) {
      _gateway._purchaseCoordinator = null;
    }
    BundledPurchaseOwnership.uninstall(_gateway);
    final subscription = _purchaseSubscription;
    _purchaseSubscription = null;
    if (subscription != null) unawaited(subscription.cancel());

    final attempts = _attemptsByProduct.values.toList(growable: false);
    _attemptsByProduct.clear();
    _preparingProducts.clear();
    _restoreAttempt = null;
    _evidenceInFlight.clear();
    _verifiedSubscriptionProductIds.clear();
    _acceptedEvidence.clear();
    _completedEvidence.clear();
    for (final attempt in attempts) {
      if (!attempt.completer.isCompleted) {
        attempt.completer.complete(
          PurchaseOutcome.failed(
            productId: attempt.productId,
            errorCode: RestageBillingErrorCodes.buyFailed,
            message: 'Billing configuration changed during the purchase.',
          ),
        );
      }
    }
  }

  /// Runs the resume-owned native drains without installing another listener.
  void onAppResumed() {
    if (!_isActive) return;
    for (final adapter in _platformAdapters) {
      if (adapter.drainOnResume) unawaited(_drain(adapter));
    }
  }

  @override
  Future<PurchaseOutcome> purchase(
    String productId, {
    String? basePlanId,
  }) {
    return purchaseProduct(productId, basePlanId: basePlanId);
  }

  /// Freezes the exact store subscription selection, then creates an immutable
  /// intent before resolving any signed offer or opening store UI.
  Future<PurchaseOutcome> purchaseProduct(
    String productId, {
    String? offerId,
    String? basePlanId,
  }) {
    final attribution = PurchaseAttributionScope.current;
    return _purchaseProduct(
      productId,
      offerId: offerId,
      basePlanId: basePlanId,
      attribution: attribution,
    );
  }

  Future<PurchaseOutcome> _purchaseProduct(
    String productId, {
    required String? offerId,
    required String? basePlanId,
    required PurchaseAttributionSnapshot? attribution,
  }) async {
    if (!_isActive) return _configurationChanged(productId);
    if (_attemptsByProduct.containsKey(productId) ||
        !_preparingProducts.add(productId)) {
      return PurchaseOutcome.failed(
        productId: productId,
        errorCode: RestageBillingErrorCodes.buyFailed,
        message: 'A purchase for this product is already in progress.',
      );
    }
    try {
      return await _prepareIntentAndOpenStore(
        productId,
        offerId: offerId,
        basePlanId: basePlanId,
        attribution: attribution,
      );
    } finally {
      _preparingProducts.remove(productId);
    }
  }

  Future<PurchaseOutcome> _prepareIntentAndOpenStore(
    String productId, {
    required String? offerId,
    required String? basePlanId,
    required PurchaseAttributionSnapshot? attribution,
  }) async {
    if (offerId != null && offerId.isEmpty) {
      return PurchaseOutcome.failed(
        productId: productId,
        errorCode: RestageBillingErrorCodes.offerUnavailable,
        message: 'An empty offer id cannot be applied.',
      );
    }

    final preparation = await _gateway._prepareCoordinatedPurchase(
      productId: productId,
      basePlanId: basePlanId,
      offerId: offerId,
      store: _store,
      isCurrentEpoch: () => _isActive,
    );
    if (!_isActive) return _configurationChanged(productId);
    final preparationFailure = preparation.failure;
    if (preparationFailure != null) return preparationFailure;
    final prepared = preparation.prepared;
    if (prepared == null) return _intentUnavailable(productId);
    _verifiedSubscriptionProductIds.add(productId);

    final committed = await _commitIntent(
      productId: productId,
      basePlanId: prepared.resolvedBasePlanId,
      offerId: offerId,
      attribution: attribution,
    );
    if (committed == null) {
      return _isActive
          ? _intentUnavailable(productId)
          : _configurationChanged(productId);
    }

    SignedNativeOffer? offer;
    if (offerId != null) {
      if (_store == 'appStore') {
        final signature = await committed.client.mintIntentBoundOfferSignature(
          IntentBoundOfferSignatureRequest(
            purchaseIntentId: committed.purchaseIntentId,
          ),
        );
        if (!_isActive) return _configurationChanged(productId);
        if (signature == null ||
            signature.scheme != OfferSignatureScheme.legacy) {
          return PurchaseOutcome.failed(
            productId: productId,
            errorCode: RestageBillingErrorCodes.offerUnavailable,
            message: 'No promotional-offer signature was available.',
          );
        }
        offer = AppleSignedOffer.fromSignature(
          offerId: offerId,
          signature: signature,
        );
      } else if (_store == 'playStore') {
        offer = GoogleOffer(
          offerId: offerId,
          basePlanId: prepared.resolvedBasePlanId,
        );
      } else {
        return PurchaseOutcome.failed(
          productId: productId,
          errorCode: RestageBillingErrorCodes.offerUnavailable,
          message: 'Native promotional offers are unavailable on this device.',
        );
      }
    }

    return _openStore(
      prepared: prepared,
      offer: offer,
      purchaseIntentId: committed.purchaseIntentId,
      attribution: attribution,
    );
  }

  @override
  Future<PurchaseOutcome> purchaseWithOffer({
    required String productId,
    required SignedNativeOffer offer,
  }) async {
    final offerId = switch (offer) {
      AppleSignedOffer(:final offerId) => offerId,
      GoogleOffer(:final offerId) => offerId,
      _ => null,
    };
    if (offerId == null) {
      return PurchaseOutcome.failed(
        productId: productId,
        errorCode: RestageBillingErrorCodes.offerUnavailable,
        message: 'This gateway cannot transport the requested offer.',
      );
    }
    return purchaseProduct(
      productId,
      basePlanId: offer is GoogleOffer ? offer.basePlanId : null,
      offerId: offerId,
    );
  }

  @override
  Future<RestoreOutcome> restore() async {
    if (!_isActive) {
      return RestoreOutcome.failed(
        errorCode: RestageBillingErrorCodes.restoreFailed,
        message: 'Billing configuration changed before restore started.',
      );
    }
    if (_restoreAttempt != null) {
      return RestoreOutcome.failed(
        errorCode: RestageBillingErrorCodes.restoreFailed,
        message: 'Purchase restoration is already in progress.',
      );
    }
    final attempt = _RestoreAttempt();
    _restoreAttempt = attempt;
    try {
      final launch = await _gateway._initiateCoordinatedRestore();
      if (!_isActive) {
        return RestoreOutcome.failed(
          errorCode: RestageBillingErrorCodes.restoreFailed,
          message: 'Billing configuration changed during restore.',
        );
      }
      if (launch is RestoreOutcomeFailed) return launch;

      // The plugin has no restore-complete event. This bounded result is only
      // the set of products observed for UI feedback; durable processing owns
      // its own asynchronous report/finish lifecycle on the global listener.
      await Future<void>.delayed(_gateway._restoreTimeout);
      if (!_isActive) {
        return RestoreOutcome.failed(
          errorCode: RestageBillingErrorCodes.restoreFailed,
          message: 'Billing configuration changed during restore.',
        );
      }
      final restored = attempt.productIds.toList(growable: false);
      if (restored.isEmpty) return RestoreOutcome.noPurchases();
      return RestoreOutcome.succeeded(restoredProductIds: restored);
    } finally {
      if (identical(_restoreAttempt, attempt)) _restoreAttempt = null;
    }
  }

  Future<_CommittedPurchaseIntent?> _commitIntent({
    required String productId,
    required String? basePlanId,
    required String? offerId,
    required PurchaseAttributionSnapshot? attribution,
  }) async {
    final client = _rpcClientProvider();
    if (client == null) return null;

    final anonymousToken = await _anonymousTokenProvider();
    if (!_isActive ||
        anonymousToken == null ||
        !AnonymousTokenStore.isValidUuid(anonymousToken)) {
      return null;
    }

    final intentId = _purchaseIntentIdGenerator();
    if (!_isCanonicalLowercaseUuidV4(intentId)) return null;

    final request = CreatePurchaseIntentRequest(
      purchaseIntentId: intentId,
      store: _store,
      appAnonymousToken: anonymousToken,
      storeProductId: productId,
      basePlanId: _store == 'playStore' ? basePlanId : null,
      offerId: offerId,
      paywallId: attribution?.paywallId,
      paywallVariantSlug: null,
      paywallPublishedVersion: attribution?.paywallPublishedVersion,
      experimentId: attribution?.experimentId,
      experimentVariantId: attribution?.experimentVariantId,
      experimentEpoch: attribution?.experimentEpoch,
    );
    final response = await client.createPurchaseIntent(request);
    if (!_isActive || response?.purchaseIntentId != intentId) return null;
    return _CommittedPurchaseIntent(
      purchaseIntentId: intentId,
      client: client,
    );
  }

  Future<PurchaseOutcome> _openStore({
    required _PreparedPurchase prepared,
    required SignedNativeOffer? offer,
    required String purchaseIntentId,
    required PurchaseAttributionSnapshot? attribution,
  }) async {
    final productId = prepared.product.id;
    if (!_isActive) return _configurationChanged(productId);
    if (_attemptsByProduct.containsKey(productId)) {
      return PurchaseOutcome.failed(
        productId: productId,
        errorCode: RestageBillingErrorCodes.buyFailed,
        message: 'A purchase for this product is already in progress.',
      );
    }

    final attempt = _PurchaseAttempt(
      productId: productId,
      purchaseIntentId: purchaseIntentId,
      attribution: attribution,
    );
    _attemptsByProduct[productId] = attempt;
    attempt.prepare(prepared.product);
    final failure = await _gateway._launchCoordinatedPurchase(
      prepared: prepared,
      offer: offer,
      purchaseIntentId: purchaseIntentId,
      isCurrentEpoch: () => _isActive,
    );
    if (!_isActive) {
      _removeAttempt(attempt);
      return _configurationChanged(productId);
    }
    if (failure != null) {
      _removeAttempt(attempt);
      return failure;
    }
    return attempt.completer.future;
  }

  void _handlePurchaseBatch(List<PurchaseDetails> purchases) {
    if (!_isActive) return;
    for (final purchase in purchases) {
      final attempt = _attemptsByProduct[purchase.productID];
      switch (purchase.status) {
        case PurchaseStatus.pending:
          if (attempt != null &&
              _matchesAttempt(purchase, attempt) &&
              !attempt.completer.isCompleted) {
            _completeAttempt(
              attempt,
              PurchaseOutcome.pending(
                productId: purchase.productID,
                reason: PendingReason.paymentPending,
              ),
              remove: false,
            );
          }
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          if (purchase.status == PurchaseStatus.restored) {
            _restoreAttempt?.productIds.add(purchase.productID);
          }
          final evidence = _normalizePurchase(purchase);
          if (evidence != null) unawaited(_enqueueEvidence(evidence));
        case PurchaseStatus.canceled:
          if (attempt != null && _matchesAttempt(purchase, attempt)) {
            if (!attempt.completer.isCompleted) {
              _completeAttempt(
                attempt,
                PurchaseOutcome.cancelled(productId: purchase.productID),
              );
            } else {
              _attemptsByProduct.remove(purchase.productID);
            }
          }
        case PurchaseStatus.error:
          if (attempt != null && _matchesAttempt(purchase, attempt)) {
            if (!attempt.completer.isCompleted) {
              _completeAttempt(
                attempt,
                PurchaseOutcome.failed(
                  productId: purchase.productID,
                  errorCode:
                      purchase.error?.code ?? RestageBillingErrorCodes.unknown,
                  message: 'The store reported a purchase error.',
                ),
              );
            } else {
              _attemptsByProduct.remove(purchase.productID);
            }
          }
      }
    }
  }

  void _completeAttempt(
    _PurchaseAttempt attempt,
    PurchaseOutcome outcome, {
    bool remove = true,
  }) {
    if (!_isActive || attempt.completer.isCompleted) return;
    if (remove && identical(_attemptsByProduct[attempt.productId], attempt)) {
      _attemptsByProduct.remove(attempt.productId);
    }
    attempt.completer.complete(outcome);
  }

  void _removeAttempt(_PurchaseAttempt attempt) {
    if (identical(_attemptsByProduct[attempt.productId], attempt)) {
      _attemptsByProduct.remove(attempt.productId);
    }
  }

  void _handlePurchaseStreamError(Object _) {
    if (!_isActive) return;
    debugPrint('[restage] purchase updates became unavailable');
    final attempts = _attemptsByProduct.values.toList(growable: false);
    _attemptsByProduct.clear();
    for (final attempt in attempts) {
      if (!attempt.completer.isCompleted) {
        attempt.completer.complete(
          PurchaseOutcome.failed(
            productId: attempt.productId,
            errorCode: RestageBillingErrorCodes.unknown,
            message: 'Purchase updates became unavailable.',
          ),
        );
      }
    }
  }

  StoreTransactionEvidence? _normalizePurchase(PurchaseDetails purchase) {
    if (!_knownSubscriptionProductIds.contains(purchase.productID) ||
        (purchase.status != PurchaseStatus.purchased &&
            purchase.status != PurchaseStatus.restored)) {
      return null;
    }
    final transactionId = purchase.purchaseID;
    final verificationData = purchase.verificationData.serverVerificationData;
    if (transactionId == null ||
        transactionId.isEmpty ||
        purchase.productID.isEmpty ||
        verificationData.isEmpty) {
      return null;
    }

    if (purchase is GooglePlayPurchaseDetails) {
      final wrapper = purchase.billingClientPurchase;
      return StoreTransactionEvidence(
        evidenceKey: googleEvidenceKey(wrapper.orderId),
        store: 'playStore',
        source: StoreTransactionSource.purchaseStream,
        state: _stateFromStatus(purchase.status),
        productId: purchase.productID,
        transactionId: wrapper.orderId,
        verificationData: wrapper.purchaseToken,
        purchaseIntentId: _purchaseIntentHint(purchase),
        originalTransactionId: null,
        needsFinish: !wrapper.isAcknowledged,
        finish: () => _gateway._plugin.completePurchase(purchase),
      );
    }

    final purchaseIntentId = _purchaseIntentHint(purchase);
    String? originalTransactionId;
    if (purchase is AppStorePurchaseDetails) {
      originalTransactionId = purchase
          .skPaymentTransaction.originalTransaction?.transactionIdentifier;
    }
    return StoreTransactionEvidence(
      evidenceKey: appleEvidenceKey(transactionId),
      store: 'appStore',
      source: StoreTransactionSource.purchaseStream,
      state: _stateFromStatus(purchase.status),
      productId: purchase.productID,
      transactionId: transactionId,
      verificationData: verificationData,
      purchaseIntentId: purchaseIntentId,
      originalTransactionId: originalTransactionId,
      needsFinish: purchase.pendingCompletePurchase,
      finish: () => _gateway._plugin.completePurchase(purchase),
    );
  }

  String? _purchaseIntentHint(PurchaseDetails purchase) {
    if (purchase is GooglePlayPurchaseDetails) {
      return purchase.billingClientPurchase.obfuscatedAccountId;
    }
    if (purchase is SK2PurchaseDetails) return purchase.appAccountToken;
    if (purchase is AppStorePurchaseDetails) {
      return purchase.skPaymentTransaction.payment.applicationUsername;
    }
    return null;
  }

  bool _matchesAttempt(PurchaseDetails purchase, _PurchaseAttempt attempt) =>
      _purchaseIntentHint(purchase) == attempt.purchaseIntentId;

  Future<void> _drain(PurchasePlatformAdapter adapter) async {
    if (!_isActive) return;
    List<StoreTransactionEvidence> evidence;
    try {
      evidence = await adapter.drain();
    } on Object {
      if (_isActive) {
        debugPrint('[restage] native purchase recovery was unavailable');
      }
      return;
    }
    if (!_isActive) return;
    for (final item in evidence) {
      if (!_isActive) return;
      unawaited(_enqueueEvidence(item));
    }
  }

  Future<void> _enqueueEvidence(StoreTransactionEvidence evidence) {
    if (evidence.store == 'appStore' &&
        _completedEvidence.contains(evidence.evidenceKey)) {
      return Future<void>.value();
    }
    final existing = _evidenceInFlight[evidence.evidenceKey];
    if (existing != null) return existing;

    late final Future<void> processing;
    processing = Future<void>.sync(() async {
      if (!_isActive) return;
      final context = PurchaseProcessingContext._(
        epoch: _epoch,
        isCurrent: () => _isActive,
      );
      final processor = _evidenceProcessorOverride ?? _processEvidence;
      await processor(evidence, context);
    }).catchError((Object _) {
      if (_isActive) {
        debugPrint('[restage] native purchase processing will be retried');
      }
    }).whenComplete(() {
      if (identical(_evidenceInFlight[evidence.evidenceKey], processing)) {
        _evidenceInFlight.remove(evidence.evidenceKey);
      }
    });
    _evidenceInFlight[evidence.evidenceKey] = processing;
    return processing;
  }

  Future<void> _processEvidence(
    StoreTransactionEvidence evidence,
    PurchaseProcessingContext context,
  ) async {
    if (!context.isCurrent ||
        (evidence.state != StoreTransactionState.purchased &&
            evidence.state != StoreTransactionState.restored) ||
        !_knownSubscriptionProductIds.contains(evidence.productId) ||
        evidence.store != _store ||
        (evidence.store == 'appStore' &&
            _completedEvidence.contains(evidence.evidenceKey))) {
      return;
    }
    if (!await _verifySubscriptionProduct(evidence.productId, context)) return;
    if (!context.isCurrent) return;

    var accepted = evidence.store == 'appStore'
        ? _acceptedEvidence[evidence.evidenceKey]
        : null;
    if (accepted != null && !accepted.matches(evidence)) return;
    if (accepted == null) {
      final response = await _reportWithRetry(evidence, context);
      if (response == null) {
        _completeExactAttemptAsPending(evidence, context);
        return;
      }
      if (!context.isCurrent) return;
      accepted = _AcceptedEvidenceState(evidence, response);
      if (evidence.store == 'appStore') {
        _acceptedEvidence[evidence.evidenceKey] = accepted;
      }
    }

    await _applyAcceptedSideEffects(evidence, accepted, context);
    if (!context.isCurrent) return;

    final finished =
        !evidence.needsFinish || await _finishWithRetry(evidence, context);
    if (!finished || !context.isCurrent) return;
    if (evidence.store == 'appStore') {
      _completedEvidence.add(evidence.evidenceKey);
    }
  }

  Future<bool> _verifySubscriptionProduct(
    String productId,
    PurchaseProcessingContext context,
  ) async {
    if (_verifiedSubscriptionProductIds.contains(productId)) return true;
    if (!context.isCurrent) return false;
    bool verified;
    try {
      final verifier = _subscriptionVerifierOverride;
      verified = verifier != null
          ? await verifier(productId)
          : await _gateway._verifyCoordinatedSubscriptionProduct(
              productId: productId,
              store: _store,
              isCurrentEpoch: () => context.isCurrent,
            );
    } on Object {
      return false;
    }
    if (!verified || !context.isCurrent) return false;
    _verifiedSubscriptionProductIds.add(productId);
    return true;
  }

  Future<ReportTransactionResponse?> _reportWithRetry(
    StoreTransactionEvidence evidence,
    PurchaseProcessingContext context,
  ) async {
    final client = _rpcClientProvider();
    if (client == null) return null;
    final usedReportIds = <String>{};

    for (var attempt = 0; attempt < _maxReportAttempts; attempt += 1) {
      if (!context.isCurrent) return null;
      final reportId = _nextReportId(usedReportIds);
      if (reportId != null) {
        String? anonymousToken;
        try {
          anonymousToken = await _anonymousTokenProvider();
        } on Object {
          anonymousToken = null;
        }
        if (!context.isCurrent) return null;
        final response = await context.report(
          () => client.reportTransaction(
            ReportTransactionRequest(
              reportId: reportId,
              store: evidence.store,
              storeVerificationData: evidence.verificationData,
              storeProductId: evidence.productId,
              storeTransactionId: evidence.transactionId,
              purchaseIntentId: evidence.purchaseIntentId,
              appAnonymousToken: anonymousToken,
            ),
          ),
        );
        if (response != null &&
            _isCompletionSafe(response, reportId, evidence)) {
          return response;
        }
      }
      if (attempt + 1 >= _maxReportAttempts ||
          !await _waitForRetry(attempt, context)) {
        return null;
      }
    }
    return null;
  }

  String? _nextReportId(Set<String> usedReportIds) {
    for (var attempt = 0; attempt < 4; attempt += 1) {
      final candidate = _reportIdGenerator();
      if (_isCanonicalLowercaseUuidV4(candidate) &&
          usedReportIds.add(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  static bool _isCompletionSafe(
    ReportTransactionResponse response,
    String reportId,
    StoreTransactionEvidence evidence,
  ) {
    if (!response.accepted || response.reportId != reportId) return false;
    final disposition = response.purchaseIntentDisposition;
    if (evidence.purchaseIntentId == null) {
      if (disposition != PurchaseIntentDisposition.notProvided) return false;
    } else if (disposition != PurchaseIntentDisposition.associated &&
        disposition != PurchaseIntentDisposition.alreadyAssociated) {
      return false;
    }
    return switch (response.evidence) {
      AppleAcceptedStoreEvidence(:final submittedTransactionId) =>
        evidence.store == 'appStore' &&
            submittedTransactionId == evidence.transactionId,
      GoogleAcceptedStoreEvidence(:final submittedOrderId) =>
        evidence.store == 'playStore' &&
            submittedOrderId == evidence.transactionId,
    };
  }

  Future<void> _applyAcceptedSideEffects(
    StoreTransactionEvidence evidence,
    _AcceptedEvidenceState accepted,
    PurchaseProcessingContext context,
  ) async {
    final response = accepted.response;
    if (!accepted.identityHandled) {
      final disposition = response.purchaseIntentDisposition;
      final token = response.recoveredAppAnonymousToken;
      if ((disposition == PurchaseIntentDisposition.associated ||
              disposition == PurchaseIntentDisposition.alreadyAssociated) &&
          token != null) {
        try {
          await context.repairIdentity(
            () => _authoritativeTokenReplacer(token),
          );
        } on Object {
          if (context.isCurrent) {
            debugPrint('[restage] authoritative anonymous token repair failed');
          }
        }
      }
      if (!context.isCurrent) return;
      accepted.identityHandled = true;
    }

    if (!accepted.entitlementsHandled) {
      try {
        if (!context.emitOutcome(
          () => _entitlementReconciler(response.entitlements),
        )) {
          return;
        }
      } on Object {
        if (context.isCurrent) {
          debugPrint('[restage] accepted entitlement reconciliation failed');
        }
      }
      if (!context.isCurrent) return;
      accepted.entitlementsHandled = true;
    }

    if (!accepted.syncStarted && context.isCurrent) {
      accepted.syncStarted = true;
      unawaited(_runEntitlementSync(context));
    }

    if (!accepted.outcomeHandled) {
      _surfaceAcceptedOutcome(evidence, context);
      if (!context.isCurrent) return;
      accepted.outcomeHandled = true;
    }
  }

  Future<void> _runEntitlementSync(PurchaseProcessingContext context) async {
    try {
      await context.runMutation(_entitlementSync);
    } on Object {
      if (context.isCurrent) {
        debugPrint('[restage] post-purchase entitlement sync failed');
      }
    }
  }

  void _surfaceAcceptedOutcome(
    StoreTransactionEvidence evidence,
    PurchaseProcessingContext context,
  ) {
    final attempt = _attemptsByProduct[evidence.productId];
    if (attempt == null ||
        evidence.purchaseIntentId != attempt.purchaseIntentId) {
      return;
    }
    final priceMicros = attempt.priceMicros;
    final currency = attempt.currency;
    if (priceMicros == null || currency == null) return;
    final outcome = PurchaseOutcomeSucceeded(
      productId: evidence.productId,
      transactionId: evidence.transactionId,
      verificationData: evidence.verificationData,
      priceMicros: priceMicros,
      currency: currency,
    );

    if (!attempt.completer.isCompleted) {
      _completeAttempt(attempt, outcome);
      return;
    }

    _removeAttempt(attempt);
    final attribution = attempt.attribution;
    if (attribution != null) {
      context.emitOutcome(
        () => _delayedSuccessEmitter(outcome, attribution),
      );
    }
  }

  void _completeExactAttemptAsPending(
    StoreTransactionEvidence evidence,
    PurchaseProcessingContext context,
  ) {
    final attempt = _attemptsByProduct[evidence.productId];
    if (attempt == null ||
        attempt.completer.isCompleted ||
        evidence.purchaseIntentId != attempt.purchaseIntentId) {
      return;
    }
    context.emitOutcome(() {
      _completeAttempt(
        attempt,
        PurchaseOutcome.pending(
          productId: evidence.productId,
          reason: PendingReason.unknown,
        ),
        remove: false,
      );
    });
  }

  Future<bool> _finishWithRetry(
    StoreTransactionEvidence evidence,
    PurchaseProcessingContext context,
  ) async {
    for (var attempt = 0; attempt < _maxFinishAttempts; attempt += 1) {
      if (!context.isCurrent) return false;
      try {
        if (await context.finish(evidence).timeout(_finishAttemptTimeout)) {
          return true;
        }
      } on TimeoutException {
        return false;
      } on Object {
        if (!context.isCurrent) return false;
      }
      if (attempt + 1 >= _maxFinishAttempts ||
          !await _waitForRetry(attempt, context)) {
        return false;
      }
    }
    return false;
  }

  Future<bool> _waitForRetry(
    int retryIndex,
    PurchaseProcessingContext context,
  ) async {
    if (!context.isCurrent) return false;
    try {
      await _delay(_retryDelayPolicy(retryIndex));
    } on Object {
      return false;
    }
    return context.isCurrent;
  }

  PurchaseOutcome _intentUnavailable(String productId) =>
      PurchaseOutcome.failed(
        productId: productId,
        errorCode: RestageBillingErrorCodes.buyFailed,
        message: 'The purchase could not be prepared securely.',
      );

  PurchaseOutcome _configurationChanged(String productId) =>
      PurchaseOutcome.failed(
        productId: productId,
        errorCode: RestageBillingErrorCodes.buyFailed,
        message: 'Billing configuration changed during the purchase.',
      );

  static List<PurchasePlatformAdapter> _defaultPlatformAdapters(
    InAppPurchase plugin,
    Set<String> knownSubscriptionProductIds,
  ) {
    if (InAppPurchaseGateway._isApplePlatform) {
      return <PurchasePlatformAdapter>[
        StoreKit2UnfinishedPurchaseAdapter(),
      ];
    }
    if (InAppPurchaseGateway._isAndroidPlatform) {
      return <PurchasePlatformAdapter>[
        GoogleOwnedPurchaseAdapter(
          plugin: plugin,
          knownSubscriptionProductIds: knownSubscriptionProductIds,
        ),
      ];
    }
    return const <PurchasePlatformAdapter>[];
  }

  static StoreTransactionState _stateFromStatus(PurchaseStatus status) {
    return switch (status) {
      PurchaseStatus.pending => StoreTransactionState.pending,
      PurchaseStatus.purchased => StoreTransactionState.purchased,
      PurchaseStatus.restored => StoreTransactionState.restored,
      PurchaseStatus.canceled => StoreTransactionState.cancelled,
      PurchaseStatus.error => StoreTransactionState.failed,
    };
  }

  static bool _isCanonicalLowercaseUuidV4(String value) {
    return value == value.toLowerCase() &&
        AnonymousTokenStore.isValidUuid(value);
  }

  static Duration Function(int retryIndex) _defaultRetryDelayPolicy() {
    final random = Random.secure();
    return (retryIndex) {
      final exponent = min(retryIndex, 4);
      final baseMilliseconds = 50 * (1 << exponent);
      final jitterMilliseconds = random.nextInt(baseMilliseconds + 1);
      return Duration(
        milliseconds: baseMilliseconds + jitterMilliseconds,
      );
    };
  }

  static Future<void> _ignoreAuthoritativeToken(String _) async {}

  static void _ignoreEntitlements(List<EntitlementSummary> _) {}

  static Future<void> _ignoreSync() async {}

  static void _ignoreDelayedSuccess(
    PurchaseOutcomeSucceeded _,
    PurchaseAttributionSnapshot __,
  ) {}
}

/// Epoch guard handed to the transaction processor.
///
/// Report, finish, identity repair, and outcome work must all pass through this
/// guard so a replaced configuration cannot act on a late async result.
final class PurchaseProcessingContext {
  PurchaseProcessingContext._({
    required int epoch,
    required bool Function() isCurrent,
  })  : _epoch = epoch,
        _isCurrent = isCurrent;

  final int _epoch;
  final bool Function() _isCurrent;

  /// Configuration epoch captured for this processing attempt.
  int get epoch => _epoch;

  /// Whether this processing attempt still belongs to the active coordinator.
  bool get isCurrent => _isCurrent();

  /// Runs a report only while current and discards a late response.
  Future<T?> report<T>(Future<T> Function() operation) async {
    if (!isCurrent) return null;
    final result = await operation();
    return isCurrent ? result : null;
  }

  /// Finishes native evidence only while the epoch remains current.
  Future<bool> finish(StoreTransactionEvidence evidence) async {
    if (!isCurrent) return false;
    await evidence.finish();
    return isCurrent;
  }

  /// Applies an identity repair only while the epoch remains current.
  Future<bool> repairIdentity(Future<void> Function() operation) async {
    if (!isCurrent) return false;
    await operation();
    return isCurrent;
  }

  /// Runs an asynchronous local mutation only for the active epoch.
  Future<bool> runMutation(Future<void> Function() operation) async {
    if (!isCurrent) return false;
    await operation();
    return isCurrent;
  }

  /// Emits an outcome only while the epoch remains current.
  bool emitOutcome(void Function() operation) {
    if (!isCurrent) return false;
    operation();
    return true;
  }
}

final class _PurchaseAttempt {
  _PurchaseAttempt({
    required this.productId,
    required this.purchaseIntentId,
    required this.attribution,
  });

  final String productId;
  final String purchaseIntentId;
  final PurchaseAttributionSnapshot? attribution;
  int? priceMicros;
  String? currency;
  final Completer<PurchaseOutcome> completer = Completer<PurchaseOutcome>();

  void prepare(ProductDetails product) {
    priceMicros = (product.rawPrice * 1000000).toInt();
    currency = product.currencyCode;
  }
}

final class _RestoreAttempt {
  final Set<String> productIds = <String>{};
}

final class _AcceptedEvidenceState {
  _AcceptedEvidenceState(
    StoreTransactionEvidence evidence,
    this.response,
  )   : store = evidence.store,
        productId = evidence.productId,
        transactionId = evidence.transactionId,
        purchaseIntentId = evidence.purchaseIntentId;

  final String store;
  final String productId;
  final String transactionId;
  final String? purchaseIntentId;
  final ReportTransactionResponse response;

  bool identityHandled = false;
  bool entitlementsHandled = false;
  bool syncStarted = false;
  bool outcomeHandled = false;

  bool matches(StoreTransactionEvidence evidence) =>
      evidence.store == store &&
      evidence.productId == productId &&
      evidence.transactionId == transactionId &&
      evidence.purchaseIntentId == purchaseIntentId;
}

final class _BoundedMarkerMap<T> {
  _BoundedMarkerMap(int capacity) : _capacity = max(1, capacity);

  final int _capacity;
  final LinkedHashMap<String, T> _values = LinkedHashMap<String, T>();

  T? operator [](String key) {
    final value = _values.remove(key);
    if (value != null) _values[key] = value;
    return value;
  }

  void operator []=(String key, T value) {
    _values.remove(key);
    _values[key] = value;
    while (_values.length > _capacity) {
      _values.remove(_values.keys.first);
    }
  }

  void clear() => _values.clear();
}

final class _BoundedMarkerSet {
  _BoundedMarkerSet(int capacity) : _values = _BoundedMarkerMap<bool>(capacity);

  final _BoundedMarkerMap<bool> _values;

  bool contains(String key) => _values[key] ?? false;

  void add(String key) => _values[key] = true;

  void clear() => _values.clear();
}

final class _CommittedPurchaseIntent {
  const _CommittedPurchaseIntent({
    required this.purchaseIntentId,
    required this.client,
  });

  final String purchaseIntentId;
  final RestageRpcClient client;
}
