<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="doc/brand/restage-wordmark-oscillate-4.0s-dark.svg">
    <source media="(prefers-color-scheme: light)" srcset="doc/brand/restage-wordmark-oscillate-4.0s-light.svg">
    <img alt="restage" src="doc/brand/restage-wordmark-oscillate-4.0s-light.webp" width="300">
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
  the WebP <img>. A mark+wordmark lockup variant ships alongside in doc/brand/.
-->

The Restage runtime SDK — it renders server-driven surfaces as real Flutter
widgets in your own widget tree, via [Remote Flutter Widgets (RFW)](https://pub.dev/packages/rfw). One
runtime drives every surface: paywalls, onboarding, in-app messages, surveys, and
whole screens. The runtime is declarative-only — no JavaScript, bytecode, scripts,
or executable code is loaded from a surface artifact.

## Status

The SDK supports both bundled-asset and Restage-hosted delivery:

- Single surfaces (a paywall, an in-app message) load `.rfw` assets through
  `AssetVariantResolver` from `assets/paywalls/<id>.rfw`.
- Flows — onboarding, surveys, any multi-screen surface — load generated flow
  JSON and screen `.rfw` assets through `AssetFlowResolver` (e.g.
  `assets/onboarding/...`).
- Restage-hosted paywall delivery: `Restage.configure(baseUrl: …)` installs
  `RestageVariantResolver`, which fetches the active published paywall and
  falls back to a bundled asset when the hosted fetch is unavailable. Hosted
  flow delivery is provided by `ServerFlowResolver` (pass it as `flowResolver:`);
  `configure` otherwise defaults flows to `AssetFlowResolver`.

Apps that bundle all their artifacts can keep using the asset resolvers
directly.

## Paywall Quick Start

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

## Onboarding Quick Start

`restage_codegen` generates the `OnboardingFlowRef<R>` and, when the flow uses
host actions, a generated-style `FlowActionRegistry`. The shape below shows the
public API that generated code and app code use together.

```dart
import 'package:flutter/widgets.dart';
import 'package:restage/restage.dart';

final class FirstRunResult {
  const FirstRunResult({required this.completed});

  final bool completed;
}

abstract final class FirstRunFlowDescriptor {
  static final OnboardingFlowRef<FirstRunResult> ref =
      OnboardingFlowRef<FirstRunResult>(
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

`FlowUnavailablePolicy` is required. Missing assets, incompatible versions,
unsupported document features, action-contract mismatches, and build-time render
failures use the fallback or hide policy instead of partially running the flow.
Generated result decoders should reject missing, extra, or mistyped result
fields so bad terminal results fail closed before `onComplete` runs.

## Flow navigation & customization

The back/skip chrome around a flow is customizable on a ladder — Theme (visual
tokens), Slots (your affordance widget), Layout (your whole layout via
`chromeBuilder` / `persistentChromeBuilder`), or DIY (own a
`RestageFlowController` and render with `RestageScreenView`). Back navigation
follows screen history (skipping decision/action states, never re-firing an
action), with a configurable `systemBack` policy when in-flow back is exhausted.

See [`doc/flow_navigation_and_customization.md`](doc/flow_navigation_and_customization.md)
for the full ladder, the two onboarding→paywall navigation patterns, the
`RestageScreenView` vs `RestageFlowView(transition:)` boundary, and the
compliance boundary.

## Host Actions

Host actions are typed, app-owned capability boundaries. A flow can select
among action capabilities the installed app already shipped; it cannot define
new executable behavior. Handlers receive generated typed args plus
`FlowActionContext`, and return generated typed results that the runtime encodes
back into the flow.

## Data Minimization

Flow-originated custom events, terminal results, child-flow results, and action
arguments are filtered through explicit declarations before they leave the flow
runtime. Do not put secrets, credentials, private tokens, or unreleased business
logic in flow documents, generated Dart, or bundled RFW assets.

## Telemetry & data

Restage includes a conversion-analytics layer — it's what powers your dashboard,
A/B results, and revenue attribution. It's built to be boring and honest:

- **It's off until you connect a backend.** Analytics activates only when you
  pass `baseUrl` to `Restage.configure(...)`. In local mode (no `baseUrl`) the
  SDK renders everything on-device and makes no calls to any backend.
- **No endpoint is baked in.** Events go to *your* configured `baseUrl`
  (`<baseUrl>/analytics/events`), authenticated with your public key
  (`rs_pk_…`). Point it at Restage Cloud and your events power your dashboard and
  usage-based billing; point it at your own backend and they go there. There is
  no hidden Restage host in the SDK — grep for it.
- **The identity is anonymous.** Each install gets a random UUID that carries no
  personal data and resets on uninstall. The SDK never collects a user
  identity — `userId` is null unless *you* attach your own via the `identity`
  callback.

**What each event contains:** a dedup id, the event name (e.g. a paywall view, a
completed purchase) and a UTC timestamp; which surface it was and its
id/version/session; the anonymous install token and an app-session id; an app
context of `platform`, `locale`, SDK version, and optional app version/build;
conversion dimensions (product/offer/variant/experiment) where they apply; and
the event's own typed fields, after a scrub that keeps render/host context out
of analytics.

**What it never collects:** advertising identifiers (IDFA/GAID), device
fingerprints, location, contacts, screen content, or any PII you don't
explicitly attach.

**Delivery is fail-safe.** Events are batched, capped, retried safely, and never
throw into your app.

**Turning it off:** run in local mode (omit `baseUrl`) for zero telemetry, or
pass `analyticsEnabled: false` to `Restage.configure(...)` to keep hosted
delivery + entitlement sync while disabling analytics.

It's all BSD-3-Clause and readable — see `lib/src/analytics/` and
`lib/src/billing/anonymous_token.dart`.

## Building Artifacts

Add `restage_codegen` as a dev dependency and run build runner to generate
descriptors, flow JSON, and screen `.rfw` assets:

```sh
dart run build_runner build
```

Apps depending on `restage` must build with
`--no-tree-shake-icons` because RFW constructs `IconData` from runtime values:

```sh
flutter build ios --no-tree-shake-icons
flutter build appbundle --no-tree-shake-icons
flutter build web --wasm --no-tree-shake-icons
```

## License

BSD-3-Clause - see `LICENSE`.
