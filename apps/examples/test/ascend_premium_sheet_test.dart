import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/paywalls/ascend_premium.dart'
    show AscendPremiumPaywallSurface;
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

// The sheet the paywall opens calls the app's callbacks: its plan toggles and
// its continue button work from the delivered design and the compiled original.
void main() {
  setUp(() {
    Restage.debugReset();
    registerRestageWidgets();
  });

  Future<void> tapInSheet(WidgetTester tester, String label) async {
    final target = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.text(label),
    );
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Future<List<String>> pick(WidgetTester tester, VariantResolver resolver,
      {required bool delivered}) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final plans = <String>[];
    final failures = <PaywallLoadFailed>[];
    await tester.pumpWidget(MaterialApp(
      home: AscendPremiumPaywallSurface(
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
    expect(find.byType(BottomSheet), findsNothing);
    await tester.tap(find.text('Start free trial'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Monthly'), findsNothing);
    await tapInSheet(tester, 'Start free trial');
    await tapInSheet(tester, 'See All Plans');
    if (!delivered) {
      // Flutter builds a sheet's content once, so the app's own copy keeps
      // the summary after the State changes.
      expect(find.text('See All Plans'), findsOneWidget);
      return plans;
    }
    expect(find.text('See All Plans'), findsNothing);
    await tapInSheet(tester, 'Monthly');
    await tapInSheet(tester, 'Start free trial');
    await tapInSheet(tester, 'Annual');
    await tapInSheet(tester, 'Start free trial');
    return plans;
  }

  testWidgets('the delivered sheet reports the selected plan', (tester) async {
    final text = readDeliveryText('assets/paywalls/ascend_premium.rfwtxt');
    expect(text, contains('set state.plansExpanded = true'));
    expect(text, contains('set state.annualSelected = false'));
    expect(
      text,
      contains('c1: switch state.annualSelected '
          '{ true: "annual", false: "monthly" }'),
    );
    final bytes = Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(text)));
    expect(await pick(tester, _StaticResolver(bytes), delivered: true),
        ['annual', 'monthly', 'annual']);
  });

  // As in Flutter, a sheet route's content is built once, so the paywall's
  // setState doesn't rebuild it and only the default plan is reported.
  testWidgets(
      'the compiled original follows Flutter: the sheet route is built once '
      "and doesn't rebuild on the paywall's setState", (tester) async {
    expect(await pick(tester, _UnavailableResolver(), delivered: false),
        ['annual']);
  });
}
