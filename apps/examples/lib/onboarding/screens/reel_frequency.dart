import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'reel_frequency.rsscreen.g.dart';

/// Survey — the second cancellation question ("How often did you watch?").
///
/// A linear multiple-choice question, like the first: every option fires the
/// same [next] event and advances to the save-offer. Written out in full
/// because the transpiler lowers literal widget trees, not method calls.
@ScreenSource(id: 'reel_frequency')
class ReelFrequencyScreen extends StatelessWidget {
  /// Advances to the save-offer.
  static const next = OnboardingEvent<void>('next');

  const ReelFrequencyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF141414),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'REEL',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF8B5CF6),
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'How often did you watch?',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'One last question before you go.',
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFF9A9A9A),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 26),
              GestureDetector(
                onTap: onboardingEvent(next),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F1F1F),
                    border: Border.all(color: const Color(0xFF333333)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Almost every day',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFE5E5E5),
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: Color(0xFF8C8C8C),
                        size: 24,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: onboardingEvent(next),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F1F1F),
                    border: Border.all(color: const Color(0xFF333333)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Expanded(
                        child: Text(
                          'A few times a week',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFE5E5E5),
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: Color(0xFF8C8C8C),
                        size: 24,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: onboardingEvent(next),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F1F1F),
                    border: Border.all(color: const Color(0xFF333333)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Hardly ever',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFE5E5E5),
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: Color(0xFF8C8C8C),
                        size: 24,
                      ),
                    ],
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
