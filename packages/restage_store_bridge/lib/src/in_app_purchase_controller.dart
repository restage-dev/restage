import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';

part 'in_app_purchase_scope.dart';

/// Owns native purchase updates for the lifetime of an app service.
///
/// Construct at app startup. Delivery must be idempotent by verified native
/// transaction identity; retained processing stages last only until disposal.
class InAppPurchaseController {
  /// Subscribes immediately to the store's purchase stream.
  InAppPurchaseController({
    required Future<bool> Function(PurchaseDetails) verifyPurchase,
    required Future<void> Function(PurchaseDetails) deliverPurchase,
    required FutureOr<void> Function(Object, StackTrace) onError,
    Set<String> consumableProductIds = const {},
    FutureOr<void> Function(PurchaseDetails)? onPurchaseUpdated,
    PurchaseParam Function(ProductDetails)? purchaseParamBuilder,
  }) : _verifyPurchase = verifyPurchase,
       _deliverPurchase = deliverPurchase,
       _onError = onError,
       _consumableProductIds = Set.unmodifiable(consumableProductIds),
       _onPurchaseUpdated = onPurchaseUpdated,
       _purchaseParamBuilder = purchaseParamBuilder {
    final store = InAppPurchase.instance;
    _platform = InAppPurchasePlatform.instance;
    if (_platform is InAppPurchaseAndroidPlatform) {
      _androidAddition = store
          .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
    }
    _subscription = _platform.purchaseStream.listen(
      _onPurchases,
      onError: (Object error, StackTrace stack) {
        _track(_report(error, stack));
      },
    );
  }

  final Future<bool> Function(PurchaseDetails) _verifyPurchase;
  final Future<void> Function(PurchaseDetails) _deliverPurchase;
  final FutureOr<void> Function(Object, StackTrace) _onError;
  final Set<String> _consumableProductIds;
  final FutureOr<void> Function(PurchaseDetails)? _onPurchaseUpdated;
  final PurchaseParam Function(ProductDetails)? _purchaseParamBuilder;
  late final InAppPurchasePlatform _platform;
  InAppPurchaseAndroidPlatformAddition? _androidAddition;
  late final StreamSubscription<List<PurchaseDetails>> _subscription;
  final Map<Object, _Transaction> _transactions = {};
  final Map<PurchaseDetails, _Transaction> _terminalTransactions =
      Map.identity();
  final Set<Future<void>> _work = {};
  Future<void> _dispatchTail = Future.value();
  Future<void>? _disposal;
  bool _disposed = false;

  /// Dispatches the exact product and returns the store's acceptance result.
  ///
  /// Dispatch calls are serialized until their native methods return. Purchase
  /// updates and checkout completion are independent of that serialization.
  Future<bool> purchase(ProductDetails product) => _dispatch(() {
    final param =
        _purchaseParamBuilder?.call(product) ??
        PurchaseParam(productDetails: product);
    if (!identical(param.productDetails, product)) {
      throw ArgumentError(
        'Purchase parameters must retain the selected product.',
      );
    }
    if (_consumableProductIds.contains(product.id)) {
      return _platform.buyConsumable(
        purchaseParam: param,
        autoConsume: _platform is! InAppPurchaseAndroidPlatform,
      );
    }
    return _platform.buyNonConsumable(purchaseParam: param);
  });

  /// Requests native restore updates; this is not an entitlement snapshot.
  Future<void> restorePurchases() => _dispatch(_platform.restorePurchases);

  /// Retries unfinished transactions from their last successful stage.
  Future<void> retryPendingPurchases() {
    if (_disposed) return Future.error(StateError('Controller is disposed.'));
    return Future.wait([
      for (final transaction in [
        ..._transactions.values,
        ..._terminalTransactions.values,
      ])
        _process(transaction),
    ]);
  }

  /// Stops new dispatch, cancels the stream and observes already-running work.
  Future<void> dispose() {
    _disposed = true;
    return _disposal ??= _dispose();
  }

  Future<void> _dispose() async {
    await _subscription.cancel();
    await _dispatchTail;
    while (_work.isNotEmpty) {
      await Future.wait(_work.toList());
    }
  }

