import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'lumen_welcome.rsscreen.g.dart';

/// Onboarding — the calm welcome screen for the meditation flow.
///
/// Fixed calm palette (the flow renders on its own surface, not the host
/// theme). The full-width CTA uses an `Expanded` child in a `Row` so it
/// survives lowering.
@ScreenSource(id: 'lumen_welcome')
class LumenWelcomeScreen extends StatelessWidget {
  /// Advances to the experience question.
  static const next = OnboardingEvent<void>('next');

  const LumenWelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F5FB),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
          child: Column(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 108,
                      height: 108,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF8B7BE0), Color(0xFFB6A8F0)],
                        ),
                      ),
                      child: const Icon(
                        Icons.self_improvement_rounded,
                        size: 56,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 32),
                    const Text(
                      'Welcome to Lumen',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF2A2833),
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'A few quiet minutes a day — meditation, sleep, and '
                      'focus, made simple.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: Color(0xFF847F92),
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF7C6CD6),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      onPressed: onboardingEvent(next),
                      child: const Text(
                        'Get started',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
