import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/paywalls/minimal_paywall.dart';

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
    // Nothing is registered by hand: the mount is the only thing that can put
    // this paywall's widgets in front of the runtime.
    InstalledWidgetLibraries.reset();
    InstalledIconTable.reset();
  });

  tearDown(() {
    InstalledWidgetLibraries.reset();
    InstalledIconTable.reset();
  });

  testWidgets(
      'a generated paywall mount renders the delivered blob in an app that '
      'never registered any widgets', (tester) async {
    final bytes = readDeliveryArtifact('assets/paywalls/minimal_paywall.rfw');
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final failures = <PaywallLoadFailed>[];
    await tester.pumpWidget(
      MaterialApp(
        home: MinimalPaywallSurface(
          resolver: _StaticResolver(bytes),
          onEvent: (event) {
            if (event is PaywallLoadFailed) failures.add(event);
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
    expect(
      failures.map((f) => '${f.errorCode}: ${f.message}').toList(),
      isEmpty,
    );
    // The delivered blob's own widgets are on screen, so the mount installed
    // them: the authored fallback is not what rendered.
    expect(find.byType(MinimalPaywall), findsNothing);
    expect(find.text('Go Pro'), findsOneWidget);
    expect(find.text('Everything, unlocked.'), findsOneWidget);
    expect(find.text(r'$59.99'), findsOneWidget);
  });
}
