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
      initial: permissionScreenRef,
      states: [
        screen(permissionScreenRef)
            .on(PermissionScreen.enable)
            .run(requestNotifications)
            .result((granted) => granted)
            .goTo(readyScreenRef),
        screen(readyScreenRef).on(ReadyScreen.finish).goTo(done),
        end(done, result: {}),
      ],
    );
  }
}
