---
name: restage-authoring
description: Use when adding Restage to a Flutter app or writing, changing, mounting, or publishing a Restage surface (onboarding flow, message, survey, paywall, or any screen), a @RestageWidget custom widget, or when fixing restage_codegen build errors. Covers annotations, typed events, generated mounts, host data, flows, over-the-air limits, the build, and the restage CLI and MCP server.
---

# Restage authoring

Restage is server-driven UI for Flutter. A surface is an ordinary Flutter widget with one
annotation. `restage_codegen` compiles its `build()` tree into a surface the app renders,
and generates a typed widget that mounts it. A published version replaces the surface
over the air. The app's compiled Dart code stays the same.

Write surfaces in Dart and let the build compile them. Never hand-write or edit RFW text,
`.rfw` binaries, `.rsbundle` files, or anything under `restage.generated/`,
`lib/*.g.dart` or `.restage/`. Change the Dart source and rebuild.

## Workflow

1. **Check setup.** `pubspec.yaml` needs `restage` in `dependencies`, and
   `restage_codegen` and `build_runner` in `dev_dependencies`. If any is missing, run
   `flutter pub add restage` and `flutter pub add --dev restage_codegen build_runner`.
   Details: [references/setup-and-delivery.md](references/setup-and-delivery.md).
2. **Write or annotate the widget.** Pick the annotation from the table below. Keep the
   `part 'restage.generated/<file>.restage.g.dart';` line in every annotated file.
3. **Build.** Run `dart run build_runner build`. If it stops, fix the source at the
   reported line; [references/diagnostics.md](references/diagnostics.md) maps each
   error code to a fix. Never work around an error by editing generated output.
   Commit what the build changed, including `.restage/measurement-state.json` and
   `.restage/wire-ids.events.jsonl`; they keep analytics ids stable across builds.
4. **Mount the generated widget** (`<ClassName>Surface`) where the surface belongs, and
   handle its events in `onEvent` or `onComplete`.
5. **Verify.** Run `flutter analyze` and the app's tests. A generated mount renders the
   widget you wrote when nothing is published, so the app works before any delivery
   setup. To test the compiled surface itself, bundle it first (*Bundled surfaces* in
   [references/setup-and-delivery.md](references/setup-and-delivery.md)).
6. **Deliver**, only when the user wants to. `restage surface push <id>` uploads a
   version and changes nothing users see. `restage surface publish <id>` makes it live
   for every installed app. **Ask before publishing.** See
   [references/tools.md](references/tools.md).

## Choose the annotation

| You want | Write | Mount with |
| --- | --- | --- |
| A screen published on its own | `@Screen(surface: Surface.message)` (or `onboarding`, `survey`, `general`) | `<Class>Surface(...)` |
| A screen used as a step in a flow | `@Screen()` with no category | the flow's mount |
| A multi-screen flow | `@FlowGraph(surface: Surface.onboarding)` on a top-level `FlowDefinition` | `<FlowName>Surface(onComplete: ...)` |
| A paywall | `@Paywall()` | `<Class>Surface(onEvent: ...)` |
| Your own component, usable inside surfaces | `@RestageWidget()` | used like any widget |

- Categories are `onboarding`, `message`, `survey`, `paywall` and `general`. Use
  `general` for anything that fits none of the others.
- The surface id defaults to the file name. Pass `id:` when the file might move, and on
  every declaration when a file declares more than one surface. Prefer one surface per
  file.
- An id is 1 to 64 characters: lowercase letters, digits, `-` and `_`, starting with a
  letter or digit.
- `@ScreenSource`, `@PaywallSource` and `@FlowSource` are deprecated. Use the names
  above in new code.

## A standalone screen

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

  final String name;
  final int streakDays;

  static const dismiss = SurfaceEvent<void>('dismiss');
  static const openStats = SurfaceEvent<String>('open_stats');

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Nice week, $name', style: textTheme.headlineSmall),
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
- In a standalone `@Paywall()`, fire events with `paywallEvent('name', args: {...})`.
  The generated paywall mount delivers them as `PaywallCustomEvent` with `eventName`
  and `args`. A paywall used as a flow step declares `SurfaceEvent`s for its
  transitions, like any screen.
