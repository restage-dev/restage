import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'tally_welcome.rsscreen.g.dart';

/// Onboarding — the welcome / value-prop screen.
///
/// The single CTA starts the personalization flow (the next screen is the goal
/// fork — the answer that branches the path).
@ScreenSource(id: 'tally_welcome')
class TallyWelcomeScreen extends StatelessWidget {
  /// Starts the goal-personalization flow.
  static const start = OnboardingEvent<void>('start');

  const TallyWelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBF7F0),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFF10A37F),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.pie_chart_rounded,
                  color: Color(0xFFFFFFFF),
                  size: 30,
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Your money,\nwith a plan',
                style: TextStyle(
                  fontSize: 34,
                  height: 1.1,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1F2421),
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Tell us what you\'re working toward and we\'ll shape your '
                'setup around it — debt, savings, or your first investments.',
                style: TextStyle(
                  fontSize: 16,
                  height: 1.45,
                  color: Color(0xFF7C8079),
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFFFF),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFEBE4D8)),
                    ),
                    child: const Icon(
                      Icons.lock_outline_rounded,
                      color: Color(0xFF10A37F),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Text(
                    'Bank-grade encryption',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1F2421),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFFFF),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFEBE4D8)),
                    ),
                    child: const Icon(
                      Icons.bolt_rounded,
                      color: Color(0xFF10A37F),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Text(
                    'Set up in under a minute',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1F2421),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF10A37F),
                  foregroundColor: const Color(0xFFFFFFFF),
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: onboardingEvent(start),
                child: const Text(
                  'Get started',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
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
