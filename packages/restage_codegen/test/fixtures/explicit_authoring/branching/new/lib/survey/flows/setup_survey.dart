import 'package:restage/restage.dart';

import '../screens/explore.dart';
import '../screens/guided.dart';
import '../screens/question.dart';

part 'setup_survey.rsflow.g.dart';

const answer = FlowStateRef<String>(
  'answer',
  classification: FlowStateClassification.exportable,
);

const returningUser = SeedableFlowStateRef<bool>(
  'returningUser',
  defaultValue: false,
);

final route = Decision(
  'route',
  branches: [
    Branch(
      when: answer.equals('guided'),
      to: GuidedScreen,
    ),
    Branch(
      when: returningUser.equals(true),
      to: GuidedScreen,
    ),
  ],
  otherwise: ExploreScreen,
);

@FlowGraph(surface: Surface.survey)
final setupSurvey = FlowDefinition(
  start: QuestionScreen,
  state: [answer, returningUser],
  transitions: [
    Transition(
      QuestionScreen.answer,
      capture: answer,
      to: route,
    ),
    Transition(
      QuestionScreen.skip,
      writes: [answer.set('skipped')],
      to: route,
    ),
    Transition.complete(GuidedScreen.finish),
    Transition.complete(ExploreScreen.finish),
  ],
  outbound: FlowOutboundPolicy(
    terminalResult: {'answer': answer},
    surveyAnswers: {'answer': answer},
  ),
);

// Generated from the declaration above; the host seed is intentionally not a
// second state-key spelling:
// const seed = SetupSurveySeed(returningUser: true);
