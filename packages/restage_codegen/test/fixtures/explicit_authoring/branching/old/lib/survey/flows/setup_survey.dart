import 'package:restage/restage.dart';

import '../screens/explore.dart';
import '../screens/guided.dart';
import '../screens/question.dart';

part 'restage.generated/setup_survey.restage.g.dart';

@FlowSource(id: 'setup_survey', version: 1, minClient: 1)
final class SetupSurveyFlow extends RestageFlow {
  const SetupSurveyFlow();

  @override
  FlowDef buildFlow() {
    final route = flowNode('route');
    final done = endState('done');

    return flow(
      initial: questionScreenRef,
      flowState: const {
        'answer': FlowStateDeclaration(
          type: FlowDataType.string,
          classification: FlowStateClassification.exportable,
        ),
        'returningUser': FlowStateDeclaration(
          type: FlowDataType.bool,
          classification: FlowStateClassification.internal,
          defaultValue: false,
          hostSeedable: true,
        ),
      },
      outbound: const FlowOutboundDeclarations(
        terminalResult: FlowOutboundPayloadDeclaration(
          fields: {
            'answer': FlowOutboundField(
              type: FlowDataType.string,
              ref: StateFlowOutboundRef(key: 'answer'),
            ),
          },
        ),
        surveyAnswers: FlowOutboundPayloadDeclaration(
          fields: {
            'answer': FlowOutboundField(
              type: FlowDataType.string,
              ref: StateFlowOutboundRef(key: 'answer'),
            ),
          },
        ),
      ),
      states: [
        screen(questionScreenRef)
            .on(QuestionScreen.answer)
            .capture('answer')
            .goTo(route)
            .on(QuestionScreen.skip)
            .write('answer', 'skipped')
            .goTo(route),
        decision(
          route,
          branches: [
            flowBranch(
              when: state('answer').equals('guided'),
              target: guidedScreenRef,
            ),
            flowBranch(
              when: state('returningUser').equals(true),
              target: guidedScreenRef,
            ),
          ],
          defaultBranch: flowBranchTarget(exploreScreenRef),
        ),
        screen(guidedScreenRef).on(GuidedScreen.finish).goTo(done),
        screen(exploreScreenRef).on(ExploreScreen.finish).goTo(done),
        end(done, result: {}),
      ],
    );
  }
}
