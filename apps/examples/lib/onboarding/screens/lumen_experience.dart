import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'lumen_experience.rsscreen.g.dart';

/// Onboarding — the meditation-experience question.
///
/// A personalization question: the user taps the option that fits and the flow
/// advances. The flow is linear (the answer tailors the experience, it does not
/// fork the graph), so every option fires the same [next] event — each option
/// card is one of several triggers for the single forward transition.
@ScreenSource(id: 'lumen_experience')
class LumenExperienceScreen extends StatelessWidget {
  /// Advances to the goal question.
  static const next = OnboardingEvent<void>('next');

  const LumenExperienceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F5FB),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              const Text(
                'How much have you meditated?',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF2A2833),
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                "We'll tailor your first sessions to fit.",
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFF847F92),
                  height: 1.4,
                ),
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: onboardingEvent(next),
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(
                            color: const Color(0xFFE5E1F0),
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.spa_rounded,
                              color: Color(0xFF7C6CD6),
                              size: 26,
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Text(
                                "I'm new to meditation",
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF2A2833),
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: Color(0xFFA9A4BB),
                              size: 24,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    GestureDetector(
                      onTap: onboardingEvent(next),
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(
                            color: const Color(0xFFE5E1F0),
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.eco_rounded,
                              color: Color(0xFF7C6CD6),
                              size: 26,
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Text(
                                "I've practiced a little",
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF2A2833),
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: Color(0xFFA9A4BB),
                              size: 24,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    GestureDetector(
                      onTap: onboardingEvent(next),
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(
                            color: const Color(0xFFE5E1F0),
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.forest_rounded,
                              color: Color(0xFF7C6CD6),
                              size: 26,
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Text(
                                "I'm experienced",
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF2A2833),
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: Color(0xFFA9A4BB),
                              size: 24,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
