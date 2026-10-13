import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import '../retry_after.dart';
import 'surface_delivery_receipt_batch.dart';

/// How often accumulated receipts are posted.
const Duration kSurfaceDeliveryReceiptFlushInterval = Duration(seconds: 30);

/// The route receipts are posted to, under the configured service origin.
const String kSurfaceDeliveryReceiptPath = '/sdk/v1/delivery-receipts';

/// The largest body the route accepts.
const int kSurfaceDeliveryReceiptMaximumPostBytes = 64 * 1024;

/// The most receipts the route accepts in one body.
const int kSurfaceDeliveryReceiptMaximumPostReceipts = 500;

/// Posts drained receipts to the service on app pause, and every 30 seconds
/// while a receipt-observing surface is mounted.
final class SurfaceDeliveryReceiptUploader {
  SurfaceDeliveryReceiptUploader._();

  static SurfaceDeliveryReceiptUploader instance =
      SurfaceDeliveryReceiptUploader._();

  /// Cancels timers, detaches the current uploader, and installs a fresh one.
  @internal
  static void debugReset() {
    instance._close();
    instance = SurfaceDeliveryReceiptUploader._();
  }

  /// Test seam for the HTTP client; production constructs one on first use.
  http.Client? debugHttpClient;

  /// Test seam for the retry timer.
  Timer Function(Duration delay, void Function() callback) timerFactory =
      (delay, callback) => Timer(delay, callback);

  /// Test seam for the periodic flush timer.
  Timer Function(Duration period, void Function() callback)
      periodicTimerFactory =
      (period, callback) => Timer.periodic(period, (_) => callback());

  /// Spreads the transport-error retry so a fleet does not retry in step.
  Random random = Random();

  String? _baseUrl;
  String? _apiKey;

  /// Bumped on every change of key or origin; a payload posts only under the
  /// generation it was drained in.
  int _generation = 0;
  bool _configured = false;
  bool _enabled = false;
  bool _closed = false;
  http.Client? _client;
  Timer? _periodic;
  Timer? _retryTimer;
  SurfaceDeliveryReceiptPayload? _retry;
  Future<void>? _inFlight;
  int _mounted = 0;

  bool get isEnabled => _enabled;

  bool get hasPendingRetry => _retry != null;

  bool get hasPeriodicTimer => _periodic != null;

  bool get hasRetryTimer => _retryTimer != null;

  /// A receipt-observing surface mounted; the periodic flush runs while any is.
  void retain() {
    _mounted += 1;
    _armPeriodic();
  }

  /// A receipt-observing surface unmounted; the last one stops every timer.
  void release() {
    if (_mounted > 0) _mounted -= 1;
    if (_mounted > 0) return;
    _periodic?.cancel();
    _periodic = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    final parked = _retry;
    _retry = null;
    if (parked != null) _drop(parked, SurfaceDeliveryReceiptBatch.instance);
  }

  /// Binds the uploader to the configured service and public key.
  ///
  /// Receipts queued under one key never post under another: a change of key
  /// or origin retires whatever is queued, counted as dropped.
  void configure({
    required String? baseUrl,
    required String? apiKey,
    required bool enabled,
  }) {
    final batch = SurfaceDeliveryReceiptBatch.instance;
    if (_configured && (baseUrl != _baseUrl || apiKey != _apiKey)) {
      _generation += 1;
      _cancelTimers();
      batch.countDropped(batch.retire());
    }
    _configured = true;
    _baseUrl = baseUrl;
    _apiKey = apiKey;
    _enabled = enabled && baseUrl != null && apiKey != null;
    batch.enabled = _enabled;
    batch.onAppended = _enabled ? _armPeriodic : null;
    if (!_enabled) _cancelTimers();
  }

  /// Drains the batch and posts it, honoring one retry per payload.
  ///
  /// While a rate-limited retry is parked, its deadline wins and this is a
  /// no-op; the retry timer posts the parked payload with whatever has
  /// accumulated since.
  Future<void> flush() {
    if (_retryTimer != null) return Future<void>.value();
    return _inFlight ??= _flush().whenComplete(() {
      _inFlight = null;
    });
  }

  Future<void> _flush() async {
    final batch = SurfaceDeliveryReceiptBatch.instance;
    final generation = _generation;
    final retry = _retry;
    _retry = null;
    final payload = await batch.drain();
    if (_closed || !_enabled) return;
    var canRetry = true;
    if (retry != null) {
      canRetry = false;
      payload.absorb(retry);
    }
    if (generation != _generation) {
      _drop(payload, batch);
      return;
    }
    if (payload.isEmpty) {
      _periodic?.cancel();
      _periodic = null;
      return;
    }
    await _post(payload, batch, generation, canRetry: canRetry);
  }

