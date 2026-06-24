import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'notify.rsscreen.g.dart';

/// First-run onboarding — the notification pre-permission priming screen.
///
/// This is the screen that earns the OS notification grant. It explains the
/// value first (a pre-permission "primer"), then offers two honest choices:
///
/// - **Enable reminders** fires [enable], which the flow routes through a host
///   action (`requestNotifications`). The host shows the real OS dialog and
///   reports back; on a grant the flow advances to the "you're set" screen. If
///   the OS dialog is declined the flow simply stays here — the choice below is
///   always available, so a decline is never a dead end.
/// - **Not now** fires [skip], a flow *custom event*. It is not a graph
///   transition; the host listens for it and moves on to the paywall. This is
///   how an onboarding surfaces an action the host — not the flow graph —
///   should handle.
///
/// Pairing a graph transition (enable) with a host-handled custom event (skip)
/// on one screen is the supported way to give a permission ask two forward
/// paths under the flow runtime.
@ScreenSource(id: 'notify')
class NotifyScreen extends StatelessWidget {
  /// Requests the notification permission via the host action, then advances.
  static const enable = OnboardingEvent<void>('enable');

  /// Skips the permission; the host advances to the paywall.
  static const skip = OnboardingEvent<void>('skip');

  const NotifyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E1B33),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
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
                        Icons.notifications_active_rounded,
                        size: 42,
                        color: Color(0xFF0E1B33),
                      ),
                    ),
                    const SizedBox(height: 32),
                    const Text(
                      'Stay on track',
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
                      'A gentle reminder for your daily session — just a nudge when it helps, never spam.',
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
                      onPressed: onboardingEvent(enable),
                      child: const Text(
                        'Enable reminders',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: onboardingEvent(skip),
                child: const Text(
                  'Not now',
                  style: TextStyle(
                    fontSize: 15,
                    color: Color(0xFFAEB9D4),
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
