import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import '../widgets/pulse_badge.dart';

/// A minimal paywall referencing the customer's [PulseBadge] — a *categorical*
/// (AnimationController-driven) non-inlinable 4b widget.
///
/// It proves the package-emitted widget catalog lets an irreducibly imperative
/// custom widget be *referenced* (never inlined) in a Dart-authored surface and
/// resolved from the delivered blob through the registered runtime factory —
/// the case no future transpiler increment could turn into an inline.
@PaywallSource(id: 'pulse_paywall')
class PulsePaywall extends StatefulWidget {
  /// Const constructor.
  const PulsePaywall({super.key});

  @override
  State<PulsePaywall> createState() => _PulsePaywallState();
}

class _PulsePaywallState extends State<PulsePaywall> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Text(
                'Keep your streak alive',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 24),
              const Center(child: PulseBadge(label: 'Streak', count: 12)),
              const Spacer(),
              GestureDetector(
                onTap: paywallPurchase(slot: 'annual'),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    'Continue',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
