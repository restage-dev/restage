import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/widgets/pricing_card.dart';
import 'package:restage_example/widgets/pricing_table.dart';

/// A paywall that renders a **list of customer data classes** natively over the
/// air.
///
/// The [PricingTable] is a custom `@RestageWidget` whose `plans` property is a
/// `List<Plan>` — a list of customer data classes. Authored here in ordinary
/// Flutter, the build-time codegen compiles the whole list into the delivered
/// blob as a list of field-name-keyed maps; the SDK reconstructs it element by
/// element and the `PricingTable` factory renders each plan as real widgets on
/// the device. No hand-written wiring.
///
/// This is the developer-facing proof that a custom widget with a
/// list-of-data-class property works in a remote paywall.
@PaywallSource(id: 'pricing_table_showcase')
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
