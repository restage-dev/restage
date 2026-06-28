<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="packages/restage/doc/brand/restage-wordmark-oscillate-4.0s-dark.svg">
    <source media="(prefers-color-scheme: light)" srcset="packages/restage/doc/brand/restage-wordmark-oscillate-4.0s-light.svg">
    <img alt="Restage" src="packages/restage/doc/brand/restage-wordmark-oscillate-4.0s-light.webp" width="320">
  </picture>
</p>

<p align="center">
  <a href="https://pub.dev/packages/restage"><img alt="restage on pub.dev" src="https://img.shields.io/pub/v/restage.svg?label=restage"></a>
  &nbsp;
  <a href="https://github.com/restage-dev/restage/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/restage-dev/restage/actions/workflows/ci.yml/badge.svg"></a>
  &nbsp;
  <a href="LICENSE"><img alt="License: BSD-3-Clause" src="https://img.shields.io/badge/license-BSD--3--Clause-blue.svg"></a>
</p>

<p align="center">
  <a href="https://restage.dev"><b>restage.dev</b></a>
  &nbsp;·&nbsp;
  <a href="https://pub.dev/publishers/restage.dev">Packages on pub.dev</a>
  &nbsp;·&nbsp;
  <a href="QUICKSTART.md">Quickstart</a>
</p>

<!--
  Hero — animated overprint wordmark (the same asset the restage package README
  uses). GitHub renders the theme-adaptive animated SVG; viewers that strip SVG
  fall back to the WebP. Paths are relative to the PUBLIC REPO ROOT, where this
  file lands at extraction (runbook Step 8) — so the hero renders on the GitHub
  landing page, not when previewing this staged copy under docs/launch/front-door/.
-->

**Server-driven UI for Flutter.** Build any surface of your app — onboarding, in-app messages, surveys, paywalls, whole screens — in vanilla Flutter, then ship changes to it over the air without an app-store release. It renders as real Flutter widgets in your own widget tree — not a webview, not a platform view.

The Flutter you author is the artifact that ships. A build step compiles your widget into a small data file (a [Remote Flutter Widgets](https://pub.dev/packages/rfw) blob); the SDK renders it. Your design system and theme come with it: a `Theme.of(context)` read resolves against your live `ThemeData` at render time, so a delivered surface follows your app into dark mode or a rebrand with no recompile. Webview and native-island tools can't do that — they render in a second engine that has no access to your widgets.

```dart
@ScreenSource(id: 'welcome')
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});
  static const next = OnboardingEvent<void>('next');

  @override
  Widget build(BuildContext context) => Column(children: [
        Text('Welcome', style: Theme.of(context).textTheme.headlineMedium),
        FilledButton(onPressed: onboardingEvent(next), child: const Text('Get started')),
      ]);
}
```

`dart run build_runner build` lowers that to a committed `.rfw` blob; the SDK renders it, fully offline. Swap `@ScreenSource` for `@PaywallSource`, `@FlowSource`, and the rest — every surface runs on the same catalog, compiler, and runtime. Full walkthrough in [QUICKSTART.md](QUICKSTART.md).

## Start here

The fastest way in is to copy a starter. The [`apps/examples`](apps/examples) README has a **Starters** section: four minimal, copy-me surfaces — a paywall, an onboarding flow, a one-screen message, and a custom widget — each the smallest file that still compiles and ships. Retitle it, restyle it, ship it. Prefer a step-by-step build? The [Quickstart](QUICKSTART.md) writes one from scratch.

## How it works

- **App Store Review Guideline 4.7 compliant by design** (and Google Play's equivalent). The blob is inert data — references and literal values, no JavaScript, no eval, no bytecode. Your over-the-air updates ship content, not code.
- **It fails safe, not wrong.** The compiler stops at build time with a diagnostic rather than lowering a construct differently. Surfaces are immutably versioned and carry a `sinceVersion` floor, so a delivered surface can never reach a client too old to render it. Delivery is fail-closed with tiered fallback (cached → bundled → error builder), hold-last-good, and one-click rollback.
- **No lock-in.** A surface is just a `.rfw` file — serve it from your own backend or CDN and you have an OTA pipeline you run yourself. Restage's hosted delivery (coming soon) runs that pipeline for you, with the safety net above; the SDK runs without it.

## What you get

- **Every surface, one runtime** — paywalls, onboarding, messages, surveys, permission prompts, full screens. `apps/examples/` has copyable, offline versions of each. Multi-screen flows, back navigation, and interactive state travel in the blob with no host code.
- **A 115-widget catalog** across `restage_core` / `restage_material` / `restage_cupertino`, extensible with your own design-system widgets via `@RestageWidget`.
- **Monetization** for commerce surfaces — a pluggable billing gateway (bundled, RevenueCat, or your own), purchase and restore, promotional offers, and an entitlement stream with grant/revoke events. Receipt validation and revenue attribution run on a backend — yours, or the coming hosted platform.
- **A2UI (early)** — the same source can emit a genui A2UI catalog, so AI-generated UI builds from your real widgets, not a generic palette.

**Coming soon: hosted delivery — and much more will follow.**

## Install

```yaml
dependencies:
  restage: ^1.0.0
  restage_material: ^1.0.0

dev_dependencies:
  restage_codegen: ^1.0.0
  build_runner: ">=2.4.0 <3.0.0"
```

The `restage` CLI is optional (`dart pub global activate restage_cli`). When you build a **release** that ships a Restage surface, pass `--no-tree-shake-icons` — the blob constructs icons from runtime values, which the release icon tree-shaker can't reason about. A debug `flutter run` doesn't need it.

## Packages

| Package | What it is | License |
|---|---|---|
| [`restage`](packages/restage) | The Flutter SDK that renders surfaces on device | BSD-3 |
| [`restage_core`](packages/restage_core) | Cross-platform widget catalog | BSD-3 |
| [`restage_material`](packages/restage_material) | Material widget catalog | BSD-3 |
| [`restage_cupertino`](packages/restage_cupertino) | Cupertino widget catalog | BSD-3 |
| [`restage_cli`](packages/restage_cli) | The `restage` command-line tool | BSD-3 |
| [`restage_mcp`](packages/restage_mcp) | MCP server for agent and tool access | BSD-3 |
| [`restage_a2ui`](packages/restage_a2ui) | App-side capability check for genui A2UI payloads | BSD-3 |
| [`rfw_catalog_schema`](packages/rfw_catalog_schema) | Catalog format and the `@RestageWidget` annotations | BSD-3 |
| [`restage_codegen`](packages/restage_codegen) | Build-time toolchain that lowers your Flutter into render blobs | FSL-1.1-ALv2 |
| [`rfw_catalog_compiler`](packages/rfw_catalog_compiler) | Catalog compiler used by the toolchain | FSL-1.1-ALv2 |
| [`apps/examples`](apps/examples) | Example surfaces to copy | BSD-3 |

## License

Open source where it runs in your app, fair-source where it builds your blobs.

- **BSD-3-Clause** — the SDK, the catalog libraries, the schema, the CLI, the MCP server, the A2UI check, and the examples. (The same license Flutter itself uses.)
- **FSL-1.1-ALv2** — the build-time toolchain (`restage_codegen`, `rfw_catalog_compiler`): source-available, free for all use including inside your own company, and it converts to Apache-2.0 two years after each release.

The hosted backend, dashboard, editor, and delivery are proprietary. Every package carries its own `LICENSE`.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). The easiest place to start is the widget catalog — adding a widget is a curation entry plus generated registration.
