# Connect surfaces to the host app

Generated mounts are the default integration. Give them app data and handle their
events; keep services and platform behavior outside the surface's compiled tree.

## Present and dismiss a placement

Use `Restage.presentPlacement` when presentation should participate in placement
resolution. The generated constructor already supplies the implicit placement;
a name is needed only when deliberately overriding it.

This uses the message shipped with this skill:

<!-- skill-check: file lib/show_recap.dart -->
```dart
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
import 'messages/weekly_recap.dart';

Future<void> showRecap(BuildContext context) => Restage.presentPlacement(
  context,
  builder: (context, presentation) => WeeklyRecapSurface(
    name: 'Sam',
    streakDays: 12,
    onEvent: (event) {
      if (event is WeeklyRecapDismissEvent) presentation.close();
    },
  ),
);
```

Wire the other events to the app's actual behavior. The presentation controller
owns the route it opens; use it to close that route. Directly embedding
`WeeklyRecapSurface(...)` in the widget tree is also supported. Use the ordinary
constructor in either case.

Direct `RestagePlacement`, `RestageScreen`, `RestagePaywall` and `RestageFlowGraph`
hosts are lower-level options for integrations that manage references, bindings,
registration and unavailable content themselves. Do not replace generated mounts
with them merely to make a placement explicit.

## Choose a purchase integration

The paywall controls presentation and emits intent. The purchase system determines
what was purchased and what access the user has. A button tap or a successful
purchase dispatch is not proof of a completed transaction.

| Existing purchase system | Integration |
| --- | --- |
| RevenueCat | `restage_revenuecat`: configure RevenueCat in the app and connect its offering with `revenueCatEventHandler` |
| Flutter `in_app_purchase`, with this bridge owning the stream | `restage_store_bridge`: one `InAppPurchaseScope` and `InAppPurchaseController` above navigation, then `inAppPurchaseEventHandler` |
| App already owns its purchase stream/service | App handler, or `inAppPurchaseCustomEventHandler` with verified, delivered and correctly correlated purchase results |

These are optional dependencies. Check their availability and APIs for the app's
resolved package versions before adding them. Neither adapter supplies the app's
complete paywall UI. Classes such as `RevenueCatPaywallSurface` in examples are
generated from the example's authored widget.

For RevenueCat, use the same offering for displayed package data and the handler.
The purchase event is `revenuecat.purchase` with `packageIdentifier` in its args;
restore is `revenuecat.restore`. The adapter exports functions, not a scope widget.
Use `onCustomerInfo` for the app's existing entitlement checks and `onError` for
purchase/restore errors, including cancellation.

These handlers consume standalone paywall events (`RestageEvent` and
`PaywallCustomEvent`). An embedded flow step emits `SurfaceEvent` transitions,
which are a different contract. To reuse the adapter inside a flow, an installed
host action can present a generated standalone paywall and await its result.
Connect that result to the flow only after the purchase service confirms it.

For the store bridge, create the controller before querying products and keep its
scope above navigation so closing a paywall does not stop purchase processing.
Your app supplies verification and idempotent entitlement/content delivery.
Select the intended store product and offer, then use the same immutable product
mapping for display and dispatch. The events are `in_app_purchase.purchase` with
`packageIdentifier`, and `in_app_purchase.restore`.

Pass localized display data through generated mount parameters. The adapters'
`revenueCatOfferingData` and `inAppPurchaseOfferingData` helpers are context-map
alternatives for direct mounts. Store catalog offer data does not establish a
particular user's trial eligibility. Handle loading, missing products, errors,
pending transactions and restore in the host integration.

RevenueCat's successful purchase handler reports the originating exposure when
available. The default native controller handler does not automatically attribute
purchases: dispatch acceptance cannot identify the later transaction. A custom
service may report a verified, delivered purchase correlated to the original
Restage event. Preserve that event; do not manufacture attribution from a later
uncorrelated store update. Restore does not count as a new conversion.

## Refresh and observation

Configure hosted delivery once at startup as shown in
[setup-and-delivery.md](setup-and-delivery.md). Default resolution covers paywalls,
screens and flows. Explicit resolver overrides are for custom resolution and can
bypass the corresponding default placement path.

A new published version can be used on a later mount. Refreshing content already
on screen is opt-in through `liveRefresh`; select supported `SurfaceRefreshTrigger`
values for the app. `Restage.reloadSurfaces()` requests a refresh, optionally with
`surfaceId:`. Compatibility and swap-safety checks still apply; a running flow
must not be assumed to switch graphs mid-session.

Measurement, delivery receipts and live-refresh signals serve different purposes.
Use the installed SDK's `measurementEnabled`, `analyticsEnabled` and
`deliveryReceiptsEnabled` controls deliberately. Do not describe disabling one as
disabling every network request or every other kind of telemetry.
