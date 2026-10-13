import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import '../paywalls/lumen_welcome_offer.dart';
import 'flows/lumen_onboarding.dart';

/// Hosts meditation onboarding with a simulated reminder action.
/// Supplies the embedded offer's constructor for the compiled fallback.
class LumenOnboardingDemo extends StatefulWidget {
  /// Creates the onboarding host.
  ///
  /// [grantReminders] is the decision the demo's reminder host action returns.
  /// `true` walks the granted path (the flow advances to the recap and the
  /// paywall); `false` walks the declined path (the gate holds on the priming
  /// screen — the flow never proceeds on behaviour it did not get).
  ///
  const LumenOnboardingDemo({super.key, this.grantReminders = true});

  /// The fixed reminder decision this demo returns from the host action.
  final bool grantReminders;

  @override
  State<LumenOnboardingDemo> createState() => _LumenOnboardingDemoState();
}

class _LumenOnboardingDemoState extends State<LumenOnboardingDemo> {
  late final LumenOnboardingActions _actions;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _actions = LumenOnboardingActions(
      enableReminders: (args, context) async {
        // A real app requests the OS notification permission here and returns
        // the user's answer. The demo returns a fixed decision so both branches
        // are exercisable.
        return ReminderDecision(granted: widget.grantReminders);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_completed) {
      return const _CompletionScreen();
    }
    return LumenOnboardingFlowSurface(
      paywallLumenWelcomeOfferScreenBuilder: LumenWelcomeOfferPaywall.new,
      actions: _actions,
      onComplete: (result) {
        if (mounted) setState(() => _completed = result.completed);
      },
      loadingBuilder: (context) => const ColoredBox(color: Color(0xFFF7F5FB)),
      unavailable: FlowUnavailablePolicy.fallback(
        builder: (context, error) => ColoredBox(
          color: const Color(0xFFF7F5FB),
          child: Center(
            child: Text(
              error.message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF2A2833)),
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
    // The terminal hand-off. System back returns to the gallery from here.
    return const Scaffold(
      backgroundColor: Color(0xFFF7F5FB),
      body: Stack(
        children: [
          SafeArea(
            child: Center(
              child: Text(
                'Onboarding complete',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF2A2833),
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
