import 'package:flutter/foundation.dart';

import '../events/event_enums.dart';

/// Optional handle the host attaches to a `RestagePaywall` to dismiss it
/// programmatically or fire events from outside the paywall (e.g., a "Skip"
/// button rendered by the host atop the paywall).
///
/// ```dart
/// final controller = RestagePaywallController();
///
/// RestagePaywall(id: 'pro_upgrade', controller: controller);
///
/// // Later — e.g. from a host "Skip" button:
/// controller.dismiss(reason: DismissReason.userClose);
/// ```
class RestagePaywallController {
  /// Creates a detached controller. Pass it to `RestagePaywall(controller:)`
  /// to attach.
  RestagePaywallController();

  void Function({required DismissReason reason})? _dismiss;
  void Function(String name, {Map<String, Object?>? args})? _fireEvent;

  /// Whether the controller is currently attached to a mounted [RestagePaywall].
  bool get isAttached => _dismiss != null;

  /// Dismiss the paywall, tagging the resulting `PaywallDismissed` event
  /// with [reason] for analytics. No-op when the controller is detached.
  ///
  /// For free-form analytics tags that don't map to [DismissReason], use
  /// [fireEvent] with a custom event name instead.
  void dismiss({DismissReason reason = DismissReason.programmatic}) {
    final fn = _dismiss;
    if (fn == null) {
      debugPrint(
          '[restage] dismiss() called on detached RestagePaywallController');
      return;
    }
    fn(reason: reason);
  }

  /// Fire a custom event from the host (e.g., a Skip button) into the
  /// active paywall's event channel. No-op when the controller is detached.
  void fireEvent(String name, {Map<String, Object?>? args}) {
    final fn = _fireEvent;
    if (fn == null) {
      debugPrint(
          '[restage] fireEvent() called on detached RestagePaywallController');
      return;
    }
    fn(name, args: args);
  }

  /// Wired by `RestagePaywall` when the controller is attached via
  /// the `controller:` parameter. Internal use only.
  @internal
  void attachInternal({
    required void Function({required DismissReason reason}) onDismiss,
    required void Function(String name, {Map<String, Object?>? args})
        onFireEvent,
  }) {
    _dismiss = onDismiss;
    _fireEvent = onFireEvent;
  }

  /// Wired by `RestagePaywall.dispose()` to break the back-reference.
  @internal
  void detachInternal() {
    _dismiss = null;
    _fireEvent = null;
  }
}
