import 'package:meta/meta.dart';
import 'package:restage_shared/restage_shared.dart' show Surface;

import '../flow/flow_resolver.dart' show ResolvedFlow;
import '../resolver/resolved_variant.dart';
import '../resolver/surface_delivery_observations.dart';
import '../resolver/surface_resolution_report.dart';
import '../surface_screen/surface_screen_types.dart' show ResolvedSurfaceScreen;
import 'surface_delivery_receipt.dart';

/// Distinct receipts held in memory before new presentations are dropped.
const int kSurfaceDeliveryReceiptCapacity = 500;

/// The most presentations one posted receipt may coalesce.
const int kSurfaceDeliveryReceiptMaximumCount = 100000;

/// One receipt with the presentations it stands for.
typedef SurfaceDeliveryReceiptEntry = ({
  SurfaceDeliveryReceipt receipt,
  int count
});

/// How long a delivery refusal explains the next held or bundled resolution.
const Duration _refusalMemory = Duration(seconds: 30);

/// The platform and app build every receipt in this process carries.
typedef SurfaceDeliveryReceiptDevice = ({String? platform, int appBuild});

/// Receipts drained from the batch, coalesced by identical facts.
final class SurfaceDeliveryReceiptPayload {
  SurfaceDeliveryReceiptPayload(this.counts, this.dropped);

  /// Rebuilds a payload from posted-shape entries, merging identical receipts.
  factory SurfaceDeliveryReceiptPayload.fromEntries(
    Iterable<SurfaceDeliveryReceiptEntry> entries,
    int dropped,
  ) {
    final counts = <SurfaceDeliveryReceipt, int>{};
    for (final entry in entries) {
      counts[entry.receipt] = (counts[entry.receipt] ?? 0) + entry.count;
    }
    return SurfaceDeliveryReceiptPayload(counts, dropped);
  }

  final Map<SurfaceDeliveryReceipt, int> counts;
  int dropped;

  bool get isEmpty => counts.isEmpty && dropped == 0;

  int get presentations => counts.values.fold(0, (sum, count) => sum + count);

  /// Adds [other]'s receipts and drops into this payload.
  void absorb(SurfaceDeliveryReceiptPayload other) {
    other.counts.forEach((receipt, count) {
      counts[receipt] = (counts[receipt] ?? 0) + count;
    });
    dropped += other.dropped;
  }

  /// The receipts in posted shape: no entry above the per-receipt count bound.
  List<SurfaceDeliveryReceiptEntry> entries() => <SurfaceDeliveryReceiptEntry>[
        for (final entry in counts.entries)
          for (var left = entry.value;
              left > 0;
              left -= kSurfaceDeliveryReceiptMaximumCount)
            (
              receipt: entry.key,
              count: left > kSurfaceDeliveryReceiptMaximumCount
                  ? kSurfaceDeliveryReceiptMaximumCount
                  : left,
            ),
      ];

  Map<String, Object> toJson() => <String, Object>{
        'receipts': <Object>[
          for (final entry in entries()) entry.receipt.toJson(entry.count),
        ],
        'dropped': dropped,
      };
}

/// One open presentation, closed by its paint or its failure.
final class SurfaceDeliveryReceiptHandle {
  SurfaceDeliveryReceiptHandle._(this._batch, this._open);

  /// A handle that records nothing.
  SurfaceDeliveryReceiptHandle._inert()
      : _batch = null,
        _open = null;

  final SurfaceDeliveryReceiptBatch? _batch;
  final _OpenReceipt? _open;

  bool get isClosed => _open?.closed ?? true;

  /// The content painted [elapsed] after its mount.
  void painted(Duration elapsed) => _close(
        SurfaceDeliveryReceiptOutcome.painted,
        _open?.reason,
        SurfaceDeliveryLatencyBucket.of(elapsed),
      );

  /// The content did not render; [reason] says why when known.
  void failed(SurfaceDeliveryReceiptReason reason) => _close(
        SurfaceDeliveryReceiptOutcome.renderFailed,
        reason,
        SurfaceDeliveryLatencyBucket.unknown,
      );

  void _close(
    SurfaceDeliveryReceiptOutcome outcome,
    SurfaceDeliveryReceiptReason? reason,
    SurfaceDeliveryLatencyBucket latency,
  ) {
    final open = _open;
    final batch = _batch;
    if (open == null || batch == null || open.closed) return;
    open.closed = true;
    batch._closeOpen(open, outcome, reason ?? open.reason, latency);
  }
}

final class _OpenReceipt {
  _OpenReceipt({
    required this.surfaceType,
    required this.surfaceSlug,
    required this.publishedVersion,
    required this.source,
    required this.reason,
    required this.routeId,
    required this.openedAt,
  });

  final Surface surfaceType;
  final String surfaceSlug;
  final int publishedVersion;
  final SurfaceResolutionSource source;
  final SurfaceDeliveryReceiptReason reason;
  final String routeId;
  final DateTime openedAt;
  bool closed = false;
}

