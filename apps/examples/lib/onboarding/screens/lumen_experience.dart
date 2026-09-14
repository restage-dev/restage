import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/lumen_experience.restage.g.dart';

/// Onboarding — the meditation-experience question.
///
/// A personalization question: the user taps the option that fits and the flow
/// advances. The flow is linear (the answer tailors the experience, it does not
/// fork the graph), so every option fires the same [next] event — each option
/// card is one of several triggers for the single forward transition.
@Screen()
class LumenExperienceScreen extends StatelessWidget {
  /// Advances to the goal question.
  static const next = SurfaceEvent<void>('next');

  /// Steps back. The flow runtime pops its own history for this
  /// reserved name when the graph authors no transition for it.
  static const back = SurfaceEvent<void>('back');

  const LumenExperienceScreen({super.key});

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
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: 36),
                              Text(
                                'How much have\nyou meditated?',
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
                                "We'll tailor your first sessions to fit.",
                                style: TextStyle(
                                  fontSize: 16,
                                  height: 1.45,
                                  color: dark
                                      ? const Color(0xFFB6AFD6)
                                      : const Color(0xFF6F6889),
                                ),
                              ),
                              const SizedBox(height: 28),
                              // The first choice carries the selected treatment, so the
                              // pattern is visible at rest.
                              GestureDetector(
                                onTap: surfaceEvent(next),
                                child: Container(
                                  padding: const EdgeInsets.all(18),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
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
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              "I'm new to meditation",
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w700,
                                                color: dark
                                                    ? const Color(0xFFF4F1FF)
                                                    : const Color(0xFF221E33),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Start with the basics',
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: dark
                                                    ? const Color(0xFFB6AFD6)
                                                    : const Color(0xFF6F6889),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        width: 22,
                                        height: 22,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            width: 2,
                                            color: dark
                                                ? const Color(0xFFC39BFF)
                                                : const Color(0xFF6A55C4),
                                          ),
                                        ),
                                        child: Center(
                                          child: Container(
                                            width: 10,
                                            height: 10,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: dark
                                                  ? const Color(0xFFC39BFF)
                                                  : const Color(0xFF6A55C4),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              GestureDetector(
                                onTap: surfaceEvent(next),
                                child: Container(
                                  padding: const EdgeInsets.all(18),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                    color: dark
                                        ? const Color(0x14FFFFFF)
                                        : const Color(0x99FFFFFF),
                                    border: Border.all(
                                      width: 1.5,
                                      color: dark
                                          ? const Color(0x24FFFFFF)
                                          : const Color(0x2E7C6CD6),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              "I've practiced a little",
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w700,
                                                color: dark
                                                    ? const Color(0xFFF4F1FF)
                                                    : const Color(0xFF221E33),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Pick up where you left off',
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: dark
                                                    ? const Color(0xFFB6AFD6)
                                                    : const Color(0xFF6F6889),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        width: 22,
                                        height: 22,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            width: 2,
                                            color: dark
                                                ? const Color(0x2EFFFFFF)
                                                : const Color(0x2E7C6CD6),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              GestureDetector(
                                onTap: surfaceEvent(next),
                                child: Container(
                                  padding: const EdgeInsets.all(18),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                    color: dark
                                        ? const Color(0x14FFFFFF)
                                        : const Color(0x99FFFFFF),
                                    border: Border.all(
                                      width: 1.5,
                                      color: dark
                                          ? const Color(0x24FFFFFF)
                                          : const Color(0x2E7C6CD6),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              "I'm experienced",
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w700,
                                                color: dark
                                                    ? const Color(0xFFF4F1FF)
                                                    : const Color(0xFF221E33),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Go straight to longer sits',
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: dark
                                                    ? const Color(0xFFB6AFD6)
                                                    : const Color(0xFF6F6889),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        width: 22,
                                        height: 22,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            width: 2,
                                            color: dark
                                                ? const Color(0x2EFFFFFF)
                                                : const Color(0x2E7C6CD6),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      GestureDetector(
                        onTap: surfaceEvent(next),
                        child: Container(
                          height: 58,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
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
                              'Continue',
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
