import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/paywalls/fluent_pro.dart';

/// Locks the Fluent Pro **entry-screen** purchase CTA's slot mapping against
/// regression.
///
/// The entry screen carries two plan cards — Personal (the framed "most
/// popular" default) and Family — and a single "START MY FREE WEEK" CTA that
/// purchases whichever plan is selected. The Family card *displays* the family
/// product, so the CTA must charge the `family` slot when Family is selected;
/// charging any other slot is a display-vs-charge mismatch (the canonical
/// copy-paste billing bug).
///
/// This drives the paywall **locally** (the authored [FluentProPaywall] widget,
/// not the delivered blob) so the assertion pins what the *source* produces:
/// `paywallPurchase(slot:)` fires the `restage.purchase` event with the slot
/// the source selects. Mounting under a [RestagePaywallEventDispatcher] captures
/// the raw `(name, args)` the authoring helper delivers, so the test reads the
/// literal slot directly — no blob regeneration or product/price resolution in
/// the loop.
void main() {
  /// Gives the test a tall canvas so the bounded paywall renders without a
  /// RenderFlex overflow under the wide test font.
  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// Mounts [FluentProPaywall] under a dispatcher that records every fired
  /// `(name, args)` into [events], and returns that list.
  Future<List<({String name, Map<String, Object?> args})>> pumpEntry(
    WidgetTester tester,
  ) async {
    useTallSurface(tester);
    final events = <({String name, Map<String, Object?> args})>[];
    await tester.pumpWidget(
      MaterialApp(
        home: RestagePaywallEventDispatcher(
          onEvent: (name, args) => events.add((name: name, args: args)),
          child: const FluentProPaywall(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return events;
  }

  /// The slot of the most recent `restage.purchase` event, or null.
  String? lastPurchasedSlot(
    List<({String name, Map<String, Object?> args})> events,
  ) {
    final purchases =
        events.where((e) => e.name == RestageEventNames.purchase).toList();
    return purchases.isEmpty ? null : purchases.last.args['slot'] as String?;
  }

  Future<void> tapText(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  /// Taps the plan card carrying [label] (its GestureDetector ancestor).
  Future<void> tapPlanCard(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(
      find.ancestor(
        of: find.text(label),
        matching: find.byType(GestureDetector),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'the entry CTA charges the monthly slot for the default Personal plan',
    (tester) async {
      final events = await pumpEntry(tester);
      // Personal is the pre-selected default — no plan tap needed.
      await tapText(tester, 'START MY FREE WEEK');
      expect(lastPurchasedSlot(events), 'monthly');
    },
  );

  testWidgets(
    'selecting Family re-targets the entry CTA to the family slot '
    '(the displayed product)',
    (tester) async {
      final events = await pumpEntry(tester);
      await tapPlanCard(tester, 'Family');
      await tapText(tester, 'START MY FREE WEEK');
      // The Family card shows the family product; the CTA must charge `family`,
      // never the annual slot (the regression this test guards).
      expect(lastPurchasedSlot(events), 'family');
    },
  );

  testWidgets(
    'selecting Family then Personal re-targets the entry CTA back to monthly',
    (tester) async {
      final events = await pumpEntry(tester);
      await tapPlanCard(tester, 'Family');
      await tapPlanCard(tester, 'Personal');
      await tapText(tester, 'START MY FREE WEEK');
      expect(lastPurchasedSlot(events), 'monthly');
    },
  );
}
