import 'package:restage/restage.dart';

import '../screens/welcome.dart';

part 'restage.generated/neutral_welcome.restage.g.dart';

@FlowGraph(surface: Surface.onboarding)
const onboardingWelcome = FlowDefinition(
  start: NeutralWelcome,
  transitions: [
    Transition.complete(NeutralWelcome.finish),
  ],
);
