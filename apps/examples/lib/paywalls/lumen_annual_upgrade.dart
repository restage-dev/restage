import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

/// The meditation app's annual upgrade: a sunrise hero band with a sun disc,
/// three reasons to switch, and one yearly price card.
///
/// The palette follows the host's brightness, so the same compiled surface
/// renders the dusk and daylight designs.
@Paywall()
class LumenAnnualUpgradePaywall extends StatelessWidget {
  /// Continues with the yearly plan.
  static const continueFlow = SurfaceEvent<Map<String, Object?>>('continue');

  /// Dismisses the offer and keeps the monthly plan.
  static const close = SurfaceEvent<void>('close');

  /// Opens the subscription terms.
  static const terms = SurfaceEvent<void>('terms');

  /// Opens the privacy policy.
  static const privacy = SurfaceEvent<void>('privacy');

  const LumenAnnualUpgradePaywall({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF120E22) : const Color(0xFFFFFDFB),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The sunrise band: a share of the screen rather than a fixed
            // height, so a small phone keeps room for the price and the CTA.
            Flexible(
              flex: 46,
              child: Container(
                constraints: const BoxConstraints(
                  minHeight: 220,
                  maxHeight: 420,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: const Alignment(-0.34, -0.94),
                    end: const Alignment(0.34, 0.94),
                    colors: dark
                        ? const [
                            Color(0xFF2A1B4D),
                            Color(0xFF5B2C6F),
                            Color(0xFFC4573A),
                          ]
                        : const [
                            Color(0xFFEFE7FF),
                            Color(0xFFF8D7E3),
                            Color(0xFFFFC9A9),
                          ],
                    stops: const [0.0, 0.45, 1.0],
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      left: -60,
                      bottom: -140,
                      child: Container(
                        width: 360,
                        height: 360,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [Color(0x8CFFFFFF), Color(0x00FFFFFF)],
                            stops: [0.0, 0.68],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 26,
                      top: 150,
                      child: Container(
                        width: 150,
                        height: 150,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            center: Alignment(-0.2, -0.3),
                            colors: [
                              Color(0xFFFFF1E0),
                              Color(0xFFFFB59A),
                              Color(0x00FFB59A),
                            ],
                            stops: [0.0, 0.55, 0.72],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x80FFB59A),
                              blurRadius: 80,
                              offset: Offset(0, 30),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 24,
                      top: 72,
                      child: Row(
                        children: [
                          Icon(
                            Icons.wb_sunny_outlined,
                            size: 28,
                            color: dark
                                ? const Color(0xFFF7F3FF)
                                : const Color(0xFF2A2833),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'LUMEN PLUS',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2,
                              color: dark
                                  ? const Color(0xFFF7F3FF)
                                  : const Color(0xFF2A2833),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      left: 24,
                      right: 24,
                      bottom: 40,
                      child: Text(
                        'A whole year\nof calm.',
                        style: TextStyle(
                          fontSize: 40,
                          height: 1.02,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.4,
                          color: dark
                              ? const Color(0xFFF7F3FF)
                              : const Color(0xFF2A2833),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 54,
              // A tablet gets a centred column rather than a stretched card.
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Switch to yearly and pay \$59.99 for your first year. '
                                  'Every session, sleep story and focus mix included.',
                                  style: TextStyle(
                                    fontSize: 16,
                                    height: 1.45,
                                    color: dark
                                        ? const Color(0xFFB4AACB)
                                        : const Color(0xFF7A7290),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.check_circle_outline,
                                      size: 20,
                                      color: dark
                                          ? const Color(0xFFFFB59A)
                                          : const Color(0xFF6A55C4),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'Save 44% against monthly',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w500,
                                          letterSpacing: -0.1,
                                          color: dark
                                              ? const Color(0xFFF7F3FF)
                                              : const Color(0xFF2A2833),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.check_circle_outline,
                                      size: 20,
                                      color: dark
                                          ? const Color(0xFFFFB59A)
                                          : const Color(0xFF6A55C4),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'Offline downloads for every session',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w500,
                                          letterSpacing: -0.1,
                                          color: dark
                                              ? const Color(0xFFF7F3FF)
                                              : const Color(0xFF2A2833),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.check_circle_outline,
                                      size: 20,
                                      color: dark
                                          ? const Color(0xFFFFB59A)
                                          : const Color(0xFF6A55C4),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'New sleep stories every week',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w500,
                                          letterSpacing: -0.1,
                                          color: dark
                                              ? const Color(0xFFF7F3FF)
                                              : const Color(0xFF2A2833),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 18,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(22),
                            color: dark
                                ? const Color(0x0FFFFFFF)
                                : const Color(0xFFFFFFFF),
                            border: Border.all(
                              color: dark
                                  ? const Color(0x1AFFFFFF)
                                  : const Color(0xFFEFE9F6),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'YEARLY',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.6,
                                      color: dark
                                          ? const Color(0xFFFFB59A)
                                          : const Color(0xFFC4573A),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(999),
                                      color: dark
                                          ? const Color(0xFFFFB59A)
                                          : const Color(0xFFC4573A),
                                    ),
                                    child: const Text(
                                      'SAVE 44%',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.4,
                                        color: Color(0xFFFFFFFF),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              // Scales down rather than overflowing when a
                              // longer localised price widens the row.
                              Row(
                                children: [
                                  Flexible(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            r'$59.99',
                                            style: TextStyle(
                                              fontSize: 42,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: -1.6,
                                              color: dark
                                                  ? const Color(0xFFF7F3FF)
                                                  : const Color(0xFF2A2833),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          // Sits on the price's baseline, which the
                                          // catalog Row cannot align to directly.
                                          Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: 7),
                                            child: Text(
                                              'first year',
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: dark
                                                    ? const Color(0xFFB4AACB)
                                                    : const Color(0xFF7A7290),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: 7),
                                            child: Text(
                                              r'$107.88',
                                              style: TextStyle(
                                                fontSize: 14,
                                                decoration:
                                                    TextDecoration.lineThrough,
                                                color: dark
                                                    ? const Color(0xFFB4AACB)
                                                    : const Color(0xFF7A7290),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                r'$5 a month, billed once. '
                                r'Renews at $69.99 / year.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: dark
                                      ? const Color(0xFFB4AACB)
                                      : const Color(0xFF7A7290),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: paywallEvent(
                            'continue',
                            args: {'plan': 'yearly'},
                          ),
                          child: Container(
                            height: 58,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              // Dark is a flat coral; light is the violet ramp.
                              gradient: LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: dark
                                    ? const [
                                        Color(0xFFFFB59A),
                                        Color(0xFFFFB59A),
                                      ]
                                    : const [
                                        Color(0xFF6A55C4),
                                        Color(0xFF9A7BE8),
                                      ],
                              ),
                            ),
                            child: Center(
                              child: Text(
                                'Go yearly',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: dark
                                      ? const Color(0xFF2A1B4D)
                                      : const Color(0xFFFFFFFF),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: GestureDetector(
                                onTap: paywallEvent('close'),
                                child: Text(
                                  'Keep monthly',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: dark
                                        ? const Color(0xFF7E759B)
                                        : const Color(0xFF9A93AE),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 18),
                            Flexible(
                              child: GestureDetector(
                                onTap: paywallEvent('terms'),
                                child: Text(
                                  'Terms',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: dark
                                        ? const Color(0xFF7E759B)
                                        : const Color(0xFF9A93AE),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 18),
                            Flexible(
                              child: GestureDetector(
                                onTap: paywallEvent('privacy'),
                                child: Text(
                                  'Privacy',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: dark
                                        ? const Color(0xFF7E759B)
                                        : const Color(0xFF9A93AE),
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
            ),
          ],
        ),
      ),
    );
  }
}
