import 'package:restage/restage.dart';

import '../screens/stride_goals.dart';
import '../screens/stride_ready.dart';
import '../screens/stride_reminders.dart';
import '../screens/stride_welcome.dart';

part 'restage.generated/stride_first_run.restage.g.dart';

/// Onboarding with a reminder action and a `Map<String, Object?>` result.
/// General delivery lets the graph change over the air, using only the actions
/// and events the installed app already has.
@FlowGraph(
  surface: Surface.onboarding,
  version: 2,
  delivery: FlowDeliveryMode.general,
  minClient: 6,
)
final class StrideFirstRunFlow extends RestageFlow {
  /// Host action that shows the OS notification dialog and reports the grant.
  static const requestNotifications =
      FlowActionRef<void, ReminderDecision>('requestNotifications');

  const StrideFirstRunFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');

    return flow(
      initial: strideWelcomeScreenRef,
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
          // "Maybe later" is a custom event your app handles.
          'skip': FlowOutboundPayloadDeclaration(),
        },
      ),
      states: [
        screen(strideWelcomeScreenRef)
            .on(StrideWelcomeScreen.start)
            .goTo(strideGoalsScreenRef),
        screen(strideGoalsScreenRef)
            .on(StrideGoalsScreen.next)
            .goTo(strideRemindersScreenRef),
        screen(strideRemindersScreenRef)
            .on(StrideRemindersScreen.enable)
            .run(requestNotifications)
            .result((result) => result.granted)
            .goTo(strideReadyScreenRef),
        screen(strideReadyScreenRef).on(StrideReadyScreen.begin).goTo(done),
        end(done, result: {'completed': true}),
      ],
    );
  }
}

/// Typed result of the notification host action.
final class ReminderDecision {
  /// Creates a reminder decision.
  const ReminderDecision({required this.granted});

  /// Whether the user granted the OS notification permission.
  final bool granted;
}
