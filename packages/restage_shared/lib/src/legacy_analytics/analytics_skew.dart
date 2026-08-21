/// Server-side event-time clamping (the single-sourced clock-skew bound).
///
/// The raw client wall-clock fire time is untrusted: a bad or malicious device
/// clock could write future or far-past partitions that hide events. The ingest
/// path preserves the raw value as `client_occurred_at` and derives a clamped
/// `occurred_at` — the event-time field dashboards filter on — via
/// [clampOccurredAt]. The bound is single-sourced here so the SDK, the ingest
/// validator, and the dashboard query invariant all agree.
library;

/// The maximum tolerated difference between a client's reported event time and
/// the server receive time. Generous (48h) for legitimately offline-batched
/// events while still bounding clock abuse.
const Duration kMaxEventSkew = Duration(hours: 48);

/// Clamps an untrusted [clientOccurredAt] against the server-trusted
/// [receivedAt]. Never drops the event — a stale/future time is bounded, and
/// the raw value is preserved separately by the caller.
///
/// - future (`client > received`, clock-ahead device) → [receivedAt];
/// - past within [maxSkew] (floor inclusive) → [clientOccurredAt] (kept);
/// - stale past (`client < received - maxSkew`) → `received - maxSkew`.
DateTime clampOccurredAt({
  required DateTime clientOccurredAt,
  required DateTime receivedAt,
  Duration maxSkew = kMaxEventSkew,
}) {
  if (clientOccurredAt.isAfter(receivedAt)) return receivedAt;
  final floor = receivedAt.subtract(maxSkew);
  if (clientOccurredAt.isBefore(floor)) return floor;
  return clientOccurredAt;
}