final class _Refusal {
  const _Refusal(this.reason, this.at);

  final SurfaceDeliveryReceiptReason reason;
  final DateTime at;
}

/// In-memory receipts for this process, drained by the uploader.
final class SurfaceDeliveryReceiptBatch {
  SurfaceDeliveryReceiptBatch._();

  static SurfaceDeliveryReceiptBatch instance = SurfaceDeliveryReceiptBatch._();

  /// Replaces the process batch with an empty one.
  @internal
  static void debugReset() {
    instance = SurfaceDeliveryReceiptBatch._();
  }

  /// Whether new presentations are recorded at all.
  bool enabled = false;

  /// Called after each append so the uploader can arm its timer.
  void Function()? onAppended;

  /// Test seam for the platform and app build; defaults to the device read.
  Future<SurfaceDeliveryReceiptDevice> Function()? deviceSource;

  DateTime Function() clock = () => DateTime.now().toUtc();

  final Set<_OpenReceipt> _open = <_OpenReceipt>{};
  final Map<_Key, int> _closed = <_Key, int>{};
  final Map<String, _Refusal> _refusals = <String, _Refusal>{};
  final Map<String, SurfaceDeliveryReceiptHandle> _latestBySurface =
      <String, SurfaceDeliveryReceiptHandle>{};
  Future<SurfaceDeliveryReceiptDevice>? _device;
  int _dropped = 0;

  int get dropped => _dropped;

  int get openCount => _open.length;

  /// Whether a flush would have anything to post.
  bool get hasReceipts => _open.isNotEmpty || _closed.isNotEmpty;

  /// Records presentations the uploader could not deliver.
  void countDropped(int count) => _dropped += count;

  /// Forgets every queued presentation and returns how many there were.
  int retire() {
    var presentations = _open.length;
    for (final count in _closed.values) {
      presentations += count;
    }
    for (final open in _open) {
      open.closed = true;
    }
    _open.clear();
    _closed.clear();
    _refusals.clear();
    _latestBySurface.clear();
    return presentations;
  }

  /// Remembers that the service refused [surfaceSlug] so the next held or
  /// bundled resolution can say why.
  void noteRefusal(
    Surface surfaceType,
    String surfaceSlug,
    SurfaceDeliveryReceiptReason reason,
  ) {
    _refusals[_surfaceKey(surfaceType, surfaceSlug)] =
        _Refusal(reason, clock());
  }

  /// Opens a receipt for one resolved presentation.
  SurfaceDeliveryReceiptHandle open({
    required Surface surfaceType,
    required String surfaceSlug,
    required int publishedVersion,
    required SurfaceResolutionSource source,
    required SurfaceDeliveryReceiptReason reason,
    required String routeId,
  }) {
    if (!enabled) return SurfaceDeliveryReceiptHandle._inert();
    if (_open.length + _closed.length >= kSurfaceDeliveryReceiptCapacity) {
      _dropped += 1;
      return SurfaceDeliveryReceiptHandle._inert();
    }
    final now = clock();
    final open = _OpenReceipt(
      surfaceType: surfaceType,
      surfaceSlug: surfaceSlug,
      publishedVersion: publishedVersion,
      source: source,
      reason: _explain(surfaceType, surfaceSlug, source, reason, now),
      routeId: routeId,
      openedAt: now,
    );
    _open.add(open);
    _device ??= _readDevice();
    final handle = SurfaceDeliveryReceiptHandle._(this, open);
    _latestBySurface[_surfaceKey(surfaceType, surfaceSlug)] = handle;
    onAppended?.call();
    return handle;
  }

  /// The most recent open handle for [surfaceSlug], for mounts that hold no
  /// reference to the resolved object.
  SurfaceDeliveryReceiptHandle? latestFor(Surface surfaceType, String slug) =>
      _latestBySurface[_surfaceKey(surfaceType, slug)];

  /// Closes every open receipt as not painted, then returns and clears all.
  Future<SurfaceDeliveryReceiptPayload> drain() async {
    for (final open in _open.toList()) {
      open.closed = true;
      _closeOpen(
        open,
        SurfaceDeliveryReceiptOutcome.notPainted,
        open.reason,
        SurfaceDeliveryLatencyBucket.unknown,
      );
    }
    _open.clear();
    _latestBySurface.clear();
    final dropped = _dropped;
    _dropped = 0;
    if (_closed.isEmpty) {
      return SurfaceDeliveryReceiptPayload(
          <SurfaceDeliveryReceipt, int>{}, dropped);
    }
    final closed = Map<_Key, int>.of(_closed);
    _closed.clear();
    final device = await (_device ??= _readDevice());
    final platform = device.platform;
    final counts = <SurfaceDeliveryReceipt, int>{};
    if (platform == null) {
      // A platform outside the closed set has nowhere to report to.
      return SurfaceDeliveryReceiptPayload(counts, dropped);
    }
    closed.forEach((key, count) {
      final receipt = key.toReceipt(platform, device.appBuild);
      counts[receipt] = (counts[receipt] ?? 0) + count;
    });
    return SurfaceDeliveryReceiptPayload(counts, dropped);
  }

