import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

import 'fluent_pro_choose_plan.dart';

/// A playful, gradient-hero premium paywall in the free-trial + two-plan-radio
/// archetype — the shape a consumer subscription app (a language tutor, a habit
/// tracker, a kids' learning app) often uses: a glowing mascot hero over a
/// dark blue → purple gradient, a free-trial headline with one accented phrase,
/// and two plan cards (a "most popular" one framed and pre-selected).
///
/// This is a **fixed-brand** surface — a deliberate single-brightness palette
/// (a dark gradient canvas, white type, a teal accent) authored with explicit
/// colour literals — so it holds its look regardless of the host app theme.
///
/// ## Pinned offer over a scrollable value body
///
/// The value content (the mascot hero and the headline) scrolls in an
/// `Expanded(SingleChildScrollView(...))`; the offer zone — the two plan cards,
/// the purchase pill, the "view all plans" link, and the legal line — is pinned
/// below, so the buy button is always on screen.
///
/// One piece of selection state lives at the root: `personalSelected` (the
/// framed "most popular" Personal plan is the default). Tapping a plan card
/// moves the selected check and re-targets the purchase — all inside the
/// delivered blob, with no host code.
///
/// ## "View all plans" is a real navigation
///
/// The "VIEW ALL PLANS" control is a real `Navigator.push` to a second
/// [PaywallSource] ([FluentProChoosePlanScreen]); the build-time codegen lowers
/// it to a 2-screen flow (entry → choose-a-plan), and the entry's back
/// affordance fires `paywallEvent('skip')` — the flow's required terminator.
/// RestagePaywall hosts the lowered flow transparently (no host-code change).
///
/// The mascot hero is a glowing gradient capsule with sparkle accents — a
/// lightweight stand-in for a real mascot illustration, composed from catalog
/// primitives so the whole surface travels in the render blob.
@PaywallSource(id: 'fluent_pro')
class FluentProPaywall extends StatefulWidget {
  const FluentProPaywall({super.key});

  @override
  State<FluentProPaywall> createState() => _FluentProPaywallState();
}

class _FluentProPaywallState extends State<FluentProPaywall> {
  /// Plan selection: the framed "most popular" Personal plan is the default;
  /// tapping Family flips it.
  bool personalSelected = true;

