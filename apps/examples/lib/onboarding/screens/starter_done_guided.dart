import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'starter_done_guided.rsscreen.g.dart';

/// Starter onboarding — the "guided" ending.
///
/// The decision routes here when the user chose the guided path. It is a real,
/// distinct screen (not a recoloured shared one), so the fork is visible in the
/// delivered surface itself. `finish` completes the flow.
@ScreenSource(id: 'starter_done_guided')
class StarterDoneGuidedScreen extends StatelessWidget {
  /// Completes onboarding.
  static const finish = OnboardingEvent<void>('finish');

  /// Const constructor.
  const StarterDoneGuidedScreen({super.key});

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
              Icon(
                Icons.route_rounded,
                size: 56,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 20),
              Text(
                "Great — we'll walk you through it.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: onboardingEvent(finish),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Start the tour'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
