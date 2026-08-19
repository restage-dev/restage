import 'package:restage/restage.dart';

import '../screens/welcome.dart';

part 'neutral_welcome.rsflow.g.dart';

@FlowGraph(surface: Surface.onboarding)
const onboardingWelcome = FlowDefinition(
  start: NeutralWelcome,
  transitions: [
    Transition.complete(NeutralWelcome.finish),
  ],
);