  void selectFamily() => setState(() => personalSelected = false);
  void selectPersonal() => setState(() => personalSelected = true);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        // Dark indigo → violet canvas. Explicit Alignment(x, y) so the gradient
        // direction lowers as a concrete value rather than a named constant.
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(0, -1),
            end: Alignment(0, 1),
            colors: [
              Color(0xFF13183A),
              Color(0xFF241B5C),
              Color(0xFF3A2270),
            ],
            stops: [0, 0.5, 1],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Scrollable value content; the offer zone below is pinned.
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Top row: close affordance + the "PRO" badge.
                        Row(
                          children: [
                            // The flow terminator: dismissing the entry maps to
                            // the lowered flow's `skip` -> `end` (required, or
                            // the Navigator.push lowering fatal-defers).
                            GestureDetector(
                              onTap: paywallEvent('skip'),
                              child: const Icon(
                                Icons.arrow_back_rounded,
                                color: Colors.white,
                                size: 26,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF16C79A),
                                    Color(0xFF35A0E8),
                                    Color(0xFF8B5CF6),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'PRO',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                  fontStyle: FontStyle.italic,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        // Glowing mascot hero + sparkle accents.
                        SizedBox(
                          height: 150,
                          child: Stack(
                            children: [
                              Center(
                                child: Container(
                                  width: 94,
                                  height: 134,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      begin: Alignment(0, -1),
                                      end: Alignment(0, 1),
                                      colors: [
                                        Color(0xFF16C79A),
                                        Color(0xFF35C1E8),
                                        Color(0xFFC44BE6),
                                        Color(0xFFE7E9F5),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(42),
                                    border: Border.all(
                                      color: const Color(0x66FFFFFF),
                                      width: 2,
                                    ),
                                  ),
                                  child: const Center(
                                    child: Icon(
                                      Icons.auto_awesome,
                                      color: Colors.white,
                                      size: 36,
                                    ),
                                  ),
                                ),
                              ),
                              const Positioned(
                                left: 44,
                                top: 28,
                                child: Icon(
                                  Icons.auto_awesome,
                                  color: Color(0xFFEAF6FF),
                                  size: 18,
                                ),
                              ),
                              const Positioned(
                                right: 52,
                                top: 44,
                                child: Icon(
                                  Icons.auto_awesome,
                                  color: Color(0xFFEAF6FF),
                                  size: 14,
                                ),
                              ),
                              const Positioned(
                                right: 84,
                                bottom: 34,
                                child: Icon(
                                  Icons.circle,
                                  color: Color(0xFF7FC4FF),
                                  size: 8,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        // Free-trial headline; the trial phrase is accented teal.
                        const Text.rich(
                          TextSpan(
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 25,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                              letterSpacing: -0.3,
                            ),
                            children: [
                              TextSpan(text: 'Get started with a '),
                              TextSpan(
                                text: '7 day free trial',
                                style: TextStyle(color: Color(0xFF16E0A8)),
                              ),
                              TextSpan(text: ' on Pro'),
                            ],
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                // Pinned offer zone — the two plan cards, the CTA, and the legal.
                // Family plan (unselected default). Tapping it re-targets.
                GestureDetector(
                  onTap: selectFamily,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF252050),
                      border: Border.all(
                        color: personalSelected
                            ? const Color(0x33FFFFFF)
                            : const Color(0xFF16C79A),
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Family',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                r'12 mo • $119.99',
                                style: TextStyle(
                                  color: Color(0xFFB4ADD6),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Text(
                          r'$9.99 / MO',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Selected check — appears when Family is the chosen plan
                        // (mirrors the Personal card's in-row check). Positive
                        // condition with swapped branches: the check shows when
                        // Personal is NOT selected.
                        personalSelected
                            ? const SizedBox(width: 26, height: 26)
                            : Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1CB0F6),
                                  borderRadius: BorderRadius.circular(13),
                                ),
                                child: const Icon(
                                  Icons.check_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Personal plan — the framed "most popular" default. A bright
                // gradient frame (composed as an outer gradient container around
                // the card fill), a ribbon tab, and a selected check that appears
                // when this plan is chosen.
                GestureDetector(
                  onTap: selectPersonal,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF16C79A),
                          Color(0xFF1CB0F6),
                          Color(0xFFB45CFF),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF2C2566),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // MOST POPULAR ribbon tab.
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF16C79A), Color(0xFF1CB0F6)],
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'MOST POPULAR',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                            child: Row(
                              children: [
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Personal',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 22,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        r'12 mo • $95.99',
                                        style: TextStyle(
                                          color: Color(0xFFCFC9F0),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  paywallPriceFor(slot: 'monthly'),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const Text(
                                  ' / MO',
                                  style: TextStyle(
                                    color: Color(0xFFCFC9F0),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                // Selected check — appears when Personal is the
                                // chosen plan.
                                personalSelected
                                    ? Container(
                                        width: 26,
                                        height: 26,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF1CB0F6),
                                          borderRadius:
                                              BorderRadius.circular(13),
                                        ),
                                        child: const Icon(
                                          Icons.check_rounded,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                      )
                                    : const SizedBox(width: 26, height: 26),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Cancel anytime in the App Store',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFC6CFE8),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                // White "START MY FREE WEEK" pill — purchases the selected plan.
                GestureDetector(
                  onTap: paywallPurchase(
                    slot: personalSelected ? 'monthly' : 'family',
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text(
                      'START MY FREE WEEK',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF1A1340),
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: GestureDetector(
                    // "View all plans" pushes the all-tiers "Choose a plan"
                    // screen. The build-time codegen lowers this Navigator.push
                    // to a flow transition (entry -> choose-a-plan), hosted
                    // transparently by RestagePaywall.
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const FluentProChoosePlanScreen(),
                      ),
                    ),
                    child: const Text(
                      'VIEW ALL PLANS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text.rich(
                  TextSpan(
                    style: TextStyle(
                      color: Color(0xFFB9C2DD),
                      fontSize: 11,
                      height: 1.4,
                    ),
                    children: [
                      TextSpan(
                        text: 'Your monthly or annual subscription ',
                      ),
                      TextSpan(
                        text: 'automatically renews',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      TextSpan(
                        text: ' for the same term unless cancelled at least 24 '
                            'hours prior to the end of the current term.',
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
