import 'package:restage/restage.dart';

import '../paywalls/lumen_premium.dart';
import 'lumen_trial_ending.dart';

part 'restage.generated/lumen_trial_ending_flow.restage.g.dart';

/// A trial-ending message that leads into the meditation app's plan selector.
///
/// The nudge opens the plan selector; "Maybe later" completes the message
/// directly. Both paths converge on the one terminal the flow runtime allows.
@FlowGraph(id: 'lumen_trial_offer', surface: Surface.message)
const lumenTrialOffer = FlowDefinition(
  start: LumenTrialEndingScreen,
  transitions: [
    Transition(LumenTrialEndingScreen.openOffer, to: LumenPremiumPaywall),
    Transition.complete(LumenTrialEndingScreen.later),
    Transition.complete(LumenPremiumPaywall.continueFlow),
  ],
);
