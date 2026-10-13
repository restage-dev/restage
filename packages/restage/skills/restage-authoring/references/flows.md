# Flows

A flow is a sequence of screens: onboarding, a multi-step message, a survey. Each step
is a `@Screen()` with no category, in its own file, and inherits the flow's category.
The flow itself is a top-level `FlowDefinition` annotated with `@FlowGraph`.
Use the generated `<FlowName>Surface` to mount it at its implicit placement, with
typed callbacks and the authored flow as its compiled fallback. No bundle or
explicit placement name is required.

## Choose the flow contract

- Use the default typed flow when the app depends on a fixed graph or typed result.
  Published updates can change screen content while preserving that contract.
- Use `delivery: FlowDeliveryMode.general` when adding, removing or reordering
  steps over the air matters more than a generated result class. The installed
  actions and signals still bound what the flow can do; results are maps.
- Use standalone surfaces when the app already owns the navigation between them.

Keep platform work in host actions and presentation decisions in the graph. Separate
temporary screen state from flow state that must survive a transition, and declare
only the result fields the app needs.

## Steps

<!-- skill-check: example ../examples/lib/onboarding/goal_step.dart -->
```dart
@Screen()
final class GoalStep extends StatelessWidget {
  const GoalStep({super.key});

  static const pick = SurfaceEvent<String>('pick');

  @override
  Widget build(BuildContext context) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FilledButton(
            onPressed: surfaceEvent(pick, 'focus'),
            child: const Text('Focus better'),
          ),
          FilledButton(
            onPressed: surfaceEvent(pick, 'sleep'),
            child: const Text('Sleep better'),
          ),
        ],
      );
}
```

## State, capture and result

<!-- skill-check: example ../examples/lib/onboarding/first_run.dart -->
```dart
const goal = FlowStateRef<String>(
  'goal',
  classification: FlowStateClassification.exportable,
);
// ...
@FlowGraph(id: 'first_run', surface: Surface.onboarding)
const firstRun = FlowDefinition(
  start: WelcomeStep,
  state: [goal, returningUser],
  transitions: [
    Transition(WelcomeStep.next, to: GoalStep),
    Transition(GoalStep.pick, capture: goal, to: ReadyStep),
    Transition.complete(ReadyStep.finish),
  ],
  outbound: FlowOutboundPolicy(
    terminalResult: {'goal': goal},
    // ...
```

- `capture: goal` stores the event's value. `writes: [goal.set('skipped')]` stores a
  fixed value.
- Flow-state values are `bool`, `int` or `String`. Keep richer display data in the
  flow's render context and screen builders.
- Mark result state as `exportable` and explicitly list its fields in `outbound`.
  `terminalResult` becomes the generated result class (`FirstRunResult`, with a
  `goal` field). A state declaration alone does not add a result field.
- Every `Transition.complete` in a flow must end with the same result shape.

## Answers

Typed onboarding, message and survey flows can record answers. List the state in
`surveyAnswers`, and declare in `measurementAnswers` how each answer is counted:

<!-- skill-check: example ../examples/lib/onboarding/first_run.dart -->
```dart
outbound: FlowOutboundPolicy(
  terminalResult: {'goal': goal},
  surveyAnswers: {'goal': goal},
  measurementAnswers: {
    'goal': FlowAnswerMeasurement.category(
      outcomeKey: 'onboarding.goal',
      propertyName: 'goal',
      categoryLabels: {'focus': 'Focus better', 'sleep': 'Sleep better'},
    ),
  },
),
```

- `category` takes a fixed set of values and their labels. `integer` and
  `scaledDecimal` take bounded numbers.
- Free text is never measured. Put it in `terminalResult` so only the app receives it.
- Each answer also reaches `Restage.events` as a `SurveyQuestionResponded` event, on
  any of these flows.
- A general flow (`FlowDeliveryMode.general`) can't declare `measurementAnswers`.

Mount:

<!-- skill-check: expression -->
```dart
FirstRunSurface(
  onComplete: (result) => saveGoal(result.goal),
)
```

## Decisions

A transition can lead to a `Decision`, whose branches are tried in order:

