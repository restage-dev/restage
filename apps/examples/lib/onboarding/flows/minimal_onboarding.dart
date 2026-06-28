import 'package:restage/restage.dart';

import '../screens/starter_done_explore.dart';
import '../screens/starter_done_guided.dart';
import '../screens/starter_question.dart';
import '../screens/starter_welcome.dart';

part 'minimal_onboarding.rsflow.g.dart';

/// A minimal onboarding flow that navigates, captures an answer, branches on
/// it, and completes — the smallest honest answer-driven onboarding.
///
/// The shape:
/// - **welcome → question** — an ordinary linear transition.
/// - **the fork** — the question's two options each `write` the chosen `mode`
///   into flow-state, then converge on a routing node.
/// - **the decision** — `route` reads the captured `mode` and sends the user to
///   the matching ending screen, so the answer still drives the path.
///
/// Same runtime as any flow; only the authoring (this DSL) changes per surface.
@FlowSource(id: 'minimal_onboarding', version: 1)
final class MinimalOnboardingFlow extends RestageFlow {
  /// Const constructor.
  const MinimalOnboardingFlow();

  @override
  FlowDef buildFlow() {
    final route = flowNode('route');
    final done = endState('done');

    return flow(
      initial: StarterWelcomeScreenDescriptor.ref,
      flowState: const {
        'mode': FlowStateDeclaration(
          type: FlowDataType.string,
          classification: FlowStateClassification.internal,
        ),
      },
      states: [
        screen(StarterWelcomeScreenDescriptor.ref)
            .on(StarterWelcomeScreen.next)
            .goTo(StarterQuestionScreenDescriptor.ref),
        // The fork: one screen, two events, the chosen answer written on the way.
        screen(StarterQuestionScreenDescriptor.ref)
            .on(StarterQuestionScreen.guided)
            .write('mode', 'guided')
            .goTo(route)
            .on(StarterQuestionScreen.explore)
            .write('mode', 'explore')
            .goTo(route),
        // The decision routes the ending on the captured answer.
        decision(
          route,
          branches: [
            flowBranch(
              when: state('mode').equals('guided'),
              target: StarterDoneGuidedScreenDescriptor.ref,
            ),
          ],
          defaultBranch:
              flowBranchTarget(StarterDoneExploreScreenDescriptor.ref),
        ),
        screen(StarterDoneGuidedScreenDescriptor.ref)
            .on(StarterDoneGuidedScreen.finish)
            .goTo(done),
        screen(StarterDoneExploreScreenDescriptor.ref)
            .on(StarterDoneExploreScreen.finish)
            .goTo(done),
        end(done, result: {}),
      ],
    );
  }
}
