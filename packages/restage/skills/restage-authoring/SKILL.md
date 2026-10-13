---
name: restage-authoring
description: Adopt existing Flutter widgets as Restage surfaces, configure the SDK, design for OTA updates, author screens and flows, generate GenUI catalogs or Widgetbook stories, connect host behavior, and fix compilation or rendering. Use for Dart source, build settings and SDK integration; deployed analytics and serving operations belong to restage-operations.
---

# Restage authoring

Build surfaces from ordinary Flutter composition, then mount the generated
`<Name>Surface(...)` widget. Restage delivers data describing that composition;
the installed app supplies Dart behavior. Onboarding, messages, surveys,
paywalls and other screens use the same approach.

## Example

A surface is an ordinary widget with an annotation and declared events, from
[weekly_recap.dart](examples/lib/messages/weekly_recap.dart):

<!-- skill-check: example examples/lib/messages/weekly_recap.dart -->
```dart
part 'restage.generated/weekly_recap.restage.g.dart';
// ...
@Screen(id: 'weekly_recap', surface: Surface.message)
final class WeeklyRecap extends StatelessWidget {
  // ...
  static const dismiss = SurfaceEvent<void>('dismiss');
  static const openStats = SurfaceEvent<String>('open_stats');
  // ...
    FilledButton(
      onPressed: surfaceEvent(openStats, 'weekly'),
      child: const Text('See your stats'),
    ),
```

`dart run build_runner build` generates `WeeklyRecapSurface`. The app mounts it
and handles each event, from [main.dart](examples/lib/main.dart):

<!-- skill-check: example examples/lib/main.dart -->
```dart
// The default placement needs no name. Until delivered content is
// available, the mount renders WeeklyRecap itself.
WeeklyRecapSurface(
  name: 'Sam',
  streakDays: 12,
  onEvent: (event) => switch (event) {
    WeeklyRecapDismissEvent() => debugPrint('dismissed'),
    WeeklyRecapOpenStatsEvent(:final value) => debugPrint(
        'open stats: $value',
      ),
  },
),
```

## Recommended defaults

- Mount the generated `*Surface(...)` widget. It takes typed inputs and events,
  registers the surface, and renders the original widget when no delivered
  content is available. It already has a default placement; call
  `.atPlacement('name', ...)` only to give it a different name.
- Leave `bundled_runtime` off. An ordinary app needs no generated surface
  assets, because the original widget is the fallback. Widgetbook and A2UI
  emitters also work without bundling.
- Keep the layout and content you want to change over the air (OTA) in
  composition the compiler supports. The compiler either inlines a
  `@RestageWidget` component or renders it from the app's compiled code; the
  annotation alone does not tell you which. Read
  [surface-design.md](references/surface-design.md) before choosing boundaries.
- Keep purchases, permissions and other host behavior in app code, reached
  through events or flow host actions. Preserve
  [supported Navigator calls](references/flows.md#existing-paywall-navigation)
  between paywalls; other app navigation stays in the host. Plan the inputs and
  events the installed app must support before releasing it.
- Fix authored Dart and rebuild. Do not hand-edit generated Dart, RFW or bundles.
  Keep the identity files `.restage/measurement-state.json` and
  `.restage/wire-ids.events.jsonl` with the source and never delete them. Edit
  them by hand only to add the exact entry a build error tells you to add.

## Working sequence

1. Inspect the app's resolved SDK/compiler versions and existing setup. Add
   missing dependencies, then read [setup-and-delivery.md](references/setup-and-delivery.md)
   for generation, hosted configuration, fallback and optional bundling.
2. Start from the app's existing widget when available. Follow
   [adopting-existing-widgets.md](references/adopting-existing-widgets.md) to
   choose a screen, paywall, flow or reusable component and preserve supported
   composition. Choose the smallest useful delivery boundary.
3. Write or update the authored source and run `dart run build_runner build`.
   Use [diagnostics.md](references/diagnostics.md) to fix errors. When OTA
   flexibility matters, review `customWidgetAppFactoryUsed` notices: each names
   a component that only an app release can change.
4. Mount the generated widget and wire real app handlers. Exercise fallback,
   events and any state or flow behavior touched by the change. Also exercise
   RFW rendering when the change depends on delivered composition; a passing
   fallback test does not prove that path.
5. When the user wants hosted delivery, build before pushing. The optional
   `restage-operations` skill covers inspecting, pushing and publishing; local
   authoring does not require it, an account or a network connection.

## Choose the annotation

| Task | Annotation | Mount |
| --- | --- | --- |
| Independently delivered screen | `@Screen(surface: Surface.message)` or another category | `<Class>Surface(...)` |
| Screen inside a flow | `@Screen()` | Through the generated flow mount |
| Multi-screen flow | `@FlowGraph(surface: Surface.onboarding)` | `<FlowName>Surface(onComplete: ...)` |
| Paywall | `@Paywall()` | `<Class>Surface(onEvent: ...)` |
| Reusable component in a surface | `@RestageWidget()` and library export | Compose it inside the surface |

Categories are `onboarding`, `message`, `survey`, `paywall` and `general`.
`Surface.general` is a category; `FlowDeliveryMode.general` controls structural
flow updates. They are independent choices. Prefer current annotations over the
legacy `@ScreenSource`, `@PaywallSource` and `@FlowSource` names.

Keep `part 'restage.generated/<file>.restage.g.dart';` in each surface library.
Prefer one surface per file; use explicit stable `id:` values when moving files
or declaring several surfaces together.

## Read for the task

| Need | Reference |
| --- | --- |
| Convert existing Flutter UI with minimal source changes | [Adopt existing widgets](references/adopting-existing-widgets.md) |
| Maximize OTA flexibility; distinguish inlining from native rendering | [Surface design](references/surface-design.md) |
| Typed events, app-owned data and supported authoring patterns | [Surfaces and events](references/surfaces-and-events.md) |
| Library registration, child slots and capabilities | [Custom widgets](references/custom-widgets.md) |
| Build order and integration with Flutter GenUI or Widgetbook | [Optional emitters](references/emitters.md) |
| Branching, state, host actions, typed/general flows | [Flows](references/flows.md) |
| Placement presentation, purchase adapters and runtime controls | [Host integration](references/host-integration.md) |
| Setup, delivery, fallback, app size and optional bundled RFW | [Setup and delivery](references/setup-and-delivery.md) |
| Configure delivery, reporting, catalogs and live refresh | [Runtime configuration](references/configuration.md) |
| Builder options, output paths and reusable packages | [Build configuration](references/build-configuration.md) |
| Build failures and identity reconciliation | [Diagnostics](references/diagnostics.md) |

[examples/lib/](examples/lib/) contains a message with host data, a stateful
survey, an onboarding flow and a paywall. Copy the sources into an app with the
SDK and generator dependencies, then generate their Dart parts. The examples
use generated mounts and need no surface assets. Adapt their handlers to the
app; logging a purchase event does not perform a purchase.