<!-- skill-check: declarations -->
```dart
final route = Decision(
  'route',
  branches: [
    Branch(when: goal.equals('focus'), to: FocusTipsStep),
  ],
  otherwise: SleepTipsStep,
);
```

Use `final` for the flow when it references a `Decision`. Conditions: `equals`,
`notEquals`, `oneOf`, `isSet`, `isUnset`, `equalsState`; integer state also has
`greaterThan`, `atLeast`, `lessThan`, `atMost`. For a step defined later or a loop,
use `NodeRef('id')` in the transition and list the step in `nodes:`.

## Starting values from the app

<!-- skill-check: example ../examples/lib/onboarding/first_run.dart -->
```dart
const returningUser = SeedableFlowStateRef<bool>(
  'returningUser',
  defaultValue: false,
);
```

List `returningUser` in the flow's `state` beside `goal`. A decision can
branch on `returningUser.equals(true)`. The generated `FirstRunSeed` exposes only
the seedable keys:

<!-- skill-check: expression -->
```dart
FirstRunSurface(
  initialState: const FirstRunSeed(returningUser: true),
  onComplete: (result) => saveGoal(result.goal),
)
```

The default applies when the app omits a seed. This is initial flow state; use
render context and step builders for display-only host data, as below. In a general
flow, host-seeded state can guide branching but cannot be returned in `terminalResult`.

## Host data in flow screens

A generated flow mount does not take every step's constructor parameters directly.
It generates a `<screenId>ScreenBuilder` argument for a step whose original
constructor needs app-owned values. Supply the same values through `context` for
the delivered RFW screens and through that builder for the compiled fallback.

For a step declared with `@Screen(id: 'profile')` and
`const ProfileStep(this.name, {super.key})`, the `typedJourney` flow generates
`profileScreenBuilder`:

<!-- skill-check: declarations -->
```dart
Widget journeyFor(String name) => TypedJourneySurface(
  context: {'name': name},
  profileScreenBuilder: () => ProfileStep(name),
);
```

The flow's `context` publishes `data.context.name` to its screens; the zero-argument
builder constructs the original Dart widget. Use required constructor inputs for
values the app must supply. Steps with callable constructors that need no arguments
use their defaults automatically. Inspect the generated constructor for exact builder
names, including child-flow screens. Use serializable render values in `context`,
and test both delivered and compiled paths with the same input.

An enclosing Restage surface's render context takes precedence over this flow's
`context`. Keep data ownership explicit when nesting surfaces.

## Host actions

A host action is app code the flow can call, such as a permission request. In
`lib/flows/permission_flow.dart`, import two `@Screen()` steps: `PermissionScreen`
declares a void `enable` event and `ReadyScreen` declares a void `finish` event.
Their buttons pass `surfaceEvent(...)` directly as callbacks.

<!-- skill-check: file lib/flows/permission_flow.dart -->
```dart
import 'package:restage/restage.dart';

import '../screens/permission.dart';
import '../screens/ready.dart';

part 'restage.generated/permission_flow.restage.g.dart';

const requestNotifications = FlowActionRef<void, bool>('requestNotifications');

@FlowGraph(surface: Surface.onboarding)
final permissionFlow = FlowDefinition(
  start: PermissionScreen,
  transitions: [
    Transition(
      PermissionScreen.enable,
      action: requestNotifications.continueWhen((granted) => granted),
      to: ReadyScreen,
    ),
    Transition.complete(ReadyScreen.finish),
  ],
);
```

The app supplies its platform handler through the generated actions class:

<!-- skill-check: declarations -->
```dart
Widget permissionEntry({
  required Future<bool> Function() requestNotificationPermission,
}) => PermissionFlowSurface(
  actions: PermissionFlowActions(
    requestNotifications: (_, actionContext) => requestNotificationPermission(),
  ),
);
```

Import Flutter widgets and the flow file at this call site. The handler returns
whether permission was granted. A false result leaves the user on the current
screen; a thrown error follows the flow's unavailable handling. Handle expected
platform outcomes in the app rather than throwing for an ordinary decline.

