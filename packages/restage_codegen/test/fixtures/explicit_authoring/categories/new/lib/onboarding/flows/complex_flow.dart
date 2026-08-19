import 'package:restage/restage.dart';

import '../screens/welcome.dart';

part 'complex_flow.rsflow.g.dart';

@FlowGraph(surface: Surface.onboarding)
final class ComplexFlow extends RestageFlow {
  const ComplexFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');

    return flow(
      initial: NeutralWelcomeDescriptor.ref,
      states: [
        screen(NeutralWelcomeDescriptor.ref)
            .on(NeutralWelcome.finish)
            .goTo(done),
        end(done, result: {}),
      ],
    );
  }
}
