import 'package:purchases_flutter/purchases_flutter.dart';

/// Converts [offering] into local render data for a paywall's `context`.
///
/// `packages` preserves the offering's order. Each entry contains `identifier`,
/// `productIdentifier`, `priceString`, and `currencyCode`, with optional
/// `subscriptionPeriod`, `freeTrial` and `introductoryPrice` fields.
/// Offer phases contain `priceString`, `period` and `cycles` when available.
/// These are catalog offers; the store determines eligibility at purchase time.
Map<String, Object> revenueCatOfferingData(Offering offering) => {
      'identifier': offering.identifier,
      'packages': [
        for (final package in offering.availablePackages) _packageData(package),
      ],
    };

Map<String, Object> _packageData(Package package) {
  final product = package.storeProduct;
  final intro = product.introductoryPrice;
  final option = product.defaultOption;
  return {
    'identifier': package.identifier,
    'productIdentifier': product.identifier,
    'priceString': product.priceString,
    'currencyCode': product.currencyCode,
    if (product.subscriptionPeriod case final period?)
      'subscriptionPeriod': period,
    if (option?.freePhase case final phase?)
      'freeTrial': _phaseData(phase)
    else if (intro != null && intro.price == 0)
      'freeTrial': _introData(intro),
    if (option?.introPhase case final phase?)
      'introductoryPrice': _phaseData(phase)
    else if (intro != null && intro.price != 0)
      'introductoryPrice': _introData(intro),
  };
}

Map<String, Object> _introData(IntroductoryPrice intro) => {
      'priceString': intro.priceString,
      'period': intro.period,
      'cycles': intro.cycles,
    };

Map<String, Object> _phaseData(PricingPhase phase) => {
      'priceString': phase.price.formatted,
      if (phase.billingPeriod case final period?) 'period': period.iso8601,
      if (phase.billingCycleCount case final cycles?) 'cycles': cycles,
    };
