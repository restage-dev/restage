import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'crave_location.rsscreen.g.dart';

/// Permission-priming — the location pre-permission primer (the host-action
/// gate).
///
/// A food-delivery app earns the OS location grant with a value-first primer
/// shown *before* the system dialog, so a decline there is never terminal. The
/// screen offers two honest choices:
///
/// - **Use current location** fires [allow], routed through the host action
///   `requestLocation`: the host shows the OS dialog and reports back, and the
///   flow advances to the confirmation **only on a granted result**. A decline
///   leaves the user here — the choice below is always available.
/// - **Not now** fires [skip], a host-handled custom event (not a graph
///   transition): the host carries the user into the app without the grant.
@ScreenSource(id: 'crave_location')
class CraveLocationScreen extends StatelessWidget {
  /// Requests the OS location permission via the host action, then advances on
  /// a granted result.
  static const allow = OnboardingEvent<void>('allow');

  /// Skips the permission; the host carries on without it.
  static const skip = OnboardingEvent<void>('skip');

  const CraveLocationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 20, 28, 24),
          child: Column(
            children: [
              Row(
                children: [
                  const Text(
                    'Crave',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFFF5630),
                      letterSpacing: -0.5,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: onboardingEvent(skip),
                    child: const Text(
                      'Not now',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF8A8580),
                      ),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 132,
                      height: 132,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFFFFE9E3),
                      ),
                      child: const Icon(
                        Icons.near_me_rounded,
                        size: 64,
                        color: Color(0xFFFF5630),
                      ),
                    ),
                    const SizedBox(height: 34),
                    const Text(
                      'Restaurants right around you',
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
                      'Share your location and we’ll show what’s open nearby '
                      'and deliver to the right place.',
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
                      onPressed: onboardingEvent(allow),
                      child: const Text(
                        'Use current location',
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
