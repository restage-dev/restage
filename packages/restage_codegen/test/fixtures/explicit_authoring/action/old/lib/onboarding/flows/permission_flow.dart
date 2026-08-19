import 'package:restage/restage.dart';

import '../screens/permission.dart';
import '../screens/ready.dart';

part 'restage.generated/permission_flow.restage.g.dart';

@FlowSource(id: 'permission_flow', version: 1, minClient: 1)
final class PermissionFlow extends RestageFlow {
  static const requestNotifications =
      FlowActionRef<void, bool>('requestNotifications');

  const PermissionFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');

    return flow(
      initial: PermissionScreenDescriptor.ref,
      states: [
        screen(PermissionScreenDescriptor.ref)
            .on(PermissionScreen.enable)
            .run(requestNotifications)
            .result((granted) => granted)
            .goTo(ReadyScreenDescriptor.ref),
        screen(ReadyScreenDescriptor.ref).on(ReadyScreen.finish).goTo(done),
        end(done, result: {}),
      ],
    );
  }
}
