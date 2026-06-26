import 'package:restage/restage.dart';

import '../screens/tally_debt.dart';
import '../screens/tally_goal.dart';
import '../screens/tally_invest.dart';
import '../screens/tally_recap_debt.dart';
import '../screens/tally_recap_invest.dart';
import '../screens/tally_recap_savings.dart';
import '../screens/tally_savings.dart';
import '../screens/tally_welcome.dart';

part 'tally_onboarding.rsflow.g.dart';

/// A personal-finance onboarding that **forks on the user's money goal**.
///
/// The shape demonstrates answer-driven branching end to end:
/// - **Multi-transition screen fork** — the goal screen offers three CTAs, each
///   firing a distinct event that `.write()`s the chosen goal into flow-state
///   and routes to a *genuinely different* tailored setup screen (debt /
///   savings / investing).
/// - **Convergence** — the three setup screens advance to a single routing node.
/// - **`decision()` branch** — the node reads the captured `goal` and routes to
///   a goal-tailored recap (debt / savings / investing), so the answer the user
///   gave at the fork still drives the ending several screens later.
///
/// This is the authorable counterpart to the linear meditation onboarding: same
/// runtime, but the answer forks the path rather than just tailoring copy.
@FlowSource(id: 'tally_onboarding', version: 1)
final class TallyOnboardingFlow extends RestageFlow {
  const TallyOnboardingFlow();

  @override
  FlowDef buildFlow() {
    final route = flowNode('route');
    final done = endState('done');

    return flow(
      initial: TallyWelcomeScreenDescriptor.ref,
      flowState: const {
        'goal': FlowStateDeclaration(
          type: FlowDataType.string,
          classification: FlowStateClassification.internal,
        ),
      },
      states: [
        screen(TallyWelcomeScreenDescriptor.ref)
            .on(TallyWelcomeScreen.start)
            .goTo(TallyGoalScreenDescriptor.ref),
        // The fork: one screen, three distinct events, three destinations — the
        // chosen goal is written into flow-state on the way.
        screen(TallyGoalScreenDescriptor.ref)
            .on(TallyGoalScreen.debt)
            .write('goal', 'debt')
            .goTo(TallyDebtScreenDescriptor.ref)
            .on(TallyGoalScreen.savings)
            .write('goal', 'savings')
            .goTo(TallySavingsScreenDescriptor.ref)
            .on(TallyGoalScreen.invest)
            .write('goal', 'invest')
            .goTo(TallyInvestScreenDescriptor.ref),
        // The three tailored setup screens converge on the routing node.
        screen(TallyDebtScreenDescriptor.ref)
            .on(TallyDebtScreen.next)
            .goTo(route),
        screen(TallySavingsScreenDescriptor.ref)
            .on(TallySavingsScreen.next)
            .goTo(route),
        screen(TallyInvestScreenDescriptor.ref)
            .on(TallyInvestScreen.next)
            .goTo(route),
        // The decision routes the ending on the captured goal.
        decision(
          route,
          branches: [
            flowBranch(
              when: state('goal').equals('debt'),
              target: TallyRecapDebtScreenDescriptor.ref,
            ),
            flowBranch(
              when: state('goal').equals('savings'),
              target: TallyRecapSavingsScreenDescriptor.ref,
            ),
          ],
          defaultBranch: flowBranchTarget(TallyRecapInvestScreenDescriptor.ref),
        ),
        screen(TallyRecapDebtScreenDescriptor.ref)
            .on(TallyRecapDebtScreen.finish)
            .goTo(done),
        screen(TallyRecapSavingsScreenDescriptor.ref)
            .on(TallyRecapSavingsScreen.finish)
            .goTo(done),
        screen(TallyRecapInvestScreenDescriptor.ref)
            .on(TallyRecapInvestScreen.finish)
            .goTo(done),
        end(done, result: {}),
      ],
    );
  }
}
