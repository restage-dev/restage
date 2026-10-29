import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' show sha256;
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import '../resolver/placement_fallback_log.dart'
    show acceptedApiKeyEpoch, noteAcceptedApiKey, noteRefusedApiKey;
import '../retry_after.dart';
import 'surface_delivery_receipt_batch.dart';
import 'surface_delivery_receipt_journal.dart';
import '../restage_rpc_client/uuid_v4.dart';

/// How often accumulated receipts are posted.
const Duration kSurfaceDeliveryReceiptFlushInterval = Duration(seconds: 30);

/// The waits before posting again after the service refuses the key.
const List<Duration> kSurfaceDeliveryReceiptRefusalRetries = [
  Duration(seconds: 5),
  Duration(seconds: 15),
  Duration(seconds: 45),
];

/// The route receipts are posted to, under the configured service origin.
const String kSurfaceDeliveryReceiptPath = '/sdk/v1/delivery-receipts';

/// The largest body the route accepts.
const int kSurfaceDeliveryReceiptMaximumPostBytes = 64 * 1024;

/// The most unacknowledged posts kept; the oldest beyond it are dropped.
const int kSurfaceDeliveryReceiptMaximumJournaledPosts = 200;

/// The most receipts the route accepts in one body.
const int kSurfaceDeliveryReceiptMaximumPostReceipts = 500;

/// Posts drained receipts to the service on app pause, and every 30 seconds
/// while a receipt-observing surface is mounted. Receipts the service has not
/// acknowledged are journaled, so a killed process posts them at next launch.
final class SurfaceDeliveryReceiptUploader {
  SurfaceDeliveryReceiptUploader._();

  static SurfaceDeliveryReceiptUploader instance =
      SurfaceDeliveryReceiptUploader._();

  /// Cancels timers, detaches the current uploader, and installs a fresh one.
  @internal
  static void debugReset() {
    instance._close();
    instance = SurfaceDeliveryReceiptUploader._()
      ..debugJournal = MemorySurfaceDeliveryReceiptJournal();
  }

  /// Test seam for the HTTP client; production constructs one on first use.
  http.Client? debugHttpClient;

  /// Test seam for the journal; production keeps it in app support storage.
  SurfaceDeliveryReceiptJournal? debugJournal;

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
  String? _fingerprint;

  /// Bumped on every change of key or origin; a payload posts only under the
  /// generation it was drained in.
  int _generation = 0;
  bool _configured = false;
  bool _enabled = false;
  bool _closed = false;
  http.Client? _client;
  SurfaceDeliveryReceiptJournal? _journal;
  Timer? _periodic;
  Timer? _retryTimer;
  Future<void>? _inFlight;
  int _mounted = 0;

  /// Posts not yet acknowledged, oldest first; each resends unchanged.
  List<SurfaceDeliveryReceiptPost> _posts = <SurfaceDeliveryReceiptPost>[];

  /// Journaled receipts an earlier process had not yet put in a post.
  List<String> _unbatched = <String>[];
  bool _retried = false;
  int _refusals = 0;

  /// The key stayed refused through every retry; nothing posts under it
  /// again in this process.
  bool _keyRefused = false;

  /// The acceptance count when the key was given up; any later acceptance,
  /// on any route, lifts the stop.
  int _refusedAtEpoch = 0;

  Future<void> _restored = Future<void>.value();

  /// Whether an enabled configuration has read the journal in this process.
  bool _journalRead = false;
  Future<void>? _saving;
  bool _saveAgain = false;

  bool get isEnabled => _enabled;

  bool get hasPendingRetry => _posts.isNotEmpty;

  bool get hasPeriodicTimer => _periodic != null;

  bool get hasRetryTimer => _retryTimer != null;

  SurfaceDeliveryReceiptJournal get _store =>
      _journal ??= debugJournal ?? createSurfaceDeliveryReceiptJournal();

  /// A receipt-observing surface mounted; the periodic flush runs while any is.
  void retain() {
    _mounted += 1;
    _armPeriodic();
  }

