import 'package:restage/restage.dart';

import '../screens/moved_notice.dart';

part 'restage.generated/moved_flow.restage.g.dart';

@FlowGraph(id: 'stable_flow', surface: Surface.message)
const movedFlow = FlowDefinition(
  start: MovedNotice,
  transitions: [
    Transition.complete(MovedNotice.dismiss),
  ],
);
