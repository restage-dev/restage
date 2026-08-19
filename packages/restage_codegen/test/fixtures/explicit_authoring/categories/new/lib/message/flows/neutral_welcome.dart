import 'package:restage/restage.dart';

import '../../onboarding/screens/welcome.dart';

part 'neutral_welcome.rsflow.g.dart';

@FlowGraph(surface: Surface.message)
const messageWelcome = FlowDefinition(
  start: NeutralWelcome,
  transitions: [
    Transition.complete(NeutralWelcome.finish),
  ],
);
