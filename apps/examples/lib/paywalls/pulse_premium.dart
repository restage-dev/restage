import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

/// A dark, conversion-first premium paywall in the segmented-tier archetype:
/// a three-way tier strip (Basic | Premium | Premium+), a long scrolling
/// feature list, two **side-by-side** plan cards with a selected-state border, a
/// flowing rich-text legal line, and an explicit Terms / Privacy / Restore row.
///
/// This is a **fixed-brand** surface — a deliberate single-brightness palette
/// (near-black canvas, white type, a violet accent) authored with explicit
/// colour literals — so it holds its look regardless of the host app theme. A
/// bold conversion paywall is often a single-brightness brand moment on purpose.
///
/// ## Pinned offer over a scrollable value body
///
/// The offer zone — the plan cards, the purchase CTA, and the legal row — is
/// **pinned**: it lives in fixed siblings below an `Expanded(SingleChildScroll
/// View(...))` that carries the value content (wordmark, headline, tier strip,
/// feature rows). So the price + buy button are always on screen while the long
/// feature list scrolls — the layout fits every device, smallest included,
/// without the offer ever falling below the fold.
///
/// Two pieces of selection state live at the root: the tier (`selectedTier`,
/// an `int` so the strip is a true three-way choice) and the billing period
/// (`annualSelected`). Both lower into the render blob as state switches and
/// both DRIVE the surface: the feature list grows per tier (the entry tier
/// shows the core rows; the upper tiers add more — each extra row gated by an
/// int-equality conditional on `selectedTier`), and the price + the CTA
/// re-target to the selected tier x the selected period, so neither selector is
/// decorative — the whole interaction travels with the delivered paywall, with
/// no host code.
///
/// The feature rows are inlined flat (no extracted helper widget) so the
/// transpiler follows the tree. Note: the inline link word in the legal line is
/// styled but not tappable — a per-word tap inside a rich-text run is not yet
/// expressible in the render blob. The Terms / Privacy / Restore row below
/// carries the working affordance.
@PaywallSource(id: 'pulse_premium')
class PulsePremiumPaywall extends StatefulWidget {
  const PulsePremiumPaywall({super.key});

  @override
  State<PulsePremiumPaywall> createState() => _PulsePremiumPaywallState();
}

class _PulsePremiumPaywallState extends State<PulsePremiumPaywall> {
  /// Tier strip selection: 0 = Basic, 1 = Premium, 2 = Premium+.
  int selectedTier = 1;

  /// Plan selection: annual when true, monthly when false. Monthly is the
  /// default so the promo flash shows.
  bool annualSelected = false;

  void selectBasic() => setState(() => selectedTier = 0);
  void selectPremium() => setState(() => selectedTier = 1);
  void selectPremiumPlus() => setState(() => selectedTier = 2);

