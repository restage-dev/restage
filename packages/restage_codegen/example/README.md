# restage_codegen example

`restage_codegen` is the build-time code generator behind the Restage SDK. You
don't call it directly — you add it as a dev dependency and run `build_runner`.
It reads an ordinary Flutter widget annotated with its surface type and compiles
it into the small, inert Remote Flutter Widget (`.rfw`) render blob the Restage
runtime renders. The same pipeline serves every surface — onboarding screens,
in-app messages, surveys, paywalls, and any full screen you author.

## 1. Add the toolchain

```yaml
# pubspec.yaml
dependencies:
  restage: ^1.3.0          # runtime SDK + the surface annotations

dev_dependencies:
  build_runner: ^2.4.0
  restage_codegen: ^1.3.0  # the build-time compiler (this package)
```

## 2. Author a surface in vanilla Flutter

A surface is an ordinary widget annotated with its surface type. This example is
an independently published message screen. Use `@Paywall` for a specialized
paywall, `@Screen()` for a reusable flow screen, or
`@FlowGraph(surface: Surface.<category>)` for a typed flow. The source uses your
own widgets and your app's theme; there are no shim classes to learn.

```dart
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/welcome.restage.g.dart';

@Screen(id: 'welcome', surface: Surface.message)
final class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('Welcome', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        const Text('Server-driven UI that renders as real Flutter widgets.'),
      ],
    );
  }
}
```

## 3. Compile it

```sh
dart run build_runner build
```

`restage_codegen` runs as a `build_runner` builder (wired through `build.yaml`):
it analyzes the annotated source, decomposes structured Flutter types — text
styles, paddings, gradients, borders — against the widget catalog, and writes a
small `.rfw` blob as generated output. Commit the generated output your app
bundles: it carries no executable code, only inert references and literal values.

## What it produces

- A per-surface `.rfw` render blob the Restage runtime decodes into real Flutter
  widgets, in your own widget tree.
- A generated `SurfaceScreenRef<E>` and publication entry in
  `lib/generated/restage.publication.json`.
- Catalog entries for any custom widgets you registered with `@RestageWidget`
  (see [`rfw_catalog_compiler`](https://pub.dev/packages/rfw_catalog_compiler)).

Publish the generated entry by slug:

```sh
restage surface publish welcome
```

The manifest is the publication authority. Generated asset paths and source
directories are outputs or layout conventions, not publication selectors.

The runtime half of the loop — rendering the blob in your app — lives in the
[`restage`](https://pub.dev/packages/restage) package. A complete, runnable
gallery is in
[`apps/examples`](https://github.com/restage-dev/restage/tree/main/apps/examples).

## Migration from legacy source annotations

Older source may use `@ScreenSource`, `@PaywallSource`, or `@FlowSource`.
Those spellings are deprecated compatibility frontends. New source should use
`@Screen`, `@Paywall`, and `@FlowGraph(surface: ...)`.
