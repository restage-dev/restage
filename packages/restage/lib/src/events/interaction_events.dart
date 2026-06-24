part of 'restage_event.dart';

/// Editor- or `paywallEvent`-fired event. The [eventName] is whatever the
/// author wrote in `paywallEvent('subscribe', ...)` or
/// `event 'subscribe' { ... }`.
///
/// SDK-owned events (e.g. `restage.purchase`, `restage.restore`) are
/// translated by the runtime to their typed subclass and never arrive as a
/// `PaywallCustomEvent`.
final class PaywallCustomEvent extends RestageEvent {
  /// Const constructor.
  const PaywallCustomEvent({
    required String super.paywallId,
    required this.eventName,
    required this.args,
    super.firedAt,
  });

  /// The author-supplied event name.
  final String eventName;

  /// Author-supplied arguments. Spread into [toMap] for analytics.
  final Map<String, Object?> args;

  @override
  String get name => 'paywall_custom_event';

  @override
  Map<String, Object?> toMap() => {
        'name': name,
        'paywallId': paywallId,
        'eventName': eventName,
        ...args,
      };
}
