# Surfaces, host data and events

## A standalone screen

<!-- skill-check: example ../examples/lib/messages/weekly_recap.dart -->
```dart
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import '../app_widgets.dart';

part 'restage.generated/weekly_recap.restage.g.dart';

const kHighlights = ['Longest session', 'Most active day', 'New habits'];

/// A standalone message that shows data the app already has.
@Screen(id: 'weekly_recap', surface: Surface.message)
final class WeeklyRecap extends StatelessWidget {
  const WeeklyRecap({super.key, required this.name, required this.streakDays});

  /// Display name for the recap greeting.
  final String name;

  /// Consecutive days of activity shown in the badge.
  final int streakDays;

  static const dismiss = SurfaceEvent<void>('dismiss');
  static const openStats = SurfaceEvent<String>('open_stats');

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Nice week, $name'),
          const RecapHeading(title: 'Weekly highlights'),
          const SizedBox(height: 12),
          StreakBadge(days: streakDays),
          const SizedBox(height: 12),
          for (final highlight in kHighlights) Text(highlight),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: surfaceEvent(openStats, 'weekly'),
            child: const Text('See your stats'),
          ),
          TextButton(
            onPressed: surfaceEvent(dismiss),
            child: const Text('Not now'),
          ),
        ],
      ),
    );
  }
}
```

The build generates `WeeklyRecapSurface`, a sealed `WeeklyRecapEvent` with one class per
event (`WeeklyRecapDismissEvent`, `WeeklyRecapOpenStatsEvent`), and `weeklyRecapRef`:

<!-- skill-check: expression -->
```dart
WeeklyRecapSurface(
  name: user.firstName,
  streakDays: stats.streak,
  onEvent: (event) => switch (event) {
    WeeklyRecapDismissEvent() => Navigator.of(context).maybePop(),
    WeeklyRecapOpenStatsEvent(:final value) => openStats(value),
  },
)
```

Event class names are the screen class name, then the event field name in
UpperCamelCase, then `Event`.

## Events

- Declare each event once as a `static const` `SurfaceEvent<T>` field on the surface
  class. `T` is `void` or the value type it carries.
- Pass `surfaceEvent(event)` or `surfaceEvent(event, value)` directly as the callback,
  for taps and value callbacks alike: `onPressed: surfaceEvent(dismiss)`,
  `onChanged: surfaceEvent(pick)`. When the widget passes a value (a Switch, a
  TextField), that value is the event's value.
- An event can carry a map: `surfaceEvent(submit, {'mood': mood, 'note': note})`
  with `SurfaceEvent<Map<String, Object?>>`. The generated class exposes it as
  `arguments`.
- Don't wrap it in a closure: `() => surfaceEvent(...)` returns the callback without
  calling it, so the event never fires when your own widget shows. The build warns.
- In a standalone `@Paywall()`, fire events with `paywallEvent('name', args: {...})`
  or with `surfaceEvent(event)` and a declared `SurfaceEvent`. The generated paywall
  mount delivers them as `PaywallCustomEvent` with `eventName` and `args`; a
  `surfaceEvent` value arrives as `args['value']`. The names `purchase`, `restore`
  and `restage.purchase…`/`restage.restore…` are reserved; use names such as
  `restore_purchases`. A paywall used as a flow step declares `SurfaceEvent`s for its
  transitions, like any screen.
- `@Paywall(completesOn: [ProUpgradePaywall.startTrial])` marks that tap as a
  completed interaction for measurement. Declare the event with
  `static const startTrial = SurfaceEvent<void>('start_trial');`. The host still
  performs purchases and navigation; this does not close a route or advance a
  flow. Other exits are recorded as dismissals. Naming an event that no tap fires
  stops the build. A tap on your own `@RestageWidget`'s callback counts, including
  one inside a wrapper widget's `Widget` child.
- For a parent `GestureDetector` that owns the tap over a child with its own,
  wrap the child in `IgnorePointer` and set `behavior: HitTestBehavior.opaque`;
  without it the detector misses taps the ignored child would have received.
- The dashboard and MCP name each tap from a `Semantics(label: ...)` around it, or
  else from its text, its tooltip, then its icon. Wrap a tap in
  `Semantics(label: 'Choose plan')` to name it yourself.
- Taps inside a `for` loop are counted per item. In a loop over a list literal or a
  same-file `const` list, the item is the element's `key: ValueKey('...')` or its
  position. In a loop over a host-data list of objects or maps, the item is the
  element's position. Loops over a host-data list of strings or numbers keep one
  count for all their taps; `dart run build_runner build --verbose` shows the build's
  note on why.
  Value callbacks never carry an item.
- Handle purchases, permissions, API calls and app navigation in app code that
  receives the event. Use flow transitions and host actions for work inside a flow.
  Supported declarative state callbacks and bounded Navigator calls can also compile;
  arbitrary callback bodies cannot. See the state section below and
  [flows.md](flows.md).

