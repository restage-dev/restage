import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/lumen_welcome_refresh.restage.g.dart';

/// The prepared second version of the marketing demo's welcome screen.
/// Its layout is compiled and delivered as data; the flow events stay the same.
@Screen()
class LumenWelcomeScreen extends StatelessWidget {
  static const next = SurfaceEvent<void>('next');
  static const signIn = SurfaceEvent<void>('sign_in');

  const LumenWelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: dark
                ? const [
                    Color(0xFF0F0B1F),
                    Color(0xFF14102A),
                    Color(0xFF0B0817)
                  ]
                : const [
                    Color(0xFFFBFAFF),
                    Color(0xFFF4F1FC),
                    Color(0xFFEFEAF9)
                  ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 72, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 36,
                child: Row(
                  children: [
                    Icon(
                      Icons.dark_mode_outlined,
                      size: 26,
                      color: dark
                          ? const Color(0xFFC39BFF)
                          : const Color(0xFF6A55C4),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'LUMEN',
                      style: TextStyle(
                        fontSize: 13,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w700,
                        color: dark
                            ? const Color(0xFFC39BFF)
                            : const Color(0xFF6A55C4),
                      ),
                    ),
                    const Spacer(),
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
              const SizedBox(height: 28),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Your calm,\nyour way.',
                        style: TextStyle(
                          fontSize: 42,
                          height: 1.05,
                          letterSpacing: -1.6,
                          fontWeight: FontWeight.w800,
                          color: dark
                              ? const Color(0xFFF4F1FF)
                              : const Color(0xFF221E33),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'A brighter morning. A softer landing.\nMake space for the moments that matter.',
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.5,
                          color: dark
                              ? const Color(0xFFB6AFD6)
                              : const Color(0xFF6F6889),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          color: dark
                              ? const Color(0xFF231C36)
                              : const Color(0xFFF9F6FF),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AspectRatio(
                              aspectRatio: 2,
                              child: Stack(
                                children: [
                                  Positioned(
                                    left: 0,
                                    top: 0,
                                    right: 0,
                                    bottom: 0,
                                    child: Container(
                                      decoration: const BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Color(0xFF40385F),
                                            Color(0xFFB79ACF)
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 28,
                                    right: 48,
                                    child: Container(
                                      width: 88,
                                      height: 88,
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Color(0xFFE5D7FF),
                                        boxShadow: [
                                          BoxShadow(
                                              color: Color(0x55C39BFF),
                                              blurRadius: 48,
                                              spreadRadius: 14)
                                        ],
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    left: -110,
                                    bottom: -100,
                                    child: Container(
                                      width: 410,
                                      height: 210,
                                      decoration: BoxDecoration(
                                        borderRadius:
                                            BorderRadius.circular(200),
                                        color: const Color(0xFF8476AE),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    right: -90,
                                    bottom: -110,
                                    child: Container(
                                      width: 370,
                                      height: 210,
                                      decoration: BoxDecoration(
                                        borderRadius:
                                            BorderRadius.circular(200),
                                        color: const Color(0xFF51456F),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    left: -40,
                                    right: -40,
                                    bottom: -145,
                                    child: Container(
                                      height: 200,
                                      decoration: BoxDecoration(
                                        borderRadius:
                                            BorderRadius.circular(200),
                                        color: const Color(0xFF302A4C),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    left: 18,
                                    top: 18,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: const Color(0x33FFFFFF),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: const Text('A FRESH START',
                                          style: TextStyle(
                                              fontSize: 10,
                                              letterSpacing: 1.2,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFFFFFFFF))),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(18),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text('The morning reset',
                                            style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.w700,
                                                color: dark
                                                    ? const Color(0xFFF4F1FF)
                                                    : const Color(0xFF221E33))),
                                        const SizedBox(height: 5),
                                        Text(
                                            'Five minutes. A little more space.',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: dark
                                                    ? const Color(0xFFB6AFD6)
                                                    : const Color(0xFF6F6889))),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Icon(Icons.wb_sunny_outlined,
                                      size: 24,
                                      color: dark
                                          ? const Color(0xFFC39BFF)
                                          : const Color(0xFF6A55C4)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.air,
                              size: 17,
                              color: dark
                                  ? const Color(0xFFC8B8E5)
                                  : const Color(0xFF6A55C4)),
                          const SizedBox(width: 6),
                          Text('Breathe',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: dark
                                      ? const Color(0xFFC8B8E5)
                                      : const Color(0xFF6A55C4))),
                          const SizedBox(width: 22),
                          Icon(Icons.spa_outlined,
                              size: 17,
                              color: dark
                                  ? const Color(0xFFC8B8E5)
                                  : const Color(0xFF6A55C4)),
                          const SizedBox(width: 6),
                          Text('Unwind',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: dark
                                      ? const Color(0xFFC8B8E5)
                                      : const Color(0xFF6A55C4))),
                          const SizedBox(width: 22),
                          Icon(Icons.nights_stay_outlined,
                              size: 17,
                              color: dark
                                  ? const Color(0xFFC8B8E5)
                                  : const Color(0xFF6A55C4)),
                          const SizedBox(width: 6),
                          Text('Rest',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: dark
                                      ? const Color(0xFFC8B8E5)
                                      : const Color(0xFF6A55C4))),
                        ],
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
                          : const [Color(0xFF6A55C4), Color(0xFF8B7CF6)],
                    ),
                  ),
                  child: Center(
                    child: Text('Find my rhythm',
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: dark
                                ? const Color(0xFF14102A)
                                : const Color(0xFFFFFFFF))),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: surfaceEvent(signIn),
                child: Center(
                  child: Text('Already a member? Sign in',
                      style: TextStyle(
                          fontSize: 13,
                          color: dark
                              ? const Color(0xFFC8B8E5)
                              : const Color(0xFF6A55C4))),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
