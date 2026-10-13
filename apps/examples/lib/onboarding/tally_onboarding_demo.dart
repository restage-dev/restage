import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import 'flows/tally_onboarding.dart';

/// Hosts the goal-based onboarding with its generated surface mount.
/// The flow selects a branch from the answer and reports completion.
class TallyOnboardingDemo extends StatefulWidget {
  /// Creates the onboarding host.
  const TallyOnboardingDemo({super.key});

  @override
  State<TallyOnboardingDemo> createState() => _TallyOnboardingDemoState();
}

class _TallyOnboardingDemoState extends State<TallyOnboardingDemo> {
  bool _completed = false;

  @override
  Widget build(BuildContext context) {
    if (_completed) {
      return const _CompletionScreen();
    }
    return TallyOnboardingFlowSurface(
      onComplete: (result) {
        if (mounted) setState(() => _completed = true);
      },
      loadingBuilder: (context) => const ColoredBox(color: Color(0xFFFBF7F0)),
      unavailable: FlowUnavailablePolicy.fallback(
        builder: (context, error) => Scaffold(
          backgroundColor: const Color(0xFFFBF7F0),
          body: Center(
            child: Text(
              error.message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF1F2421)),
            ),
          ),
        ),
      ),
    );
  }
}

class _CompletionScreen extends StatelessWidget {
  const _CompletionScreen();

  @override
  Widget build(BuildContext context) {
    // The terminal hand-off. In a real app this is the app itself; system
    // back returns to the gallery from here.
    return Scaffold(
      backgroundColor: const Color(0xFFFBF7F0),
      body: Stack(
        children: [
          SafeArea(
            child: Center(
              child: Text(
                'You\'re all set',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF1F2421),
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