## Host data

Constructor parameters of a `@Screen` or `@Paywall` class are host data: values the app
passes at mount time, such as a name or a list of items. The generated mount takes the
same parameters. Supported types are `String`, `int`, finite `double`, `bool`, `num`,
`List` and `Map<String, ...>` of those, nullable variants, and plain data classes with
final fields of those types and a const constructor. List elements must have a
concrete non-nullable type; map keys must be non-nullable `String`. Reading a
parameter of another type (`DateTime`, a callback, a controller) in `build()` stops
the build. Declaring one without reading it is fine. A parameter read by the
compiled tree cannot have a non-null default; make it required and supply the
default at the host call site.

Host render data stays on the device. It is separate from audience-routing inputs,
and is not copied into measurement events. Pass only the values the surface needs;
keep services, controllers and formatting logic in app code.

## Composition and helpers

Keep `build()` to one returned expression, optionally preceded by initialized
`final` or `const` locals, one per statement. Each local must contribute to the
returned tree. Theme reads such as `Theme.of(context).colorScheme` remain live.

Keep supported helpers where they are. The compiler can inline the widget's own
helper methods and top-level or static helpers from other files in the same
package, including prefixed imports. Normal Dart visibility still applies. For
example, an existing helper can stay:

<!-- skill-check: members -->
```dart
Widget _item(String label) =>
    ListTile(leading: const Icon(Icons.check), title: Text(label));

@override
Widget build(BuildContext context) => Column(
      children: [_item('Dark mode'), _item('Faster sync')],
    );
```

Their bodies follow the same single-return rule. Pass every helper parameter,
including optional parameters, explicitly. Recursive helpers, arbitrary instance
method calls and unsupported helper bodies cannot compile. Helpers from a
dependency package can also inline when that package supplies custom widgets in
the installed catalog. Reusable widget classes need `@RestageWidget()`; supported
composition is inlined, while a native factory is used when required. See
[surface-design.md](surface-design.md) before choosing that boundary.

## Conditions and lists

Use conditional expressions, collection `if`, and collection `for` for display
decisions. Conditions can use supported host-data or screen-state reads; they do
not all have to be constants. For example, inside a surface with `bool isPro` and
`String plan` constructor fields:

<!-- skill-check: expression -->
```dart
Column(
  children: [
    if (isPro) Text(plan == 'annual' ? 'Annual member' : 'Member'),
  ],
)
```

- A loop over a list literal or a same-file `const` list expands at build time.
- A loop over a host-data list renders the current items on the device:
  `children: [for (final label in labels) Text(label)]`.
- Supported runtime conditions also work inside host-data loops.
- Static list spreads preserve their elements. C-style loops, null-aware spreads,
  set iteration and arbitrary `.map()` calls are not substitutes for collection
  `for`.
- Runtime string interpolation requires non-null `String` values: host data,
  `State` fields, `final` locals in `build()`, or conditions over them. A `Text`, a
  built-in widget's `String` property and the `String` property of a custom widget
  your app renders can join text and values (`label: 'Only $price a year'`). In a
  value object such as a `TextStyle`, pass the finished string. Format prices, dates
  and counts in app code before passing them in.

Keep numeric values finite. Use `CrossAxisAlignment.stretch` or `Expanded` for
available width instead of `double.infinity`. The compiler lists supported
properties when a catalog widget cannot accept an argument.

## Local screen state

Use a `StatefulWidget` surface for temporary selections and text entry. Supported
state fields are `bool`, `int`, `double`, `num`, `String` and enums with non-null
constant initializers. Controllers, subscriptions, lifecycle methods and network
work belong in app code or a focused native widget.

A value callback can store its incoming value directly:

<!-- skill-check: example ../examples/lib/surveys/mood_check.dart -->
```dart
String note = '';
// ...
TextField(
  // ...
  onChanged: (value) => setState(() => note = value),
),
```

Do transformations such as `trim()` in the app when it receives the result. A
named method can perform one supported state assignment and be passed by reference:

<!-- skill-check: example ../examples/lib/surveys/mood_check.dart -->
```dart
bool good = true;
// ...
void pickGood() => setState(() => good = true);
// ...
ListTile(
  title: const Text('Good'),
  // ...
  onTap: pickGood,
),
```

If a field is also written by a value callback, a named handler can only reset it
to a literal. Submit the current state through an event, such as
`surfaceEvent(submit, {'note': note})`. Free text is app data, not a measured answer.
The complete [survey example](../examples/lib/surveys/mood_check.dart) combines
selection, text entry and typed events.

For text inputs, use the supported `InputDecoration` fields (`hintText`,
`labelText`, `helperText`, `prefixIcon` and supported borders), named `TextInputType`
values and `TextInputAction`. The compiler reports unsupported settings. Prefer a
small native input component when a required behavior cannot be expressed by these
controls; keep the rest of the form in the surface.
