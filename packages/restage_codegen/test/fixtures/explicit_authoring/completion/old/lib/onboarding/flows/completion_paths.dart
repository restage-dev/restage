import 'package:restage/restage.dart';

import '../screens/accepted.dart';
import '../screens/declined.dart';
import '../screens/start.dart';

part 'completion_paths.rsflow.g.dart';

@FlowSource(id: 'completion_paths', version: 1, minClient: 1)
final class CompletionPathsFlow extends RestageFlow {
  const CompletionPathsFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');

    return flow(
      initial: StartScreenDescriptor.ref,
      states: [
        screen(StartScreenDescriptor.ref)
            .on(StartScreen.accept)
            .goTo(AcceptedScreenDescriptor.ref)
            .on(StartScreen.decline)
            .goTo(DeclinedScreenDescriptor.ref),
        screen(AcceptedScreenDescriptor.ref)
            .on(AcceptedScreen.finish)
            .goTo(done),
        screen(DeclinedScreenDescriptor.ref)
            .on(DeclinedScreen.finish)
            .goTo(done),
        end(done, result: {}),
      ],
    );
  }
}
