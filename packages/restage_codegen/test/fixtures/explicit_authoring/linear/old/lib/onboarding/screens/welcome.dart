import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/welcome.restage.g.dart';

@ScreenSource(id: 'welcome')
final class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  static const next = OnboardingEvent<void>('next');

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onboardingEvent(next),
      child: const Text('Continue'),
    );
  }
}
