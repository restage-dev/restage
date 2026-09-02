# Restage example

Write a surface in plain Flutter, compile it to a render blob, and render it.
All offline, no account.

## 1. Author a surface

A surface is a plain Flutter widget annotated with its surface type
(`@Paywall` here; use `@Screen` or `@FlowGraph(surface: ...)` for ordinary
screens and flows). It uses your own widgets and your app's theme.

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
`lib/generated/restage.publication.json` records the publication
identity and exact artifact closure.

Push the generated surface by id, then publish the pushed revision:

```sh
restage surface push welcome
restage surface publish welcome
```

A push uploads a version. A publish makes it live.

## 3. Render it

```dart
void main() {
  Restage.configure(apiKey: 'local-dev');
  runApp(const MaterialApp(
    home: Scaffold(
      body: RestageScreen(
        screen: welcomeScreenRef,
        unavailable: SurfaceScreenUnavailablePolicy.hide(),
      ),
    ),
  ));
}
```

`RestageScreen` decodes the blob and renders it as real Flutter widgets, in your
own widget tree.

## Full, runnable examples

A complete gallery (paywalls, onboarding, a permission prompt, an in-app
message, a survey, and custom widgets) lives in
[`apps/examples`](https://github.com/restage-dev/restage/tree/main/apps/examples).
Copy one to start. The full walkthrough is in
[QUICKSTART.md](https://github.com/restage-dev/restage/blob/main/QUICKSTART.md).
