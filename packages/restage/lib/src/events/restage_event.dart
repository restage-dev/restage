import 'package:restage_shared/restage_shared.dart';
import 'package:meta/meta.dart';

import 'event_enums.dart';

part 'conversion_events.dart';
part 'flow_events.dart';
part 'interaction_events.dart';
part 'lifecycle_events.dart';
part 'presentation_events.dart';

/// Reserved event names that the SDK runtime intercepts and demuxes into
/// typed `Purchase*` / `Restore*` events. Authoring helpers (`paywallPurchase`,
/// the `restage.restore` RFW event) and the demuxer are the only call sites.
abstract final class RestageEventNames {
  RestageEventNames._();

  /// Fired by `paywallPurchase` and the `event "restage.purchase"` RFW form.
  /// Demuxer routes to [PurchaseInitiated] and the billing gateway.
  static const String purchase = 'restage.purchase';

  /// Fired by the `event "restage.restore"` RFW form. Demuxer routes to
  /// [RestoreInitiated] and the billing gateway.
  static const String restore = 'restage.restore';
}

/// Base type for every event the Restage SDK emits.
///
/// Sealed — pattern-match exhaustively in `onEvent` callbacks:
/// ```dart
/// RestagePaywall(
///   onEvent: (event) {
///     switch (event) {
///       case PaywallViewed(): ...;
///       case PurchaseSucceeded(:final productId): unlock(productId);
///       case PaywallCustomEvent(eventName: 'restore'): triggerRestore();
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
  /// (e.g. `EntitlementRevoked` fired with no paywall mounted).
  final String? paywallId;

  /// Wall-clock time the event was fired. Populated by the SDK runtime.
  final DateTime? firedAt;

  /// Flat map representation. `name` plus all subclass fields. Used by hosts
  /// to forward events to analytics SDKs (Mixpanel, Amplitude, Segment).
  Map<String, Object?> toMap();
}
