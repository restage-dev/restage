import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

import 'fixtures/compiled_surfaces/native_flow.dart';

final class _FailingVariantResolver implements VariantResolver {
  @override
  Future<ResolvedVariant> resolve(String id,
          {String? placementId, Locale? locale}) =>
      Future<ResolvedVariant>.error(const RestagePaywallError(
        code: RestageErrorCodes.deliveryUnavailable,
        message: 'Delivery failed.',
      ));
}

final class _FailingFlowResolver implements FlowResolver {
  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> flow) =>
      Future<ResolvedFlow>.error(FlowUnavailableError(
        flowId: flow.id,
        flowVersion: flow.version,
        reason: 'delivery_unavailable',
        message: 'Delivery failed.',
      ));
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  setUp(Restage.debugReset);

  for (final failing in [false, true]) {
    final label = failing ? 'a failing resolver' : 'no configuration';

    testWidgets('generated paywall original fires custom events with $label',
        (tester) async {
      final events = <RestageEvent>[];
      await tester.pumpWidget(MaterialApp(
          home: NativeOfferSurface(
        resolver: failing ? _FailingVariantResolver() : null,
        onEvent: events.add,
      )));
      await _settle(tester);
      await tester.tap(find.text('Offer original'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      final custom = events.whereType<PaywallCustomEvent>().toList();
      expect(custom, hasLength(1));
      expect(custom.single.eventName, 'skip');
      expect(custom.single.args, isEmpty);
      expect(custom.single.paywallId, 'native_offer');
    });

    testWidgets('generated flow originals complete with $label',
        (tester) async {
      NativeClassResult? result;
      await tester.pumpWidget(MaterialApp(
          home: NativeClassFlowSurface(
        resolver: failing ? _FailingFlowResolver() : null,
        onComplete: (r) => result = r,
      )));
      await _settle(tester);
      await tester.tap(find.text('Preferences original'));
      await _settle(tester);
      await tester.pumpWidget(const SizedBox());
      expect(result, isA<NativeClassResult>());
    });
  }
}