- A paywall can end as completed rather than dismissed. List the events whose taps
  complete it: `@Paywall(completesOn: [ProUpgradePaywall.startTrial])`, with
  `static const startTrial = SurfaceEvent<void>('start_trial');`. Every other way out
  is recorded as a dismissal. Naming an event that no tap fires stops the build.
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
- A surface can only report what happened. Navigation, purchases, permissions and API
  calls run in app code that reacts to the event. `Navigator`, tap closures such as
  `() => setState(...)` and other inline callbacks in a surface's `build()` stop the
  build. The one exception is a value callback that writes screen state (below).

## Host data

Constructor parameters of a `@Screen` or `@Paywall` class are host data: values the app
passes at mount time, such as a name or a list of items. The generated mount takes the
same parameters. Supported types are `String`, `int`, finite `double`, `bool`, `num`,
`List` and `Map<String, ...>` of those, nullable variants, and plain data classes with
final fields of those types. Reading a parameter of another type (`DateTime`, a
callback, a controller) in `build()` stops the build. Declaring one without reading it
is fine.

Host data stays on the device. Measurement strips it from events, and it is not used
for targeting.

## What the build can compile

Most ordinary Flutter compiles as written. The rules, with what to write instead:

- `build()` may start with `final` or `const` locals, one per statement, and must use
  every local in the returned tree.
- Helper methods and same-library functions that return widgets or values are inlined
  with their arguments. Their body must be one returned expression (optionally after
  `final` locals), every optional parameter must be passed explicitly, and a helper
  can't call itself. For a reusable component, extract a `@RestageWidget` class.
- A widget class of your own used in a surface needs `@RestageWidget()`.
- Constants must be declared in the same file (top-level or `static const`).
- `for` over a list literal or same-file `const` list, collection `if`, and spreads of
  list literals expand at build time. A `for` over a host-data list stays a loop on the
  device. `.map()`, C-style `for`, `...?`, sets, maps and record fields (`item.$1`) are
  not supported.
- Interpolate only `String` values, in one string literal: `'Hello, $name'`. Pass
  numbers as host data to a widget property, or format them into a `String` in the app.
- No `double.infinity`. For full width, use
  `crossAxisAlignment: CrossAxisAlignment.stretch` or `Row(children: [Expanded(...)])`.
- Only catalog properties are accepted. For example, `ListTile` has no `selected`.
  The error lists the properties that exist.
- `Theme.of(context)` reads stay live and follow the app's theme.
- Screen state: a `StatefulWidget` surface may keep `String`, `int`, `double` and
  `bool` fields in its `State`, each with a literal initial value.
  - A value callback writes the value as is:
    `onChanged: (value) => setState(() => note = value)` on a `TextField`,
    `CupertinoTextField`, `Switch`, `Slider` or other value widget. Anything else in
    the callback, such as `value.trim()`, stops the build.
  - A named method with one assignment inside `setState`, passed by reference
    (`onTap: pickGood`), also changes a field. On a field a value callback writes, it
    can only assign a literal, such as a Clear button setting `''`.
  - Reads of the field show its current value. Send it to the app with an event:
    `surfaceEvent(submit, {'note': note})`. What the user types stays on the device
    and is never measured.

  See [examples/lib/surveys/mood_check.dart](examples/lib/surveys/mood_check.dart).
- `TextField` takes `decoration: InputDecoration(...)` with `hintText`, `labelText`,
  `helperText`, `prefixIcon: Icon(...)` and `border` (`InputBorder.none`,
  `UnderlineInputBorder()` or `OutlineInputBorder()`). Other decoration fields stop
  the build. `keyboardType` takes a named `TextInputType` (`text`, `multiline`,
  `number`, `phone`, `emailAddress`, `url`, `name`), and `textInputAction` a
  `TextInputAction`. `CupertinoTextField` takes `placeholder`, `keyboardType` and
  `textInputAction`.
