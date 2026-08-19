import 'package:restage/restage.dart';

import '../screens/offer.dart';
import '../../paywalls/general_premium.dart';

part 'restage.generated/general_offer.restage.g.dart';

@FlowGraph(surface: Surface.general)
const generalOffer = FlowDefinition(
  start: GeneralOfferScreen,
  transitions: [
    Transition(GeneralOfferScreen.showPaywall, to: GeneralPaywall),
    Transition.complete(
      PaywallEvents.purchase,
      from: GeneralPaywall,
    ),
  ],
);
