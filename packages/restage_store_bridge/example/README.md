# Native store purchases with Restage

[lib/main.dart](lib/main.dart) shows the app integration: configure Restage, mount
`InAppPurchaseScope`, query native products, then mount `StorePaywallSurface` with
typed packages and `inAppPurchaseEventHandler`. Your app supplies store products
and owns verification and fulfillment.

[lib/store_upgrade.dart](lib/store_upgrade.dart) is the authored Flutter paywall.
`@Paywall()` infers `store_upgrade` from the filename and generates
`StorePaywallSurface`, which serializes
its typed inputs for Restage delivery and uses the original `StorePaywall` as a
compiled Flutter fallback. Both paths display the same prices and billing terms
and dispatch the same purchase and restore events. No separate fallback layout
or widget registration is needed.

## Copy into your app

1. Copy the configuration, scope, catalog query and generated mount from
   `main.dart`. Mount the scope above `MaterialApp` and query products from a
   descendant's startup with a cached future.
2. Replace exactly two app integration functions: `verifyPurchase` must validate
   real store evidence; `deliverPurchase` must deliver idempotently by verified
   transaction identity across restarts. The example functions throw until
   connected and never grant access.
3. Replace `pro_monthly` and `pro_annual` with your native store product IDs and
   supply accurate localized trial, billing-period and renewal terms. If a SKU
   has several native offers, select the intended returned `ProductDetails`
   object. Build the typed display packages from that same immutable native map.
   The paywall displays literal plugin prices; Google Play may return a free or
   introductory price, so your terms must also explain subsequent billing.
4. Copy the authored paywall and generate its mount and publication output. Push
   and publish it to your Restage project:

```sh
dart run build_runner build
restage surface push store_upgrade
restage surface publish store_upgrade
```

The default generator writes publication artifacts under `.restage/build` for
push and publish. They are tooling output and need no Flutter asset declaration.
`Restage.configureWithInstalledCatalog` uses `restageSurfaces` from the generated
`restage_surfaces.g.dart`. With a public API key and base URL, the generated mount
resolves hosted content. If no delivered or cached content is available, it
renders the original compiled Flutter paywall with the same typed inputs and
event handler. Without credentials, this example uses that compiled fallback.

## Run

Use an app registered for App Store or Google Play sandbox purchases. Configure
its bundle/application identifier and products, and connect the two billing
functions before purchasing. From this directory:

```sh
flutter create --platforms=android,ios .
flutter pub get
dart run build_runner build
flutter run \
  --dart-define=RESTAGE_API_KEY=your_public_restage_key \
  --dart-define=RESTAGE_BASE_URL=your_restage_api_url
```

`InAppPurchaseScope` calls its controller factory once per mount, subscribes
before the child queries products, and disposes the controller on unmount. Keep
it above navigation so dismissing a paywall leaves purchase observation active;
use `InAppPurchaseScope.of(context)` in descendants. Rebuilding keeps the same
controller; use a different key to replace it. The scope requests Android
purchase recovery at startup and resume, coalescing overlapping recovery calls.
iOS restore remains an explicit user action. Recovery and disposal failures reach
the controller's `onError` callback.

For failed processing stages, call
`await InAppPurchaseScope.of(context).retryPendingPurchases()` from a descendant
context; successful delivery is retained during finish retries. Apps with
service-owned controllers can manage subscription disposal and Android recovery themselves;
see the [package README](../README.md) for that integration.

## Existing purchase service

[lib/custom.dart](lib/custom.dart) uses the same generated mount and typed
packages with `inAppPurchaseCustomEventHandler`. Replace the default handler with
that call; this path needs no bridge controller or scope.

Your `purchase` callback returns a `PurchaseDetails` only after correlating,
verifying and delivering a new purchase for that invocation. The helper requires
purchased status and the selected product ID. Return null when no new purchase is
confirmed. Your service owns its stream, native completion, deduplication and
checkout correlation. Restore does not report a purchase conversion.

The default path has no automatic purchase attribution. The custom path reports
an app-confirmed result against its original Restage event. SKU and timing cannot
establish correlation; unmatched, restored and recovered updates stay unattributed.
Reports leave the paid amount unknown and reporting failure does not undo a purchase.
See the [package README](../README.md) for lifecycle details and the separate
[RevenueCat example](../../restage_revenuecat/example) for RevenueCat integration.

[test/paywall_test.dart](test/paywall_test.dart) proves both hosted delivery and
compiled fallback after a hosted refusal with exact native offer selection, literal prices,
visible terms and restore. It also checks Android recovery, subscription before
catalog access, one query across rebuilds, scope teardown, delivered version
changes and rollback. The fake store proves wiring; native sandbox checks
qualify your store setup and fulfillment service.
