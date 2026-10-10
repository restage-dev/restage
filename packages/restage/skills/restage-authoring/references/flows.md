# Flows

A flow is a sequence of screens: onboarding, a multi-step message, a survey. Each step
is a `@Screen()` with no category, in its own file, and inherits the flow's category.
The flow itself is a top-level `FlowDefinition` annotated with `@FlowGraph`.

## Steps

```dart
@Screen()
final class GoalStep extends StatelessWidget {
  const GoalStep({super.key});

  static const pick = SurfaceEvent<String>('pick');

  @override
  Widget build(BuildContext context) => Column(
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

```dart
const goal = FlowStateRef<String>(
  'goal',
  classification: FlowStateClassification.exportable,
);

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

- `capture: goal` stores the event's value. `writes: [goal.set('skipped')]` stores a
  fixed value.
- State is private to the flow. Only state marked `exportable` and listed in `outbound`
  leaves it. `terminalResult` becomes the generated result class (`FirstRunResult`,
  with a `goal` field).
- Every `Transition.complete` in a flow must end with the same result shape.

## Answers

Typed onboarding, message and survey flows can record answers. List the state in
`surveyAnswers`, and declare in `measurementAnswers` how each answer is counted:

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

```dart
FirstRunSurface(
  onComplete: (result) => saveGoal(result.goal),
)
```

## Decisions

A transition can lead to a `Decision`, whose branches are tried in order:

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

```dart
const returningUser = SeedableFlowStateRef<bool>(
  'returningUser',
  defaultValue: false,
);
```

The build generates `<FlowName>Seed`, passed as `initialState:` on the mount.

## Host actions

A host action is app code the flow can call, such as a permission request:

```dart
const requestNotifications = FlowActionRef<void, bool>('requestNotifications');

// In transitions:
Transition(
  PermissionStep.enable,
  action: requestNotifications.continueWhen((granted) => granted),
  to: ReadyStep,
),
```

The app supplies the implementation on the mount through `actions:`. A published
version can only call actions the installed app provides.

## Paywalls in flows

A `@Paywall()` can be a step in a flow of any category. It keeps `Surface.paywall` and
declares `SurfaceEvent`s for its transitions.

## What a published version can change

By default a flow is typed. A published version can change what each step shows, but
adding a step or rerouting a transition needs an app release. To change the graph over
the air, declare:

```dart
@FlowGraph(surface: Surface.onboarding, delivery: FlowDeliveryMode.general)
```

A published version can then add, remove and reorder steps and change transitions,
using only the events and host actions the installed app declares. `onComplete` then
receives `Map<String, Object?>` in place of a generated result class.

`Surface.general` (a category) and `FlowDeliveryMode.general` (what an update can
change) are separate choices.

## Hosted flows

Flows render the version built into the app unless `Restage.configure` gets
`flowResolver: ServerFlowResolver(baseUrl: ..., apiKey: ..., active: true)`, or the
mount gets it as `resolver:`. If no published version can run, the generated mount runs
the flow built into the app from the start. A flow never switches versions halfway.

Flow definitions and generated assets ship inside the app and can be read by anyone.
Don't put secrets or private business rules in them.
