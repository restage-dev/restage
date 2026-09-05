import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/lumen_trial_ending.restage.g.dart';

/// Message — the last nudge before a meditation trial ends.
///
/// A glass sheet centred on the aurora ground. The primary action opens the
/// offer; "Maybe later" ends the message, and so does the close control.
@Screen(id: 'lumen_trial_ending', surface: Surface.message)
class LumenTrialEndingScreen extends StatelessWidget {
  /// Opens the subscription offer.
  static const openOffer = SurfaceEvent<void>('open_offer');

  /// Dismisses the message. The host decides what dismissal means.
  static const later = SurfaceEvent<void>('later');

  const LumenTrialEndingScreen({super.key});

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
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          GestureDetector(
                            onTap: surfaceEvent(later),
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
                                            Icons.notifications_none_rounded,
                                            size: 44,
                                            color: dark
                                                ? const Color(0xFFC39BFF)
                                                : const Color(0xFF6A55C4),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 26),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(999),
                                            color: dark
                                                ? const Color(0x1AFFFFFF)
                                                : const Color(0x1A7C6CD6),
                                          ),
                                          child: Text(
                                            'TRIAL ENDS IN 2 DAYS',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 1.2,
                                              color: dark
                                                  ? const Color(0xFFC39BFF)
                                                  : const Color(0xFF6A55C4),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      'Keep the calm going',
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
                                      'Your 14 free days are nearly up. Stay on the yearly '
                                      'plan and keep every sleep story and session.',
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
                                      onTap: surfaceEvent(openOffer),
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
                                            'See the offer',
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
                                    const SizedBox(height: 10),
                                    GestureDetector(
                                      onTap: surfaceEvent(later),
                                      child: SizedBox(
                                        height: 48,
                                        child: Center(
                                          child: Text(
                                            'Maybe later',
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                              color: dark
                                                  ? const Color(0xFFB6AFD6)
                                                  : const Color(0xFF6F6889),
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
