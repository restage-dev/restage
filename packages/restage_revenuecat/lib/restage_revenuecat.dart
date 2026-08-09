/// Keep RevenueCat underneath Restage paywalls.
///
/// Exposes [RevenueCatBillingGateway], a Restage `BillingGateway` that
/// delegates Buy / Restore to the host app's existing RevenueCat
/// configuration.
library;

export 'src/revenue_cat_billing_gateway.dart' show RevenueCatBillingGateway;
