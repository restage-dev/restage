import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:rfw/formats.dart';

class _SwitchableResolver implements VariantResolver {
  Uint8List? next;
  bool throwNext = false;
  String? experimentId;
  String? variantId;
  int? experimentEpoch;

  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async {
    if (throwNext) {
      throw const RestagePaywallError(code: 'fetch_failed', message: 'no');
    }
    return ResolvedVariant(
      bytes: next!,
      paywallId: id,
      experimentId: experimentId,
      variantId: variantId,
      experimentEpoch: experimentEpoch,
    );
  }
}

void main() {
  setUp(() => Restage.debugReset());

  testWidgets(
      'with cacheLastRender: true, second resolver failure falls back '
      'to cached blob', (tester) async {
    final goodBytes = Uint8List.fromList(encodeLibraryBlob(parseLibraryFile('''
      import restage.core;
      widget Paywall = Text(text: "First");
    ''')));
    final resolver = _SwitchableResolver()
      ..next = goodBytes
      ..experimentId = 'exp_paywall_copy'
      ..variantId = 'variant_a'
      ..experimentEpoch = 3;
    final firstEvents = <RestageEvent>[];
    final secondEvents = <RestageEvent>[];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'cached',
          resolver: resolver,
          cacheLastRender: true,
          onEvent: firstEvents.add,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('First'), findsOneWidget);
    final firstViewed = firstEvents.whereType<PaywallViewed>().single;
    expect(firstViewed.experimentId, 'exp_paywall_copy');
    expect(firstViewed.variantId, 'variant_a');
    expect(firstViewed.experimentEpoch, 3);

    // Force a remount to trigger a second fetch; this time, fail.
    resolver.throwNext = true;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'cached',
          resolver: resolver,
          cacheLastRender: true,
          key: const ValueKey('round2'),
          onEvent: secondEvents.add,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Cache hits → "First" still rendered.
    expect(find.text('First'), findsOneWidget);
    final secondViewed = secondEvents.whereType<PaywallViewed>().single;
    expect(secondViewed.experimentId, 'exp_paywall_copy');
    expect(secondViewed.variantId, 'variant_a');
    expect(secondViewed.experimentEpoch, 3);
  });
}
