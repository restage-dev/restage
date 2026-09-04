# Flow navigation & customization

Where a flow's navigation controls come from, how flow navigation and back
behave, how to choose between the high-level and low-level rendering surfaces,
and the compliance boundary that holds however you compose them.

This covers `RestageFlowGraph` (the normal full flow surface),
`RestageFlowView` (the lower-level compositor), and `RestageScreenView` (the
current-screen rendering surface). All of them render the same flow document
driven by the same `RestageFlowController`.

## Navigation controls come from your screens

A flow surface draws no back control, no skip control and no bar of its own. The
runtime moves between screens and keeps the history; what the user taps is app
structure you place.

The usual place is an app bar. Put an `AppBar` (Material) or a
`CupertinoNavigationBar` (Cupertino) in a screen and it shows the platform back
control whenever the flow has a screen behind the current one.

```dart
@Screen()
final class GoalScreen extends StatelessWidget {
  const GoalScreen({super.key});

  static const next = SurfaceEvent<void>('next');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: const Text('What brings you here?'),
          ),
          Expanded(
            child: Center(
              child: FilledButton(
                onPressed: surfaceEvent(next),
                child: const Text('Continue'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

The bar is the first child of the body, because the catalog's `Scaffold` has no `appBar` slot. `AppBar` takes the status-bar inset itself, so the rest of the body sits below it. Wrap that rest in `SafeArea(top: false)` so the inset is applied once.

The screen is ordinary Flutter and compiles to a render blob like any other.
`AppBar` and `CupertinoNavigationBar` are catalog widgets, so the bar you author
is delivered with the rest of the screen and shows the control a compiled screen
shows.

### The mechanism: the screens are routes

The surface hosts its screens on a `Navigator` of its own: one route per screen
visit in-flow back can still reach, kept mounted so back restores the screen
rather than re-decoding it. A screen with another behind it reports `canPop`, and
`AppBar` and `CupertinoNavigationBar` derive their leading control from that with
`automaticallyImplyLeading` at its default.

Everything that pops that route pops exactly one flow screen: the bar's own back
control, `Navigator.maybePop`, the Android system-back gesture, Android's
predictive back and the iOS leading-edge swipe. The last two are the route's own,
so they preview the prior screen and complete the same pop. Exactly one level
owns the gesture at a time: while the flow has a screen to go back to the flow's
screen owns it and the enclosing route stands down, and once in-flow back is
exhausted the enclosing route has it again.

Screens move with the app's `pageTransitionsTheme`, like any other route, and a
`Hero` flies between them. Supply a `transition` to replace that motion for one
flow.

Two cases show nothing, both correct. A screen with no app bar has no back
control. The first screen of a sub-flow has none either, because a sub-flow
boundary is a barrier. The first screen of a flow has no screen behind it, so its
app bar shows a control only when the enclosing route can be dismissed, and that
control leaves the flow. A flow mounted outside any route renders normally.

The surface needs bounded constraints, like any `Navigator`. Make it the body of
a `Scaffold`, or give it an `Expanded` or a sized box.

## Drawing your own control

`RestageFlowController` carries what a control needs.

| Member | Meaning |
|---|---|
| `canBack` | whether there is a prior screen in this frame |
| `back()` | pop screen history (a no-op when `canBack` is false) |
| `canSkip` | whether the current screen has a skip destination |
| `skip()` | route the reserved `skip` event |
| `currentScreenId` | the current screen's state id (null when no screen is mounted) |
| `isComplete` | whether the flow has finished |
| `isBusy` | whether a transition or host action is in flight |

The controller is a `Listenable`, so read it inside a `ListenableBuilder` and the
control follows the flow.

```dart
ListenableBuilder(
  listenable: controller,
  builder: (context, _) => Row(
    children: [
      if (controller.canBack)
        IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: controller.back,
        ),
      const Spacer(),
      if (controller.canSkip)
        TextButton(
          onPressed: controller.skip,
          child: const Text('Skip'),
        ),
    ],
  ),
)
```

A control drawn this way needs a controller the app owns, so mount the flow with
`RestageFlowView` and compose around it. Wrapping the view frames the whole flow:
the control stays put while screens animate beneath it. `_backControl` below is
the `ListenableBuilder` above.

```dart
Stack(
  children: [
    Positioned.fill(
      child: RestageFlowView<FirstRunResult>(controller: controller),
    ),
    Positioned(top: 0, left: 0, child: _backControl(controller)),
  ],
)
```

A custom control owns its own `Semantics`. An `IconButton`'s `tooltip`, or a
`Semantics(button: true, label: 'Back')` wrapper, keeps it screen-reader
reachable. An `AppBar` back control already carries its label.

A control authored inside a screen fires an event like any other. Give it the
reserved `back` event and it pops screen history with no transition to write:

```dart
static const back = SurfaceEvent<void>('back');
```

There is deliberately **no "step N of M"**: a flow can branch (decision states,
sub-flows), so a total step count is not knowable in general. A progress
indicator is the author's to derive: you authored the flow's shape and have
`currentScreenId`.

## Skip

Skip has no platform affordance to inherit, so it is always a control you draw.
`controller.skip()` routes the reserved `skip` event: an authored `on['skip']`
transition takes it, otherwise the declared `outbound.customEvents['skip']` is
emitted for the host to handle, commonly to dismiss the flow. `canSkip` is false
when the screen has neither, which is the signal to leave the control out rather
than show a dead one.

Inside a delivered screen, the natural place for skip is the app bar: a
`TextButton` in `AppBar.actions`, or a `CupertinoButton` in
`CupertinoNavigationBar.trailing`, wired to a `SurfaceEvent<void>('skip')`. The
runtime routes it exactly as `controller.skip()` does.

## Dismissing the flow from a host control

`Navigator.maybePop` on the host route pops one flow screen while the flow has
one to go back to. That is what an app bar's back control relies on. A close
control that should leave the flow regardless of where the user is calls `pop`,
which dismisses the route in one step:

```dart
void dismissFlow(BuildContext context) => Navigator.of(context).pop();
```

Call it from a context outside the flow surface, so `Navigator.of` resolves to
the host route rather than the flow's own navigator.

Completion needs none of this. The controller finishes before it calls
`onComplete`, so `Navigator.maybePop` inside that callback pops the route.

## Back navigation

Back follows screen history the way a `Navigator` does:

- **History.** Each screen visit is recorded; back pops to the prior screen, with
  its state preserved (the kept-mounted screen instance is restored, not
  re-decoded). `canBack` reflects whether there is a prior screen.
- **Decision/action states are skipped.** Decision and action states run *between*
  screens and are never recorded on the back-stack, so back pops to the prior
  *screen* and never re-runs a transition or re-fires a host action.
- **Barriers are structural.** A sub-flow boundary is an automatic barrier (a
  child flow's back never reaches into its parent); `canBack` is false on a
  frame's first screen. A completed flow does not navigate (`canBack` / `canSkip`
  are false).
- **Back is a pure pop.** The app bar's back control, a drawn control calling
  `controller.back()`, and the platform system-back gesture all pop screen
  history; they never run a side-effecting authored action.

### System back when in-flow back is exhausted

While there is screen history, the platform system-back gesture pops one screen
from the flow's own navigator. When in-flow back is exhausted (the first
screen, or a barrier), a `systemBack` policy (`SystemBackPolicy`) decides what
happens:

| Policy | Behavior |
|---|---|
| `SystemBackPolicy.popHost` (default) | let system-back reach the host route (the host's own structure decides: dismiss a pushed route, or the platform's "back at root" behavior) |
| `SystemBackPolicy.block()` | trap it; back at the first screen is a no-op (a mandatory flow) |
| `SystemBackPolicy.complete()` | treat exhausted back as completing/dismissing the flow (requires a skip destination: a declared `customEvents['skip']` or `on['skip']`; without one, exhausted back is a no-op) |
| `SystemBackPolicy.onExhausted(callback)` | a callback escape hatch for bespoke handling |

The policy governs only the exhausted case. While the flow can still go back, the
surface takes the gesture and pops one screen under every policy.

### The iOS edge-swipe and Android predictive back

Both are Flutter's, on the flow screen's own route. Dragging from the leading
edge on iOS previews the prior screen; an Android predictive-back drag does the
same with the platform's own motion. Completing the drag performs the same pure
history pop as an app bar's back control, and cancelling leaves the current
screen in place.

While the flow has a screen to go back to, the enclosing route's gesture is off,
so the two are never live together. Once in-flow back is exhausted (the first
screen, or a barrier), the enclosing route owns the gesture again according to
the `systemBack` policy. With the default `SystemBackPolicy.popHost`, the host
route's own gesture dismisses the flow route.

## Two flow→paywall navigation patterns

There are two ways to structure "onboarding, then a paywall." Pick by whether the
two are distinct stages or one continuous flow.

### Pattern A: handoff (the host navigates)

The flow reaches an end state, `onComplete` fires, and the **host** navigates to
a separate paywall surface. The completed flow does not navigate, so the user
cannot back into onboarding from the paywall. Use this when onboarding and the
paywall are distinct stages.

```dart
RestageFlowGraph<FirstRunResult>(
  flow: firstRunFlowRef,
  actions: FirstRunActions(/* ... */),
  unavailable: FlowUnavailablePolicy.hide(),
  onComplete: (result) => Navigator.of(context).pushReplacement(
    MaterialPageRoute<void>(builder: (_) => const MyPaywall()),
  ),
);
```

### Pattern B: paywall as a flow step (in-flow back into the paywall)

Author the paywall as the flow's last *screen*. Because a flow screen renders
any flow render-blob and a paywall is a render-blob, the runtime renders it
directly; in-flow back then lets the user return from the paywall to an earlier
screen to fix a choice. Add a completion transition when the paywall should end
the flow, as in the example below. Use this when the paywall is part of one
continuous flow.

```dart
import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import 'screens/welcome.dart';

