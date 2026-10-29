import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:restage/src/delivery/surface_delivery_receipt.dart';
import 'package:restage/src/delivery/surface_delivery_receipt_batch.dart';
import 'package:restage/src/delivery/surface_delivery_receipt_uploader.dart';
import 'package:restage/src/resolver/placement_fallback_log.dart';
import 'package:restage/src/resolver/surface_resolution_report.dart';
import 'package:restage_shared/restage_shared.dart' show Surface;

final class _FakeTimer implements Timer {
  _FakeTimer(this.delay, this.callback);

  final Duration delay;
  final void Function() callback;
  bool cancelled = false;

  @override
  void cancel() => cancelled = true;

  @override
  bool get isActive => !cancelled;

  @override
  int get tick => 0;
}

void main() {
  late SurfaceDeliveryReceiptUploader uploader;
  late SurfaceDeliveryReceiptBatch batch;
  late List<http.Request> requests;
  late List<_FakeTimer> retries;
  late List<_FakeTimer> periodics;
  late Future<http.Response> Function(http.Request request) answer;

  setUp(() {
    SurfaceDeliveryReceiptBatch.debugReset();
    SurfaceDeliveryReceiptUploader.debugReset();
    requests = <http.Request>[];
    retries = <_FakeTimer>[];
    periodics = <_FakeTimer>[];
    answer = (_) async => http.Response('', 204);
    uploader = SurfaceDeliveryReceiptUploader.instance
      ..debugHttpClient = MockClient((request) {
        requests.add(request);
        return answer(request);
      })
      ..timerFactory = ((delay, callback) {
        final timer = _FakeTimer(delay, callback);
        retries.add(timer);
        return timer;
      })
      ..periodicTimerFactory = ((period, callback) {
        final timer = _FakeTimer(period, callback);
        periodics.add(timer);
        return timer;
      })
      ..random = Random(7)
      ..configure(
        baseUrl: 'https://api.example.test',
        apiKey: 'rs_pk_test',
        enabled: true,
      )
      ..retain();
    batch = SurfaceDeliveryReceiptBatch.instance
      ..deviceSource = (() async => (platform: 'ios', appBuild: 7));
  });

  void present({String slug = 'pro'}) {
    batch
        .open(
          surfaceType: Surface.paywall,
          surfaceSlug: slug,
          publishedVersion: 3,
          source: SurfaceResolutionSource.fresh,
          reason: SurfaceDeliveryReceiptReason.none,
          routeId: '',
        )
        .painted(const Duration(milliseconds: 50));
  }

  Map<String, Object?> body(http.Request request) =>
      (jsonDecode(request.body) as Map).cast<String, Object?>();

  test('a 200 clears the drained batch', () async {
    present();
    answer = (_) async => http.Response('{}', 200);

    await uploader.flush();

    expect(requests, hasLength(1));
    final request = requests.single;
    expect(request.method, 'POST');
    expect(
      request.url.toString(),
      'https://api.example.test/sdk/v1/delivery-receipts',
    );
    expect(request.headers['Authorization'], 'Bearer rs_pk_test');
    expect(request.headers['Content-Type'], startsWith('application/json'));
    expect((await batch.drain()).isEmpty, isTrue);
    expect(uploader.hasPendingRetry, isFalse);
  });

  test('a refused key is retried, then named and given up', () async {
    final lines = <String>[];
    final previous = debugPrint;
    debugPrint = (message, {wrapWidth}) => lines.add(message ?? '');
    var now = DateTime.utc(2026);
    refusedApiKeyClock = () => now;
    addTearDown(() {
      debugPrint = previous;
      resetPlacementFallbackLog();
    });
    answer = (_) async => http.Response('{"error":"unauthorized"}', 401);

    present();
    await uploader.flush();
    for (final wait in kSurfaceDeliveryReceiptRefusalRetries) {
      expect(uploader.hasPendingRetry, isTrue);
      expect(retries.last.delay, wait);
      expect(lines, isEmpty);
      now = now.add(wait);
      retries.last.callback();
      await Future<void>.delayed(Duration.zero);
      await uploader.flush();
    }

    expect(requests, hasLength(4));
    expect(uploader.hasPendingRetry, isFalse);
    present(slug: 'later');
    await uploader.flush();
    expect(requests, hasLength(4), reason: 'a refused key posts nothing more');
    expect(lines, hasLength(1));
    expect(
        lines.single,
        startsWith(
            '[restage] the service at api.example.test refused the API key (HTTP 401).'));
  });

  Future<void> giveUpKey(void Function(DateTime) setNow) async {
    var now = DateTime.utc(2026);
    setNow(now);
    answer = (_) async => http.Response('{"error":"unauthorized"}', 401);
    present();
    await uploader.flush();
    for (final wait in kSurfaceDeliveryReceiptRefusalRetries) {
      now = now.add(wait);
      setNow(now);
      retries.last.callback();
      await Future<void>.delayed(Duration.zero);
      await uploader.flush();
    }
    expect(requests, hasLength(4));
  }

  test('a key accepted on another route lifts the receipts stop', () async {
    final previous = debugPrint;
    debugPrint = (message, {wrapWidth}) {};
    var now = DateTime.utc(2026);
    refusedApiKeyClock = () => now;
    addTearDown(() {
      debugPrint = previous;
      resetPlacementFallbackLog();
    });
    await giveUpKey((value) => now = value);

    answer = (_) async => http.Response('', 204);
    present(slug: 'blocked');
    await uploader.flush();
    expect(requests, hasLength(4), reason: 'the key is still given up');

    noteAcceptedApiKey();
    present(slug: 'after');
    await uploader.flush();
    expect(requests, hasLength(5));
  });

  test('an app resume lifts the receipts stop', () async {
    final previous = debugPrint;
    debugPrint = (message, {wrapWidth}) {};
    var now = DateTime.utc(2026);
    refusedApiKeyClock = () => now;
    addTearDown(() {
      debugPrint = previous;
      resetPlacementFallbackLog();
    });
    await giveUpKey((value) => now = value);

    answer = (_) async => http.Response('', 204);
    uploader.onAppResumed();
    present(slug: 'after');
    await uploader.flush();
    expect(requests, hasLength(5));
  });

  test('a key the service publishes during the retries is never named',
      () async {
    final lines = <String>[];
    final previous = debugPrint;
    debugPrint = (message, {wrapWidth}) => lines.add(message ?? '');
    addTearDown(() {
      debugPrint = previous;
      resetPlacementFallbackLog();
    });
    answer = (_) async => http.Response('{"error":"unauthorized"}', 401);

    present();
    await uploader.flush();
    expect(retries.last.delay, kSurfaceDeliveryReceiptRefusalRetries.first);
    answer = (_) async => http.Response('', 204);
    retries.last.callback();
    await Future<void>.delayed(Duration.zero);
    await uploader.flush();

    expect(requests, hasLength(2));
    expect(requests[1].body, requests[0].body);
    expect(uploader.hasPendingRetry, isFalse);
    expect(lines, isEmpty);
  });

  test('a 429 re-queues once and the retry after the delay succeeds', () async {
    present();
    answer = (_) async => http.Response('', 429, headers: {'retry-after': '5'});

    await uploader.flush();

    expect(requests, hasLength(1));
    expect(uploader.hasPendingRetry, isTrue);
    expect(retries, hasLength(1));
    expect(retries.single.delay, const Duration(seconds: 5));

    answer = (_) async => http.Response('', 204);
    retries.single.callback();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(requests, hasLength(2));
    expect(body(requests.last)['receipts'], hasLength(1));
    expect(uploader.hasPendingRetry, isFalse);
    expect((await batch.drain()).dropped, 0);
  });

  test('a second 429 keeps the receipts for the next flush', () async {
    present();
    present();
    answer = (_) async => http.Response('', 429, headers: {'retry-after': '5'});

    await uploader.flush();
    retries.single.callback();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(requests, hasLength(2));
    expect(uploader.hasPendingRetry, isTrue);
    expect(retries, hasLength(1));
    expect((await batch.drain()).dropped, 0);

    answer = (_) async => http.Response('', 204);
    await uploader.flush();
    expect(requests, hasLength(3));
    expect(
        ((body(requests.last)['receipts']! as List).single as Map)['count'], 2);
    expect(uploader.hasPendingRetry, isFalse);
  });

  test('a 404 drops silently with no retry', () async {
    present();
    answer = (_) async => http.Response('', 404);

    await uploader.flush();

    expect(requests, hasLength(1));
    expect(retries, isEmpty);
    expect(uploader.hasPendingRetry, isFalse);
    expect((await batch.drain()).dropped, 0);
  });

  test('a transport error re-queues once', () async {
    present();
    answer = (_) async => throw http.ClientException('offline');

    await uploader.flush();

    expect(requests, hasLength(1));
    expect(retries, hasLength(1));
    expect(
      retries.single.delay.inMilliseconds,
      inInclusiveRange(
        kSurfaceDeliveryReceiptFlushInterval.inMilliseconds * 3 ~/ 4,
        kSurfaceDeliveryReceiptFlushInterval.inMilliseconds * 5 ~/ 4,
      ),
    );

    answer = (_) async => http.Response('', 204);
    retries.single.callback();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(requests, hasLength(2));
    expect(uploader.hasPendingRetry, isFalse);
  });

  test('a retry resends its post unchanged; new receipts post apart', () async {
    present();
    answer = (_) async => throw http.ClientException('offline');
    await uploader.flush();
    present();
    answer = (_) async => http.Response('', 204);

    retries.single.callback();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(requests, hasLength(3));
    expect(requests[1].body, requests[0].body);
    expect(body(requests[2])['batchId'], isNot(body(requests[0])['batchId']));
    expect(
        ((body(requests[2])['receipts']! as List).single as Map)['count'], 1);
  });

  test('the body never carries a key beyond the closed set', () async {
    present();
    answer = (_) async => http.Response('', 204);

    await uploader.flush();

    final json = body(requests.single);
    expect(json.keys, unorderedEquals(['batchId', 'receipts', 'dropped']));
    expect(json['dropped'], 0);
    final receipt =
        ((json['receipts']! as List).single as Map).cast<String, Object?>();
    expect(
      receipt.keys,
      unorderedEquals([
        'surfaceType',
        'surfaceSlug',
        'publishedVersion',
        'source',
        'reason',
        'outcome',
        'platform',
        'appBuild',
        'routeId',
        'latencyBucket',
        'minute',
        'count',
      ]),
    );
  });

  test(
      'the periodic timer runs only while a surface is mounted and the batch '
      'has receipts', () async {
    uploader.release();
    present();
    expect(periodics, isEmpty);

    uploader.retain();
    expect(periodics, hasLength(1));
    expect(periodics.single.delay, kSurfaceDeliveryReceiptFlushInterval);

    await uploader.flush();
    expect(periodics.single.isActive, isTrue);
    await uploader.flush();
    expect(periodics.single.isActive, isFalse);
    expect(uploader.hasPeriodicTimer, isFalse);

    present();
    expect(periodics, hasLength(2));
    uploader.release();
    expect(periodics.last.isActive, isFalse);
    expect(uploader.hasPeriodicTimer, isFalse);

    present();
    expect(periodics, hasLength(2));
  });

  test('a parked rate-limited retry outlasts the periodic tick', () async {
    present();
    answer =
        (_) async => http.Response('', 429, headers: {'retry-after': '60'});

    await uploader.flush();
    expect(requests, hasLength(1));
    expect(retries.single.delay, const Duration(seconds: 60));

    answer = (_) async => http.Response('', 204);
    present();
    periodics.single.callback();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(requests, hasLength(1));
    await uploader.flush();
    expect(requests, hasLength(1));

    retries.single.callback();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(requests, hasLength(3));
    expect(requests[1].body, requests[0].body);
    expect(
        ((body(requests[2])['receipts']! as List).single as Map)['count'], 1);
    expect(uploader.hasPendingRetry, isFalse);
    expect(uploader.hasRetryTimer, isFalse);
  });

  test('the last release cancels a parked retry and keeps its receipts',
      () async {
    present();
    present();
    answer = (_) async => http.Response('', 429, headers: {'retry-after': '5'});
    await uploader.flush();
    expect(uploader.hasRetryTimer, isTrue);

    uploader.release();

    expect(uploader.hasRetryTimer, isFalse);
    expect(uploader.hasPendingRetry, isTrue);
    expect(retries.single.isActive, isFalse);
    expect((await batch.drain()).dropped, 0);
  });

  test('a reset cancels a parked retry and detaches the old uploader',
      () async {
    present();
    final gate = Completer<http.Response>();
    answer = (_) => gate.future;
    final inFlight = uploader.flush();
    await Future<void>.delayed(Duration.zero);
    expect(requests, hasLength(1));

    SurfaceDeliveryReceiptUploader.debugReset();
    SurfaceDeliveryReceiptBatch.debugReset();
    final replacement = SurfaceDeliveryReceiptBatch.instance
      ..enabled = true
      ..deviceSource = (() async => (platform: 'ios', appBuild: 7));
    replacement
        .open(
          surfaceType: Surface.paywall,
          surfaceSlug: 'after',
          publishedVersion: 1,
          source: SurfaceResolutionSource.fresh,
          reason: SurfaceDeliveryReceiptReason.none,
          routeId: '',
        )
        .painted(Duration.zero);

    gate.complete(http.Response('', 429, headers: {'retry-after': '5'}));
    await inFlight;

    expect(retries, isEmpty);
    expect(uploader.hasRetryTimer, isFalse);
    expect(SurfaceDeliveryReceiptUploader.instance.hasPendingRetry, isFalse);
    final drained = await replacement.drain();
    expect(drained.dropped, 0);
    expect(drained.counts.keys.single.surfaceSlug, 'after');
  });

  test('a change of key retires the queue as dropped and posts nothing',
      () async {
    present();
    present();

    uploader.configure(
      baseUrl: 'https://api.example.test',
      apiKey: 'rs_pk_other',
      enabled: true,
    );
    expect(batch.hasReceipts, isFalse);
    uploader.retain();
    await uploader.flush();

    expect(requests, hasLength(1));
    final json = body(requests.single);
    expect(json['receipts'], isEmpty);
    expect(json['dropped'], 2);
    expect(requests.single.headers['Authorization'], 'Bearer rs_pk_other');
  });

  for (final failure in <String, Future<http.Response> Function()>{
    '429': () async => http.Response('', 429, headers: {'retry-after': '5'}),
    'transport error': () async => throw http.ClientException('offline'),
  }.entries) {
    test(
        'a ${failure.key} for a post under an old key drops its receipts and '
        'never posts them under the new key', () async {
      present(slug: 'old-a');
      present(slug: 'old-b');
      final gate = Completer<http.Response>();
      answer = (_) => gate.future;
      final inFlight = uploader.flush();
      await Future<void>.delayed(Duration.zero);
      expect(requests, hasLength(1));

      uploader.configure(
        baseUrl: 'https://api.example.test',
        apiKey: 'rs_pk_other',
        enabled: true,
      );
      answer = (_) async => http.Response('', 204);
      gate.complete(failure.value());
      await inFlight;

      expect(retries, isEmpty);
      expect(uploader.hasPendingRetry, isFalse);
      expect(uploader.hasRetryTimer, isFalse);

      present(slug: 'new');
      await uploader.flush();

      final underNewKey = requests
          .where((r) => r.headers['Authorization'] == 'Bearer rs_pk_other')
          .toList();
      expect(underNewKey, hasLength(1));
      final json = body(underNewKey.single);
      final slugs = (json['receipts']! as List)
          .map((receipt) => (receipt as Map)['surfaceSlug'])
          .toList();
      expect(slugs, ['new']);
      expect(json['dropped'], 2);
    });
  }

  test('a change of key drops a parked retry and counts it', () async {
    present();
    present();
    answer = (_) async => http.Response('', 429, headers: {'retry-after': '5'});
    await uploader.flush();
    expect(uploader.hasPendingRetry, isTrue);

    uploader.configure(
      baseUrl: 'https://api.example.test',
      apiKey: 'rs_pk_other',
      enabled: true,
    );

    expect(uploader.hasPendingRetry, isFalse);
    expect(retries.single.isActive, isFalse);
    answer = (_) async => http.Response('', 204);
    await uploader.flush();
    expect(requests, hasLength(2));
    expect(body(requests.last)['receipts'], isEmpty);
    expect(body(requests.last)['dropped'], 2);
    expect(requests.last.headers['Authorization'], 'Bearer rs_pk_other');
  });

  group('the 64 KiB boundary', () {
    const count = 200;
    final envelope = '{"batchId":"${'0' * 36}","receipts":[],"dropped":0}';

    Future<int> baseLength() async {
      present(slug: '');
      final probe = (await batch.drain()).entries().single;
      return utf8.encode(jsonEncode(probe.receipt.toJson(probe.count))).length;
    }

    // Opens [count] + 1 equal receipts after one of [first] encoded bytes.
    Future<void> fill(int first, int base) async {
      present(slug: 'a' * (first - base));
      for (var index = 1; index <= count; index += 1) {
        present(slug: 's${index.toString().padLeft(63, '0')}');
      }
    }

    int firstFor(int target, int base) {
      final rest = base + 64;
      return target - envelope.length - (count - 1) - (count - 1) * rest;
    }

    test('a body of exactly 65536 bytes goes in one post', () async {
      final base = await baseLength();
      await fill(firstFor(kSurfaceDeliveryReceiptMaximumPostBytes, base), base);

      await uploader.flush();

      expect(requests.first.bodyBytes.length,
          kSurfaceDeliveryReceiptMaximumPostBytes);
      expect(body(requests.first)['receipts'], hasLength(count));
      for (final request in requests) {
        expect(request.bodyBytes.length,
            lessThanOrEqualTo(kSurfaceDeliveryReceiptMaximumPostBytes));
      }
    });

    test('one byte more splits the post', () async {
      final base = await baseLength();
      await fill(
        firstFor(kSurfaceDeliveryReceiptMaximumPostBytes + 1, base),
        base,
      );

      await uploader.flush();

      expect(body(requests.first)['receipts'], hasLength(count - 1));
      for (final request in requests) {
        expect(request.bodyBytes.length,
            lessThanOrEqualTo(kSurfaceDeliveryReceiptMaximumPostBytes));
      }
      expect(
        requests.fold<int>(
          0,
          (sum, request) => sum + (body(request)['receipts']! as List).length,
        ),
        count + 1,
      );
    });
  });

  test('a post never carries more than 500 receipts', () async {
    for (var index = 0; index < kSurfaceDeliveryReceiptCapacity; index += 1) {
      present(slug: 'p$index');
    }

    await uploader.flush();

    expect(requests.length, greaterThan(1));
    for (final request in requests) {
      expect(
        (body(request)['receipts']! as List).length,
        lessThanOrEqualTo(kSurfaceDeliveryReceiptMaximumPostReceipts),
      );
      expect(body(request).keys,
          unorderedEquals(['batchId', 'receipts', 'dropped']));
    }
    expect(
      requests.fold<int>(
        0,
        (sum, request) => sum + (body(request)['receipts']! as List).length,
      ),
      kSurfaceDeliveryReceiptCapacity,
    );
  });

  test('a post never exceeds 64 KiB', () async {
    for (var index = 0; index < 500; index += 1) {
      batch
          .open(
            surfaceType: Surface.paywall,
            surfaceSlug: 's${index.toString().padLeft(63, '0')}',
            publishedVersion: 1000000 + index,
            source: SurfaceResolutionSource.holdLastGood,
            reason: SurfaceDeliveryReceiptReason.serverError,
            routeId: 'r${index.toString().padLeft(63, '0')}',
          )
          .painted(const Duration(milliseconds: 5));
    }

    await uploader.flush();

    expect(requests.length, greaterThan(1));
    for (final request in requests) {
      expect(request.bodyBytes.length, lessThanOrEqualTo(64 * 1024));
    }
    expect(
      requests.fold<int>(
        0,
        (sum, request) => sum + (body(request)['receipts']! as List).length,
      ),
      500,
    );
  });

  test('a coalesced count is posted in bounded pieces', () async {
    for (var index = 0; index < 3; index += 1) {
      present();
    }
    final receipt = (await batch.drain()).counts.keys.single;
    final oversized = SurfaceDeliveryReceiptPayload(
      {receipt: kSurfaceDeliveryReceiptMaximumCount * 2 + 5},
      0,
    );

    expect(
      oversized.entries().map((entry) => entry.count),
      [
        kSurfaceDeliveryReceiptMaximumCount,
        kSurfaceDeliveryReceiptMaximumCount,
        5,
      ],
    );
  });

  test('a failure mid-way re-queues only what was not posted', () async {
    for (var index = 0; index < kSurfaceDeliveryReceiptCapacity; index += 1) {
      present(slug: 'p$index');
    }
    var posts = 0;
    answer = (_) async {
      posts += 1;
      return posts == 1
          ? http.Response('', 204)
          : http.Response('', 429, headers: {'retry-after': '5'});
    };

    await uploader.flush();
    expect(requests, hasLength(2));
    expect(uploader.hasPendingRetry, isTrue);
    final posted = (body(requests.first)['receipts']! as List).length;

    answer = (_) async => http.Response('', 204);
    retries.single.callback();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(requests.length, greaterThan(2));
    final retried = requests.skip(2).fold<int>(
          0,
          (sum, request) => sum + (body(request)['receipts']! as List).length,
        );
    expect(posted + retried, kSurfaceDeliveryReceiptCapacity);
    expect(uploader.hasPendingRetry, isFalse);
  });

  test('a disabled uploader discards what it drains and never posts', () async {
    present();
    uploader.configure(baseUrl: null, apiKey: null, enabled: true);

    await uploader.flush();

    expect(requests, isEmpty);
    expect(batch.enabled, isFalse);
  });
}
