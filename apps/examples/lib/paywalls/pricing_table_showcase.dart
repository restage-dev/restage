import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/widgets/pricing_card.dart';
import 'package:restage_example/widgets/pricing_table.dart';

/// A paywall with a [PricingTable] that takes a `List<Plan>`.
///
/// The build writes the list into the delivered surface, and the generated factory
/// rebuilds each plan on the device, in order.
@Paywall()
class PricingTableShowcase extends StatelessWidget {
  /// Const constructor.
  const PricingTableShowcase({super.key});

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
                'Compare plans',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 24),
              const PricingTable(
                plans: [
                  Plan(
                    name: 'Pro',
                    price: Price(1999, currency: 'USD'),
                    badge: 'Most popular',
                    tier: PlanTier.pro,
                  ),
                  Plan(
                    name: 'Starter',
                    price: Price(999),
                  ),
                ],
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
