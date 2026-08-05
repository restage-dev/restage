import 'package:restage/restage.dart';

import '../screens/plan_board_showcase.dart';

part 'plan_board_showcase.rsflow.g.dart';

/// A single-state flow for the plan board showcase.
///
/// The screen's `act` event completes the flow. Its `dismiss` event is handled
/// by the host and does not transition the flow graph.
@FlowSource(id: 'plan_board_showcase', version: 1)
final class PlanBoardShowcaseFlow extends RestageFlow {
  /// Const constructor.
  const PlanBoardShowcaseFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');

    return flow(
      initial: PlanBoardShowcaseScreenDescriptor.ref,
      outbound: const FlowOutboundDeclarations(
        customEvents: {
          'dismiss': FlowOutboundPayloadDeclaration(),
        },
      ),
      states: [
        screen(PlanBoardShowcaseScreenDescriptor.ref)
            .on(PlanBoardShowcaseScreen.act)
            .goTo(done),
        end(done, result: {}),
      ],
    );
  }
}
