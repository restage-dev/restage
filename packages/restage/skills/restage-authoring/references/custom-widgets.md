# Custom widgets

A custom widget is a component from the app, such as a design-system card, added to the
catalog so surfaces can use it next to the built-in Flutter, Material and Cupertino
widgets. The compiler inlines supported composition when it can; otherwise a
registered factory runs the widget in the installed app. See
[surface-design.md](surface-design.md) to choose and verify that boundary.

## Annotate the widget

<!-- skill-check: example ../examples/lib/widgets/streak_badge.dart -->
```dart
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

/// A pill showing how many days in a row the user has been active.
@RestageWidget()
class StreakBadge extends StatelessWidget {
  /// Creates a streak badge.
  const StreakBadge({super.key, required this.days, this.label = 'day streak'});

  /// Consecutive active days.
  final int days;

  /// Text shown after the number.
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text('$days $label'),
      ),
    );
  }
}
```

- The class name is the catalog name.
- The unnamed public constructor defines the properties: order, required, nullable and
  defaults. Doc comments on fields describe them.
- `Widget` and `List<Widget>` inputs are child slots under their own names. They don't
  have to be called `child` or `children`.
- Callbacks with no argument or one value argument become events named after the
  field.
- Data classes, enums, lists, maps and records in the constructor are supported,
  including `List<String>`, `List<bool>`, `List<int>`, `List<double>` and
  `List<num>`.
- Taps on the widget's callbacks, and inside the children passed to its `Widget`
  and `List<Widget>` inputs, are measured. Named and positional parameters both work.
- Add `@RestageProperty` only for what Dart can't express, such as value constraints
  or a theme default.
- Don't annotate `Container`, `Text` or other widgets used inside it.

## Declare the library

Every custom widget must be exported by exactly one library file:

<!-- skill-check: example ../examples/lib/app_widgets.dart -->
```dart
import 'package:restage/restage.dart';

export 'widgets/recap_heading.dart';
export 'widgets/streak_badge.dart';

/// The app's custom widget library.
final class AppWidgets extends WidgetLibrary {
  /// Creates the library declaration.
  const AppWidgets();

  @override
  final String namespace = 'app.widgets';
}

/// The library identity.
const WidgetLibrary appWidgets = AppWidgets();

/// Raise `capabilityVersion` when a catalog change needs a newer app.
@RestageLibrary(library: appWidgets, capabilityVersion: 1)
const appWidgetCatalog = 0;
```

A widget with no library, or exported by two, stops the build and names the files.

## Use it in a surface

Import the library file and use the widget like any other:

<!-- skill-check: expression -->
```dart
StreakBadge(days: streakDays)
```

The build writes `lib/user_catalog.g.dart` and `lib/user_factories.g.dart`. Generated
mounts install the custom widgets their surface draws, so there is no startup call.
An app that mounts surfaces only by id, such as `RestagePaywall(id: ...)`, calls the
generated `registerRestageWidgets()` once at startup instead.

If the build warns that a widget can't be named from the surface's library, import the
widget library file in the surface's file.

## Releases

An update can change inlined composition within the installed contract. A component
rendered through its native factory keeps the implementation installed in the app;
changing that implementation, or requiring a new native component or property,
needs an app release. Raise `capabilityVersion` when a surface depends on a changed
library capability so incompatible builds refuse it. Check the generated output
and build diagnostics rather than inferring the rendering path from the annotation.

A push records each library version the surface depends on in
`.restage/library-contracts/`; commit it with the catalog identity files. Before
that push the library changes freely, with no version bump and nothing to delete.
A widget package has no push: run `restage library record` in it before publishing.
After that, the compiler compares the library against these snapshots. Additive capability
changes increase `capabilityVersion`; a breaking contract change also advances
`compatibleSince` to the new capability version. Follow the compiler's exact
version diagnostic and never lower the compatibility floor. These library
capabilities describe installed widget support, not the package's semver policy.

Before the dashboard can preview new or changed custom widgets, upload a preview
build. Follow [Dashboard preview builds](setup-and-delivery.md#dashboard-preview-builds)
to choose a personal or shared target and verify it. This is separate from
publishing a surface revision or releasing new app code.

## Optional A2UI and Widgetbook output

The same source can feed Restage delivery, Flutter GenUI and Widgetbook. Enable
either optional emitter independently; one build generates its catalog or stories
before the consuming app runs. Neither needs bundled RFW assets or a published
surface. Read [emitters.md](emitters.md) for the build order, dependencies and
the code that connects each generated output to its runtime.
