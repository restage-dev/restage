import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/user_factories.g.dart';
import 'package:restage_example/paywalls/pricing_showcase.dart';
import 'package:rfw/formats.dart' hide WidgetLibrary;

import '_support/bundled_artifacts.dart';

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

void main() {
  setUp(() {
    Restage.debugReset();
    registerRestageWidgets();
  });

  testWidgets(
      'the delivered pricing_showcase renders the split PricingCard, its '
      'plan forwarded, as the app does', (tester) async {
    final text = readDeliveryText('assets/paywalls/pricing_showcase.rfwtxt');
    expect(
        text,
        contains(
            'widget PricingCard = PricingCard__split(key: args.key, plan: args.plan'));
    final bytes = Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(text)));
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<List<String?>> run(Widget body) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
        home: Scaffold(body: body),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      return [
        for (final element in find.byType(Text).evaluate())
          (element.widget as Text).data ??
              (element.widget as Text).textSpan?.toPlainText(),
      ];
    }

    final app = await run(const PricingShowcase());
    final failures = <PaywallLoadFailed>[];
    final delivered = await run(PricingShowcaseSurface(
      resolver: _StaticResolver(bytes),
      onEvent: (e) {
        if (e is PaywallLoadFailed) failures.add(e);
      },
    ));
    expect(
        failures.map((f) => '${f.errorCode}: ${f.message}').toList(), isEmpty);
    expect(app, contains('Most popular'));
    expect(delivered, app);
  });
}
