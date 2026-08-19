import 'package:restage/restage.dart';

import '../screens/profile.dart';

part 'restage.generated/profile_flow.restage.g.dart';

const profileName = FlowStateRef<String>('profileName');

@FlowGraph(surface: Surface.onboarding)
const profileFlow = FlowDefinition(
  start: ProfileScreen,
  state: [profileName],
  transitions: [
    Transition.complete(ProfileScreen.finish),
  ],
);
