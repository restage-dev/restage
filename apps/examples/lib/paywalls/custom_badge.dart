import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import '../widgets/streak_badge.dart';

/// A minimal paywall that references the customer's non-inlinable [StreakBadge].
///
/// It proves an app-backed `@RestageWidget` is *referenced* (not inlined) in
/// a Dart-authored surface and rendered from the delivered blob: the codegen
/// resolves `StreakBadge` against the package's generated catalog and emits a
/// reference, which the SDK resolves at runtime through the registered factory.
@PaywallSource(id: 'custom_badge')
class CustomBadgePaywall extends StatefulWidget {
  /// Const constructor.
  const CustomBadgePaywall({super.key});

  @override
  State<CustomBadgePaywall> createState() => _CustomBadgePaywallState();
}

class _CustomBadgePaywallState extends State<CustomBadgePaywall> {
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
                'Your streaks',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 24),
              const Center(child: StreakBadge(label: 'Streak', count: 9)),
              const SizedBox(height: 12),
              const Center(child: StreakBadge(label: 'Saved', count: 3)),
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
