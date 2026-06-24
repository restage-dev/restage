import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'welcome.rsscreen.g.dart';

/// First-run onboarding — the welcome screen.
///
/// ## Authoring an onboarding screen
///
/// An onboarding screen is a `StatelessWidget` annotated `@ScreenSource`,
/// authored in the same standard Flutter syntax as a paywall. The build-time
/// codegen lowers it to a render blob and emits a screen descriptor the flow
/// references by name. Each screen declares the events it can fire as static
/// `OnboardingEvent` fields; a button wires one with `onboardingEvent(...)`,
/// which codegen replaces with a flow-event reference (it never runs at
/// runtime). The flow graph (see `lib/onboarding/flows/first_run.dart`) decides
/// where each event leads.
///
/// ## Why the colors are fixed literals, not theme reads
///
/// Unlike the paywalls, this screen uses fixed brand colors rather than
/// `Theme.of(context).colorScheme.<role>`. The onboarding runtime renders the
/// flow on its own surface and does not publish the host app's theme into the
/// render namespace, so a theme read would resolve to nothing once delivered.
/// A first-run flow is also typically a single deliberate brand moment (calm,
/// dark, on-brand) rather than something that adapts to the host theme — so the
/// fixed palette is both the working choice and the design intent. The palette
/// is shared across the four flow screens for a continuous feel and is chosen
/// to lead naturally into the wellness paywall this flow hands off to.
///
/// The full-width CTA uses an `Expanded` child in a `Row` (not
/// `SizedBox(width: double.infinity)`, which does not survive lowering — see
/// the paywall templates).
@ScreenSource(id: 'welcome')
class WelcomeScreen extends StatelessWidget {
  /// Advances to the value screen.
  static const next = OnboardingEvent<void>('next');

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
                      onPressed: onboardingEvent(next),
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
