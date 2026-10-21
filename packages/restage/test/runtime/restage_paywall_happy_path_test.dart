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

class _ControlledResolver implements VariantResolver {
  final result = Completer<ResolvedVariant>();

  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) =>
      result.future;
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

  testWidgets(
      'commits the served assignment on first paint and snapshots one event '
      'for both callback paths', (tester) async {
    const assignment = SurfaceAssignment(
      experimentId: 'experiment.checkout',
      experimentRevisionId: 'revision.checkout.1',
      experimentEpochId: 'epoch.checkout.1',
      variantId: 'arm.treatment',
    );
    final resolver = _ControlledResolver();
    final local = <RestageEvent>[];
    final global = <RestageEvent>[];
    final subscription = Restage.events.listen(global.add);
    addTearDown(subscription.cancel);
    final bytes = Uint8List.fromList(
      encodeLibraryBlob(
        parseLibraryFile('''
          import restage.core;
          widget Paywall = Text(text: "Assigned");
        '''),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RestagePaywall(
          id: 'checkout',
          resolver: resolver,
          onEvent: local.add,
        ),
      ),
    );
    expect(
      Restage.assignmentFor('checkout', surfaceType: Surface.paywall),
      isNull,
    );

    resolver.result.complete(
      ResolvedVariant(
        bytes: bytes,
        surfaceVersion: 'served-version-42',
        paywallId: 'checkout',
        paywallPublishedVersion: 42,
        assignment: assignment,
      ),
    );
    await tester.pumpAndSettle();

    final localViewed = local.whereType<PaywallViewed>().single;
    final globalViewed = global.whereType<PaywallViewed>().single;
    expect(identical(localViewed, globalViewed), isTrue);
    expect(localViewed.surfaceId, 'checkout');
    expect(localViewed.surfaceType, Surface.paywall);
    expect(localViewed.surfaceVersion, 'served-version-42');
    expect(localViewed.assignment, assignment);
    expect(localViewed.variantId, 'arm.treatment');
    expect(
      Restage.assignmentFor('checkout', surfaceType: Surface.paywall),
      assignment,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    expect(
      Restage.assignmentFor('checkout', surfaceType: Surface.paywall),
      assignment,
    );
  });

  testWidgets(
      'painted compiled fallback replaces the previous served assignment',
      (tester) async {
    const assignment = SurfaceAssignment(
        experimentId: 'experiment.checkout',
        experimentRevisionId: 'revision.checkout',
        experimentEpochId: 'epoch.checkout',
        variantId: 'arm.checkout');
    final first = _ControlledResolver();
    await tester.pumpWidget(
        MaterialApp(home: RestagePaywall(id: 'checkout', resolver: first)));
    first.result.complete(ResolvedVariant(
        bytes: Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(
            'import restage.core; widget Paywall = Text(text: "Assigned");'))),
        paywallId: 'checkout',
        surfaceVersion: '1',
        assignment: assignment));
    await tester.pumpAndSettle();
    expect(Restage.assignmentFor('checkout', surfaceType: Surface.paywall),
        assignment);
    await tester.pumpWidget(const SizedBox());
    final second = _ControlledResolver();
    var offstage = true;
    late StateSetter setHost;
    final fallbackEvents = <RestageEvent>[];
    await tester.pumpWidget(
        MaterialApp(home: StatefulBuilder(builder: (context, setState) {
      setHost = setState;
      return Offstage(
          offstage: offstage,
          child: RestagePaywall(
              id: 'checkout',
              resolver: second,
              onEvent: fallbackEvents.add,
              fallbackBuilder: (_) => const Text('Compiled fallback')));
    })));
    second.result.completeError(RestagePaywallError(
        code: RestageErrorCodes.deliveryUnavailable, message: 'Offline'));
    await tester.pumpAndSettle();
    expect(Restage.assignmentFor('checkout', surfaceType: Surface.paywall),
        assignment);
    expect(fallbackEvents.whereType<PaywallViewed>(), isEmpty);
    setHost(() => offstage = false);
    await tester.pumpAndSettle();
    expect(find.text('Compiled fallback'), findsOneWidget);
    expect(fallbackEvents.whereType<PaywallViewed>().single.assignment, isNull);
    expect(Restage.assignmentFor('checkout', surfaceType: Surface.paywall),
        isNull);
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
