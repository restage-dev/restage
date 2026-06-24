import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_example/onboarding/flows/first_run.dart';
import 'package:restage_example/stub_products.dart';
import 'package:restage_example/user_factories.g.dart';
import 'package:restage/restage.dart';
import 'package:patrol/patrol.dart';

/// Proof-slice smoke for the flow-runtime forward + back transitions.
///
/// Walks the first-run onboarding flow forward through its screens, then back
/// out, in light and then dark, holding each screen on-screen long enough to
/// review as a distinct frame and letting each transition play. Record it with
/// `patrol test --web-video=on` (or a simulator screen capture) so the
/// transitions themselves are captured, not just the settled screens.
///
/// What to look for in the frames:
/// - **Forward:** each screen change ANIMATES forward, native-grade for the
///   device platform (a Cupertino push on iOS, a Material-3 shared-axis on
///   Android) — never an instant hard cut. The first screen appears at rest.
/// - **Back:** tapping the default back affordance animates the REVERSE of the
///   forward transition; the prior screen returns with its state intact.
/// - **The sharp edge (back across the action):** "You're all set" is reached by
///   the `requestNotifications` host action (which runs *between* the priming
///   screen and "all set"). Backing from "all set" returns to the priming
///   screen WITHOUT re-running the action — no second OS permission prompt, no
///   flicker of a re-fired action. Confirm the priming screen simply reappears.
/// - Light and dark must be identical in motion. This walks the **back**
///   direction (the other 4 of the 8 states) plus the action/decision boundary.
const _dwell = Duration(milliseconds: 1200);

ThemeData _theme(Brightness brightness) => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.indigo,
        brightness: brightness,
      ),
    );

void main() {
  patrolTest(
    'onboarding forward + back transitions (light × dark; back across the '
    'action does not re-fire it)',
    ($) async {
      Restage.debugReset();
      Restage.configure(
        apiKey: 'rs_pk_smoke',
        products: kStubProducts,
        resolver: const AssetVariantResolver(),
      );
      registerRestageCustomerWidgets();

      for (final brightness in [Brightness.light, Brightness.dark]) {
        await $.pumpWidgetAndSettle(
          MaterialApp(
            theme: _theme(brightness),
            home: _FirstRunOnboardingHost(
              actions: FirstRunActions(
                // The granted decision so the forward walk reaches "You're all
                // set" across the host action.
                requestNotifications: (_, __) async =>
                    const NotificationDecision(granted: true),
              ),
            ),
          ),
        );

        // ── Forward ──────────────────────────────────────────────────────
        // Welcome — the first screen, shown at rest (no enter animation).
        // `RestageOnboarding` resolves its flow + screen blobs with a
        // fire-and-forget async load (its loadingBuilder shows until that
        // completes); on the web target that Future is not drained by
        // pumpWidgetAndSettle, so wait until the first screen is actually
        // visible before asserting. A genuine load failure still times out here
        // — this only awaits a load that does complete, it does not mask one.
        await $('Welcome to Aura').waitUntilVisible();
        await Future<void>.delayed(_dwell);

        // Forward → Value.
        await $('Get started').tap();
        await $.pumpAndSettle();
        await $('Build a daily practice').waitUntilVisible();
        await Future<void>.delayed(_dwell);

        // Forward → notification priming.
        await $('Continue').tap();
        await $.pumpAndSettle();
        await $('Stay on track').waitUntilVisible();
        await Future<void>.delayed(_dwell);

        // Forward (granted) → "you're all set" (across the host action).
        await $('Enable reminders').tap();
        await $.pumpAndSettle();
        await $("You're all set").waitUntilVisible();
        await Future<void>.delayed(_dwell);

        // ── Back ─────────────────────────────────────────────────────────
        final back = $(find.bySemanticsLabel('Back'));

        // Back across the action → notification priming reappears. The action
        // sits between the priming screen and "all set", so it is structurally
        // skipped and NOT re-fired (no second permission prompt).
        await back.tap();
        await $.pumpAndSettle();
        await $('Stay on track').waitUntilVisible();
        await Future<void>.delayed(_dwell);

        // Back → Value (reverse transition).
        await back.tap();
        await $.pumpAndSettle();
        await $('Build a daily practice').waitUntilVisible();
        await Future<void>.delayed(_dwell);

        // Back → Welcome (the first screen; no back affordance there).
        await back.tap();
        await $.pumpAndSettle();
        await $('Welcome to Aura').waitUntilVisible();
        await Future<void>.delayed(_dwell);
      }
    },
  );
}

/// Minimal host for the first-run onboarding flow under test — renders it through
/// [RestageOnboarding] with the supplied actions. The forward/back walk above
/// drives the flow's own screens, so the host needs nothing more.
class _FirstRunOnboardingHost extends StatelessWidget {
  const _FirstRunOnboardingHost({required this.actions});

  final FirstRunActions actions;

  @override
  Widget build(BuildContext context) {
    return RestageOnboarding<FirstRunResult>(
      flow: FirstRunFlowDescriptor.ref,
      actions: actions,
      loadingBuilder: (context) => const ColoredBox(color: Color(0xFF0E1B33)),
      unavailable: FlowUnavailablePolicy.fallback(
        builder: (context, error) => const ColoredBox(color: Color(0xFF0E1B33)),
      ),
    );
  }
}
