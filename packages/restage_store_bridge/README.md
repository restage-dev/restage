# restage_store_bridge

Connect Flutter's `in_app_purchase` catalog and purchases to [Restage](https://restage.dev)
paywalls. Use an app-scoped controller or connect an existing app purchase service.
Your app verifies transactions and delivers entitlements or consumable content.

This package is available from source and is not yet published to pub.dev.

## Connect a delivered Restage paywall

The [example](example) includes an authored paywall, its generated mount, and
copyable app integration. Initialize Restage with your delivery configuration,
then let `InAppPurchaseScope` own one store controller above your app.
`billing` and `reportError` below are your app's existing billing and error handling:

```dart
import 'package:flutter/widgets.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:restage/restage.dart';
import 'package:restage_store_bridge/restage_store_bridge.dart';

import 'store_upgrade.dart';
import 'restage_surfaces.g.dart';

WidgetsFlutterBinding.ensureInitialized();
Restage.configureWithInstalledCatalog(
  apiKey: const String.fromEnvironment('RESTAGE_API_KEY'),
  baseUrl: const String.fromEnvironment('RESTAGE_BASE_URL'),
  surfaces: restageSurfaces,
);

runApp(
  InAppPurchaseScope(
    create: () => InAppPurchaseController(
      verifyPurchase: billing.verifyPurchase,
      deliverPurchase: billing.deliverPurchase,
      consumableProductIds: const {'coins'},
      onError: reportError,
    ),
    child: const MyApp(),
  ),
);
```

`MyApp` is your existing root widget. The scope creates the controller once,
refreshes Android purchases at startup and resume, and disposes it when removed.
Keep it above `MaterialApp` and navigation so it stays alive across paywall visits.
The factory runs once per mounted scope; rebuilding does not replace the controller.

Load the catalog once after the scope mounts. The example uses a cached future
with loading and error states:

```dart
final response = await InAppPurchase.instance.queryProductDetails({
  'pro_monthly',
  'pro_annual',
});
if (response.error != null || response.notFoundIDs.isNotEmpty) {
  // Show catalog unavailability and handle the error in your app.
  return;
}

// This selection assumes one returned offer per product ID.
final packages = Map<String, ProductDetails>.unmodifiable({
  'monthly': response.productDetails.singleWhere((p) => p.id == 'pro_monthly'),
  'annual': response.productDetails.singleWhere((p) => p.id == 'pro_annual'),
});

// Replace with accurate localized terms for your configured products.
const billingTerms = {
  'monthly': r'$4.99 each month. Renews until canceled. No free trial.',
  'annual': r'$39.99 each year. Renews until canceled. No free trial.',
};
final displayPackages = [
  for (final entry in packages.entries)
    PaywallPackage(
      identifier: entry.key,
      priceString: entry.value.price,
      billingTerms: billingTerms[entry.key]!,
    ),
];
```

Once the catalog is ready, mount the paywall from a descendant's build method:

```dart
final paywall = StorePaywallSurface(
  packages: displayPackages,
  onEvent: inAppPurchaseEventHandler(
    packages: packages,
    controller: InAppPurchaseScope.of(context),
    onError: reportError,
  ),
);
```

`StorePaywallSurface` is generated from the example's `@Paywall()` widget in
`store_upgrade.dart`; the file name supplies the paywall id. It passes these
typed inputs to the surface, registers the widgets it needs, and uses the
original Flutter widget as its compiled fallback. Build the authored paywall
with Restage codegen, then push and publish it through your Restage workflow.
Your app supplies current store products and handles purchase/restore events.
See the
[authored paywall](example/lib/store_upgrade.dart) and [run instructions](example/README.md).

Use the same unmodifiable map for display and for purchases. Its keys identify offers;
several keys can refer to different native offers with the same product ID. On
Google Play, inspect the returned native offer details to select the intended
base plan and offer. Retain those exact `ProductDetails` objects. A purchase
parameter builder can supply account or offer options:

```dart
final controller = InAppPurchaseController(
  verifyPurchase: billing.verifyPurchase,
  deliverPurchase: billing.deliverPurchase,
  onError: reportError,
  purchaseParamBuilder: billing.purchaseParamFor,
);
```

The builder must retain the exact selected object in `param.productDetails`.
Use this configuration in the scope's `create` callback, or create the controller
in your own app service.

## Display prices and billing terms

When mounting `RestagePaywall` directly by ID, use
`inAppPurchaseOfferingData(identifier: 'pro', packages: packages)` for its
`context`. It preserves package order and returns:

```text
identifier: offering identifier
packages:
  - identifier: package map key
    productIdentifier: native product ID
    priceString: literal ProductDetails.price
    currencyCode: ProductDetails.currencyCode
```

Generated mounts serialize their typed arguments instead, as shown above.
Direct mounts also need generated widget registration and a chosen
`fallbackBuilder`; the generated mount supplies both automatically.
The helper does not add subscription periods, trials or renewal terms. Google
Play's catalog price can describe the first free or introductory phase. Your
app must supply accurate localized trial, billing-period and renewal terms and
render them alongside `priceString`. A catalog price does not establish the
amount paid by a particular user. See the [example](example) for a compiled
widget that displays both fields.

A purchase button sends the displayed package's map key:

```dart
FilledButton(
  onPressed: paywallEvent(
    'in_app_purchase.purchase',
    args: {'packageIdentifier': package.identifier},
  ),
  child: Text(package.priceString),
)

TextButton(
  onPressed: paywallEvent('in_app_purchase.restore'),
  child: const Text('Restore purchases'),
)
```

