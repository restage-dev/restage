import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/start.restage.g.dart';

@ScreenSource(id: 'start')
final class StartScreen extends StatelessWidget {
  const StartScreen({super.key});

  static const next = OnboardingEvent<void>('next');

  @override
  Widget build(BuildContext context) => const Text('Start');
}
