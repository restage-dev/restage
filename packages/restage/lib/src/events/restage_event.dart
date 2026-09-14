import 'package:meta/meta.dart';
import 'package:restage_shared/restage_shared.dart' show Surface;

import 'event_enums.dart';

part 'delivery_events.dart';
part 'flow_events.dart';
part 'interaction_events.dart';
part 'presentation_events.dart';

/// Base type for every event the Restage SDK emits.
///
/// Event handlers should include a wildcard or default case so they remain
/// compatible with additional event types:
/// ```dart
/// RestagePaywall(
///   onEvent: (event) {
///     switch (event) {
///       case PaywallViewed(): ...;
///       case _: break;
///     }
///   },
/// );
/// ```
@immutable
sealed class RestageEvent {
  /// Const base constructor. `firedAt` is populated by the SDK at fire time;
  /// passing it explicitly is supported for tests and replay.
  const RestageEvent({this.paywallId, this.firedAt});

  /// Canonical snake_case event name. Used by [toMap] for analytics
  /// forwarding to Mixpanel / Amplitude.
  String get name;

  /// Which paywall fired this event. `null` for app-wide lifecycle events
  /// (e.g. `FlowUnavailable` fired before a surface is mounted).
  final String? paywallId;

  /// Wall-clock time the event was fired. Populated by the SDK runtime.
  final DateTime? firedAt;

  /// Flat map representation. `name` plus all subclass fields. Used by hosts
  /// to forward events to analytics SDKs (Mixpanel, Amplitude, Segment).
  Map<String, Object?> toMap();
}
