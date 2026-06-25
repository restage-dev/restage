# restage_core example

`restage_core` is the curated cross-platform RFW widget catalog — layout,
structure, and decoration primitives (Container, Column, Row, Stack, Text,
Image, and more) for server-driven Flutter UI.

You author a surface in ordinary Flutter using these primitives, then a build
step lowers it against the catalog into an inert render blob.

## Author with core primitives

```dart
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

@PaywallSource(id: 'pro')
class ProSurface extends StatelessWidget {
  const ProSurface({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Text('Welcome'),
          SizedBox(height: 8),
          Text('Everything you need, in one place.'),
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

The same primitives compose any surface — paywalls, onboarding, messages, or
surveys. See the [package README](../README.md) for the full widget set, and
[`apps/examples`](https://github.com/restage-dev/restage/tree/main/apps/examples)
for complete, runnable surfaces.
