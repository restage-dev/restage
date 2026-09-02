# restage_cupertino example

`restage_cupertino` is the curated Cupertino (Apple HIG) RFW widget catalog for
server-driven Flutter UI: `CupertinoButton`, navigation/page scaffolding,
switches, sliders, pickers, text fields, and more. Sibling to `restage_core`
and `restage_material`.

You author a surface in plain Flutter using Cupertino widgets, then a build
step lowers it against the catalog into an inert render blob.

## Author with Cupertino widgets

```dart
import 'package:flutter/cupertino.dart';
import 'package:restage/restage.dart';

part 'restage.generated/welcome.restage.g.dart';

@Screen(id: 'welcome', surface: Surface.onboarding)
final class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text('Welcome'),
      ),
      child: Center(
        child: Text('A simple Cupertino surface.'),
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
