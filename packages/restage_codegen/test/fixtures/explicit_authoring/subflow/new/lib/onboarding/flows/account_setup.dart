import 'package:restage/restage.dart';

import '../screens/account.dart';
import '../screens/error.dart';
import 'profile_flow.dart';

part 'account_setup.rsflow.g.dart';

const accountName = FlowStateRef<String>('accountName');
final done = Completion('done');

final profileStep = Subflow(
  'profile',
  flow: profileFlow,
  input: [profileName.fromState(accountName)],
  onComplete: done,
  onUnavailable: ErrorScreen,
);

@FlowGraph(surface: Surface.onboarding)
final accountSetup = FlowDefinition(
  start: AccountScreen,
  state: [accountName],
  transitions: [
    Transition(AccountScreen.profile, to: profileStep),
  ],
);
