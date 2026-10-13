# Custom widgets

A custom widget is a component from the app, such as a design-system card, added to the
catalog so surfaces can use it next to the built-in Flutter, Material and Cupertino
widgets. Its Dart code is compiled into the app. Surfaces set its properties.

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

A custom widget's code runs from the installed app. Adding a widget, changing its code,
or changing its constructor needs an app release. Raise `capabilityVersion` when a
surface starts depending on such a change, so older apps never receive it.

Before the dashboard can show a surface that uses custom widgets, push a build of the
app with `restage build push`. See [tools.md](tools.md).

## Optional A2UI and Widgetbook output

The same classes can also produce an A2UI catalog and Widgetbook stories. Turn them on in
`build.yaml`:

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
