import 'package:restage/restage.dart';

import '../screens/profile.dart';

part 'profile_flow.rsflow.g.dart';

@FlowSource(id: 'profile_flow', version: 1, minClient: 1)
final class ProfileFlow extends RestageFlow {
  const ProfileFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');

    return flow(
      initial: ProfileScreenDescriptor.ref,
      flowState: const {
        'profileName': FlowStateDeclaration(
          type: FlowDataType.string,
          classification: FlowStateClassification.internal,
        ),
      },
      states: [
        screen(ProfileScreenDescriptor.ref).on(ProfileScreen.finish).goTo(done),
        end(done, result: {}),
      ],
    );
  }
}
