import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

/// The meditation app's welcome offer: an aurora ground, a short benefits
/// list, two glass plan cards with the annual term pre-selected, and a
/// gradient call to action.
///
/// The palette follows the host's brightness, so the same compiled surface
/// renders the night and day designs.
@Paywall()
class LumenWelcomeOfferPaywall extends StatefulWidget {
  /// Continues with the selected plan.
  static const continueFlow = SurfaceEvent<Map<String, Object?>>('continue');

  /// Dismisses the offer.
  static const close = SurfaceEvent<void>('close');

  /// Opens the subscription terms.
  static const terms = SurfaceEvent<void>('terms');

  /// Opens the privacy policy.
  static const privacy = SurfaceEvent<void>('privacy');

  /// Asks the app to restore an existing subscription; the app answers this
  /// event by running its own restore.
  static const restorePurchases = SurfaceEvent<void>('restore_purchases');

  const LumenWelcomeOfferPaywall({super.key});

  @override
  State<LumenWelcomeOfferPaywall> createState() =>
      _LumenWelcomeOfferPaywallState();
}

class _LumenWelcomeOfferPaywallState extends State<LumenWelcomeOfferPaywall> {
  /// The annual term is the default; tapping the monthly card flips it.
  bool annualSelected = true;

  void selectAnnual() => setState(() => annualSelected = true);
  void selectMonthly() => setState(() => annualSelected = false);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Stack(
        children: [
          // The aurora ground: a vertical wash, then two soft glows.
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
                      ? const [Color(0xBF8B7CF6), Color(0x008B7CF6)]
                      : const [Color(0x738B7CF6), Color(0x008B7CF6)],
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
                      ? const [Color(0x8C5EDBD1), Color(0x005EDBD1)]
                      : const [Color(0x735EDBD1), Color(0x005EDBD1)],
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
                                'LUMEN PLUS',
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
                          GestureDetector(
                            onTap: paywallEvent('close'),
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
                              const SizedBox(height: 40),
                              Text(
                                'Sleep deeper\ntonight.',
                                style: TextStyle(
                                  fontSize: 44,
                                  height: 1.02,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -1.6,
                                  color: dark
                                      ? const Color(0xFFF4F1FF)
                                      : const Color(0xFF221E33),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'Guided meditations, sleep stories and focus music, '
                                'unlocked in one calm place.',
                                style: TextStyle(
                                  fontSize: 17,
                                  height: 1.45,
                                  color: dark
                                      ? const Color(0xFFB6AFD6)
                                      : const Color(0xFF6F6889),
                                ),
                              ),
                              const SizedBox(height: 32),
                              Row(
                                children: [
                                  Icon(
                                    Icons.check_circle_outline,
                                    size: 20,
                                    color: dark
                                        ? const Color(0xFFC39BFF)
                                        : const Color(0xFF6A55C4),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      '300+ guided meditations',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                        letterSpacing: -0.1,
                                        color: dark
                                            ? const Color(0xFFF4F1FF)
                                            : const Color(0xFF221E33),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Icon(
                                    Icons.check_circle_outline,
                                    size: 20,
                                    color: dark
                                        ? const Color(0xFFC39BFF)
                                        : const Color(0xFF6A55C4),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Sleep stories and soundscapes',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                        letterSpacing: -0.1,
                                        color: dark
                                            ? const Color(0xFFF4F1FF)
                                            : const Color(0xFF221E33),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Icon(
                                    Icons.check_circle_outline,
                                    size: 20,
                                    color: dark
                                        ? const Color(0xFFC39BFF)
                                        : const Color(0xFF6A55C4),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Focus sessions for deep work',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                        letterSpacing: -0.1,
                                        color: dark
                                            ? const Color(0xFFF4F1FF)
                                            : const Color(0xFF221E33),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Annual — glass, framed while selected, carrying the badge.
                      GestureDetector(
                        onTap: selectAnnual,
                        child: Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            color: annualSelected
                                ? (dark
                                    ? const Color(0x388B7CF6)
                                    : const Color(0x1F7C6CD6))
                                : (dark
                                    ? const Color(0x14FFFFFF)
                                    : const Color(0x99FFFFFF)),
                            border: Border.all(
                              width: 1.5,
                              color: annualSelected
                                  ? (dark
                                      ? const Color(0xFFA899FF)
                                      : const Color(0xFF7C6CD6))
                                  : (dark
                                      ? const Color(0x24FFFFFF)
                                      : const Color(0x2E7C6CD6)),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Annual',
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
                                      r'14 days free, then $69.99 / year',
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
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(999),
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
                                ),
                                child: Text(
                                  'SAVE 35%',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.3,
                                    color: dark
                                        ? const Color(0xFF14102A)
                                        : const Color(0xFFFFFFFF),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Monthly — the same glass, plain while the annual is chosen.
                      GestureDetector(
                        onTap: selectMonthly,
                        child: Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            color: annualSelected
                                ? (dark
                                    ? const Color(0x14FFFFFF)
                                    : const Color(0x99FFFFFF))
                                : (dark
                                    ? const Color(0x388B7CF6)
                                    : const Color(0x1F7C6CD6)),
                            border: Border.all(
                              width: 1.5,
                              color: annualSelected
                                  ? (dark
                                      ? const Color(0x24FFFFFF)
                                      : const Color(0x2E7C6CD6))
                                  : (dark
                                      ? const Color(0xFFA899FF)
                                      : const Color(0xFF7C6CD6)),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Monthly',
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
                                      r'$8.99 / month',
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
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      GestureDetector(
                        onTap: paywallEvent(
                          'continue',
                          args: {'plan': annualSelected ? 'annual' : 'monthly'},
                        ),
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
                                color: Color(0x597C6CD6),
                                blurRadius: 30,
                                offset: Offset(0, 12),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              'Start 14 days free',
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
                          GestureDetector(
                            onTap: paywallEvent('restore_purchases'),
                            child: const Text(
                              'Restore',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF8E86B3),
                              ),
                            ),
                          ),
                          const SizedBox(width: 18),
                          GestureDetector(
                            onTap: paywallEvent('terms'),
                            child: const Text(
                              'Terms',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF8E86B3),
                              ),
                            ),
                          ),
                          const SizedBox(width: 18),
                          GestureDetector(
                            onTap: paywallEvent('privacy'),
                            child: const Text(
                              'Privacy',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF8E86B3),
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
