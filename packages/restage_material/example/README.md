# restage_material example

`restage_material` is the curated Material Design RFW widget catalog (buttons,
Scaffold, AppBar, Card, ListTile, chips, selection controls, and more) for
server-driven Flutter UI. Sibling to `restage_core` and `restage_cupertino`.

You author a surface in ordinary Flutter using Material widgets, then a build
step lowers it against the catalog into an inert render blob.

## Author with Material widgets

```dart
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@PaywallSource(id: 'pro')
class ProSurface extends StatelessWidget {
  const ProSurface({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Go Pro'),
          FilledButton(
            onPressed: paywallPurchase(slot: 'annual'),
            child: const Text('Start free trial'),
          ),
        ],
      ),
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
