# Build your first surface

This walks you from nothing to a real surface rendering in your Flutter app.
We'll build a paywall, because it's the most common first surface, but the same
steps build any surface: onboarding, an in-app message, or a full screen.

The whole thing runs offline. You don't need a Restage account or a backend to
write a surface and render it on device.

If you'd rather read working code than a walkthrough, the [`apps/examples`](apps/examples)
README has a **Starters** section: four minimal, copy-me surfaces (a paywall, an
onboarding flow, a one-screen message, and a custom widget), each the smallest file
that still ships, plus a library of fuller, polished surfaces. Copying a starter is the
fastest way to begin. This guide builds one from scratch so you see each piece.

## 1. Add the packages

In your Flutter app's `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  restage: ^1.3.0
  restage_material: ^1.0.2

dev_dependencies:
  flutter_test:
    sdk: flutter
  build_runner: ">=2.4.0 <3.0.0"
  restage_codegen: ^1.2.0
```

Keep whatever your project already lists (a fresh `flutter create` app has
`flutter_test` and `flutter_lints` there); add these entries to it rather than
replacing the block.

Then fetch them:

```sh
flutter pub get
```

(If you have the CLI installed, `restage init` will do this step and scaffold a
starter paywall for you. This guide assumes you're doing it by hand.)

## 2. Write the surface

A simple paywall is a `StatelessWidget` annotated with `@Paywall`. You write
ordinary Flutter. These are your own widgets: swap in your design-system components
and they ship the same way. The `id` is how you'll reference the surface when you
render it. (Interactive paywalls, plan selection and the like, are a `StatefulWidget`
root holding their selection state; the examples show that pattern.)

Save the source as `lib/paywalls/pro_upgrade.dart`. The builder reads paywalls
from `lib/paywalls/`, so this walkthrough depends on that path. What the path
does NOT decide is identity:
the annotation's `id` and the generated publication manifest own the surface
identity and its artifact closure.

```dart
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@Paywall(id: 'pro_upgrade')
class ProUpgradePaywall extends StatelessWidget {
  const ProUpgradePaywall({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Go Pro',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text('Everything, unlocked.'),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: paywallPurchase(slot: 'annual'),
                child: const Text('Start free trial'),
              ),
              TextButton(
                onPressed: paywallEvent('restage.restore'),
                child: const Text('Restore purchases'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

Two helpers come from the SDK: `paywallPurchase(slot: 'annual')` wires the
button to buy that product, and `paywallEvent('restage.restore')` fires the
SDK's reserved restore event, which the SDK handles when it renders the
paywall.

A third helper, `paywallPriceFor(slot: 'annual')`, drops a live store price
into any `Text`. It binds to your connected store products at render time, so
it joins when you pass products to `Restage.configure` (step 5). This
walkthrough attaches no store, and a price binding with nothing behind it
reports a paywall load failure instead of rendering a wrong price, so leave it
out here.

A few authoring habits keep a surface compilable. The build follows your widget
tree literally, so: write each string as a single literal, keep the build tree
flat rather than extracting helper widgets, and write any theme reads inline at the
point of use. The examples document the full list. And one capability boundary:
fully custom render logic (a `CustomPainter`, for instance) is not available in a
surface; compose from Flutter's own widgets instead. If the build step can't lower
something, it tells you at build time rather than rendering it differently.

## 3. Compile it

This walkthrough runs offline, so the generated surface has to ship inside the
app. Create a `build.yaml` next to `pubspec.yaml` that sets `bundled_runtime`
on every `restage_codegen` builder key:

```yaml
targets:
  $default:
    builders:
      restage_codegen:restage_source_roster:
        options: &restage_placement
          bundled_runtime: true
      restage_codegen:restage_package_surface_compiler:
        options: *restage_placement
      restage_codegen:generated_dart:
        options: *restage_placement
      restage_codegen:outputs:
        options: *restage_placement
```

The options must be identical on every key. `&restage_placement` names the
options block where it first appears and each `*restage_placement` reuses it,
so there is one block to edit. A mismatch between keys fails the build with a
placement options divergence error instead of scattering output.

> [!NOTE]
> `bundled_runtime: true` is the opt-in that makes this offline walkthrough
> work; it is not the default. By default nothing is routed into the app's
> assets: with hosted delivery, surfaces reach installed apps over the air and
> no `build.yaml` is needed at all. See **Hosted delivery** under *Where to go
> next*.

Run the build:

```sh
dart run build_runner build
```

This compiles your widget into one deterministic container:

```
lib/paywalls/pro_upgrade.dart  ──▶  assets/restage/bundles/lib/paywalls/pro_upgrade.rsbundle
```

The `.rsbundle` is a zip holding the compiled artifacts at their logical
paths: the binary `.rfw` blob your app renders, the human-readable `.rfwtxt`,
and the capability sidecar. Generated artifacts are packaged once, inside the
container, and the runtime answers logical-path reads from inside it. Unzip
the bundle when you want to inspect the `.rfwtxt`.

Artifact paths are not publication selectors; the generated manifest at
`lib/generated/restage.publication.json` records the exact closure. It is a
build output, so it appears after this step rather than in a fresh clone.
Commit the generated outputs your app bundles.

Bundle the container by adding its directory to your `pubspec.yaml`. A Flutter
directory entry is not recursive, so each bundle directory is listed; the tree
mirrors the authored `lib/` layout:

```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/restage/bundles/lib/paywalls/
```

The asset entry bundles generated output for this specialized paywall. It does
not choose which surface the CLI publishes.

## 4. Publish the generated surface

The normal publication command selects the generated entry by slug:

```sh
restage surface publish pro_upgrade
```

Run it after `restage init` has configured the project and app, and after
`restage login` has completed.

The CLI reads `lib/generated/restage.publication.json` and uploads the
exact artifact closure recorded there. `--type paywall` is optional validation or
disambiguation. Do not pass `--path` to select an artifact; source and asset
directories are not publication authority.

## 5. Render it in your app

Configure Restage once at startup, then drop `RestagePaywall` wherever you want
the paywall. `AssetVariantResolver` tells it to load the bundled blob you just
compiled.

```dart
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

void main() {
  Restage.configure(
    apiKey: 'local-dev',
    resolver: const AssetVariantResolver(),
    // products: [ ... your store products ... ],
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'pro_upgrade',
          resolver: const AssetVariantResolver(),
          onEvent: (event) {
            switch (event) {
              case PaywallViewed():
                debugPrint('paywall viewed');
              case PurchaseSucceeded():
                debugPrint('purchased');
              case PaywallLoadFailed(:final message):
                debugPrint('paywall load failed: $message');
              case _:
                break;
            }
          },
        ),
      ),
    );
  }
}
```

`RestagePaywall(id: 'pro_upgrade')` resolves the generated bundled paywall and
renders it as real Flutter widgets. The `onEvent` callback is where your app
reacts to what happens in the surface: a view, a purchase, a restore, or any event
you fired with `paywallEvent`. Keep the `PaywallLoadFailed` case during
development: a surface that cannot render fails closed to an empty box, and
that event's message is the one signal saying why.

To see real prices and a working purchase, pass your App Store and Play products to
`products:` in `configure`. The `paywallPriceFor` and `paywallPurchase` slots bind
to them by slot name.

Build and run it:

```sh
flutter run
```

A debug `flutter run` doesn't tree-shake icons, so it needs no flag. When you build
a **release** of an app that ships a Restage surface, add `--no-tree-shake-icons`.
The render blob constructs icons from runtime values, which the release icon
tree-shaker can't see, so the build fails without the flag:

```sh
flutter build ios --no-tree-shake-icons
```

## 6. The edit loop

Change the widget, recompile, and you have a new surface:

```sh
dart run build_runner build
```

Or keep it rebuilding as you edit:

```sh
dart run build_runner watch
```

One thing to know: Flutter doesn't hot-reload bundled assets, so after the `.rfw`
rebuilds, hot-restart the running app (press `R` in `flutter run`) to pick up the
new blob.

That's the whole local loop: write Flutter, compile, render, repeat. Everything so
far works with no account and no network.

## Where to go next

- **Another surface.** Onboarding flows, in-app messages, and surveys are authored
  with the same code generator. The examples keep engagement source files under
  `lib/onboarding/` as a readable layout convention. See the engagement-surface
  examples in [`apps/examples`](apps/examples).
- **An interactive paywall.** The example paywalls show plan selection (tap a plan,
  the selection updates, the purchase re-targets) that travels inside the render
  blob with no host code. The examples README explains the pattern.
- **Hosted delivery.** When you want a published surface to update installed apps
  over the air, use hosted delivery and `restage surface publish`. Hosted delivery
  is in private beta; the SDK already falls back to your bundled blob until it's
  available, so nothing you build now has to change.

## Migration from legacy source annotations

Older projects may use `@PaywallSource`, `@ScreenSource`, or `@FlowSource`.
Those annotations remain only as deprecated compatibility frontends. New source
should use `@Paywall`, `@Screen`, or `@FlowGraph(surface: ...)`. The specialized
`restage paywall publish <name>` command is also retained for compatibility, but
normal publication uses `restage surface publish <slug>` for every surface family.
