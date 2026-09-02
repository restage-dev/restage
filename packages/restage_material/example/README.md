# restage_material example

`restage_material` is the curated Material Design RFW widget catalog (buttons,
Scaffold, AppBar, Card, ListTile, chips, selection controls, and more) for
server-driven Flutter UI. Sibling to `restage_core` and `restage_cupertino`.

You author a surface in plain Flutter using Material widgets, then a build
step lowers it against the catalog into an inert render blob.

## Author with Material widgets

```dart
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/welcome.restage.g.dart';

@Screen(id: 'welcome', surface: Surface.onboarding)
final class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Welcome')),
      body: const Center(
        child: Text('A simple Material surface.'),
      ),
    );
  }
}
```

A build step lowers this standard Flutter tree to a render blob:

```sh
dart run build_runner build
```

The generated manifest at
`lib/generated/restage.publication.json` records the surface identity
and exact artifact closure. Push by surface id, then publish the pushed
revision:

```sh
restage surface push welcome
restage surface publish welcome
```

The same widgets compose any surface: onboarding, messages, surveys, or
screens. See the [package README](../README.md) for the full widget set, and
[`apps/examples`](https://github.com/restage-dev/restage/tree/main/apps/examples)
for complete, runnable surfaces.
