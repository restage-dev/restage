import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import 'flows/tally_onboarding.dart';

/// Hosts the Tally goal-fork onboarding — the public answer-branching template.
///
/// The host side is minimal: this flow has no host actions and no embedded
/// paywall — the answer-driven branch lives entirely in the flow graph (the
/// goal fork + the routing decision). The host gives the flow somewhere to run,
/// shows a completion hand-off, and fails closed.
///
/// Like the other examples this ships its flow as a bundled asset (no backend).
/// A production app delivers onboarding over the air by injecting a
/// `ServerFlowResolver` once at startup — the fail-closed and completion wiring
/// are identical either way.
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
    return RestageFlowGraph<TallyOnboardingResult>(
      flow: tallyOnboardingFlowRef,
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
