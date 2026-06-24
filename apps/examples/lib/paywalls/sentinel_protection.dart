import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

/// A light, savings-led plan selector in the discount-badge archetype — the
/// shape a security, VPN, or utility subscription often uses: a brand badge +
/// discount-mark hero, then two radio plan cards where the longer term is
/// pre-selected, framed, and carries a "Save 50%" badge with a struck-through
/// original price.
///
/// This is a **fixed-brand** surface — a deliberate single-brightness palette
/// (a light-grey canvas, a teal accent) authored with explicit colour literals
/// — so it holds its look regardless of the host app theme.
///
/// ## Distributed (not floor-pinned) layout
///
/// The value content here is short (just a header + a hero), so the strict
/// pinned-CTA mechanism (`Expanded(SingleChildScrollView(...))` over a pinned
/// offer) would absorb all the slack into one empty void above a floor-pinned
/// block. Instead this is a bounded `Column` with `Spacer`s between the header,
/// the hero, the cards, and the bottom block, so the slack is distributed into
/// moderate gaps that scale with the device — the hero sits in the upper-middle,
/// the cards in the lower-middle, and the summary + CTA + privacy near the
/// bottom, with the CTA always on-screen (it fits the smallest device
/// unscrolled). For a long value body, prefer the pinned-CTA layout (an
/// `Expanded(SingleChildScrollView(...))` over a pinned offer) so the buy button
/// never falls below the fold.
///
/// One piece of selection state lives at the root: `yearSelected` (the 1-year
/// plan is the default). Tapping a card moves the radio and re-targets the
/// purchase inside the delivered blob.
///
/// The discount story (the struck `$99.99 → $49.99`, the `Save 50%` badge, the
/// `$4.17/month` equivalent) is authored as literal text so it stays internally
/// consistent; the standalone 1-month price binds to the live monthly slot. The
/// purchase is live-bound per plan via `paywallPurchase(slot:)`.
@PaywallSource(id: 'sentinel_protection')
class SentinelProtectionPaywall extends StatefulWidget {
  const SentinelProtectionPaywall({super.key});

  @override
  State<SentinelProtectionPaywall> createState() =>
      _SentinelProtectionPaywallState();
}

class _SentinelProtectionPaywallState extends State<SentinelProtectionPaywall> {
  /// Plan selection: the 1-year plan is the default; tapping the 1-month card
  /// flips it.
  bool yearSelected = true;

  void selectYear() => setState(() => yearSelected = true);
  void selectMonth() => setState(() => yearSelected = false);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header.
              // Back affordance, top-left (start-aligned Row).
              Row(
                children: [
                  GestureDetector(
                    onTap: paywallEvent('close'),
                    child: const Icon(
                      Icons.chevron_left_rounded,
                      color: Color(0xFF0EA5A4),
                      size: 30,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Select your protection plan',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF14142B),
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'No commitment. You can cancel anytime in your Apple account.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF6B6B76),
                  fontSize: 15,
                  height: 1.35,
                ),
              ),
              // Slack above the hero — pushes it into the upper-middle.
              const Spacer(),
              // Brand badge + discount mark hero, sized for central presence.
              SizedBox(
                height: 178,
                child: Stack(
                  children: [
                    Center(
                      child: Container(
                        width: 150,
                        height: 150,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD6F5F2),
                          borderRadius: BorderRadius.circular(75),
                        ),
                        child: Center(
                          child: Container(
                            width: 92,
                            height: 92,
                            decoration: BoxDecoration(
                              color: const Color(0xFF0EA5A4),
                              borderRadius: BorderRadius.circular(46),
                            ),
                            child: const Icon(
                              Icons.shield_rounded,
                              color: Colors.white,
                              size: 50,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 70,
                      top: 16,
                      child: Container(
                        width: 62,
                        height: 62,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF5A4D),
                          borderRadius: BorderRadius.circular(31),
                        ),
                        child: const Center(
                          child: Text(
                            '%',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Slack between the hero and the cards.
              const Spacer(),
              // 1-year plan (default selected). A "Save 50%" badge sits at the
              // top-right; the teal frame + filled radio track the selection.
              GestureDetector(
                onTap: selectYear,
                child: Stack(
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(14, 18, 14, 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(
                          color: yearSelected
                              ? const Color(0xFF0EA5A4)
                              : const Color(0xFFE2E3E8),
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          // Radio indicator.
                          yearSelected
                              ? Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0EA5A4),
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
                                      color: const Color(0xFFC2C3CC),
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
                                  '1-year plan',
                                  style: TextStyle(
                                    color: Color(0xFF14142B),
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text(
                                      r'$99.99',
                                      style: TextStyle(
                                        color: Color(0xFF9A9AA3),
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        decoration: TextDecoration.lineThrough,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      r'$49.99',
                                      style: TextStyle(
                                        color: Color(0xFF14142B),
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const Text(
                            r'$4.17/month',
                            style: TextStyle(
                              color: Color(0xFF0EA5A4),
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0EA5A4),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: const Text(
                          'Save 50%',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // 1-month plan (unselected default). The standalone monthly price
              // binds to the live monthly slot.
              GestureDetector(
                onTap: selectMonth,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(
                      color: yearSelected
                          ? const Color(0xFFE2E3E8)
                          : const Color(0xFF0EA5A4),
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      yearSelected
                          ? Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(
                                  color: const Color(0xFFC2C3CC),
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                            )
                          : Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: const Color(0xFF0EA5A4),
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
                        child: Text(
                          '1-month plan',
                          style: TextStyle(
                            color: Color(0xFF14142B),
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        '${paywallPriceFor(slot: 'monthly')}/month',
                        style: const TextStyle(
                          color: Color(0xFF6B6B76),
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Slack between the cards and the bottom block.
              const Spacer(),
              const Text(
                r'First year — $49.99. Auto-renews at $99.99/year.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF6B6B76),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              // Start subscription CTA — teal pill; purchases the selected plan.
              GestureDetector(
                onTap: paywallPurchase(
                  slot: yearSelected ? 'annual' : 'monthly',
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0EA5A4),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text(
                    'Start subscription',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: GestureDetector(
                  onTap: paywallEvent('subscription_info'),
                  child: const Text(
                    'Subscription and privacy info',
                    style: TextStyle(
                      color: Color(0xFF0EA5A4),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
