import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/restage.dart';
import 'package:rfw/formats.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _StaticResolver implements VariantResolver {
  _StaticResolver(
    this.bytes, {
    this.experimentId,
    this.variantId,
    this.experimentEpoch,
    this.publishedVersion,
  });
  final Uint8List bytes;
  final String? experimentId;
  final String? variantId;
  final int? experimentEpoch;
  final int? publishedVersion;

  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async =>
      ResolvedVariant(
        bytes: bytes,
        paywallId: id,
        experimentId: experimentId,
        variantId: variantId,
        experimentEpoch: experimentEpoch,
        paywallPublishedVersion: publishedVersion,
      );
}

final class _ControlledResolver implements VariantResolver {
  final Completer<ResolvedVariant> response = Completer<ResolvedVariant>();

  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) =>
      response.future;
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
          resolver: _StaticResolver(
            bytes,
            experimentId: 'exp_paywall_copy',
            variantId: 'variant_a',
            experimentEpoch: 3,
          ),
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
    expect(viewed.experimentId, 'exp_paywall_copy');
    expect(viewed.variantId, 'variant_a');
    expect(viewed.experimentEpoch, 3);
  });

  testWidgets('a blob paywall emits one canonical root after successful paint',
      (tester) async {
    final requests = <http.Request>[];
    Restage.debugAnalyticsHttpClient = MockClient((request) async {
      requests.add(request);
      return http.Response('', 200);
    });
    Restage.configure(
      apiKey: 'rs_pk_test',
      baseUrl: 'http://127.0.0.1:1',
    );
    const source = '''
      import restage.core;
      widget Paywall = Text(text: "Canonical");
    ''';
    final bytes =
        Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RestagePaywall(
          id: 'upgrade',
          resolver: _StaticResolver(
            bytes,
            experimentId: 'exp-blob',
            variantId: 'variant-c',
            experimentEpoch: 4,
            publishedVersion: 12,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await Restage.debugFlushAnalytics();

    final events = <Map<String, Object?>>[
      for (final request in requests)
        for (final event in (jsonDecode(request.body)
            as Map<String, Object?>)['events']! as List)
          (event! as Map).cast<String, Object?>(),
    ];
    final presentations =
        events.where((event) => event['name'] == 'surface_presented').toList();
    expect(presentations, hasLength(1));
    expect(presentations.single['surface'], 'paywall');
    expect(presentations.single['surfaceId'], 'upgrade');
    expect(presentations.single['surfaceVersion'], '12');
    expect(presentations.single['surfaceSessionId'], isNotNull);
    expect(presentations.single['experimentId'], 'exp-blob');
    expect(presentations.single['variantId'], 'variant-c');
    expect(presentations.single['experimentEpoch'], 4);

    final viewed =
        events.singleWhere((event) => event['name'] == 'paywall_viewed');
    expect(viewed['surface'], 'paywall');
    expect(viewed['surfaceId'], 'upgrade');
    expect(viewed['surfaceVersion'], '12');
    expect(
      viewed['surfaceSessionId'],
      presentations.single['surfaceSessionId'],
    );
    expect(viewed['experimentId'], 'exp-blob');
    expect(viewed['variantId'], 'variant-c');
    expect(viewed['experimentEpoch'], 4);
  });

  testWidgets(
      'prepaint paywall lifecycle is owner-bound while global track stays '
      'surface-anonymous', (tester) async {
    final requests = <http.Request>[];
    _configureAnalytics(requests);
    final resolver = _ControlledResolver();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RestagePaywall(id: 'pending', resolver: resolver),
        ),
      ),
    );
    await tester.pump();
    Restage.track('global_during_paywall');

    final events = await _capturedEvents(requests);
    final started = events.singleWhere(
      (event) => event['name'] == 'paywall_load_started',
    );
    expect(started['surface'], 'paywall');
    expect(started['surfaceId'], 'pending');
    expect(started['surfaceVersion'], isNull);
    expect(started['surfaceSessionId'], isNull);
    expect(started['experimentId'], isNull);
    expect(started['variantId'], isNull);
    expect(started['experimentEpoch'], isNull);

    final global = events.singleWhere(
      (event) => event['name'] == 'global_during_paywall',
    );
    expect(global['surface'], isNull);
    expect(global['surfaceId'], isNull);
    expect(global['surfaceVersion'], isNull);
    expect(global['surfaceSessionId'], isNull);

    resolver.response.complete(
      ResolvedVariant(
        bytes: _blob('Pending resolved'),
        paywallId: 'pending',
      ),
    );
    await tester.pumpAndSettle();
  });

  testWidgets(
      'failed prepaint paywall lifecycle never fabricates a root session',
      (tester) async {
    final requests = <http.Request>[];
    _configureAnalytics(requests);
    final resolver = _ControlledResolver();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RestagePaywall(id: 'failed', resolver: resolver),
        ),
      ),
    );
    await tester.pump();
    resolver.response.completeError(
      const RestagePaywallError(
        code: RestageErrorCodes.deliveryUnavailable,
        message: 'controlled unavailable',
      ),
    );
    await tester.pumpAndSettle();

    final events = await _capturedEvents(requests);
    for (final event in events.where(
      (event) =>
          event['name'] == 'paywall_load_started' ||
          event['name'] == 'paywall_load_failed',
    )) {
      expect(event['surface'], 'paywall');
      expect(event['surfaceId'], 'failed');
      expect(event['surfaceVersion'], isNull);
      expect(event['surfaceSessionId'], isNull);
      expect(event['experimentId'], isNull);
      expect(event['variantId'], isNull);
      expect(event['experimentEpoch'], isNull);
    }
  });

  testWidgets(
      'overlapping paywalls retain independent active contexts when one '
      'unmounts', (tester) async {
    final requests = <http.Request>[];
    _configureAnalytics(requests);
    final controllerA = RestagePaywallController();
    final controllerB = RestagePaywallController();
    final bytes = _blob('Overlapping');

    Widget paywall(
      String id,
      int version,
      RestagePaywallController controller,
    ) =>
        RestagePaywall(
          key: ValueKey<String>(id),
          id: id,
          controller: controller,
          resolver: _StaticResolver(bytes, publishedVersion: version),
        );

    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: <Widget>[
            Expanded(
              key: const ValueKey<String>('slot-a'),
              child: paywall('a', 1, controllerA),
            ),
            Expanded(
              key: const ValueKey<String>('slot-b'),
              child: paywall('b', 2, controllerB),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final canonical = (await _capturedEvents(requests))
        .where((event) => event['name'] == 'surface_presented')
        .toList();
    final sessionA = canonical
        .singleWhere((event) => event['surfaceId'] == 'a')['surfaceSessionId'];
    final sessionB = canonical
        .singleWhere((event) => event['surfaceId'] == 'b')['surfaceSessionId'];
    requests.clear();

    controllerA.fireEvent('event_a');
    controllerB.fireEvent('event_b');
    await tester.pump();
    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: <Widget>[
            Expanded(
              key: const ValueKey<String>('slot-b'),
              child: paywall('b', 2, controllerB),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    controllerB.fireEvent('event_b_after_a_unmount');
    await tester.pump();

    final events = await _capturedEvents(requests);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    final eventA = events.singleWhere(
      (event) =>
          (event['properties'] as Map<String, Object?>?)?['eventName'] ==
          'event_a',
    );
    final eventB = events.singleWhere(
      (event) =>
          (event['properties'] as Map<String, Object?>?)?['eventName'] ==
          'event_b',
    );
    final eventBAfter = events.singleWhere(
      (event) =>
          (event['properties'] as Map<String, Object?>?)?['eventName'] ==
          'event_b_after_a_unmount',
    );
    expect(eventA['surfaceId'], 'a');
    expect(eventA['surfaceSessionId'], sessionA);
    expect(eventB['surfaceId'], 'b');
    expect(eventB['surfaceSessionId'], sessionB);
    expect(eventBAfter['surfaceId'], 'b');
    expect(eventBAfter['surfaceSessionId'], sessionB);
  });
}

Uint8List _blob(String text) {
  final source = '''
    import restage.core;
    widget Paywall = Text(text: "$text");
  ''';
  return Uint8List.fromList(encodeLibraryBlob(parseLibraryFile(source)));
}

void _configureAnalytics(List<http.Request> requests) {
  Restage.debugAnalyticsHttpClient = MockClient((request) async {
    requests.add(request);
    return http.Response('', 200);
  });
  Restage.configure(
    apiKey: 'rs_pk_test',
    baseUrl: 'http://127.0.0.1:1',
  );
}

Future<List<Map<String, Object?>>> _capturedEvents(
  List<http.Request> requests,
) async {
  await Restage.debugFlushAnalytics();
  return <Map<String, Object?>>[
    for (final request in requests)
      for (final event in (jsonDecode(request.body)
          as Map<String, Object?>)['events']! as List)
        (event! as Map).cast<String, Object?>(),
  ];
}
