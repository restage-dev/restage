import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'tally_recap_invest.rsscreen.g.dart';

/// Onboarding — the investing recap (the decision's default branch).
///
/// The routing decision sends the user here when the captured goal is `invest`
/// (the default branch). A goal-specific ending: the funding step + an
/// investing-specific CTA.
@ScreenSource(id: 'tally_recap_invest')
class TallyRecapInvestScreen extends StatelessWidget {
  /// Completes onboarding.
  static const finish = OnboardingEvent<void>('finish');

  const TallyRecapInvestScreen({super.key});

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
              const SizedBox(height: 12),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0x1A7C3AED),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.trending_up_rounded,
                  color: Color(0xFF7C3AED),
                  size: 34,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Your portfolio\nis ready',
                style: TextStyle(
                  fontSize: 30,
                  height: 1.12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1F2421),
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Add your first funds and we\'ll put the mix to work.',
                style: TextStyle(
                  fontSize: 16,
                  height: 1.4,
                  color: Color(0xFF7C8079),
                ),
              ),
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFFFF),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFEBE4D8)),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TO GET STARTED',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.1,
                              color: Color(0xFFB8B0A2),
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Fund 70/30 portfolio',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1F2421),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Text(
                      '\$500 min',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF7C3AED),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: const Color(0xFFFFFFFF),
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: onboardingEvent(finish),
                child: const Text(
                  'Fund my account',
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
