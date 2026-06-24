import 'package:flutter/foundation.dart';

/// The Tier-2 per-session summary contract — the typed shape of the
/// `paywall_session_summary` event's `properties`.
///
/// Tier-2 per-frame signals (viewability, dwell, scroll, taps) never reach the
/// wire individually: the SDK accumulates them locally and emits a single
/// summary at the surface-session boundary (mount → dismiss). This class is the
/// contract for that payload; it rides the analytics envelope's `properties`
/// map (so it adds no new wire fields and no warehouse columns).
///
/// Active instrumentation that would populate it is deferred — the production
/// bridge suppresses `paywall_session_summary` so a zeroed summary never
/// pollutes analytics. [instrumentationVersion] lets consumers filter
/// incomplete summaries once capture turns on.
@immutable
class PaywallSessionSummary {
  /// Creates a session summary.
  const PaywallSessionSummary({
    required this.sectionDwellMs,
    required this.maxScrollDepthPct,
    required this.tapCounts,
    required this.sessionDurationMs,
    required this.sectionsViewed,
    required this.instrumentationVersion,
  });

  /// Reconstructs a summary from an analytics envelope's `properties` map,
  /// tolerating missing keys (safe zero/empty defaults) and `num` cells.
  factory PaywallSessionSummary.fromProperties(Map<String, Object?> props) {
    return PaywallSessionSummary(
      sectionDwellMs: _intMap(props['sectionDwellMs']),
      maxScrollDepthPct: _int(props['maxScrollDepthPct']),
      tapCounts: _intMap(props['tapCounts']),
      sessionDurationMs: _int(props['sessionDurationMs']),
      sectionsViewed: _stringList(props['sectionsViewed']),
      instrumentationVersion: _int(props['instrumentationVersion']),
    );
  }

  /// Per-section dwell time in milliseconds, keyed by widget id.
  final Map<String, int> sectionDwellMs;

  /// The deepest scroll depth reached, as a percentage (0–100).
  final int maxScrollDepthPct;

  /// Tap counts keyed by widget id.
  final Map<String, int> tapCounts;

  /// Total session duration in milliseconds (mount → dismiss, resume-inclusive).
  final int sessionDurationMs;

  /// The widget ids that became viewable during the session, in first-seen
  /// order.
  final List<String> sectionsViewed;

  /// The instrumentation schema version that produced this summary (lets
  /// dashboards filter incomplete summaries before capture is fully enabled).
  final int instrumentationVersion;

  /// Encodes to the analytics envelope `properties` map.
  Map<String, Object?> toProperties() => <String, Object?>{
        'sectionDwellMs': Map<String, int>.of(sectionDwellMs),
        'maxScrollDepthPct': maxScrollDepthPct,
        'tapCounts': Map<String, int>.of(tapCounts),
        'sessionDurationMs': sessionDurationMs,
        'sectionsViewed': List<String>.of(sectionsViewed),
        'instrumentationVersion': instrumentationVersion,
      };

  @override
  bool operator ==(Object other) =>
      other is PaywallSessionSummary &&
      mapEquals(other.sectionDwellMs, sectionDwellMs) &&
      other.maxScrollDepthPct == maxScrollDepthPct &&
      mapEquals(other.tapCounts, tapCounts) &&
      other.sessionDurationMs == sessionDurationMs &&
      listEquals(other.sectionsViewed, sectionsViewed) &&
      other.instrumentationVersion == instrumentationVersion;

  @override
  int get hashCode => Object.hash(
        _mapHash(sectionDwellMs),
        maxScrollDepthPct,
        _mapHash(tapCounts),
        sessionDurationMs,
        Object.hashAll(sectionsViewed),
        instrumentationVersion,
      );
}

// Order-independent hash over a map's entries (mirrors mapEquals's contract).
int _mapHash(Map<String, int> map) => Object.hashAllUnordered(<int>[
      for (final entry in map.entries) Object.hash(entry.key, entry.value),
    ]);

Map<String, int> _intMap(Object? value) {
  if (value is! Map) return <String, int>{};
  return <String, int>{
    for (final entry in value.entries) entry.key.toString(): _int(entry.value),
  };
}

List<String> _stringList(Object? value) {
  if (value is! List) return <String>[];
  return <String>[for (final item in value) item.toString()];
}

int _int(Object? value) => value is num ? value.toInt() : 0;
