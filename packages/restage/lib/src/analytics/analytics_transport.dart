import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:restage_shared/restage_shared.dart';

import '../secure_transport.dart';

/// Batched, fail-safe transport that ships [AnalyticsEvent]s to the ingest
/// endpoint.
///
/// Design guarantees:
/// - **Never throws into host code.** [enqueue] only buffers; [flush] catches
///   every error and reports it through `onError` (a log hook).
/// - **Bounded.** The buffer is capped at [maxBufferSize]; the oldest events are
///   dropped beyond it, so a long offline period can never grow memory without
///   bound.
/// - **At-least-once with safe retry.** A transient failure (network error or
///   5xx) retains the batch for the next flush; the ingest path dedups on
///   `eventId`, so a resend is safe. A 4xx (a malformed/poison batch the server
///   will never accept) is dropped to avoid a redelivery loop.
/// - **Config-driven endpoint.** [endpointUrl] is supplied by the host's
///   configuration; no backend host is baked into the SDK.
class AnalyticsTransport {
  /// Creates a transport targeting [endpointUrl], authenticating with the
  /// public [apiKey]. [httpClient] is the test seam.
  AnalyticsTransport({
    required this.endpointUrl,
    required this.apiKey,
    http.Client? httpClient,
    this.batchSize = 20,
    this.maxBufferSize = 200,
    void Function(Object error, StackTrace stackTrace)? onError,
  })  : _client = httpClient ?? http.Client(),
        _onError = onError ?? _swallow {
    // The analytics stream carries the public API key and event data — require
    // TLS (loopback excepted for local development).
    assertSecureUrl(endpointUrl, label: 'analytics endpoint');
  }

  /// The full ingest URL (e.g. `https://api.example.com/analytics/events`).
  final String endpointUrl;

  /// The public API key (`rs_pk_*`) sent as the bearer token.
  final String apiKey;

  /// Auto-flush once the buffer reaches this many events.
  final int batchSize;

  /// Hard cap on buffered events; the oldest are dropped beyond it.
  final int maxBufferSize;

  final http.Client _client;
  final void Function(Object, StackTrace) _onError;
  final List<AnalyticsEvent> _buffer = <AnalyticsEvent>[];
  bool _flushing = false;

  /// Buffers [event] and triggers a fire-and-forget [flush] once the buffer
  /// reaches [batchSize]. Synchronous and non-throwing.
  void enqueue(AnalyticsEvent event) {
    _buffer.add(event);
    final overflow = _buffer.length - maxBufferSize;
    if (overflow > 0) {
      _buffer.removeRange(0, overflow);
    }
    if (_buffer.length >= batchSize) {
      unawaited(flush());
    }
  }

  /// Sends the buffered batch. Never throws; clears the sent events on success,
  /// retains them on a transient failure, and drops them on a 4xx.
  Future<void> flush() async {
    if (_flushing || _buffer.isEmpty) return;
    _flushing = true;
    final batchLength = _buffer.length;
    final body = jsonEncode(<String, Object?>{
      'events': <Object?>[for (final e in _buffer) e.toJson()],
    });
    try {
      final response = await _client.post(
        Uri.parse(endpointUrl),
        headers: <String, String>{
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: body,
      );
      final status = response.statusCode;
      if (status >= 200 && status < 300) {
        _dropSent(batchLength);
      } else if (status >= 400 && status < 500) {
        // The server will never accept this batch — drop it rather than loop.
        _dropSent(batchLength);
        _onError(
          StateError('analytics ingest rejected the batch ($status)'),
          StackTrace.current,
        );
      } else {
        // 5xx / unexpected — retain for retry on the next flush.
        _onError(
          StateError('analytics ingest transient failure ($status)'),
          StackTrace.current,
        );
      }
    } on Object catch (error, stackTrace) {
      // Network or encode failure — retain for retry; never surface to the host.
      _onError(error, stackTrace);
    } finally {
      _flushing = false;
    }
  }

  void _dropSent(int batchLength) {
    // Remove only the prefix that was sent; events enqueued during the in-flight
    // POST are appended after and survive.
    final removable = batchLength.clamp(0, _buffer.length);
    _buffer.removeRange(0, removable);
  }

  /// Closes the underlying client.
  void close() => _client.close();

  static void _swallow(Object _, StackTrace __) {}
}
