# Restage example

Write a surface in plain Flutter, compile it to a render blob, and render it.
All offline, no account.

## 1. Author a surface

A surface is a plain Flutter widget annotated with its surface type
(`@Screen` here; use `@Paywall` for paywalls or `@FlowGraph(surface: ...)`
for flows). It uses your own widgets and your app's theme.

```dart
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/welcome.restage.g.dart';

@Screen(id: 'welcome', surface: Surface.onboarding)
final class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('Welcome', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        const Text('A simple server-driven screen.'),
      ],
    );
  }
}
```

## 2. Compile it

```sh
dart run build_runner build
```

This writes generated, inert render artifacts. Commit the generated output your
app bundles. The fixed
`.restage/build/metadata/restage.publication.json` records the publication
identity and exact artifact closure.

When you configure a hosted project, you can also push and publish the surface:

```sh
restage surface push welcome
restage surface publish welcome
```

A push uploads a version. A publish makes it live.

## 3. Render it

```dart
void main() {
  runApp(MaterialApp(
    home: Scaffold(body: WelcomeScreenSurface()),
  ));
}
```

The generated `WelcomeScreenSurface` installs its widgets and renders delivered
content when configured. Without hosted content, it uses the original
`WelcomeScreen` as its compiled fallback. No API key is needed for this example.

## Full, runnable examples

A complete gallery (paywalls, onboarding, a permission prompt, an in-app
message, a survey, and custom widgets) lives in
[`apps/examples`](https://github.com/restage-dev/restage/tree/main/apps/examples).
Copy one to start. The full walkthrough is in
[QUICKSTART.md](https://github.com/restage-dev/restage/blob/main/QUICKSTART.md).
