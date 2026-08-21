import 'package:restage/restage.dart';

import '../screens/starter_notice.dart';

part 'restage.generated/minimal_notice.restage.g.dart';

/// A single-state flow — the smallest the runtime supports, and all a one-screen
/// surface needs.
///
/// The screen's `act` event is the one graph transition: it completes the flow,
/// and the host acts on `onComplete`. The screen's `dismiss` event is a custom
/// event (no transition) the host listens for to close the surface. There is no
/// separate "message"/"notice" API — any one-screen surface is just a flow with
/// a single screen.
@FlowGraph(surface: Surface.onboarding)
final class MinimalNoticeFlow extends RestageFlow {
  /// Const constructor.
  const MinimalNoticeFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');

    return flow(
      initial: starterNoticeScreenRef,
      outbound: const FlowOutboundDeclarations(
        customEvents: {
          // The × — handled by the host, not the flow graph.
          'dismiss': FlowOutboundPayloadDeclaration(),
        },
      ),
      states: [
        screen(starterNoticeScreenRef).on(StarterNoticeScreen.act).goTo(done),
        end(done, result: {}),
      ],
    );
  }
}
