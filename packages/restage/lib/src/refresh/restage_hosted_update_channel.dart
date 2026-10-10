import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';
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
final class RestageHostedUpdateChannel implements DeliveryUpdateChannel {
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
  Stream<SurfaceUpdate> watch(SurfaceRef surface) =>
      _HostedWatch<SurfaceUpdate>(
        update: SurfaceUpdate(surface),
        fetchStamp: () async {
          final stamp = await _rpcClient.fetchSurfaceStamp(
              surfaceType: surface.surfaceType, surfaceSlug: surface.slug);
          return switch (stamp) {
            SurfaceStamp() =>
              _WatchStamp(identity: stamp.version, token: stamp.watchChannel),
            SurfaceStampRateLimited() =>
              _WatchStamp(retry: true, retryAfter: stamp.retryAfter),
            _ => const _WatchStamp(retry: true),
          };
        },
        edgeUrl: _edgeUrl,
        reconnectBaseDelay: _reconnectBaseDelay,
        random: _random,
      ).stream;

  @override
  Stream<DeliveryPolicyScopeV1> watchDelivery(
    DeliveryPolicyScopeV1 scope, {
    PlacementDeliveryWatchV1? watch,
    Future<PlacementRefreshProbeV1> Function()? reconnectProbe,
  }) {
    var firstStamp = true;
    var hasAuthority = watch != null;
    return _HostedWatch<DeliveryPolicyScopeV1>(
      update: scope,
      initialIdentity: watch?.decisionIdentityDigest,
      fetchStamp: () async {
        if (firstStamp) {
          firstStamp = false;
          if (watch != null) return _deliveryStamp(scope, watch);
        }
        final probe = await reconnectProbe?.call() ??
            const PlacementRefreshProbeV1.unavailable();
        final stamp = switch (probe) {
          PlacementRefreshRateLimitedV1() =>
            _WatchStamp(retry: true, retryAfter: probe.retryAfter),
          PlacementRefreshUnchangedV1(watch: final renewed?)
              when renewed.decisionIdentityDigest ==
                  probe.decisionIdentityDigest =>
            _deliveryStamp(scope, renewed, requiresResolution: !hasAuthority),
          _ => const _WatchStamp(retry: true, requiresResolution: true),
        };
        if (!stamp.retry) {
          hasAuthority = true;
        }
        return stamp;
      },
      edgeUrl: _edgeUrl,
      reconnectBaseDelay: _reconnectBaseDelay,
      random: _random,
    ).stream;
  }
}

_WatchStamp _deliveryStamp(
    DeliveryPolicyScopeV1 scope, PlacementDeliveryWatchV1 watch,
    {bool requiresResolution = false}) {
  for (final channel in watch.channels) {
    if (channel.scope == scope) {
      return _WatchStamp(
          identity: watch.decisionIdentityDigest,
          token: channel.token,
          requiresResolution: requiresResolution);
    }
  }
  return const _WatchStamp(retry: true, requiresResolution: true);
}

/// The close code the edge sends when a watch token expires.
const _tokenExpiredCloseCode = 4401;

/// The longest random delay before reconnecting after a token expiry.
const _maxExpiryReconnectDelay = Duration(seconds: 5);

/// Frames above this many characters are refused.
const _maxFrameLength = 64 * 1024;

final class _HostedWatch<T> {
  _HostedWatch({
    required this.update,
    required this.fetchStamp,
    required this.edgeUrl,
    required this.reconnectBaseDelay,
    required this.random,
    Object? initialIdentity,
  }) : _lastSeenIdentity = initialIdentity {
    controller = StreamController<T>(
      onListen: _onListen,
      onCancel: _onCancel,
    );
  }

  final T update;
  final Future<_WatchStamp> Function() fetchStamp;
  final Uri edgeUrl;
  final Duration reconnectBaseDelay;
  final Random random;

  late final StreamController<T> controller;
  StreamSubscription<Object?>? _socketSubscription;
  WebSocketChannel? _socket;
  Completer<void>? _socketDone;
  Timer? _backoffTimer;
  Completer<void>? _backoffDone;
  bool _stopped = false;
  Object? _lastSeenIdentity;

  Stream<T> get stream => controller.stream;

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
    Duration? retryAfter;
    var tokenExpired = false;
    while (!_stopped) {
      if (tokenExpired) {
        // Spread the reconnects of sockets that expire together.
        await _wait(_maxExpiryReconnectDelay * random.nextDouble());
        if (_stopped) return;
      } else if (reconnectAttempt > 0) {
        final backoff = _backoffDelay(reconnectAttempt);
        await _wait(
          retryAfter != null && retryAfter > backoff ? retryAfter : backoff,
        );
        retryAfter = null;
        if (_stopped) return;
      }
      tokenExpired = false;

      try {
        final stamp = await fetchStamp();
        if (_stopped) return;
        if (stamp.retry) {
          if (stamp.requiresResolution) controller.add(update);
          retryAfter = stamp.retryAfter;
          reconnectAttempt++;
          continue;
        }

        final token = stamp.token;
        if (token == null) return;

        final previousIdentity = _lastSeenIdentity;
        _lastSeenIdentity = stamp.identity;
        if (stamp.requiresResolution ||
            (previousIdentity != null && stamp.identity != previousIdentity)) {
          controller.add(update);
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
        tokenExpired = socket.closeCode == _tokenExpiredCloseCode;
      } catch (_) {
        // Transport and decoding failures are retryable while the surface is
        // still watched. They never reach the stream as errors.
      } finally {
        await _closeSocket();
      }
      // An expired token is routine: reconnect soon with a fresh stamp.
      reconnectAttempt = tokenExpired ? 0 : reconnectAttempt + 1;
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
    if (_stopped) return;
    final length = switch (frame) {
      final String text => text.length,
      final List<int> bytes => bytes.length,
      _ => 0,
    };
    if (length > _maxFrameLength) {
      // An oversized frame fails the connection; the loop backs off.
      final done = _socketDone;
      if (done != null && !done.isCompleted) done.complete();
      return;
    }
    if (frame is! String) return;
    try {
      final message = jsonDecode(frame);
      if (message is Map && message['type'] == 'surface_update') {
        controller.add(update);
      }
    } catch (_) {
      // Ignore malformed or unrelated frames.
    }
  }

  Future<void> _wait(Duration delay) {
    if (_stopped) return Future<void>.value();
    final done = Completer<void>();
    _backoffDone = done;
    _backoffTimer = Timer(delay, () {
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

final class _WatchStamp {
  const _WatchStamp({
    this.identity,
    this.token,
    this.retry = false,
    this.retryAfter,
    this.requiresResolution = false,
  });

  final Object? identity;
  final String? token;
  final bool retry;
  final Duration? retryAfter;
  final bool requiresResolution;
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
