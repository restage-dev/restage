import 'package:restage/restage.dart';

import '../screens/profile.dart';

part 'profile_flow.rsflow.g.dart';

const profileName = FlowStateRef<String>('profileName');

@FlowGraph(surface: Surface.onboarding)
const profileFlow = FlowDefinition(
  start: ProfileScreen,
  state: [profileName],
  transitions: [
    Transition.complete(ProfileScreen.finish),
  ],
);
