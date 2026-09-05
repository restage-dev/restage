import 'package:restage/restage.dart';

import '../screens/lumen_experience.dart';
import '../screens/lumen_goal.dart';
import '../screens/lumen_recap.dart';
import '../screens/lumen_reminder.dart';
import '../screens/lumen_welcome.dart';

part 'restage.generated/lumen_onboarding.restage.g.dart';

/// A meditation onboarding flow that ends on an embedded subscription paywall.
///
/// The shape: welcome → two linear personalization questions (experience, goal)
/// → a reminder **host-action gate** (the one conditional the flow runtime
/// offers — advance only on a granted result) → a recap → the meditation
/// welcome offer as the final flow screen via `paywallScreen(...)`, whose continue
/// action ends the flow. The paywall's close and terms controls leave the
/// graph as declared custom events.
///
/// The questions are linear by design: the flow runtime authors exactly one
/// forward transition per screen, so a personalization answer tailors the
/// experience rather than forking the graph (the faithful pattern — real
/// onboardings capture answers for tailoring, not an immediate path fork).
@FlowGraph(surface: Surface.onboarding)
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
    final done = endState('done');

    return flow(
      initial: lumenWelcomeScreenRef,
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
        screen(lumenGoalScreenRef)
            .on(LumenGoalScreen.next)
            .goTo(lumenReminderScreenRef),
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