  /// A receipt-observing surface unmounted; the last one stops every timer.
  /// Unacknowledged receipts stay journaled for the next flush.
  void release() {
    if (_mounted > 0) _mounted -= 1;
    if (_mounted > 0) return;
    _periodic?.cancel();
    _periodic = null;
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  /// Binds the uploader to the configured service and public key.
  ///
  /// Receipts queued under one key never post under another: a change of key
  /// or origin retires whatever is queued, counted as dropped. The first
  /// enabled configuration in a process posts what an earlier one journaled.
  void configure({
    required String? baseUrl,
    required String? apiKey,
    required bool enabled,
  }) {
    final batch = SurfaceDeliveryReceiptBatch.instance;
    if (_configured && (baseUrl != _baseUrl || apiKey != _apiKey)) {
      _generation += 1;
      _cancelTimers();
      batch.countDropped(batch.retire() + _discardPending());
      _refusals = 0;
      _keyRefused = false;
    }
    _configured = true;
    _baseUrl = baseUrl;
    _apiKey = apiKey;
    _enabled = enabled && baseUrl != null && apiKey != null;
    _fingerprint = _enabled
        ? sha256.convert(utf8.encode('$baseUrl\n$apiKey')).toString()
        : null;
    batch.enabled = _enabled;
    batch.onAppended = _enabled ? _armPeriodic : null;
    batch.onClosed = _enabled ? _scheduleSave : null;
    if (!_enabled) {
      _cancelTimers();
      batch.countDropped(_discardPending());
      // Receipts turned off leave nothing on the device; a configuration still
      // waiting for its key keeps the journal for that key.
      if (!enabled) {
        _journalRead = true;
        // After any write still in flight, so that write cannot restore it.
        final saving = _saving ?? Future<void>.value();
        unawaited(saving.catchError((Object _) {}).then(
              (_) => _store.write(
                (fingerprint: '', posts: const [], receipts: const []),
              ),
            ));
      }
      return;
    }
    // The first enabled configuration takes back the journal; a keyless one
    // before it never wipes it.
    if (!_journalRead) {
      _journalRead = true;
      _restored = _restore();
    } else {
      _scheduleSave();
    }
  }

  /// Takes back what an earlier process journaled under the same key.
  Future<void> _restore() async {
    final fingerprint = _fingerprint;
    final generation = _generation;
    final stored = await _store.read();
    // A reconfiguration during the read owns the queue now.
    if (stored == null || fingerprint == null || generation != _generation) {
      return;
    }
    if (stored.fingerprint != fingerprint) {
      await _store.write((fingerprint: fingerprint, posts: [], receipts: []));
      return;
    }
    _posts = [...stored.posts, ..._posts];
    _unbatched = [...stored.receipts, ..._unbatched];
    unawaited(flush());
  }

  /// Drains the batch and posts it with anything still unacknowledged.
  ///
  /// While a retry is parked, its deadline wins and this is a no-op; the
  /// retry timer posts with whatever has accumulated since.
  Future<void> flush() {
    if (_retryTimer != null) return Future<void>.value();
    return _inFlight ??= _flush().whenComplete(() {
      _inFlight = null;
    });
  }

  Future<void> _flush() async {
    await _restored;
    final batch = SurfaceDeliveryReceiptBatch.instance;
    final generation = _generation;
    final device = await batch.device();
    // From the drain to the pending list in one step, so a save never sees
    // receipts that are in neither.
    final payload = batch.drainFor(device);
    if (_closed || !_enabled) return;
    if (_keyRefused && acceptedApiKeyEpoch != _refusedAtEpoch) {
      _keyRefused = false;
      _refusals = 0;
    }
    if (_keyRefused) {
      batch.countDropped(payload.presentations + payload.dropped);
      return;
    }
    if (generation != _generation) {
      batch.countDropped(payload.presentations + payload.dropped);
      return;
    }
    // New receipts go in fresh posts; unacknowledged ones resend unchanged.
    _posts = [
      ..._posts,
      ..._batched(
        _merged([
          ..._unbatched,
          for (final entry in payload.entries())
            jsonEncode(entry.receipt.toJson(entry.count)),
        ]),
        payload.dropped,
      ),
    ];
    _unbatched = <String>[];
    if (_posts.length > kSurfaceDeliveryReceiptMaximumJournaledPosts) {
      final excess =
          _posts.length - kSurfaceDeliveryReceiptMaximumJournaledPosts;
      for (final post in _posts.take(excess)) {
        batch.countDropped(_presentations(post.receipts) + post.dropped);
      }
      _posts = _posts.sublist(excess);
    }
    if (_posts.isEmpty) {
      _periodic?.cancel();
      _periodic = null;
      return;
    }
    // A post's id reaches the journal before the post is sent, so a resend
    // after a kill reuses it.
    await _saved();
    if (_closed || generation != _generation) return;
    await _post(batch, generation);
    _scheduleSave();
  }

  /// Completes once the journal holds the queue as it is now, or once a
  /// write has taken longer than [_journalWait]; a slow disk never holds
  /// receipts back.
  Future<void> _saved() async {
    _scheduleSave();
    for (var saving = _saving; saving != null; saving = _saving) {
      try {
        await saving.timeout(_journalWait);
      } on Object {
        return;
      }
    }
  }

  static const Duration _journalWait = Duration(seconds: 2);

  /// Posts the queue in order. A refused post is dropped alone; when the
  /// service fails or does not answer, the queue stays for a retry.
  Future<void> _post(SurfaceDeliveryReceiptBatch batch, int generation) async {
    final baseUrl = _baseUrl;
    final apiKey = _apiKey;
    if (baseUrl == null || apiKey == null) return;
    while (_posts.isNotEmpty) {
      if (generation != _generation) return;
      final http.Response response;
      try {
        response = await (_client ??= debugHttpClient ?? http.Client()).post(
          Uri.parse('$baseUrl$kSurfaceDeliveryReceiptPath'),
          headers: <String, String>{
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: _body(_posts.first),
        );
      } on Object {
        if (generation == _generation) _retryLater(_spreadRetryDelay());
        return;
      }
      if (_closed || generation != _generation) return;
      final status = response.statusCode;
      if (status == 429) {
        _retryLater(retryAfterDelay(response.headers['retry-after']));
        return;
      }
      // A key minted moments ago is refused until the service publishes it,
      // so a refusal is retried before the queue is given up.
      if (status == 401) {
        noteRefusedApiKey(Uri.parse('$baseUrl$kSurfaceDeliveryReceiptPath'));
        if (_refusals < kSurfaceDeliveryReceiptRefusalRetries.length) {
          _retryRefused(kSurfaceDeliveryReceiptRefusalRetries[_refusals++]);
        } else {
          _keyRefused = true;
          _refusedAtEpoch = acceptedApiKeyEpoch;
          batch.countDropped(_discardPending());
        }
        return;
      }
      // An organization the service is not serving now may be served again;
      // the queue stays journaled for the next flush.
      if (status == 403) return;
      // The service may answer later; the queue stays journaled.
      if (status == 408 || status >= 500) {
        _retryLater(_spreadRetryDelay());
        return;
      }
      _refusals = 0;
      if (status >= 200 && status < 300) noteAcceptedApiKey();
      final accepted = (status >= 200 && status < 300) || status == 404;
      if (!accepted) {
        final refused = _posts.first;
        batch.countDropped(_presentations(refused.receipts) + refused.dropped);
      }
      _posts = _posts.sublist(1);
      _retried = false;
    }
  }

  void _retryRefused(Duration delay) {
    _retryTimer?.cancel();
    _retryTimer = timerFactory(delay, () {
      _retryTimer = null;
      unawaited(flush());
    });
  }

  /// The app came back to the foreground: a key given up earlier is tried
  /// again.
  void onAppResumed() {
    _keyRefused = false;
    _refusals = 0;
  }

  /// Retries once on a timer while a surface is mounted; otherwise what is
  /// pending waits for the next flush.
  void _retryLater(Duration delay) {
    if (_closed || !_enabled || _mounted == 0 || _retried) {
      _retried = false;
      return;
    }
    _retried = true;
    _retryTimer?.cancel();
    _retryTimer = timerFactory(delay, () {
      _retryTimer = null;
      unawaited(flush());
    });
  }

  /// Journals every unacknowledged receipt; writes coalesce.
  void _scheduleSave() {
    if (_fingerprint == null || _closed) return;
    if (_saving != null) {
      _saveAgain = true;
      return;
    }
    _saving = _save().whenComplete(() {
      _saving = null;
      if (_saveAgain) {
        _saveAgain = false;
        _scheduleSave();
      }
    });
  }

  Future<void> _save() async {
    await _restored;
    final batch = SurfaceDeliveryReceiptBatch.instance;
    final device = await batch.device();
    final fingerprint = _fingerprint;
    if (fingerprint == null) return;
    // One synchronous snapshot of the queue and what is closed.
    await _store.write((
      fingerprint: fingerprint,
      posts: _posts,
      receipts: [
        ..._unbatched,
        for (final entry in batch.closedEntries(device))
          jsonEncode(entry.receipt.toJson(entry.count)),
      ],
    ));
  }

  /// [receipts] with identical receipts coalesced, each count bounded.
  static List<String> _merged(List<String> receipts) {
    final counts = <String, int>{};
    for (final receipt in receipts) {
      final json = (jsonDecode(receipt) as Map).cast<String, Object?>();
      final count = json.remove('count');
      final key = jsonEncode(json);
      counts[key] = (counts[key] ?? 0) + (count is int ? count : 1);
    }
    return [
      for (final MapEntry(:key, value: count) in counts.entries)
        for (var left = count;
            left > 0;
            left -= kSurfaceDeliveryReceiptMaximumCount)
          jsonEncode({
            ...(jsonDecode(key) as Map).cast<String, Object?>(),
            'count': left > kSurfaceDeliveryReceiptMaximumCount
                ? kSurfaceDeliveryReceiptMaximumCount
                : left,
          }),
    ];
  }

  /// Forgets what is queued and returns the presentations it held.
  int _discardPending() {
    var presentations = _presentations(_unbatched);
    for (final post in _posts) {
      presentations += _presentations(post.receipts) + post.dropped;
    }
    _posts = <SurfaceDeliveryReceiptPost>[];
    _unbatched = <String>[];
    _retried = false;
    return presentations;
  }

  static int _presentations(Iterable<String> receipts) {
    var presentations = 0;
    for (final receipt in receipts) {
      presentations += switch (jsonDecode(receipt)) {
        {'count': final int count} => count,
        _ => 1,
      };
    }
    return presentations;
  }

  /// [receipts] split into posts the route accepts, each under a new id,
  /// with [dropped] reported in the first.
  static List<SurfaceDeliveryReceiptPost> _batched(
    List<String> receipts,
    int dropped,
  ) {
    final posts = <SurfaceDeliveryReceiptPost>[];
    var rest = receipts;
    while (rest.isNotEmpty || (posts.isEmpty && dropped > 0)) {
      final batchId = generateUuidV4();
      final first = posts.isEmpty ? dropped : 0;
      var size = utf8
          .encode(_body((batchId: batchId, receipts: const [], dropped: first)))
          .length;
      var taken = 0;
      for (final json in rest) {
        if (taken == kSurfaceDeliveryReceiptMaximumPostReceipts) break;
        final growth = utf8.encode(json).length + (taken == 0 ? 0 : 1);
        if (taken > 0 &&
            size + growth > kSurfaceDeliveryReceiptMaximumPostBytes) {
          break;
        }
        size += growth;
        taken += 1;
      }
      posts.add((
        batchId: batchId,
        receipts: rest.sublist(0, taken),
        dropped: first,
      ));
      rest = rest.sublist(taken);
    }
    return posts;
  }

  /// The wire form of [post].
  static String _body(SurfaceDeliveryReceiptPost post) =>
      '{"batchId":${jsonEncode(post.batchId)},'
      '"receipts":[${post.receipts.join(',')}],"dropped":${post.dropped}}';

  /// The flush interval spread by a quarter either way.
  Duration _spreadRetryDelay() {
    final spread = 0.75 + random.nextDouble() * 0.5;
    return Duration(
      milliseconds:
          (kSurfaceDeliveryReceiptFlushInterval.inMilliseconds * spread)
              .round(),
    );
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
  }

  void _close() {
    _closed = true;
    _enabled = false;
    _cancelTimers();
  }
}
