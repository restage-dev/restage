# Flow navigation & customization

How to customize the chrome (the back/skip affordances) around a Restage flow,
how flow navigation and back behave, how to choose between the high-level and
low-level rendering surfaces, and the compliance boundary that holds however you
compose them.

This covers `RestageOnboarding` / `RestageFlowView` (the full surfaces) and
`RestageScreenView` (the lower-level per-screen surface). All of them render the
same flow document driven by the same `RestageFlowController`.

## The chrome customization ladder

A flow surface draws **chrome** — the back affordance (and an optional skip
affordance) — around each screen. Customization is a ladder: take only the rung
you need. Higher rungs leave the layout to the SDK; lower rungs hand you more
control.

The ladder separates the three concerns a typical app bar conflates: the
affordance's **visual** (the icon/label), its **layout** (where it sits), and
its **intent** (what it does + when it is available).

| Rung | You take over | You write |
|---|---|---|
| **Default** | nothing | — (platform-styled back when there is history; skip off by default) |
| **Theme** | the visual tokens | `chromeTheme: FlowChromeTheme(...)` |
| **Slots** | the affordance widgets (SDK still positions them) | `backBuilder` / `skipBuilder` |
| **Layout** | the whole chrome layout | `chromeBuilder` (per-screen) / `persistentChromeBuilder` (frames the flow) |
| **DIY** | everything | own a `RestageFlowController`; render with `RestageScreenView`; draw your own chrome |

See the *Chrome customization* example in `apps/examples/` for a runnable tour
that switches between these rungs over one flow (and the *build-your-own-flow*
example for the DIY rung).

### Default

With no chrome parameters, the surface shows a platform-adaptive back affordance
whenever there is a prior screen to return to, and no skip affordance. The
back/skip affordances expose clean accessibility labels (`Back` / `Skip`).

### Theme — restyle the default affordances

`FlowChromeTheme` restyles the built-in affordances without changing their
layout. Every token is optional; an omitted token keeps the platform-appropriate
default.

```dart
RestageOnboarding<FirstRunResult>(
  flow: FirstRunFlowDescriptor.ref,
  unavailable: FlowUnavailablePolicy.hide(),
  chromeTheme: const FlowChromeTheme(
    backIcon: Icons.chevron_left,
    color: Color(0xFF6FD6C6),
    size: 32,
    padding: EdgeInsets.all(16),
    skipLabel: 'Not now',
  ),
);
```

`FlowChromeTheme` has value equality and a `copyWith`, so you can derive one
theme from another.

### Slots — supply the affordance widget, SDK positions it

`backBuilder` / `skipBuilder` (`FlowChromeAffordanceBuilder`) let you supply the
affordance widget; the SDK still positions it and supplies the persistent
framing. `onAction` performs the affordance's intent (a back pop, or a skip).

```dart
RestageOnboarding<FirstRunResult>(
  flow: FirstRunFlowDescriptor.ref,
  unavailable: FlowUnavailablePolicy.hide(),
  backBuilder: (context, onAction) => IconButton(
    icon: const Icon(Icons.arrow_back_ios_new),
    onPressed: onAction,
  ),
);
```

