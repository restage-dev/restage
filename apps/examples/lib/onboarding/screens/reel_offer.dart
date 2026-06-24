import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'reel_offer.rsscreen.g.dart';

/// Survey — the save-offer (the retention host-action gate).
///
/// [keep] is routed through a host action (`redeemOffer`): the host applies the
/// retention discount and reports back, and the flow advances to the confirmation
/// **only when the redemption succeeds**. This is the one conditional branch the
/// flow runtime offers (advance-or-stay). [cancel] is a host-handled custom
/// event (not a graph transition): the host confirms the cancellation. The
/// decline is host-owned, not a second graph transition — a retention save-offer
/// retains (a discount redemption), it does not re-sell.
@ScreenSource(id: 'reel_offer')
class ReelOfferScreen extends StatelessWidget {
  /// Redeems the retention offer via the host action, then advances on success.
  static const keep = OnboardingEvent<void>('keep');

  /// Declines the offer; the host confirms the cancellation.
  static const cancel = OnboardingEvent<void>('cancel');

  const ReelOfferScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF141414),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8B5CF6),
                        borderRadius: BorderRadius.circular(40),
                      ),
                      child: const Text(
                        '50% OFF',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                    const Text(
                      'Wait — stay for half price',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Keep watching for 3 months at 50% off. Same plan, same '
                      'profiles — cancel anytime.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: Color(0xFF9A9A9A),
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: onboardingEvent(keep),
                child: const Text(
                  'Keep my discount',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: onboardingEvent(cancel),
                child: const Text(
                  'No thanks, cancel my membership',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF9A9A9A),
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
