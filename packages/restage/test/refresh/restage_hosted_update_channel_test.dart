import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/restage.dart';
import 'package:restage/src/refresh/restage_hosted_update_channel.dart';
import 'package:restage/src/restage_rpc_client/restage_rpc_client.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';

import '../support/placement_delivery_fixture.dart';

const _surface = SurfaceRef(surfaceType: 'message', slug: 'welcome');

PublicPlacementDeliveryV1 _delivery() =>
    (readPlacementDeliveryFixture().response.decisions.first
            as PlacementBatchAvailableV1)
        .publicDelivery;

PlacementDeliveryWatchV1 _watch({
  String digest = 'a',
  String tag = 'first',
  String? edgeOrigin,
}) {
  final mac = base64UrlEncode(List.filled(32, 1)).replaceAll('=', '');
  return PlacementDeliveryWatchV1(
    decisionIdentityDigest: CanonicalDigest(digest * 64),
    edgeOrigin: edgeOrigin,
    channels: [
      for (final (index, scope) in _delivery().dependencyClosure.indexed)
        PlacementDeliveryWatchChannelV1(
          scope: scope,
          token: 'v2.ABCDEFGH.2000000000000.'
              '${base64UrlEncode(utf8.encode('$tag-$index')).replaceAll('=', '')}.$mac',
        ),
    ],
  );
}

String _token(PlacementDeliveryWatchV1 watch, DeliveryPolicyScopeV1 scope) =>
    watch.channels.singleWhere((channel) => channel.scope == scope).token;

RestageRpcClient _stampClient(
  List<SurfaceStampFetchResult> stamps, {
  void Function()? onRequest,
}) {
  var index = 0;
  return RestageRpcClient(
    baseUrl: 'https://api.example.com',
    apiKey: 'rs_pk_test',
    httpClient: MockClient((request) async {
      onRequest?.call();
      final stamp = stamps[index < stamps.length ? index++ : stamps.length - 1];
      if (stamp is SurfaceStampRateLimited) {
        return http.Response(
          'not json',
          429,
          headers: {'Retry-After': '${stamp.retryAfter.inSeconds}'},
        );
      }
      if (stamp is SurfaceStampUnavailable) return http.Response('', 503);
      final available = stamp as SurfaceStamp;
      return http.Response(
        jsonEncode(<String, Object?>{
          'version': available.version,
          if (available.watchChannel case final token?) 'watchChannel': token,
        }),
        200,
      );
    }),
  );
}

