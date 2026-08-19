import 'package:restage/restage.dart';

import '../../onboarding/screens/welcome.dart';

part 'restage.generated/neutral_welcome.restage.g.dart';

@FlowGraph(surface: Surface.message)
const messageWelcome = FlowDefinition(
  start: NeutralWelcome,
  transitions: [
    Transition.complete(NeutralWelcome.finish),
  ],
);
