import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/lumen_trial_ending.restage.g.dart';

/// Message — the last nudge before a meditation trial ends, in the app's calm
/// palette.
///
/// The primary action opens the subscription offer; "Maybe later" closes the
/// message.
@Screen(id: 'lumen_trial_ending', surface: Surface.message)
class LumenTrialEndingScreen extends StatelessWidget {
  /// Opens the subscription offer.
  static const openOffer = SurfaceEvent<void>('open_offer');

  /// Dismisses the message. The host decides what dismissal means.
  static const later = SurfaceEvent<void>('later');

  const LumenTrialEndingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F5FB),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 108,
                      height: 108,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF8B7BE0), Color(0xFFB6A8F0)],
                        ),
                      ),
                      child: const Icon(
                        Icons.nightlight_round,
                        size: 52,
                        color: Color(0xFFFFFFFF),
                      ),
                    ),
                    const SizedBox(height: 30),
                    const Text(
                      'YOUR TRIAL ENDS TOMORROW',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF6A55C4),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.8,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Keep your evenings quiet',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF2A2833),
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Twelve new sleep soundscapes just landed. Keep them, '
                      'and the whole library, with Lumen Plus.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF847F92),
                        fontSize: 16,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF7C6CD6),
                        foregroundColor: const Color(0xFFFFFFFF),
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      onPressed: surfaceEvent(openOffer),
                      child: const Text(
                        'Continue with Lumen Plus',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: surfaceEvent(later),
                child: const Text(
                  'Maybe later',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF847F92),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
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
