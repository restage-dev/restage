import 'package:restage/restage.dart';

import '../screens/offer_intro.dart';
import '../../paywalls/premium.dart';

part 'first_run_flow.rsflow.g.dart';

@FlowSource(id: 'first_run_flow', version: 1, minClient: 1)
final class FirstRunFlow extends RestageFlow {
  const FirstRunFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');

    return flow(
      initial: OfferIntroScreenDescriptor.ref,
      states: [
        screen(OfferIntroScreenDescriptor.ref)
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
