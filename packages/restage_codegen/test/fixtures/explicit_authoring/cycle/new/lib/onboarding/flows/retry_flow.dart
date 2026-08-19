import 'package:restage/restage.dart';

import '../screens/failure.dart';
import '../screens/retry_screen.dart';
import '../screens/start.dart';

part 'restage.generated/retry_flow.restage.g.dart';

const attempts = FlowStateRef<int>('attempts', defaultValue: 0);
const retryRef = NodeRef('retry');

final retryDecision = Decision(
  'retry',
  branches: [
    Branch(
      when: attempts.lessThan(3),
      to: RetryScreen,
    ),
  ],
  otherwise: FailureScreen,
);

@FlowGraph(surface: Surface.onboarding)
final retryFlow = FlowDefinition(
  start: StartScreen,
  state: [attempts],
  transitions: [
    Transition(StartScreen.next, to: retryRef),
    Transition(RetryScreen.failed, to: retryRef),
    Transition.complete(RetryScreen.succeeded),
    Transition.complete(FailureScreen.finish),
  ],
  nodes: [retryDecision],
);
