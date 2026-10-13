<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="brand/restage-wordmark-bold-dark.svg">
    <source media="(prefers-color-scheme: light)" srcset="brand/restage-wordmark-bold-light.svg">
    <img alt="Restage" src="brand/restage-wordmark-banner-dark.png" width="320">
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

Restage is server-driven UI for Flutter. Add one annotation to a widget you
already wrote, and it becomes a surface you can publish, measure, and roll back
without a new app build: an onboarding flow, a message, a survey, a paywall, or
any screen. It renders as real Flutter widgets in your app, using your theme.

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
restage surface push welcome
restage surface publish welcome
```

That's it. The [Quickstart](QUICKSTART.md) takes you from install to a
published surface. [`apps/examples`](apps/examples) has starters to copy:
an onboarding flow, a one-screen message, a paywall, a custom widget, and a
screen driven by host data.

## Author, push, and publish

Use the annotation that matches what you build:

- `@Screen(surface: Surface.<category>)` publishes one screen.
- `@Paywall` publishes a paywall. A paywall can also be a step in a flow.
- `@FlowGraph(surface: Surface.<category>)` publishes a typed flow of screens.

`@Screen()` with no category is a screen for use inside a flow. The categories
are `onboarding`, `message`, `survey`, `paywall`, and `general`.

`restage surface push <id>` uploads the artifacts the build generated for that
surface id. `restage surface publish <id>` then makes one pushed revision live.
A push changes nothing that is running. Push ten variants; publish one.

You can also name the file instead of the id:

```sh
restage surface push lib/screens/welcome.dart
```

The CLI resolves the file through the same generated manifest, so it selects
what the build produced. Naming a screen that belongs to a flow pushes that
flow. If a file produced more than one surface, the CLI lists them and asks;
`--all` pushes all of them.

## Why Restage

- **Your widgets, your theme.** You use your own design system. The build
  compiles the code you wrote, and `Theme.of(context)` resolves when the
  surface renders, so a published surface follows your app into dark mode or a
  rebrand.
- **Use it anywhere in the app.** An onboarding flow, a survey, a paywall, a
  whole screen, or one card inside your own `Scaffold`. One runtime renders
  all of them.
- **It has a catalog of 119 widgets** across `restage_core`,
  `restage_material`, and `restage_cupertino`. Add your own widgets with
  `@RestageWidget`.
- **Your app owns the implementation.** What ships is data the app renders.
  Your widgets carry the logic as Dart compiled into your app, and the surface
  composes and configures them. New behavior needs an app release.
- **It measures every version (beta).** Views, taps, and completions are captured
  automatically for each version, with no tracking calls to add. With Restage
  Cloud, A/B tests show which version moves your main metric.
- **It fails safe.** The build stops with an error when it cannot compile
  something. A surface never reaches a client that is too old to render it. If
  a fetch fails, the SDK renders your bundled copy.
- **It leaves the purchase to your app.** A paywall fires an event that
  carries the plan the user chose. Your app handles that event in `onEvent`
  and runs the purchase through the store library it already uses. The SDK
  does not talk to the app stores.
- **It does not lock you in.** Serve the artifacts from your own backend or
  CDN. The SDK works without Restage Cloud.

## Controlled delivery

The SDK ships immutable surface versions. A client that cannot render a version
falls back to a safe one. Restage Cloud adds the controls: roll back, freeze,
or switch off any surface, decide who can publish, and export an audit trail of
what changed, when, and by whom.

## Works with

- **A2UI (early):** the same widget constructors emit a genui A2UI catalog, so
  AI-generated UI builds from your real widgets.
- **Widgetbook:** generate stories from the same constructors and browse them
  in a Widgetbook v4 workbench.

## Install

```yaml
dependencies:
  restage: ^2.0.0
  restage_material: ^2.0.0

dev_dependencies:
  restage_codegen: ^2.0.0
  build_runner: ">=2.4.0 <3.0.0"
```

Release builds need no special flags. The build step records which widgets
and icons your app uses, and Flutter's icon tree-shaking works as usual.

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
| [`restage_measurement_schema`](packages/restage_measurement_schema) | Shared data types for measurement and experiments | BSD-3 |
| [`restage_codegen`](packages/restage_codegen) | Build-time toolchain that compiles your Flutter into render artifacts | FSL-1.1-ALv2 |
| [`rfw_catalog_compiler`](packages/rfw_catalog_compiler) | Catalog compiler used by the toolchain | FSL-1.1-ALv2 |
| [`restage_cli`](packages/restage_cli) | The `restage` command-line tool. Not on pub.dev yet | BSD-3 |
| [`restage_mcp`](packages/restage_mcp) | MCP server for agent and tool access. Not on pub.dev yet | BSD-3 |
| [`restage_revenuecat`](packages/restage_revenuecat) | Placeholder for a RevenueCat adapter. No public API yet, and not on pub.dev | BSD-3 |
| [`restage_a2ui`](packages/restage_a2ui) | App-side capability check for genui A2UI payloads | BSD-3 |
| [`restage_widgetbook_example`](packages/restage_widgetbook_example) | Annotated widget library with generated RFW, A2UI, and Widgetbook output | BSD-3 |
| [`apps/examples`](apps/examples) | Example surfaces to copy | BSD-3 |
| [`apps/widgetbook_example`](apps/widgetbook_example) | Runnable Widgetbook v4 workbench for the generated stories | BSD-3 |

## License

- **BSD-3-Clause** for everything that runs in your app: the SDK, the catalogs,
  the catalog and measurement schemas, the CLI, the MCP server, the A2UI
  check, and the examples. Flutter uses the same license.
- **FSL-1.1-ALv2** for the build-time toolchain (`restage_codegen` and
  `rfw_catalog_compiler`). The source is available. All use is free, including
  use inside your own company. Each release converts to Apache-2.0 two years
  after it ships.

Each package carries its own `LICENSE` file.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). The widget catalog is the easiest
place to start. To add a widget, you write one curation entry; the registration
is generated.
