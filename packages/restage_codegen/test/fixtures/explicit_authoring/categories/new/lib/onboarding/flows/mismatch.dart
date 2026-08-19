import 'package:restage/restage.dart';

import '../../message/screens/maintenance.dart';

part 'mismatch.rsflow.g.dart';

@FlowGraph(surface: Surface.onboarding)
const categorizedMismatch = FlowDefinition(
  start: MaintenanceNotice,
  transitions: [
    Transition.complete(MaintenanceNotice.dismiss),
  ],
);
