import 'package:restage/restage.dart';

import '../screens/reel_frequency.dart';
import '../screens/reel_kept.dart';
import '../screens/reel_offer.dart';
import '../screens/reel_reason.dart';

part 'restage.generated/reel_cancel.restage.g.dart';

/// A "before you cancel" retention survey: two linear questions → a save-offer
/// **host-action gate** → a retained confirmation.
///
/// The shape: two multiple-choice questions (linear — the answers are collected
/// for server-side analysis, they do not fork the graph), then the save-offer
/// screen runs the `redeemOffer` host action and advances to the confirmation
/// **only when the redemption succeeds** (the one conditional the flow runtime
/// offers). The save-offer's "No thanks, cancel" is a host-handled custom event
/// (confirm the cancellation); the decline is host-owned, not a second graph
/// transition. The terminal result is a data-minimization-filtered `retained`
/// outcome the host collects.
@FlowGraph(surface: Surface.onboarding)
final class ReelCancelFlow extends RestageFlow {
  /// Host action that applies the retention discount and reports the redemption.
  /// The flow advances to the confirmation only on a redeemed result.
  static const redeemOffer = FlowActionRef<void, OfferDecision>('redeemOffer');

  const ReelCancelFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');

    return flow(
      initial: reelReasonScreenRef,
      flowState: const {
        'retained': FlowStateDeclaration(
          type: FlowDataType.bool,
          classification: FlowStateClassification.exportable,
        ),
      },
      outbound: const FlowOutboundDeclarations(
        terminalResult: FlowOutboundPayloadDeclaration(
          fields: {
            'retained': FlowOutboundField(
              type: FlowDataType.bool,
              ref: StateFlowOutboundRef(key: 'retained'),
            ),
          },
        ),
        customEvents: {
          // "No thanks, cancel" — handled by the host, not the flow graph.
          'cancel': FlowOutboundPayloadDeclaration(),
        },
      ),
      states: [
        screen(reelReasonScreenRef)
            .on(ReelReasonScreen.next)
            .goTo(reelFrequencyScreenRef),
        screen(reelFrequencyScreenRef)
            .on(ReelFrequencyScreen.next)
            .goTo(reelOfferScreenRef),
        screen(reelOfferScreenRef)
            .on(ReelOfferScreen.keep)
            .run(redeemOffer)
            .result((result) => result.redeemed)
            .goTo(reelKeptScreenRef),
        screen(reelKeptScreenRef).on(ReelKeptScreen.finish).goTo(done),
        end(done, result: {'retained': true}),
      ],
    );
  }
}

/// Typed result of the retention-offer host action.
final class OfferDecision {
  /// Creates an offer decision.
  const OfferDecision({required this.redeemed});

  /// Whether the retention offer was successfully redeemed.
  final bool redeemed;
}
