import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/stride_reminders.restage.g.dart';

/// Stride onboarding — the reminder-priming screen.
///
/// This is the one screen that reaches outside the flow. It offers two ways
/// forward, and each is a distinct kind of installed capability:
///
/// * **"Turn on reminders"** fires the [enable] event, which the flow binds to
///   the `requestNotifications` *host action* — a capability the app owns. The
///   flow requests it by contract; the app shows the real OS dialog. The flow
///   advances only on a granted result (an advance-or-stay gate).
/// * **"Maybe later"** fires the [skip] *custom event*, which the flow declares
///   but does not route in its graph. It surfaces to the host as a
///   `FlowCustomEvent` so the app can carry the user forward without the grant.
///
/// Both the action name and the event name are part of the flow's **installed
/// vocabulary**: general-mode delivery can recompose the graph over the air,
/// but it can only ever reference verbs and events the app already ships. A new
/// capability is a new app release — never an over-the-air change.
///
/// See `stride_welcome.dart` for the screen-authoring notes that apply here.
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
