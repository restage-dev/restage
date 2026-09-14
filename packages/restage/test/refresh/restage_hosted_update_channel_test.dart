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

const _surface = SurfaceRef(surfaceType: 'message', slug: 'welcome');

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
