import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_example/onboarding/chrome_ladder_demo.dart';
import 'package:restage_example/stub_products.dart';
import 'package:restage_example/user_factories.g.dart';
import 'package:restage/restage.dart';
import 'package:patrol/patrol.dart';

/// Proof-slice smoke for the chrome customization ladder.
///
/// Walks one flow forward to where the back affordance is shown, switches
/// through each ladder rung so the back affordance visibly changes, and
/// advances a screen under the persistent chrome so its framing is captured.
/// Light and dark are **separate tests** (each gets a fresh binding) — pumping
/// the same widget structure twice in one test reuses the demo's State (Flutter
/// element reuse), which would leave the flow where the first walk ended rather
/// than re-loading the first screen. Record with `patrol test --web-video=on`.
///
/// What to look for in the frames:
/// - **Theme** — the back arrow changes to a *different icon*, in a brand color,
///   visibly larger.
/// - **Slots** — the chevron is replaced by a custom labelled "‹ Back" control.
/// - **Layout** — the back control moves to the top-**right**.
/// - **Persistent** — the chrome stays put (frames the flow) while the screen
///   transitions beneath it; toggling switches it to ride inside each screen.
const _dwell = Duration(milliseconds: 1200);

ThemeData _theme(Brightness brightness) => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.indigo,
        brightness: brightness,
      ),
    );

Future<void> _walkLadder(
  PatrolIntegrationTester $,
  Brightness brightness,
) async {
  Restage.debugReset();
  Restage.configure(
    apiKey: 'rs_pk_smoke',
    products: kStubProducts,
    resolver: const AssetVariantResolver(),
  );
  registerRestageCustomerWidgets();

  await $.pumpWidgetAndSettle(
    MaterialApp(
      theme: _theme(brightness),
      home: const ChromeLadderDemo(initialRung: ChromeRung.defaultChrome),
    ),
  );

  // The flow loads asynchronously (its loadingBuilder shows until then); wait
  // for the first screen, then advance so the flow has history and the back
  // affordance is shown.
  await $('Welcome to Aura').waitUntilVisible();
  await Future<void>.delayed(_dwell);
  await $('Get started').tap();
  await $.pumpAndSettle();
  await $('Build a daily practice').waitUntilVisible();
  await Future<void>.delayed(_dwell);

  // Theme — the back arrow becomes a distinct icon, color, and size.
  await $('Theme').tap();
  await $.pumpAndSettle();
  await $(find.byIcon(kChromeLadderThemeIcon)).waitUntilVisible();
  await Future<void>.delayed(_dwell);

  // Slots — a custom labelled back control replaces the chevron.
  await $('Slots').tap();
  await $.pumpAndSettle();
  await $(find.byKey(const Key('chrome-ladder-slots-back'))).waitUntilVisible();
  await Future<void>.delayed(_dwell);

  // Layout — the back control moves to the top-right.
  await $('Layout').tap();
  await $.pumpAndSettle();
  await $(find.byKey(const Key('chrome-ladder-layout-back')))
      .waitUntilVisible();
  await Future<void>.delayed(_dwell);

  // Persistent — back to the built-in chrome, then advance a screen so the
  // persistent chrome's stable framing is captured during the transition;
  // then toggle it to per-screen so the difference is observable.
  await $('Default').tap();
  await $.pumpAndSettle();
  await $('Continue').tap();
  await $.pumpAndSettle();
  await $('Stay on track').waitUntilVisible();
  await Future<void>.delayed(_dwell);
  await $(find.byType(Switch)).tap();
  await $.pumpAndSettle();
  await Future<void>.delayed(_dwell);
}

void main() {
  patrolTest(
    'chrome customization ladder — each rung over a flow (light)',
    ($) => _walkLadder($, Brightness.light),
  );

  patrolTest(
    'chrome customization ladder — each rung over a flow (dark)',
    ($) => _walkLadder($, Brightness.dark),
  );
}
