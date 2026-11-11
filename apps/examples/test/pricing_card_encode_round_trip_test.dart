import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/user_factories.g.dart';
import 'package:restage_example/paywalls/pricing_showcase.dart';

import '_support/bundled_artifacts.dart';

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
    registerRestageWidgets();
  });

  List<String?> texts(WidgetTester tester) => [
        for (final element in find.byType(Text).evaluate())
          (element.widget as Text).data,
      ];

  testWidgets(
    'the built pricing_showcase blob round-trips every authored Plan field '
    'faithfully through the real generated factory',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      Future<List<String?>> render(Widget home) async {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          MaterialApp(theme: ThemeData(useMaterial3: true), home: home),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        return texts(tester);
      }

      final app = await render(const PricingShowcase());
      final bytes =
          readDeliveryArtifact('assets/paywalls/pricing_showcase.rfw');
      final delivered = await render(
        PricingShowcaseSurface(resolver: _StaticResolver(bytes)),
      );

      // The 'Pro' card sets every field, including a nested Price
      // (positional amount + named currency), an optional badge and an enum
      // tier. The 'Starter' card omits the optionals, which reconstruct as
      // the constructor default (currency 'USD', tier starter) or null
      // (no badge line).
      expect(delivered, [
        'Choose your plan',
        'Most popular',
        'Pro',
        'USD 19.99',
        'pro',
        'Starter',
        'USD 9.99',
        'starter',
        'Continue',
      ]);
      expect(delivered, app);
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
      ResolvedVariant(bytes: bytes, surfaceVersion: 'test', paywallId: id);
}
