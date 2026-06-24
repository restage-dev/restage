import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'lumen_reminder.rsscreen.g.dart';

/// Onboarding — the daily-reminder priming screen (the host-action gate).
///
/// [enable] is routed through a host action (`enableReminders`): the host
/// requests the OS notification permission and reports back, and the flow
/// advances **only when the result is granted**. This is the one conditional
/// branch the flow runtime offers (advance-or-stay). It is one-directional by
/// design — there is no in-graph "skip" affordance, because a second forward
/// transition from one screen is not authorable; the host action simply
/// reports the user's decision.
@ScreenSource(id: 'lumen_reminder')
class LumenReminderScreen extends StatelessWidget {
  /// Requests the reminder permission via the host action, then advances on a
  /// granted result.
  static const enable = OnboardingEvent<void>('enable');

  const LumenReminderScreen({super.key});

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
                      width: 104,
                      height: 104,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF8B7BE0), Color(0xFFB6A8F0)],
                        ),
                      ),
                      child: const Icon(
                        Icons.notifications_active_rounded,
                        size: 50,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 32),
                    const Text(
                      'Stay on track',
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
                      'A gentle daily nudge for your session — just when it '
                      'helps, never spam.',
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
                      onPressed: onboardingEvent(enable),
                      child: const Text(
                        'Enable daily reminders',
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
