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
            onPressed: context.surfaceEvent(openStats, 'weekly'),
            child: const Text('See your stats'),
          ),
          TextButton(
            onPressed: context.surfaceEvent(dismiss),
            child: const Text('Not now'),
          ),
        ],
      ),
    );
  }
}
```

The build generates `WeeklyRecapSurface`, a sealed `WeeklyRecapSurfaceEvent` with one class per
event (`WeeklyRecapSurfaceDismissEvent`, `WeeklyRecapSurfaceOpenStatsEvent`), and `weeklyRecapRef`:

<!-- skill-check: expression -->
```dart
WeeklyRecapSurface(
  name: user.firstName,
  streakDays: stats.streak,
  onEvent: (event) => switch (event) {
    WeeklyRecapSurfaceDismissEvent() => Navigator.of(context).maybePop(),
    WeeklyRecapSurfaceOpenStatsEvent(:final value) => openStats(value),
  },
)
```

Event class names are the screen class name, then `Surface`, then the event field
name in UpperCamelCase, then `Event`.

## Events

- Make things happen with plain Flutter callbacks first: `final VoidCallback? onClose;`
  and `onPressed: onClose`, or a closure such as `() => cubit.purchase(plan)`. The
  generated mount takes the same callbacks and hands your closures to the delivered
  design. Use a typed event when Restage acts on the tap: a flow step's outcome, an
  outcome a flow or placement routes, or a paywall's `completesOn` event.
  A design you'll deliver into more than one placement fires typed events; app
  callbacks tie it to its own mount.
- Declare each event once as a `static const` `SurfaceEvent<T>` field on the surface
  class. `T` is `void` or the value type it carries.
- Declare an event several surfaces fire once, in a shared class such as
  `abstract final class CommonEvents { static const dismiss = SurfaceEvent<void>('dismiss'); }`.
  A shared widget fires `context.surfaceEvent(CommonEvents.dismiss)`, and the event
  joins the contract of each surface that shows it; don't declare it again. A widget
  the build never reads, such as one the app passes in at run time, still needs the
  surface to declare each event it fires.
- A dialog or sheet a surface opens fires on that surface. A page route doesn't: wrap
  the pushed page in `InheritedTheme.capture(from: context, to:
  Navigator.of(context).context).wrap(...)`. Don't wrap a paywall's push to another
  `@Paywall` screen; the delivered paywall shows that screen.
- Pass `context.surfaceEvent(event)` or `context.surfaceEvent(event, value)` directly as the callback,
  for taps and value callbacks alike: `onPressed: context.surfaceEvent(dismiss)`,
  `onChanged: context.surfaceEvent(pick)`. When the widget passes a value (a Switch, a
  TextField), that value is the event's value.
- An event can carry a map: `context.surfaceEvent(submit, {'mood': mood, 'note': note})`
  with `SurfaceEvent<Map<String, Object?>>`. The generated class exposes it as
  `arguments`.
- Don't wrap it in a closure: `() => context.surfaceEvent(...)` returns the callback without
  calling it, so the event never fires when your own widget shows. The build warns.
- A standalone `@Paywall()` makes things happen with plain callbacks, such as
  `final VoidCallback? onClose;` and `onPressed: onClose`. The generated mount takes the
  same callbacks and hands your closures to the delivered paywall. Fire a typed event
  only when Restage acts on it: a flow step's outcome, an outcome a flow or placement
  routes, or an event in `completesOn`. The generated paywall mount delivers a typed
  event as `PaywallCustomEvent` with `eventName` and `args`; a map value is its `args`
  and any other value arrives as `args['value']`. The names `purchase`, `restore`
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
concrete non-nullable type; map keys must be non-nullable `String`. A parameter of
another type, such as a callback or a controller, can also be read in `build()`, for
example `onPressed: onBuy`: the object stays in the app, and the design refers to it.
Parameters can have defaults; the generated mount takes the same defaults.

Host render data stays on the device. It is separate from audience-routing inputs,
and is not copied into measurement events. Pass only the values the surface needs;
keep services, controllers and formatting logic in app code.

## Composition and helpers

Write `build()` as you would for any Flutter widget. It can declare locals, run
statements, loop, branch with `if` and `switch`, use `try` and `catch`, and
return early. End `build()` with a `return` of the widget tree, or with a
statement that returns on every path, such as a `switch` whose cases return. An
arrow body also works.

The generated widget runs your build's statements as written: once per build,
in order. An exception is thrown or caught where your app throws or catches it.
Each value the surface shows is taken where your build computes it, and the
surface shows the `return` your build took. A `return` can read any local your
build declares, including pattern variables, `catch` clause variables, loop
variables and a classic `for` loop index that the loop body changes. Theme reads
such as `Theme.of(context).colorScheme` remain live.

A design published later can read a value only where your build computes it.
For example, if `build()` returns early when `offer` is null and reads
`offer.features` after that, a design can show the features only where it shows
the later `return`. `restage surface push` names each app build that can't
show such a design, and why. Publishing a delivery plan that serves it to those
builds asks you to confirm first. Those builds keep showing what they showed
before.

Restage reserves names that start with `_restage` for the code it generates, so
the build can't declare or read them. A statement that the generated widget
can't copy, such as `super.build(context)`, stops the build with its location;
move it into a method of the surface class or its `State`. In a `State`'s build,
a call the generated widget can't make, such as `debugPrint(...)`, also stops
the build and names the call; make the call through a method of the `State`.

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

To inline, a helper's body must be one returned expression, optionally after
initialized `final` or `const` locals. Pass every helper parameter,
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
`context.surfaceEvent(submit, {'note': note})`. Free text is app data, not a measured answer.
The complete [survey example](../examples/lib/surveys/mood_check.dart) combines
selection, text entry and typed events.

For text inputs, use the supported `InputDecoration` fields (`hintText`,
`labelText`, `helperText`, `prefixIcon` and supported borders), named `TextInputType`
values and `TextInputAction`. The compiler reports unsupported settings. Prefer a
small native input component when a required behavior cannot be expressed by these
controls; keep the rest of the form in the surface.
