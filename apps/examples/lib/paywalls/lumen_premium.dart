import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

/// A calm, full-screen meditation **plan-selector** paywall in the
/// free-trial-led archetype — the subscription climax a wellness app shows
/// after onboarding. A soft hero, a short benefits list, then two radio plan
/// cards (the annual term pre-selected and framed, carrying a free-trial
/// badge), and a pinned "Start free trial" CTA.
///
/// This is a **fixed-brand** surface — a deliberate single-brightness calm
/// palette authored with explicit colour literals — so it holds its look
/// regardless of the host app theme.
///
/// One piece of selection state lives at the root: `annualSelected` (the annual
/// plan is the default). Tapping a card moves the radio and re-targets the
/// purchase inside the delivered blob via `paywallPurchase(slot:)`. The value
/// body is moderate, so the layout pins the CTA below an
/// `Expanded(SingleChildScrollView(...))` so the buy button never falls below
/// the fold on a small device.
@PaywallSource(id: 'lumen_premium')
class LumenPremiumPaywall extends StatefulWidget {
  const LumenPremiumPaywall({super.key});

  @override
  State<LumenPremiumPaywall> createState() => _LumenPremiumPaywallState();
}

class _LumenPremiumPaywallState extends State<LumenPremiumPaywall> {
  /// Plan selection: the annual plan is the default; tapping the monthly card
  /// flips it.
  bool annualSelected = true;

  void selectAnnual() => setState(() => annualSelected = true);
  void selectMonthly() => setState(() => annualSelected = false);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F5FB),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Back affordance, top-left.
              Row(
                children: [
                  GestureDetector(
                    onTap: paywallEvent('close'),
                    child: const Icon(
                      Icons.close_rounded,
                      color: Color(0xFFA9A4BB),
                      size: 26,
                    ),
                  ),
                ],
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),
                      // Calm hero.
                      Center(
                        child: Container(
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
                            Icons.self_improvement_rounded,
                            color: Colors.white,
                            size: 54,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Unlock Lumen Plus',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF2A2833),
                          fontSize: 27,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Your whole practice — meditation, sleep, and focus, '
                        'guided every day.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF847F92),
                          fontSize: 15,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 26),
                      // Benefits.
                      Row(
                        children: [
                          const Icon(
                            Icons.check_circle_rounded,
                            color: Color(0xFF7C6CD6),
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Hundreds of guided meditations',
                              style: TextStyle(
                                color: Color(0xFF393650),
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          const Icon(
                            Icons.check_circle_rounded,
                            color: Color(0xFF7C6CD6),
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Sleep sounds and calming soundscapes',
                              style: TextStyle(
                                color: Color(0xFF393650),
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          const Icon(
                            Icons.check_circle_rounded,
                            color: Color(0xFF7C6CD6),
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Focus music and quick reset sessions',
                              style: TextStyle(
                                color: Color(0xFF393650),
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 26),
                      // Annual plan (default selected) — framed, with a free-trial
                      // badge.
                      GestureDetector(
                        onTap: selectAnnual,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                          decoration: BoxDecoration(
                            color: annualSelected
                                ? const Color(0xFFEEEAFB)
                                : Colors.white,
                            border: Border.all(
                              color: annualSelected
                                  ? const Color(0xFF7C6CD6)
                                  : const Color(0xFFE5E1F0),
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Row(
                            children: [
                              annualSelected
                                  ? Container(
                                      width: 24,
                                      height: 24,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF7C6CD6),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(
                                        Icons.check_rounded,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                    )
                                  : Container(
                                      width: 24,
                                      height: 24,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        border: Border.all(
                                          color: const Color(0xFFCFC9DE),
                                          width: 2,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                              const SizedBox(width: 14),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Annual',
                                      style: TextStyle(
                                        color: Color(0xFF2A2833),
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    SizedBox(height: 3),
                                    Text(
                                      '14-day free trial · best value',
                                      style: TextStyle(
                                        color: Color(0xFF6A55C4),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '${paywallPriceFor(slot: 'annual')}/yr',
                                style: const TextStyle(
                                  color: Color(0xFF2A2833),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Monthly plan (unselected default). The standalone monthly
                      // price binds to the live monthly slot.
                      GestureDetector(
                        onTap: selectMonthly,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                          decoration: BoxDecoration(
                            color: annualSelected
                                ? Colors.white
                                : const Color(0xFFEEEAFB),
                            border: Border.all(
                              color: annualSelected
                                  ? const Color(0xFFE5E1F0)
                                  : const Color(0xFF7C6CD6),
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Row(
                            children: [
                              annualSelected
                                  ? Container(
                                      width: 24,
                                      height: 24,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        border: Border.all(
                                          color: const Color(0xFFCFC9DE),
                                          width: 2,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    )
                                  : Container(
                                      width: 24,
                                      height: 24,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF7C6CD6),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(
                                        Icons.check_rounded,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                    ),
                              const SizedBox(width: 14),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Monthly',
                                      style: TextStyle(
                                        color: Color(0xFF2A2833),
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    SizedBox(height: 3),
                                    Text(
                                      '7-day free trial',
                                      style: TextStyle(
                                        color: Color(0xFF847F92),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '${paywallPriceFor(slot: 'monthly')}/mo',
                                style: const TextStyle(
                                  color: Color(0xFF66616E),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
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
              const SizedBox(height: 14),
              Text(
                // ignore: lines_longer_than_80_chars
                '14-day free trial, then ${paywallPriceFor(slot: 'annual')}/year. Cancel anytime.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF847F92),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              // Start free trial CTA — calm pill; purchases the selected plan.
              GestureDetector(
                onTap: paywallPurchase(
                  slot: annualSelected ? 'annual' : 'monthly',
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 17),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C6CD6),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: const Text(
                    'Start free trial',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: paywallEvent('restore'),
                    child: const Text(
                      'Restore',
                      style: TextStyle(
                        color: Color(0xFF6A55C4),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Text(
                    '   ·   ',
                    style: TextStyle(color: Color(0xFFC6BFD9), fontSize: 14),
                  ),
                  GestureDetector(
                    onTap: paywallEvent('terms'),
                    child: const Text(
                      'Terms',
                      style: TextStyle(
                        color: Color(0xFF6A55C4),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
