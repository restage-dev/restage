import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

/// A free-trial paywall for a fitness / activity app — a **single screen with a
/// modal bottom sheet**, in the trial-timeline archetype. One screen, three
/// states:
///   1. **Footer (no scrim):** a clean white surface with a soft warm hero glow,
///      an upper-right circular dismiss, a bold headline, and a vertical trial
///      **timeline** (Today → 2 Days before → In 30 days) drawn with accent dots,
///      a connecting line, and a closing down-arrow — over a flat grey footer
///      band holding one "Start free trial" pill. No sheet, no scrim yet.
///   2. **Modal sheet (scrim):** tapping the footer calls a standard
///      `showModalBottomSheet(...)`, which the build-time codegen lowers to the
///      declarative drag-to-dismiss sheet. The sheet rises over a scrim (the
///      timeline dims); collapsed content shows "Free 30-Day Trial" + a
///      "Save 44%" flash, the default (Annual) price summary, an outlined
///      "See All Plans" button, the "Start free trial" CTA, and the legal line.
///   3. **See All Plans (content swap + grow):** "See All Plans" flips
///      `plansExpanded`; the summary + See-All-Plans button are replaced in place
///      by the Annual / Monthly radio card and the sheet grows, while the CTA
///      stays pinned at the bottom.
///
/// You write the same `showModalBottomSheet` you'd write in any Flutter app — no
/// gesture or animation code crosses the wire. The trigger becomes a synthetic
/// open flag, the sheet's own drag / scrim dismiss clears it, and the surface
/// behind it is carried as the sheet's underlay. Drag-to-dismiss and scrim-tap
/// are the sheet's built-in behavior.
///
/// Two within-screen selection states lower into the render blob: `plansExpanded`
/// (the See-All-Plans swap) and `annualSelected` (the plan radios + the purchase
/// target). Both are plain `bool` fields that lower to `switch state.…`, so the
/// whole interaction travels with the delivered paywall, no host code.
///
/// Authoring notes: the tree is flat (the sheet body is inlined in the
/// `builder`, no extracted helper); the sheet's `builder` names its param `_` and
/// reads no `BuildContext` (fixed colour literals — a deliberate single-brightness
/// brand surface); the down-arrow is pushed to the rail's bottom with
/// `mainAxisAlignment.end`. Prices bind live via `paywallPriceFor(slot:)`; the
/// "Save 44%" flash is a literal marketing flag.
@PaywallSource(id: 'ascend_premium')
class AscendPremiumPaywall extends StatefulWidget {
  const AscendPremiumPaywall({super.key});

  @override
  State<AscendPremiumPaywall> createState() => _AscendPremiumPaywallState();
}

class _AscendPremiumPaywallState extends State<AscendPremiumPaywall> {
  /// Whether the full plan list is shown. Collapsed by default — the sheet opens
  /// on the default (Annual) plan with a "See All Plans" affordance.
  bool plansExpanded = false;

  /// Plan selection: annual when true, monthly when false. Annual is default.
  bool annualSelected = true;