Unknown, empty or malformed package keys are errors. Unrelated events are ignored.

## Verification and delivery

`verifyPurchase` returns `Future<bool>` for a native `PurchaseDetails` update.
Verify the transaction with your trusted purchase validation service. A `false`
result declines the transaction; it is neither delivered nor finished and is
not automatically retried in this controller.

`deliverPurchase` returns `Future<void>` and must deliver each verified native
transaction id at most once, including across restarts and when the store sends
a purchase again. The controller remembers completed stages in memory only.
The order is verification, delivery, then completion or consumption. If
completion fails, access already delivered stays in place.

Thrown verification, delivery and completion errors reach the required controller
`onError`. Retry current in-memory failures with:

```dart
await controller.retryPendingPurchases();
```

Retries resume the failed stage. Successful delivery is retained, so a finish
retry does not deliver again. After a restart, recovery relies on the store
sending purchases again, Android's owned-purchase refresh, and your app
delivering each transaction only once. There is no persistent retry queue.

List every supported consumable SKU in `consumableProductIds`, including products
that can arrive through recovery. Google consumables are explicitly consumed
after verified delivery. The default controller supports single-product Google
transactions; multi-product tokens and transactions with a missing or
unsupported id produce processing errors before delivery or completion. An existing
app service can handle other transaction shapes through the custom path.

`onPurchaseUpdated` can observe pending, canceled and other native UI states.
It does not grant access. Observer errors are reported separately and cannot
interrupt transaction processing. Store stream errors also reach controller
`onError`. Keep error callbacks reliable; the app owns its error presentation.

Native purchase and restore calls run one at a time, each until it returns. A
`true` purchase result means the store accepted the request. The controller
does not lock the whole checkout; preventing overlapping checkouts in your UI is
up to your app. Restores and recovery can arrive independently of paywall mounts.
Restore requests do not return a complete entitlement snapshot, and consumed
content requires the app's own recovery source.

`InAppPurchaseScope` handles disposal and Android startup/resume recovery. Its
automatic recovery and cleanup errors use the controller's `onError`. Apple
restore remains user-initiated.

If your app service creates the controller directly, it owns disposal:

```dart
await controller.dispose();
```

Disposal stops new purchase requests, cancels the stream listener and waits for already
running work. It cannot cancel a native purchase. Keep the controller alive when
a paywall is dismissed. A manually owned controller also needs Android
`restorePurchases()` calls at startup after subscribing and when the app resumes;
send errors from those calls to your app's error callback.

## Use an existing purchase service

If your app already owns purchase streams and fulfillment, keep the same
Restage setup, catalog and paywall arguments. Replace `onEvent` with this handler
and omit the controller and scope:

```dart
final handler = inAppPurchaseCustomEventHandler(
  packages: packages,
  purchase: billing.purchaseAndVerify,
  restore: billing.restore,
  onPurchase: showPurchaseSuccess,
  onError: reportError,
);
```

`purchase` has type `Future<PurchaseDetails?> Function(ProductDetails)`. A non-null
result must be a new purchase that your app has matched to this checkout,
verified and delivered. It must have `PurchaseStatus.purchased` and the exact
selected product ID. Return null when there is no confirmed new purchase.

Your service finishes or consumes the native transaction, prevents duplicate
checkouts, drops duplicate transactions, and matches each transaction to its
checkout. A matching SKU or a nearby stream update isn't enough. Restore invokes neither `onPurchase`
nor conversion reporting.

Both handler builders return `Future<void> Function(RestageEvent)`. Selection,
purchase, validation and restore errors reach the optional handler `onError`;
without it, the returned future propagates errors. Custom `onPurchase` errors
propagate separately, while confirmed reporting is still observed. Handle observer
failures in your app or observe the returned handler future when invoking it.

## Purchase conversion reports

The default controller and handler don't report purchases automatically. A
native purchase request doesn't return the id of the transaction it will
create, and the shared stream also includes restored, recovered and external
purchases. A matching SKU, timing, verification and first delivery can't show
which paywall a purchase came from.

If your app can reliably match a transaction to its checkout on its own, keep
the original event and report after verified delivery:

```dart
await Restage.measurement.reportPurchase(
  originalEvent,
  packageIdentifier: matchedPackageIdentifier,
  productIdentifier: matchedProductIdentifier,
);
```

Do not report unmatched, restored or recovered updates as new paywall purchases.
The custom handler reports the purchase your app confirmed using the original
event, so it stays linked to that paywall view through a refresh or dismissal.

Reports contain package and product identifiers, with paid amount unknown.
Reporting failure does not change purchase success. Reporting needs a view of a
published paywall that measurement covers, and measurement must be configured;
`Restage.reset()` and the measurement setting still apply. Each event object
reports at most once, so your app must make sure one transaction isn't reported
through two different events.

## Examples and testing

The [default integration](example/lib/main.dart) and
[custom integration](example/lib/custom.dart) share one delivered paywall.
RevenueCat has its own [separate example](../restage_revenuecat/example).
Widget tests exercise hosted delivery with HTTP fixtures and separately check
the compiled Flutter fallback, native offer selection and billing terms. Native
sandbox testing is still required for your store configuration and fulfillment
service.

## License

BSD-3-Clause. See [LICENSE](LICENSE).
