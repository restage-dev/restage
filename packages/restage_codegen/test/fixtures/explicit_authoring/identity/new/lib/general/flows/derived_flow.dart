import 'package:restage/restage.dart';

import '../screens/derived_notice.dart';

part 'derived_flow.rsflow.g.dart';

@FlowGraph(surface: Surface.general)
const derivedFlow = FlowDefinition(
  start: DerivedNotice,
  transitions: [
    Transition.complete(DerivedNotice.dismiss),
  ],
);
