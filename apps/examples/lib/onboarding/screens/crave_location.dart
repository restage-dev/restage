import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:restage/restage.dart';

part 'restage.generated/crave_location.restage.g.dart';

/// A location permission primer, shown before the system dialog so a decline
/// isn't a dead end.
///
/// - **Use current location** fires [allow], routed through the `requestLocation`
///   host action. The flow moves on only when permission is granted; a decline
///   leaves the user here.
/// - **Not now** fires [skip], a custom event your app handles by continuing
///   without the permission.
@Screen()
class CraveLocationScreen extends StatelessWidget {
  /// Requests the OS location permission via the host action, then advances on
  /// a granted result.
  static const allow = SurfaceEvent<void>('allow');

  /// Skips the permission; the host carries on without it.
  static const skip = SurfaceEvent<void>('skip');

  const CraveLocationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        elevation: 0,
        foregroundColor: const Color(0xFFFF5630),
        centerTitle: false,
        titleSpacing: 28,
        title: const Text(
          'Crave',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Color(0xFFFF5630),
            letterSpacing: -0.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: surfaceEvent(skip),
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
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
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
                      onPressed: surfaceEvent(allow),
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
