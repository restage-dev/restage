# Build your first surface

This guide takes you from nothing to a surface rendering in your Flutter app.
It builds a paywall as the example. The same steps build any surface:
onboarding, an in-app message, a survey, or a full screen.

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

Save the file as `lib/paywalls/pro_upgrade.dart`. Other directories under
`lib/` work too; the annotation identifies the surface.

```dart
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/pro_upgrade.restage.g.dart';

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
`onEvent` (step 4), and runs the purchase from there through the store library
it already uses.

The build stops with an error if a surface uses the event names `purchase` or
`restore`, one of the SDK's own `restage.purchase…` or `restage.restore…` names,
or the measurement name `__restage_measurement_tap_v1`. Use your own event names,
as this guide does.

The compiler supports widget composition, helpers and theme reads, including
widgets from packages your app depends on. Custom rendering logic, such as a
`CustomPainter`, belongs in a registered app widget. Unsupported expressions
produce build diagnostics.

## 3. Compile it

Run the generator with its default options:

```sh
dart run build_runner build
```

It writes the typed mount to
`lib/paywalls/restage.generated/pro_upgrade.restage.g.dart` and the publishable
artifacts under `.restage/build/`. The CLI reads
`.restage/build/metadata/restage.publication.json` to find them when you push.

Leave `bundled_runtime` at its default, `false`. You do not need to set this
option in `build.yaml` or add generated surface files to Flutter assets. The
generated mount retains the original Flutter widget as its compiled fallback,
so this example works offline without surface assets.

Commit generated Dart, `.restage/measurement-state.json` and
`.restage/wire-ids.events.jsonl`. The latter two preserve identifiers across
builds. `.restage/build/` is build output and does not belong in the app's
asset list.

Bundling is optional when you want to ship RFW artifacts for offline loading.
See the [bundled-surface reference](packages/restage/skills/restage-authoring/references/setup-and-delivery.md#optional-bundled-surfaces).

## 4. Render it in your app

Mount the generated `ProUpgradePaywallSurface` wherever you want the paywall.
It installs the widgets it needs and uses your original widget as its compiled
fallback, and declares its placement automatically. No hosted configuration or
surface assets are needed for this example.

```dart
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import 'paywalls/pro_upgrade.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: ProUpgradePaywallSurface(
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

`ProUpgradePaywallSurface` renders your original Flutter widget until hosted
content is available. `onEvent` is where your app reacts to what happens
in the surface: a view, a dismissal, or an event you fired with
`paywallEvent`. The `continue` event arrives with `args['plan']`, so your
purchase code goes in that case. Keep the `PaywallLoadFailed` case during
development to report delivery failures. If delivered content can't render,
the generated mount shows the original `ProUpgradePaywall` with the same event
handler.

Build and run it:

```sh
flutter run
```

Release builds need no special flags. The build step records which widgets and
icons your app uses, so a release keeps only those and Flutter's icon
tree-shaking works as usual. Don't pass `--no-tree-shake-icons`: it puts the
whole icon font back into the app.

## 5. The edit loop

Change the widget, recompile, and you have a new surface:

```sh
dart run build_runner build
```

Or keep it rebuilding as you edit:

```sh
dart run build_runner watch
```

The compiled-widget fallback follows Flutter's normal hot-reload rules.
Regenerate after changes to the surface or its parameters and events.

That's the whole local loop: write Flutter, compile, render, repeat. Nothing
so far needs an account or a network.

## 6. Publish when ready (optional)

When you want the surface on a server, push it by id, then publish the pushed
revision:

```sh
restage surface push pro_upgrade
restage surface publish pro_upgrade
```

A push uploads a version and changes nothing that is running. A publish makes
one pushed revision live. Push ten variants; publish one.

Run these after `restage init` has configured the project and app, and after
`restage login`. The push reads `.restage/build/metadata/restage.publication.json` and
uploads the artifacts recorded there. `--type paywall` is optional; it checks the
surface's type.

You can also name the file instead of the id:

```sh
restage surface push lib/paywalls/pro_upgrade.dart
```

The CLI resolves the file through the same generated manifest, so it selects
what the build produced. If a file produced more than one surface, the CLI
lists them and asks; `--all` pushes all of them.

The earlier steps work without publishing. Configure hosted delivery at app
startup when you want this mount to fetch published content.

## Where to go next

- **Another surface.** Onboarding flows, in-app messages, and surveys use the
  same code generator. The examples keep their onboarding, message, and survey
  sources under `lib/onboarding/`. See [`apps/examples`](apps/examples).
- **An interactive paywall.** The example paywalls show plan selection (tap a
  plan, the selection updates, and the button sends the chosen plan) that
  travels inside the artifact with no host code. The examples README explains the pattern.
- **Restage Cloud.** When you want a published surface to update installed
  apps over the air, configure Restage at startup with your public API key
  and service URL, then push and publish it with
  `restage surface push` and `restage surface publish`. Until a version is
  available, the generated mount renders your compiled widget.
