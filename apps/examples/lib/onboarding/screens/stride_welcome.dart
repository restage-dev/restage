import 'package:flutter/material.dart';
import 'package:restage/restage.dart';

part 'restage.generated/stride_welcome.restage.g.dart';

/// Stride onboarding — the welcome screen.
///
/// A screen is a `StatelessWidget` annotated `@Screen`, authored in the
/// same standard Flutter syntax as any other surface. Build-time codegen lowers
/// it to a render blob and emits a screen descriptor the flow references by
/// name. Each screen declares the events it can fire as static
/// `SurfaceEvent` fields; a button wires one with `surfaceEvent(...)`,
/// which codegen replaces with a flow-event reference (it never runs at
/// runtime). The flow graph (see `lib/onboarding/flows/stride_first_run.dart`)
/// decides where each event leads — and, because that flow is delivered in
/// *general* mode, the graph can be recomposed over the air without an app
/// release, as long as everything it asks the app to *do* — host actions,
/// host-handled custom events — is a capability the app already ships. (Screen
/// content and navigation events ride the payload itself; they are not the
/// release-bound part.) Nothing on this screen changes between the two modes;
/// the delivery contract lives entirely in the flow.
///
/// The colours are fixed brand literals rather than `Theme.of(context)` reads:
/// the flow renders on its own surface and does not publish the host app's
/// theme into the render namespace, and a first-run flow is a single deliberate
/// brand moment. The full-width CTA uses an `Expanded` child in a `Row` (not
/// `SizedBox(width: double.infinity)`, which does not survive lowering).
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
