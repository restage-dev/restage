import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'reel_kept.rsscreen.g.dart';

/// Survey — the retained confirmation (the redeemed path of the save-offer).
///
/// The gate advances here only when the retention offer was redeemed; [finish]
/// completes the flow with a `retained` outcome the host collects.
@ScreenSource(id: 'reel_kept')
class ReelKeptScreen extends StatelessWidget {
  /// Completes the flow (the user kept their membership).
  static const finish = OnboardingEvent<void>('finish');

  const ReelKeptScreen({super.key});

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
                      width: 120,
                      height: 120,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF1F1F1F),
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        size: 64,
                        color: Color(0xFF8B5CF6),
                      ),
                    ),
                    const SizedBox(height: 30),
                    const Text(
                      'Your discount is applied',
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
                      'You’re saving 50% for the next 3 months. Enjoy the show.',
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
                onPressed: onboardingEvent(finish),
                child: const Text(
                  'Continue watching',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
