import 'package:restage/restage.dart';

import '../screens/derived_notice.dart';

part 'restage.generated/derived_flow.restage.g.dart';

@FlowGraph(surface: Surface.general)
const derivedFlow = FlowDefinition(
  start: DerivedNotice,
  transitions: [
    Transition.complete(DerivedNotice.dismiss),
  ],
);