  void showAllPlans() => setState(() => plansExpanded = true);
  void selectAnnual() => setState(() => annualSelected = true);
  void selectMonthly() => setState(() => annualSelected = false);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      body: Stack(
        children: [
          // Soft warm hero glow bleeding from the top, behind the content.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 260,
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topCenter,
                  radius: 0.9,
                  colors: [Color(0x3306B6A4), Color(0x0006B6A4)],
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Close affordance, top-right (grey circle).
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              GestureDetector(
                                onTap: paywallEvent('close'),
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFEDEDF0),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.close_rounded,
                                    color: Color(0xFF55555C),
                                    size: 22,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            "Try the very best of Ascend. First month's on us.",
                            style: TextStyle(
                              color: Color(0xFF1A1A1A),
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 26),
                          // Trial timeline — step 1 (Today). Each step is an
                          // IntrinsicHeight Row: a left rail (dot + connecting
                          // line that fills the row height) and the step text.
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 48,
                                  child: Column(
                                    children: [
                                      Container(
                                        width: 14,
                                        height: 14,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFF06B6A4),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 4,
                                          ),
                                          child: Container(
                                            width: 6,
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF06B6A4),
                                              borderRadius:
                                                  BorderRadius.circular(3),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Today',
                                        style: TextStyle(
                                          color: Color(0xFF1A1A1A),
                                          fontSize: 20,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      SizedBox(height: 6),
                                      Text(
                                        'Unlock premium features including route '
                                        'planning, segment insights, and advanced '
                                        'training analysis.',
                                        style: TextStyle(
                                          color: Color(0xFF6D6D72),
                                          fontSize: 14,
                                          height: 1.35,
                                        ),
                                      ),
                                      SizedBox(height: 30),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Step 2 (2 Days before).
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 48,
                                  child: Column(
                                    children: [
                                      Container(
                                        width: 14,
                                        height: 14,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFF06B6A4),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 4,
                                          ),
                                          child: Container(
                                            width: 6,
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF06B6A4),
                                              borderRadius:
                                                  BorderRadius.circular(3),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '2 Days before',
                                        style: TextStyle(
                                          color: Color(0xFF1A1A1A),
                                          fontSize: 20,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      SizedBox(height: 6),
                                      Text(
                                        'Get a reminder before your trial ends.',
                                        style: TextStyle(
                                          color: Color(0xFF6D6D72),
                                          fontSize: 14,
                                          height: 1.35,
                                        ),
                                      ),
                                      SizedBox(height: 30),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Step 3 (In 30 days) — the rail closes with a
                          // down-arrow pushed to the bottom of the rail.
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 48,
                                  child: Column(
                                    children: [
                                      Container(
                                        width: 14,
                                        height: 14,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFF06B6A4),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      Expanded(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.end,
                                          children: [
                                            // Bold chunky down-arrow: a thick
                                            // rounded grey shaft overlapping a
                                            // wide chevron arrowhead (head wider
                                            // than the bars). Composed because a
                                            // thin Icon reads too light; the
                                            // shaft is Positioned over the glyph
                                            // so they read as one arrow.
                                            SizedBox(
                                              width: 48,
                                              height: 50,
                                              child: Stack(
                                                children: [
                                                  // Thick rounded shaft from the
                                                  // top, centred on the rail.
                                                  Positioned(
                                                    top: 0,
                                                    left: 0,
                                                    right: 0,
                                                    child: Center(
                                                      child: Container(
                                                        width: 7,
                                                        height: 28,
                                                        decoration:
                                                            BoxDecoration(
                                                          color: const Color(
                                                            0xFF8A8A8A,
                                                          ),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      3.5),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  // Wide heavy chevron head at the
                                                  // bottom, overlapping the shaft
                                                  // so they read as one arrow.
                                                  const Positioned(
                                                    bottom: 0,
                                                    left: 0,
                                                    right: 0,
                                                    child: Center(
                                                      child: Icon(
                                                        Icons.expand_more,
                                                        color:
                                                            Color(0xFF8A8A8A),
                                                        size: 46,
                                                      ),
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
                                ),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'In 30 days',
                                        style: TextStyle(
                                          color: Color(0xFF1A1A1A),
                                          fontSize: 20,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      SizedBox(height: 6),
                                      Text(
                                        "You'll be charged for your plan. Cancel "
                                        'at least 24 hours before.',
                                        style: TextStyle(
                                          color: Color(0xFF6D6D72),
                                          fontSize: 14,
                                          height: 1.35,
                                        ),
                                      ),
                                      SizedBox(height: 8),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Flat grey footer band (full-bleed). Its "Start free trial" pill
                // opens the plan sheet via a real showModalBottomSheet.
                Container(
                  color: const Color(0xFFEFEFF2),
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: GestureDetector(
                    onTap: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: const Color(0xFFFFFFFF),
                      // The lowering lifts this builder body into the declarative
                      // sheet child; it reads the outer paywall state (named `_`
                      // here) and no own BuildContext, so it lowers statically.
                      // The sheet body is inlined (no extracted helper).
                      builder: (_) => Padding(
                        padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Collapsed (default-plan summary + See All Plans) vs
                            // expanded (the full Annual/Monthly radio card). A
                            // widget-level ternary on the state field lowers to
                            // `switch state.plansExpanded { true: …, false: … }`.
                            plansExpanded
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      const Text(
                                        'Free 30-Day Trial',
                                        style: TextStyle(
                                          color: Color(0xFF1A1A1A),
                                          fontSize: 20,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 14),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF6F6F8),
                                          borderRadius:
                                              BorderRadius.circular(16),
                                        ),
                                        child: Column(
                                          children: [
                                            // Annual row.
                                            GestureDetector(
                                              onTap: selectAnnual,
                                              child: Container(
                                                color: const Color(0x00000000),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  vertical: 16,
                                                ),
                                                child: Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Row(
                                                            children: [
                                                              const Text(
                                                                'Annual',
                                                                style:
                                                                    TextStyle(
                                                                  color: Color(
                                                                    0xFF1A1A1A,
                                                                  ),
                                                                  fontSize: 17,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w800,
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                width: 10,
                                                              ),
                                                              Container(
                                                                padding:
                                                                    const EdgeInsets
                                                                        .symmetric(
                                                                  horizontal: 8,
                                                                  vertical: 3,
                                                                ),
                                                                decoration:
                                                                    BoxDecoration(
                                                                  color:
                                                                      const Color(
                                                                    0xFF06B6A4,
                                                                  ),
                                                                  borderRadius:
                                                                      BorderRadius
                                                                          .circular(
                                                                    6,
                                                                  ),
                                                                ),
                                                                child:
                                                                    const Text(
                                                                  'Save 44%',
                                                                  style:
                                                                      TextStyle(
                                                                    color: Colors
                                                                        .white,
                                                                    fontSize:
                                                                        12,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w800,
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                          const SizedBox(
                                                            height: 6,
                                                          ),
                                                          Row(
                                                            children: [
                                                              const Text(
                                                                'Free 30-day '
                                                                'trial, then ',
                                                                style:
                                                                    TextStyle(
                                                                  color: Color(
                                                                    0xFF6D6D72,
                                                                  ),
                                                                  fontSize: 13,
                                                                ),
                                                              ),
                                                              Text(
                                                                paywallPriceFor(
                                                                  slot:
                                                                      'annual',
                                                                ),
                                                                style:
                                                                    const TextStyle(
                                                                  color: Color(
                                                                    0xFF1A1A1A,
                                                                  ),
                                                                  fontSize: 13,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w800,
                                                                ),
                                                              ),
                                                              const Text(
                                                                '/year',
                                                                style:
                                                                    TextStyle(
                                                                  color: Color(
                                                                    0xFF6D6D72,
                                                                  ),
                                                                  fontSize: 13,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    const SizedBox(width: 12),
                                                    // Radio glyph — filled when
                                                    // selected.
                                                    Container(
                                                      width: 24,
                                                      height: 24,
                                                      decoration: BoxDecoration(
                                                        shape: BoxShape.circle,
                                                        border: Border.all(
                                                          color: annualSelected
                                                              ? const Color(
                                                                  0xFF06B6A4,
                                                                )
                                                              : const Color(
                                                                  0xFFC4C4CC,
                                                                ),
                                                          width: 2,
                                                        ),
                                                      ),
                                                      child: annualSelected
                                                          ? Center(
                                                              child: Container(
                                                                width: 12,
                                                                height: 12,
                                                                decoration:
                                                                    const BoxDecoration(
                                                                  color: Color(
                                                                    0xFF06B6A4,
                                                                  ),
                                                                  shape: BoxShape
                                                                      .circle,
                                                                ),
                                                              ),
                                                            )
                                                          : const SizedBox(),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            const Divider(
                                              height: 1,
                                              color: Color(0xFFE4E4EA),
                                            ),
                                            // Monthly row.
                                            GestureDetector(
                                              onTap: selectMonthly,
                                              child: Container(
                                                color: const Color(0x00000000),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  vertical: 16,
                                                ),
                                                child: Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          const Text(
                                                            'Monthly',
                                                            style: TextStyle(
                                                              color: Color(
                                                                0xFF1A1A1A,
                                                              ),
                                                              fontSize: 17,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w800,
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            height: 6,
                                                          ),
                                                          Row(
                                                            children: [
                                                              const Text(
                                                                'Free 30-day '
                                                                'trial, then ',
                                                                style:
                                                                    TextStyle(
                                                                  color: Color(
                                                                    0xFF6D6D72,
                                                                  ),
                                                                  fontSize: 13,
                                                                ),
                                                              ),
                                                              Text(
                                                                paywallPriceFor(
                                                                  slot:
                                                                      'monthly',
                                                                ),
                                                                style:
                                                                    const TextStyle(
                                                                  color: Color(
                                                                    0xFF1A1A1A,
                                                                  ),
                                                                  fontSize: 13,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w800,
                                                                ),
                                                              ),
                                                              const Text(
                                                                '/month',
                                                                style:
                                                                    TextStyle(
                                                                  color: Color(
                                                                    0xFF6D6D72,
                                                                  ),
                                                                  fontSize: 13,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    const SizedBox(width: 12),
                                                    Container(
                                                      width: 24,
                                                      height: 24,
                                                      decoration: BoxDecoration(
                                                        shape: BoxShape.circle,
                                                        border: Border.all(
                                                          color: annualSelected
                                                              ? const Color(
                                                                  0xFFC4C4CC,
                                                                )
                                                              : const Color(
                                                                  0xFF06B6A4,
                                                                ),
                                                          width: 2,
                                                        ),
                                                      ),
                                                      child: annualSelected
                                                          ? const SizedBox()
                                                          : Center(
                                                              child: Container(
                                                                width: 12,
                                                                height: 12,
                                                                decoration:
                                                                    const BoxDecoration(
                                                                  color: Color(
                                                                    0xFF06B6A4,
                                                                  ),
                                                                  shape: BoxShape
                                                                      .circle,
                                                                ),
                                                              ),
                                                            ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  )
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        children: [
                                          const Text(
                                            'Free 30-Day Trial',
                                            style: TextStyle(
                                              color: Color(0xFF1A1A1A),
                                              fontSize: 20,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF06B6A4),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: const Text(
                                              'Save 44%',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Text(
                                            paywallPriceFor(slot: 'annual'),
                                            style: const TextStyle(
                                              color: Color(0xFF1A1A1A),
                                              fontSize: 15,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          const Text(
                                            '/year after trial',
                                            style: TextStyle(
                                              color: Color(0xFF6D6D72),
                                              fontSize: 15,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                      // See All Plans — outlined pill; expands
                                      // the sheet in place.
                                      GestureDetector(
                                        onTap: showAllPlans,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 15,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFFFFFF),
                                            borderRadius:
                                                BorderRadius.circular(28),
                                            border: Border.all(
                                              color: const Color(0xFF06B6A4),
                                              width: 1.5,
                                            ),
                                          ),
                                          child: const Text(
                                            'See All Plans',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: Color(0xFF06B6A4),
                                              fontSize: 16,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                            const SizedBox(height: 12),
                            // Start free trial CTA — purchases the selected plan.
                            // Pinned last so it stays at the sheet bottom as the
                            // expanded card grows the sheet.
                            GestureDetector(
                              onTap: paywallPurchase(
                                slot: annualSelected ? 'annual' : 'monthly',
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF06B6A4),
                                  borderRadius: BorderRadius.circular(28),
                                ),
                                child: const Text(
                                  'Start free trial',
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
                            const Text(
                              "You won't be charged until your trial ends. "
                              'Cancel any time up to 24 hours before.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFF8A8A90),
                                fontSize: 12,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF06B6A4),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: const Text(
                        'Start free trial',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
