import 'package:restage/restage.dart';

import 'categorized_screens.dart';

part 'restage.generated/general_flow.restage.g.dart';

@FlowGraph(id: 'general_journey', surface: Surface.general)
const generalJourney = FlowDefinition(
  start: GeneralStatus,
  transitions: [
    Transition.complete(GeneralStatus.finish),
  ],
);