void main() {
  late _WebSocketTestServer server;

  setUp(() async {
    server = await _WebSocketTestServer.start();
  });

  tearDown(() => server.close());

  test(
      'missing accepted watch authority resolves before adopting fresh scoped tokens',
      () async {
    final channel = RestageHostedUpdateChannel(
      rpcClient: _stampClient(const [SurfaceStamp(version: 1)]),
      edgeUrl: server.httpUrl,
    );
    final watch = _watch();
    final scope = watch.channels.first.scope;
    final updates = StreamIterator(channel.watchDelivery(scope,
        reconnectProbe: () async => PlacementRefreshProbeV1.unchanged(
            watch.decisionIdentityDigest,
            watch: watch)));
    addTearDown(updates.cancel);
    final next = updates.moveNext();
    expect(await next.timeout(const Duration(seconds: 2)), isTrue);
    expect(updates.current, scope);
    await server.socketAt(0);
    expect(server.requests.single.uri.queryParameters['channel'],
        _token(watch, scope));
    await updates.cancel();
  });

  test(
      'an initially throttled watch still resolves its missing accepted authority',
      () async {
    var probes = 0;
    final channel = RestageHostedUpdateChannel(
      rpcClient: _stampClient(const [SurfaceStamp(version: 1)]),
      edgeUrl: server.httpUrl,
      reconnectBaseDelay: const Duration(milliseconds: 1),
      random: const _FixedRandom(0.5),
    );
    final watch = _watch();
    final scope = watch.channels.first.scope;
    final updates = StreamIterator(channel.watchDelivery(scope,
        reconnectProbe: () async => ++probes == 1
            ? const PlacementRefreshProbeV1.rateLimited(Duration.zero)
            : PlacementRefreshProbeV1.unchanged(watch.decisionIdentityDigest,
                watch: watch)));
    addTearDown(updates.cancel);
    expect(
        await updates.moveNext().timeout(const Duration(seconds: 2)), isTrue);
    expect(updates.current, scope);
    await server.socketAt(0);
    expect(probes, 2);
    await updates.cancel();
  });

  test('an unmatched exact family never borrows a different scope token',
      () async {
    final channel = RestageHostedUpdateChannel(
      rpcClient: _stampClient(const [SurfaceStamp(version: 1)]),
      edgeUrl: server.httpUrl,
    );
    final watch = _watch();
    final child = watch.channels
        .singleWhere((channel) => !channel.scope.root.isPlacement)
        .scope;
    final otherFamily = DeliveryPolicyScopeV1(
        root: child.root, family: const DeliveryFamilySelectorV1.general());
    expect(await channel.watchDelivery(otherFamily, watch: watch).first,
        otherFamily);
    expect(server.connectionCount, 0);
  });

  test('a watch connects to the origin the server advertised', () async {
    final channel = RestageHostedUpdateChannel(
      rpcClient: _stampClient(const [SurfaceStamp(version: 1)]),
    );
    final watch = _watch(edgeOrigin: server.httpUrl.origin);
    final scope = watch.channels.last.scope;
    final updates = StreamIterator(channel.watchDelivery(scope,
        watch: watch,
        reconnectProbe: () async => throw StateError('no probe')));
    addTearDown(updates.cancel);
    final update = updates.moveNext();
    final socket = await server.socketAt(0);
    socket.add(jsonEncode({'type': 'surface_update'}));
    expect(await update, isTrue);
    expect(server.requests.single.uri.queryParameters['channel'],
        _token(watch, scope));
  });

  test('a watch with no advertised origin and no override never connects',
      () async {
    final channel = RestageHostedUpdateChannel(
      rpcClient: _stampClient(const [SurfaceStamp(version: 1)]),
    );
    final watch = _watch();
    final scope = watch.channels.last.scope;
    final updates = StreamIterator(channel.watchDelivery(scope,
        watch: watch,
        reconnectProbe: () async => throw StateError('no probe')));
    addTearDown(updates.cancel);
    unawaited(updates.moveNext());
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(server.connectionCount, 0);
  });

  test(
      'delivery watches use the supplied exact scoped token on the existing socket',
      () async {
    var surfaceStampRequests = 0;
    final channel = RestageHostedUpdateChannel(
      rpcClient: _stampClient(const [SurfaceStamp(version: 1)],
          onRequest: () => surfaceStampRequests++),
      edgeUrl: server.httpUrl,
      reconnectBaseDelay: const Duration(milliseconds: 1),
      random: const _FixedRandom(0),
    );
    final watch = _watch();
    final scope = watch.channels.last.scope;
    final updates = StreamIterator(channel.watchDelivery(scope,
        watch: watch,
        reconnectProbe: () async =>
            throw StateError('initial token requires no probe')));
    addTearDown(updates.cancel);
    final update = updates.moveNext();
    final socket = await server.socketAt(0);
    expect(server.requests.single.uri.path, '/watch');
    expect(server.requests.single.uri.queryParameters['channel'],
        _token(watch, scope));
    socket.add(jsonEncode({'type': 'surface_update'}));
    expect(await update, isTrue);
    expect(updates.current, scope);
    expect(surfaceStampRequests, 0);
  });

  test(
      'two accepted decisions sharing a scope keep independent token associations',
      () async {
    final channel = RestageHostedUpdateChannel(
      rpcClient: _stampClient(const [SurfaceStamp(version: 1)]),
      edgeUrl: server.httpUrl,
      reconnectBaseDelay: const Duration(milliseconds: 1),
    );
    final firstWatch = _watch(tag: 'first');
    final secondWatch = _watch(digest: 'b', tag: 'second');
    final scope = firstWatch.channels.first.scope;
    final firstUpdates = <DeliveryPolicyScopeV1>[];
    final secondUpdates = <DeliveryPolicyScopeV1>[];
    final received = Completer<void>();
    final first =
        channel.watchDelivery(scope, watch: firstWatch).listen((update) {
      firstUpdates.add(update);
      received.complete();
    });
    final second = channel
        .watchDelivery(scope, watch: secondWatch)
        .listen(secondUpdates.add);
    final firstSocket = await server.socketAt(0);
    await server.socketAt(1);
    expect(server.requests[0].uri.queryParameters['channel'],
        _token(firstWatch, scope));
    expect(server.requests[1].uri.queryParameters['channel'],
        _token(secondWatch, scope));
    firstSocket.add(jsonEncode({'type': 'surface_update'}));
    await received.future;
    expect(firstUpdates, [scope]);
    expect(secondUpdates, isEmpty);
    await first.cancel();
    await second.cancel();
  });

  test('expired delivery tokens renew through the accepted read-only probe',
      () async {
    var surfaceStampRequests = 0;
    var probes = 0;
    final channel = RestageHostedUpdateChannel(
      rpcClient: _stampClient(const [SurfaceStamp(version: 1)],
          onRequest: () => surfaceStampRequests++),
      edgeUrl: server.httpUrl,
      reconnectBaseDelay: const Duration(hours: 1),
      random: const _FixedRandom(0),
    );
    final watch = _watch();
    final renewed = _watch(tag: 'renewed');
    final scope = watch.channels.first.scope;
    final updates = <DeliveryPolicyScopeV1>[];
    final subscription =
        channel.watchDelivery(scope, watch: watch, reconnectProbe: () async {
      probes++;
      return PlacementRefreshProbeV1.unchanged(renewed.decisionIdentityDigest,
          watch: renewed);
    }).listen(updates.add);
    final firstSocket = await server.socketAt(0);
    await firstSocket.close(4401, 'token expired');
    await server.socketAt(1);
    expect(server.requests[1].uri.queryParameters['channel'],
        _token(renewed, scope));
    expect(updates, isEmpty);
    expect(probes, 1);
    expect(surfaceStampRequests, 0);
    await subscription.cancel();
  });

  test(
      'reconnect observes changed decision authority with identical publication',
      () async {
    final publication = _delivery().actualPublication;
    final channel = RestageHostedUpdateChannel(
      rpcClient: _stampClient(const [SurfaceStamp(version: 1)]),
      edgeUrl: server.httpUrl,
      reconnectBaseDelay: const Duration(milliseconds: 1),
      random: const _FixedRandom(0.5),
    );
    final watch = _watch();
    final changed = _watch(digest: 'b', tag: 'changed-authority');
    final scope = watch.channels.first.scope;
    final updates = StreamIterator(channel.watchDelivery(scope,
        watch: watch,
        reconnectProbe: () async => PlacementRefreshProbeV1.unchanged(
            changed.decisionIdentityDigest,
            watch: changed)));
    addTearDown(updates.cancel);
    final next = updates.moveNext();
    final socket = await server.socketAt(0);
    await socket.close();
    expect(await next.timeout(const Duration(seconds: 2)), isTrue);
    expect(updates.current, scope);
    await server.socketAt(1);
    expect(server.requests[1].uri.queryParameters['channel'],
        _token(changed, scope));
    expect(_delivery().actualPublication, publication);
    expect(changed.decisionIdentityDigest, isNot(watch.decisionIdentityDigest));
    await updates.cancel();
  });

  test(
      'unknown reconnect authority requires resolution without a surface probe',
      () async {
    var surfaceStampRequests = 0;
    var probes = 0;
    final channel = RestageHostedUpdateChannel(
      rpcClient: _stampClient(const [SurfaceStamp(version: 1)],
          onRequest: () => surfaceStampRequests++),
      edgeUrl: server.httpUrl,
      reconnectBaseDelay: const Duration(milliseconds: 1),
      random: const _FixedRandom(0),
    );
    final watch = _watch();
    final scope = watch.channels.first.scope;
    final updates = StreamIterator(
        channel.watchDelivery(scope, watch: watch, reconnectProbe: () async {
      probes++;
      return const PlacementRefreshProbeV1.unavailable();
    }));
    addTearDown(updates.cancel);
    final next = updates.moveNext();
    final socket = await server.socketAt(0);
    await socket.close(4401);
    expect(await next.timeout(const Duration(seconds: 2)), isTrue);
    expect(updates.current, scope);
    await updates.cancel();
    expect(probes, 1);
    expect(surfaceStampRequests, 0);
    expect(server.connectionCount, 1);
  });

  testWidgets(
      'delivery probe throttling and cancellation share the existing backoff',
      (tester) async {
    var probes = 0;
    final channel = RestageHostedUpdateChannel(
      rpcClient: _stampClient(const [SurfaceStamp(version: 1)]),
      edgeUrl: Uri.parse('http://edge.example.com'),
      reconnectBaseDelay: const Duration(seconds: 1),
      random: const _FixedRandom(0.5),
    );
    final updates = <DeliveryPolicyScopeV1>[];
    final subscription = channel.watchDelivery(
        _delivery().dependencyClosure.first, reconnectProbe: () async {
      probes++;
      return const PlacementRefreshProbeV1.rateLimited(Duration(seconds: 7));
    }).listen(updates.add);
    await tester.pump();
    expect(probes, 1);
    await tester.pump(const Duration(milliseconds: 6999));
    expect(probes, 1);
    await tester.pump(const Duration(milliseconds: 1));
    expect(probes, 2);
    expect(updates, isEmpty);
    await subscription.cancel();
    await tester.pump(const Duration(seconds: 30));
    expect(probes, 2);
  });

  test('cancelling while a delivery probe is pending prevents a renewed socket',
      () async {
    final probeStarted = Completer<void>();
    final probe = Completer<PlacementRefreshProbeV1>();
    final channel = RestageHostedUpdateChannel(
      rpcClient: _stampClient(const [SurfaceStamp(version: 1)]),
      edgeUrl: server.httpUrl,
      reconnectBaseDelay: const Duration(milliseconds: 1),
      random: const _FixedRandom(0),
    );
    final watch = _watch();
    final updates = <DeliveryPolicyScopeV1>[];
    final subscription = channel.watchDelivery(watch.channels.first.scope,
        watch: watch, reconnectProbe: () {
      probeStarted.complete();
      return probe.future;
    }).listen(updates.add);
    final socket = await server.socketAt(0);
    await socket.close(4401);
    await probeStarted.future;
    await subscription.cancel();
    probe.complete(PlacementRefreshProbeV1.unchanged(
        watch.decisionIdentityDigest,
        watch: _watch(tag: 'renewed')));
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await pumpEventQueue();
    expect(server.connectionCount, 1);
    expect(updates, isEmpty);
  });

  testWidgets('waits for the throttled stamp delay before retrying',
      (tester) async {
    var stampRequests = 0;
    final channel = RestageHostedUpdateChannel(
      rpcClient: _stampClient(
        const [
          SurfaceStampRateLimited(Duration(seconds: 7)),
        ],
        onRequest: () => stampRequests++,
      ),
      edgeUrl: Uri.parse('http://edge.example.com'),
      reconnectBaseDelay: const Duration(seconds: 1),
      random: const _FixedRandom(0.5),
    );
    final subscription = channel.watch(_surface).listen((_) {});

    await tester.pump();
    expect(stampRequests, 1);

    await tester.pump(const Duration(milliseconds: 6999));
    expect(stampRequests, 1);

    await tester.pump(const Duration(milliseconds: 1));
    expect(stampRequests, 2);
    await subscription.cancel();
  });

  testWidgets('keeps a longer reconnect backoff than the throttled delay',
      (tester) async {
    var stampRequests = 0;
    final channel = RestageHostedUpdateChannel(
      rpcClient: _stampClient(
        const [
          SurfaceStampRateLimited(Duration(seconds: 1)),
        ],
        onRequest: () => stampRequests++,
      ),
      edgeUrl: Uri.parse('http://edge.example.com'),
      reconnectBaseDelay: const Duration(seconds: 10),
      random: const _FixedRandom(0.5),
    );
    final subscription = channel.watch(_surface).listen((_) {});

    await tester.pump();
    expect(stampRequests, 1);

    await tester.pump(const Duration(milliseconds: 9999));
    expect(stampRequests, 1);

    await tester.pump(const Duration(milliseconds: 1));
    expect(stampRequests, 2);
    await subscription.cancel();
  });

  testWidgets('cancelling a throttled stamp wait prevents its retry',
      (tester) async {
    var stampRequests = 0;
    final channel = RestageHostedUpdateChannel(
      rpcClient: _stampClient(
        const [
          SurfaceStampRateLimited(Duration(seconds: 7)),
        ],
        onRequest: () => stampRequests++,
      ),
      edgeUrl: Uri.parse('http://edge.example.com'),
      reconnectBaseDelay: const Duration(seconds: 1),
      random: const _FixedRandom(0.5),
    );
    final subscription = channel.watch(_surface).listen((_) {});

    await tester.pump();
    expect(stampRequests, 1);

    await subscription.cancel();
    await tester.pump(const Duration(seconds: 7));

    expect(stampRequests, 1);
  });

  test('emits a surface update for a surface_update text frame', () async {
    final channel = RestageHostedUpdateChannel(
      rpcClient: _stampClient(
        const [SurfaceStamp(version: 1, watchChannel: 'token +/?')],
      ),
      edgeUrl: server.httpUrl,
      reconnectBaseDelay: const Duration(milliseconds: 1),
      random: Random(1),
    );
    final update = channel.watch(_surface).first;
    final socket = await server.socketAt(0);

    expect(server.requests.single.uri.path, '/watch');
    expect(server.requests.single.uri.queryParameters['channel'], 'token +/?');
    socket.add(jsonEncode(<String, Object>{'type': 'surface_update'}));

    expect(await update, const TypeMatcher<SurfaceUpdate>());
  });

  test('cancelling closes the socket and prevents reconnects', () async {
    var stampRequests = 0;
    final channel = RestageHostedUpdateChannel(
      rpcClient: _stampClient(
        const [SurfaceStamp(version: 1, watchChannel: 'token')],
        onRequest: () => stampRequests++,
      ),
      edgeUrl: server.httpUrl,
      reconnectBaseDelay: const Duration(milliseconds: 1),
      random: Random(1),
    );
    final subscription = channel.watch(_surface).listen((_) {});
    await server.socketAt(0);

    await subscription.cancel();
    await server.disconnectAt(0);
    // Settle deterministically rather than on a single wall-clock delay: drain
    // the microtask queue, then give any erroneous reconnect (backoff base 1ms)
    // ample real time to fire, then drain again. Under load a fixed short delay
    // could read the counters before teardown settled.
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await pumpEventQueue();

    expect(server.connectionCount, 1);
    expect(stampRequests, 1);
  });

  test('reconnect emits immediately when the stamp advanced in the gap',
      () async {
    final channel = RestageHostedUpdateChannel(
      rpcClient: _stampClient(const [
        SurfaceStamp(version: 1, watchChannel: 'first'),
        SurfaceStamp(version: 2, watchChannel: 'second'),
      ]),
      edgeUrl: server.httpUrl,
      reconnectBaseDelay: const Duration(milliseconds: 1),
      random: Random(1),
    );
    final updates = StreamIterator(channel.watch(_surface));
    final nextUpdate = updates.moveNext();
    final firstSocket = await server.socketAt(0);

    await firstSocket.close();

    expect(
      await nextUpdate.timeout(
        const Duration(seconds: 2),
        onTimeout: () => throw StateError('client did not emit gap update'),
      ),
      isTrue,
    );
    expect(updates.current, isA<SurfaceUpdate>());
    await server.socketAt(1);
    expect(server.requests[1].uri.queryParameters['channel'], 'second');
    await updates.cancel();
  });

  test('an expired-token close reconnects after a short random delay',
      () async {
    final channel = RestageHostedUpdateChannel(
      rpcClient: _stampClient(const [
        SurfaceStamp(version: 1, watchChannel: 'first'),
        SurfaceStamp(version: 1, watchChannel: 'second'),
      ]),
      edgeUrl: server.httpUrl,
      reconnectBaseDelay: const Duration(hours: 1),
      // 0.1 of the five-second maximum.
      random: const _FixedRandom(0.1),
    );
    final subscription = channel.watch(_surface).listen((_) {});
    final firstSocket = await server.socketAt(0);

    await firstSocket.close(4401, 'token expired');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(server.connectionCount, 1);

    await server.socketAt(1);
    expect(server.requests[1].uri.queryParameters['channel'], 'second');
    await subscription.cancel();
  });

  test('any other close waits for the backoff', () async {
    final channel = RestageHostedUpdateChannel(
      rpcClient: _stampClient(
        const [SurfaceStamp(version: 1, watchChannel: 'token')],
      ),
      edgeUrl: server.httpUrl,
      reconnectBaseDelay: const Duration(hours: 1),
      random: Random(1),
    );
    final subscription = channel.watch(_surface).listen((_) {});
    final firstSocket = await server.socketAt(0);

    await firstSocket.close(1000);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(server.connectionCount, 1);
    await subscription.cancel();
  });

  test('an oversized frame is dropped and fails the connection', () async {
    final channel = RestageHostedUpdateChannel(
      rpcClient: _stampClient(
        const [SurfaceStamp(version: 1, watchChannel: 'token')],
      ),
      edgeUrl: server.httpUrl,
      reconnectBaseDelay: const Duration(milliseconds: 1),
      random: Random(1),
    );
    final emitted = <SurfaceUpdate>[];
    final subscription = channel.watch(_surface).listen(emitted.add);
    final firstSocket = await server.socketAt(0);

    final message = jsonEncode(<String, Object>{'type': 'surface_update'});
    firstSocket.add('$message${' ' * (64 * 1024 - message.length + 1)}');
    await server.disconnectAt(0);

    final secondSocket = await server.socketAt(1);
    expect(emitted, isEmpty);
    secondSocket.add('$message${' ' * (64 * 1024 - message.length)}');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(emitted, hasLength(1));
    await subscription.cancel();
  });

  test('a stamp without a watch channel stays silent', () async {
    final channel = RestageHostedUpdateChannel(
      rpcClient: _stampClient(const [SurfaceStamp(version: 1)]),
      edgeUrl: server.httpUrl,
      reconnectBaseDelay: const Duration(milliseconds: 1),
      random: Random(1),
    );
    final emitted = <SurfaceUpdate>[];
    final subscription = channel.watch(_surface).listen(emitted.add);

    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(server.connectionCount, 0);
    expect(emitted, isEmpty);
    await subscription.cancel();
  });

  test('watch never throws synchronously for an unusable edge URI', () async {
    final channel = RestageHostedUpdateChannel(
      rpcClient: _stampClient(
        const [SurfaceStamp(version: 1, watchChannel: 'token')],
      ),
      edgeUrl: Uri(),
      reconnectBaseDelay: const Duration(milliseconds: 1),
      random: Random(1),
    );

    expect(() => channel.watch(_surface), returnsNormally);
    final subscription = channel.watch(_surface).listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await subscription.cancel();
  });
}

