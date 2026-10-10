import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

/// The second screen of [LumenPlusOfferPaywall]: the trial's terms before it
/// starts.
@Paywall()
class LumenPlusCheckoutScreen extends StatelessWidget {
  const LumenPlusCheckoutScreen({super.key});

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
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
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
                                  Icons.arrow_back_ios_new,
                                  size: 14,
                                  color: dark
                                      ? const Color(0xFFB6AFD6)
                                      : const Color(0xFF6F6889),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
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
                      const SizedBox(height: 28),
                      Text(
                        'Start your free trial',
                        style: TextStyle(
                          fontSize: 32,
                          height: 1.1,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1,
                          color: dark
                              ? const Color(0xFFF4F1FF)
                              : const Color(0xFF221E33),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 8,
                                ),
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
                                child: Column(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 10),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              'Plan',
                                              style: TextStyle(
                                                fontSize: 15,
                                                color: dark
                                                    ? const Color(0xFFB6AFD6)
                                                    : const Color(0xFF6F6889),
                                              ),
                                            ),
                                          ),
                                          Text(
                                            r'Annual',
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                              color: dark
                                                  ? const Color(0xFFF4F1FF)
                                                  : const Color(0xFF221E33),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 10),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              'Due today',
                                              style: TextStyle(
                                                fontSize: 15,
                                                color: dark
                                                    ? const Color(0xFFB6AFD6)
                                                    : const Color(0xFF6F6889),
                                              ),
                                            ),
                                          ),
                                          Text(
                                            r'$0.00',
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                              color: dark
                                                  ? const Color(0xFFF4F1FF)
                                                  : const Color(0xFF221E33),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 10),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              'After 14 days',
                                              style: TextStyle(
                                                fontSize: 15,
                                                color: dark
                                                    ? const Color(0xFFB6AFD6)
                                                    : const Color(0xFF6F6889),
                                              ),
                                            ),
                                          ),
                                          Text(
                                            r'$69.99 / year',
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                              color: dark
                                                  ? const Color(0xFFF4F1FF)
                                                  : const Color(0xFF221E33),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                "We'll remind you 2 days before your trial ends. "
                                'Cancel anytime in Settings.',
                                style: TextStyle(
                                  fontSize: 14,
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
                      const SizedBox(height: 18),
                      GestureDetector(
                        onTap: paywallEvent(
                          'continue',
                          args: {'plan': 'annual'},
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
