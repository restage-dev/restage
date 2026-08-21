<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/restage-dev/restage/main/brand/restage-wordmark-oscillate-4.0s-dark.svg">
    <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/restage-dev/restage/main/brand/restage-wordmark-oscillate-4.0s-light.svg">
    <img alt="restage" src="https://raw.githubusercontent.com/restage-dev/restage/main/brand/restage-wordmark-oscillate-4.0s-light.webp" width="300">
  </picture>
</p>

<p align="center">
  <a href="https://pub.dev/packages/restage"><img alt="pub package" src="https://img.shields.io/pub/v/restage.svg"></a>
  &nbsp;
  <a href="https://github.com/restage-dev/restage/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/restage-dev/restage/actions/workflows/ci.yml/badge.svg"></a>
  &nbsp;
  <a href="LICENSE"><img alt="License: BSD-3-Clause" src="https://img.shields.io/badge/license-BSD--3--Clause-blue.svg"></a>
</p>

<!--
  Logo: animated overprint wordmark. GitHub renders the light/dark SVG (vector,
  theme-adaptive, animated); pub.dev and other viewers that strip SVG fall back to
  the WebP <img>. A mark+wordmark lockup variant ships alongside in /brand/.
-->

Restage is a server-driven UI toolkit for Flutter. Build any part of your app
with the widgets you already use and ship it over the air. Everything renders as
real Flutter widgets in your app, using your theme.

