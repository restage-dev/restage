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
  Logo — animated overprint wordmark. GitHub renders the light/dark SVG (vector,
  theme-adaptive, animated); pub.dev and other viewers that strip SVG fall back to
  the WebP <img>. A mark+wordmark lockup variant ships alongside in /brand/.
-->

**Server-driven UI for Flutter.** Restage is the runtime SDK. It renders server-driven surfaces as *real* Flutter widgets in your own widget tree, via [Remote Flutter Widgets (RFW)](https://pub.dev/packages/rfw). One runtime drives every surface: paywalls, onboarding, in-app messages, surveys, and whole screens. Nothing executable is loaded from a surface.

## What makes it different

- **Your real Flutter UI, over the air.** Author a surface in your own widgets and design system; what ships is compiled from that exact code. Not a fixed palette, not a JSON dialect, not a webview.
- **Your design system comes with it.** `Theme.of(context)` resolves live at render time. A surface follows your app into dark mode or a rebrand, with no recompile.
- **No code over the air.** An update changes the screens your app shows. It can't run new code, so an update can't do anything your released app couldn't already do. That keeps updates App Store-safe, and makes OTA UI viable where compliance matters.
- **Fails safe, not wrong.** A surface can't reach a client too old to render it, and a failed fetch falls back to your bundled copy. `FlowUnavailablePolicy` is required, not optional.
- **Built for governed delivery.** This SDK ships the primitives: surface versioning and fail-closed clients. The delivery service builds roll back, freeze, kill, and an exportable audit trail on top; the hosted service is coming soon.
- **One runtime, every surface.** Paywalls, onboarding, messages, surveys, whole screens. One catalog, one runtime.

## Status

The SDK ships the full delivery path today. The hosted Restage service that runs it for you is coming soon. Either way the resolvers are the same:

- **Single surfaces** (a paywall, a message) load `.rfw` assets through `AssetVariantResolver`, from `assets/paywalls/<id>.rfw`.
- **Flows** (onboarding, surveys, any multi-screen surface) load generated flow JSON and screen `.rfw` assets through `AssetFlowResolver`.
- **Hosted delivery:** `Restage.configure(baseUrl: …)` installs `RestageVariantResolver`. It fetches the active published surface and falls back to a bundled asset when the fetch is unavailable. Point `baseUrl` at your own backend now, or at the hosted service when it opens. Flows take the same hosted path through `ServerFlowResolver` (pass it as `flowResolver:`).

Apps that bundle all their artifacts keep using the asset resolvers directly.

## Paywall quick start

```dart
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: RestagePaywall(
            id: 'pro_upgrade',
            resolver: const AssetVariantResolver(),
            onEvent: (event) {
              switch (event) {
                case PaywallViewed():
                  debugPrint('viewed');
                case PurchaseSucceeded():
                  debugPrint('purchased');
                case _:
                  break;
              }
            },
          ),
        ),
      );
}
```

## Onboarding quick start

`restage_codegen` generates the `SurfaceFlowRef<R>` and, when the flow uses host actions, a `FlowActionRegistry`. The example below shows the public API that generated code and your app code use together.

```dart
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

final class FirstRunResult {
  const FirstRunResult({required this.completed});

  final bool completed;
}

abstract final class FirstRunFlowDescriptor {
  static final SurfaceFlowRef<FirstRunResult> ref =
      SurfaceFlowRef<FirstRunResult>(
    id: 'first_run',
    version: 1,
    minClient: 3,
    decodeResult: _decodeResult,
  );

  static FirstRunResult _decodeResult(Map<String, Object?> result) {
    if (result.length != 1 || result['completed'] is! bool) {
      throw const FormatException('Invalid first_run result.');
    }
    return FirstRunResult(completed: result['completed']! as bool);
  }
}

final class NotificationResult {
  const NotificationResult({required this.granted});

  final bool granted;
}

final class FirstRunActions implements FlowActionRegistry {
  FirstRunActions({
    required FlowActionHandler<void, NotificationResult>
        requestNotifications,
  }) : flowActionBindings = {
          'requestNotifications': FlowActionBinding<void, NotificationResult>(
            actionName: 'requestNotifications',
            contractVersion: 1,
            argsSchema: const FlowActionSchema.object({}),
            resultSchema: const FlowActionSchema.object({
              'granted': FlowActionSchemaField(
                required: true,
                schema: FlowActionSchema.bool(),
              ),
            }),
            minClient: 3,
            idempotent: false,
            handler: requestNotifications,
            decodeArgs: (_) {},
            encodeResult: (value) => {'granted': value.granted},
          ),
        };

  @override
  final Map<String, FlowActionBinding<dynamic, dynamic>> flowActionBindings;
}

class OnboardingEntry extends StatelessWidget {
  const OnboardingEntry({super.key});

  @override
  Widget build(BuildContext context) {
    return RestageOnboarding<FirstRunResult>(
      flow: FirstRunFlowDescriptor.ref,
      actions: FirstRunActions(
        requestNotifications: (_, context) async {
          return const NotificationResult(granted: true);
        },
      ),
      unavailable: FlowUnavailablePolicy.fallback(
        builder: (context, error) => Text(error.message),
      ),
      onComplete: (result) {
        Navigator.of(context).pushReplacementNamed('/home');
      },
    );
  }
}
```

`FlowUnavailablePolicy` is required. Missing assets, incompatible versions, unsupported document features, action-contract mismatches, and build-time render failures fall back or hide instead of running the flow partway. Generated result decoders reject missing, extra, or mistyped fields, so a bad terminal result fails closed before `onComplete` runs.

## Flow navigation and customization

The back and skip chrome around a flow is customizable, from theme tokens up to owning the controller yourself. Back navigation follows screen history and never re-fires an action.

See [`doc/flow_navigation_and_customization.md`](doc/flow_navigation_and_customization.md) for the full customization ladder, the onboarding-to-paywall patterns, and the compliance boundary.

## Host actions

Host actions are typed, app-owned capability boundaries. A flow can select among the action capabilities your installed app already shipped. It cannot define new executable behavior. Handlers receive typed args plus `FlowActionContext` and return typed results the runtime encodes back into the flow.

## Data minimization

Flow-originated custom events, terminal results, child-flow results, and action arguments are filtered through explicit declarations before they leave the flow runtime. Do not put secrets, credentials, private tokens, or unreleased business logic in flow documents, generated Dart, or bundled RFW assets.

## Live refresh

Every surface picks up new content the next time it is shown. That is the default, and it covers most changes: publish a new version, and the next onboarding run, paywall view, or survey render uses it.

Live refresh is the opt-in accelerator on top of that. When you turn it on, a surface that is already on screen updates itself in place, with no navigation and no app restart. It works the same for every surface. An onboarding screen re-themes while the user is looking at it, a paywall swaps its offer, an in-app message updates its copy. Same lane, same rules.

Two things are worth stating plainly:

- Content updates on the next view by default. Live refresh live-updates on-screen surfaces when you opt in. It does not claim instant delivery everywhere.
- It never weakens delivery. A live refresh re-resolves through the same fail-safe path your first render uses, skips unchanged content, and applies a change only when the surface is safe to swap: not mid-interaction, not mid-purchase, not enrolled in an experiment. If the realtime lane is unavailable, the surface keeps rendering what it already has. Live refresh accelerates delivery. It is never a bypass.

There are no timers. The realtime lane runs only while a surface is mounted and foregrounded. A resume check covers anything published while the app was backgrounded.

### Turning it on

Opt surfaces in with a set of triggers, resolved most-specific-wins (widget override, then per-surface override, then the app-global set):

```dart
Restage.configure(
  apiKey: 'rs_pk_...',
  baseUrl: 'https://your-backend.example',
  // Wire the Restage-hosted realtime lane.
  liveRefreshEdgeUrl: Uri.parse('https://your-edge.example'),
  // App-global default: every surface takes live edge pushes + the resume check.
  liveRefresh: const {
    SurfaceRefreshTrigger.updateChannel,
    SurfaceRefreshTrigger.appResume,
  },
  // Per-surface override by id (wins over the global set).
  liveRefreshOverrides: const {
    'welcome_flow': {SurfaceRefreshTrigger.appResume},
  },
);

// Per-widget override (wins over everything). An empty set opts this one out.
RestageOnboarding<FirstRunResult>(
  flow: welcomeFlow,
  liveRefresh: const {SurfaceRefreshTrigger.updateChannel},
  unavailable: const FlowUnavailablePolicy.hide(),
);
```

`liveRefreshEdgeUrl` (with `baseUrl` and no custom channel) installs the Restage-hosted realtime lane, so mounted surfaces that opt into `updateChannel` refresh in place as you publish.

When you branch on a trigger, prefer an `if` or a membership test over an exhaustive `switch`. The `SurfaceRefreshTrigger` set is additive, so code that switches over every case would break when a new trigger is added.

### Bring your own channel

To drive live refresh from your own infrastructure (your push provider, your own socket), implement `SurfaceUpdateChannel` and pass it as `updateChannel`. A signal means "this surface may have changed." The SDK re-resolves through its normal delivery path, skips unchanged content, and applies a change through the same swap-safety gate. A channel signals opportunity. It can never force a swap.

```dart
class MyPushChannel implements SurfaceUpdateChannel {
  @override
  Stream<SurfaceUpdate> watch(SurfaceRef surface) {
    // Emit a SurfaceUpdate(surface) whenever your backend says this surface's
    // content changed. The SDK subscribes while the surface is mounted and
    // foregrounded, and cancels on dispose or background.
    return myPushStream
        .where((message) => message.matches(surface))
        .map((_) => SurfaceUpdate(surface));
  }
}

Restage.configure(
  apiKey: 'rs_pk_...',
  baseUrl: 'https://your-backend.example',
  updateChannel: MyPushChannel(),
  liveRefresh: const {SurfaceRefreshTrigger.updateChannel},
);
```

## Telemetry and data

Restage includes a conversion-analytics layer. It powers your dashboard, A/B results, and revenue attribution. It's built to be boring and honest:

- **It's off until you connect a backend.** Analytics activates only when you pass `baseUrl` to `Restage.configure(...)`. In local mode (no `baseUrl`) the SDK renders everything on-device and calls no backend.
- **No endpoint is baked in.** Events go to *your* configured `baseUrl` (`<baseUrl>/analytics/events`), authenticated with your public key (`rs_pk_…`). Point it at Restage Cloud and your events power your dashboard and usage-based billing. Point it at your own backend and they go there. There is no hidden Restage host in the SDK. Grep for it.
- **The identity is pseudonymous.** Each install gets a random UUID that carries no personal data and resets on uninstall or `Restage.reset()`. The SDK never collects a user identity unless *you* attach your own via `Restage.identify(...)`.

**What each event contains:** a dedup id; the event name and a UTC timestamp; which surface it was, with its id, version, and session; the pseudonymous install id and an app-session id; an app context of `platform`, `locale`, SDK version, and optional app version or build; conversion dimensions (product, offer, variant, experiment) where they apply; and the event's own typed fields, after a scrub that keeps render and host context out of analytics.

**What it never collects:** advertising identifiers (IDFA/GAID), device fingerprints, location, contacts, screen content, or any PII you do not explicitly attach.

**Delivery is fail-safe.** Events are batched, capped, retried safely, and never throw into your app.

**Turning it off:** run in local mode (omit `baseUrl`) for zero telemetry, or pass `analyticsEnabled: false` to `Restage.configure(...)` to keep hosted delivery and entitlement sync while disabling analytics.

It's all BSD-3-Clause and readable: see `lib/src/analytics/` and `lib/src/billing/anonymous_token.dart`.

## Build your artifacts

Add `restage_codegen` as a dev dependency and run build_runner to generate descriptors, flow JSON, and screen `.rfw` assets:

```sh
dart run build_runner build
```

Apps that depend on `restage` must build with `--no-tree-shake-icons`, because RFW builds `IconData` from runtime values:

```sh
flutter build ios --no-tree-shake-icons
flutter build appbundle --no-tree-shake-icons
flutter build web --wasm --no-tree-shake-icons
```

## License

BSD-3-Clause. See [LICENSE](LICENSE).

## What's next

- [`apps/examples`](https://github.com/restage-dev/restage/tree/main/apps/examples): copy a starter surface.
