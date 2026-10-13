# Flow navigation & customization

Where a flow's navigation controls come from, how navigation and back behave,
how to choose between the high-level and low-level flow widgets, and what stays
in your app however you compose them.

This covers `RestageFlowGraph` (the normal flow widget), `RestageFlowView` (the
lower-level widget for a controller you own), and `RestageScreenView` (renders
only the current screen). All of them render the same flow, driven by the same
`RestageFlowController`.

## Navigation controls come from your screens

A flow surface draws no back control, no skip control and no bar of its own. The
runtime moves between screens and keeps the history; you place the controls the
user taps.

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
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('What brings you here?'),
      ),
      body: Center(
        child: FilledButton(
          onPressed: surfaceEvent(next),
          child: const Text('Continue'),
        ),
      ),
    );
  }
}
```

Put the bar in the scaffold's `appBar` slot, so it sits above the body and clears
the status bar.

The screen is ordinary Flutter and compiles like any other. `AppBar` and
`CupertinoNavigationBar` are catalog widgets, so the bar is delivered with the
rest of the screen and shows the same control as the compiled screen.

### The mechanism: the screens are routes

The flow hosts its screens on a `Navigator` of its own: one route for each screen
visit that back can still reach. The routes stay mounted, so back restores a
screen without rebuilding it. A screen with another behind it reports `canPop`, and
`AppBar` and `CupertinoNavigationBar` derive their leading control from that with
`automaticallyImplyLeading` at its default.

Everything that pops that route pops exactly one flow screen: the bar's own back
control, `Navigator.maybePop`, the Android system-back gesture, Android's
predictive back and the iOS leading-edge swipe. The last two are the route's own,
so they preview the prior screen and complete the same pop. Only one level
handles the gesture at a time: while the flow has a screen to go back to, the
flow handles it; once there is none, the route around the flow handles it again.

Screens move with the app's `pageTransitionsTheme`, like any other route, and a
`Hero` flies between them. Supply a `transition` to replace that motion for one
flow.

Two cases show no back control, and both are correct. A screen with no app bar
has none. The first screen of a sub-flow has none either, because back never
leaves a sub-flow for its parent. The first screen of a flow has no screen behind it, so its
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

A control inside a screen fires an event like any other. Give it the reserved
`back` event and it goes back one screen with no transition to write:

```dart
static const back = SurfaceEvent<void>('back');
```

There is no built-in **"step N of M"**: a flow can branch (decisions,
sub-flows), so the total number of steps isn't known in general. Build a progress
indicator from the flow you wrote and `currentScreenId`.

## Skip

Skip has no platform control, so you always draw it. `controller.skip()` sends
the reserved `skip` event: a `skip` transition on the screen takes it; otherwise,
if the flow declares `skip` as a custom event, your app receives it, usually to
close the flow. When neither exists, `canSkip` is false, so leave the control out.

Inside a delivered screen, the natural place for skip is the app bar: a
`TextButton` in `AppBar.actions`, or a `CupertinoButton` in
`CupertinoNavigationBar.trailing`, wired to a `SurfaceEvent<void>('skip')`. The
runtime handles it exactly as `controller.skip()` does.

## Dismissing the flow from a host control

`Navigator.maybePop` on the route that holds the flow goes back one flow screen
while there is one. That is what an app bar's back control relies on. A close
button that should leave the flow from any screen calls `pop`, which closes the
route in one step:

```dart
void dismissFlow(BuildContext context) => Navigator.of(context).pop();
```

Call it with a context from outside the flow, so `Navigator.of` finds your route.
Inside the flow it would find the flow's own navigator.

Completion needs none of this. The flow has finished by the time `onComplete`
runs, so `Navigator.maybePop` inside that callback closes the route.

## Back navigation

Back follows screen history the way a `Navigator` does:

- **Each screen visit is recorded.** Back returns to the previous screen with its
  state kept. `canBack` tells you whether there is one.
- **Decisions and host actions are skipped.** They run between screens and aren't
  recorded, so back never runs a transition again or repeats a host action.
- **Sub-flows are a boundary.** Back inside a sub-flow never reaches the parent
  flow; `canBack` is false on a sub-flow's first screen. A completed flow doesn't
  navigate (`canBack` and `canSkip` are false).
- **Back only goes back.** The app bar's back control, `controller.back()`, and
  system back run none of your flow's transitions or actions.

### System back on the first screen

While there is screen history, system back goes back one screen. When there is
nothing left to go back to (the first screen, or the first screen of a sub-flow),
the `systemBack` policy (`SystemBackPolicy`) decides what happens:

| Policy | Behavior |
|---|---|
| `SystemBackPolicy.popHost` (default) | the route around the flow handles system back: a pushed route closes, and a flow at the root sends the app to the background |
| `SystemBackPolicy.block()` | system back does nothing on the first screen (a flow the user must finish) |
| `SystemBackPolicy.complete()` | system back leaves the flow through its `skip` event; the flow needs a `skip` transition or custom event, and without one system back does nothing |
| `SystemBackPolicy.onExhausted(callback)` | runs your own callback |

The policy applies only when there is nothing left to go back to. Before that,
system back always goes back one screen.

### The iOS edge-swipe and Android predictive back

Both are Flutter's, on the flow screen's own route. Dragging from the leading
edge on iOS previews the prior screen; an Android predictive-back drag does the
same with the platform's own motion. Completing the drag goes back one screen,
like an app bar's back control, and canceling leaves the current screen in place.

While the flow has a screen to go back to, the gesture of the route around the
flow is off, so the two never compete. Once there is nothing left to go back to,
that route handles the gesture again under the `systemBack` policy. With the
default `SystemBackPolicy.popHost`, its gesture closes the flow route.

## Two flow→paywall navigation patterns

There are two ways to structure "onboarding, then a paywall." Pick by whether the
two are distinct stages or one continuous flow.

### Pattern A: handoff (the host navigates)

The flow reaches its end, `onComplete` fires, and **your app** navigates to a
separate paywall. The completed flow does not navigate, so the user
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

Write the paywall as the flow's last *screen*. A flow can render a paywall as a
step, and back then lets the user return from the paywall to an earlier screen
to change a choice. Add a completion transition when the paywall should end
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

The `@Paywall` stays a paywall even when it is a step in an onboarding flow. The
build generates the flow reference and records every screen the flow needs in
`.restage/build/metadata/restage.publication.json`. Mount the flow with its
generated `WelcomeWithPaywallSurface`, or pass the generated `SurfaceFlowRef<R>`
to `RestageFlowGraph<R>`.

## Choosing a rendering surface

`RestageFlowGraph` and `RestageScreenView` differ in how much of the
presentation the SDK owns. Use `RestageFlowView` when your app needs to own the
controller or change the screen transitions.

### `RestageFlowView`: the SDK owns the screens and transitions

`RestageFlowGraph` is the normal flow widget: it loads the flow and drives its
own controller. `RestageFlowView` takes a controller you own and hosts the
screens as routes on a navigator of its own, so their motion is the app's page
transition. To replace that motion, supply a `transition`
(`FlowTransitionBuilder`); it receives the entering screen's animation and the
secondary animation that displaces the screen beneath, so it covers a
**two-screens-visible** cross-transition. A builder you supply also replaces the
platform's gesture previews. The SDK still manages the screens; you own the
animation.

A control that must stay on screen across steps belongs outside the flow, in a
`Stack` or `Column` you own that reads the controller, because a control inside
a screen travels with that screen's route.

### `RestageScreenView`: you own the driver (single screen)

`RestageScreenView` (`@experimental`) renders the controller's **current screen
only**: no screen history, no navigator, no transitions. You drive the
`RestageFlowController` (which still handles the delivered graph, experiments,
and over-the-air updates), render each current screen through
`RestageScreenView`, and supply your own transitions and controls around it.

Because it renders only the current screen, use an **incoming** transition:
animate the new screen in on each step, and the old one is simply replaced. A
transition that shows two screens at once needs the outgoing screen too, which
this widget doesn't hold; use `RestageFlowView(transition:)` for that. See the *build-your-own-flow* example
in `apps/examples/` for a controller + `RestageScreenView` + a host-owned
incoming transition + a host-owned back control.

| You want… | Use |
|---|---|
| the whole flow, loaded and driven for you | `RestageFlowGraph` |
| a controller you own, or a custom transition that shows two screens at once | `RestageFlowView` |
| to drive everything yourself: your own timing, back, and incoming transitions | `RestageScreenView` |

Every screen still renders through the controller's checks, so
`RestageScreenView` is still safe: there is no way to render delivered content
without the controller.

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

`stepIndex` is the screen's **0-based position in the flow's history**. Reaching a
screen again by going forward after a back gives it the same index, so it is a
stable funnel position that doesn't grow with repeat views. `stepCount` is the
number of screens in the flow; for a branching flow it counts every screen on
every path, so treat it as approximate.

> **Permission convention.** An onboarding host action whose result has a
> `granted: bool` is recorded as `OnboardingPermissionResponse`. `permission` is
> the action's name and `granted` is the result's value. It fires on **both**
> grant and decline, so a decline shows as a funnel drop. A host action that
> doesn't report a `granted` boolean isn't treated as a permission request.

## App Store compliance

What ships is data the app renders. Your widgets carry the logic, as Dart
compiled into your app. The surface composes and configures them over the air.

- The navigation controls in this guide are Flutter widgets in your app, placed
  around the rendered screens.
- Flow documents describe screen transitions, data, and which declared actions
  to call. The installed SDK checks them against the widgets and actions your
  app has.
- Host-action handlers and custom widget implementations compile into your app.
  New behavior is a release.

Your host actions, registered custom widgets and surrounding app remain part
of your App Review responsibility. Review the app and its delivered content
against the applicable store policies.
