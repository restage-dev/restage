import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_wrappers.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class FakeStore extends InAppPurchasePlatform {
  final updates = StreamController<List<PurchaseDetails>>.broadcast(sync: true);
  final calls = <String>[];
  final params = <PurchaseParam>[];
  final completed = <PurchaseDetails>[];
  Future<bool> Function()? onBuy;
  Future<void> Function(PurchaseDetails)? onComplete;
  Future<void> Function()? onRestore;
  bool? autoConsume;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => updates.stream;

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    calls.add('buy');
    params.add(purchaseParam);
    return await onBuy?.call() ?? true;
  }

  @override
  Future<bool> buyConsumable({
    required PurchaseParam purchaseParam,
    bool autoConsume = true,
  }) {
    this.autoConsume = autoConsume;
    return buyNonConsumable(purchaseParam: purchaseParam);
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    calls.add('complete');
    completed.add(purchase);
    await onComplete?.call(purchase);
  }

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    calls.add('restore');
    await onRestore?.call();
  }
}

class FakeAndroidStore extends FakeStore
    implements InAppPurchaseAndroidPlatform {
  BillingResponse completionCode = BillingResponse.ok;

  @override
  Future<BillingResultWrapper> completePurchase(
    PurchaseDetails purchase,
  ) async {
    calls.add('complete');
    completed.add(purchase);
    await onComplete?.call(purchase);
    return BillingResultWrapper(responseCode: completionCode);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAndroidAddition
    with MockPlatformInterfaceMixin
    implements InAppPurchaseAndroidPlatformAddition {
  final consumed = <PurchaseDetails>[];
  BillingResponse response = BillingResponse.ok;
  Future<void> Function()? onConsume;

  @override
  Future<BillingResultWrapper> consumePurchase(PurchaseDetails purchase) async {
    consumed.add(purchase);
    await onConsume?.call();
    return BillingResultWrapper(responseCode: response);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ProductDetails product([String id = 'pro']) => ProductDetails(
  id: id,
  title: id,
  description: id,
  price: r'$4.99',
  rawPrice: 4.99,
  currencyCode: 'USD',
);

PurchaseVerificationData get verification => PurchaseVerificationData(
  localVerificationData: 'receipt',
  serverVerificationData: 'receipt',
  source: 'store',
);

SK2PurchaseDetails apple({
  String? id = 'transaction',
  String productId = 'pro',
  PurchaseVerificationData? data,
  PurchaseStatus status = PurchaseStatus.purchased,
}) => SK2PurchaseDetails(
  productID: productId,
  purchaseID: id,
  verificationData: data ?? verification,
  transactionDate: null,
  status: status,
);

AppStorePurchaseDetails apple1({
  String? id = 'transaction',
  PurchaseStatus status = PurchaseStatus.purchased,
}) => AppStorePurchaseDetails(
  productID: 'pro',
  purchaseID: null,
  verificationData: verification,
  transactionDate: null,
  skPaymentTransaction: SKPaymentTransactionWrapper(
    payment: const SKPaymentWrapper(productIdentifier: 'pro'),
    transactionState: status == PurchaseStatus.pending
        ? SKPaymentTransactionStateWrapper.purchasing
        : status == PurchaseStatus.canceled || status == PurchaseStatus.error
        ? SKPaymentTransactionStateWrapper.failed
        : SKPaymentTransactionStateWrapper.purchased,
    transactionIdentifier: id,
  ),
  status: status,
);

GooglePlayPurchaseDetails google({
  String token = 'token',
  String order = 'order',
  String productId = 'pro',
  List<String>? products,
  bool acknowledged = false,
  PurchaseStatus status = PurchaseStatus.purchased,
  PurchaseStateWrapper state = PurchaseStateWrapper.purchased,
}) => GooglePlayPurchaseDetails(
  purchaseID: null,
  productID: productId,
  verificationData: verification,
  transactionDate: null,
  billingClientPurchase: PurchaseWrapper(
    orderId: order,
    packageName: 'app',
    purchaseTime: 1,
    purchaseToken: token,
    signature: 'signature',
    products: products ?? [productId],
    isAutoRenewing: false,
    originalJson: '{}',
    isAcknowledged: acknowledged,
    purchaseState: state,
  ),
  status: status,
);

Future<void> flushStore() => Future<void>.delayed(Duration.zero);
