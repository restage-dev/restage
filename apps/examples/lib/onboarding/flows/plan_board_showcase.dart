import 'package:restage/restage.dart';

import '../screens/plan_board_showcase.dart';

part 'restage.generated/plan_board_showcase.restage.g.dart';

/// A single-state flow for the plan board showcase.
///
/// The screen's `act` event completes the flow. Its `dismiss` event is handled
/// by the host and does not transition the flow graph.
@FlowGraph(surface: Surface.onboarding)
final class PlanBoardShowcaseFlow extends RestageFlow {
  /// Const constructor.
  const PlanBoardShowcaseFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');

    return flow(
      initial: planBoardShowcaseScreenRef,
      outbound: const FlowOutboundDeclarations(
        customEvents: {
          'dismiss': FlowOutboundPayloadDeclaration(),
        },
      ),
      states: [
        screen(planBoardShowcaseScreenRef)
            .on(PlanBoardShowcaseScreen.act)
            .goTo(done),
        end(done, result: {}),
      ],
    );
  }
}
