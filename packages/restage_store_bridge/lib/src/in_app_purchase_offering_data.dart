import 'package:in_app_purchase/in_app_purchase.dart';

/// Converts an ordered package map into local paywall render data.
///
/// Create one immutable [packages] map for this helper and the event handler.
/// Keys identify offers, including offers that share a product ID. Prices are
/// literal store catalog prices and can describe a free or introductory phase.
/// Supply accurate trial, billing-period and renewal terms alongside this data.
Map<String, Object> inAppPurchaseOfferingData({
  required String identifier,
  required Map<String, ProductDetails> packages,
}) => {
  'identifier': identifier,
  'packages': [
    for (final package in packages.entries)
      {
        'identifier': package.key,
        'productIdentifier': package.value.id,
        'priceString': package.value.price,
        'currencyCode': package.value.currencyCode,
      },
  ],
};
