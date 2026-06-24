import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'crave_ready.rsscreen.g.dart';

/// Permission-priming — the confirmation shown once location is granted.
///
/// The granted path of the gate lands here; [start] completes the flow and the
/// host drops the user into the app.
@ScreenSource(id: 'crave_ready')
class CraveReadyScreen extends StatelessWidget {
  /// Completes the flow and enters the app.
  static const start = OnboardingEvent<void>('start');

  const CraveReadyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
          child: Column(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 132,
                      height: 132,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFFE7F6EC),
                      ),
                      child: const Icon(
                        Icons.check_circle_rounded,
                        size: 72,
                        color: Color(0xFF1FA463),
                      ),
                    ),
                    const SizedBox(height: 34),
                    const Text(
                      'You’re all set',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1F1B16),
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Finding the tastiest spots and fastest delivery '
                      'right around you.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: Color(0xFF8A8580),
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
                        backgroundColor: const Color(0xFFFF5630),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: onboardingEvent(start),
                      child: const Text(
                        'Start browsing',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
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
