import 'package:restage/restage.dart';

import '../screens/offer_intro.dart';
import '../../paywalls/premium.dart';

part 'restage.generated/first_run_flow.restage.g.dart';

@FlowSource(id: 'first_run_flow', version: 1, minClient: 1)
final class FirstRunFlow extends RestageFlow {
  const FirstRunFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');

    return flow(
      initial: offerIntroScreenRef,
      states: [
        screen(offerIntroScreenRef)
            .on(OfferIntroScreen.next)
            .goTo(paywallScreen('premium')),
        screen(paywallScreen('premium'))
            .on(PaywallFlowEvents.purchase)
            .goTo(done),
        end(done, result: {}),
      ],
    );
  }
}
