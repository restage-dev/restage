import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

/// A light, membership-style plan paywall in the expandable-plan-card
/// archetype — the shape a media subscription (audiobooks, streaming, news)
/// often uses: a "current membership" status card, a headline, and two
/// selectable plan cards where the **selected** card expands to reveal a
/// benefits checklist and a "Try … free" call to action while the other
/// collapses to its title and price.
///
/// This is a **fixed-brand** surface — a deliberate single-brightness palette
/// (a white canvas, an indigo accent) authored with explicit colour literals —
/// so it holds its look regardless of the host app theme.
///
/// ## Pinned offer over a scrollable value body
///
/// The value content (the status card and the headline) scrolls in an
/// `Expanded(SingleChildScrollView(...))`; the offer zone — the two plan cards,
/// with the selected card's inline CTA — is pinned below.
///
/// One piece of selection state lives at the root: `standardSelected` (the
/// Standard plan is the default). Tapping a card moves the radio, expands that
/// card (and collapses the other), and re-targets the purchase inside the
/// delivered blob.
///
/// The whole tree is inlined flat (no extracted helper widget / method) so the
/// transpiler follows it — a helper that returns a widget is not a catalog
/// widget and does not lower. The Standard auto-renew line binds its price to
/// the live monthly slot; the Premium price is literal. The purchase is
/// live-bound per plan via `paywallPurchase(slot:)`.
@PaywallSource(id: 'narrate_membership')
class NarrateMembershipPaywall extends StatefulWidget {
  const NarrateMembershipPaywall({super.key});

  @override
  State<NarrateMembershipPaywall> createState() =>
      _NarrateMembershipPaywallState();
}

class _NarrateMembershipPaywallState extends State<NarrateMembershipPaywall> {
  /// Plan selection: the Standard plan is the default (expanded); tapping the
  /// Premium Plus card flips it.
  bool standardSelected = true;

  void selectStandard() => setState(() => standardSelected = true);
  void selectPremium() => setState(() => standardSelected = false);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Scrollable value content; the offer zone below is pinned.
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Top bar: a back affordance + a close affordance.
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          GestureDetector(
                            onTap: paywallEvent('close'),
                            child: const Icon(
                              Icons.arrow_back_ios_new_rounded,
                              color: Color(0xFF5A6B82),
                              size: 20,
                            ),
                          ),
                          GestureDetector(
                            onTap: paywallEvent('close'),
                            child: const Icon(
                              Icons.close_rounded,
                              color: Color(0xFF16263C),
                              size: 26,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Current-membership status card.
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 18,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F7FB),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Column(
                          children: [
                            Text(
                              'CURRENT MEMBERSHIP',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFF5A6B82),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
                              ),
                            ),
                            SizedBox(height: 10),
                            Text(
                              "You're not currently a member.",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFF16263C),
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      const Text(
                        'Get the most out of Narrate',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF13243B),
                          fontSize: 27,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Switch plans or cancel anytime.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF16263C),
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Pinned offer zone — the two selectable plan cards.
              // Standard card: expands (benefits + CTA) when selected.
              GestureDetector(
                onTap: selectStandard,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(
                      color: standardSelected
                          ? const Color(0xFF4F46E5)
                          : const Color(0xFFE0E3E9),
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              border:
                                  Border.all(color: const Color(0xFFB8C0CC)),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'FREE TRIAL',
                              style: TextStyle(
                                color: Color(0xFF5A6B82),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          const Spacer(),
                          // Selection radio (filled when Standard is selected).
                          standardSelected
                              ? Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF4F46E5),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Center(
                                    child: Container(
                                      width: 9,
                                      height: 9,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                    ),
                                  ),
                                )
                              : Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    border: Border.all(
                                      color: const Color(0xFFC2C7D0),
                                      width: 2,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Standard',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF13243B),
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        // ignore: lines_longer_than_80_chars
                        'Auto-renews at ${paywallPriceFor(slot: 'monthly')}/mo after 1-month trial',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF4A5A6E),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      // Expanded content only when Standard is selected.
                      standardSelected
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const SizedBox(height: 14),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 11),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 24,
                                        height: 24,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF16263C),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: const Icon(
                                          Icons.check_rounded,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      const Expanded(
                                        child: Text(
                                          'Select 1 audiobook a month from a '
                                          'catalogue of over 1 million titles.',
                                          style: TextStyle(
                                            color: Color(0xFF16263C),
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            height: 1.3,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 11),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 24,
                                        height: 24,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF16263C),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: const Icon(
                                          Icons.check_rounded,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      const Expanded(
                                        child: Text(
                                          'Keep your chosen audiobooks for as '
                                          "long as you're a member.",
                                          style: TextStyle(
                                            color: Color(0xFF16263C),
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            height: 1.3,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 11),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 24,
                                        height: 24,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF16263C),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: const Icon(
                                          Icons.check_rounded,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      const Expanded(
                                        child: Text(
                                          'Unlimited access to a library of '
                                          'bingeable podcasts.',
                                          style: TextStyle(
                                            color: Color(0xFF16263C),
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            height: 1.3,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                GestureDetector(
                                  onTap: paywallPurchase(slot: 'monthly'),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 15,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF4F46E5),
                                      borderRadius: BorderRadius.circular(28),
                                    ),
                                    child: const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          'Try Standard free',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        SizedBox(width: 8),
                                        Icon(
                                          Icons.open_in_new_rounded,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : const SizedBox(height: 4),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Premium Plus card: expands (benefits + CTA) when selected.
              GestureDetector(
                onTap: selectPremium,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F2FD),
                    border: Border.all(
                      color: standardSelected
                          ? const Color(0xFFE0E3E9)
                          : const Color(0xFF4F46E5),
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              border:
                                  Border.all(color: const Color(0xFFB8C0CC)),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              '30 DAYS FREE',
                              style: TextStyle(
                                color: Color(0xFF5A6B82),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          const Spacer(),
                          // Selection radio (filled when Premium is selected).
                          standardSelected
                              ? Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    border: Border.all(
                                      color: const Color(0xFFC2C7D0),
                                      width: 2,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                )
                              : Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF4F46E5),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Center(
                                    child: Container(
                                      width: 9,
                                      height: 9,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                    ),
                                  ),
                                ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Premium Plus',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF13243B),
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '1 credit a month',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF4F46E5),
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        r'$14.95/mo after trial',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF4A5A6E),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      // Expanded content only when Premium Plus is selected.
                      standardSelected
                          ? const SizedBox(height: 4)
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const SizedBox(height: 14),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 11),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 24,
                                        height: 24,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF16263C),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: const Icon(
                                          Icons.check_rounded,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      const Expanded(
                                        child: Text(
                                          'Get 1 credit a month for any premium '
                                          'title, yours to keep forever.',
                                          style: TextStyle(
                                            color: Color(0xFF16263C),
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            height: 1.3,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 11),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 24,
                                        height: 24,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF16263C),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: const Icon(
                                          Icons.check_rounded,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      const Expanded(
                                        child: Text(
                                          'Unlimited listening across a huge '
                                          'selection of audiobooks and shows.',
                                          style: TextStyle(
                                            color: Color(0xFF16263C),
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            height: 1.3,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                GestureDetector(
                                  onTap: paywallPurchase(slot: 'annual'),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 15,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF4F46E5),
                                      borderRadius: BorderRadius.circular(28),
                                    ),
                                    child: const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          'Try Premium Plus free',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        SizedBox(width: 8),
                                        Icon(
                                          Icons.open_in_new_rounded,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ],
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