  void _closeOpen(
    _OpenReceipt open,
    SurfaceDeliveryReceiptOutcome outcome,
    SurfaceDeliveryReceiptReason reason,
    SurfaceDeliveryLatencyBucket latency,
  ) {
    _open.remove(open);
    final key = _Key(
      surfaceType: open.surfaceType,
      surfaceSlug: open.surfaceSlug,
      publishedVersion: open.publishedVersion,
      source: open.source,
      reason: reason,
      outcome: outcome,
      routeId: open.routeId,
      latencyBucket: latency,
      minute: DateTime.utc(
        open.openedAt.year,
        open.openedAt.month,
        open.openedAt.day,
        open.openedAt.hour,
        open.openedAt.minute,
      ),
    );
    _closed[key] = (_closed[key] ?? 0) + 1;
  }

  SurfaceDeliveryReceiptReason _explain(
    Surface surfaceType,
    String surfaceSlug,
    SurfaceResolutionSource source,
    SurfaceDeliveryReceiptReason reason,
    DateTime now,
  ) {
    if (source == SurfaceResolutionSource.fresh) return reason;
    final refusal = _refusals.remove(_surfaceKey(surfaceType, surfaceSlug));
    if (refusal == null || now.difference(refusal.at) > _refusalMemory) {
      return reason;
    }
    // A transport-shaped reason is refined by what the service actually said.
    return reason == SurfaceDeliveryReceiptReason.offline
        ? refusal.reason
        : reason;
  }

  Future<SurfaceDeliveryReceiptDevice> _readDevice() async {
    final source = deviceSource;
    if (source != null) return source();
    try {
      final observations = await readSurfaceDeliveryObservations();
      return (
        platform: observations.platform,
        appBuild: observations.appBuildOrdinal ?? 0,
      );
    } on Object {
      return (platform: null, appBuild: 0);
    }
  }

  static String _surfaceKey(Surface surfaceType, String slug) =>
      '${surfaceType.wireName}/$slug';
}

final class _Key {
  const _Key({
    required this.surfaceType,
    required this.surfaceSlug,
    required this.publishedVersion,
    required this.source,
    required this.reason,
    required this.outcome,
    required this.routeId,
    required this.latencyBucket,
    required this.minute,
  });

  final Surface surfaceType;
  final String surfaceSlug;
  final int publishedVersion;
  final SurfaceResolutionSource source;
  final SurfaceDeliveryReceiptReason reason;
  final SurfaceDeliveryReceiptOutcome outcome;
  final String routeId;
  final SurfaceDeliveryLatencyBucket latencyBucket;
  final DateTime minute;

  SurfaceDeliveryReceipt toReceipt(String platform, int appBuild) =>
      SurfaceDeliveryReceipt(
        surfaceType: surfaceType,
        surfaceSlug: surfaceSlug,
        publishedVersion: publishedVersion,
        source: source,
        reason: reason,
        outcome: outcome,
        platform: platform,
        appBuild: appBuild,
        routeId: routeId,
        latencyBucket: latencyBucket,
        minuteBucketUtc: minute,
      );

  @override
  bool operator ==(Object other) =>
      other is _Key &&
      surfaceType == other.surfaceType &&
      surfaceSlug == other.surfaceSlug &&
      publishedVersion == other.publishedVersion &&
      source == other.source &&
      reason == other.reason &&
      outcome == other.outcome &&
      routeId == other.routeId &&
      latencyBucket == other.latencyBucket &&
      minute == other.minute;

  @override
  int get hashCode => Object.hash(
        surfaceType,
        surfaceSlug,
        publishedVersion,
        source,
        reason,
        outcome,
        routeId,
        latencyBucket,
        minute,
      );
}

final Expando<SurfaceDeliveryReceiptHandle> _handles =
    Expando<SurfaceDeliveryReceiptHandle>('restage.surfaceDeliveryReceipt');

/// Attaches [handle] to the resolved object a mount will later render.
@internal
void attachSurfaceDeliveryReceipt(
  Object resolved,
  SurfaceDeliveryReceiptHandle handle,
) {
  _handles[resolved] = handle;
}

/// The receipt opened for [resolved], if any.
@internal
SurfaceDeliveryReceiptHandle? surfaceDeliveryReceiptFor(Object resolved) =>
    _handles[resolved];

/// The served published version [resolved] carries, or 0 when it has none.
@internal
int surfaceDeliveryPublishedVersionOf(Object resolved) => switch (resolved) {
      ResolvedVariant(:final paywallPublishedVersion) =>
        paywallPublishedVersion ?? 0,
      ResolvedSurfaceScreen(:final publishedRevision) => publishedRevision ?? 0,
      ResolvedFlow(:final document) => document.version,
      _ => 0,
    };
