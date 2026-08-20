# restage_revenuecat

[![ci](https://github.com/restage-dev/restage/actions/workflows/ci.yml/badge.svg)](https://github.com/restage-dev/restage/actions/workflows/ci.yml) [![license](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](LICENSE)

This adapter is available from the Restage repository and is not yet published
to pub.dev.

Keep **RevenueCat** underneath your **Restage** paywalls.

`restage_revenuecat` is a [`BillingGateway`](https://pub.dev/documentation/restage/latest/restage/BillingGateway-class.html)
implementation that delegates a Restage paywall's Buy / Restore taps to the host
app's existing RevenueCat configuration. Restage renders the surface and owns its
own analytics; RevenueCat stays the subscription substrate. You adopt Restage's
renderer without ripping RevenueCat out first, and migrate the substrate
whenever you want to.

## How it works

A Restage paywall fires a purchase event; the SDK routes it through the injected
`BillingGateway`. This package's gateway forwards that call to RevenueCat:

- `purchase(productId)` → resolves the product to its offer-bearing RevenueCat
  **package** (via `Purchases.getOfferings`) and purchases it
  (`Purchases.purchase(PurchaseParams.package(...))`)
- `restore()` → `Purchases.restorePurchases`

Buying the **package** rather than the raw store product lets RevenueCat apply
the package's configured **offer / free trial / intro price / Google
base-plan**. RevenueCat resolves the concrete offer at its own SDK
runtime, always reflecting your current RevenueCat offering config. The package
is matched by store product id, searching your current offering first, then any
offering. If the product isn't in any offering (so there's no RevenueCat offer
to apply), the gateway falls back to purchasing the raw store product.

RevenueCat performs the actual StoreKit / Google Play purchase and keeps its own
receipt. Restage leaves RevenueCat's state and StoreKit alone, and
optimistically grants the entitlement locally so the UI unlocks immediately.

Because RevenueCat keeps the raw receipt, the gateway returns a **receipt-less**
success: the transaction id is carried for attribution, but there is no receipt
on the wire. A receipt-less success is an attribution hint, never a "verified"
signal. (See `BillingGateway` and `PurchaseOutcomeSucceeded.verificationData`.)

## Usage

Configure RevenueCat as you already do, then hand Restage the adapter gateway:

```dart
import 'package:restage/restage.dart';
import 'package:restage_revenuecat/restage_revenuecat.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Your existing RevenueCat setup is unchanged.
  await Purchases.configure(PurchasesConfiguration('your_revenuecat_api_key'));

  Restage.configure(
    apiKey: 'rs_pk_…',
    billingGateway: RevenueCatBillingGateway(),
    products: const [
      RestageProduct(id: 'pro_monthly', slot: 'primary', entitlement: 'pro'),
      // …or import them from Restage once you connect a store (hosted access is in private beta).
    ],
  );

  runApp(const MyApp());
}
```

Keep **all** of your existing RevenueCat entitlement-gating code
(`Purchases.getCustomerInfo()`, etc.). This package only renders the paywall and
routes Buy / Restore into RevenueCat.

## Scope (v1)

This adapter targets the common case: **subscription** products bought from a
paywall.

- A product mapped onto a package in one of your RevenueCat offerings is bought
  as that package (offer/trial/base-plan applied) on both platforms.
- The raw store-product **fallback** (a product in no offering) resolves through
  `Purchases.getProducts`, which on Android defaults to the subscription
  category, so a non-subscription Android product with no package resolves as
  not found. iOS is unaffected.
- A plan change (upgrade / downgrade between products) is not yet wired on this
  path; the purchase is treated as a new purchase.
- `restore()` re-grants the store's **active subscriptions**. Non-subscription
  / lifetime / non-renewing entitlements are not included (this never
  over-grants expired purchases). Such purchases are tracked by RevenueCat's
  `CustomerInfo` and remain gated by your existing RevenueCat code.

## Identifiers

`PurchaseOutcomeSucceeded.transactionId` carries RevenueCat's
`StoreTransaction.transactionIdentifier`: the StoreKit per-transaction id on
iOS, the Google order id on Android. It can be empty for a purchase RevenueCat
does not surface an id for (e.g. some pending states); the adapter treats an
empty id as "no attribution id available".

## License

BSD-3-Clause. See [LICENSE](LICENSE).
