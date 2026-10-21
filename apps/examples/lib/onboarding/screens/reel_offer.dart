import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:restage/restage.dart';

part 'restage.generated/reel_offer.restage.g.dart';

/// Survey: the save offer.
///
/// [keep] runs the `redeemOffer` host action. Your app applies the discount, and
/// the flow moves to the confirmation only when the redemption succeeds. [cancel]
/// is a custom event your app handles by confirming the cancellation.
@Screen()
class ReelOfferScreen extends StatelessWidget {
  /// Redeems the retention offer via the host action, then advances on success.
  static const keep = SurfaceEvent<void>('keep');

  /// Declines the offer; the host confirms the cancellation.
  static const cancel = SurfaceEvent<void>('cancel');

  const ReelOfferScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF141414),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        top: false,
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
                onPressed: surfaceEvent(keep),
                child: const Text(
                  'Keep my discount',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: surfaceEvent(cancel),
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
