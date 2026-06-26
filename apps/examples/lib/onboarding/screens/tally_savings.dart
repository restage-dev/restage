import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'tally_savings.rsscreen.g.dart';

/// Onboarding — the savings setup (the "Build savings" fork destination).
///
/// A genuinely goal-specific screen: a savings-target hero + an auto-save card +
/// an on-track stat. Reached only when the user picked the savings goal; [next]
/// continues to the routing decision.
@ScreenSource(id: 'tally_savings')
class TallySavingsScreen extends StatelessWidget {
  /// Continues to the plan recap.
  static const next = OnboardingEvent<void>('next');

  const TallySavingsScreen({super.key});

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
                'Your savings plan',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1F2421),
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'A target and a pace to reach it without thinking about it.',
                style: TextStyle(fontSize: 15, color: Color(0xFF7C8079)),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: const Color(0x1A2563EB),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0x332563EB)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'EMERGENCY FUND TARGET',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: Color(0xFF2563EB),
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '\$5,000',
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1F2421),
                        letterSpacing: -0.5,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'About 3 months of your essentials',
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
                        color: const Color(0x1A2563EB),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.autorenew_rounded,
                        color: Color(0xFF2563EB),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Auto-save \$210 / month',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1F2421),
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Moved the day after payday. Pause anytime.',
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
                    'On track for  ',
                    style: TextStyle(fontSize: 14, color: Color(0xFF7C8079)),
                  ),
                  const Text(
                    'April 2026',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF2563EB),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
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
