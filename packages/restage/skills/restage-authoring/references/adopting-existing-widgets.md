# Adopt existing Flutter widgets

Start with the Flutter UI the app already has. Keep its layout, theme, data and
supported local state; add the delivery boundary where OTA changes are useful.
Often the source change is an import, a generated part and an annotation, followed
by mounting the generated widget. Adapt unsupported behavior only where needed.

## Choose what Restage owns

Choose the smallest useful subtree. An existing page can keep its navigation,
state owner and services while a child becomes a surface. Keep the app's outer
APIs and business functions; extract a presentational child only when needed to
separate those responsibilities. A whole widget that already compiles needs no
extra split.

| Existing UI and intended behavior | Choice |
| --- | --- |
| One independently delivered message, survey or other screen | `@Screen(surface: Surface.message)` or the appropriate category; mount `<Class>Surface(...)` |
| An offer needing paywall lifecycle, completion measurement or purchase-adapter handlers | `@Paywall()`; mount `<Class>Surface(onEvent: ...)` and keep purchases in the host |
| Several screens whose sequence and transitions Restage should own | `@Screen()` steps and an `@FlowGraph(surface: ...)` definition; mount the generated flow |
| A reusable app component used inside surfaces | `@RestageWidget()` plus its library export; compose it inside a screen |

Choose the category by purpose, separately from who owns the interaction:

| Category | Typical purpose |
| --- | --- |
| `Surface.message` | Announcement, banner or prompt |
| `Surface.survey` | Questions and answers |
| `Surface.onboarding` | First-run introduction or setup |
| `Surface.paywall` | Purchase offer or upgrade experience |
| `Surface.general` | An experience without a specialized category |

`Surface` is an enum, not an `@Surface` annotation. A categorized `@Screen` is
independent; a bare `@Screen()` is a flow step. The annotation marks the authored
widget; the generated `*Surface` widget is the app's delivery mount.

`@Paywall()` supplies paywall lifecycle events and the `PaywallCustomEvent`
contract used by supplied purchase-event handlers. Purchase execution stays in
the app; an adapter is optional. `completesOn` records completion for measurement;
it does not navigate or advance a flow. `@Screen(surface: Surface.paywall)` uses
the generic typed-event screen host with a paywall category. A message mentioning
an upgrade can remain a message. See [host-integration.md](host-integration.md).

Existing `@Paywall` navigation can already compile into a flow. Check the
[supported Navigator forms](flows.md#existing-paywall-navigation) before
rewriting working `push`/`pop` callbacks as events or a `FlowDefinition`. Keep
the generated entry paywall mount; no explicit `@FlowGraph` is needed for this
automatic conversion.

Choose a flow when Restage should own the journey, not merely because the app has
several routes. Existing app navigation can continue to present individual
surfaces. Flow category and delivery mode are separate. Flows default to typed,
with a fixed graph and typed result; `FlowDeliveryMode.general` allows structural
updates within the installed contract. See [flows.md](flows.md).

Use bare `@Screen()` for reusable flow steps. Categorized screens must match the
flow's category; `@Paywall()` can be a step in any category. An embedded paywall
uses flow events, so standalone purchase handlers are not directly interchangeable.
Use a flow host action when the graph must await a purchase or service result.

## Keep the existing composition

For example, `lib/welcome_banner.dart` already contains:

<!-- skill-check: file reference_fragments/welcome_banner_before.dart -->
```dart
import 'package:flutter/material.dart';

/// A greeting displayed in the app.
final class WelcomeBanner extends StatelessWidget {
  const WelcomeBanner({super.key, required this.name});

  /// Name used in the greeting.
  final String name;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Text(
      'Welcome, $name',
      style: Theme.of(context).textTheme.bodyLarge,
    ),
  );
}
```

After adding the dependencies in [setup-and-delivery.md](setup-and-delivery.md),
make this change to that file:

```diff
 import 'package:flutter/material.dart';
+import 'package:restage/restage.dart';
+
+part 'restage.generated/welcome_banner.restage.g.dart';

 /// A greeting displayed in the app.
+@Screen(id: 'welcome_banner', surface: Surface.message)
 final class WelcomeBanner extends StatelessWidget {
```

The constructor, field and `build()` body stay as they were. Run
`dart run build_runner build`, then change the app's mount:

```diff
-WelcomeBanner(name: user.name)
+WelcomeBannerSurface(name: user.name)
```

The generated mount accepts the existing data and uses the original widget as
its compiled fallback after successful generation; unsupported source must first
be fixed, not left to runtime fallback. Theme reads remain live. It already has an
implicit placement; no `.atPlacement(...)` call is needed. Leave `bundled_runtime` off:
no surface assets, upload or publication are needed to run the fallback locally.

## Adapt behavior at its existing boundary

Keep supported constructor values as host data. Read services and app state in
their existing owner, then pass the values the UI needs. A constructor parameter
read by the compiled tree cannot currently have a non-null default; make it
required and supply that default at the host call site. Unsupported values such
as controllers stay in the host or a focused native component.

If callers depend on an existing constructor or callback API, keep that API on
the host widget and pass its resolved values and handlers across this boundary.

Preserve supported helpers and local state. A simple selection or text-entry
`StatefulWidget` does not need a rewrite into a stateless view. Supported primitive
or enum state with constant initializers and supported `setState` assignments can
stay. Lifecycle work, subscriptions and arbitrary imperative callback bodies
need a host or native boundary. See
[surfaces-and-events.md](surfaces-and-events.md) for the exact supported patterns.

When an existing callback performs app work, keep that function and connect an
event to it. For a button previously using `onPressed: onContinue`, declare on the
screen class:

<!-- skill-check: members -->
```dart
static const next = SurfaceEvent<void>('next');
```

Use `onPressed: surfaceEvent(next)` in the same button. Replace its callback
constructor input with the generated event handler at the app's mount:

<!-- skill-check: expression -->
```dart
WelcomeBannerSurface(
  name: user.name,
  onEvent: (event) {
    if (event is WelcomeBannerNextEvent) onContinue();
  },
)
```

The app's `onContinue` can keep its existing navigation or business logic. Pass
`surfaceEvent(next)` directly; `() => surfaceEvent(next)` only returns a callback.
This adaptation is for host behavior, not a requirement to replace supported
local state callbacks. Paywalls use their paywall event contract, and flows can
use transitions and host actions; follow the relevant guide for those cases.

## Keep composition available for updates

Use the existing standard Flutter widgets and supported helpers. Do not annotate
built-in leaves, flatten working helpers or register the whole page as one native
widget to bypass compilation. Existing reusable app widgets can be declared with
`@RestageWidget()` and a [library export](custom-widgets.md). The compiler tries
to inline their supported composition; a native factory preserves only its
exposed inputs and child slots as update points.

Use diagnostics to change the smallest unsupported expression or component.
Keep native boundaries around behavior that needs them, such as an animation,
controller or platform view, while leaving the surrounding layout in the surface.
See [surface-design.md](surface-design.md) to inspect what actually compiled.

## Verify the conversion

1. Generate and fix source diagnostics; do not edit generated output.
2. Mount without delivered content or bundled assets. Confirm the original widget
   renders with the same data, theme and behavior.
3. Exercise delivered RFW separately and assert that it rendered rather than
   falling back. Check the same inputs, interactions and state changes.
4. Review the emitted composition and any `customWidgetAppFactoryUsed`
   diagnostics. Confirm that the parts intended for OTA updates are represented
   in RFW and that the installed app supports their contract.
