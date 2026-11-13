# Changelog

## 0.2.0

- Added `revenueCatOfferingData` for localized package and offer data. It is
  asynchronous and includes trial and introductory phases only for offers this
  user is eligible for.
- Added `revenueCatEventHandler` for package purchases, restores and exposure-bound conversion reports.
- Purchase handling uses the app’s RevenueCat configuration and preserves its entitlement checks.
