import 'package:meta/meta.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    show MountSelectionAttributionV1, PresentationAssignmentCarrierV2;
import 'package:restage_shared/restage_shared.dart' show Surface;

import '../resolver/surface_resolution_report.dart';

/// Why a presentation showed something other than a fresh copy, or failed.
enum SurfaceDeliveryReceiptReason {
  none,
  offline,
  throttled,
  serverError,
  unsupported,
  decodeFailed,

  /// An installed widget library no longer renders the version the content
  /// needs.
  incompatibleLibrary,
}

/// What became of the content once it was resolved.
enum SurfaceDeliveryReceiptOutcome {
  painted,
  notPainted,
  renderFailed,

  /// The mount showed the host's own fallback because the service said so.
  fallback,
}

/// Mount-to-paint latency, bucketed.
enum SurfaceDeliveryLatencyBucket {
  lt200ms,
  lt500ms,
  lt1s,
  lt3s,
  ge3s,
  unknown;

  /// The bucket [elapsed] falls into.
  static SurfaceDeliveryLatencyBucket of(Duration elapsed) {
    final ms = elapsed.inMilliseconds;
    if (ms < 200) return lt200ms;
    if (ms < 500) return lt500ms;
    if (ms < 1000) return lt1s;
    if (ms < 3000) return lt3s;
    return ge3s;
  }
}

/// One presentation's delivery facts. Carries no device or user identifier.
@immutable
final class SurfaceDeliveryReceipt {
  const SurfaceDeliveryReceipt({
    required this.surfaceType,
    required this.surfaceSlug,
    required this.publishedVersion,
    required this.source,
    required this.reason,
    required this.outcome,
    required this.platform,
    required this.appBuild,
    required this.routeId,
    required this.latencyBucket,
    required this.minuteBucketUtc,
    this.attribution,
    this.routingSelectionReceipt,
    this.assignment,
  });

  /// Null, with an empty slug, for a fallback filed under its placement.
  final Surface? surfaceType;
  final String surfaceSlug;
  final int publishedVersion;
  final SurfaceResolutionSource source;
  final SurfaceDeliveryReceiptReason reason;
  final SurfaceDeliveryReceiptOutcome outcome;
  final String platform;
  final int appBuild;

  /// The selected route, or the empty string when untargeted.
  final String routeId;
  final SurfaceDeliveryLatencyBucket latencyBucket;
  final DateTime minuteBucketUtc;
  final MountSelectionAttributionV1? attribution;
  final String? routingSelectionReceipt;
  final PresentationAssignmentCarrierV2? assignment;

  /// The wire form, with [count] presentations coalesced into it.
  Map<String, Object> toJson(int count) => <String, Object>{
        'surfaceType': surfaceType?.wireName ?? '',
        'surfaceSlug': surfaceSlug,
        'publishedVersion': publishedVersion,
        'source': source.name,
        'reason': reason.name,
        'outcome': outcome.name,
        'platform': platform,
        'appBuild': appBuild,
        'routeId': routeId,
        'latencyBucket': latencyBucket.name,
        'minute': formatMinute(minuteBucketUtc),
        'count': count,
        if (attribution != null) 'attribution': attribution!.toJson(),
        if (routingSelectionReceipt != null)
          'routingSelectionReceipt': routingSelectionReceipt!,
        if (assignment != null) 'assignment': assignment!.toJson(),
      };

  /// `2026-09-10T18:42Z` for [minute], which must be UTC.
  static String formatMinute(DateTime minute) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${minute.year.toString().padLeft(4, '0')}-${two(minute.month)}-'
        '${two(minute.day)}T${two(minute.hour)}:${two(minute.minute)}Z';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SurfaceDeliveryReceipt &&
          surfaceType == other.surfaceType &&
          surfaceSlug == other.surfaceSlug &&
          publishedVersion == other.publishedVersion &&
          source == other.source &&
          reason == other.reason &&
          outcome == other.outcome &&
          platform == other.platform &&
          appBuild == other.appBuild &&
          routeId == other.routeId &&
          latencyBucket == other.latencyBucket &&
          minuteBucketUtc == other.minuteBucketUtc &&
          attribution == other.attribution &&
          routingSelectionReceipt == other.routingSelectionReceipt &&
          assignment == other.assignment;

  @override
  int get hashCode => Object.hash(
        surfaceType,
        surfaceSlug,
        publishedVersion,
        source,
        reason,
        outcome,
        platform,
        appBuild,
        routeId,
        latencyBucket,
        minuteBucketUtc,
        attribution,
        routingSelectionReceipt,
        assignment,
      );
}
