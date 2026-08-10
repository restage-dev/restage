# Changelog

## Unreleased — coordinated breaking release

**Breaking.** `transactionId` is now nullable (`String?`) on `BillingGateway`'s
purchase result and on `PurchasePlatformAdapter`. Some store purchases have no
transaction identity — a Google Play promotional-code purchase has no order ID —
and the field is now absent in those cases rather than carrying an invented
value.

If you read `transactionId` off a purchase result, handle null. If you
*implement* `BillingGateway` and pass a non-null value, no change is required:
the parameter widened, so existing calls still type-check.

`RestageConversionEvent.transactionId` was already nullable and is unchanged.

Other changes:

- Add `package:restage/a2ui.dart` and `package:restage/rfw.dart` convenience
  entrypoints for target-specific customer catalog configuration.
- Add the Widgetbook configuration entrypoint and typed per-widget/per-input
  emit-target routing annotations.
- Remove the closed event-name export. Customer callback constructor properties
  now use their exact Dart names as event identities.
- Purchase results carry the store-issued transaction identifier where one
  exists: the StoreKit transaction ID on Apple, the Google Play order ID on
  Android. For an external-provider gateway it is the per-transaction id that
  provider surfaces.
- Native purchases carry a durable purchase intent, so a purchase keeps its
  association with the surface that initiated it even if the app dies between
  the store call and the receipt arriving.
- Experiment attribution is surface-general: onboarding, message and survey
  surfaces attribute an experiment the same way a paywall does. Experiment
  dimensions come only from an authoritative root binding; payload-claimed
  assignments are scrubbed and never trusted.
- Google Play prepaid base plans are not accepted through the bundled gateway.
  Direct gateway calls keep their existing product behavior.

## 1.3.0

- Add opt-in live refresh for mounted surfaces: pass a `liveRefresh` trigger
  set (`SurfaceRefreshTrigger.appResume` / `.updateChannel`) to
  `Restage.configure`, with per-surface `liveRefreshOverrides`. A mounted
  surface re-resolves and swaps in place when newer published content is
  available; a surface with in-progress user state is never swapped
  mid-interaction.
- Add the `SurfaceUpdateChannel` SPI (`SurfaceRef` / `SurfaceUpdate`) for
  custom change-signal sources, and `liveRefreshEdgeUrl` for Restage-hosted
  realtime update signals.
- Add `Restage.reloadSurfaces()` for an explicit host-initiated refresh pass.
- Add general-delivery flow authoring:
  `@FlowSource(delivery: FlowDeliveryMode.general)` produces flows with
  untyped `Map` results validated at build time.
- Analytics impressions now report the resolved surface version.

## 1.2.0

- Add a neutral default surface floor.
- Additive runtime support for upcoming surface work; no breaking changes.

## 1.1.1

- Republish without stray build artifacts that were accidentally included in
  the 1.1.0 archive. No code change from 1.1.0.

## 1.1.0

- Add flow branching: decision states and predicate evaluation
  (`flow_predicates`) plus host-supplied initial flow state (`flow_seed`),
  enabling answer-driven onboarding and survey flows.

## 1.0.1

- Declare supported platforms (Android, iOS) explicitly.
- Update the `in_app_purchase` dependencies to their latest stable versions.

## 1.0.0

- Initial scaffold.
