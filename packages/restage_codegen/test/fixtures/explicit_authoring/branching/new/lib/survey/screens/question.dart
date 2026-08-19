import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/question.restage.g.dart';

@Screen()
final class QuestionScreen extends StatelessWidget {
  const QuestionScreen({super.key});

  static const answer = SurfaceEvent<String>('answer');
  static const skip = SurfaceEvent<void>('skip');

  @override
  Widget build(BuildContext context) => const Text('Question');
}