> **Accessibility:** a Slots/Layout widget owns its own `Semantics`. The built-in
> chrome supplies a single clean label per affordance; a custom widget must
> supply its own (e.g. an `IconButton`'s `tooltip`, or a `Semantics(button: true,
> label: 'Back')` wrapper) so it stays screen-reader-reachable.

### Layout — own the chrome layout

Two builder layers let you own the layout entirely. Both receive a
`FlowChromeState` snapshot:

- `chromeBuilder` (`FlowChromeBuilder`) — **per-screen**: lives inside the
  animated slot, so it animates with the screen. It receives the screen's
  rendered widget; compose chrome around or over it.
- `persistentChromeBuilder` (`FlowPersistentChromeBuilder`) — **frames the whole
  flow**: lives outside the transition, so it stays put while screens animate
  beneath. It receives the animated screen stack as `flowBody`.

Both may be set together (the frame composes around the per-screen result).

```dart
RestageOnboarding<FirstRunResult>(
  flow: FirstRunFlowDescriptor.ref,
  unavailable: FlowUnavailablePolicy.hide(),
  persistentChromeBuilder: (context, state, flowBody) => Column(
    children: [
      LinearProgressIndicator(value: state.canBack ? 0.5 : 0.0),
      Expanded(child: flowBody),
    ],
  ),
);
```

`FlowChromeState` carries only signals the runtime can stand behind:

| Field | Meaning |
|---|---|
| `onBack` / `onSkip` | perform a back pop / a skip (no-ops when unavailable) |
| `canBack` / `canSkip` | whether there is a prior screen / a skip destination |
| `isForward` | whether the in-flight transition is a forward push (vs a back pop) |
| `screenId` | the current screen's state id (null when no screen is mounted) |
| `isComplete` | whether the flow has finished (collapse chrome on completion) |
| `isBusy` | whether a transition or host action is in flight (keep affordances inert while busy) |

There is deliberately **no "step N of M"**: a flow can branch (decision states,
sub-flows), so a total step count is not knowable in general. A progress
indicator is the author's to derive — you authored the flow's shape and have
`screenId`.

### Persistent vs per-screen chrome

`persistentChrome` (a bool, default `true`) governs the **built-in** chrome's
layer: `true` frames the flow with a stable bar that does not slide with the
content (the most robust default); `false` rides inside the animated slot.
Supplying `chromeBuilder` / `persistentChromeBuilder` chooses the layer
explicitly and supersedes the bool.

`persistentChrome` is a parameter on `RestageOnboarding` / `RestageFlowView`
(not on `FlowChromeTheme`, which stays purely visual). For an app-wide setting,
pass the same value (or wrap the surface).

### DIY — own the controller

The lowest rung is to drive a `RestageFlowController` yourself and render with
`RestageScreenView`, drawing your own chrome. See *Choosing a rendering surface*
below.

## Skip

Skip is **off by default** (a forced onboarding shouldn't be skippable, and there
is no platform "skip" default to inherit). Set `enableSkip: true` to show it. The
skip affordance is shown only when the current screen actually has a skip
destination — an authored `on['skip']` transition, or a declared
`outbound.customEvents['skip']` — so there is never a visible-but-dead skip
control. `controller.skip()` routes the reserved `skip` event: an authored
transition takes it, otherwise the declared custom event is emitted for the host
to handle (commonly to dismiss the flow).

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
  frame's first screen. A completed flow does not navigate (`canBack` /`canSkip`
  are false).
- **The auto-shown back affordance is a pure pop.** The SDK's back chevron (and
  the platform system-back gesture) pop screen history; they never run a
  side-effecting authored action. The reserved `on['back']` transition is for an
  author-placed in-screen control, not the auto-shown chrome.

### System back when in-flow back is exhausted

While there is screen history, the platform system-back gesture is consumed and
pops. When in-flow back is exhausted (the first screen, or a barrier), a
`systemBack` policy (`SystemBackPolicy`) decides what happens:

| Policy | Behavior |
|---|---|
| `SystemBackPolicy.popHost` (default) | let system-back propagate to the host (the host's own structure decides — dismiss a pushed route, or the platform's "back at root" behavior) |
| `SystemBackPolicy.block()` | trap it; back at the first screen is a no-op (a mandatory flow) |
| `SystemBackPolicy.complete()` | treat exhausted back as completing/dismissing the flow (requires a skip destination — a declared `customEvents['skip']` or `on['skip']`; without one, exhausted back is a no-op) |
| `SystemBackPolicy.onExhausted(callback)` | a callback escape hatch for bespoke handling |

### iOS edge-swipe

The flow renders its screens in a single keep-mounted stack within one host route
— not as one `Navigator` route per screen. The Android system-back button is a
whole-route signal, so it is routed through the controller (consumed to step back
within the flow while history remains, then handed to the `systemBack` policy).
On iOS, `RestageFlowView` adds an in-flow leading-edge drag while `canBack` is
true: dragging from the leading edge previews the prior kept-mounted screen, and
completing the drag performs the same pure history pop as the back chrome. A
cancelled drag leaves the current screen in place. This is the flow's own
screen-history gesture, not a host-route pop; authored `on['back']` transitions
are still reserved for author-placed in-screen controls.

Once in-flow back is exhausted (the first screen, or a barrier), the route is
poppable again according to the `systemBack` policy. With the default
`SystemBackPolicy.popHost`, the host route's own iOS edge-swipe dismisses the
flow route.

## Two onboarding→paywall navigation patterns

There are two ways to structure "onboarding, then a paywall." Pick by whether the
two are distinct phases or one continuous flow.

### Pattern A — handoff (the host navigates)

The flow reaches an end state, `onComplete` fires, and the **host** navigates to
a separate paywall surface. The completed flow does not navigate, so the user
cannot back into onboarding from the paywall. Use this when onboarding and the
paywall are distinct phases.

```dart
RestageOnboarding<FirstRunResult>(
  flow: FirstRunFlowDescriptor.ref,
  actions: FirstRunActions(/* ... */),
  unavailable: FlowUnavailablePolicy.hide(),
  onComplete: (result) => Navigator.of(context).pushReplacement(
    MaterialPageRoute<void>(builder: (_) => const MyPaywall()),
  ),
);
```

### Pattern B — paywall as a flow step (in-flow back into the paywall)

Author the paywall as the flow's last *screen* (no end state at the paywall, so
the flow stays active). Because a flow screen renders any flow render-blob and a
paywall is a render-blob, the runtime renders it directly; in-flow back then lets
the user return from the paywall to an earlier screen to fix a choice. Use this
when the paywall is part of one continuous flow.

```dart
return flow(
  initial: WelcomeScreenDescriptor.ref,
  states: [
    screen(WelcomeScreenDescriptor.ref)
        .on(WelcomeScreen.next)
        .goTo(paywallScreen('serene')),
    screen(paywallScreen('serene'))
        .on(PaywallFlowEvents.purchase)
        .goTo(done),
    end(done, result: {'purchased': true}),
  ],
);
```

For a Dart-authored `@PaywallSource(id: 'serene')`, codegen emits the normal
paywall artifacts and a flow-screen adapter at
`assets/onboarding/screens/paywall_serene.rfw`. If the embedded paywall reads
live prices, pass the same `priceQueries` map to `RestageOnboarding` /
`RestageFlowView` / `RestageScreenView` that you would pass to
`RestagePaywall`.

## Choosing a rendering surface

`RestageOnboarding` / `RestageFlowView` and `RestageScreenView` differ in how
much of the presentation the SDK owns.

### `RestageFlowView` — the SDK owns the stack + transitions

`RestageFlowView` (and the `RestageOnboarding` convenience wrapper) own a
kept-mounted screen stack, the back-stack, the chrome ladder above, and a
platform-adaptive transition. To fully customize the transition — including a
**two-screens-visible** (opposing-slide) cross-transition where the outgoing and
incoming screens animate against each other — supply a `transition`
(`FlowTransitionBuilder`); the SDK keeps owning the stack mechanism, you own the
visual.

### `RestageScreenView` — you own the driver (single screen)

`RestageScreenView` (`@experimental`) renders the controller's **current screen
only** — no kept-mounted stack, no transitions, no back-stack, no chrome. You
drive the `RestageFlowController` (it keeps the server-driven topology,
experiments, and OTA), render each current screen through `RestageScreenView`,
and supply your own transitions, back affordance, and chrome around it.

Because it renders the *current* screen, the transition it composes with is an
**incoming-style** one: animate the new current screen in on each advance; the
old screen is simply replaced. (A two-screens-visible cross-transition needs the
outgoing screen too, which a current-only surface does not hold — use
`RestageFlowView(transition:)` for that.) See the *build-your-own-flow* example
in `apps/examples/` for a controller + `RestageScreenView` + a host-owned
incoming transition + an own back affordance.

| You want… | Use |
|---|---|
| the full surface, default or themed chrome | `RestageOnboarding` / `RestageFlowView` |
| a fully custom two-screens-visible (opposing-slide) transition over the SDK stack | `RestageFlowView(transition:)` |
| to own the whole driver — your own switcher timing, back, and incoming-style transitions | `RestageScreenView` |

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

`stepIndex` is the screen's **0-based depth in the flow's back-stack** — re-reaching
a screen by navigating forward after a back yields its earlier index again, so it
stays a stable funnel position rather than an inflating view counter. `stepCount`
is the number of screens authored in the flow (a best-effort "of N"; for a
branching flow it is the authored total, not the length of any single path).

> **Permission convention.** An onboarding host-action whose result carries a
> `granted: bool` is recorded as `OnboardingPermissionResponse` — `permission` is
> the action's name, `granted` is the result's value — and it fires on **both**
> grant and decline (the decline is the funnel-drop signal). A host-action that
> does not report a `granted` boolean is not treated as a permission request.

## Compliance boundary

Restage's flow runtime is declarative-only. The customization surfaces above are
host Flutter widgets composed *around* the rendered screens; they do not change
what the runtime interprets. The compliance claim is bounded and exact:

- Composition of the primitives can't make **Restage's runtime** review-unsafe —
  there is no server→executable-code mechanism to compose into existence; the
  runtime interprets only inert data (the flow document's finite
  comparator/reference vocabulary plus declarative render blobs) and invokes only
  pre-declared host actions with inert, allowlisted arguments.
- Composition also can't make the **customer's own host code** review-safe — host
  actions, registered custom widgets, and the surrounding app are the customer's
  own App Review responsibility. The primitives expose no new server→code path,
  so they neither widen nor discharge that pre-existing responsibility.

> Restage's runtime is declarative-only and never executes server-shipped code;
> that holds however you compose these primitives. Your host actions and
> registered custom widgets are your own app-reviewed code; keep them within your
> App Review obligations.
