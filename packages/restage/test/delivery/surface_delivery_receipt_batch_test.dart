import 'package:flutter_test/flutter_test.dart';
import 'package:restage/src/delivery/surface_delivery_receipt.dart';
import 'package:restage/src/delivery/surface_delivery_receipt_batch.dart';
import 'package:restage/src/resolver/surface_resolution_report.dart';
import 'package:restage_shared/restage_shared.dart' show Surface;

void main() {
  late SurfaceDeliveryReceiptBatch batch;
  var now = DateTime.utc(2026, 9, 10, 18, 42, 7);

  setUp(() {
    SurfaceDeliveryReceiptBatch.debugReset();
    now = DateTime.utc(2026, 9, 10, 18, 42, 7);
    batch = SurfaceDeliveryReceiptBatch.instance
      ..enabled = true
      ..clock = (() => now)
      ..deviceSource = (() async => (platform: 'android', appBuild: 412));
  });

  SurfaceDeliveryReceiptHandle open({
    String slug = 'pro',
    SurfaceResolutionSource source = SurfaceResolutionSource.fresh,
    SurfaceDeliveryReceiptReason reason = SurfaceDeliveryReceiptReason.none,
    int version = 12,
    String routeId = '',
  }) =>
      batch.open(
        surfaceType: Surface.paywall,
        surfaceSlug: slug,
        publishedVersion: version,
        source: source,
        reason: reason,
        routeId: routeId,
      );

  test('a painted handle closes with its latency bucket', () async {
    open().painted(const Duration(milliseconds: 300));

    final payload = await batch.drain();

    expect(payload.dropped, 0);
    expect(payload.counts, hasLength(1));
    final receipt = payload.counts.keys.single;
    expect(payload.counts[receipt], 1);
    expect(receipt.surfaceType, Surface.paywall);
    expect(receipt.surfaceSlug, 'pro');
    expect(receipt.publishedVersion, 12);
    expect(receipt.source, SurfaceResolutionSource.fresh);
    expect(receipt.reason, SurfaceDeliveryReceiptReason.none);
    expect(receipt.outcome, SurfaceDeliveryReceiptOutcome.painted);
    expect(receipt.platform, 'android');
    expect(receipt.appBuild, 412);
    expect(receipt.routeId, '');
    expect(receipt.latencyBucket, SurfaceDeliveryLatencyBucket.lt500ms);
    expect(receipt.minuteBucketUtc, DateTime.utc(2026, 9, 10, 18, 42));
  });

  test('latency buckets follow the closed thresholds', () {
    expect(
      SurfaceDeliveryLatencyBucket.of(const Duration(milliseconds: 199)),
      SurfaceDeliveryLatencyBucket.lt200ms,
    );
    expect(
      SurfaceDeliveryLatencyBucket.of(const Duration(milliseconds: 499)),
      SurfaceDeliveryLatencyBucket.lt500ms,
    );
    expect(
      SurfaceDeliveryLatencyBucket.of(const Duration(milliseconds: 999)),
      SurfaceDeliveryLatencyBucket.lt1s,
    );
    expect(
      SurfaceDeliveryLatencyBucket.of(const Duration(milliseconds: 2999)),
      SurfaceDeliveryLatencyBucket.lt3s,
    );
    expect(
      SurfaceDeliveryLatencyBucket.of(const Duration(seconds: 3)),
      SurfaceDeliveryLatencyBucket.ge3s,
    );
  });

  test('a failed handle closes as renderFailed with its reason', () async {
    open().failed(SurfaceDeliveryReceiptReason.decodeFailed);

    final receipt = (await batch.drain()).counts.keys.single;

    expect(receipt.outcome, SurfaceDeliveryReceiptOutcome.renderFailed);
    expect(receipt.reason, SurfaceDeliveryReceiptReason.decodeFailed);
    expect(receipt.latencyBucket, SurfaceDeliveryLatencyBucket.unknown);
  });

  test('the first close wins', () async {
    final handle = open()..painted(const Duration(milliseconds: 10));
    handle.failed(SurfaceDeliveryReceiptReason.decodeFailed);

    final payload = await batch.drain();

    expect(payload.counts, hasLength(1));
    expect(
      payload.counts.keys.single.outcome,
      SurfaceDeliveryReceiptOutcome.painted,
    );
  });

  test('an unresolved handle closes as notPainted at drain', () async {
    open();

    final receipt = (await batch.drain()).counts.keys.single;

    expect(receipt.outcome, SurfaceDeliveryReceiptOutcome.notPainted);
    expect(receipt.latencyBucket, SurfaceDeliveryLatencyBucket.unknown);
  });

  test('identical receipts within one minute coalesce into count', () async {
    open().painted(const Duration(milliseconds: 10));
    now = now.add(const Duration(seconds: 40));
    open().painted(const Duration(milliseconds: 20));
    now = now.add(const Duration(seconds: 40));
    open().painted(const Duration(milliseconds: 30));

    final payload = await batch.drain();

    expect(payload.counts.values.toList()..sort(), [1, 2]);
    expect(
      payload.counts.keys.map((receipt) => receipt.minuteBucketUtc).toSet(),
      {DateTime.utc(2026, 9, 10, 18, 42), DateTime.utc(2026, 9, 10, 18, 43)},
    );
  });

  test('drain returns and clears', () async {
    open().painted(Duration.zero);
    expect((await batch.drain()).counts, hasLength(1));
    expect((await batch.drain()).isEmpty, isTrue);
  });

  test('opens past the capacity are dropped and counted', () async {
    for (var index = 0; index < kSurfaceDeliveryReceiptCapacity; index += 1) {
      open();
    }
    final overflow = open();

    expect(overflow.isClosed, isTrue);
    expect(batch.dropped, 1);
    final payload = await batch.drain();
    expect(payload.dropped, 1);
    expect(payload.counts.values.single, kSurfaceDeliveryReceiptCapacity);
    expect((await batch.drain()).dropped, 0);
  });

  test('a recent refusal explains a held or bundled resolution', () async {
    batch.noteRefusal(
      Surface.paywall,
      'pro',
      SurfaceDeliveryReceiptReason.throttled,
    );
    open(
      source: SurfaceResolutionSource.holdLastGood,
      reason: SurfaceDeliveryReceiptReason.offline,
    ).painted(Duration.zero);

    final receipt = (await batch.drain()).counts.keys.single;

    expect(receipt.source, SurfaceResolutionSource.holdLastGood);
    expect(receipt.reason, SurfaceDeliveryReceiptReason.throttled);
  });

  test('a refusal is consumed once and forgotten after thirty seconds',
      () async {
    batch.noteRefusal(
      Surface.paywall,
      'pro',
      SurfaceDeliveryReceiptReason.serverError,
    );
    now = now.add(const Duration(seconds: 31));
    open(
      source: SurfaceResolutionSource.bundled,
      reason: SurfaceDeliveryReceiptReason.offline,
    ).painted(Duration.zero);
    batch.noteRefusal(
      Surface.paywall,
      'pro',
      SurfaceDeliveryReceiptReason.serverError,
    );
    open(
      source: SurfaceResolutionSource.bundled,
      reason: SurfaceDeliveryReceiptReason.offline,
    ).painted(Duration.zero);
    open(
      source: SurfaceResolutionSource.bundled,
      reason: SurfaceDeliveryReceiptReason.offline,
    ).painted(Duration.zero);

    final reasons = (await batch.drain())
        .counts
        .entries
        .map((entry) => (entry.key.reason, entry.value))
        .toSet();

    expect(reasons, {
      (SurfaceDeliveryReceiptReason.offline, 2),
      (SurfaceDeliveryReceiptReason.serverError, 1),
    });
  });

  test('a refusal never overrides a fresh or a non-transport reason', () async {
    batch.noteRefusal(
      Surface.paywall,
      'pro',
      SurfaceDeliveryReceiptReason.throttled,
    );
    open().painted(Duration.zero);
    batch.noteRefusal(
      Surface.paywall,
      'pro',
      SurfaceDeliveryReceiptReason.throttled,
    );
    open(
      source: SurfaceResolutionSource.bundled,
      reason: SurfaceDeliveryReceiptReason.unsupported,
    ).painted(Duration.zero);

    final reasons =
        (await batch.drain()).counts.keys.map((receipt) => receipt.reason);

    expect(
        reasons,
        unorderedEquals([
          SurfaceDeliveryReceiptReason.none,
          SurfaceDeliveryReceiptReason.unsupported,
        ]));
  });

  test('a disabled batch records nothing', () async {
    batch.enabled = false;

    final handle = open();

    expect(handle.isClosed, isTrue);
    expect((await batch.drain()).isEmpty, isTrue);
  });

  test('a platform outside the closed set produces no receipts', () async {
    batch.deviceSource = () async => (platform: null, appBuild: 0);
    open().painted(Duration.zero);

    final payload = await batch.drain();

    expect(payload.counts, isEmpty);
  });

  test('the latest handle per surface is reachable by slug', () async {
    final first = open(slug: 'welcome');
    final second = open(slug: 'welcome');

    expect(batch.latestFor(Surface.paywall, 'welcome'), same(second));
    expect(batch.latestFor(Surface.onboarding, 'welcome'), isNull);
    first.painted(Duration.zero);
    await batch.drain();
    expect(batch.latestFor(Surface.paywall, 'welcome'), isNull);
  });

  test('the wire form carries exactly the closed key set', () async {
    open(routeId: 'r1').painted(const Duration(milliseconds: 900));

    final payload = await batch.drain();
    final json = payload.toJson();

    expect(json.keys, unorderedEquals(['receipts', 'dropped']));
    final receipt = (json['receipts']! as List).single as Map<String, Object>;
    expect(receipt, {
      'surfaceType': 'paywall',
      'surfaceSlug': 'pro',
      'publishedVersion': 12,
      'source': 'fresh',
      'reason': 'none',
      'outcome': 'painted',
      'platform': 'android',
      'appBuild': 412,
      'routeId': 'r1',
      'latencyBucket': 'lt1s',
      'minute': '2026-09-10T18:42Z',
      'count': 1,
    });
  });
}
