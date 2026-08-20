# Build your first surface

This guide takes you from nothing to a surface rendering in your Flutter app.
It builds a paywall because that is the most common first surface. The same
steps build any surface: onboarding, an in-app message, or a full screen.

The whole thing runs offline. You don't need a Restage account or a backend to
write a surface and render it on device.

If you'd rather read working code, the [`apps/examples`](apps/examples)
README has four starters to copy (a paywall, an onboarding flow, a one-screen
message, and a custom widget), each the smallest file that still ships. This
guide builds one from scratch so you see each piece.

## 1. Add the packages

In your app's `pubspec.yaml`, add these to whatever is already there:

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

Then fetch them:

```sh
flutter pub get
```

If you have the CLI installed, `restage init` does this step and scaffolds a
starter paywall. This guide does it by hand.

## 2. Write the surface

A simple paywall is a `StatelessWidget` annotated with `@Paywall`. It is plain
Flutter, and the widgets are your own: swap in your design-system components
and they ship the same way. The `id` is how you reference the surface when you
render it. (An interactive paywall with plan selection is a `StatefulWidget`
root that holds its selection state; the examples show that pattern.)

Save the file as `lib/paywalls/pro_upgrade.dart`. The builder reads paywalls
from `lib/paywalls/`, so this guide depends on that path.

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

Two helpers come from the SDK. `paywallPurchase(slot: 'annual')` wires the
button to buy that product. `paywallEvent('restage.restore')` fires the SDK's
reserved restore event, which the SDK handles when it renders the paywall.

A third helper, `paywallPriceFor(slot: 'annual')`, puts a live store price into
any `Text`. It binds to your connected store products at render time, so it
works once you pass products to `Restage.configure` (step 5). This guide
attaches no store, and a price binding with nothing behind it reports a paywall
load failure instead of rendering a wrong price, so leave it out here.

A few habits keep a surface compilable. The build follows your widget tree
literally, so write each string as one literal, keep the build tree flat
instead of extracting helper widgets, and write theme reads inline where you
use them. The examples document the full list. One boundary: custom render
logic (a `CustomPainter`, for instance) isn't available in a surface; compose
from Flutter's own widgets instead. If the build can't lower something, it
tells you at build time instead of rendering it differently.

## 3. Compile it

This guide runs offline, so the compiled surface has to ship inside the app.
Create a `build.yaml` next to `pubspec.yaml` that sets `bundled_runtime` on
every `restage_codegen` builder key:

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
block where it first appears and each `*restage_placement` reuses it, so there
is one block to edit. If two keys disagree, the build fails with a placement
options divergence error instead of scattering output.

> [!NOTE]
> `bundled_runtime: true` is what makes this offline guide work. It is not the
> default. By default nothing goes into the app's assets: with hosted delivery,
> surfaces reach installed apps over the air and no `build.yaml` is needed at
> all. See **Hosted delivery** under *Where to go next*.

Run the build:

```sh
dart run build_runner build
```

This compiles your widget into one container:

```
lib/paywalls/pro_upgrade.dart  ──▶  assets/restage/bundles/lib/paywalls/pro_upgrade.rsbundle
```

The `.rsbundle` is a zip that holds the compiled artifacts at their logical
paths: the binary `.rfw` artifact your app renders, the readable `.rfwtxt`, and
the capability sidecar. Unzip it when you want to read the `.rfwtxt`.

Those artifacts are the only thing that ships over the air. They hold
references and literal values, never executable code. Your Dart stays in the
app.

The build also writes `lib/generated/restage.publication.json`, which records
the exact artifacts for each surface id. It is a build output, so it appears
after this step, not in a fresh clone. Commit the generated outputs your app
bundles.

Add the bundle directory to your `pubspec.yaml`. A Flutter asset directory
entry isn't recursive, so list each bundle directory; the tree mirrors your
`lib/` layout:

```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/restage/bundles/lib/paywalls/
```

## 4. Publish it

When you want the surface on a server, publish it by id:

```sh
restage surface publish pro_upgrade
```

Run it after `restage init` has configured the project and app, and after
`restage login`. The CLI reads `lib/generated/restage.publication.json` and
uploads the artifacts recorded there. `--type paywall` is optional validation.

You can also name the file instead of the id:

```sh
restage surface publish lib/paywalls/pro_upgrade.dart
```

The CLI resolves the file through the same generated manifest, so it selects
what the build produced. If a file produced more than one surface, the CLI
lists them and asks; `--all` publishes all of them.

You can skip this step for now. The rest of the guide renders the bundled copy.

## 5. Render it in your app

Configure Restage once at startup, then put `RestagePaywall` wherever you want
the paywall. `AssetVariantResolver` tells it to load the bundled artifact you
just compiled.

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

`RestagePaywall(id: 'pro_upgrade')` resolves the bundled paywall and renders
it as real Flutter widgets. `onEvent` is where your app reacts to what happens
in the surface: a view, a purchase, a restore, or any event you fired with
`paywallEvent`. Keep the `PaywallLoadFailed` case during development. A
surface that can't render fails closed to an empty box, and that event's
message is the one signal that says why.

To see real prices and a working purchase, pass your App Store and Play
products to `products:` in `configure`. The `paywallPriceFor` and
`paywallPurchase` slots bind to them by slot name.

Build and run it:

```sh
flutter run
```

A debug `flutter run` doesn't tree-shake icons, so it needs no flag. When you
build a release of an app that ships a Restage surface, add
`--no-tree-shake-icons`. The artifact constructs icons from runtime values,
which the release icon tree-shaker can't see, so the build fails without it:

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

Flutter doesn't hot-reload bundled assets, so after the `.rfw` rebuilds,
hot-restart the running app (press `R` in `flutter run`) to pick up the new
artifact.

That's the whole local loop: write Flutter, compile, render, repeat. Nothing
so far needs an account or a network.

## Where to go next

- **Another surface.** Onboarding flows, in-app messages, and surveys use the
  same code generator. The examples keep engagement source files under
  `lib/onboarding/`. See the engagement-surface examples in
  [`apps/examples`](apps/examples).
- **An interactive paywall.** The example paywalls show plan selection (tap a
  plan, the selection updates, the purchase re-targets) that travels inside the
  artifact with no host code. The examples README explains the pattern.
- **Hosted delivery.** When you want a published surface to update installed
  apps over the air, use hosted delivery and `restage surface publish`. Hosted
  delivery is in private beta. The SDK falls back to your bundled artifact
  until it is available, so nothing you build now has to change.
