import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/user_factories.g.dart';
import 'package:restage_example/widgets/pricing_card.dart' show PlanTier;
import 'package:restage_example/widgets/pricing_table.dart';
import 'package:rfw/formats.dart' hide WidgetLibrary;

/// The LIST-of-objects DECODE-SIDE FAITHFULNESS GOLDEN (the compile+run net).
///
/// Exercises the REAL generated factory for [PricingTable] end to end through
/// the RFW runtime — not a mock: a hand-authored wire blob whose `plans`
/// property is a LIST of per-item field-name-keyed maps (the wire
/// representation of a `List<Plan>` — no encode step, a separate concern) is
/// rendered, and the reconstructed `PricingTable.plans` is asserted
/// element by element and field by field, plus the list CONTAINER contract (an
/// absent required list fails closed; a non-map element fails closed — never a
/// silently rendered, wrongly-empty list).
void main() {
  setUp(() {
    Restage.debugReset();
    registerRestageCustomerWidgets();
  });

  Future<void> pumpBlob(WidgetTester tester, String blob) async {
    final bytes = Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(blob)));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RestagePaywall(id: 'table', resolver: _StaticResolver(bytes)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  PricingTable readTable(WidgetTester tester) =>
      tester.widget<PricingTable>(find.byType(PricingTable));

  // The failing reconstruction throws during the build; drain it and confirm the
  // widget did not render — fail-closed, never a silently wrong / empty list.
  // (The build error's exact type is pinned at the codec/emitter level; asserting
  // it here trips flutter_test's multi-frame FlutterError handling.)
  void expectFailClosed(WidgetTester tester) {
    tester.takeException();
    expect(find.byType(PricingTable), findsNothing);
  }

  testWidgets(
    'a LIST of object maps reconstructs element-by-element, in order',
    (tester) async {
      await pumpBlob(tester, '''
        import restage_example.widgets;
        widget Paywall = PricingTable(plans: [
          { name: "Pro", price: { amount: 1999, currency: "EUR" }, tier: "pro" },
          { name: "Starter", price: { amount: 0 } },
        ]);
      ''');

      final plans = readTable(tester).plans;
      expect(plans.length, 2);
      // Element 0 — full fields.
      expect(plans[0].name, 'Pro');
      expect(plans[0].price.amount, 1999); // positional Price arg
      expect(plans[0].price.currency, 'EUR'); // named Price arg
      expect(plans[0].tier, PlanTier.pro); // customer enum from "pro"
      expect(plans[0].badge, isNull); // optional-nullable, absent
      // Element 1 — optional-omitted fields fall to the item ctor defaults.
      expect(plans[1].name, 'Starter');
      expect(plans[1].price.amount, 0);
      expect(plans[1].price.currency, 'USD'); // Price.currency default
      expect(plans[1].badge, isNull);
      expect(plans[1].tier, PlanTier.starter); // Plan.tier default
    },
  );

  testWidgets('an EMPTY list reconstructs as an empty list', (tester) async {
    await pumpBlob(tester, '''
      import restage_example.widgets;
      widget Paywall = PricingTable(plans: []);
    ''');

    expect(readTable(tester).plans, isEmpty);
  });

  testWidgets(
    'a NON-MAP list element FAILS CLOSED (no partial list, never fabricated)',
    (tester) async {
      // The second element is a scalar, not a map — the reconstruction fails
      // closed rather than emitting a one-element (partial) list.
      await pumpBlob(tester, '''
        import restage_example.widgets;
        widget Paywall = PricingTable(plans: [
          { name: "Pro", price: { amount: 1 } },
          42,
        ]);
      ''');

      expectFailClosed(tester);
    },
  );

  testWidgets(
    'a REQUIRED list absent from the wire FAILS CLOSED (never a silently-empty '
    'list)',
    (tester) async {
      // `plans` (required) is omitted — the generated factory must throw rather
      // than reconstruct an empty list for a required list property.
      await pumpBlob(tester, '''
        import restage_example.widgets;
        widget Paywall = PricingTable();
      ''');

      expectFailClosed(tester);
    },
  );
}

class _StaticResolver implements VariantResolver {
  _StaticResolver(this.bytes);

  final Uint8List bytes;

  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async =>
      ResolvedVariant(bytes: bytes, paywallId: id);
}
