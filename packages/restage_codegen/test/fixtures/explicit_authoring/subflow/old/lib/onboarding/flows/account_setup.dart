import 'package:restage/restage.dart';

import '../screens/account.dart';
import '../screens/error.dart';
import 'profile_flow.dart';

part 'account_setup.rsflow.g.dart';

const profileChildFlow = OnboardingFlowRef<Map<String, Object?>>(
  id: 'profile_flow',
  version: 1,
  minClient: 1,
  decodeResult: _decodeProfileChild,
);

Map<String, Object?> _decodeProfileChild(Map<String, Object?> result) => result;

@FlowSource(id: 'account_setup', version: 1, minClient: 1)
final class AccountSetupFlow extends RestageFlow {
  const AccountSetupFlow();

  @override
  FlowDef buildFlow() {
    final profile = flowNode('profile');
    final done = endState('done');

    return flow(
      initial: AccountScreenDescriptor.ref,
      flowState: const {
        'accountName': FlowStateDeclaration(
          type: FlowDataType.string,
          classification: FlowStateClassification.internal,
        ),
      },
      states: [
        screen(AccountScreenDescriptor.ref)
            .on(AccountScreen.profile)
            .goTo(profile),
        subFlow(
          profile,
          flow: profileChildFlow,
          input: const {
            'profileName': StateFlowValueSource(key: 'accountName'),
          },
          onComplete: [
            flowBranch(
              when: const FlowBranchPredicate(fields: {}),
              target: done,
            ),
          ],
          defaultBranch: flowBranchTarget(done),
          subFlowUnavailable: flowBranchTarget(ErrorScreenDescriptor.ref),
        ),
        screen(ErrorScreenDescriptor.ref),
        end(done, result: {}),
      ],
    );
  }
}
