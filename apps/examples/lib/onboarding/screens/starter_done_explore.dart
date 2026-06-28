import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'starter_done_explore.rsscreen.g.dart';

/// Starter onboarding — the "explore" ending.
///
/// The decision routes here when the user chose to explore on their own — a
/// genuinely different ending from the guided one. `finish` completes the flow.
@ScreenSource(id: 'starter_done_explore')
class StarterDoneExploreScreen extends StatelessWidget {
  /// Completes onboarding.
  static const finish = OnboardingEvent<void>('finish');

  /// Const constructor.
  const StarterDoneExploreScreen({super.key});

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
                Icons.explore_rounded,
                size: 56,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 20),
              Text(
                'All set — dive in whenever you like.',
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
                child: const Text('Take me in'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
