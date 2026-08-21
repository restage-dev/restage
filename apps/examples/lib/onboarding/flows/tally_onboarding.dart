import 'package:restage/restage.dart';

import '../screens/tally_debt.dart';
import '../screens/tally_goal.dart';
import '../screens/tally_invest.dart';
import '../screens/tally_recap_debt.dart';
import '../screens/tally_recap_invest.dart';
import '../screens/tally_recap_savings.dart';
import '../screens/tally_savings.dart';
import '../screens/tally_welcome.dart';

part 'restage.generated/tally_onboarding.restage.g.dart';

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
@FlowGraph(surface: Surface.onboarding)
final class TallyOnboardingFlow extends RestageFlow {
  const TallyOnboardingFlow();

  @override
  FlowDef buildFlow() {
    final route = flowNode('route');
    final done = endState('done');

    return flow(
      initial: tallyWelcomeScreenRef,
      flowState: const {
        'goal': FlowStateDeclaration(
          type: FlowDataType.string,
          classification: FlowStateClassification.internal,
        ),
      },
      states: [
        screen(tallyWelcomeScreenRef)
            .on(TallyWelcomeScreen.start)
            .goTo(tallyGoalScreenRef),
        // The fork: one screen, three distinct events, three destinations — the
        // chosen goal is written into flow-state on the way.
        screen(tallyGoalScreenRef)
            .on(TallyGoalScreen.debt)
            .write('goal', 'debt')
            .goTo(tallyDebtScreenRef)
            .on(TallyGoalScreen.savings)
            .write('goal', 'savings')
            .goTo(tallySavingsScreenRef)
            .on(TallyGoalScreen.invest)
            .write('goal', 'invest')
            .goTo(tallyInvestScreenRef),
        // The three tailored setup screens converge on the routing node.
        screen(tallyDebtScreenRef).on(TallyDebtScreen.next).goTo(route),
        screen(tallySavingsScreenRef).on(TallySavingsScreen.next).goTo(route),
        screen(tallyInvestScreenRef).on(TallyInvestScreen.next).goTo(route),
        // The decision routes the ending on the captured goal.
        decision(
          route,
          branches: [
            flowBranch(
              when: state('goal').equals('debt'),
              target: tallyRecapDebtScreenRef,
            ),
            flowBranch(
              when: state('goal').equals('savings'),
              target: tallyRecapSavingsScreenRef,
            ),
          ],
          defaultBranch: flowBranchTarget(tallyRecapInvestScreenRef),
        ),
        screen(tallyRecapDebtScreenRef)
            .on(TallyRecapDebtScreen.finish)
            .goTo(done),
        screen(tallyRecapSavingsScreenRef)
            .on(TallyRecapSavingsScreen.finish)
            .goTo(done),
        screen(tallyRecapInvestScreenRef)
            .on(TallyRecapInvestScreen.finish)
            .goTo(done),
        end(done, result: {}),
      ],
    );
  }
}
