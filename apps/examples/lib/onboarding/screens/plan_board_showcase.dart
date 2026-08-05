import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import '../../widgets/pricing_card.dart' show Plan, PlanTier, Price;
import '../../widgets/plan_board.dart';

part 'plan_board_showcase.rsscreen.g.dart';

/// A general screen that showcases map-backed plan properties.
///
/// The surface is authored as ordinary Flutter and compiled to a committed
/// screen artifact. Both map-shaped properties are reconstructed by the
/// generated widget factory when that artifact renders.
///
/// The string keys are authored out of alphabetical order, and the enum keys
/// out of declaration order, deliberately: each map travels as an ordered entry
/// list, so authoring in a canonical order would let an ordering regression
/// pass by coincidence.
@ScreenSource(id: 'plan_board_showcase')
class PlanBoardShowcaseScreen extends StatelessWidget {
  /// Continues from the showcased plans.
  static const act = OnboardingEvent<void>('act');

  /// Dismisses the surface (host-handled custom event).
  static const dismiss = OnboardingEvent<void>('dismiss');

  /// Const constructor.
  const PlanBoardShowcaseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: onboardingEvent(dismiss),
                    icon: Icon(
                      Icons.close_rounded,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                'Pick the plan that fits',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              const PlanBoard(
                plans: {
                  'team': Plan(
                    name: 'Team',
                    price: Price(4900),
                    badge: 'Most seats',
                    tier: PlanTier.team,
                  ),
                  'pro': Plan(
                    name: 'Pro',
                    price: Price(1900),
                    tier: PlanTier.pro,
                  ),
                  'starter': Plan(
                    name: 'Starter',
                    price: Price(0, currency: 'EUR'),
                  ),
                },
                highlights: {
                  PlanTier.team: Plan(
                    name: 'Team',
                    price: Price(4900),
                    tier: PlanTier.team,
                  ),
                  PlanTier.starter: Plan(
                    name: 'Starter',
                    price: Price(0, currency: 'EUR'),
                  ),
                },
              ),
              const SizedBox(height: 16),
              Text(
                'Review the plans above, then continue when you are ready.',
                style: TextStyle(
                  fontSize: 16,
                  height: 1.45,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: onboardingEvent(act),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
