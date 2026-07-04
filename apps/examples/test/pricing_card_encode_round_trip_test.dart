import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/user_factories.g.dart';
import 'package:restage_example/widgets/pricing_card.dart';

/// The ENCODE-SIDE SOUND NET (source → encode → wire → decode → pixels).
///
/// The `pricing_showcase` paywall AUTHORS `PricingCard(plan: Plan(...))` in
/// ordinary Flutter (`lib/paywalls/pricing_showcase.dart`); build-time codegen
/// ENCODES each `Plan(...)` value into the committed blob as a field-name-keyed
/// map. This test loads the COMMITTED `.rfw` binary — the exact artifact that
/// ships — renders it through the REAL RFW runtime + the generated
/// `PricingCard` factory (not a mock), and asserts each reconstructed `plan`
/// FIELD BY FIELD against the authored source value — so a field/argument
/// transposition cannot hide behind a coincidentally-equal map.
///
/// Together with `pricing_card_decode_golden_test.dart` (which pins the decode
/// half against hand-authored wire maps) this closes the round trip: what the
/// encoder writes is exactly what the decoder faithfully reads.
void main() {
  setUp(() {
    Restage.debugReset();
    registerRestageCustomerWidgets();
  });

  PricingCard cardNamed(WidgetTester tester, String name) =>
      tester.widgetList<PricingCard>(find.byType(PricingCard)).firstWhere(
            (card) => card.plan.name == name,
          );

  testWidgets(
    'the built pricing_showcase blob round-trips every authored Plan field '
    'faithfully through the real generated factory',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bytes =
          File('assets/paywalls/pricing_showcase.rfw').readAsBytesSync();

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: RestagePaywall(
            id: 'pricing_showcase',
            resolver: _StaticResolver(bytes),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PricingCard), findsNWidgets(2));

      // The 'Pro' card — every field set at the source, including a nested
      // Price (positional amount + named currency), an optional badge, and an
      // enum tier.
      final pro = cardNamed(tester, 'Pro').plan;
      expect(pro.name, 'Pro');
      expect(pro.price.amount, 1999); // positional Price arg
      expect(pro.price.currency, 'USD'); // named Price arg
      expect(pro.badge, 'Most popular'); // optional-nullable, present
      expect(pro.tier, PlanTier.pro); // customer enum

      // The 'Starter' card — the optionals the source OMITS reconstruct as the
      // constructor default (currency 'USD', tier starter) or null (badge): the
      // encode omits those keys, and the decoder reads the absent key as the
      // default / null (the omit↔absent symmetry, end to end).
      final starter = cardNamed(tester, 'Starter').plan;
      expect(starter.name, 'Starter');
      expect(starter.price.amount, 999);
      expect(starter.price.currency, 'USD'); // default (currency key omitted)
      expect(starter.badge, isNull); // omitted → null
      expect(starter.tier, PlanTier.starter); // default (tier key omitted)
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
