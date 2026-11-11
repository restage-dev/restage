import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:restage_example/paywalls/fluent_pro.dart'
    show FluentProPaywallSurface;
import 'package:restage_example/paywalls/lumen_plus_offer.dart'
    show LumenPlusOfferPaywallSurface;
import 'package:restage_example/user_factories.g.dart';
import 'package:restage_shared/restage_shared.dart';

class _UnavailableResolver implements VariantResolver {
  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async =>
      throw StateError('No delivered design');
}

// A paywall whose design lowers a pushed screen: the app's own copy delivers
// the pushed screen's events to the paywall, and the delivered design is the
// same bytes as before its mount recorded the build.
final _paywalls = <({
  String id,
  Widget Function(ValueChanged<RestageEvent> onEvent) mount,
  String push,
  String cta,
  Map<String, Object?> args,
  // The bundle's SHA-256 before its generated mount recorded the build.
  String bundle,
})>[
  (
    id: 'fluent_pro',
    mount: (onEvent) => FluentProPaywallSurface(
          resolver: _UnavailableResolver(),
          onEvent: onEvent,
        ),
    push: 'VIEW ALL PLANS',
    cta: 'START MY FREE WEEK',
    args: {'plan': 'personal'},
    bundle: 'sha256:'
        '3294396faf50131ea51cecd0c28f4ea493342354f261648c31ce6dde66ca365a',
  ),
  (
    id: 'lumen_plus_offer',
    mount: (onEvent) => LumenPlusOfferPaywallSurface(
          resolver: _UnavailableResolver(),
          onEvent: onEvent,
        ),
    push: 'Continue',
    cta: 'Start 14 days free',
    args: {'plan': 'annual'},
    bundle: 'sha256:'
        'f211fabd688364e694fae70a4b40b30ec708c1691e57a828a2ef139abd08f10e',
  ),
];

void main() {
  setUp(() {
    Restage.debugReset();
    registerRestageWidgets();
  });

  for (final paywall in _paywalls) {
    testWidgets(
        "${paywall.id}: the app's own pushed screen reaches the paywall",
        (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final events = <RestageEvent>[];
      await tester.pumpWidget(MaterialApp(home: paywall.mount(events.add)));
      await tester.pumpAndSettle();
      // No design was delivered, so the mount shows its compiled original.
      expect(tester.takeException(), isStateError);
      expect(events.whereType<PaywallLoadFailed>(), isNotEmpty);

      await tester.tap(find.text(paywall.push));
      await tester.pumpAndSettle();
      await tester.tap(find.text(paywall.cta).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final custom = events.whereType<PaywallCustomEvent>().toList();
      expect(custom.map((e) => e.eventName), ['continue']);
      expect(custom.single.args, paywall.args);
    });

    test('${paywall.id}: the delivered design is unchanged', () {
      final bytes = File(
        'assets/restage/bundles/lib/paywalls/${paywall.id}.rsbundle',
      ).readAsBytesSync();
      expect(FlowContentHash.compute(bytes).value, paywall.bundle);
      final flow = RestageBundleCodec.decode(bytes)
          .entries
          .singleWhere((entry) =>
              entry.logicalPath == 'assets/paywalls/${paywall.id}.flow.json')
          .bytes;
      expect((jsonDecode(utf8.decode(flow)) as Map)['minClient'], 17);
    });
  }
}