final class _FixedRandom implements Random {
  const _FixedRandom(this.value);

  final double value;

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => value;

  @override
  int nextInt(int max) => 0;
}

final class _WebSocketTestServer {
  _WebSocketTestServer._(this._server) {
    _server.listen((request) async {
      requests.add(request);
      final socket = await WebSocketTransformer.upgrade(request);
      final disconnected = Completer<void>();
      socket.listen(
        (_) {},
        onDone: disconnected.complete,
      );
      _sockets.add(socket);
      _disconnects.add(disconnected.future);
      if (_socketWaiters.remove(_sockets.length - 1) case final waiter?) {
        waiter.complete(socket);
      }
    });
  }

  static Future<_WebSocketTestServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return _WebSocketTestServer._(server);
  }

  final HttpServer _server;
  final List<WebSocket> _sockets = [];
  final List<Future<void>> _disconnects = [];
  final Map<int, Completer<WebSocket>> _socketWaiters = {};
  final List<HttpRequest> requests = [];

  Uri get httpUrl =>
      Uri.parse('http://${_server.address.host}:${_server.port}');

  int get connectionCount => _sockets.length;

  Future<WebSocket> socketAt(int index) {
    if (index < _sockets.length) return Future.value(_sockets[index]);
    return (_socketWaiters[index] ??= Completer<WebSocket>()).future.timeout(
          const Duration(seconds: 2),
          onTimeout: () => throw StateError('socket $index was not accepted'),
        );
  }

  Future<void> disconnectAt(int index) => _disconnects[index].timeout(
        const Duration(seconds: 2),
        onTimeout: () => throw StateError('server did not observe disconnect'),
      );

  Future<void> close() async {
    for (final socket in _sockets) {
      await socket.close();
    }
    await _server.close(force: true);
  }
}
