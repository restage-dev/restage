import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/paywalls/pricing_showcase.dart'
    show PricingShowcaseSurface;
import 'package:restage_example/user_factories.g.dart';
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

class _UnavailableResolver implements VariantResolver {
  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async =>
      throw StateError('No delivered design');
}

// A plain `onTap: onClose` fires the app's own closure from the compiled
// original and from the delivered design alike.
void main() {
  setUp(() {
    Restage.debugReset();
    registerRestageWidgets();
  });

  testWidgets('the compiled original calls onClose', (tester) async {
    var closes = 0;
    final failures = <PaywallLoadFailed>[];
    await tester.pumpWidget(MaterialApp(
      home: PricingShowcaseSurface(
        resolver: _UnavailableResolver(),
        onClose: () => closes++,
        onEvent: (e) {
          if (e is PaywallLoadFailed) failures.add(e);
        },
      ),
    ));
    await tester.pumpAndSettle();
    // No design was delivered, so the mount shows its compiled original.
    expect(tester.takeException(), isStateError);
    expect(failures, isNotEmpty);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(closes, 1);
  });

  testWidgets('the delivered design calls onClose', (tester) async {
    final text = readDeliveryText('assets/paywalls/pricing_showcase.rfwtxt');
    expect(text, contains('nativeEvent'));
    final bytes = Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(text)));
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var closes = 0;
    final failures = <PaywallLoadFailed>[];
    await tester.pumpWidget(MaterialApp(
      home: PricingShowcaseSurface(
        resolver: _StaticResolver(bytes),
        onClose: () => closes++,
        onEvent: (e) {
          if (e is PaywallLoadFailed) failures.add(e);
        },
      ),
    ));
    await tester.pumpAndSettle();
    expect(failures.map((f) => f.message), isEmpty);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(closes, 1);
  });
}
