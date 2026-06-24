import 'package:restage/restage.dart';

/// Stub product + price configuration for the example gallery.
///
/// The gallery's "live prices" tiles render through the remote-render path,
/// which resolves `data.products.<slot>.localizedPrice` from the host app's
/// configured products. A real app passes its own App Store Connect / Play
/// Console product IDs to `Restage.configure(products: ...)` and lets the
/// billing gateway resolve live prices; here we supply a fixed stub set so
/// the examples show realistic prices with no store account.
///
/// The slots (`annual`, `monthly`, `family`, `student`) match those the gallery
/// paywalls bind via `paywallPriceFor(slot:)` and `Package(slot:)`.
const List<RestageProduct> kStubProducts = <RestageProduct>[
  RestageProduct(
    id: 'com.restage.pro.annual',
    slot: 'annual',
    entitlement: 'pro',
  ),
  RestageProduct(
    id: 'com.restage.pro.monthly',
    slot: 'monthly',
    entitlement: 'pro',
  ),
  RestageProduct(
    id: 'com.restage.pro.family',
    slot: 'family',
    entitlement: 'pro',
  ),
  RestageProduct(
    id: 'com.restage.pro.student',
    slot: 'student',
    entitlement: 'pro',
  ),
  // A per-tier x period matrix (three tiers x monthly / annual) for a
  // segmented-tier paywall, so the tier strip AND the period cards both drive
  // the charge.
  RestageProduct(
    id: 'com.restage.tier.basic.monthly',
    slot: 'basic_monthly',
    entitlement: 'pro',
  ),
  RestageProduct(
    id: 'com.restage.tier.basic.annual',
    slot: 'basic_annual',
    entitlement: 'pro',
  ),
  RestageProduct(
    id: 'com.restage.tier.premium.monthly',
    slot: 'premium_monthly',
    entitlement: 'pro',
  ),
  RestageProduct(
    id: 'com.restage.tier.premium.annual',
    slot: 'premium_annual',
    entitlement: 'pro',
  ),
  RestageProduct(
    id: 'com.restage.tier.premiumplus.monthly',
    slot: 'premiumplus_monthly',
    entitlement: 'pro',
  ),
  RestageProduct(
    id: 'com.restage.tier.premiumplus.annual',
    slot: 'premiumplus_annual',
    entitlement: 'pro',
  ),
];

/// Stub resolved prices keyed by product id, mirroring what a billing
/// gateway returns once the store has answered a price query.
const Map<String, PriceInfo> kStubPriceQueries = <String, PriceInfo>{
  'com.restage.pro.annual': PriceInfo(
    localizedPrice: r'$59.99',
    priceMicros: 59990000,
    currency: 'USD',
    title: 'Annual',
    description: 'One year of Pro',
  ),
  'com.restage.pro.monthly': PriceInfo(
    localizedPrice: r'$6.99',
    priceMicros: 6990000,
    currency: 'USD',
    title: 'Monthly',
    description: 'One month of Pro',
  ),
  'com.restage.pro.family': PriceInfo(
    localizedPrice: r'$119.99',
    priceMicros: 119990000,
    currency: 'USD',
    title: 'Family',
    description: 'One year of Pro for up to six people',
  ),
  'com.restage.pro.student': PriceInfo(
    localizedPrice: r'$47.99',
    priceMicros: 47990000,
    currency: 'USD',
    title: 'Student',
    description: 'One year of Pro at the student rate',
  ),
  'com.restage.tier.basic.monthly': PriceInfo(
    localizedPrice: r'$2.99',
    priceMicros: 2990000,
    currency: 'USD',
    title: 'Basic Monthly',
    description: 'Basic, billed monthly',
  ),
  'com.restage.tier.basic.annual': PriceInfo(
    localizedPrice: r'$31.99',
    priceMicros: 31990000,
    currency: 'USD',
    title: 'Basic Annual',
    description: 'Basic, billed annually',
  ),
  'com.restage.tier.premium.monthly': PriceInfo(
    localizedPrice: r'$7.99',
    priceMicros: 7990000,
    currency: 'USD',
    title: 'Premium Monthly',
    description: 'Premium, billed monthly',
  ),
  'com.restage.tier.premium.annual': PriceInfo(
    localizedPrice: r'$83.99',
    priceMicros: 83990000,
    currency: 'USD',
    title: 'Premium Annual',
    description: 'Premium, billed annually',
  ),
  'com.restage.tier.premiumplus.monthly': PriceInfo(
    localizedPrice: r'$15.99',
    priceMicros: 15990000,
    currency: 'USD',
    title: 'Premium+ Monthly',
    description: 'Premium+, billed monthly',
  ),
  'com.restage.tier.premiumplus.annual': PriceInfo(
    localizedPrice: r'$167.99',
    priceMicros: 167990000,
    currency: 'USD',
    title: 'Premium+ Annual',
    description: 'Premium+, billed annually',
  ),
};
