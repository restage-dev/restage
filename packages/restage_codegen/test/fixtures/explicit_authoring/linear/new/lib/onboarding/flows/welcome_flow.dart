import 'package:restage/restage.dart';

import '../screens/profile.dart';
import '../screens/welcome.dart';

part 'welcome_flow.rsflow.g.dart';

@FlowGraph(surface: Surface.onboarding)
const welcomeFlow = FlowDefinition(
  start: WelcomeScreen,
  transitions: [
    Transition(
      WelcomeScreen.next,
      to: ProfileScreen,
    ),
    Transition.complete(ProfileScreen.finish),
  ],
);
