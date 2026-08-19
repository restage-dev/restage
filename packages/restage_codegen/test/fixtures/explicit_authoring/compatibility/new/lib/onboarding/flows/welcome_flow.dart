import 'package:restage/restage.dart';

import '../screens/welcome.dart';

part 'restage.generated/welcome_flow.restage.g.dart';

@FlowGraph(surface: Surface.onboarding)
const compatibilityWelcome = FlowDefinition(
  start: CompatibilityWelcome,
  transitions: [
    Transition.complete(CompatibilityWelcome.finish),
  ],
);
