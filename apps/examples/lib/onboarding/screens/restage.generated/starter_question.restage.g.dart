part of '../starter_question.dart';

// ignore_for_file: type=lint

const starterQuestionScreenRef = NeutralFlowScreenRef(
  id: 'starter_question',
  artifactPath: 'starter_question.rfw',
  version: 1,
  minClient: 10,
);

@Deprecated('Use starterQuestionScreenRef')
abstract final class StarterQuestionScreenDescriptor {
  const StarterQuestionScreenDescriptor._();

  static const NeutralFlowScreenRef ref = starterQuestionScreenRef;
}
