import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/user_factories.g.dart';
import 'package:restage_example/widgets/pricing_card.dart';
import 'package:restage_example/widgets/pricing_table.dart';

/// The LIST ENCODE-SIDE SOUND NET (source → encode → wire → decode → pixels).
///
/// The `pricing_table_showcase` paywall AUTHORS
/// `PricingTable(plans: [Plan(...), Plan(...)])` in ordinary Flutter
/// (`lib/paywalls/pricing_table_showcase.dart`); build-time codegen ENCODES the
/// whole `List<Plan>` into the committed blob as a list of field-name-keyed
/// maps. This test loads the COMMITTED `.rfw` binary — the exact artifact that
/// ships — renders it through the REAL RFW runtime + the generated
/// `PricingTable` factory (not a mock), and asserts each reconstructed plan
/// ELEMENT BY ELEMENT and FIELD BY FIELD against the authored source list — so
/// an element/field/argument transposition cannot hide behind a
/// coincidentally-equal list.
///
/// Together with `pricing_table_decode_golden_test.dart` (which pins the decode
/// half against a hand-authored wire list) this closes the round trip for a
/// list-of-data-class property: what the encoder writes, in order, is exactly
/// what the decoder faithfully reads.
void main() {
  setUp(() {
    Restage.debugReset();
    registerRestageCustomerWidgets();
  });

  List<Plan> renderedPlans(WidgetTester tester) =>
      tester.widget<PricingTable>(find.byType(PricingTable)).plans;

  testWidgets(
    'the built pricing_table_showcase blob round-trips every authored plan, in '
    'order, through the real generated factory',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final bytes =
          File('assets/paywalls/pricing_table_showcase.rfw').readAsBytesSync();

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: RestagePaywall(
            id: 'pricing_table_showcase',
            resolver: _StaticResolver(bytes),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final plans = renderedPlans(tester);
      expect(plans, hasLength(2));

      // Element 0 — the 'Pro' plan: every field set at the source, including a
      // nested Price (positional amount + named currency), an optional badge,
      // and an enum tier.
      expect(plans[0].name, 'Pro');
      expect(plans[0].price.amount, 1999); // positional Price arg
      expect(plans[0].price.currency, 'USD'); // named Price arg
      expect(plans[0].badge, 'Most popular'); // optional-nullable, present
      expect(plans[0].tier, PlanTier.pro); // customer enum

      // Element 1 — the 'Starter' plan: the optionals the source OMITS
      // reconstruct as the constructor default (currency 'USD', tier starter)
      // or null (badge) — the omit↔absent symmetry, per element, end to end.
      expect(plans[1].name, 'Starter');
      expect(plans[1].price.amount, 999);
      expect(plans[1].price.currency, 'USD'); // default (currency key omitted)
      expect(plans[1].badge, isNull); // omitted → null
      expect(plans[1].tier, PlanTier.starter); // default (tier key omitted)
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