The handler receives its typed input and `FlowActionContext`. The context has an
operation ID and retry fields; it does not promise automatic retries. A published
flow can call only actions whose installed contracts match. Adding a native action
or changing its input/output types requires an app release.

## Reuse a child flow

Use `Subflow` to run a reusable graph, with explicit input and completion targets.
For example, `profileFlow` declares `profileName` in its state and `accountSetup`
declares `accountName`:

<!-- skill-check: declarations -->
```dart
final done = Completion('done');
final profileStep = Subflow(
  'profile',
  flow: profileFlow,
  input: [profileName.fromState(accountName)],
  onComplete: done,
  onUnavailable: ErrorScreen,
);
```

Route `Transition(AccountScreen.profile, to: profileStep)` to this node. Each input
names the child's state reference and its parent source; use `fromValue(...)` for
a literal. Choose an unavailable target so the app has a useful path when the
child cannot run. Keep child contracts compatible with the installed parent.

## Paywalls in flows

A `@Paywall()` can be a step in a flow of any category. Its standalone publication
remains a paywall; the containing graph owns its transitions and flow events.
Declare `SurfaceEvent`s for transitions. Supplied purchase-adapter handlers accept
standalone paywall events, not flow events. Use a host action when the graph must
await purchase or service work; see [host-integration.md](host-integration.md).

## What a published version can change

By default a flow is typed. A published version can change what each step shows, but
adding a step or rerouting a transition needs an app release. To change the graph over
the air, declare:

<!-- skill-check: skip shows the annotation line only -->
```dart
@FlowGraph(surface: Surface.onboarding, delivery: FlowDeliveryMode.general)
```

A published version can then add, remove and reorder steps and change transitions,
using the installed widget vocabulary, events and host actions. `onComplete` then
receives `Map<String, Object?>` in place of a generated result class. Validate the
fields your app reads from that map.

General flows have additional outbound limits:

- Host-seeded flow state cannot leave through `terminalResult`.
- Analytics-reaching outputs (`customEvents`, `surveyAnswers`, `lifecycle`) may
  reference event arguments, not captured flow state.
- `measurementAnswers` is unavailable; use a typed flow for measured answers.

The simple `FlowOutboundPolicy` maps shown above reference state. Do not copy its
`surveyAnswers` example into a general flow. Use an advanced descriptor only when
its outbound contract requires one; keep ordinary graphs in `FlowDefinition`.

`Surface.general` (a category) and `FlowDeliveryMode.general` (what an update can
change) are separate choices.

## Hosted flows

`Restage.configure(apiKey: ..., baseUrl: ..., surfaces: restageSurfaces)` enables
hosted flow delivery automatically. Leave resolver overrides out of ordinary
integrations so generated mounts use placement resolution. Explicit resolvers are
for custom delivery behavior.

Without hosted configuration, the generated mount can run its compiled flow.
Unavailable hosted content falls back to compatible retained content or the authored
flow. Publishing normally affects later mounts. Opt-in live refresh uses the SDK's
swap-safety checks and does not discard user-contributed flow state.

Flow definitions and generated assets ship inside the app and can be read by anyone.
Don't put secrets or private business rules in them.

## Existing paywall navigation

Keep existing navigation that fits the supported forms. Restage automatically
compiles navigation between `@Paywall` widgets into a flow; mount the generated
entry paywall without writing a `@FlowGraph` declaration. Use `FlowDefinition`
when you need explicit branching, host actions or results beyond this subset.

Supported callbacks contain a single synchronous
`Navigator.push(context, MaterialPageRoute(builder: ...))` or
`Navigator.of(context).push(...)` from `onPressed`/`onTap`, with an annotated paywall
destination constructed without arguments through its unnamed constructor.
`CupertinoPageRoute` is also supported; `Navigator.pop(context)` in a pushed
paywall becomes a flow back action. Pushes are limited to one level: a pushed
paywall cannot push another. The entry paywall needs a dismissal path.

Awaiting or reading a route result, returning a value with `pop`, root-navigator
overrides and arbitrary navigation callbacks are outside that lowering. Keep app
navigation in a generated mount's callbacks when it is not part of the flow.
