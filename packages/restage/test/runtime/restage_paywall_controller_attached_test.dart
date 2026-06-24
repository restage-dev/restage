import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:rfw/formats.dart';

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

Uint8List _trivialPaywallBytes() {
  const source = '''
    import restage.core;
    widget Paywall = Text(text: "Hi");
  ''';
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}

void main() {
  setUp(() => Restage.debugReset());

  testWidgets('controller.fireEvent reaches host onEvent as PaywallCustomEvent',
      (tester) async {
    final received = <RestageEvent>[];
    final controller = RestagePaywallController();
    final bytes = _trivialPaywallBytes();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'pro_upgrade',
          resolver: _StaticResolver(bytes),
          controller: controller,
          onEvent: received.add,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(controller.isAttached, isTrue);

    controller.fireEvent('subscribe', args: const {'plan': 'monthly'});

    final custom =
        received.whereType<PaywallCustomEvent>().toList(growable: false);
    expect(custom, hasLength(1));
    expect(custom.single.eventName, 'subscribe');
    expect(custom.single.args, {'plan': 'monthly'});
    expect(custom.single.paywallId, 'pro_upgrade');
  });

  testWidgets(
      'controller.dismiss fires PaywallDismissed with the supplied reason',
      (tester) async {
    final received = <RestageEvent>[];
    final controller = RestagePaywallController();
    final bytes = _trivialPaywallBytes();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'pro_upgrade',
          resolver: _StaticResolver(bytes),
          controller: controller,
          onEvent: received.add,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    received.clear();
    controller.dismiss(reason: DismissReason.userClose);

    final dismissed =
        received.whereType<PaywallDismissed>().toList(growable: false);
    expect(dismissed, hasLength(1));
    expect(dismissed.single.reason, DismissReason.userClose);
    expect(dismissed.single.paywallId, 'pro_upgrade');
  });

  testWidgets(
      'controller.dismiss with no reason defaults to DismissReason.programmatic',
      (tester) async {
    final received = <RestageEvent>[];
    final controller = RestagePaywallController();
    final bytes = _trivialPaywallBytes();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'pro_upgrade',
          resolver: _StaticResolver(bytes),
          controller: controller,
          onEvent: received.add,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    received.clear();
    controller.dismiss();

    final dismissed =
        received.whereType<PaywallDismissed>().toList(growable: false);
    expect(dismissed, hasLength(1));
    expect(dismissed.single.reason, DismissReason.programmatic);
  });

  testWidgets('controller is detached after RestagePaywall is unmounted',
      (tester) async {
    final controller = RestagePaywallController();
    final bytes = _trivialPaywallBytes();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'pro_upgrade',
          resolver: _StaticResolver(bytes),
          controller: controller,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(controller.isAttached, isTrue);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    expect(controller.isAttached, isFalse);
  });
}
