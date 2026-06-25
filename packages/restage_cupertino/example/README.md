# restage_cupertino example

`restage_cupertino` is the curated Cupertino (Apple HIG) RFW widget catalog —
`CupertinoButton`, navigation/page scaffolding, switches, sliders, pickers,
text fields, and more — for server-driven Flutter UI. Sibling to `restage_core`
and `restage_material`.

You author a surface in ordinary Flutter using Cupertino widgets, then a build
step lowers it against the catalog into an inert render blob.

## Author with Cupertino widgets

```dart
import 'package:flutter/cupertino.dart';
import 'package:restage/restage.dart';

@PaywallSource(id: 'pro')
class ProSurface extends StatelessWidget {
  const ProSurface({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('Go Pro'),
        CupertinoButton.filled(
          onPressed: paywallPurchase(slot: 'annual'),
          child: const Text('Start free trial'),
        ),
      ],
    );
  }
}
```

A build step lowers this standard Flutter tree to a render blob:

```sh
dart run build_runner build
```

The same widgets compose any surface — paywalls, onboarding, messages, or
surveys. See the [package README](../README.md) for the full widget set, and
[`apps/examples`](https://github.com/restage-dev/restage/tree/main/apps/examples)
for complete, runnable surfaces.
