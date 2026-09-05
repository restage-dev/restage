import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

/// The meditation app's seasonal offer: a night-sky ground with a soft
/// aurora sweep and scattered stars, one discounted yearly price, and a
/// deadline pill.
///
/// The palette follows the host's brightness, so the same compiled surface
/// renders the night and daylight designs.
@Paywall()
class LumenHolidayPromoPaywall extends StatelessWidget {
  /// Continues with the seasonal yearly plan.
  static const continueFlow = SurfaceEvent<Map<String, Object?>>('continue');

  /// Dismisses the offer.
  static const close = SurfaceEvent<void>('close');

  /// Opens the subscription terms.
  static const terms = SurfaceEvent<void>('terms');

  /// Opens the privacy policy.
  static const privacy = SurfaceEvent<void>('privacy');

  const LumenHolidayPromoPaywall({super.key});

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
                          Color(0xFF06111F),
                          Color(0xFF0B1B33),
                          Color(0xFF071426),
                        ]
                      : const [
                          Color(0xFFF3F8FF),
                          Color(0xFFE8F1FB),
                          Color(0xFFEEF3FA),
                        ],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),
          // The aurora: a teal-to-violet sweep whose open ends fall offscreen.
          Positioned(
            left: -80,
            top: -160,
            child: Container(
              width: 560,
              height: 560,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(
                  center: const Alignment(0.2, -0.4),
                  startAngle: 1.9199,
                  endAngle: 5.4105,
                  colors: dark
                      ? const [
                          Color(0x005EDBD1),
                          Color(0x8C5EDBD1),
                          Color(0x8C8B7CF6),
                          Color(0x005EDBD1),
                        ]
                      : const [
                          Color(0x005EDBD1),
                          Color(0x735EDBD1),
                          Color(0x668B7CF6),
                          Color(0x005EDBD1),
                        ],
                  stops: const [0.0, 0.3, 0.6, 1.0],
                ),
              ),
            ),
          ),
          Positioned(
            left: 40,
            top: 110,
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dark ? const Color(0x8CFFFFFF) : const Color(0x40152238),
              ),
            ),
          ),
          Positioned(
            left: 120,
            top: 60,
            child: Container(
              width: 3,
              height: 3,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dark ? const Color(0x8CFFFFFF) : const Color(0x40152238),
              ),
            ),
          ),
          Positioned(
            left: 210,
            top: 150,
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dark ? const Color(0x8CFFFFFF) : const Color(0x40152238),
              ),
            ),
          ),
          Positioned(
            left: 300,
            top: 80,
            child: Container(
              width: 3,
              height: 3,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dark ? const Color(0x8CFFFFFF) : const Color(0x40152238),
              ),
            ),
          ),
          Positioned(
            left: 350,
            top: 200,
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dark ? const Color(0x8CFFFFFF) : const Color(0x40152238),
              ),
            ),
          ),
          Positioned(
            left: 70,
            top: 230,
            child: Container(
              width: 3,
              height: 3,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dark ? const Color(0x8CFFFFFF) : const Color(0x40152238),
              ),
            ),
          ),
          Positioned(
            left: 250,
            top: 250,
            child: Container(
              width: 3,
              height: 3,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dark ? const Color(0x8CFFFFFF) : const Color(0x40152238),
              ),
            ),
          ),
          Positioned(
            left: 330,
            top: 300,
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dark ? const Color(0x8CFFFFFF) : const Color(0x40152238),
              ),
            ),
          ),
          Positioned(
            left: 150,
            top: 320,
            child: Container(
              width: 3,
              height: 3,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dark ? const Color(0x8CFFFFFF) : const Color(0x40152238),
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
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.ac_unit,
                                    size: 28,
                                    color: dark
                                        ? const Color(0xFF8FF0E8)
                                        : const Color(0xFF0E7C74),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    'WINTER OFFER',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 2,
                                      color: dark
                                          ? const Color(0xFF8FF0E8)
                                          : const Color(0xFF0E7C74),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              color: dark
                                  ? const Color(0x295EDBD1)
                                  : const Color(0x405EDBD1),
                            ),
                            child: Text(
                              'ENDS 2 JAN',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.4,
                                color: dark
                                    ? const Color(0xFF8FF0E8)
                                    : const Color(0xFF0E7C74),
                              ),
                            ),
                          ),
                        ],
                      ),
                      // The airy top is a share of what is left rather than a
                      // fixed drop, so the headline is on the first screen of a
                      // small phone and the design keeps its height on a tall
                      // one.
                      const Flexible(child: SizedBox(height: 150)),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'A quieter\nwinter.',
                                style: TextStyle(
                                  fontSize: 46,
                                  height: 1.0,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -1.8,
                                  color: dark
                                      ? const Color(0xFFEEF6FF)
                                      : const Color(0xFF152238),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  // The mockup caps this line rather than
                                  // fixing it, so a narrow phone can shrink it.
                                  Flexible(
                                    child: Container(
                                      constraints: const BoxConstraints(
                                        maxWidth: 330,
                                      ),
                                      child: Text(
                                        "The full library for the darkest weeks, at the "
                                        "year's lowest price.",
                                        style: TextStyle(
                                          fontSize: 17,
                                          height: 1.45,
                                          color: dark
                                              ? const Color(0xFF9FB3CC)
                                              : const Color(0xFF5E6F8A),
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
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(26),
                          color: dark
                              ? const Color(0x0FFFFFFF)
                              : const Color(0xB3FFFFFF),
                          border: Border.all(
                            color: dark
                                ? const Color(0x24FFFFFF)
                                : const Color(0x1A152238),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                // Scales down rather than overflowing when a
                                // longer localised price widens the row.
                                Flexible(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          r'$49.99',
                                          style: TextStyle(
                                            fontSize: 42,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: -1.6,
                                            color: dark
                                                ? const Color(0xFFEEF6FF)
                                                : const Color(0xFF152238),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        // Sits on the price's baseline, which the
                                        // catalog Row cannot align to directly.
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 7),
                                          child: Text(
                                            'first year',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: dark
                                                  ? const Color(0xFF9FB3CC)
                                                  : const Color(0xFF5E6F8A),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                Flexible(
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: 7),
                                    child: Text(
                                      r'$69.99',
                                      style: TextStyle(
                                        fontSize: 14,
                                        decoration: TextDecoration.lineThrough,
                                        color: dark
                                            ? const Color(0xFF9FB3CC)
                                            : const Color(0xFF5E6F8A),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Container(
                              height: 1,
                              decoration: BoxDecoration(
                                color: dark
                                    ? const Color(0x24FFFFFF)
                                    : const Color(0x1A152238),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Icon(
                                  Icons.check_circle_outline,
                                  size: 20,
                                  color: dark
                                      ? const Color(0xFF8FF0E8)
                                      : const Color(0xFF0E7C74),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Everything in Lumen Plus',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: -0.1,
                                      color: dark
                                          ? const Color(0xFFEEF6FF)
                                          : const Color(0xFF152238),
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
                                      ? const Color(0xFF8FF0E8)
                                      : const Color(0xFF0E7C74),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    r'Renews at $69.99 / year',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: -0.1,
                                      color: dark
                                          ? const Color(0xFFEEF6FF)
                                          : const Color(0xFF152238),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      GestureDetector(
                        onTap: paywallEvent(
                          'continue',
                          args: {'plan': 'winter_yearly'},
                        ),
                        child: Container(
                          height: 58,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: dark
                                  ? const [Color(0xFF5EDBD1), Color(0xFF8B7CF6)]
                                  : const [
                                      Color(0xFF2FB8AD),
                                      Color(0xFF6A55C4)
                                    ],
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x475EDBD1),
                                blurRadius: 34,
                                offset: Offset(0, 14),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              'Claim the winter price',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: dark
                                    ? const Color(0xFF061224)
                                    : const Color(0xFFFFFFFF),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Flexible(
                            child: Text(
                              'Restore',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF8895AA),
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
                                      ? const Color(0xFF6F83A0)
                                      : const Color(0xFF8895AA),
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
                                      ? const Color(0xFF6F83A0)
                                      : const Color(0xFF8895AA),
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
    );
  }
}
