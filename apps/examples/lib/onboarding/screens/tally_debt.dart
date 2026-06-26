import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'tally_debt.rsscreen.g.dart';

/// Onboarding — the debt-payoff setup (the "Pay off debt" fork destination).
///
/// A genuinely goal-specific screen: a payoff-date hero + the avalanche-strategy
/// explainer + an interest-saved stat. Reached only when the user picked the
/// debt goal; [next] continues to the routing decision.
@ScreenSource(id: 'tally_debt')
class TallyDebtScreen extends StatelessWidget {
  /// Continues to the plan recap.
  static const next = OnboardingEvent<void>('next');

  const TallyDebtScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBF7F0),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              const Text(
                'Your payoff plan',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1F2421),
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Tuned to clear your balances with the least interest.',
                style: TextStyle(fontSize: 15, color: Color(0xFF7C8079)),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: const Color(0x1A10A37F),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0x3310A37F)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DEBT-FREE BY',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: Color(0xFF10A37F),
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'December 2027',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1F2421),
                        letterSpacing: -0.5,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      '18 months sooner than minimum payments',
                      style: TextStyle(fontSize: 14, color: Color(0xFF7C8079)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFFFF),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFEBE4D8)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0x1A10A37F),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.layers_rounded,
                        color: Color(0xFF10A37F),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Avalanche method',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1F2421),
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Highest-interest balance first, so you pay '
                            'the least.',
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1.35,
                              color: Color(0xFF7C8079),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  const Text(
                    'Est. interest saved  ',
                    style: TextStyle(fontSize: 14, color: Color(0xFF7C8079)),
                  ),
                  const Text(
                    '\$1,240',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF10A37F),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF10A37F),
                  foregroundColor: const Color(0xFFFFFFFF),
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: onboardingEvent(next),
                child: const Text(
                  'Continue',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
