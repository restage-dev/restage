import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'value.rsscreen.g.dart';

/// First-run onboarding — the value screen.
///
/// Sets up *why* a daily reminder helps before the flow asks for the
/// notification permission. Asking for a permission right after the user has
/// understood its value (rather than cold, up front) is the pattern that earns
/// the grant. See `welcome.dart` for the screen-authoring notes that apply to
/// every screen in this flow.
@ScreenSource(id: 'value')
class ValueScreen extends StatelessWidget {
  /// Advances to the notification-priming screen.
  static const next = OnboardingEvent<void>('next');

  const ValueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E1B33),
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
                      width: 96,
                      height: 96,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF6FD6C6), Color(0xFF8FA2F2)],
                        ),
                      ),
                      child: const Icon(
                        Icons.calendar_today_rounded,
                        size: 42,
                        color: Color(0xFF0E1B33),
                      ),
                    ),
                    const SizedBox(height: 32),
                    const Text(
                      'Build a daily practice',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFF5F7FB),
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Short sessions that fit your day. A nudge keeps it going.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: Color(0xFFAEB9D4),
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
                        backgroundColor: const Color(0xFF6FD6C6),
                        foregroundColor: const Color(0xFF0E1B33),
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ),
                      onPressed: onboardingEvent(next),
                      child: const Text(
                        'Continue',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
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
