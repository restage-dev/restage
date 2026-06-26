import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'tally_goal.rsscreen.g.dart';

/// Onboarding — the goal fork (the headline answer-driven branch).
///
/// Each option fires a DISTINCT event, so the flow forks: the chosen goal is
/// written into flow-state and the user is routed to a goal-specific plan
/// screen (a genuinely different next screen per answer — not a tailored
/// variant of one screen).
@ScreenSource(id: 'tally_goal')
class TallyGoalScreen extends StatelessWidget {
  /// The user wants to pay off debt.
  static const debt = OnboardingEvent<void>('debt');

  /// The user wants to build savings.
  static const savings = OnboardingEvent<void>('savings');

  /// The user wants to start investing.
  static const invest = OnboardingEvent<void>('invest');

  const TallyGoalScreen({super.key});

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
                'What are you\nworking toward?',
                style: TextStyle(
                  fontSize: 30,
                  height: 1.12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1F2421),
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'We\'ll shape your setup around this. Change it anytime.',
                style: TextStyle(
                  fontSize: 16,
                  height: 1.4,
                  color: Color(0xFF7C8079),
                ),
              ),
              const SizedBox(height: 28),
              GestureDetector(
                onTap: onboardingEvent(debt),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFFFF),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFEBE4D8)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: const Color(0x1A10A37F),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.trending_down_rounded,
                          color: Color(0xFF10A37F),
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Pay off debt',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1F2421),
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Get to zero faster, save on interest',
                              style: TextStyle(
                                fontSize: 13.5,
                                color: Color(0xFF7C8079),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: Color(0xFFB8B0A2),
                        size: 24,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: onboardingEvent(savings),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFFFF),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFEBE4D8)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: const Color(0x1A2563EB),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.account_balance_wallet_rounded,
                          color: Color(0xFF2563EB),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Build savings',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1F2421),
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Set a target and grow it on autopilot',
                              style: TextStyle(
                                fontSize: 13.5,
                                color: Color(0xFF7C8079),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: Color(0xFFB8B0A2),
                        size: 24,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: onboardingEvent(invest),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFFFF),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFEBE4D8)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: const Color(0x1A7C3AED),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.show_chart_rounded,
                          color: Color(0xFF7C3AED),
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Start investing',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1F2421),
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Put your money to work for the long run',
                              style: TextStyle(
                                fontSize: 13.5,
                                color: Color(0xFF7C8079),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: Color(0xFFB8B0A2),
                        size: 24,
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