  void selectAnnual() => setState(() => annualSelected = true);
  void selectMonthly() => setState(() => annualSelected = false);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B12),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Scrollable value content; the offer zone below is pinned.
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Close affordance, top-left (start-aligned Row).
                      Row(
                        children: [
                          GestureDetector(
                            onTap: paywallEvent('close'),
                            child: const Icon(
                              Icons.close_rounded,
                              color: Color(0xFFE6E6F0),
                              size: 26,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Brand wordmark at the top.
                      const Center(
                        child: Text(
                          'Pulse',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Upgrade to Premium',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Tri-state segmented tier selector — Basic | Premium |
                      // Premium+. Each segment's fill + label colour switch on
                      // `selectedTier == n`.
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF17171F),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: selectBasic,
                                child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 9),
                                  decoration: BoxDecoration(
                                    color: selectedTier == 0
                                        ? const Color(0xFF7B61FF)
                                        : const Color(0x00000000),
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  child: Text(
                                    'Basic',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: selectedTier == 0
                                          ? const Color(0xFFFFFFFF)
                                          : const Color(0xFF9AA0AB),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: selectPremium,
                                child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 9),
                                  decoration: BoxDecoration(
                                    color: selectedTier == 1
                                        ? const Color(0xFF7B61FF)
                                        : const Color(0x00000000),
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  child: Text(
                                    'Premium',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: selectedTier == 1
                                          ? const Color(0xFFFFFFFF)
                                          : const Color(0xFF9AA0AB),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: selectPremiumPlus,
                                child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 9),
                                  decoration: BoxDecoration(
                                    color: selectedTier == 2
                                        ? const Color(0xFF7B61FF)
                                        : const Color(0x00000000),
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  child: Text(
                                    'Premium+',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: selectedTier == 2
                                          ? const Color(0xFFFFFFFF)
                                          : const Color(0xFF9AA0AB),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      // The full feature list — icon-tile + bold-title + grey
                      // subtitle rows, inlined flat. The long list scrolls; the
                      // offer pins.
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E1E28),
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: const Icon(
                                Icons.verified_rounded,
                                color: Color(0xFF7B61FF),
                                size: 23,
                              ),
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Verified badge',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Build trust and protect your profile from '
                                    'impersonation.',
                                    style: TextStyle(
                                      color: Color(0xFF9AA0AB),
                                      fontSize: 13,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E1E28),
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: const Icon(
                                Icons.auto_awesome_rounded,
                                color: Color(0xFF7B61FF),
                                size: 23,
                              ),
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'AI-assisted replies',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Draft faster with higher assistant usage '
                                    'limits.',
                                    style: TextStyle(
                                      color: Color(0xFF9AA0AB),
                                      fontSize: 13,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E1E28),
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: const Icon(
                                Icons.trending_up_rounded,
                                color: Color(0xFF7B61FF),
                                size: 23,
                              ),
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Boosted reach',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Get your posts seen by more people across '
                                    'the network.',
                                    style: TextStyle(
                                      color: Color(0xFF9AA0AB),
                                      fontSize: 13,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E1E28),
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: const Icon(
                                Icons.do_not_disturb_on_outlined,
                                color: Color(0xFF7B61FF),
                                size: 23,
                              ),
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Fewer ads',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'See about half the ads across your '
                                    'timelines.',
                                    style: TextStyle(
                                      color: Color(0xFF9AA0AB),
                                      fontSize: 13,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E1E28),
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: const Icon(
                                Icons.notes_rounded,
                                color: Color(0xFF7B61FF),
                                size: 23,
                              ),
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Longer posts',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Write longer posts with more room to say '
                                    'it.',
                                    style: TextStyle(
                                      color: Color(0xFF9AA0AB),
                                      fontSize: 13,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Mid-tier features — hidden for the entry tier (selected
                      // index 0), shown for the upper two tiers.
                      selectedTier == 0
                          ? const SizedBox()
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF1E1E28),
                                          borderRadius:
                                              BorderRadius.circular(11),
                                        ),
                                        child: const Icon(
                                          Icons.edit_rounded,
                                          color: Color(0xFF7B61FF),
                                          size: 23,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      const Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Edit window',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            SizedBox(height: 2),
                                            Text(
                                              'Fix typos for up to an hour after posting.',
                                              style: TextStyle(
                                                color: Color(0xFF9AA0AB),
                                                fontSize: 13,
                                                height: 1.35,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF1E1E28),
                                          borderRadius:
                                              BorderRadius.circular(11),
                                        ),
                                        child: const Icon(
                                          Icons.videocam_rounded,
                                          color: Color(0xFF7B61FF),
                                          size: 23,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      const Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'HD video',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            SizedBox(height: 2),
                                            Text(
                                              'Upload longer, higher-quality videos.',
                                              style: TextStyle(
                                                color: Color(0xFF9AA0AB),
                                                fontSize: 13,
                                                height: 1.35,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF1E1E28),
                                          borderRadius:
                                              BorderRadius.circular(11),
                                        ),
                                        child: const Icon(
                                          Icons.lock_rounded,
                                          color: Color(0xFF7B61FF),
                                          size: 23,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      const Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Encrypted DMs',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            SizedBox(height: 2),
                                            Text(
                                              'Keep your direct messages private and '
                                              'secure.',
                                              style: TextStyle(
                                                color: Color(0xFF9AA0AB),
                                                fontSize: 13,
                                                height: 1.35,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF1E1E28),
                                          borderRadius:
                                              BorderRadius.circular(11),
                                        ),
                                        child: const Icon(
                                          Icons.article_rounded,
                                          color: Color(0xFF7B61FF),
                                          size: 23,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      const Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Long-form publishing',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            SizedBox(height: 2),
                                            Text(
                                              'Publish formatted, long-form articles.',
                                              style: TextStyle(
                                                color: Color(0xFF9AA0AB),
                                                fontSize: 13,
                                                height: 1.35,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                      // Top-tier-only features — shown only for the top tier
                      // (selected index 2).
                      selectedTier == 2
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF1E1E28),
                                          borderRadius:
                                              BorderRadius.circular(11),
                                        ),
                                        child: const Icon(
                                          Icons.workspace_premium_rounded,
                                          color: Color(0xFF7B61FF),
                                          size: 23,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      const Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Creator subscriptions',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            SizedBox(height: 2),
                                            Text(
                                              'Earn recurring revenue from your '
                                              'subscribers.',
                                              style: TextStyle(
                                                color: Color(0xFF9AA0AB),
                                                fontSize: 13,
                                                height: 1.35,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF1E1E28),
                                          borderRadius:
                                              BorderRadius.circular(11),
                                        ),
                                        child: const Icon(
                                          Icons.paid_rounded,
                                          color: Color(0xFF7B61FF),
                                          size: 23,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      const Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Revenue share',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            SizedBox(height: 2),
                                            Text(
                                              'Share in the ad revenue from replies to '
                                              'your posts.',
                                              style: TextStyle(
                                                color: Color(0xFF9AA0AB),
                                                fontSize: 13,
                                                height: 1.35,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF1E1E28),
                                          borderRadius:
                                              BorderRadius.circular(11),
                                        ),
                                        child: const Icon(
                                          Icons.insights_rounded,
                                          color: Color(0xFF7B61FF),
                                          size: 23,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      const Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Advanced analytics',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            SizedBox(height: 2),
                                            Text(
                                              'See deeper insight into how your content '
                                              'performs.',
                                              style: TextStyle(
                                                color: Color(0xFF9AA0AB),
                                                fontSize: 13,
                                                height: 1.35,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF1E1E28),
                                          borderRadius:
                                              BorderRadius.circular(11),
                                        ),
                                        child: const Icon(
                                          Icons.bookmark_rounded,
                                          color: Color(0xFF7B61FF),
                                          size: 23,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      const Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Bookmark folders',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            SizedBox(height: 2),
                                            Text(
                                              'Organize your saved posts into custom '
                                              'folders.',
                                              style: TextStyle(
                                                color: Color(0xFF9AA0AB),
                                                fontSize: 13,
                                                height: 1.35,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            )
                          : const SizedBox(),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // Pinned offer zone — the side-by-side plan cards, the CTA, and the
              // legal stay on screen while the value content above scrolls.
              // Monthly | Annual two-column cards (IntrinsicHeight equalises the
              // two card heights); the selected card gets the violet border and
              // tapping it re-targets the CTA.
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: selectMonthly,
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF17171F),
                            border: Border.all(
                              color: annualSelected
                                  ? const Color(0xFF2A2A33)
                                  : const Color(0xFF7B61FF),
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Monthly',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                '50% off',
                                style: TextStyle(
                                  color: Color(0xFF7B61FF),
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const Text(
                                'for 2 months',
                                style: TextStyle(
                                  color: Color(0xFF9AA0AB),
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Text(
                                    'Then ',
                                    style: TextStyle(
                                      color: Color(0xFF9AA0AB),
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    paywallPriceFor(
                                      slot: selectedTier == 0
                                          ? 'basic_monthly'
                                          : selectedTier == 1
                                              ? 'premium_monthly'
                                              : 'premiumplus_monthly',
                                    ),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const Text(
                                    '/mo',
                                    style: TextStyle(
                                      color: Color(0xFF9AA0AB),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: selectAnnual,
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF17171F),
                            border: Border.all(
                              color: annualSelected
                                  ? const Color(0xFF7B61FF)
                                  : const Color(0xFF2A2A33),
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Annual',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Best value',
                                style: TextStyle(
                                  color: Color(0xFF9AA0AB),
                                  fontSize: 13,
                                ),
                              ),
                              const Spacer(),
                              Row(
                                children: [
                                  Text(
                                    paywallPriceFor(
                                      slot: selectedTier == 0
                                          ? 'basic_annual'
                                          : selectedTier == 1
                                              ? 'premium_annual'
                                              : 'premiumplus_annual',
                                    ),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const Text(
                                    '/yr',
                                    style: TextStyle(
                                      color: Color(0xFF9AA0AB),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Subscribe & pay CTA — violet pill; purchases the selected plan.
              GestureDetector(
                onTap: paywallPurchase(
                  slot: selectedTier == 0
                      ? (annualSelected ? 'basic_annual' : 'basic_monthly')
                      : selectedTier == 1
                          ? (annualSelected
                              ? 'premium_annual'
                              : 'premium_monthly')
                          : (annualSelected
                              ? 'premiumplus_annual'
                              : 'premiumplus_monthly'),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7B61FF),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: const Text(
                    'Subscribe & pay',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Dense legal fine print as one flowing italic rich-text paragraph
              // inside a bordered box; the link word is styled inline (the
              // working tap is the row below).
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF2A2A33)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text.rich(
                  TextSpan(
                    style: const TextStyle(
                      color: Color(0xFF6B6B78),
                      fontSize: 11,
                      height: 1.4,
                      fontStyle: FontStyle.italic,
                    ),
                    children: const [
                      TextSpan(text: 'By subscribing, you agree to our '),
                      TextSpan(
                        text: 'Terms of Service',
                        style: TextStyle(
                          color: Color(0xFF7B61FF),
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                      TextSpan(
                        text: '. Subscriptions auto-renew until canceled. '
                            'Cancel anytime.',
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: paywallEvent('terms_of_service'),
                    child: const Text(
                      'Terms',
                      style: TextStyle(color: Color(0xFF7B61FF), fontSize: 11),
                    ),
                  ),
                  const Text(
                    '·',
                    style: TextStyle(color: Color(0xFF6B6B78)),
                  ),
                  TextButton(
                    onPressed: paywallEvent('privacy_policy'),
                    child: const Text(
                      'Privacy',
                      style: TextStyle(color: Color(0xFF7B61FF), fontSize: 11),
                    ),
                  ),
                  const Text(
                    '·',
                    style: TextStyle(color: Color(0xFF6B6B78)),
                  ),
                  TextButton(
                    onPressed: paywallEvent('restore'),
                    child: const Text(
                      'Restore',
                      style: TextStyle(color: Color(0xFF7B61FF), fontSize: 11),
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
