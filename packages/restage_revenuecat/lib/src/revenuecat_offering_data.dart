import 'package:purchases_flutter/purchases_flutter.dart';

/// Converts [offering] into local render data for a paywall's `context`.
///
/// `packages` preserves the offering's order. Each entry contains `identifier`,
/// `productIdentifier`, `priceString`, and `currencyCode`, with optional
/// `subscriptionPeriod`, `freeTrial` and `introductoryPrice` fields.
/// Offer phases contain `priceString`, `period` and `cycles` when available.
///
/// `freeTrial` and `introductoryPrice` appear only for offers this user can
/// redeem. On Google Play they come from the package's default option: Play
/// omits offers the user is ineligible for under Play-determined eligibility,
/// returns developer-determined offers to every user, and the purchase grants
/// the displayed offer. On the App Store they require
/// [Purchases.checkTrialOrIntroductoryPriceEligibility] to report eligible
/// within 3 seconds.
Future<Map<String, Object>> revenueCatOfferingData(Offering offering) async {
  final packages = offering.availablePackages;
  final eligible = await _eligibleAppStoreProducts(packages);
  return {
    'identifier': offering.identifier,
    'packages': [
      for (final package in packages) _packageData(package, eligible),
    ],
  };
}

Future<Set<String>> _eligibleAppStoreProducts(List<Package> packages) async {
  final ids = {
    for (final package in packages)
      if (package.storeProduct case final product
          when product.defaultOption == null &&
              product.introductoryPrice != null)
        product.identifier,
  };
  if (ids.isEmpty) return const {};
  try {
    final results = await Purchases.checkTrialOrIntroductoryPriceEligibility([
      ...ids,
    ]).timeout(const Duration(seconds: 3));
    return {
      for (final MapEntry(:key, :value) in results.entries)
        if (value.status ==
            IntroEligibilityStatus.introEligibilityStatusEligible)
          key,
    };
  } on Object {
    // Without a definite answer, show the regular price.
    return const {};
  }
}

Map<String, Object> _packageData(Package package, Set<String> eligible) {
  final product = package.storeProduct;
  final option = product.defaultOption;
  final intro = option == null && eligible.contains(product.identifier)
      ? product.introductoryPrice
      : null;
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
