import 'package:restage/restage.dart';

import '../paywalls/lumen_welcome_offer.dart';
import 'lumen_trial_ending.dart';

part 'restage.generated/lumen_trial_ending_flow.restage.g.dart';

/// A trial-ending message that leads into the meditation app's welcome offer.
///
/// The nudge opens the offer; "Maybe later" and the offer's close control end
/// the message. Every path converges on the one terminal the flow runtime
/// allows.
@FlowGraph(id: 'lumen_trial_offer', surface: Surface.message)
const lumenTrialOffer = FlowDefinition(
  start: LumenTrialEndingScreen,
  transitions: [
    Transition(LumenTrialEndingScreen.openOffer, to: LumenWelcomeOfferPaywall),
    Transition.complete(LumenTrialEndingScreen.later),
    Transition.complete(LumenWelcomeOfferPaywall.continueFlow),
    Transition.complete(LumenWelcomeOfferPaywall.close),
  ],
);
