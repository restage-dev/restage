import 'package:restage/restage.dart';

import '../screens/reel_frequency.dart';
import '../screens/reel_kept.dart';
import '../screens/reel_offer.dart';
import '../screens/reel_reason.dart';

part 'restage.generated/reel_cancel.restage.g.dart';

/// A "before you cancel" survey: two questions, a save offer, then a
/// confirmation.
///
/// The answers are collected for analysis and don't change the path. The save
/// offer runs the `redeemOffer` host action and moves to the confirmation only when
/// the redemption succeeds. "No thanks, cancel" is a custom event your app handles
/// by confirming the cancellation. The flow's result is a `retained` outcome,
/// filtered to the state the flow exports.
@FlowGraph(surface: Surface.onboarding, minClient: 6)
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
          // "No thanks, cancel" is a custom event your app handles.
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
