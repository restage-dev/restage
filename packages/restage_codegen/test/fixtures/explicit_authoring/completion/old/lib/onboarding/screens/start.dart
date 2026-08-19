import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'start.rsscreen.g.dart';

@ScreenSource(id: 'start')
final class StartScreen extends StatelessWidget {
  const StartScreen({super.key});

  static const accept = OnboardingEvent<void>('accept');
  static const decline = OnboardingEvent<void>('decline');

  @override
  Widget build(BuildContext context) => const Text('Start');
}
