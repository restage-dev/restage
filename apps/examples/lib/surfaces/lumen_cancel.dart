import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/lumen_cancel.restage.g.dart';

/// Survey — the one question asked when a meditation subscription is cancelled.
///
/// Every row fires the same [reason] event with its own answer value, so the
/// flow captures the choice without forking the graph. [skip] completes the
/// survey with no answer.
@Screen(id: 'lumen_cancel_reason', surface: Surface.survey)
class LumenCancelReasonScreen extends StatelessWidget {
  /// Records the chosen reason and advances.
  static const reason = SurfaceEvent<String>('reason');

  /// Completes the survey without an answer.
  static const skip = SurfaceEvent<void>('skip');

  const LumenCancelReasonScreen({super.key});

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
                          Text(
                            'ONE QUESTION',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2,
                              color: dark
                                  ? const Color(0xFFC39BFF)
                                  : const Color(0xFF6A55C4),
                            ),
                          ),
                          GestureDetector(
                            onTap: surfaceEvent(skip),
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
                                  Icons.close_rounded,
                                  size: 14,
                                  color: dark
                                      ? const Color(0xFFB6AFD6)
                                      : const Color(0xFF6F6889),
                                ),
                              ),
                            ),
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
                                'Why are you\nleaving?',
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
                                'It shapes what we build next. No judgement.',
                                style: TextStyle(
                                  fontSize: 16,
                                  height: 1.45,
                                  color: dark
                                      ? const Color(0xFFB6AFD6)
                                      : const Color(0xFF6F6889),
                                ),
                              ),
                              const SizedBox(height: 28),
                              GestureDetector(
                                onTap: surfaceEvent(reason, 'too_expensive'),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 17,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(18),
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
                                        child: Text(
                                          'It costs too much',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: dark
                                                ? const Color(0xFFF4F1FF)
                                                : const Color(0xFF221E33),
                                          ),
                                        ),
                                      ),
                                      Icon(
                                        Icons.arrow_forward_rounded,
                                        size: 18,
                                        color: dark
                                            ? const Color(0xFFB6AFD6)
                                            : const Color(0xFF6F6889),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              GestureDetector(
                                onTap: surfaceEvent(reason, 'not_used_enough'),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 17,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(18),
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
                                        child: Text(
                                          'I did not use it enough',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: dark
                                                ? const Color(0xFFF4F1FF)
                                                : const Color(0xFF221E33),
                                          ),
                                        ),
                                      ),
                                      Icon(
                                        Icons.arrow_forward_rounded,
                                        size: 18,
                                        color: dark
                                            ? const Color(0xFFB6AFD6)
                                            : const Color(0xFF6F6889),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              GestureDetector(
                                onTap: surfaceEvent(reason, 'found_better'),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 17,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(18),
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
                                        child: Text(
                                          'I found something better',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: dark
                                                ? const Color(0xFFF4F1FF)
                                                : const Color(0xFF221E33),
                                          ),
                                        ),
                                      ),
                                      Icon(
                                        Icons.arrow_forward_rounded,
                                        size: 18,
                                        color: dark
                                            ? const Color(0xFFB6AFD6)
                                            : const Color(0xFF6F6889),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              GestureDetector(
                                onTap:
                                    surfaceEvent(reason, 'content_not_for_me'),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 17,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(18),
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
                                        child: Text(
                                          'The content was not for me',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: dark
                                                ? const Color(0xFFF4F1FF)
                                                : const Color(0xFF221E33),
                                          ),
                                        ),
                                      ),
                                      Icon(
                                        Icons.arrow_forward_rounded,
                                        size: 18,
                                        color: dark
                                            ? const Color(0xFFB6AFD6)
                                            : const Color(0xFF6F6889),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              GestureDetector(
                                onTap: surfaceEvent(reason, 'something_else'),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 17,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(18),
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
                                        child: Text(
                                          'Something else',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: dark
                                                ? const Color(0xFFF4F1FF)
                                                : const Color(0xFF221E33),
                                          ),
                                        ),
                                      ),
                                      Icon(
                                        Icons.arrow_forward_rounded,
                                        size: 18,
                                        color: dark
                                            ? const Color(0xFFB6AFD6)
                                            : const Color(0xFF6F6889),
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
                        onTap: surfaceEvent(skip),
                        child: const Center(
                          child: Text(
                            'Skip',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF8E86B3),
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

/// Survey — the acknowledgement that closes the cancellation question.
@Screen(id: 'lumen_cancel_thanks', surface: Surface.survey)
class LumenCancelThanksScreen extends StatelessWidget {
  /// Completes the survey.
  static const finish = SurfaceEvent<void>('finish');

  const LumenCancelThanksScreen({super.key});

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
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: 24),
                              Container(
                                padding:
                                    const EdgeInsets.fromLTRB(26, 34, 26, 30),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(30),
                                  color: dark
                                      ? const Color(0x14FFFFFF)
                                      : const Color(0x99FFFFFF),
                                  border: Border.all(
                                    color: dark
                                        ? const Color(0x24FFFFFF)
                                        : const Color(0x2E7C6CD6),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Center(
                                      child: Container(
                                        width: 96,
                                        height: 96,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: dark
                                              ? const Color(0x388B7CF6)
                                              : const Color(0x1F7C6CD6),
                                          border: Border.all(
                                            color: dark
                                                ? const Color(0xFFA899FF)
                                                : const Color(0xFF7C6CD6),
                                          ),
                                        ),
                                        child: Center(
                                          child: Icon(
                                            Icons.favorite_rounded,
                                            size: 42,
                                            color: dark
                                                ? const Color(0xFFC39BFF)
                                                : const Color(0xFF6A55C4),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 26),
                                    Text(
                                      'Thank you',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 30,
                                        height: 1.08,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -1,
                                        color: dark
                                            ? const Color(0xFFF4F1FF)
                                            : const Color(0xFF221E33),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      'Your sessions stay saved. Come back whenever the '
                                      'quiet is useful again.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 15,
                                        height: 1.45,
                                        color: dark
                                            ? const Color(0xFFB6AFD6)
                                            : const Color(0xFF6F6889),
                                      ),
                                    ),
                                    const SizedBox(height: 26),
                                    GestureDetector(
                                      onTap: surfaceEvent(finish),
                                      child: Container(
                                        height: 58,
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(999),
                                          gradient: LinearGradient(
                                            begin: Alignment.centerLeft,
                                            end: Alignment.centerRight,
                                            colors: dark
                                                ? const [
                                                    Color(0xFF8B7CF6),
                                                    Color(0xFFC39BFF),
                                                  ]
                                                : const [
                                                    Color(0xFF6A55C4),
                                                    Color(0xFF8B7CF6),
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
                                            'Done',
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
                              const SizedBox(height: 24),
                            ],
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
