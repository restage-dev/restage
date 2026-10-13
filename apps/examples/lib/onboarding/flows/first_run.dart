import 'package:restage/restage.dart';

import '../screens/notify.dart';
import '../screens/ready.dart';
import '../screens/value.dart';
import '../screens/welcome.dart';

part 'restage.generated/first_run.restage.g.dart';

/// First-run onboarding flow: welcome → value → notification priming → paywall.
///
/// `buildFlow()` returns the graph of screens and transitions. The build
/// generates the flow document, the typed reference, and the `FirstRunActions`
/// class your app fills in.
///
/// [requestNotifications] is a host action: your app shows the OS permission
/// dialog. The `notify` screen's `enable` event runs it and moves to `ready`
/// only when permission is granted. A decline leaves the user on that screen,
/// where "Not now" (a custom event) still moves forward.
///
/// The flow ends with a typed result. Your app's `onComplete` opens the
/// paywall, and your app handles the `skip` custom event the same way.
@FlowGraph(surface: Surface.onboarding, minClient: 6)
final class FirstRunFlow extends RestageFlow {
  /// Host action that shows the OS notification dialog and reports the grant.
  static const requestNotifications =
      FlowActionRef<void, NotificationDecision>('requestNotifications');

  const FirstRunFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');

    return flow(
      initial: welcomeScreenRef,
      flowState: const {
        'completed': FlowStateDeclaration(
          type: FlowDataType.bool,
          classification: FlowStateClassification.exportable,
        ),
      },
      outbound: const FlowOutboundDeclarations(
        terminalResult: FlowOutboundPayloadDeclaration(
          fields: {
            'completed': FlowOutboundField(
              type: FlowDataType.bool,
              ref: StateFlowOutboundRef(key: 'completed'),
            ),
          },
        ),
        customEvents: {
          // "Not now" is a custom event your app handles.
          'skip': FlowOutboundPayloadDeclaration(),
        },
      ),
      states: [
        screen(welcomeScreenRef).on(WelcomeScreen.next).goTo(valueScreenRef),
        screen(valueScreenRef).on(ValueScreen.next).goTo(notifyScreenRef),
        screen(notifyScreenRef)
            .on(NotifyScreen.enable)
            .run(requestNotifications)
            .result((result) => result.granted)
            .goTo(readyScreenRef),
        screen(readyScreenRef).on(ReadyScreen.start).goTo(done),
        end(done, result: {'completed': true}),
      ],
    );
  }
}

/// Typed result of the notification host action.
final class NotificationDecision {
  /// Creates a notification decision.
  const NotificationDecision({required this.granted});

  /// Whether the user granted the OS notification permission.
  final bool granted;
}
