import 'package:restage/restage.dart';

import '../screens/accepted.dart';
import '../screens/declined.dart';
import '../screens/start.dart';

part 'restage.generated/completion_paths.restage.g.dart';

@FlowSource(id: 'completion_paths', version: 1, minClient: 1)
final class CompletionPathsFlow extends RestageFlow {
  const CompletionPathsFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');

    return flow(
      initial: startScreenRef,
      states: [
        screen(startScreenRef)
            .on(StartScreen.accept)
            .goTo(acceptedScreenRef)
            .on(StartScreen.decline)
            .goTo(declinedScreenRef),
        screen(acceptedScreenRef).on(AcceptedScreen.finish).goTo(done),
        screen(declinedScreenRef).on(DeclinedScreen.finish).goTo(done),
        end(done, result: {}),
      ],
    );
  }
}
