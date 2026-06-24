# Restage example

Write a surface in vanilla Flutter, compile it to a render blob, and render it —
all offline, no account.

## 1. Author a surface

A surface is an ordinary Flutter widget annotated with its surface type
(`@PaywallSource` here; `@ScreenSource` / `@FlowSource` for onboarding, messages,
surveys, and full screens). It uses your own widgets and your app's theme.

```dart
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@PaywallSource(id: 'pro')
class ProPaywall extends StatelessWidget {
  const ProPaywall({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('Go Pro', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(paywallPriceFor(slot: 'annual')),
        FilledButton(
          onPressed: paywallPurchase(slot: 'annual'),
          child: const Text('Start free trial'),
        ),
      ],
    );
  }
}
```

## 2. Compile it

```sh
dart run build_runner build
```

This writes a small, inert `.rfw` render blob next to your source — commit it.

## 3. Render it

```dart
void main() {
  Restage.configure(apiKey: 'local-dev', resolver: const AssetVariantResolver());
  runApp(const MaterialApp(
    home: Scaffold(body: RestagePaywall(id: 'pro', resolver: AssetVariantResolver())),
  ));
}
```

`RestagePaywall` decodes the blob and renders it as real Flutter widgets, in your
own widget tree.

## Full, runnable examples

A complete gallery — paywalls, onboarding, a permission prompt, an in-app message,
a survey, and custom widgets — lives in
[`apps/examples`](https://github.com/restage-dev/restage/tree/main/apps/examples).
Copy one to start. The full walkthrough is in
[QUICKSTART.md](https://github.com/restage-dev/restage/blob/main/QUICKSTART.md).
