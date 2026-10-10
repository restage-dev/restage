import 'package:restage/restage.dart';

import '../screens/lumen_experience.dart';
import '../screens/lumen_goal.dart';
import '../screens/lumen_recap.dart';
import '../screens/lumen_reminder.dart';
import '../screens/lumen_welcome.dart';

part 'restage.generated/lumen_onboarding.restage.g.dart';

/// A meditation onboarding flow that ends on an embedded subscription paywall.
///
/// The shape: welcome → two personalization questions (experience, goal) → a
/// reminder **host-action gate** that advances only on a granted result → a
/// recap → the welcome offer as the final flow screen via `paywallScreen(...)`,
/// whose continue action ends the flow. The goal answer is recorded, and a
/// `decision()` sends a user who is just curious past the reminder to the
/// recap. The paywall's close and terms controls leave the graph as declared
/// custom events.
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
          classification: FlowStateClassification.internal,
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
        customEvents: {
          // Dismissing or reading the terms is host-owned; neither is a second
          // graph transition, and neither completes the flow.
          'close': FlowOutboundPayloadDeclaration(),
          'sign_in': FlowOutboundPayloadDeclaration(),
          'terms': FlowOutboundPayloadDeclaration(),
        },
      ),
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