part 'restage.generated/welcome_with_paywall.restage.g.dart';

@Paywall(id: 'serene')
final class SerenePaywall extends StatelessWidget {
  const SerenePaywall({super.key});

  static const continueFlow = SurfaceEvent<void>('continue');

  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: paywallEvent('continue'),
        child: const Text('Continue'),
      );
}

@FlowGraph(id: 'welcome_with_paywall', surface: Surface.onboarding)
const welcomeWithPaywall = FlowDefinition(
  start: WelcomeScreen,
  transitions: [
    Transition(WelcomeScreen.next, to: SerenePaywall),
    Transition.complete(
      SerenePaywall.continueFlow,
      from: SerenePaywall,
    ),
  ],
);
```

The app-defined event in this example completes the flow.

The `@Paywall` source remains a specialized paywall even when it is a step in an
onboarding flow. Codegen emits the generated flow descriptor and the exact
screen-artifact closure recorded in
`lib/generated/restage.publication.json`. At runtime, consume the
generated `SurfaceFlowRef<R>` with `RestageFlowGraph<R>`.

## Choosing a rendering surface

`RestageFlowGraph` and `RestageScreenView` differ in how much of the
presentation the SDK owns. `RestageFlowView` is the lower-level compositor used
when the host needs to control the flow's stack transition visuals or to own the
controller.

### `RestageFlowView`: the SDK owns the stack + transitions

`RestageFlowGraph` owns the normal flow host, resolving the flow and driving its
own controller. `RestageFlowView` takes a controller you own and hosts the
screens as routes on a navigator of its own, so their motion is the app's page
transition. To replace that motion, supply a `transition`
(`FlowTransitionBuilder`); it receives the entering screen's animation and the
secondary animation that displaces the screen beneath, so it covers a
**two-screens-visible** cross-transition. A supplied builder replaces the
platform's gesture-driven previews too. The SDK keeps owning the stack; you own
the visual.

A control that must persist across screens belongs outside the surface, in a
`Stack` or `Column` you own that reads the controller, because a control inside
a screen travels with that screen's route.

### `RestageScreenView`: you own the driver (single screen)

`RestageScreenView` (`@experimental`) renders the controller's **current screen
only**: no kept-mounted stack, no navigator, no transitions, no back-stack. You drive the `RestageFlowController` (it keeps the server-driven
topology, experiments, and OTA), render each current screen through
`RestageScreenView`, and supply your own transitions and controls around it.

Because it renders the *current* screen, the transition it composes with is an
**incoming-style** one: animate the new current screen in on each advance; the
old screen is simply replaced. (A two-screens-visible cross-transition needs the
outgoing screen too, which a current-only surface does not hold; use
`RestageFlowView(transition:)` for that.) See the *build-your-own-flow* example
in `apps/examples/` for a controller + `RestageScreenView` + a host-owned
incoming transition + a host-owned back control.

| You want… | Use |
|---|---|
| the full surface, resolved and driven for you | `RestageFlowGraph` |
| a controller you own, or a custom two-screens-visible transition over the SDK stack | `RestageFlowView` |
| to own the whole driver: your own switcher timing, back, and incoming-style transitions | `RestageScreenView` |

Every screen still renders through the controller's fail-closed boundary, so
`RestageScreenView` is the safe low-level path: there is no controller-free
"render an arbitrary blob" escape hatch.

## Analytics events

The flow runtime reports onboarding funnel events on the SDK event stream. They
arrive as typed `RestageEvent`s on `Restage.events`, the same stream paywalls
use, so you can forward them to your own analytics in one place:

```dart
Restage.events.listen((event) {
  switch (event) {
    case FlowStarted(:final flowId): myAnalytics.track('flow_started', {'flow': flowId});
    case OnboardingStepViewed(:final screenId, :final stepIndex):
      myAnalytics.track('onboarding_step_viewed', {'screen': screenId, 'step': stepIndex});
    case OnboardingSkipped(): myAnalytics.track('onboarding_skipped');
    case OnboardingPermissionResponse(:final permission, :final granted):
      myAnalytics.track('onboarding_permission_response', {'permission': permission, 'granted': granted});
    case _: break;
  }
});
```

The onboarding events:

| Event | Fires | Carries |
|---|---|---|
| `FlowStarted` / `FlowCompleted` / `FlowUnavailable` | flow lifecycle | flow id + version + session |
| `OnboardingStepViewed` | each *forward* screen entry (back navigation restores from history and does not re-fire) | `screenId`, `stepIndex`, `stepCount?` |
| `OnboardingSkipped` | the user takes a skip that has a real destination | `atScreenId`, `stepIndex` |
| `OnboardingPermissionResponse` | a permission host-action reports its result | `permission`, `granted` |

`stepIndex` is the screen's **0-based depth in the flow's back-stack**. Re-reaching
a screen by navigating forward after a back yields its earlier index again, so it
stays a stable funnel position rather than an inflating view counter. `stepCount`
is the number of screens authored in the flow (a best-effort "of N"; for a
branching flow it counts the authored total across every path).

> **Permission convention.** An onboarding host-action whose result carries a
> `granted: bool` is recorded as `OnboardingPermissionResponse`. `permission` is
> the action's name and `granted` is the result's value. It fires on **both**
> grant and decline (the decline is the funnel-drop signal). A host-action that
> does not report a `granted` boolean is not treated as a permission request.

## Compliance boundary

Restage's flow runtime is declarative-only. The controls and framing above are
host Flutter widgets composed *around* the rendered screens; they do not change
what the runtime interprets. The compliance claim is bounded and exact:

- Composition of the primitives can't make **Restage's runtime** review-unsafe:
  there is no server→executable-code mechanism to compose into existence. The
  runtime interprets only inert data (the flow document's finite
  comparator/reference vocabulary plus declarative render blobs) and invokes only
  pre-declared host actions with inert, allowlisted arguments.
- Composition also can't make the **app's own host code** review-safe: host
  actions, registered custom widgets, and the surrounding app are the app's
  own App Review responsibility. The primitives expose no new server→code path,
  so they neither widen nor discharge that pre-existing responsibility.

> Restage's runtime is declarative-only and never executes server-shipped code;
> that holds however you compose these primitives. Your host actions and
> registered custom widgets are your own app-reviewed code; keep them within your
> App Review obligations.
