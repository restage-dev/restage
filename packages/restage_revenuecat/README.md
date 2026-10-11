# restage_revenuecat

[![ci](https://github.com/restage-dev/restage/actions/workflows/ci.yml/badge.svg)](https://github.com/restage-dev/restage/actions/workflows/ci.yml) [![license](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](LICENSE)

Use RevenueCat offerings and purchases with [Restage](https://restage.dev) paywalls.
The app keeps its existing RevenueCat configuration and entitlement checks.

This package is available from source and is not yet published to pub.dev.

## Connect a delivered Restage paywall

The [example](example) includes an authored paywall and its generated mount.
Keep your existing RevenueCat configuration, initialize Restage, then pass the
current offering's packages and purchase handler to that mount:

```dart
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:restage/restage.dart';
import 'package:restage_revenuecat/restage_revenuecat.dart';

import 'revenuecat_upgrade.dart';
import 'restage_surfaces.g.dart';

Restage.configureWithInstalledCatalog(
  apiKey: const String.fromEnvironment('RESTAGE_API_KEY'),
  baseUrl: const String.fromEnvironment('RESTAGE_BASE_URL'),
  surfaces: restageSurfaces,
);

final offering = (await Purchases.getOfferings()).current;
if (offering == null) return;

final displayPackages = [
  for (final package in offering.availablePackages)
    PaywallPackage(
      identifier: package.identifier,
      priceString: package.storeProduct.priceString,
    ),
];

final paywall = RevenueCatPaywallSurface(
  packages: displayPackages,
  onEvent: revenueCatEventHandler(
    offering: offering,
    onCustomerInfo: (info) {
      // Apply your existing RevenueCat entitlement checks.
    },
    onError: (error, stackTrace) {
      // Handle purchase and restore errors, including cancellation.
    },
  ),
);
```

`RevenueCatPaywallSurface` is generated from `@Paywall()` in
`revenuecat_upgrade.dart`; the filename supplies the paywall identity. It
serializes typed inputs, installs its widget vocabulary and uses the original
Flutter widget as its compiled fallback with the same event handler.

See the [authored paywall](example/lib/revenuecat_upgrade.dart) and
[run instructions](example/README.md) for the build and delivery setup.

Use the same offering for display and dispatch. The handler purchases only a
package in that offering; an unknown identifier produces an `ArgumentError`.
RevenueCat’s native purchase and restore errors reach `onError`. Without that callback, the
returned future propagates errors.

## Author the buttons

A purchase button sends the identifier of the package it displays:

```dart
FilledButton(
  onPressed: paywallEvent(
    'revenuecat.purchase',
    args: {'packageIdentifier': package.identifier},
  ),
  child: Text(package.priceString),
)

TextButton(
  onPressed: paywallEvent('revenuecat.restore'),
  child: const Text('Restore purchases'),
)
```

`package` is one typed entry from the paywall's `packages` input.

When mounting `RestagePaywall` directly by ID, `revenueCatOfferingData(offering)`
provides its `context` in this shape:

```text
identifier: offering identifier
packages:
  - identifier: package identifier
    productIdentifier: store product identifier
    priceString: localized catalog price
    currencyCode: catalog currency
    subscriptionPeriod: optional billing period
    freeTrial: optional {priceString, period?, cycles?}
    introductoryPrice: optional {priceString, period?, cycles?}
```

Generated mounts serialize their typed inputs instead. Direct mounts also need
generated widget registration and a chosen `fallbackBuilder`; the generated
mount supplies both automatically.

The helper preserves package order. Offer phases come from RevenueCat’s default
subscription option or introductory price; the store determines eligibility during
purchase. Offering metadata and customer information are excluded. Host data stays
on the device.

Change which packages a published paywall displays to introduce a price point or
seasonal offer. Supply an updated RevenueCat offering containing those packages;
the handler needs no package-name mapping in app code.

## Purchase reports

Publish a paywall version to enable its **Purchase conversion** metric. Older
versions published before purchase reporting was supported retain their tap metrics.

After RevenueCat confirms a purchase, the handler reports one conversion against
the originating paywall exposure using `Restage.measurement.reportPurchase` with
the original event when measurement is available. It sends package and product
identifiers, without customer or store transaction identifiers. The event keeps
its original exposure through a refresh or dismissal.

Failed purchases, cancellations and restores produce no conversion report.
Reporting failure does not change the successful purchase or its customer info.
RevenueCat’s Flutter purchase result has no paid amount or currency; the adapter
leaves those values unknown. Localized catalog prices are used for display.

See the [example](example) and [integration guide](https://restage.dev/docs/paywalls/revenuecat).

## License

BSD-3-Clause. See [LICENSE](LICENSE).
