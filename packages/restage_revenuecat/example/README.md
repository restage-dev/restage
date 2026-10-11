# RevenueCat paywall example

This Flutter example fetches the current RevenueCat offering, renders its packages
and localized prices through `RevenueCatPaywallSurface`, and purchases the package
named by a paywall button.

For Flutter's `in_app_purchase` or an existing app purchase service, use the
separate [store bridge example](../../restage_store_bridge/example).

Use an app registered with RevenueCat and configured for store sandbox purchases.
Set the entitlement identifier in `lib/main.dart` to the one your app uses.

From this directory:

```sh
flutter create --platforms=android,ios .
flutter pub get
dart run build_runner build
flutter run \
  --dart-define=REVENUECAT_API_KEY=your_public_revenuecat_key \
  --dart-define=RESTAGE_API_KEY=your_public_restage_key \
  --dart-define=RESTAGE_BASE_URL=your_restage_api_url
```

Use your registered bundle/application identifier and the store setup required by
RevenueCat. The platform projects are generated locally by `flutter create`.

`lib/revenuecat_upgrade.dart` is the authored paywall. Its `@Paywall()` annotation
uses the filename as its ID. Build it, then push and publish it to your Restage
project:

```sh
dart run build_runner build
restage surface push revenuecat_upgrade
restage surface publish revenuecat_upgrade
```

Codegen uses its default hosted delivery configuration; no paywall runtime asset
is packaged with the app. The generated mount serializes typed packages for
delivered content and supplies the original `RevenueCatPaywall` as the compiled
Flutter fallback. Both paths use the same prices and purchase and
restore handler; no manual fallback or widget registration is needed.

Build the display packages and event handler from the same offering:

```dart
final paywallPackages = [
  for (final package in offering.availablePackages)
    PaywallPackage(
      identifier: package.identifier,
      priceString: package.storeProduct.priceString,
    ),
];
final onEvent = revenueCatEventHandler(offering: offering);

final paywall = RevenueCatPaywallSurface(
  packages: paywallPackages,
  onEvent: onEvent,
);
```

Keep the `Restage.configureWithInstalledCatalog(surfaces: restageSurfaces, ...)`
configuration from `lib/main.dart` with your public API key and base URL for
hosted delivery. If resolution fails, the generated mount renders the original
compiled paywall with the same typed inputs and event handler.

To try another price point, add a package to the same offering and publish a version
of `lib/revenuecat_upgrade.dart` selecting its identifier. Keep the app’s data
mapping and event handler unchanged. Fetch the updated offering before reopening
the paywall.
