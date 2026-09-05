import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/lumen_reminder.restage.g.dart';

/// Onboarding — the daily-reminder priming screen (the host-action gate).
///
/// [enable] is routed through a host action (`enableReminders`): the host
/// requests the OS notification permission and reports back, and the flow
/// advances **only when the result is granted**. This is the one conditional
/// branch the flow runtime offers (advance-or-stay). It is one-directional by
/// design — there is no in-graph "skip" affordance, because a second forward
/// transition from one screen is not authorable; the host action simply
/// reports the user's decision.
@Screen()
class LumenReminderScreen extends StatelessWidget {
  /// Requests the reminder permission via the host action, then advances on a
  /// granted result.
  static const enable = SurfaceEvent<void>('enable');

  /// Steps back. The flow runtime pops its own history for this
  /// reserved name when the graph authors no transition for it.
  static const back = SurfaceEvent<void>('back');

  const LumenReminderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: dark
                      ? const [
                          Color(0xFF0F0B1F),
                          Color(0xFF14102A),
                          Color(0xFF0B0817),
                        ]
                      : const [
                          Color(0xFFFBFAFF),
                          Color(0xFFF4F1FC),
                          Color(0xFFEFEAF9),
                        ],
                  stops: const [0.0, 0.6, 1.0],
                ),
              ),
            ),
          ),
          Positioned(
            left: -90,
            top: -40,
            child: Container(
              width: 340,
              height: 340,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: dark
                      ? const [Color(0xB38B7CF6), Color(0x008B7CF6)]
                      : const [Color(0x668B7CF6), Color(0x008B7CF6)],
                  stops: const [0.0, 0.7],
                ),
              ),
            ),
          ),
          Positioned(
            right: -120,
            top: 120,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: dark
                      ? const [Color(0x805EDBD1), Color(0x005EDBD1)]
                      : const [Color(0x665EDBD1), Color(0x005EDBD1)],
                  stops: const [0.0, 0.7],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            bottom: 0,
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 72, 24, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          GestureDetector(
                            onTap: surfaceEvent(back),
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: dark
                                    ? const Color(0x1AFFFFFF)
                                    : const Color(0x1A7C6CD6),
                              ),
                              child: Center(
                                child: Icon(
                                  Icons.chevron_left_rounded,
                                  size: 22,
                                  color: dark
                                      ? const Color(0xFFB6AFD6)
                                      : const Color(0xFF6F6889),
                                ),
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: dark
                                      ? const Color(0x2EFFFFFF)
                                      : const Color(0x1A7C6CD6),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: dark
                                      ? const Color(0x2EFFFFFF)
                                      : const Color(0x1A7C6CD6),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                width: 22,
                                height: 6,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(999),
                                  color: dark
                                      ? const Color(0xFFC39BFF)
                                      : const Color(0xFF6A55C4),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: dark
                                      ? const Color(0x2EFFFFFF)
                                      : const Color(0x1A7C6CD6),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 104,
                              height: 104,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: dark
                                    ? const Color(0x388B7CF6)
                                    : const Color(0x1F7C6CD6),
                                border: Border.all(
                                  width: 1.5,
                                  color: dark
                                      ? const Color(0xFFA899FF)
                                      : const Color(0xFF7C6CD6),
                                ),
                              ),
                              child: Center(
                                child: Icon(
                                  Icons.notifications_active_rounded,
                                  size: 50,
                                  color: dark
                                      ? const Color(0xFFC39BFF)
                                      : const Color(0xFF6A55C4),
                                ),
                              ),
                            ),
                            const SizedBox(height: 36),
                            Text(
                              'Stay on track',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 36,
                                height: 1.06,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1.2,
                                color: dark
                                    ? const Color(0xFFF4F1FF)
                                    : const Color(0xFF221E33),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'A gentle daily nudge for your session — just when it '
                              'helps, never spam.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                height: 1.45,
                                color: dark
                                    ? const Color(0xFFB6AFD6)
                                    : const Color(0xFF6F6889),
                              ),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: surfaceEvent(enable),
                        child: Container(
                          height: 58,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: dark
                                  ? const [Color(0xFF8B7CF6), Color(0xFFC39BFF)]
                                  : const [
                                      Color(0xFF6A55C4),
                                      Color(0xFF8B7CF6)
                                    ],
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x4D7C6CD6),
                                blurRadius: 30,
                                offset: Offset(0, 12),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              'Enable daily reminders',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: dark
                                    ? const Color(0xFF14102A)
                                    : const Color(0xFFFFFFFF),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
