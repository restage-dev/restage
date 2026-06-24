import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'ready.rsscreen.g.dart';

/// First-run onboarding — the "you're set" screen.
///
/// Reached only when the notification permission was granted (the host action
/// reported back `granted`). It's the last beat of the flow before the handoff
/// to the paywall: tapping [start] completes the flow, and the host's
/// `onComplete` callback navigates to the paywall (the flow never launches a
/// paywall itself — the host owns navigation).
@ScreenSource(id: 'ready')
class ReadyScreen extends StatelessWidget {
  /// Completes the flow; the host then opens the paywall.
  static const start = OnboardingEvent<void>('start');

  const ReadyScreen({super.key});

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
                        Icons.check_rounded,
                        size: 48,
                        color: Color(0xFF0E1B33),
                      ),
                    ),
                    const SizedBox(height: 32),
                    const Text(
                      "You're all set",
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
                      'Reminders are on. Explore everything Aura has to offer.',
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
                      onPressed: onboardingEvent(start),
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
