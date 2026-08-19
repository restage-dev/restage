import 'package:restage/restage.dart';

import '../screens/permission.dart';
import '../screens/ready.dart';

part 'restage.generated/permission_flow.restage.g.dart';

const requestNotifications = FlowActionRef<void, bool>(
  'requestNotifications',
);

@FlowGraph(surface: Surface.onboarding)
final permissionFlow = FlowDefinition(
  start: PermissionScreen,
  transitions: [
    Transition(
      PermissionScreen.enable,
      action: requestNotifications.continueWhen(
        (granted) => granted,
      ),
      to: ReadyScreen,
    ),
    Transition.complete(ReadyScreen.finish),
  ],
);
