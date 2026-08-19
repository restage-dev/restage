import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/stride_goals.restage.g.dart';

/// Stride onboarding — the goal-setting screen.
///
/// Added in the flow's second version to sit between the welcome and the
/// reminder prime. It is an ordinary screen; what makes it interesting is that
/// inserting it is a **structural** change to the graph. For a typed flow that
/// would break the delivery contract, but this flow is general-delivery, so the
/// server can add this screen over the air and roll it back without an app
/// release. See `stride_welcome.dart` for the shared screen-authoring notes.
@Screen()
class StrideGoalsScreen extends StatelessWidget {
  /// Leaves the goals screen; the flow graph decides where it leads.
  static const next = SurfaceEvent<void>('next');

  const StrideGoalsScreen({super.key});

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
                        Icons.flag_rounded,
                        size: 44,
                        color: Color(0xFF241024),
                      ),
                    ),
                    const SizedBox(height: 32),
                    const Text(
                      'Set your pace',
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
                      'Start with a few runs a week. You can change it anytime.',
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
                      onPressed: surfaceEvent(next),
                      child: const Text(
                        'Continue',
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
