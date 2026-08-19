import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/stride_ready.restage.g.dart';

/// Stride onboarding — the confirmation screen.
///
/// The last screen in the flow. Its [begin] event advances to the flow's end
/// state, which returns the terminal result to the host's `onComplete`. In
/// general mode that result is an untyped `Map` — the host reads the fields it
/// declared in the flow's outbound contract, with no generated result class in
/// between. See `stride_welcome.dart` for the shared screen-authoring notes.
@Screen()
class StrideReadyScreen extends StatelessWidget {
  /// Completes the flow.
  static const begin = SurfaceEvent<void>('begin');

  const StrideReadyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF241024),
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
                          colors: [Color(0xFFFF6F5B), Color(0xFFFF9E7D)],
                        ),
                      ),
                      child: const Icon(
                        Icons.check_circle_rounded,
                        size: 48,
                        color: Color(0xFF241024),
                      ),
                    ),
                    const SizedBox(height: 32),
                    const Text(
                      'You\'re all set',
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
                      'Lace up — your first run is waiting.',
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
                      onPressed: surfaceEvent(begin),
                      child: const Text(
                        'Start running',
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
