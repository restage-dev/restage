import 'package:restage/restage.dart';

import 'goal_step.dart';
import 'ready_step.dart';
import 'welcome_step.dart';

part 'restage.generated/first_run.restage.g.dart';

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
