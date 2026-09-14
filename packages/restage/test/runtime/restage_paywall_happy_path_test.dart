import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage/restage.dart';
import 'package:rfw/formats.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _StaticResolver implements VariantResolver {
  _StaticResolver(
    this.bytes, {
    this.publishedVersion,
    String? surfaceVersion,
  }) : surfaceVersion =
            surfaceVersion ?? publishedVersion?.toString() ?? 'test';
  final Uint8List bytes;
  final int? publishedVersion;
  final String surfaceVersion;

  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async =>
      ResolvedVariant(
        bytes: bytes,
        surfaceVersion: surfaceVersion,
        paywallId: id,
        paywallPublishedVersion: publishedVersion,
      );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    Restage.debugReset();
  });

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
    final viewed = received.whereType<PaywallViewed>().single;
    expect(viewed.publishedVersion, isNull);
  });

  testWidgets('an active paywall reports settled pager changes',
      (tester) async {
    final received = <RestageEvent>[];
    Restage.configure(
      apiKey: 'rs_pk_test',
      baseUrl: 'http://127.0.0.1:1',
    );
    final bytes = Uint8List.fromList(encodeLibraryBlob(parseLibraryFile('''
      import restage.core;
      import restage.material;
      widget Paywall = SizedBox(
        width: 240.0,
        height: 160.0,
        child: RestagePager(children: [
          Text(text: "First page"),
          Text(text: "Second page"),
        ]),
      );
    ''')));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'pager-paywall',
          resolver: _StaticResolver(bytes, surfaceVersion: 'pager-v1'),
          onEvent: received.add,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(received.whereType<PagerPageChanged>(), isEmpty);

    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();

    expect(
      received.whereType<PagerPageChanged>(),
      <Matcher>[
        isA<PagerPageChanged>()
            .having((event) => event.pageIndex, 'pageIndex', 1)
            .having((event) => event.pageCount, 'pageCount', 2),
      ],
    );
  });
}
