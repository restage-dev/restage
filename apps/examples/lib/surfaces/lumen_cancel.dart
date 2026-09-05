import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/lumen_cancel.restage.g.dart';

/// Survey — the one question asked when a meditation subscription is cancelled.
///
/// Every card fires the same [reason] event carrying its own answer value, so
/// the flow captures which one was chosen without forking the graph. The cards
/// are written out in full because the transpiler lowers literal widget trees,
/// not method calls in widget position.
@Screen(id: 'lumen_cancel_reason', surface: Surface.survey)
class LumenCancelReasonScreen extends StatelessWidget {
  /// Records the chosen reason and advances.
  static const reason = SurfaceEvent<String>('reason');

  const LumenCancelReasonScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F5FB),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppBar(
            backgroundColor: const Color(0xFFF7F5FB),
            elevation: 0,
            foregroundColor: const Color(0xFF2A2833),
          ),
          Expanded(
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    const Text(
                      'Why are you leaving?',
                      style: TextStyle(
                        color: Color(0xFF2A2833),
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'One quiet question — it shapes what we build next.',
                      style: TextStyle(
                        color: Color(0xFF847F92),
                        fontSize: 16,
                        height: 1.4,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          GestureDetector(
                            onTap: surfaceEvent(reason, 'no_time'),
                            child: Container(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 16, 16, 16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFFFFF),
                                border: Border.all(
                                  color: const Color(0xFFE5E1F0),
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Row(
                                children: [
                                  Icon(
                                    Icons.schedule_rounded,
                                    color: Color(0xFF7C6CD6),
                                    size: 24,
                                  ),
                                  SizedBox(width: 14),
                                  Expanded(
                                    child: Text(
                                      'I ran out of time to practice',
                                      style: TextStyle(
                                        color: Color(0xFF2A2833),
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          GestureDetector(
                            onTap: surfaceEvent(reason, 'too_expensive'),
                            child: Container(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 16, 16, 16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFFFFF),
                                border: Border.all(
                                  color: const Color(0xFFE5E1F0),
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Row(
                                children: [
                                  Icon(
                                    Icons.savings_rounded,
                                    color: Color(0xFF7C6CD6),
                                    size: 24,
                                  ),
                                  SizedBox(width: 14),
                                  Expanded(
                                    child: Text(
                                      'It costs more than I use',
                                      style: TextStyle(
                                        color: Color(0xFF2A2833),
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          GestureDetector(
                            onTap: surfaceEvent(reason, 'content'),
                            child: Container(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 16, 16, 16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFFFFF),
                                border: Border.all(
                                  color: const Color(0xFFE5E1F0),
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Row(
                                children: [
                                  Icon(
                                    Icons.library_music_rounded,
                                    color: Color(0xFF7C6CD6),
                                    size: 24,
                                  ),
                                  SizedBox(width: 14),
                                  Expanded(
                                    child: Text(
                                      'I wanted different sessions',
                                      style: TextStyle(
                                        color: Color(0xFF2A2833),
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          GestureDetector(
                            onTap: surfaceEvent(reason, 'break'),
                            child: Container(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 16, 16, 16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFFFFF),
                                border: Border.all(
                                  color: const Color(0xFFE5E1F0),
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Row(
                                children: [
                                  Icon(
                                    Icons.spa_rounded,
                                    color: Color(0xFF7C6CD6),
                                    size: 24,
                                  ),
                                  SizedBox(width: 14),
                                  Expanded(
                                    child: Text(
                                      'Just taking a break',
                                      style: TextStyle(
                                        color: Color(0xFF2A2833),
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
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
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Survey — the acknowledgement that closes the cancellation question.
@Screen(id: 'lumen_cancel_thanks', surface: Surface.survey)
class LumenCancelThanksScreen extends StatelessWidget {
  /// Completes the survey.
  static const finish = SurfaceEvent<void>('finish');

  const LumenCancelThanksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F5FB),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppBar(
            backgroundColor: const Color(0xFFF7F5FB),
            elevation: 0,
            foregroundColor: const Color(0xFF2A2833),
          ),
          Expanded(
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 8, 28, 28),
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
                              Icons.favorite_rounded,
                              size: 48,
                              color: Color(0xFFFFFFFF),
                            ),
                          ),
                          const SizedBox(height: 32),
                          const Text(
                            'Thank you',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF2A2833),
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'Your sessions stay saved. Come back whenever the '
                            'quiet is useful again.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF847F92),
                              fontSize: 16,
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
                              foregroundColor: const Color(0xFFFFFFFF),
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                            ),
                            onPressed: surfaceEvent(finish),
                            child: const Text(
                              'Done',
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
          ),
        ],
      ),
    );
  }
}
