import 'package:restage/restage.dart';

import '../screens/accepted.dart';
import '../screens/declined.dart';
import '../screens/start.dart';

part 'completion_paths.rsflow.g.dart';

@FlowGraph(surface: Surface.onboarding)
const completionPaths = FlowDefinition(
  start: StartScreen,
  transitions: [
    Transition(StartScreen.accept, to: AcceptedScreen),
    Transition(StartScreen.decline, to: DeclinedScreen),
    Transition.complete(AcceptedScreen.finish),
    Transition.complete(DeclinedScreen.finish),
  ],
);
