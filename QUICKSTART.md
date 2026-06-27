# Build your first surface

This walks you from nothing to a real surface rendering in your Flutter app. We
will build a paywall, because it is the most common first surface, but the same
steps build any surface: onboarding, an in-app message, or a full screen.

The whole thing runs offline. You do not need a Restage account or a backend to
write a surface and render it on device.

If you would rather read working code than a walkthrough, the [`apps/examples`](apps/examples)
README has a **Starters** section — four minimal, copy-me surfaces (a paywall, an
onboarding flow, a one-screen message, and a custom widget), each the smallest file
that still ships — plus a library of fuller, polished surfaces. Copying a starter is the
fastest way to begin. This guide builds one from scratch so you see each piece.

## 1. Add the packages

In your Flutter app's `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  restage: ^0.1.0
  restage_material: ^0.1.0

dev_dependencies:
  build_runner: ">=2.4.0 <3.0.0"
  restage_codegen: ^0.1.0
```

Then fetch them:

```sh
flutter pub get
```

(If you have the CLI installed, `restage init` will do this step and scaffold a
starter paywall for you. This guide assumes you are doing it by hand so you can see
each piece.)

## 2. Write the surface

A simple paywall is a `StatelessWidget` annotated with `@PaywallSource`. You write
ordinary Flutter. The `id` is how you will reference the surface when you render
it. (Interactive paywalls — plan selection and the like — are a `StatefulWidget`
root holding their selection state; the examples show that pattern.)

Save this as `lib/paywalls/pro_upgrade.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@PaywallSource(id: 'pro_upgrade')
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
              // The price resolves at render time from your store products.
              Text(paywallPriceFor(slot: 'annual')),
              const SizedBox(height: 16),
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

Three helpers come from the SDK:

- `paywallPriceFor(slot: 'annual')` is replaced at build time with a live price
  binding. When you render the surface, the SDK fills in the current store price.
  (In a plain `runApp` of this class, with no rendering pipeline around it, it
  returns a `$X.XX` placeholder so the layout still lays out.)
- `paywallPurchase(slot: 'annual')` wires the button to buy that product.
- `paywallEvent('restage.restore')` fires the SDK's reserved restore event, which
  the SDK handles when it renders the paywall.

A few authoring habits keep a surface compilable. The build follows your widget
tree literally, so: write each string as a single literal, keep the build tree
flat rather than extracting helper widgets, and write any theme reads inline at the
point of use. The examples document the full list. And one capability boundary:
fully custom render logic (a `CustomPainter`, for instance) is not available in a
surface; compose from Flutter's own widgets instead. If the build step cannot lower
something, it tells you at build time rather than rendering it differently.

## 3. Compile it

Run the build:

```sh
dart run build_runner build
```

This compiles your widget into a render blob:

```
lib/paywalls/pro_upgrade.dart  ──▶  assets/paywalls/pro_upgrade.rfwtxt
                                    assets/paywalls/pro_upgrade.rfw
```

The `.rfwtxt` is the human-readable output, handy for seeing what the compiler
produced. The `.rfw` is the binary blob your app renders. Both are written into
your package and are meant to be committed.

Bundle the blob by adding the asset folder to your `pubspec.yaml`:

```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/paywalls/
```

## 4. Render it in your app

Configure Restage once at startup, then drop `RestagePaywall` wherever you want
the paywall. `AssetVariantResolver` tells it to load the bundled blob you just
compiled.

```dart
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import 'paywalls/pro_upgrade.dart';

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

`RestagePaywall(id: 'pro_upgrade')` decodes `assets/paywalls/pro_upgrade.rfw` and
renders it as real Flutter widgets. The `onEvent` callback is where your app
reacts to what happens in the surface: a view, a purchase, a restore, or any event
you fired with `paywallEvent`.

To see real prices and a working purchase, pass your App Store and Play products to
`products:` in `configure`. The `paywallPriceFor` and `paywallPurchase` slots bind
to them by slot name.

Build and run it:

```sh
flutter run
```

A debug `flutter run` doesn't tree-shake icons, so it needs no flag. When you build
a **release** of an app that ships a Restage surface, add `--no-tree-shake-icons` —
the render blob constructs icons from runtime values, which the release icon
tree-shaker can't reason about, so the build fails without it:

```sh
flutter build ios --no-tree-shake-icons
```

## 5. The edit loop

Change the widget, recompile, and you have a new surface:

```sh
dart run build_runner build
```

Or keep it rebuilding as you edit:

```sh
dart run build_runner watch
```

One thing to know: Flutter does not hot-reload bundled assets, so after the `.rfw`
rebuilds, hot-restart the running app (press `R` in `flutter run`) to pick up the
new blob.

That is the whole local loop: write Flutter, compile, render, repeat. Everything so
far works with no account and no network.

## Where to go next

- **Another surface.** Onboarding flows, in-app messages, and surveys are authored
  the same way, under `lib/onboarding/`. See the engagement-surface examples in
  [`apps/examples`](apps/examples).
- **An interactive paywall.** The example paywalls show plan selection (tap a plan,
  the selection updates, the purchase re-targets) that travels inside the render
  blob with no host code. The examples README explains the pattern.
- **Hosted delivery.** When you want a published surface to update installed apps
  over the air, that is what hosted delivery and the CLI's `restage publish` are
  for. Hosted delivery is in private beta; the SDK already falls back to your
  bundled blob until it is available, so nothing you build now has to change.
