# Build your first surface

This guide takes you from nothing to a surface rendering in your Flutter app.
It builds a paywall because that is the most common first surface. The same
steps build any surface: onboarding, an in-app message, or a full screen.

The whole thing runs offline. You don't need a Restage account or a backend to
write a surface and render it on device.

If you'd rather read working code, the [`apps/examples`](apps/examples)
README has five starters to copy (a paywall, an onboarding flow, a one-screen
message, a custom widget, and a screen driven by host data), each the smallest
file that still ships. This guide builds one from scratch so you see each
piece.

## 1. Add the packages

In your app's `pubspec.yaml`, add these to whatever is already there:

```yaml
dependencies:
  flutter:
    sdk: flutter
  restage: ^2.0.0
  restage_material: ^2.0.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  build_runner: ">=2.4.0 <3.0.0"
  restage_codegen: ^2.0.0
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
                onPressed: paywallEvent('continue', args: {'plan': 'annual'}),
                child: const Text('Start free trial'),
              ),
              TextButton(
                onPressed: paywallEvent('restore_purchases'),
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

Both buttons use `paywallEvent`. It takes an event name and optional
arguments, and the build compiles them into the artifact. When the user taps,
your app receives a `PaywallCustomEvent` with that name and those arguments in
`onEvent` (step 5), and runs the purchase from there through the store library
it already uses.

The names `purchase` and `restore`, and any name that starts with `restage.`,
are reserved for the SDK and never reach your app. Use your own names, as this
guide does.

A few habits keep a surface compilable. The build follows your widget tree
literally, so write each string as one literal, keep the build tree flat
instead of extracting helper widgets, and write theme reads inline where you
use them. The examples document the full list. Custom rendering logic, such as
a `CustomPainter`, belongs in a registered app-backed widget. You can also
compose the surface from catalog widgets. If the build can't lower something, it
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
> This guide mounts `RestagePaywall` by id. Keep `bundled_runtime: true` and the
> asset declarations for its offline fallback, including when adding hosted delivery.
> Hosted delivery alone does not retain the original paywall widget. Generated
> standalone screen mounts already retain their authored widget. Typed paywall and
> flow mounts add that behavior in the next SDK release; see **Hosted delivery**
> under *Where to go next* for the API-specific requirements.

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

What ships is data the app renders. Your widgets carry the logic — real Dart,
compiled into your app. The surface composes and configures them over the air.
New behavior is a release.

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

## 4. Push it and publish it

When you want the surface on a server, push it by id, then publish the pushed
revision:

```sh
restage surface push pro_upgrade
restage surface publish pro_upgrade
```

A push uploads a version and changes nothing that is running. A publish makes
one pushed revision live. Push ten variants; publish one.

Run these after `restage init` has configured the project and app, and after
`restage login`. The push reads `lib/generated/restage.publication.json` and
uploads the artifacts recorded there. `--type paywall` is optional validation.

You can also name the file instead of the id:

```sh
restage surface push lib/paywalls/pro_upgrade.dart
```

The CLI resolves the file through the same generated manifest, so it selects
what the build produced. If a file produced more than one surface, the CLI
lists them and asks; `--all` pushes all of them.

You can skip this step for now. The rest of the guide renders the bundled copy.

## 5. Render it in your app

Configure Restage once at startup, then put `RestagePaywall` wherever you want
the paywall. It loads the bundled artifact you just compiled by default, so
there is nothing to point it at.

```dart
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

void main() {
  Restage.configure(apiKey: 'local-dev');
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
          onEvent: (event) {
            switch (event) {
              case PaywallViewed():
                debugPrint('paywall viewed');
              case PaywallCustomEvent(:final eventName, :final args):
                debugPrint('$eventName ${args['plan'] ?? ''}');
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
in the surface: a view, a dismissal, or an event you fired with
`paywallEvent`. The `continue` event arrives with `args['plan']`, so your
purchase code goes in that case. Keep the `PaywallLoadFailed` case during
development. A surface that can't render fails closed to an empty box, and
that event's message is the one signal that says why.

Build and run it:

```sh
flutter run
```

Release builds need no special flags. The build step records which widgets and
icons your app uses, so a release keeps only those and Flutter's icon
tree-shaking works as usual. Don't pass `--no-tree-shake-icons`: it puts the
whole icon font back into the app.

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
  apps over the air, use hosted delivery with `restage surface push` and
  `restage surface publish`. Hosted delivery is in private beta. The SDK falls
  back to your bundled artifact until it is available, so nothing you build now
  has to change.
