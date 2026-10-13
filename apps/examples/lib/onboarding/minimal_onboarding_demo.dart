import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import 'flows/minimal_onboarding.dart';

/// Hosts the onboarding starter with its generated surface mount.
/// Completion returns to the gallery; the flow owns navigation between screens.
class MinimalOnboardingDemo extends StatelessWidget {
  /// Creates the onboarding gallery host.
  const MinimalOnboardingDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return MinimalOnboardingFlowSurface(
      // Fail closed: if the flow can't be resolved, show a plain message
      // rather than a broken or partial surface.
      unavailable: FlowUnavailablePolicy.fallback(
        builder: (context, error) => const Scaffold(
          body: Center(child: Text('Onboarding is unavailable right now.')),
        ),
      ),
      // The user reached the end (tapped finish on an ending screen) —
      // return to the gallery. A real app would route into itself here.
      onComplete: (result) => Navigator.of(context).maybePop(),
      onFlowUnavailable: (error) => Navigator.of(context).maybePop(),
    );
  }
}
