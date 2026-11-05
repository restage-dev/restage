import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/user_factories.g.dart';
import 'package:restage_example/paywalls/custom_badge.dart';
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
      'the delivered custom_badge renders the split StreakBadge as the app '
      'does', (tester) async {
    // The committed rfwtxt is the canonical codegen output; encode it exactly
    // as the runtime decodes a delivered blob.
    final bytes = Uint8List.fromList(
      encodeLibraryBlob(
        parseLibraryFile(
          readDeliveryText('assets/paywalls/custom_badge.rfwtxt'),
        ),
      ),
    );
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // The app's own paywall, then the delivered design.
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

    final app = await run(const CustomBadgePaywall());
    final failures = <PaywallLoadFailed>[];
    final delivered = await run(RestagePaywall(
      id: 'custom_badge',
      resolver: _StaticResolver(bytes),
      onEvent: (e) {
        if (e is PaywallLoadFailed) failures.add(e);
      },
    ));
    expect(
        failures.map((f) => '${f.errorCode}: ${f.message}').toList(), isEmpty);
    expect(find.text('Streak: 9'), findsOneWidget);
    expect(find.text('Saved: 3'), findsOneWidget);
    expect(delivered, app);
  });
}
