import 'package:restage/restage.dart';

import '../screens/profile.dart';
import '../screens/welcome.dart';

part 'restage.generated/welcome_flow.restage.g.dart';

@FlowSource(id: 'welcome_flow', version: 1, minClient: 1)
final class WelcomeFlow extends RestageFlow {
  const WelcomeFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');

    return flow(
      initial: welcomeScreenRef,
      states: [
        screen(welcomeScreenRef).on(WelcomeScreen.next).goTo(profileScreenRef),
        screen(profileScreenRef).on(ProfileScreen.finish).goTo(done),
        end(done, result: {}),
      ],
    );
  }
}
