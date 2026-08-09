<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="brand/restage-wordmark-oscillate-4.0s-dark.svg">
    <source media="(prefers-color-scheme: light)" srcset="brand/restage-wordmark-oscillate-4.0s-light.svg">
    <img alt="Restage" src="brand/restage-wordmark-oscillate-4.0s-light.webp" width="320">
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
  Hero — animated overprint wordmark. GitHub renders the theme-adaptive animated
  SVG; viewers that strip SVG fall back to the WebP. Paths are relative to the
  repository root.
-->

**Server-driven UI for Flutter.** Build any surface of your app from the widgets you already write and ship changes over the air, no app-store release: what ships is content, not code. Surfaces render as *real* Flutter widgets inside your widget tree, and every change is versioned, reversible, and auditable.

Write a screen in ordinary Flutter. A build step compiles it to a small data file (a [Remote Flutter Widgets](https://pub.dev/packages/rfw) blob) and the SDK renders it, using your live theme.

```dart
@ScreenSource(id: 'welcome')
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});
  static const next = SurfaceEvent<void>('next');

  @override
  Widget build(BuildContext context) => Column(children: [
        Text('Welcome', style: Theme.of(context).textTheme.headlineMedium),
        FilledButton(onPressed: surfaceEvent(next), child: const Text('Get started')),
      ]);
}
```

`dart run build_runner build` turns this into a `.rfw` blob that renders fully offline. Swap `@ScreenSource` for `@PaywallSource` or `@FlowSource`: every surface runs on the same catalog and runtime.

## Why Restage

- **Your real Flutter UI, over the air.** Use your own widgets and design system; what ships is compiled from that exact code. Not a fixed palette, not a JSON dialect, not a webview.
- **Your design system comes with it.** `Theme.of(context)` resolves live at render time. A delivered surface follows your app into dark mode or a rebrand, with no recompile.
- **No code over the air.** An update changes the screens your app shows. It does *not* run new code, so an update can't do anything your released app couldn't already do. That's what makes OTA UI workable where the app stores' rules on shipping interpreted code are the constraint — though what your own app needs to satisfy remains your call.
- **Fails safe, not wrong.** The build step stops with an error instead of guessing. A surface can't reach a client too old to render it, and a failed fetch falls back to your bundled copy.
- **One runtime, any surface.** Paywalls, onboarding, messages, surveys, a single card, or a whole screen: anything you author runs on the same runtime. Drop one into your own `Scaffold` and only that region is server-driven.
- **No lock-in.** A surface is just a `.rfw` file. Serve it from your own backend or CDN. The SDK runs fully offline, no hosted service required.

## Built for controlled delivery

Ship UI over the air: versioned, reversible, auditable.

- The SDK ships the safety half: immutable surface versions, and clients that fail closed to a safe one.
- The delivery service builds the control on top: roll back, freeze, or kill any version, with an exportable audit trail of what changed, when, and by whom.

It's the change control a regulated or enterprise team needs. The hosted service is coming soon.

## Get started

Copy a starter. The [`apps/examples`](apps/examples) README has four minimal, copy-me surfaces: a paywall, an onboarding flow, a one-screen message, and a custom widget. Retitle it, restyle it, ship it.

Prefer building from scratch? The [Quickstart](QUICKSTART.md) writes one step by step.

## What you get

- **A 115-widget catalog** across `restage_core`, `restage_material`, and `restage_cupertino`. Extend it with your own widgets via `@RestageWidget`.
- **Monetization** for commerce surfaces: a pluggable billing gateway, purchase and restore, promotional offers, and an entitlement stream. Receipt validation and revenue attribution run on a backend: yours, or the hosted one when it ships.
- **A2UI (early):** the same source emits a genui A2UI catalog, so AI-generated UI builds from your real widgets.

## Install

```yaml
dependencies:
  restage: ^1.0.0
  restage_material: ^1.0.0

dev_dependencies:
  restage_codegen: ^1.0.0
  build_runner: ">=2.4.0 <3.0.0"
```

The `restage` CLI is optional: `dart pub global activate restage_cli`.

> **Note:** when you build a release that ships a Restage surface, pass `--no-tree-shake-icons`. The blob builds icons from runtime values, which the release tree-shaker can't see. A debug `flutter run` doesn't need it.

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

Open source where it runs in your app. Fair-source where it builds your blobs.

- **BSD-3-Clause:** the SDK, the catalog libraries, the schema, the CLI, the MCP server, the A2UI check, and the examples. The same license Flutter uses.
- **FSL-1.1-ALv2:** the build-time toolchain (`restage_codegen`, `rfw_catalog_compiler`). Source-available, free for all use including inside your own company, and it converts to Apache-2.0 two years after each release.

The hosted platform is proprietary. Every package carries its own `LICENSE`.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). The easiest place to start is the widget catalog: adding a widget is a curation entry plus generated registration.

## What's next

- [Quickstart](QUICKSTART.md): build your first surface.
- [`apps/examples`](apps/examples): copy a starter.
