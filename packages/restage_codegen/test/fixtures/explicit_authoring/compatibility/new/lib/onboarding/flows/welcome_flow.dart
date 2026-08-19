import 'package:restage/restage.dart';

import '../screens/welcome.dart';

part 'welcome_flow.rsflow.g.dart';

@FlowGraph(surface: Surface.onboarding)
const compatibilityWelcome = FlowDefinition(
  start: CompatibilityWelcome,
  transitions: [
    Transition.complete(CompatibilityWelcome.finish),
  ],
);
