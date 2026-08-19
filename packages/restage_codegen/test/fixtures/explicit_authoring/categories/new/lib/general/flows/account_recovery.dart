import 'package:restage/restage.dart';

import '../screens/announcement.dart';

part 'restage.generated/account_recovery.restage.g.dart';

@FlowGraph(surface: Surface.general)
const accountRecovery = FlowDefinition(
  start: FeatureAnnouncement,
  transitions: [
    Transition.complete(FeatureAnnouncement.dismiss),
  ],
);
