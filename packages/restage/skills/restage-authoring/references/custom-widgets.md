# Custom widgets

A custom widget is a component from the app, such as a design-system card, added to the
catalog so surfaces can use it next to the built-in Flutter, Material and Cupertino
widgets. The compiler inlines supported composition when it can; otherwise a
registered factory runs the widget in the installed app. See
[surface-design.md](surface-design.md) to choose and verify that boundary.

## Annotate the widget

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
- Data classes, enums, lists, maps and records in the constructor are supported.
- Add `@RestageProperty` only for what Dart can't express, such as value constraints
  or a theme default.
- Don't annotate `Container`, `Text` or other widgets used inside it.

## Declare the library

Every custom widget must be exported by exactly one library file:

```dart
import 'package:restage/restage.dart';

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

Commit `.restage/library-contracts/` with the catalog identity files. The compiler
compares the declared library contract against these snapshots. Additive capability
changes increase `capabilityVersion`; a breaking contract change also advances
`compatibleSince` to the new capability version. Follow the compiler's exact
version diagnostic and never lower the compatibility floor. These library
capabilities describe installed widget support, not the package's semver policy.

Before the dashboard can show a surface that uses custom widgets, push a build of the
app. `restage build push` makes a personal build that only your own preview uses;
`restage build push --env <env>` updates the build everyone sees. Inspect the selected target before updating its build. Pushing a build is separate
from publishing a surface revision.

## Optional A2UI and Widgetbook output

The same classes can also produce an A2UI catalog and Widgetbook stories. Enable
either emitter independently in `build.yaml`:

```yaml
targets:
  $default:
    builders:
      restage_codegen:user_a2ui_catalog:
        enabled: true
      restage_codegen:widgetbook_stories:
        enabled: true
```

Import `package:restage/a2ui.dart` and `package:restage/widgetbook.dart` with prefixes
for their options, such as `@a2ui.Config.usage('...')` and `@wb.Config.allValues()`.

Leave `bundled_runtime` at its default, `false`; neither emitter requires RFW
surface assets. A2UI catalogs and Widgetbook stories instantiate the Dart widgets,
so they do not prove that the corresponding RFW composition renders correctly.
