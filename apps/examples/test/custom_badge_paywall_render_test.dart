import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/user_factories.g.dart';
import 'package:restage_example/widgets/streak_badge.dart';
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
      ResolvedVariant(bytes: bytes, paywallId: id);
}

void main() {
  setUp(() {
    Restage.debugReset();
    registerRestageCustomerWidgets();
  });

  testWidgets(
      'the codegen-generated custom_badge blob references StreakBadge and the '
      'runtime resolves + renders it (codegen -> runtime, end to end)',
      (tester) async {
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

    final failures = <PaywallLoadFailed>[];
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: Scaffold(
        body: RestagePaywall(
          id: 'custom_badge',
          resolver: _StaticResolver(bytes),
          onEvent: (e) {
            if (e is PaywallLoadFailed) failures.add(e);
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(
        failures.map((f) => '${f.errorCode}: ${f.message}').toList(), isEmpty);
    // The real StreakBadge widget mounts (resolved via the registered factory)
    // — proving it was REFERENCED, not inlined, and the reference resolves.
    expect(find.byType(StreakBadge), findsNWidgets(2));
    expect(find.text('Streak: 9'), findsOneWidget);
    expect(find.text('Saved: 3'), findsOneWidget);
  });
}
