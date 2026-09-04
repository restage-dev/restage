import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import 'flows/minimal_onboarding.dart';

/// Gallery host for the onboarding starter.
///
/// The host side of a flow is small: hand `RestageFlowGraph` the flow, say what
/// to do when it can't load (`unavailable`), and act on completion. It draws no
/// navigation control — the screens carry an app bar, and the SDK holds the
/// flow's history on this route so the bar implies back. No billing — the flow
/// ends on a plain screen. A real app delivers the same flow over the air by
/// installing a server resolver once at startup; this wiring is identical.
class MinimalOnboardingDemo extends StatelessWidget {
  /// Creates the onboarding gallery host.
  const MinimalOnboardingDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return RestageFlowGraph<MinimalOnboardingResult>(
      flow: minimalOnboardingFlowRef,
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
