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
  Hero: animated overprint wordmark. GitHub renders the theme-adaptive animated
  SVG; viewers that strip SVG fall back to the WebP. Paths are relative to the
  repository root.
-->

Restage is a server-driven UI toolkit for Flutter. Build any part of your app
with the widgets you already use and ship it over the air. Everything renders as
real Flutter widgets in your app, using your theme.

## Getting started

```dart
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/welcome.restage.g.dart';

@Screen(id: 'welcome', surface: Surface.message)
final class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});
  static const next = SurfaceEvent<void>('next');

  @override
  Widget build(BuildContext context) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Welcome', style: Theme.of(context).textTheme.headlineMedium),
          FilledButton(onPressed: surfaceEvent(next), child: const Text('Get started')),
        ],
      );
}
```

```sh
dart run build_runner build
restage surface publish welcome
```

That's it. The [Quickstart](QUICKSTART.md) takes you from install to a
published surface. [`apps/examples`](apps/examples) has four
starters to copy: a paywall, an onboarding flow, a one-screen message, and a
custom widget.

## Author and publish

Use the annotation that matches what you build:

- `@Screen(surface: Surface.<category>)` publishes one screen.
- `@Paywall` publishes a paywall. A paywall can also be a step in a flow.
- `@FlowGraph(surface: Surface.<category>)` publishes a typed flow of screens.

`@Screen()` with no category is a screen for use inside a flow. The categories
are `onboarding`, `message`, `survey`, `paywall`, and `general`.

`restage surface publish <id>` uploads the artifacts the build generated for
that surface id. You can also name the file instead of the id:

```sh
restage surface publish lib/screens/welcome.dart
```

The CLI resolves the file through the same generated manifest, so it selects
what the build produced. Naming a screen that belongs to a flow publishes that
flow. If a file produced more than one surface, the CLI lists them and asks;
`--all` publishes all of them.

## Why Restage

- **Your widgets, your theme.** You use your own design system. The build
  compiles the code you wrote, and `Theme.of(context)` resolves when the
  surface renders, so a published surface follows your app into dark mode or a
  rebrand.
- **It covers any part of the app.** A whole screen, a paywall, an onboarding
  flow, a survey, or one card inside your own `Scaffold`. One runtime renders
  all of them.
- **It has a catalog of 118 widgets** across `restage_core`,
  `restage_material`, and `restage_cupertino`. Add your own widgets with
  `@RestageWidget`.
- **It ships only content.** An update changes what your app shows. It runs
  no new code, so it cannot do anything your released app could not already
  do.
- **It fails safe.** The build stops with an error when it cannot compile
  something. A surface never reaches a client that is too old to render it. If
  a fetch fails, the SDK renders your bundled copy.
- **It includes monetization.** A pluggable billing gateway, purchase and
  restore, promotional offers, and an entitlement stream. Keep an existing
  RevenueCat purchase path through the optional adapter, or use your own
  backend.
- **It does not lock you in.** Serve the artifacts from your own backend or
  CDN. The SDK runs fully offline.

## Controlled delivery

The SDK ships immutable surface versions. A client that cannot render a version
falls back to a safe one. The hosted service adds the controls: roll back,
freeze, or kill any version, and export an audit trail of what changed, when,
and by whom. The hosted service is in private beta.

## Also

- **A2UI (early):** the same widget constructors emit a genui A2UI catalog, so
  AI-generated UI builds from your real widgets.
- **Widgetbook:** generate stories from the same constructors and browse them
  in a Widgetbook v4 workbench.

## Install

```yaml
dependencies:
  restage: ^1.0.0
  restage_material: ^1.0.0

dev_dependencies:
  restage_codegen: ^1.0.0
  build_runner: ">=2.4.0 <3.0.0"
```

Pass `--no-tree-shake-icons` when you build a release that ships a Restage
surface. The artifact builds icons from runtime values, and the release
tree-shaker cannot see them. A debug `flutter run` does not need the flag.

The `restage` CLI is optional. It is not on pub.dev yet. Clone this repo and
run `melos run cli:install` to compile it onto your PATH.

## Packages

| Package | What it is | License |
|---|---|---|
| [`restage`](packages/restage) | The Flutter SDK that renders surfaces on device | BSD-3 |
| [`restage_core`](packages/restage_core) | Cross-platform widget catalog | BSD-3 |
| [`restage_material`](packages/restage_material) | Material widget catalog | BSD-3 |
| [`restage_cupertino`](packages/restage_cupertino) | Cupertino widget catalog | BSD-3 |
| [`restage_shared`](packages/restage_shared) | Surface format, schemas, and validation shared by the SDK and the toolchain | BSD-3 |
| [`rfw_catalog_schema`](packages/rfw_catalog_schema) | Catalog format and the `@RestageWidget` annotations | BSD-3 |
| [`restage_codegen`](packages/restage_codegen) | Build-time toolchain that compiles your Flutter into render artifacts | FSL-1.1-ALv2 |
| [`rfw_catalog_compiler`](packages/rfw_catalog_compiler) | Catalog compiler used by the toolchain | FSL-1.1-ALv2 |
| [`restage_cli`](packages/restage_cli) | The `restage` command-line tool. Not on pub.dev yet | BSD-3 |
| [`restage_mcp`](packages/restage_mcp) | MCP server for agent and tool access. Not on pub.dev yet | BSD-3 |
| [`restage_revenuecat`](packages/restage_revenuecat) | Optional billing gateway for apps that use RevenueCat. Not on pub.dev yet | BSD-3 |
| [`restage_a2ui`](packages/restage_a2ui) | App-side capability check for genui A2UI payloads | BSD-3 |
| [`restage_widgetbook_example`](packages/restage_widgetbook_example) | Annotated widget library with generated RFW, A2UI, and Widgetbook output | BSD-3 |
| [`apps/examples`](apps/examples) | Example surfaces to copy | BSD-3 |
| [`apps/widgetbook_example`](apps/widgetbook_example) | Runnable Widgetbook v4 workbench for the generated stories | BSD-3 |

## License

- **BSD-3-Clause** for everything that runs in your app: the SDK, the catalogs,
  the schema, the CLI, the MCP server, the RevenueCat adapter, the A2UI check,
  and the examples. Flutter uses the same license.
- **FSL-1.1-ALv2** for the build-time toolchain (`restage_codegen` and
  `rfw_catalog_compiler`). The source is available. All use is free, including
  use inside your own company. Each release converts to Apache-2.0 two years
  after it ships.

Each package carries its own `LICENSE` file.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). The widget catalog is the easiest
place to start. To add a widget, you write one curation entry; the registration
is generated.
