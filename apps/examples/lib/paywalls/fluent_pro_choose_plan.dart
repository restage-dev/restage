import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

/// "Choose a plan" all-tiers screen — the pushed screen of the lowered
/// [FluentProPaywall] flow.
///
/// Authored as a standard [PaywallSource]; the entry paywall's "VIEW ALL PLANS"
/// control (`Navigator.push(context, MaterialPageRoute(builder: (_) => const
/// FluentProChoosePlanScreen()))`) lowers to a flow transition into this screen,
/// and the `() => Navigator.pop(context)` back chevron lowers to the runtime's
/// in-flow back.
///
/// **Select-then-subscribe** (faithful to the entry, which has its own
/// `personalSelected` state): one piece of selection state lives at the root,
/// `selectedPlan` (0 = Family, 1 = Personal — the MOST POPULAR default,
/// 2 = Student, 3 = Monthly). Tapping a tier card SELECTS it — an in-row
/// trailing check moves to the chosen tier and the chosen card highlights — all
/// inside the delivered blob; no tier charges on tap. The pinned
/// "START MY FREE WEEK" CTA charges the SELECTED tier's slot via
/// `paywallPurchase(slot:)`.
///
/// A two-group all-tiers picker: a dark indigo → violet vertical gradient canvas
/// (matching the entry), a "Choose a plan" title, a "7 DAY FREE TRIAL" group
/// (Family + a "MOST POPULAR" Personal with a gradient frame + the selected
/// check) and a "NO FREE TRIAL" group (Student + Monthly), then a "Cancel anytime
/// in the App Store" line and a white "START MY FREE WEEK" pill.
///
/// The selected-check is an in-row trailing element (beside the price), the same
/// idiom the entry's plan cards use — so it never overlaps the price on a short
/// single-row card.
///
/// Pinned-offer layout: the four plan cards scroll in an
/// `Expanded(SingleChildScrollView(...))`; the offer zone (the cancel line + the
/// CTA) is pinned below, so the buy button is always on screen.
///
/// Prices are literal: the tiers are annual-billed shown as a per-month figure
/// whose /MO and 12-mo total agree ($9.99×12 ≈ $119.99, $7.99×12 ≈ $95.99,
/// $3.99×12 ≈ $47.99), which binding to the demo's monthly / annual price slots
/// would distort. The purchase is live-bound to the selected tier via
/// `paywallPurchase(slot:)`.
///
/// Fixed-brand, single-brightness surface authored with explicit colour
/// literals, so it never reads the ambient theme. Transpilable-authoring rules:
/// flat tree, no extracted helper widgets, inline values.
@PaywallSource(id: 'fluent_pro_choose_plan')
class FluentProChoosePlanScreen extends StatefulWidget {
  const FluentProChoosePlanScreen({super.key});

  @override
  State<FluentProChoosePlanScreen> createState() =>
      _FluentProChoosePlanScreenState();
}

class _FluentProChoosePlanScreenState extends State<FluentProChoosePlanScreen> {
  /// The chosen tier: 0 = Family, 1 = Personal (the MOST POPULAR default),
  /// 2 = Student, 3 = Monthly. Tapping a card moves the selection; the pinned
  /// CTA charges this tier's slot.
  int selectedPlan = 1;

  void selectFamily() => setState(() => selectedPlan = 0);
  void selectPersonal() => setState(() => selectedPlan = 1);
  void selectStudent() => setState(() => selectedPlan = 2);
  void selectMonthly() => setState(() => selectedPlan = 3);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
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
                // Top row: in-flow back chevron + the "PRO" badge.
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.arrow_back_ios_new,
                          size: 22,
                          color: Colors.white,
                        ),
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
                const Text(
                  'Choose a plan',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 20),
                // The four plan cards scroll; the offer zone below is pinned.
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // "7 DAY FREE TRIAL" group divider.
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                height: 1,
                                color: const Color(0x33FFFFFF),
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Text(
                                '7 DAY FREE TRIAL',
                                style: TextStyle(
                                  color: Color(0xFFB4ADD6),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Container(
                                height: 1,
                                color: const Color(0x33FFFFFF),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Family plan (2-6 members) — tap SELECTS it.
                        GestureDetector(
                          onTap: selectFamily,
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF252050),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: selectedPlan == 0
                                    ? const Color(0xFF16C79A)
                                    : const Color(0x33FFFFFF),
                                width: 2,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF245C66),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text(
                                        '2-6 MEMBERS',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    const Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Family Plan',
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
                                    // Selected check — in-row when Family chosen.
                                    selectedPlan == 0
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
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Personal — the MOST POPULAR pick: a bright gradient
                        // frame (the always-on "popular" highlight), a ribbon
                        // tab, and the in-row selected check when chosen. Tap
                        // SELECTS it.
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
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFF16C79A),
                                          Color(0xFF1CB0F6),
                                        ],
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
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      12,
                                      16,
                                      16,
                                    ),
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
                                                  fontSize: 20,
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
                                        const Text(
                                          r'$7.99 / MO',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 17,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        // Selected check — in-row when Personal
                                        // chosen.
                                        selectedPlan == 1
                                            ? Container(
                                                width: 26,
                                                height: 26,
                                                decoration: BoxDecoration(
                                                  color:
                                                      const Color(0xFF1CB0F6),
                                                  borderRadius:
                                                      BorderRadius.circular(13),
                                                ),
                                                child: const Icon(
                                                  Icons.check_rounded,
                                                  color: Colors.white,
                                                  size: 18,
                                                ),
                                              )
                                            : const SizedBox(
                                                width: 26,
                                                height: 26,
                                              ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        // "NO FREE TRIAL" group divider.
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                height: 1,
                                color: const Color(0x33FFFFFF),
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Text(
                                'NO FREE TRIAL',
                                style: TextStyle(
                                  color: Color(0xFFB4ADD6),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Container(
                                height: 1,
                                color: const Color(0x33FFFFFF),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Student plan — tap SELECTS it.
                        GestureDetector(
                          onTap: selectStudent,
                          child: Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: const Color(0xFF252050),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: selectedPlan == 2
                                    ? const Color(0xFF16C79A)
                                    : const Color(0x33FFFFFF),
                                width: 2,
                              ),
                            ),
                            child: Row(
                              children: [
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Student Plan',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 20,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        r'12 mo • $47.99',
                                        style: TextStyle(
                                          color: Color(0xFFB4ADD6),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      SizedBox(height: 2),
                                      Text(
                                        'Student status must be verified',
                                        style: TextStyle(
                                          color: Color(0xFF847BB0),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Text(
                                  r'$3.99 / MO',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                // Selected check — in-row when Student chosen.
                                selectedPlan == 2
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
                        ),
                        const SizedBox(height: 12),
                        // Monthly plan — tap SELECTS it.
                        GestureDetector(
                          onTap: selectMonthly,
                          child: Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: const Color(0xFF252050),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: selectedPlan == 3
                                    ? const Color(0xFF16C79A)
                                    : const Color(0x33FFFFFF),
                                width: 2,
                              ),
                            ),
                            child: Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    'Monthly',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const Text(
                                  r'$12.99 / MO',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                // Selected check — in-row when Monthly chosen.
                                selectedPlan == 3
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
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                // Pinned offer zone — the cancel line + the CTA (charges the
                // selected tier's slot).
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
                GestureDetector(
                  onTap: paywallPurchase(
                    slot: selectedPlan == 0
                        ? 'family'
                        : selectedPlan == 1
                            ? 'annual'
                            : selectedPlan == 2
                                ? 'student'
                                : 'monthly',
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
