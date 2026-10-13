---
name: restage-authoring
description: Integrate Restage into a Flutter app, design surfaces for OTA updates, author screens and flows, connect host behavior, and fix surface compilation or rendering. Use for Dart source and SDK integration; deployed analytics and serving operations belong to restage-operations.
---

# Restage authoring

Build surfaces from ordinary Flutter composition, then mount the generated
`<Name>Surface(...)` widget. Restage delivers data describing that composition;
the installed app supplies Dart behavior. Onboarding, messages, surveys,
paywalls and other screens use the same approach.

## Recommended defaults

- Use generated `*Surface(...)` mounts for typed inputs/events, registration and
  compiled-widget fallback. Every generated mount has an implicit placement;
  `.atPlacement('name', ...)` is only an optional naming override.
- Leave `bundled_runtime` off. The original widget renders when delivered content
  is unavailable; no generated surface assets belong in an ordinary app setup.
  Widgetbook and A2UI emitters also work without bundling.
- Keep the layout and content you want to change OTA in compiler-supported
  composition. `@RestageWidget` components may be inlined or use a native factory;
  the annotation alone does not tell you which. Read
  [surface-design.md](references/surface-design.md) before choosing boundaries.
- Keep purchases, permissions, navigation and other host behavior in app code,
  reached through events or flow host actions. Plan the inputs and events the
  installed app must support before releasing it.
- Fix authored Dart and rebuild. Do not hand-edit generated Dart, RFW or bundles.
  Preserve the identity files `.restage/measurement-state.json` and
  `.restage/wire-ids.events.jsonl`; only make manual entries when the compiler
  gives the exact reconciliation instruction.

## Working sequence

1. Inspect the app's resolved SDK/compiler versions and existing setup. Add
   missing dependencies, then read [setup-and-delivery.md](references/setup-and-delivery.md)
   for generation, hosted configuration, fallback and optional bundling.
2. Choose the surface category and contract, and decide what should change OTA.
   Keep supported composition visible to the compiler; isolate native behavior.
3. Write or update the authored source and run `dart run build_runner build`.
   Use [diagnostics.md](references/diagnostics.md) to fix errors. Review
   `customWidgetAppFactoryUsed` warnings when OTA flexibility matters.
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
| Maximize OTA flexibility; distinguish inlining from native rendering | [Surface design](references/surface-design.md) |
| Typed events, app-owned data and supported authoring patterns | [Surfaces and events](references/surfaces-and-events.md) |
| Library registration, child slots, capabilities, Widgetbook/A2UI | [Custom widgets](references/custom-widgets.md) |
| Branching, state, host actions, typed/general flows | [Flows](references/flows.md) |
| Placement presentation, purchase adapters and runtime controls | [Host integration](references/host-integration.md) |
| Setup, delivery, fallback, app size and optional bundled RFW | [Setup and delivery](references/setup-and-delivery.md) |
| Build failures and identity reconciliation | [Diagnostics](references/diagnostics.md) |

[examples/lib/](examples/lib/) contains a message with host data, a stateful
survey, an onboarding flow and a paywall. Copy the sources into an app with the
SDK and generator dependencies, then generate their Dart parts. The examples
use generated mounts and need no surface assets. Adapt their handlers to the
app; logging a purchase event does not perform a purchase.
