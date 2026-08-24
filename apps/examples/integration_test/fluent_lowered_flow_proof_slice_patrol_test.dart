import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:restage/restage.dart';

/// Proof slice for the **screen-navigation lowering** — drives the load-bearing
/// walk of a paywall whose `Navigator.push` to a second `@Paywall` screen
/// is lowered to a bundled flow, and holds each state long enough for the visual
/// gate to capture it as a distinct frame.
///
/// Run on a booted iOS simulator via the mobile `/smoke` gate (`patrol test`).
///
/// What to look for in the frames:
/// - State 1: the dark gradient-hero entry paywall — the glowing hero, the
///   "MOST POPULAR" Personal card, the white "START MY FREE WEEK" CTA, and
///   "VIEW ALL PLANS".
/// - State 2: the pushed "Choose a plan" all-tiers screen (Family / Personal /
///   Student / Monthly) with the authored back chevron at top-start and NO
///   second SDK back chevron (the built-in flow chrome is suppressed for a
///   paywall flow).
/// - State 3: back at the entry after the in-flow back.
///
/// The interactions are asserted by events: a plan on the pushed screen is
/// selected before the CTA reports it, and the entry CTA reports its default.
const _dwell = Duration(milliseconds: 1500);

void main() {
  patrolTest(
    'screen-navigation lowering — entry -> choose a plan -> back -> continue',
    ($) async {
      final events = <RestageEvent>[];
      Restage.debugReset();
      Restage.configure(
        apiKey: 'rs_pk_example',
        resolver: const AssetVariantResolver(),
      );

      await $.pumpWidgetAndSettle(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: RestagePaywall(id: 'fluent_pro', onEvent: events.add),
        ),
      );

      // State 1 — the entry paywall. waitUntilVisible lets the asynchronous
      // bundled-flow load land before asserting: on a real device a bare
      // pumpWidgetAndSettle can return before the asset-bundle load schedules a
      // frame (the same race the widget proof primes with an explicit pump).
      await $('VIEW ALL PLANS').waitUntilVisible();
      await $('START MY FREE WEEK').waitUntilVisible();
      await Future<void>.delayed(_dwell);

      // State 2 — push to the "Choose a plan" all-tiers screen.
      await $('VIEW ALL PLANS').tap();
      await $.pumpAndSettle();
      await $('Choose a plan').waitUntilVisible();
      await $('Family Plan').waitUntilVisible();
      await Future<void>.delayed(_dwell);

      // Tapping a tier selects it without navigating; the pinned CTA then
      // reports the selected tier.
      await $('Family Plan').tap();
      await $.pumpAndSettle();
      expect(
        events.whereType<PaywallCustomEvent>().where(
              (event) => event.eventName == 'continue',
            ),
        isEmpty,
        reason: 'tapping a tier only changes selection',
      );
      await $('Choose a plan').waitUntilVisible(); // did not advance the flow
      await $('START MY FREE WEEK').tap();
      await $.pumpAndSettle();
      expect(
        events.whereType<PaywallCustomEvent>().where(
              (event) =>
                  event.eventName == 'continue' &&
                  event.args['plan'] == 'family',
            ),
        isNotEmpty,
        reason: 'the CTA must report the selected tier',
      );
      await Future<void>.delayed(_dwell);

      // State 3 — in-flow back to the entry via the authored chevron (the sole
      // back affordance; match by codepoint since the lowered IconData drops the
      // directional matchTextDirection flag).
      final backChevron = find.byWidgetPredicate(
        (widget) =>
            widget is Icon &&
            widget.icon?.codePoint == Icons.arrow_back_ios_new.codePoint,
      );
      await $.tester.tap(backChevron);
      await $.pumpAndSettle();
      await $('VIEW ALL PLANS').waitUntilVisible();
      expect($('Choose a plan'), findsNothing);
      await Future<void>.delayed(_dwell);

      // The entry CTA reports its default Personal plan.
      await $('START MY FREE WEEK').tap();
      await $.pumpAndSettle();
      expect(
        events.whereType<PaywallCustomEvent>().where(
              (event) =>
                  event.eventName == 'continue' &&
                  event.args['plan'] == 'personal',
            ),
        isNotEmpty,
        reason: 'the entry CTA must report the default plan',
      );
      await Future<void>.delayed(_dwell);
    },
  );
}
