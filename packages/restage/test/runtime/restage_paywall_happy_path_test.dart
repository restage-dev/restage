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

void main() {
  setUp(() => Restage.debugReset());

  testWidgets('renders RFW source via library-registered widgets',
      (tester) async {
    // A trivial RFW source that uses restage.core widgets.
    const source = '''
      import restage.core;
      widget Paywall = Text(text: "Hello");
    ''';
    final bytes =
        Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(id: 'hello', resolver: _StaticResolver(bytes)),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Hello'), findsOneWidget);
  });

  testWidgets('emits PaywallLoadStarted, PaywallLoadCompleted, PaywallViewed',
      (tester) async {
    // Collect events via the per-widget onEvent callback. Subscribing to
    // Restage.events from inside testWidgets is awkward because cancelling
    // a broadcast subscription doesn't settle in fakeAsync; use onEvent to
    // assert lifecycle ordering instead.
    final received = <RestageEvent>[];
    const source = '''
      import restage.core;
      widget Paywall = Text(text: "Hi");
    ''';
    final bytes =
        Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'hi',
          resolver: _StaticResolver(bytes),
          onEvent: received.add,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final names = received.map((e) => e.name).toList();
    expect(
      names,
      containsAllInOrder(<String>[
        'paywall_load_started',
        'paywall_load_completed',
        'paywall_viewed',
      ]),
    );
  });
}
