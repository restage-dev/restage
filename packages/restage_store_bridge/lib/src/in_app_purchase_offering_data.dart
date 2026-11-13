import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';

/// Converts an ordered package map into local paywall render data.
///
/// Create one immutable [packages] map for this helper and the event handler.
/// Keys identify offers, including offers that share a product ID. Each entry
/// contains `identifier`, `productIdentifier`, `priceString` (the renewal
/// price) and `currencyCode`, with optional `subscriptionPeriod`, `freeTrial`
/// and `introductoryPrice` fields. Offer phases contain `period`, `cycles` and,
/// except for some App Store free trials, `priceString`.
///
/// `freeTrial` and `introductoryPrice` appear only for offers this user can
/// redeem. On Google Play they come from the selected offer's pricing phases:
/// Play omits offers the user is ineligible for under Play-determined
/// eligibility, returns developer-determined offers to every user, and the
/// purchase grants the displayed offer. On the App Store they come from the
/// product's introductory offer and require StoreKit 2 to report the user
/// eligible within 3 seconds. The in_app_purchase plugin gives App Store offers
/// no localized price, so the helper formats it like the product's price; a
/// paid offer it cannot format is omitted, and a free trial omits `priceString`.
Future<Map<String, Object>> inAppPurchaseOfferingData({
  required String identifier,
  required Map<String, ProductDetails> packages,
}) async {
  final entries = packages.entries.toList(growable: false);
  final eligible = await _eligibleAppStoreProducts([
    for (final entry in entries) entry.value,
  ]);
  return {
    'identifier': identifier,
    'packages': [
      for (final entry in entries)
        _packageData(entry.key, entry.value, eligible),
    ],
  };
}

Future<Set<String>> _eligibleAppStoreProducts(
  List<ProductDetails> products,
) async {
  final ids = {
    for (final product in products)
      if (product is AppStoreProduct2Details && _introOffer(product) != null)
        product.id,
  };
  if (ids.isEmpty) return const {};
  final platform = InAppPurchasePlatform.instance;
  if (platform is! InAppPurchaseStoreKitPlatform) return const {};
  final results = await Future.wait([
    for (final id in ids)
      platform
          .isIntroductoryOfferEligible(id)
          .timeout(_eligibilityTimeout)
          .then((eligible) => eligible ? id : null, onError: (_) => null),
  ]);
  return results.nonNulls.toSet();
}

const _eligibilityTimeout = Duration(seconds: 3);

Map<String, Object> _packageData(
  String key,
  ProductDetails product,
  Set<String> eligible,
) {
  final data = <String, Object>{
    'identifier': key,
    'productIdentifier': product.id,
    'priceString': product.price,
    'currencyCode': product.currencyCode,
  };
  switch (product) {
    case GooglePlayProductDetails(
      :final subscriptionIndex?,
      :final productDetails,
    ):
      final offer = productDetails.subscriptionOfferDetails?[subscriptionIndex];
      if (offer != null) _addPlayOffer(data, offer.pricingPhases);
    case AppStoreProduct2Details(:final sk2Product):
      if (sk2Product.subscription case final subscription?) {
        data['subscriptionPeriod'] = _iso(subscription.subscriptionPeriod);
      }
      if (_introOffer(product) case final offer?
          when eligible.contains(product.id)) {
        _addAppStoreOffer(data, sk2Product, offer);
      }
  }
  return data;
}

void _addPlayOffer(Map<String, Object> data, List<PricingPhaseWrapper> phases) {
  if (phases.isEmpty) return;
  final base = phases.last;
  data['priceString'] = base.formattedPrice;
  data['subscriptionPeriod'] = base.billingPeriod;
  for (final phase in phases.take(phases.length - 1)) {
    final key = phase.priceAmountMicros == 0
        ? 'freeTrial'
        : 'introductoryPrice';
    data.putIfAbsent(
      key,
      () => {
        'priceString': phase.formattedPrice,
        'period': phase.billingPeriod,
        'cycles': phase.billingCycleCount,
      },
    );
  }
}

SK2SubscriptionOffer? _introOffer(AppStoreProduct2Details product) {
  for (final offer
      in product.sk2Product.subscription?.promotionalOffers ??
          const <SK2SubscriptionOffer>[]) {
    if (offer.type == SK2SubscriptionOfferType.introductory) return offer;
  }
  return null;
}

void _addAppStoreOffer(
  Map<String, Object> data,
  SK2Product product,
  SK2SubscriptionOffer offer,
) {
  final free = offer.paymentMode == SK2SubscriptionOfferPaymentMode.freeTrial;
  final price = _formatLike(product.displayPrice, product.price, offer.price);
  if (price == null && !free) return;
  data[free ? 'freeTrial' : 'introductoryPrice'] = {
    'priceString': ?price,
    'period': _iso(offer.period),
    'cycles': offer.periodCount,
  };
}

String _iso(SK2SubscriptionPeriod period) =>
    'P${period.value}${switch (period.unit) {
      SK2SubscriptionPeriodUnit.day => 'D',
      SK2SubscriptionPeriodUnit.week => 'W',
      SK2SubscriptionPeriodUnit.month => 'M',
      SK2SubscriptionPeriodUnit.year => 'Y',
    }}';

final _number = RegExp('\\d(?:[\\d.,\'\\u00a0\\u202f\\u2019 ]*\\d)?');

/// Formats [price] the way [display] formats [displayed], or returns null when
/// the format cannot be read unambiguously.
String? _formatLike(String display, double displayed, double price) {
  final matches = _number.allMatches(display).toList();
  if (matches.length != 1 || displayed <= 0) return null;
  final match = matches.single;
  final run = match[0]!;
  final digits = run.replaceAll(RegExp(r'\D'), '');
  final fraction = [2, 0, 3]
      .where((places) => _scale(displayed, places) == int.tryParse(digits))
      .firstOrNull;
  if (fraction == null) return null;

  var whole = run;
  var decimal = '';
  if (fraction > 0) {
    final separator = run.length - fraction - 1;
    if (separator < 1 || RegExp(r'\d').hasMatch(run[separator])) return null;
    decimal = run[separator];
    whole = run.substring(0, separator);
  }
  final groups = whole.split(RegExp(r'\D'));
  final separators = whole.replaceAll(RegExp(r'\d'), '').split('').toSet();
  final grouped =
      separators.length == 1 &&
      groups.skip(1).every((group) => group.length == 3) &&
      groups.first.length <= 3;
  if (separators.isNotEmpty && !grouped) return null;

  final offer = _scale(price, fraction);
  if (offer == null) return null;
  final units = offer.toString().padLeft(fraction + 1, '0');
  final integer = units.substring(0, units.length - fraction);
  if (integer.length > 3 && separators.isEmpty) return null;
  final buffer = StringBuffer();
  for (var i = 0; i < integer.length; i++) {
    if (i > 0 && (integer.length - i) % 3 == 0) buffer.write(separators.first);
    buffer.write(integer[i]);
  }
  if (fraction > 0) {
    buffer
      ..write(decimal)
      ..write(units.substring(units.length - fraction));
  }
  return display.replaceRange(match.start, match.end, buffer.toString());
}

/// [value] in units of 10^-[places], or null when it does not fit exactly.
int? _scale(double value, int places) {
  var scaled = value;
  for (var i = 0; i < places; i++) {
    scaled *= 10;
  }
  final units = scaled.round();
  return (scaled - units).abs() < 1e-6 ? units : null;
}
