import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';

class _ThrowingResolver implements VariantResolver {
  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) {
    throw const RestagePaywallError(
      code: 'asset_not_found',
      message: 'No asset',
    );
  }
}

class _CorruptResolver implements VariantResolver {
  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async {
    return ResolvedVariant(
      bytes: Uint8List.fromList([0xFF, 0xFE, 0xFD]),
      surfaceVersion: 'test',
      paywallId: id,
    );
  }
}

void main() {
  setUp(() => Restage.debugReset());

  testWidgets('authored fallback dispatches events and rejects stale callbacks',
      (tester) async {
    final events = <RestageEvent>[];
    VoidCallback? callback;
    await tester.pumpWidget(MaterialApp(
        home: RestagePaywall(
      id: 'offline',
      resolver: _ThrowingResolver(),
      onEvent: events.add,
      fallbackBuilder: (context) {
        callback = paywallEvent('continue', args: {'choice': 'original'});
        return TextButton(
            onPressed: callback, child: const Text('Original offer'));
      },
    )));
    await tester.pumpAndSettle();
    expect(find.text('Original offer'), findsOneWidget);
    expect(events.whereType<PaywallViewed>(), hasLength(1));
    await tester.tap(find.text('Original offer'));
    expect(events.whereType<PaywallCustomEvent>(), hasLength(1));
    final stale = callback!;
    await tester.pumpWidget(const SizedBox());
    expect(stale, throwsAssertionError);
    expect(events.whereType<PaywallCustomEvent>(), hasLength(1));
    expect(events.whereType<PaywallDismissed>(), hasLength(1));
  });

  testWidgets('renders SizedBox.shrink + emits PaywallLoadFailed by default',
      (tester) async {
    final received = <RestageEvent>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'broken',
          resolver: _ThrowingResolver(),
          onEvent: received.add,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(received.whereType<PaywallLoadFailed>(), hasLength(1));
    expect(find.byType(SizedBox), findsWidgets);
  });

  testWidgets('errorBuilder override receives RestagePaywallError',
      (tester) async {
    RestagePaywallError? captured;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'broken',
          resolver: _ThrowingResolver(),
          errorBuilder: (context, err) {
            captured = err;
            return Text('Error: ${err.code}');
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(captured?.code, 'asset_not_found');
    expect(find.text('Error: asset_not_found'), findsOneWidget);
  });

  testWidgets('decode failure produces RestagePaywallError, does NOT crash UI',
      (tester) async {
    final received = <RestageEvent>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'corrupt',
          resolver: _CorruptResolver(),
          onEvent: received.add,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final failures = received.whereType<PaywallLoadFailed>();
    expect(failures, hasLength(1));
    expect(failures.first.errorCode, 'decode_failed');
  });
}
