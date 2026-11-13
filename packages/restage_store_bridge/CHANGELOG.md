## 0.1.0

- Add native store offering data and paywall event helpers. Offering data
  includes the renewal price, billing period, and trial and introductory
  phases this user is eligible for.
- Add an app-scoped purchase controller with verification, idempotent delivery,
  completion, consumable handling and retries for unfinished stages.
- Add an optional app-level `InAppPurchaseScope` for automatic controller disposal
  and Android purchase recovery.
- Add a custom handler for app-confirmed purchases and purchase conversion reports.
- Include native store and custom service examples using generated paywall
  mounts, compiled fallback and explicit billing terms.
