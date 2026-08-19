import 'package:restage/restage.dart';

import '../screens/offer_intro.dart';
import '../../paywalls/premium.dart';

part 'first_run_flow.rsflow.g.dart';

@FlowGraph(surface: Surface.onboarding)
const firstRunFlow = FlowDefinition(
  start: OfferIntroScreen,
  transitions: [
    Transition(OfferIntroScreen.next, to: PremiumPaywall),
    Transition.complete(
      PaywallEvents.purchase,
      from: PremiumPaywall,
    ),
  ],
);
