import 'package:meta/meta.dart';
import 'package:restage_shared/src/analytics/analytics_app_context.dart';
import 'package:restage_shared/src/analytics/analytics_wire_enums.dart';

/// The behavioral-analytics event envelope every surface emits.
///
/// This is the **client-sent** shape (the SDK → ingest wire). The
/// server-stamped fields (`tier`/`source`/`appId`/…, applied at ingest)
/// are deliberately NOT on this type: a client must not be able to assert them,
/// and `fromJson` never reads them. Identity/context fields are nullable to
/// model both client and server/app-wide events; the per-`source` requirements
/// are enforced at decode (the source-conditional rules below).
@immutable
final class AnalyticsEvent {
  /// Creates an event envelope.
  ///
  /// [surface] defaults to [AnalyticsSurface.paywall]; pass `null` for an
  /// app-wide / server event.
  AnalyticsEvent({
    required this.eventId,
    required this.name,
    required this.occurredAt,
    this.schemaVersion = 1,
    this.surface = AnalyticsSurface.paywall,
    this.surfaceId,
    this.surfaceVersion,
    this.placementId,
    this.anonymousId,
    this.sessionId,
    this.surfaceSessionId,
    this.userId,
    this.appContext,
    this.variantId,
    this.experimentId,
    this.productId,
    this.offerId,
    Map<String, Object?> properties = const <String, Object?>{},
    // Deep defensive copy: the envelope is `@immutable`, so a caller can
    // neither mutate `properties` (or any nested map/list) after construction
    // nor leak in a later mutation of the source structure.
  }) : properties = _deepUnmodifiableMap(properties);

  /// Decodes an envelope from [json].
  ///
  /// [source] is the **trusted** ingest classification (never read from the
  /// payload). For [AnalyticsSource.client] the decode fails loud
  /// ([FormatException]) when `appContext`, `sessionId`, or `anonymousId` is
  /// absent; for [AnalyticsSource.server] those (and `surface`) may be absent.
  /// `tier`/`source` keys in [json], if any, are ignored — they are not
  /// envelope fields.
  factory AnalyticsEvent.fromJson(
    Map<String, Object?> json, {
    required String source,
  }) {
    final appContextJson = json['appContext'];
    if (appContextJson != null && appContextJson is! Map) {
      throw FormatException(
        'AnalyticsEvent.appContext must be a map, got: $appContextJson',
      );
    }
    final appContext = appContextJson == null
        ? null
        : AnalyticsAppContext.fromJson(
            (appContextJson as Map).cast<String, Object?>(),
          );
    final anonymousId = _optionalString(json, 'anonymousId');
    final sessionId = _optionalString(json, 'sessionId');

    if (source == AnalyticsSource.client) {
      if (appContext == null) {
        throw const FormatException(
          'AnalyticsEvent: appContext is required for source=client.',
        );
      }
      if (sessionId == null || sessionId.trim().isEmpty) {
        throw const FormatException(
          'AnalyticsEvent: sessionId is required (non-empty) '
          'for source=client.',
        );
      }
      if (anonymousId == null || anonymousId.trim().isEmpty) {
        throw const FormatException(
          'AnalyticsEvent: anonymousId is required (non-empty) '
          'for source=client.',
        );
      }
    }

    final propertiesJson = json['properties'];
    if (propertiesJson != null && propertiesJson is! Map) {
      throw FormatException(
        'AnalyticsEvent.properties must be a map, got: $propertiesJson',
      );
    }
    final properties = (propertiesJson as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{};

    final schemaVersion = json['schemaVersion'];
    if (schemaVersion != null && schemaVersion is! int) {
      throw FormatException(
        'AnalyticsEvent.schemaVersion must be an int, got: $schemaVersion',
      );
    }

    return AnalyticsEvent(
      eventId: _requireNonEmptyString(json, 'eventId'),
      name: _requireNonEmptyString(json, 'name'),
      occurredAt: _requireUtc(json, 'occurredAt'),
      schemaVersion: (schemaVersion as int?) ?? 1,
      surface: _optionalString(json, 'surface'),
      surfaceId: _optionalString(json, 'surfaceId'),
      surfaceVersion: _optionalString(json, 'surfaceVersion'),
      placementId: _optionalString(json, 'placementId'),
      anonymousId: anonymousId,
      sessionId: sessionId,
      surfaceSessionId: _optionalString(json, 'surfaceSessionId'),
      userId: _optionalString(json, 'userId'),
      appContext: appContext,
      variantId: _optionalString(json, 'variantId'),
      experimentId: _optionalString(json, 'experimentId'),
      productId: _optionalString(json, 'productId'),
      offerId: _optionalString(json, 'offerId'),
      properties: properties,
    );
  }

  /// Contract version (`=1`). Readers preserve-unknown for additive change.
  final int schemaVersion;

  /// Client-minted UUID v4 — the idempotency key.
  final String eventId;

  /// Canonical `snake_case` event name.
  final String name;

  /// The emitting surface (unknown-preserving wire string). `null` = app-wide.
  final String? surface;

  /// Surface-instance id (= the paywall/flow id).
  final String? surfaceId;

  /// Published surface version (a promoted cohort dim).
  final String? surfaceVersion;

  /// Campaign / trigger name.
  final String? placementId;

  /// Client wall-clock fire time, UTC. **Untrusted** (stored as
  /// `client_occurred_at`; the server derives the clamped event time).
  final DateTime occurredAt;

  /// Stable-per-install anonymous actor id (required for `source=client`).
  final String? anonymousId;

  /// App-session id (required for `source=client`).
  final String? sessionId;

  /// Per-surface-presentation session id (mount→dismiss). `null` for app-wide.
  final String? surfaceSessionId;

  /// Opt-in customer-supplied user id.
  final String? userId;

  /// Client app context (required for `source=client`).
  final AnalyticsAppContext? appContext;

  /// Promoted cohort dim.
  final String? variantId;

  /// Promoted cohort dim.
  final String? experimentId;

  /// Promoted conversion dim.
  final String? productId;

  /// Promoted conversion dim.
  final String? offerId;

  /// Residual per-event payload.
  ///
  /// **`data` and `context` are reserved top-level keys** — they name the
  /// host-supplied render-context namespace, which must never reach analytics.
  /// The transport + ingest filter drop them (see `scrubReservedKeys`,
  /// case-insensitive); emitters should not place them at the top level. The
  /// reservation is the top-level namespace only — a nested `{'result':
  /// {'data': ...}}` is preserved.
  final Map<String, Object?> properties;

  /// Encodes to the SDK→ingest wire map. Non-null fields only; `tier`/`source`
  /// are never emitted (not envelope fields).
  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': schemaVersion,
        'eventId': eventId,
        'name': name,
        if (surface != null) 'surface': surface,
        if (surfaceId != null) 'surfaceId': surfaceId,
        if (surfaceVersion != null) 'surfaceVersion': surfaceVersion,
        if (placementId != null) 'placementId': placementId,
        'occurredAt': occurredAt.toUtc().toIso8601String(),
        if (anonymousId != null) 'anonymousId': anonymousId,
        if (sessionId != null) 'sessionId': sessionId,
        if (surfaceSessionId != null) 'surfaceSessionId': surfaceSessionId,
        if (userId != null) 'userId': userId,
        if (appContext != null) 'appContext': appContext!.toJson(),
        if (variantId != null) 'variantId': variantId,
        if (experimentId != null) 'experimentId': experimentId,
        if (productId != null) 'productId': productId,
        if (offerId != null) 'offerId': offerId,
        if (properties.isNotEmpty) 'properties': properties,
      };

