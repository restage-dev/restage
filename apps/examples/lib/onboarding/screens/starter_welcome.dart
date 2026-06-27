import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'starter_welcome.rsscreen.g.dart';

/// Starter onboarding — the welcome screen.
///
/// A `@ScreenSource` is one screen of a flow, authored in ordinary Flutter.
/// Each thing the user can do is an [OnboardingEvent]; `onboardingEvent(...)`
/// wires it to a tap. The flow decides where `next` goes — here, to the
/// question screen.
@ScreenSource(id: 'starter_welcome')
class StarterWelcomeScreen extends StatelessWidget {
  /// Advances to the first question.
  static const next = OnboardingEvent<void>('next');

  /// Const constructor.
  const StarterWelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Text(
                'Welcome',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'A quick question to set things up the way you like.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.4,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: onboardingEvent(next),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Get started'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
