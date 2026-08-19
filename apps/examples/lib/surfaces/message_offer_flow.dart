import 'package:restage/restage.dart';

import 'categorized_screens.dart';
import 'upgrade_offer.dart';

part 'restage.generated/message_offer_flow.restage.g.dart';

@FlowGraph(id: 'message_offer', surface: Surface.message)
const messageOffer = FlowDefinition(
  start: MessageNotice,
  transitions: [
    Transition(MessageNotice.openOffer, to: UpgradeOffer),
    Transition.complete(
      PaywallEvents.purchase,
      from: UpgradeOffer,
    ),
  ],
);
