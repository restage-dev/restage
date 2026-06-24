import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:rfw/formats.dart';

class _SwitchableResolver implements VariantResolver {
  Uint8List? next;
  bool throwNext = false;

  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async {
    if (throwNext) {
      throw const RestagePaywallError(code: 'fetch_failed', message: 'no');
    }
    return ResolvedVariant(bytes: next!, paywallId: id);
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
    final resolver = _SwitchableResolver()..next = goodBytes;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'cached',
          resolver: resolver,
          cacheLastRender: true,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('First'), findsOneWidget);

    // Force a remount to trigger a second fetch; this time, fail.
    resolver.throwNext = true;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'cached',
          resolver: resolver,
          cacheLastRender: true,
          key: const ValueKey('round2'),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Cache hits → "First" still rendered.
    expect(find.text('First'), findsOneWidget);
  });
}
