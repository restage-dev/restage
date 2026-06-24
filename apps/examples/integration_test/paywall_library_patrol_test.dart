import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/stub_products.dart';
import 'package:restage_example/user_factories.g.dart';

/// Proof-slice integration test for the recreated-paywall library's interactive
/// surfaces. Drives each new paywall's *delivered render blob* through its
/// selection states and asserts the consequence (the CTA re-targets the
/// selected product) — the L9 lesson: a rendered-but-dead control passes a
/// render-only test, so we drive the tap and assert what it does, not just that
/// it draws.
///
/// Harness: this runs on **web-chrome**, the only Patrol target `apps/examples`
/// configures (its pubspec `patrol:` block omits iOS/Android/macOS by design —
/// it is a web demo app with no Xcode `PatrolTests` target). A `patrol test` on
/// the iOS simulator therefore fails with `xcodebuild exited 70` (no iOS runner)
/// — that is a missing-harness condition, not a paywall/test bug, and wiring an
/// iOS runner onto a web demo app is out of scope. Run the autonomous gate on
/// chrome; the founder iOS-device pass covers native / SF-Pro fit separately.
///
/// Run for the visual gate with a recorded capture that holds each state long
/// enough to review as a distinct frame:
///
/// ```sh
/// patrol test --device chrome --web-video=on \
///   integration_test/paywall_library_patrol_test.dart
/// ```
///
/// Each `_dwell` parks a state on screen for the frame extractor. What to look
/// for in the frames: pulse_premium's tier strip highlight moves across
/// Basic / Premium / Premium+ and its plan border moves monthly ↔ annual; the
/// Ascend trial paywall walks trial-timeline (footer, no scrim) → tap the footer
/// → the modal plan sheet rises over the scrim, collapsed on the default plan →
/// "See All Plans" swaps the sheet content to the plan list → the Monthly
/// selection and purchase.
const _dwell = Duration(milliseconds: 1200);

ThemeData _theme(Brightness brightness) => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.indigo,
        brightness: brightness,
      ),
    );

/// Delivered-blob render of [id] (live stub prices), loaded from the bundled
/// asset via the default resolver.
Widget _delivered(
  String id,
  Brightness brightness,
  void Function(RestageEvent) onEvent,
) =>
    MaterialApp(
      theme: _theme(brightness),
      home: Scaffold(
        body: RestagePaywall(
          id: id,
          priceQueries: kStubPriceQueries,
          onEvent: onEvent,
        ),
      ),
    );

/// The product id of the most recent purchase fired, or null.
String? _lastPurchased(List<RestageEvent> events) {
  final ids =
      events.whereType<PurchaseInitiated>().map((e) => e.productId).toList();
  return ids.isEmpty ? null : ids.last;
}

void main() {
  patrolTest(
    'recreated paywall library — interactive states (drive + assert)',
    ($) async {
      Restage.debugReset();
      Restage.configure(
        apiKey: 'rs_pk_smoke',
        products: kStubProducts,
        resolver: const AssetVariantResolver(),
      );
      registerRestageCustomerWidgets();

      // ---- pulse_premium: dark, tri-state tier strip + monthly/annual plan ----
      final pulse = <RestageEvent>[];
      await $.pumpWidgetAndSettle(
        _delivered('pulse_premium', Brightness.dark, pulse.add),
      );
      await $('Pulse').waitUntilVisible();
      await Future<void>.delayed(_dwell); // initial: Premium tier, monthly plan

      // Tier strip — drive the two unambiguous endpoints (the highlight moves).
      await $('Premium+').tap();
      await $.pumpAndSettle();
      await Future<void>.delayed(_dwell);
      await $('Basic').tap();
      await $.pumpAndSettle();
      await Future<void>.delayed(_dwell);

      // Plan — select annual, then fire the CTA: it must buy the annual product.
      await $('Annual').tap();
      await $.pumpAndSettle();
      await Future<void>.delayed(_dwell);
      await $('Subscribe & pay').tap();
      await $.pumpAndSettle();
      expect(_lastPurchased(pulse), 'com.restage.pro.annual');

      // ---- Ascend trial paywall: light, trial-timeline → rising plan sheet ----
      // The delivered blob: a single screen whose footer opens a real modal
      // sheet (the lowered showModalBottomSheet → RestageModalSheet).
      final ascend = <RestageEvent>[];
      await $.pumpWidgetAndSettle(
        _delivered('ascend_premium', Brightness.light, ascend.add),
      );
      // State 1 — the trial timeline, footer pinned, no scrim.
      await $("Try the very best of Ascend. First month's on us.")
          .waitUntilVisible();
      await Future<void>.delayed(_dwell);

      // State 2 — tap the footer "Start free trial": the modal sheet rises over
      // the scrim, collapsed on the default (Annual) plan. Sheet closed, so the
      // footer is the only "Start free trial" on screen.
      await $('Start free trial').tap();
      await $.pumpAndSettle();
      await $('Free 30-Day Trial').waitUntilVisible();
      await Future<void>.delayed(_dwell);

      // State 3 — See All Plans swaps the sheet content to the full plan list.
      await $('See All Plans').tap();
      await $.pumpAndSettle();
      await Future<void>.delayed(_dwell);

      // Plan — select monthly, then fire the sheet CTA: it must buy the monthly
      // SKU. The sheet is open, so scope the CTA to the BottomSheet to pick the
      // sheet's "Start free trial" over the footer's behind the scrim.
      await $('Monthly').tap();
      await $.pumpAndSettle();
      await Future<void>.delayed(_dwell);
      await $(BottomSheet).$('Start free trial').tap();
      await $.pumpAndSettle();
      expect(_lastPurchased(ascend), 'com.restage.pro.monthly');
    },
  );
}
