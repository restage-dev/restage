import 'package:restage/restage.dart';

import '../screens/lumen_experience.dart';
import '../screens/lumen_goal.dart';
import '../screens/lumen_recap.dart';
import '../screens/lumen_reminder.dart';
import '../screens/lumen_welcome.dart';

part 'lumen_onboarding.rsflow.g.dart';

/// A meditation onboarding flow that ends on an embedded subscription paywall.
///
/// The shape: welcome → two linear personalization questions (experience, goal)
/// → a reminder **host-action gate** (the one conditional the flow runtime
/// offers — advance only on a granted result) → a recap → the meditation
/// paywall as the final flow screen via `paywallScreen(...)`, whose purchase
/// ends the flow.
///
/// The questions are linear by design: the flow runtime authors exactly one
/// forward transition per screen, so a personalization answer tailors the
/// experience rather than forking the graph (the faithful pattern — real
/// onboardings capture answers for tailoring, not an immediate path fork).
@FlowSource(id: 'lumen_onboarding', version: 1)
final class LumenOnboardingFlow extends RestageFlow {
  /// Host action that requests the daily-reminder permission and reports the
  /// grant. The flow advances to the recap only on a granted result.
  static const enableReminders =
      FlowActionRef<void, ReminderDecision>('enableReminders');

  const LumenOnboardingFlow();

  @override
  FlowDef buildFlow() {
    final done = endState('done');

    return flow(
      initial: LumenWelcomeScreenDescriptor.ref,
      outbound: const FlowOutboundDeclarations(
        terminalResult: FlowOutboundPayloadDeclaration(
          fields: {
            'subscribed': FlowOutboundField(
              type: FlowDataType.bool,
              ref: EventFlowOutboundRef(key: 'subscribed'),
            ),
          },
        ),
      ),
      states: [
        screen(LumenWelcomeScreenDescriptor.ref)
            .on(LumenWelcomeScreen.next)
            .goTo(LumenExperienceScreenDescriptor.ref),
        screen(LumenExperienceScreenDescriptor.ref)
            .on(LumenExperienceScreen.next)
            .goTo(LumenGoalScreenDescriptor.ref),
        screen(LumenGoalScreenDescriptor.ref)
            .on(LumenGoalScreen.next)
            .goTo(LumenReminderScreenDescriptor.ref),
        screen(LumenReminderScreenDescriptor.ref)
            .on(LumenReminderScreen.enable)
            .run(enableReminders)
            .result((result) => result.granted)
            .goTo(LumenRecapScreenDescriptor.ref),
        screen(LumenRecapScreenDescriptor.ref)
            .on(LumenRecapScreen.next)
            .goTo(paywallScreen('lumen_premium')),
        screen(paywallScreen('lumen_premium'))
            .on(PaywallFlowEvents.purchase)
            .goTo(done),
        end(done, result: {'subscribed': true}),
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