  Future<T> _dispatch<T>(Future<T> Function() dispatch) {
    if (_disposed) return Future.error(StateError('Controller is disposed.'));
    final result = _dispatchTail.then((_) {
      if (_disposed) throw StateError('Controller is disposed.');
      return dispatch();
    });
    _dispatchTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  void _onPurchases(List<PurchaseDetails> purchases) {
    if (_disposed) return;
    for (final purchase in purchases) {
      if (purchase is GooglePlayPurchaseDetails &&
          purchase.billingClientPurchase.purchaseState ==
              PurchaseStateWrapper.pending &&
          (purchase.status == PurchaseStatus.purchased ||
              purchase.status == PurchaseStatus.restored)) {
        _track(
          _notify(
            GooglePlayPurchaseDetails(
              purchaseID: purchase.purchaseID,
              productID: purchase.productID,
              verificationData: purchase.verificationData,
              transactionDate: purchase.transactionDate,
              billingClientPurchase: purchase.billingClientPurchase,
              status: PurchaseStatus.pending,
            ),
          ),
        );
        continue;
      }
      _track(_notify(purchase));
      if (purchase.status == PurchaseStatus.error && purchase.error != null) {
        _track(_report(purchase.error!, StackTrace.current));
      }
      if (purchase.status == PurchaseStatus.canceled ||
          purchase.status == PurchaseStatus.error) {
        if (purchase is AppStorePurchaseDetails &&
            purchase.pendingCompletePurchase) {
          final transaction = _terminalTransactions.putIfAbsent(
            purchase,
            () => _Transaction(purchase, terminal: true),
          );
          _process(transaction);
        }
        continue;
      }
      if (purchase.status != PurchaseStatus.purchased &&
          purchase.status != PurchaseStatus.restored) {
        continue;
      }
      try {
        final identity = _identity(purchase);
        final transaction = _transactions.putIfAbsent(
          identity,
          () => _Transaction(purchase),
        );
        transaction.purchase = purchase;
        transaction.retainFinish(purchase);
        _process(transaction);
      } on Object catch (error, stack) {
        _track(_report(error, stack));
      }
    }
  }

  Object _identity(PurchaseDetails purchase) {
    if (purchase is GooglePlayPurchaseDetails) {
      final native = purchase.billingClientPurchase;
      if (_platform is! InAppPurchaseAndroidPlatform ||
          native.products.length != 1 ||
          native.products.single != purchase.productID ||
          native.purchaseToken.isEmpty ||
          native.purchaseState != PurchaseStateWrapper.purchased) {
        throw StateError('Unsupported Google Play transaction.');
      }
      final key = (
        'google',
        native.purchaseToken,
        purchase.productID,
        native.orderId.isEmpty ? null : native.orderId,
      );
      if (_transactions.containsKey(key)) return key;
      final unidentified = (
        'google',
        native.purchaseToken,
        purchase.productID,
        null,
      );
      if (native.orderId.isNotEmpty) {
        final prior = _transactions.remove(unidentified);
        if (prior != null) _transactions[key] = prior;
        return key;
      }
      final matches = _transactions.keys
          .whereType<(String, String, String, String?)>()
          .where(
            (entry) =>
                entry.$1 == 'google' &&
                entry.$2 == native.purchaseToken &&
                entry.$3 == purchase.productID,
          )
          .toList();
      if (matches.length > 1) {
        throw StateError('Google Play renewal requires its native order ID.');
      }
      return matches.isEmpty ? key : matches.single;
    }
    final String? nativeId;
    if (purchase is AppStorePurchaseDetails) {
      nativeId = purchase.skPaymentTransaction.transactionIdentifier;
    } else if (purchase is SK2PurchaseDetails) {
      nativeId = purchase.purchaseID;
    } else {
      throw StateError('Unsupported native purchase details.');
    }
    if (nativeId == null || nativeId.isEmpty) {
      throw StateError('A native transaction identifier is required.');
    }
    return ('apple', nativeId);
  }

  Future<void> _process(_Transaction transaction) {
    if (transaction.running case final running?) return running;
    if (transaction.finished || transaction.declined) return Future.value();
    final completion = Completer<void>();
    transaction.running = completion.future;
    _track(completion.future);
    unawaited(
      Future<void>.microtask(() async {
        final purchase = transaction.purchase;
        try {
          if (!transaction.terminal) {
            if (!transaction.verified) {
              if (!await _verifyPurchase(purchase)) {
                transaction.declined = true;
                return;
              }
              transaction.verified = true;
            }
            if (!transaction.delivered) {
              await _deliverPurchase(purchase);
              transaction.delivered = true;
            }
          }
          await _finish(transaction);
          transaction.finished = true;
        } on Object catch (error, stack) {
          if (identical(transaction.running, completion.future)) {
            transaction.running = null;
          }
          await _report(error, stack);
        } finally {
          if (identical(transaction.running, completion.future)) {
            transaction.running = null;
          }
          completion.complete();
        }
      }),
    );
    return completion.future;
  }

  Future<void> _finish(_Transaction transaction) async {
    final purchase = transaction.purchase;
    if (purchase is GooglePlayPurchaseDetails &&
        _consumableProductIds.contains(purchase.productID)) {
      final result = await _androidAddition!.consumePurchase(purchase);
      _requireOk(result);
      transaction.nativeFinished = true;
      return;
    }
    final finish = transaction.finishPurchase;
    if (finish == null) return;
    if (finish is GooglePlayPurchaseDetails) {
      final result = await (_platform as InAppPurchaseAndroidPlatform)
          .completePurchase(finish);
      _requireOk(result);
    } else {
      await _platform.completePurchase(finish);
    }
    transaction.nativeFinished = true;
  }

  void _requireOk(BillingResultWrapper result) {
    if (result.responseCode != BillingResponse.ok) {
      throw StateError(
        'Native store completion failed: ${result.responseCode}.',
      );
    }
  }

  Future<void> _notify(PurchaseDetails purchase) async {
    try {
      await _onPurchaseUpdated?.call(purchase);
    } on Object catch (error, stack) {
      await _report(error, stack);
    }
  }

  Future<void> _report(Object error, StackTrace stack) async {
    try {
      await _onError(error, stack);
    } on Object catch (reportError, reportStack) {
      Zone.current.handleUncaughtError(reportError, reportStack);
    }
  }

  void _track(Future<void> future) {
    _work.add(future);
    unawaited(future.then((_) => _work.remove(future)));
  }
}

class _Transaction {
  _Transaction(this.purchase, {this.terminal = false}) {
    retainFinish(purchase);
  }

  PurchaseDetails purchase;
  final bool terminal;
  PurchaseDetails? finishPurchase;
  Future<void>? running;
  bool verified = false;
  bool delivered = false;
  bool declined = false;
  bool finished = false;
  bool nativeFinished = false;

  void retainFinish(PurchaseDetails update) {
    if (finishPurchase == null &&
        !nativeFinished &&
        update.pendingCompletePurchase) {
      finishPurchase = update;
      finished = false;
    }
  }
}
