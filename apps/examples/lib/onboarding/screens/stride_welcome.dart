import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/stride_welcome.restage.g.dart';

/// Stride onboarding: the welcome screen.
///
/// The flow in `lib/onboarding/flows/stride_first_run.dart` uses general
/// delivery, so its graph can change over the air as long as it only uses host
/// actions and custom events the app already ships. This screen is the same in
/// either mode.
///
/// It uses fixed brand colors on purpose, and its full-width button uses `Row`
/// with `Expanded`, because a surface can't carry `double.infinity`.
@Screen()
class StrideWelcomeScreen extends StatelessWidget {
  /// Leaves the welcome screen; the flow graph — recomposable over the air on
  /// a general flow — decides where it leads.
  static const start = SurfaceEvent<void>('start');

  const StrideWelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF241024),
      appBar: AppBar(
        backgroundColor: const Color(0xFF241024),
        elevation: 0,
        foregroundColor: const Color(0xFFFFFFFF),
      ),
      body: SafeArea(
        top: false,
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
                          colors: [Color(0xFFFF6F5B), Color(0xFFFF9E7D)],
                        ),
                      ),
                      child: const Icon(
                        Icons.directions_run_rounded,
                        size: 48,
                        color: Color(0xFF241024),
                      ),
                    ),
                    const SizedBox(height: 32),
                    const Text(
                      'Welcome to Stride',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFFBEFE9),
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Build a running habit that sticks — one short run at a '
                      'time.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: Color(0xFFC6A9BC),
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
                        backgroundColor: const Color(0xFFFF6F5B),
                        foregroundColor: const Color(0xFF241024),
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ),
                      onPressed: surfaceEvent(start),
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
