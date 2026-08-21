import 'package:restage/restage.dart';

import '../screens/welcome.dart';

part 'restage.generated/welcome_flow.restage.g.dart';

@FlowSource(id: 'welcome_flow', version: 1, minClient: 1)
final class CompatibilityWelcomeFlow extends RestageFlow {
  const CompatibilityWelcomeFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');

    return flow(
      initial: compatibilityWelcomeRef,
      states: [
        screen(compatibilityWelcomeRef)
            .on(CompatibilityWelcome.finish)
            .goTo(done),
        end(done, result: {}),
      ],
    );
  }
}
