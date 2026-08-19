import 'package:restage/restage.dart';

import '../screens/announcement.dart';

part 'account_recovery.rsflow.g.dart';

@FlowGraph(surface: Surface.general)
const accountRecovery = FlowDefinition(
  start: FeatureAnnouncement,
  transitions: [
    Transition.complete(FeatureAnnouncement.dismiss),
  ],
);
