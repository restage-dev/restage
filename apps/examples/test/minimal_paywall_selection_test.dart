import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/paywalls/minimal_paywall.dart'
    show MinimalPaywallSurface;
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

// The selected plan lives in the design: Continue reports the plan the user
// picked, from the delivered design and from the compiled original alike.
void main() {
  setUp(() {
    Restage.debugReset();
    registerRestageWidgets();
  });

  Future<List<String>> pick(WidgetTester tester, VariantResolver resolver,
      {required bool delivered}) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final plans = <String>[];
    final failures = <PaywallLoadFailed>[];
    await tester.pumpWidget(MaterialApp(
      home: MinimalPaywallSurface(
        resolver: resolver,
        onContinue: plans.add,
        onEvent: (e) {
          if (e is PaywallLoadFailed) failures.add(e);
        },
      ),
    ));
    await tester.pumpAndSettle();
    if (delivered) {
      expect(failures.map((f) => f.message), isEmpty);
    } else {
      // No design was delivered, so the mount shows its compiled original.
      expect(tester.takeException(), isStateError);
      expect(failures, isNotEmpty);
    }
    for (final label in ['Monthly', 'Continue', 'Annual', 'Continue']) {
      await tester.tap(find.text(label));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
    return plans;
  }

  testWidgets('the delivered design reports the selected plan', (tester) async {
    final text = readDeliveryText('assets/paywalls/minimal_paywall.rfwtxt');
    expect(text, contains('set state.annualSelected = false'));
    final bytes = Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(text)));
    expect(await pick(tester, _StaticResolver(bytes), delivered: true),
        ['monthly', 'annual']);
  });

  testWidgets('the compiled original reports the selected plan',
      (tester) async {
    expect(await pick(tester, _UnavailableResolver(), delivered: false),
        ['monthly', 'annual']);
  });
}
