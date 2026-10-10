import 'package:restage/restage.dart';

import '../screens/lumen_experience.dart';
import '../screens/lumen_goal.dart';
import '../screens/lumen_recap.dart';
import '../screens/lumen_reminder.dart';
import '../screens/lumen_welcome.dart';

part 'restage.generated/lumen_onboarding.restage.g.dart';

/// Meditation onboarding with experience and goal questions, a reminder gate,
/// and an embedded subscription paywall. Curious users skip the reminder;
/// others advance only when permission is granted. The paywall continues to
/// the end of the flow.
/// The goal is measured; closing the paywall or opening terms emits custom events.
@FlowGraph(surface: Surface.onboarding, minClient: 6)
final class LumenOnboardingFlow extends RestageFlow {
  /// Host action that requests the daily-reminder permission and reports the
  /// grant. The flow advances to the recap only on a granted result.
  static const enableReminders =
      FlowActionRef<void, ReminderDecision>('enableReminders');

  /// Continues from the embedded plan selector.
  static const continueFlow = SurfaceEvent<Map<String, Object?>>('continue');

  const LumenOnboardingFlow();

  @override
  FlowDef buildFlow() {
    final route = flowNode('route');
    final done = endState('done');

    return flow(
      initial: lumenWelcomeScreenRef,
      flowState: const {
        'goal': FlowStateDeclaration(
          type: FlowDataType.string,
          classification: FlowStateClassification.exportable,
        ),
      },
      outbound: const FlowOutboundDeclarations(
        terminalResult: FlowOutboundPayloadDeclaration(
          fields: {
            'completed': FlowOutboundField(
              type: FlowDataType.bool,
              ref: EventFlowOutboundRef(key: 'completed'),
            ),
          },
        ),
        surveyAnswers: FlowOutboundPayloadDeclaration(
          fields: {
            'goal': FlowOutboundField(
              type: FlowDataType.string,
              ref: StateFlowOutboundRef(key: 'goal'),
            ),
          },
        ),
        customEvents: {
          // Dismissing or reading the terms is host-owned; neither is a second
          // graph transition, and neither completes the flow.
          'close': FlowOutboundPayloadDeclaration(),
          'sign_in': FlowOutboundPayloadDeclaration(),
          'terms': FlowOutboundPayloadDeclaration(),
        },
      ),
      measurementAnswers: const {
        'goal': FlowAnswerMeasurement.category(
          outcomeKey: 'onboarding.goal',
          propertyName: 'goal',
          categoryLabels: {
            'sleep': 'Sleep better',
            'stress': 'Less stress',
            'focus': 'Deeper focus',
            'curious': 'Just curious',
          },
        ),
      },
      states: [
        screen(lumenWelcomeScreenRef)
            .on(LumenWelcomeScreen.next)
            .goTo(lumenExperienceScreenRef),
        screen(lumenExperienceScreenRef)
            .on(LumenExperienceScreen.next)
            .goTo(lumenGoalScreenRef),
        // Each answer is recorded on the way to the routing node.
        screen(lumenGoalScreenRef)
            .on(LumenGoalScreen.sleep)
            .write('goal', 'sleep')
            .goTo(route)
            .on(LumenGoalScreen.stress)
            .write('goal', 'stress')
            .goTo(route)
            .on(LumenGoalScreen.focus)
            .write('goal', 'focus')
            .goTo(route)
            .on(LumenGoalScreen.curious)
            .write('goal', 'curious')
            .goTo(route)
            .on(LumenGoalScreen.next)
            .goTo(route),
        // A user who is just curious skips the reminder.
        decision(
          route,
          branches: [
            flowBranch(
              when: state('goal').equals('curious'),
              target: lumenRecapScreenRef,
            ),
          ],
          defaultBranch: flowBranchTarget(lumenReminderScreenRef),
        ),
        screen(lumenReminderScreenRef)
            .on(LumenReminderScreen.enable)
            .run(enableReminders)
            .result((result) => result.granted)
            .goTo(lumenRecapScreenRef),
        screen(lumenRecapScreenRef)
            .on(LumenRecapScreen.next)
            .goTo(paywallScreen('lumen_welcome_offer')),
        screen(paywallScreen('lumen_welcome_offer'))
            .on(LumenOnboardingFlow.continueFlow)
            .goTo(done),
        end(done, result: {'completed': true}),
      ],
    );
  }
}

/// Typed result of the reminder host action.
final class ReminderDecision {
  /// Creates a reminder decision.
  const ReminderDecision({required this.granted});

  /// Whether the user granted the OS reminder permission.
  final bool granted;
}
