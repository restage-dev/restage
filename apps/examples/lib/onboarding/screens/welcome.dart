import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/welcome.restage.g.dart';

/// First-run onboarding: the welcome screen.
///
/// Each screen declares its events as static `SurfaceEvent` fields, and a button
/// fires one with `surfaceEvent(...)`. The flow in
/// `lib/onboarding/flows/first_run.dart` decides where each event leads.
///
/// It uses fixed brand colors on purpose: a first-run flow is one calm brand
/// moment, and the palette leads into the paywall the flow hands off to. The
/// full-width button uses `Row` with `Expanded`, because a surface can't carry
/// `double.infinity`.
@Screen()
class WelcomeScreen extends StatelessWidget {
  /// Advances to the value screen.
  static const next = SurfaceEvent<void>('next');

  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E1B33),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
          child: Column(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 96,
                      height: 96,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF6FD6C6), Color(0xFF8FA2F2)],
                        ),
                      ),
                      child: const Icon(
                        Icons.self_improvement_rounded,
                        size: 48,
                        color: Color(0xFF0E1B33),
                      ),
                    ),
                    const SizedBox(height: 32),
                    const Text(
                      'Welcome to Aura',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFF5F7FB),
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'A few quiet minutes a day — meditation, sleep, focus.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: Color(0xFFAEB9D4),
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
                        backgroundColor: const Color(0xFF6FD6C6),
                        foregroundColor: const Color(0xFF0E1B33),
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ),
                      onPressed: surfaceEvent(next),
                      child: const Text(
                        'Get started',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
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
