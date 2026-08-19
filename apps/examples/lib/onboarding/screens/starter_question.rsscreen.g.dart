part of 'starter_question.dart';

abstract final class StarterQuestionScreenDescriptor {
  const StarterQuestionScreenDescriptor._();

  static const NeutralFlowScreenRef ref = NeutralFlowScreenRef(
    id: 'starter_question',
    artifactPath: 'starter_question.rfw',
    version: 1,
    minClient: 1,
  );
}
