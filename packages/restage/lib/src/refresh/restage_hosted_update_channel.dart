import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../restage_rpc_client/restage_rpc_client.dart';
import 'surface_update_channel.dart';

/// The Restage-hosted realtime lane.
///
/// While a surface is watched, this channel fetches its current stamp and
/// connects to the configured edge service. Disconnects retry with jittered
/// backoff, and each retry compares a fresh stamp so an update published during
/// the gap is still observed. Connection failures stay silent; the mounted
/// surface behaves as if live refresh were unavailable.
///
/// You do not construct this directly — pass `Restage.configure(
/// liveRefreshEdgeUrl: ...)` and the SDK installs it as the default update
/// channel. To drive live refresh from your own infrastructure instead,
/// implement [SurfaceUpdateChannel] and pass it as `updateChannel`.
final class RestageHostedUpdateChannel implements SurfaceUpdateChannel {
  /// Creates a hosted update channel.
  RestageHostedUpdateChannel({
    required RestageRpcClient rpcClient,
    required Uri edgeUrl,
    @visibleForTesting Duration reconnectBaseDelay = const Duration(seconds: 1),
    @visibleForTesting Random? random,
  })  : _rpcClient = rpcClient,
        _edgeUrl = edgeUrl,
        _reconnectBaseDelay = reconnectBaseDelay,
        _random = random ?? Random();

  final RestageRpcClient _rpcClient;
  final Uri _edgeUrl;
  final Duration _reconnectBaseDelay;
  final Random _random;

  @override
  Stream<SurfaceUpdate> watch(SurfaceRef surface) => _HostedWatch(
        surface: surface,
        rpcClient: _rpcClient,
        edgeUrl: _edgeUrl,
        reconnectBaseDelay: _reconnectBaseDelay,
        random: _random,
      ).stream;
}

final class _HostedWatch {
  _HostedWatch({
    required this.surface,
    required this.rpcClient,
    required this.edgeUrl,
    required this.reconnectBaseDelay,
    required this.random,
  }) {
    controller = StreamController<SurfaceUpdate>(
      onListen: _onListen,
      onCancel: _onCancel,
    );
  }

  final SurfaceRef surface;
  final RestageRpcClient rpcClient;
  final Uri edgeUrl;
  final Duration reconnectBaseDelay;
  final Random random;

  late final StreamController<SurfaceUpdate> controller;
  StreamSubscription<Object?>? _socketSubscription;
  WebSocketChannel? _socket;
  Completer<void>? _socketDone;
  Timer? _backoffTimer;
  Completer<void>? _backoffDone;
  bool _stopped = false;
  int? _lastSeenVersion;

  Stream<SurfaceUpdate> get stream => controller.stream;

  void _onListen() {
    unawaited(_run());
  }

  Future<void> _onCancel() async {
    _stopped = true;
    _backoffTimer?.cancel();
    _backoffTimer = null;
    final backoffDone = _backoffDone;
    _backoffDone = null;
    if (backoffDone != null && !backoffDone.isCompleted) {
      backoffDone.complete();
    }
    final socketDone = _socketDone;
    if (socketDone != null && !socketDone.isCompleted) {
      socketDone.complete();
    }
    await _closeSocket();
  }

  Future<void> _run() async {
    var reconnectAttempt = 0;
    while (!_stopped) {
      if (reconnectAttempt > 0) {
        await _waitForBackoff(reconnectAttempt);
        if (_stopped) return;
      }

      try {
        final stamp = await rpcClient.fetchSurfaceStamp(
          surfaceType: surface.surfaceType,
          surfaceSlug: surface.slug,
        );
        if (_stopped) return;
        if (stamp == null) {
          reconnectAttempt++;
          continue;
        }

        final token = stamp.watchChannel;
        if (token == null) return;

        final previousVersion = _lastSeenVersion;
        _lastSeenVersion = stamp.version;
        if (previousVersion != null && stamp.version != previousVersion) {
          controller.add(SurfaceUpdate(surface));
        }

        final socket = WebSocketChannel.connect(_webSocketUri(edgeUrl, token));
        _socket = socket;
        final socketDone = _listenToSocket(socket);
        await socket.ready;
        // The `finally` closes the socket on this return, as it does for the
        // normal and error paths.
        if (_stopped) return;
        // A reconnect delivers a duplicate frame here; it forces a full
        // re-resolve, bounded by the registry's canSwap()/_refreshing guard.
        await socketDone;
      } catch (_) {
        // Transport and decoding failures are retryable while the surface is
        // still watched. They never reach the stream as errors.
      } finally {
        await _closeSocket();
      }
      reconnectAttempt++;
    }
  }

  Future<void> _listenToSocket(WebSocketChannel socket) async {
    final done = Completer<void>();
    _socketDone = done;
    _socketSubscription = socket.stream.listen(
      _handleFrame,
      onError: (Object _) {
        if (!done.isCompleted) done.complete();
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
    );
    await done.future;
    if (identical(_socketDone, done)) _socketDone = null;
  }

  void _handleFrame(Object? frame) {
    if (_stopped || frame is! String) return;
    try {
      final message = jsonDecode(frame);
      if (message is Map && message['type'] == 'surface_update') {
        controller.add(SurfaceUpdate(surface));
      }
    } catch (_) {
      // Ignore malformed or unrelated frames.
    }
  }

  Future<void> _waitForBackoff(int attempt) {
    if (_stopped) return Future<void>.value();
    final done = Completer<void>();
    _backoffDone = done;
    _backoffTimer = Timer(_backoffDelay(attempt), () {
      _backoffTimer = null;
      if (identical(_backoffDone, done)) _backoffDone = null;
      if (!done.isCompleted) done.complete();
    });
    return done.future;
  }

  Duration _backoffDelay(int attempt) {
    const cap = Duration(seconds: 60);
    final exponent = min(attempt - 1, 30);
    final uncappedMicros = reconnectBaseDelay.inMicroseconds * pow(2, exponent);
    final cappedMicros = min(uncappedMicros, cap.inMicroseconds).toInt();
    final jitter = 0.75 + random.nextDouble() * 0.5;
    return Duration(
      microseconds: min((cappedMicros * jitter).round(), cap.inMicroseconds),
    );
  }

  Future<void> _closeSocket() async {
    final socket = _socket;
    _socket = null;
    if (socket != null) {
      try {
        await socket.sink.close();
      } catch (_) {}
    }
    final subscription = _socketSubscription;
    _socketSubscription = null;
    if (subscription != null) {
      try {
        await subscription.cancel();
      } catch (_) {}
    }
  }
}

Uri _webSocketUri(Uri edgeUrl, String token) {
  final scheme = switch (edgeUrl.scheme) {
    'http' => 'ws',
    'https' => 'wss',
    final scheme => scheme,
  };
  final basePath = edgeUrl.path.endsWith('/')
      ? edgeUrl.path.substring(0, edgeUrl.path.length - 1)
      : edgeUrl.path;
  return edgeUrl.replace(
    scheme: scheme,
    path: '$basePath/watch',
    queryParameters: {'channel': token},
    fragment: '',
  );
}
