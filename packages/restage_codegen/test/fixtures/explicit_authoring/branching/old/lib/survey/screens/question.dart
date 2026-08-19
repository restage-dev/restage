import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/question.restage.g.dart';

@ScreenSource(id: 'question')
final class QuestionScreen extends StatelessWidget {
  const QuestionScreen({super.key});

  static const answer = OnboardingEvent<String>('answer');
  static const skip = OnboardingEvent<void>('skip');

  @override
  Widget build(BuildContext context) => const Text('Question');
}
