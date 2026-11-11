import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import '../widgets/pulse_badge.dart';

part 'restage.generated/pulse_paywall.restage.g.dart';

/// A minimal paywall that uses the app's [PulseBadge], which runs an animation
/// controller.
///
/// The delivered surface refers to `PulseBadge` by name, and the SDK renders it
/// through its registered factory.
@Paywall()
class PulsePaywall extends StatefulWidget {
  /// Const constructor.
  const PulsePaywall({super.key, this.onContinue});

  /// Continues to the purchase.
  final VoidCallback? onContinue;

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
                onTap: widget.onContinue,
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
