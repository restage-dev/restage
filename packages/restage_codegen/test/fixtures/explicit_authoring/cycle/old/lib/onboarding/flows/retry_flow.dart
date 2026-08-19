import 'package:restage/restage.dart';

import '../screens/failure.dart';
import '../screens/retry_screen.dart';
import '../screens/start.dart';

part 'restage.generated/retry_flow.restage.g.dart';

@FlowSource(id: 'retry_flow', version: 1, minClient: 1)
final class RetryFlow extends RestageFlow {
  const RetryFlow();

  @override
  FlowDef buildFlow() {
    final retry = flowNode('retry');
    final done = endState('done');

    return flow(
      initial: StartScreenDescriptor.ref,
      flowState: const {
        'attempts': FlowStateDeclaration(
          type: FlowDataType.int,
          classification: FlowStateClassification.internal,
          defaultValue: 0,
        ),
      },
      states: [
        screen(StartScreenDescriptor.ref).on(StartScreen.next).goTo(retry),
        decision(
          retry,
          branches: [
            flowBranch(
              when: state('attempts').lessThan(3),
              target: RetryScreenDescriptor.ref,
            ),
          ],
          defaultBranch: flowBranchTarget(FailureScreenDescriptor.ref),
        ),
        screen(RetryScreenDescriptor.ref)
            .on(RetryScreen.failed)
            .goTo(retry)
            .on(RetryScreen.succeeded)
            .goTo(done),
        screen(FailureScreenDescriptor.ref).on(FailureScreen.finish).goTo(done),
        end(done, result: {}),
      ],
    );
  }
}
