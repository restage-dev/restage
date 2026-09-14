part of 'restage_event.dart';

/// Fired when a hosted surface delivery is rate limited.
@immutable
final class SurfaceDeliveryRateLimited extends RestageEvent {
  /// Creates a rate-limited delivery event.
  const SurfaceDeliveryRateLimited({
    required this.surface,
    required this.surfaceId,
    required this.retryAfter,
    super.firedAt,
  });

  @override
  String get name => 'surface_delivery_rate_limited';

  /// The requested surface category.
  final Surface surface;

  /// The requested surface identifier.
  final String surfaceId;

  /// The minimum delay requested by the service.
  final Duration retryAfter;

  @override
  Map<String, Object?> toMap() => <String, Object?>{
        'name': name,
        'surface': surface.wireName,
        'surfaceId': surfaceId,
        'retryAfterMs': retryAfter.inMilliseconds,
        if (firedAt != null) 'firedAt': firedAt!.toIso8601String(),
      };
}
