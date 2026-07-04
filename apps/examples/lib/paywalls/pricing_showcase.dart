import 'package:flutter/material.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/widgets/pricing_card.dart';

/// A paywall that renders a **customer data class** natively over the air.
///
/// Each row is a [PricingCard] — a custom `@RestageWidget` — whose `plan`
/// property is a nested [Plan] data class (`name`, a nested [Price], an
/// optional `badge`, an enum `tier`). Authored here in ordinary Flutter, the
/// build-time codegen compiles each `Plan(...)` value into the delivered blob
/// as a field-name-keyed map; the SDK reconstructs it and the `PricingCard`
/// factory renders it as real widgets on the device. No hand-written wiring —
/// the same file drives the local preview and the server-delivered surface.
///
/// This is the developer-facing proof that a custom widget with a data-class
/// property works in a remote paywall.
@PaywallSource(id: 'pricing_showcase')
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