  /// Posts [payload] in bodies the route accepts, stopping at the first
  /// failure; what remains is re-queued or dropped as a whole.
  Future<void> _post(
    SurfaceDeliveryReceiptPayload payload,
    SurfaceDeliveryReceiptBatch batch,
    int generation, {
    required bool canRetry,
  }) async {
    final baseUrl = _baseUrl;
    final apiKey = _apiKey;
    if (baseUrl == null || apiKey == null) return;
    var remaining = payload.entries();
    var dropped = payload.dropped;
    while (remaining.isNotEmpty || dropped > 0) {
      if (generation != _generation) {
        _drop(SurfaceDeliveryReceiptPayload.fromEntries(remaining, dropped),
            batch);
        return;
      }
      final chunk = _chunk(remaining, dropped);
      final http.Response response;
      try {
        response = await (_client ??= debugHttpClient ?? http.Client()).post(
          Uri.parse('$baseUrl$kSurfaceDeliveryReceiptPath'),
          headers: <String, String>{
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: chunk.body,
        );
      } on Object {
        _requeue(
          SurfaceDeliveryReceiptPayload.fromEntries(remaining, dropped),
          batch,
          generation,
          canRetry,
          _spreadRetryDelay(),
        );
        return;
      }
      if (_closed) return;
      final status = response.statusCode;
      if (status == 429) {
        _requeue(
          SurfaceDeliveryReceiptPayload.fromEntries(remaining, dropped),
          batch,
          generation,
          canRetry,
          retryAfterDelay(response.headers['retry-after']),
        );
        return;
      }
      final accepted = (status >= 200 && status < 300) || status == 404;
      if (!accepted) {
        _drop(SurfaceDeliveryReceiptPayload.fromEntries(remaining, 0), batch);
        return;
      }
      remaining = remaining.sublist(chunk.taken);
      dropped = 0;
    }
  }

  /// The longest prefix of [entries] that encodes under the route's limits,
  /// always at least one entry so a post can make progress.
  static _Chunk _chunk(
    List<SurfaceDeliveryReceiptEntry> entries,
    int dropped,
  ) {
    final encoded = <String>[];
    const head = '{"receipts":[';
    final tail = '],"dropped":$dropped}';
    var size = head.length + tail.length;
    for (final entry in entries) {
      if (encoded.length == kSurfaceDeliveryReceiptMaximumPostReceipts) break;
      final json = jsonEncode(entry.receipt.toJson(entry.count));
      final growth = utf8.encode(json).length + (encoded.isEmpty ? 0 : 1);
      if (encoded.isNotEmpty &&
          size + growth > kSurfaceDeliveryReceiptMaximumPostBytes) {
        break;
      }
      encoded.add(json);
      size += growth;
    }
    return _Chunk(
      taken: encoded.length,
      body: '$head${encoded.join(',')}$tail',
    );
  }

  /// The flush interval spread by a quarter either way.
  Duration _spreadRetryDelay() {
    final spread = 0.75 + random.nextDouble() * 0.5;
    return Duration(
      milliseconds:
          (kSurfaceDeliveryReceiptFlushInterval.inMilliseconds * spread)
              .round(),
    );
  }

  void _requeue(
    SurfaceDeliveryReceiptPayload payload,
    SurfaceDeliveryReceiptBatch batch,
    int generation,
    bool canRetry,
    Duration delay,
  ) {
    if (_closed ||
        !canRetry ||
        !_enabled ||
        _mounted == 0 ||
        generation != _generation) {
      _drop(payload, batch);
      return;
    }
    _retry = payload;
    _retryTimer?.cancel();
    _retryTimer = timerFactory(delay, () {
      _retryTimer = null;
      unawaited(flush());
    });
  }

  void _drop(
    SurfaceDeliveryReceiptPayload payload,
    SurfaceDeliveryReceiptBatch batch,
  ) {
    batch.countDropped(payload.presentations + payload.dropped);
  }

  void _armPeriodic() {
    if (!_enabled ||
        _closed ||
        _mounted == 0 ||
        _periodic != null ||
        !SurfaceDeliveryReceiptBatch.instance.hasReceipts) {
      return;
    }
    _periodic = periodicTimerFactory(
      kSurfaceDeliveryReceiptFlushInterval,
      () => unawaited(flush()),
    );
  }

  void _cancelTimers() {
    _periodic?.cancel();
    _periodic = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    final parked = _retry;
    _retry = null;
    if (parked != null) _drop(parked, SurfaceDeliveryReceiptBatch.instance);
  }

  void _close() {
    _closed = true;
    _enabled = false;
    _cancelTimers();
  }
}

final class _Chunk {
  const _Chunk({required this.taken, required this.body});

  final int taken;
  final String body;
}
