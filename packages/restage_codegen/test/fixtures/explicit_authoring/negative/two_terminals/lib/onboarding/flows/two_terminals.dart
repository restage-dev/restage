import 'package:restage/restage.dart';

import '../screens/start.dart';

part 'two_terminals.rsflow.g.dart';

@FlowGraph(surface: Surface.onboarding)
const twoTerminals = FlowDefinition(
  start: TerminalStart,
  transitions: [
    Transition.complete(TerminalStart.finish, id: 'done'),
    Transition.complete(TerminalStart.cancel, id: 'cancelled'),
  ],
);
