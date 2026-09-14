// GENERATED CODE - DO NOT MODIFY BY HAND
// Source: lib/onboarding/screens/lumen_welcome.dart

import 'package:flutter/material.dart';

/// Onboarding — the first screen of the meditation flow.
///
/// The aurora ground, three concentric rings around a lit core, and the
/// progress dots the rest of the flow carries. The palette follows the host's
/// brightness.
class MarketingLumenWelcomeScreen extends StatelessWidget {
  const MarketingLumenWelcomeScreen({
    required this.onNext,
    required this.onSignIn,
    super.key,
  });

  final VoidCallback onNext;
  final VoidCallback onSignIn;

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
                      SizedBox(
                        height: 36,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.dark_mode_outlined,
                                  size: 28,
                                  color: dark
                                      ? const Color(0xFFC39BFF)
                                      : const Color(0xFF6A55C4),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'LUMEN',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 2,
                                    color: dark
                                        ? const Color(0xFFC39BFF)
                                        : const Color(0xFF6A55C4),
                                  ),
                                ),
                              ],
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
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: 24),
                              SizedBox(
                                height: 260,
                                child: Stack(
                                  children: [
                                    Center(
                                      child: Container(
                                        width: 230,
                                        height: 230,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: dark
                                              ? const Color(0x0FFFFFFF)
                                              : const Color(0x0F7C6CD6),
                                          border: Border.all(
                                            color: dark
                                                ? const Color(0x24FFFFFF)
                                                : const Color(0x2E7C6CD6),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Center(
                                      child: Container(
                                        width: 160,
                                        height: 160,
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
                                      ),
                                    ),
                                    Center(
                                      child: Container(
                                        width: 92,
                                        height: 92,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
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
                                              color: Color(0x737C6CD6),
                                              blurRadius: 60,
                                              offset: Offset(0, 20),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 32),
                              Text(
                                'Find your\nquiet.',
                                style: TextStyle(
                                  fontSize: 40,
                                  height: 1.05,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -1.4,
                                  color: dark
                                      ? const Color(0xFFF4F1FF)
                                      : const Color(0xFF221E33),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'A few questions, and Lumen builds a daily practice around '
                                'your life.',
                                style: TextStyle(
                                  fontSize: 17,
                                  height: 1.45,
                                  color: dark
                                      ? const Color(0xFFB6AFD6)
                                      : const Color(0xFF6F6889),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      GestureDetector(
                        onTap: onNext,
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
                              'Begin',
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
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Flexible(
                            child: Text(
                              'Already have an account?',
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFF8E86B3),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: onSignIn,
                            child: Text(
                              'Sign in',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: dark
                                    ? const Color(0xFFC39BFF)
                                    : const Color(0xFF6A55C4),
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
          ),
        ],
      ),
    );
  }
}
