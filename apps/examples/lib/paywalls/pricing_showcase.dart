import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/widgets/pricing_card.dart';

/// A paywall whose rows are [PricingCard] widgets, each taking a [Plan] data
/// class.
///
/// The build writes each `Plan(...)` into the delivered surface, and the generated
/// factory rebuilds it on the device. No hand-written decoding is needed.
@Paywall()
class PricingShowcase extends StatelessWidget {
  /// Const constructor.
  const PricingShowcase({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: paywallEvent('close'),
                    child: Icon(
                      Icons.close_rounded,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Choose your plan',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 24),
              const PricingCard(
                plan: Plan(
                  name: 'Pro',
                  price: Price(1999, currency: 'USD'),
                  badge: 'Most popular',
                  tier: PlanTier.pro,
                ),
              ),
              const SizedBox(height: 12),
              const PricingCard(
                plan: Plan(
                  name: 'Starter',
                  price: Price(999),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: paywallEvent('continue'),
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
