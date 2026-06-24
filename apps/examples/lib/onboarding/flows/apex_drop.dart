import 'package:restage/restage.dart';

import '../screens/apex_drop.dart';

part 'apex_drop.rsflow.g.dart';

/// A single-state message flow: one screen, one terminal state.
///
/// This is the smallest flow the runtime supports, and it is all a message
/// needs. The screen's `act` event is the one graph transition — it completes
/// the flow, and the host acts on `onComplete`. The screen's `dismiss` event is
/// a custom event (no graph transition); the host listens for it and closes the
/// message. There is no separate "message" API — a message is just a flow that
/// happens to have a single screen.
@FlowSource(id: 'apex_drop', version: 1)
final class ApexDropFlow extends RestageFlow {
  const ApexDropFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');

    return flow(
      initial: ApexDropScreenDescriptor.ref,
      outbound: const FlowOutboundDeclarations(
        customEvents: {
          // The × — handled by the host, not the flow graph.
          'dismiss': FlowOutboundPayloadDeclaration(),
        },
      ),
      states: [
        screen(ApexDropScreenDescriptor.ref).on(ApexDropScreen.act).goTo(done),
        end(done, result: {}),
      ],
    );
  }
}
