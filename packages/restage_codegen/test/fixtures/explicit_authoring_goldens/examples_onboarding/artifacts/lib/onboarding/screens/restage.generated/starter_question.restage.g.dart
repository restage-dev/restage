part of '../starter_question.dart';

const starterQuestionScreenRef = NeutralFlowScreenRef(
  id: 'starter_question',
  artifactPath: 'starter_question.rfw',
  version: 1,
  minClient: 1,
);

@Deprecated('Use starterQuestionScreenRef')
abstract final class StarterQuestionScreenDescriptor {
  const StarterQuestionScreenDescriptor._();

  static const NeutralFlowScreenRef ref = starterQuestionScreenRef;
}