This package is the runtime SDK. It renders what the build produced as real
Flutter widgets in your widget tree, through
[Remote Flutter Widgets](https://pub.dev/packages/rfw). Nothing it loads over
the air is executable.

One runtime renders every surface: paywalls, onboarding, in-app messages,
surveys, and whole screens.

## Why Restage

- **Your widgets, your theme.** The build compiles the code you wrote, and
  `Theme.of(context)` resolves when the surface renders.
- **Any part of the app.** A whole screen, a paywall, an onboarding flow, or
  one card inside your own `Scaffold`.
- **It ships only content.** An update changes what your app shows. It runs no
  new code.
- **It fails safe.** A surface never reaches a client too old to render it, and
  a failed fetch renders your bundled copy.

## Quick start

Here's a paywall, written as a plain Flutter widget with one annotation:

```dart
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@Paywall(id: 'pro_upgrade')
class ProUpgradePaywall extends StatelessWidget {
  const ProUpgradePaywall({super.key});

  @override
  Widget build(BuildContext context) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Go Pro', style: Theme.of(context).textTheme.headlineMedium),
          FilledButton(
            onPressed: paywallPurchase(slot: 'annual'),
            child: const Text('Start free trial'),
          ),
        ],
      );
}
```

Compile it with [`restage_codegen`](https://pub.dev/packages/restage_codegen):

```sh
dart run build_runner build
```

Render it anywhere in your app. The SDK loads the compiled artifact and draws
it as real Flutter widgets:

```dart
RestagePaywall(
  id: 'pro_upgrade',
  resolver: const AssetVariantResolver(),
  onEvent: (event) {
    if (event case PurchaseSucceeded()) {
      // unlock Pro
    }
  },
)
```

Change the widget, rebuild, and the surface updates. Publish it with
`restage surface publish pro_upgrade` and installed apps pick it up over the
air. The [Quickstart](https://github.com/restage-dev/restage/blob/main/QUICKSTART.md)
walks through all of it, including the `build.yaml` for bundled assets.

## Surfaces

One host widget per surface kind:

- **Screens**: any single surface you write with `@Screen`, such as a welcome
  page, a notice, or a settings card. Mount it with
  `RestageScreen(screen: welcomeScreenRef, ...)` wherever it should appear;
  the build generates `welcomeScreenRef`, and taps come back as typed Dart events.
- **Paywalls**: a `@Paywall` surface with products, purchase, and restore built
  in. Mount it with `RestagePaywall(id: 'pro_upgrade', ...)`.
- **Flows**: a `@FlowGraph` sequence of screens, such as onboarding, a survey,
  or a multi-step message. Mount it with
  `RestageFlowGraph(flow: firstRunFlowRef, ...)`; the build
  generates the descriptor. See [doc/flows.md](doc/flows.md)
  for the full example, host actions, and data minimization, and
  [doc/flow_navigation_and_customization.md](doc/flow_navigation_and_customization.md)
  for back and skip chrome.

### Delivery

Apps that bundle their artifacts use the asset resolvers. To fetch surfaces
from a server, call `Restage.configure(baseUrl: ...)` at startup. That
installs `RestageVariantResolver`, which fetches the active published surface
and falls back to the bundled asset when the fetch fails. Flows take the same
path through `ServerFlowResolver` (pass it as `flowResolver:`). Point `baseUrl`
at your own backend, or at the hosted service.

A surface never reaches a client that is too old to render it. If a fetch
fails, the SDK renders your bundled copy. For flows, `FlowUnavailablePolicy`
is required, so a flow that can't run falls back or hides instead of running
partway.

Two more documents cover the rest of delivery:

- [doc/live_refresh.md](doc/live_refresh.md): opt-in in-place updates for
  surfaces that are already on screen.
- [doc/bundled_native_purchases.md](doc/bundled_native_purchases.md): what the
  bundled StoreKit and Google Play gateway needs and guarantees.

## Build

Apps that depend on `restage` must build with `--no-tree-shake-icons`, because
RFW builds `IconData` from runtime values:

```sh
flutter build ios --no-tree-shake-icons
flutter build appbundle --no-tree-shake-icons
flutter build web --wasm --no-tree-shake-icons
```

## Telemetry and data

Restage includes a conversion-analytics layer. It powers your dashboard, A/B
results, and revenue attribution. It's built to be boring and honest:

- **It's off until you connect a backend.** Analytics activates only when you
  pass `baseUrl` to `Restage.configure(...)`. In local mode (no `baseUrl`) the
  SDK renders everything on device and calls no backend.
- **No endpoint is baked in.** Events go to *your* configured `baseUrl`
  (`<baseUrl>/analytics/events`), authenticated with your public key
  (`rs_pk_...`). Point it at Restage Cloud and your events power your dashboard
  and usage-based billing. Point it at your own backend and they go there.
  There is no hidden Restage host in the SDK.
- **The identity is pseudonymous.** Each install gets a random UUID. It isn't
  derived from any device or advertising identifier, and it resets on
  uninstall or `Restage.reset()`. It's a pseudonymous identifier rather than
  an anonymous one. Treat it as personal data under GDPR and similar laws, as
  we do. **The SDK attaches no user identity of your own.** No call binds
  your account id to an event.
- **What `Restage.reset()` does, and doesn't do.** It rotates the pseudonymous
  id on the device and rotates the session. That id is also the experiment
  assignment key, so the install becomes a new randomized unit: assignment is
  re-drawn on the next surface presentation, and nothing records a link
  between the old unit and the new one. It's a local call: it sends nothing
  and tells the server nothing. It does **not** erase or amend events already
  sent, and it does **not** clear the metering token described below. It isn't
  a deletion request. Treat it as rotating an identifier going forward, not as
  erasing a history.

**What each event contains:** a dedup id; the event name and a UTC timestamp;
which surface it was, with its id, version, and session; the pseudonymous
install id and an app-session id; an app context of `platform`, `locale`, SDK
version, and optional app version or build; conversion dimensions (product,
offer, variant, experiment) where they apply; and the event's own typed fields,
after a scrub that keeps render and host context out of analytics.

**What it never collects:** advertising identifiers (IDFA/GAID), device
fingerprints, location, contacts, or screen content. Beyond the fields listed
above, it collects no personal data you don't explicitly attach. Ordinary
request metadata such as an IP address is visible to whatever backend you point
it at, as with any network call.

**Delivery is fail-safe.** Events are batched, capped, retried safely, and
never throw into your app.

**Turning it off:** run in local mode (omit `baseUrl`) for zero telemetry, or
pass `analyticsEnabled: false` to `Restage.configure(...)` to keep hosted
delivery and entitlement sync and disable analytics. If you use the hosted
service, surface fetches still include the metering token described below.

### The metering token

The hosted service is billed by monthly active users, so the SDK needs a way to
count them. How it works:

- **If you don't use the hosted service, there is no token.** Without a
  `baseUrl` the SDK never creates one. Even with a `baseUrl`, the SDK creates
  the token only the first time it fetches a surface from the server.
- **It's a random UUID.** The device generates it, stores it in
  `shared_preferences`, and loses it when the app is uninstalled. It contains
  nothing about the user or the device, and it isn't connected to the
  analytics install id.
- **It's sent only with surface fetches.** It goes in the body of the request
  to `<baseUrl>/sdk/v1/surface` and nowhere else. It never appears in
  analytics events.
- **It goes only to the server you configured.** There is no baked-in Restage
  endpoint. If your `baseUrl` is your own backend, the token goes there, and
  your server is free to ignore the field.
- **`analyticsEnabled: false` doesn't remove it.** That flag turns off
  analytics. The metering token is how use of the hosted service is counted
  for billing, so it stays as long as you fetch surfaces from the server. Run
  without a `baseUrl` and the SDK sends nothing at all.

If you need to describe it in your own privacy policy: a random per-install
identifier, used only to count active users for billing, reset when the app is
uninstalled. The implementation is in `lib/src/metering/` and it's short.

All of this is BSD-3-Clause and readable: see `lib/src/analytics/` and
`lib/src/billing/anonymous_token.dart`.

### Linking a signed-in user

By default, measurement knows no user. Events and experiment assignment key
off the pseudonymous install id, and nothing ties them to an account.

If your app has signed-in users and you want measurement tied to a user or an
account, you link one explicitly:

```dart
final result = await Restage.measurement.linkSubject(request);
final reset = await Restage.measurement.resetSubject(resetRequest);
final withdrawal = await Restage.measurement.withdrawConsent(withdrawalRequest);
```

Linking is deliberately not a one-liner. A request carries proof from your own
auth system that the user is signed in, the user's consent and region, and a
challenge from the service, so a link can't happen by accident. You get back a
receipt or a failure, and nothing you sent is ever echoed back.
`resetSubject` unlinks; `withdrawConsent` blocks future linking. Until your
app installs a verifier for these proofs, every call here fails closed and
does nothing.

## License

BSD-3-Clause. See [LICENSE](LICENSE).
