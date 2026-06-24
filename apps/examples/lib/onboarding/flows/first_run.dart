import 'package:restage/restage.dart';

import '../screens/notify.dart';
import '../screens/ready.dart';
import '../screens/value.dart';
import '../screens/welcome.dart';

part 'first_run.rsflow.g.dart';

/// First-run onboarding flow: welcome → value → notification priming → paywall.
///
/// ## What this demonstrates
///
/// The same render pipeline that ships paywalls also drives multi-screen
/// *engagement* surfaces. A flow is authored in pure Dart: `buildFlow()`
/// returns a graph of screens and transitions, and the build-time codegen emits
/// the flow document the SDK's flow runtime interprets, plus a typed descriptor
/// and a typed action registry for the host to fill in.
///
/// ## The notification host action
///
/// [requestNotifications] is a *host action* — a capability the app owns, not
/// the flow. The flow can request it by contract, but the app supplies the
/// behavior (showing the real OS permission dialog) through the generated
/// `FirstRunActions` registry. The flow only branches on the typed result: the
/// `notify` screen's `enable` event runs the action and advances to `ready`
/// **only when the result is `granted`**. This gate is one-directional by
/// design — a declined permission leaves the user on the priming screen, where
/// the screen's "Not now" choice (a host-handled custom event) always offers a
/// way forward. The flow never proceeds on behaviour it did not get.
///
/// ## The paywall handoff
///
/// The flow ends with a typed result; it does not open a paywall itself. The
/// host's `onComplete` callback navigates to the paywall, and the host listens
/// for the `skip` custom event to do the same when the user opts out. Keeping
/// navigation in the host is the honest contract: the flow describes intent,
/// the app acts on it.
@FlowSource(id: 'first_run', version: 1)
final class FirstRunFlow extends RestageFlow {
  /// Host action that shows the OS notification dialog and reports the grant.
  static const requestNotifications =
      FlowActionRef<void, NotificationDecision>('requestNotifications');

  const FirstRunFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');

    return flow(
      initial: WelcomeScreenDescriptor.ref,
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
          // "Not now" — handled by the host, not the flow graph.
          'skip': FlowOutboundPayloadDeclaration(),
        },
      ),
      states: [
        screen(WelcomeScreenDescriptor.ref)
            .on(WelcomeScreen.next)
            .goTo(ValueScreenDescriptor.ref),
        screen(ValueScreenDescriptor.ref)
            .on(ValueScreen.next)
            .goTo(NotifyScreenDescriptor.ref),
        screen(NotifyScreenDescriptor.ref)
            .on(NotifyScreen.enable)
            .run(requestNotifications)
            .result((result) => result.granted)
            .goTo(ReadyScreenDescriptor.ref),
        screen(ReadyScreenDescriptor.ref).on(ReadyScreen.start).goTo(done),
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
