import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/stride_reminders.restage.g.dart';

/// Stride onboarding: the reminder screen.
///
/// "Turn on reminders" fires [enable], which the flow binds to the
/// `requestNotifications` host action. Your app shows the OS dialog, and the flow
/// moves on only when permission is granted. "Maybe later" fires [skip], a custom
/// event your app receives as a `FlowCustomEvent` so it can carry on without the
/// permission.
///
/// General delivery can change the graph over the air, but only with actions and
/// events the installed app already has. A new action needs an app release.
@Screen()
class StrideRemindersScreen extends StatelessWidget {
  /// Requests the notification permission (bound to a host action by the flow).
  static const enable = SurfaceEvent<void>('enable');

  /// "Maybe later" — a host-handled custom event; the flow does not route it.
  static const skip = SurfaceEvent<void>('skip');

  const StrideRemindersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF241024),
      appBar: AppBar(
        backgroundColor: const Color(0xFF241024),
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        top: false,
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
                          colors: [Color(0xFFFF6F5B), Color(0xFFFF9E7D)],
                        ),
                      ),
                      child: const Icon(
                        Icons.notifications_active_rounded,
                        size: 44,
                        color: Color(0xFF241024),
                      ),
                    ),
                    const SizedBox(height: 32),
                    const Text(
                      'Never miss a run',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFFBEFE9),
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'A gentle nudge on your schedule keeps the streak alive.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: Color(0xFFC6A9BC),
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
                        backgroundColor: const Color(0xFFFF6F5B),
                        foregroundColor: const Color(0xFF241024),
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ),
                      onPressed: surfaceEvent(enable),
                      child: const Text(
                        'Turn on reminders',
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
                onPressed: surfaceEvent(skip),
                child: const Text(
                  'Maybe later',
                  style: TextStyle(
                    fontSize: 15,
                    color: Color(0xFFC6A9BC),
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
