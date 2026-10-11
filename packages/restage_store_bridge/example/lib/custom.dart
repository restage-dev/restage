import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:restage_store_bridge/restage_store_bridge.dart';

import 'store_upgrade.dart';

// Use the same delivered paywall with your existing app purchase service.
// The app owns stream processing, verification, delivery and completion.
StorePaywallSurface customStorePaywall({
  required Map<String, ProductDetails> packages,
  required List<PaywallPackage> paywallPackages,
  required Future<PurchaseDetails?> Function(ProductDetails) purchase,
  required Future<void> Function() restore,
  required FutureOr<void> Function(Object, StackTrace) onError,
}) => StorePaywallSurface(
  packages: paywallPackages,
  onEvent: inAppPurchaseCustomEventHandler(
    packages: packages,
    purchase: purchase,
    restore: restore,
    onError: onError,
  ),
);
