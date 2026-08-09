# Changelog

## 0.2.0

- `RevenueCatBillingGateway.purchase` now buys the offer-bearing RevenueCat
  **package** — it resolves the product to its package via `Purchases.getOfferings`
  (current offering first, then any offering) and purchases that package, so
  RevenueCat applies the configured offer / free trial / intro price / base-plan
  at its SDK runtime. A product in no offering falls back to the raw
  store-product purchase (unchanged behavior, no offer to apply).

## 0.1.0

- Initial release: `RevenueCatBillingGateway` — a Restage `BillingGateway` that
  delegates Buy / Restore to the host app's existing RevenueCat configuration.
