import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import 'flows/minimal_onboarding.dart';

/// Gallery host for the onboarding starter.
///
/// The host side of a flow is small: hand `RestageOnboarding` the flow, say what
/// to do when it can't load (`unavailable`), act on completion, and supply the
/// chrome (the back / close affordances). No billing — the flow ends on a plain
/// screen. A real app delivers the same flow over the air by installing a server
/// resolver once at startup; this wiring is identical.
class MinimalOnboardingDemo extends StatelessWidget {
  /// Creates the onboarding gallery host.
  const MinimalOnboardingDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return RestageOnboarding<MinimalOnboardingResult>(
      flow: MinimalOnboardingFlowDescriptor.ref,
      // Fail closed: if the flow can't be resolved, show a plain message rather
      // than a broken or partial surface.
      unavailable: FlowUnavailablePolicy.fallback(
        builder: (context, error) => const Scaffold(
          body: Center(child: Text('Onboarding is unavailable right now.')),
        ),
      ),
      // The user reached the end (tapped finish on an ending screen) — return to
      // the gallery. A real app would route into itself here instead.
      onComplete: (result) => Navigator.of(context).maybePop(),
      onFlowUnavailable: (error) => Navigator.of(context).maybePop(),
      chromeBuilder: _chrome,
    );
  }

  // One coherent set of affordances on every screen, so back is never doubled:
  // a persistent close (top-right) that exits to the gallery, and the in-flow
  // back (top-left) shown only when there's a previous screen to step back to.
  Widget _chrome(BuildContext context, FlowChromeState state, Widget screen) {
    return Stack(
      children: [
        Positioned.fill(child: screen),
        Positioned(
          top: 0,
          right: 0,
          child: SafeArea(
            child: IconButton(
              icon: const Icon(Icons.close_rounded),
              tooltip: 'Close',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ),
        if (state.canBack)
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Back',
                onPressed: state.onBack,
              ),
            ),
          ),
      ],
    );
  }
}
