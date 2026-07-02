import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/user_factories.g.dart';
import 'package:restage_example/widgets/pricing_card.dart';
import 'package:rfw/formats.dart' hide WidgetLibrary;

/// The DECODE-SIDE FAITHFULNESS GOLDEN (the compile+run faithfulness net).
///
/// Exercises the REAL generated factory (`_buildPricingCard` in
/// `user_factories.g.dart`) end to end through the RFW runtime — not a mock:
/// a hand-authored wire blob whose `plan` property is a MAP LITERAL (the wire
/// representation of the customer `Plan` data class — no encode step, which is
/// a separate concern) is rendered, and the reconstructed `PricingCard.plan`
/// is asserted field by field. This catches a compiled-but-unfaithful
/// reconstruction the static admission gate cannot see.
///
/// The single `PricingCard` widget's nested `Plan`/`Price` cover the edge-shape
/// corpus: a nested (two-level) data class, named + mixed +
/// positional constructor args, an optional-nullable field (null on absent), an
/// optional non-nullable field with a default (the default on absent), a
/// required field (fail-closed on absent), and a customer enum field.
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
          body: RestagePaywall(id: 'pricing', resolver: _StaticResolver(bytes)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  PricingCard readCard(WidgetTester tester) =>
      tester.widget<PricingCard>(find.byType(PricingCard));

  testWidgets(
    'a FULL wire map reconstructs every field faithfully (nested, mixed ctor, '
    'enum)',
    (tester) async {
      await pumpBlob(tester, '''
        import restage_example.widgets;
        widget Paywall = PricingCard(plan: {
          name: "Pro plan",
          price: { amount: 1999, currency: "EUR" },
          badge: "Best value",
          tier: "pro",
        });
      ''');

      final plan = readCard(tester).plan;
      expect(plan.name, 'Pro plan');
      expect(plan.price.amount, 1999); // positional Price arg
      expect(plan.price.currency, 'EUR'); // named Price arg (overrides default)
      expect(plan.badge, 'Best value'); // optional-nullable, present
      expect(plan.tier, PlanTier.pro); // customer enum decoded from "pro"
    },
  );

  testWidgets(
    'ABSENT optional keys reconstruct as null / the constructor default (never '
    'fabricated, never crash)',
    (tester) async {
      // `badge`, `currency`, and `tier` are all omitted from the wire map.
      await pumpBlob(tester, '''
        import restage_example.widgets;
        widget Paywall = PricingCard(plan: {
          name: "Basic",
          price: { amount: 0 },
        });
      ''');

      final plan = readCard(tester).plan;
      expect(plan.name, 'Basic');
      expect(plan.price.amount, 0);
      expect(plan.price.currency, 'USD'); // optional non-null → ctor default
      expect(plan.badge, isNull); // optional-nullable → null on absent
      expect(plan.tier, PlanTier.starter); // enum default on absent
    },
  );

  testWidgets(
    'a MISSING REQUIRED field FAILS CLOSED (throws during reconstruction, never '
    'fabricates a partial value)',
    (tester) async {
      // `name` (required) is omitted — the generated factory throws rather than
      // reconstructing a partial `Plan`.
      await pumpBlob(tester, '''
        import restage_example.widgets;
        widget Paywall = PricingCard(plan: {
          price: { amount: 0 },
        });
      ''');

      // The fail-closed reconstruction throws, so NO faithful PricingCard is
      // built (RFW records the build error / renders its fallback in place).
      // Drain the exception so it doesn't auto-fail the test.
      tester.takeException();
      expect(find.byType(PricingCard), findsNothing);
    },
  );

  testWidgets(
    'a MISSING REQUIRED NESTED value (price) also FAILS CLOSED',
    (tester) async {
      await pumpBlob(tester, '''
        import restage_example.widgets;
        widget Paywall = PricingCard(plan: {
          name: "No price",
        });
      ''');

      tester.takeException();
      expect(find.byType(PricingCard), findsNothing);
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