  @override
  bool operator ==(Object other) =>
      other is AnalyticsEvent &&
      other.schemaVersion == schemaVersion &&
      other.eventId == eventId &&
      other.name == name &&
      other.surface == surface &&
      other.surfaceId == surfaceId &&
      other.surfaceVersion == surfaceVersion &&
      other.placementId == placementId &&
      other.occurredAt == occurredAt &&
      other.anonymousId == anonymousId &&
      other.sessionId == sessionId &&
      other.surfaceSessionId == surfaceSessionId &&
      other.userId == userId &&
      other.appContext == appContext &&
      other.variantId == variantId &&
      other.experimentId == experimentId &&
      other.productId == productId &&
      other.offerId == offerId &&
      _deepEquals(other.properties, properties);

  @override
  int get hashCode => Object.hash(
        schemaVersion,
        eventId,
        name,
        surface,
        surfaceId,
        surfaceVersion,
        placementId,
        occurredAt,
        anonymousId,
        sessionId,
        Object.hash(
          surfaceSessionId,
          userId,
          appContext,
          variantId,
          experimentId,
          productId,
          offerId,
        ),
        _deepHash(properties),
      );
}

String _requireNonEmptyString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) return value;
  throw FormatException(
    'AnalyticsEvent.$key must be a non-empty string, got: $value',
  );
}

String? _optionalString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is String) return value;
  throw FormatException(
    'AnalyticsEvent.$key must be a string when present, got: $value',
  );
}

DateTime _requireUtc(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw FormatException(
      'AnalyticsEvent.$key must be an ISO-8601 string, got: $value',
    );
  }
  return DateTime.parse(value).toUtc();
}

/// Order-independent deep equality over the inert JSON value space
/// (`Map`/`List`/scalar) used for `properties`.
bool _deepEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_deepEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

int _deepHash(Object? value) {
  if (value is Map) {
    var hash = 0;
    for (final entry in value.entries) {
      // XOR so the per-entry hashes are order-independent.
      hash ^= Object.hash(entry.key, _deepHash(entry.value));
    }
    return hash;
  }
  if (value is List) {
    return Object.hashAll(value.map(_deepHash));
  }
  return value.hashCode;
}

/// Recursively copies [source] into an unmodifiable map, freezing every nested
/// map and list so the result is deeply immutable (and detached from the
/// caller's structure).
Map<String, Object?> _deepUnmodifiableMap(Map<String, Object?> source) {
  return Map<String, Object?>.unmodifiable(<String, Object?>{
    for (final entry in source.entries)
      entry.key: _deepUnmodifiable(entry.value),
  });
}

Object? _deepUnmodifiable(Object? value) {
  if (value is Map) {
    return Map<Object?, Object?>.unmodifiable(<Object?, Object?>{
      for (final entry in value.entries)
        entry.key: _deepUnmodifiable(entry.value),
    });
  }
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(_deepUnmodifiable));
  }
  return value;
}