- Gestures, painting and animation belong in compiled widgets: a `@RestageWidget` of
  your own, or catalog widgets such as `RestageModalSheet`, `RestageDraggableSheet` and
  `RestagePager`.

## Flows

```dart
@FlowGraph(id: 'first_run', surface: Surface.onboarding)
const firstRun = FlowDefinition(
  start: WelcomeStep,
  state: [goal],
  transitions: [
    Transition(WelcomeStep.next, to: GoalStep),
    Transition(GoalStep.pick, capture: goal, to: ReadyStep),
    Transition.complete(ReadyStep.finish),
  ],
  outbound: FlowOutboundPolicy(terminalResult: {'goal': goal}),
);
```

Each step is a `@Screen()` in its own file. The build generates `firstRunRef`, a typed
`FirstRunResult`, and `FirstRunSurface(onComplete: (result) => ...)`. Answers,
decisions, host actions, seeded state, subflows and over-the-air graph changes are
covered in [references/flows.md](references/flows.md).

## Custom widgets

Annotate your own component with `@RestageWidget()` and export it from one library file
that declares a `WidgetLibrary` and `@RestageLibrary`. The public constructor defines
its properties and doc comments describe them. Surfaces then use it like any other
widget. Generated mounts install the custom widgets their surface draws, so no
startup call is needed. See [references/custom-widgets.md](references/custom-widgets.md).

## What an update can change without an app release

A published version can change layout, copy, styling, and how surfaces compose the
widgets the installed app already has: the built-in catalog plus your registered custom
widgets. It can also change what flow screens show, and use any icon from the Material
and Cupertino icon fonts or an icon font your app's packages declare: the surface
carries the icons it names. An icon chosen from host data at run time must be one the
app itself draws.

These need a new app build:

- a new or changed `@RestageWidget` (its Dart code runs in the app);
- new or changed events, host-data parameters, host actions, or flow results;
- a different graph for a typed flow (declare `delivery: FlowDeliveryMode.general` to
  change the graph over the air);
- any new behavior, since surfaces carry data and no code.

Treat events, host data and results as the contract between a surface and the app.
The SDK refuses a published version that needs something the installed app lacks, and
shows the compiled-in widget instead. Apps built with an older SDK also refuse versions
that use delivered icons, screen state written by value callbacks, per-item taps,
paywall completion, or answers on onboarding and message flows.

## Delivery and tools

- Without `Restage.configure(apiKey: ..., baseUrl: ...)`, generated mounts render the
  widget you wrote. With it, paywalls and standalone screens fetch the live published
  version. Flows also need `flowResolver: ServerFlowResolver(..., active: true)`.
- A mount waits up to the render deadline, `renderDeadline:` (300 ms by default), for
  the published version. Then it shows the last published version saved on the device,
  the bundled copy, or the widget you wrote, and saves what arrives for the next mount.
  Pass `surfaces: restageSurfaces` (generated in `lib/restage_surfaces.g.dart`) to
  fetch every surface as the app starts.
- Measurement is on by default with hosted delivery. Don't add tracking calls for
  surface interactions. `measurementEnabled: false` (a constant) switches it off.
- The `restage` CLI pushes and publishes. The `restage_mcp` MCP server gives an agent
  project context: surface status, history, funnels, routing and builds. See
  [references/tools.md](references/tools.md).

## Examples

[examples/lib/](examples/lib/) is a complete app that compiles with the current SDK:
a message with host data and a custom widget, a survey with a selection and a typed
note, a three-step onboarding flow that records an answer, a paywall that completes on
its start-trial tap, the widget library file, and `main.dart` mounting all of them.

## Keeping this skill current

This skill ships inside the `restage` package. After upgrading `restage`, refresh it
with `dart run skills@ get --package restage --all`.
