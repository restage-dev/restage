import 'package:restage/restage.dart';

import '../screens/profile.dart';

part 'restage.generated/profile_flow.restage.g.dart';

@FlowSource(id: 'profile_flow', version: 1, minClient: 1)
final class ProfileFlow extends RestageFlow {
  const ProfileFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');

    return flow(
      initial: profileScreenRef,
      flowState: const {
        'profileName': FlowStateDeclaration(
          type: FlowDataType.string,
          classification: FlowStateClassification.internal,
        ),
      },
      states: [
        screen(profileScreenRef).on(ProfileScreen.finish).goTo(done),
        end(done, result: {}),
      ],
    );
  }
}
