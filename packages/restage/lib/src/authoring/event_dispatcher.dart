import 'package:flutter/widgets.dart';

import '../measurement/measurement_event_sanitizer.dart'
    show isMeasurementTapEventName;
import '../runtime/event_demux.dart' show isReservedCommerceEventName;
import 'authoring_refusal_diagnostic.dart';
import 'event_dispatch_admission.dart' show RestageEventScope;
import 'paywall_event_dispatch.dart';

/// Signature for paywall event callbacks.
///
/// Author-fired events from a rendered paywall reach the host app via this
/// handler.
typedef PaywallEventHandler = void Function(
    String name, Map<String, Object?> args);

PaywallEventHandler _dropReservedEvents(PaywallEventHandler onEvent) {
  return (name, args) {
    if (isReservedCommerceEventName(name) || isMeasurementTapEventName(name)) {
      return;
    }
    onEvent(name, args);
  };
}

/// Provides an event-dispatch handler to its subtree.
///
/// `RestagePaywall` wraps its `RemoteWidget` subtree with this widget so
/// author-fired events from the rendered paywall reach the host's `onEvent`
/// callback.
///
class RestagePaywallEventDispatcher extends StatefulWidget {
  /// Wraps [child] and routes paywall events fired in its subtree to [onEvent].
  const RestagePaywallEventDispatcher({
    super.key,
    required this.onEvent,
    required this.child,
    this.mount,
  });

  /// Called when an authored helper fires for this dispatcher.
  final PaywallEventHandler onEvent;

  /// The generated mount this dispatcher renders, which its recorded events
  /// dispatch through.
  final Object? mount;

  /// The subtree under which paywall event helpers should resolve to
  /// [onEvent].
  final Widget child;

  @override
  State<RestagePaywallEventDispatcher> createState() =>
      _RestagePaywallEventDispatcherState();
}

class _RestagePaywallEventDispatcherState
    extends State<RestagePaywallEventDispatcher> {
  late final RestagePaywallEventDispatchRegistration _registration;

  @override
  void initState() {
    super.initState();
    _registration = RestagePaywallEventDispatchRegistration(
      handler: _dropReservedEvents(widget.onEvent),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _registration
      ..updateTarget(RestagePaywallEventTargetScope.maybeOf(context))
      ..updateMount(widget.mount);
  }

  @override
  void didUpdateWidget(RestagePaywallEventDispatcher old) {
    super.didUpdateWidget(old);
    if (!identical(old.onEvent, widget.onEvent)) {
      _registration.updateHandler(_dropReservedEvents(widget.onEvent));
    }
    _registration.updateMount(widget.mount);
  }

  @override
  void dispose() {
    _registration.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _RestagePaywallEventRegistrationScope(
        registration: _registration,
        child: widget.child,
      );
}

/// The standalone paywall [context] is built in, with its element depth;
/// null when none is above it.
({int depth, RestagePaywallDispatchHandler dispatch})? paywallEventDispatcherAt(
  BuildContext context, {
  required void Function(AuthoringRefusalKind refusal) onRefused,
}) {
  final element = context.getElementForInheritedWidgetOfExactType<
      _RestagePaywallEventRegistrationScope>();
  if (element == null) return null;
  final registration =
      (element.widget as _RestagePaywallEventRegistrationScope).registration;
  // A paywall that is gone refuses; it never passes its events outward.
  final dispatch = registration.capture(onRefused: onRefused) ??
      (_, __) => onRefused(AuthoringRefusalKind.callbackRefused);
  return (depth: element.depth, dispatch: dispatch);
}

// The registration events fired below this dispatcher resolve to; a theme,
// so a dialog, sheet or menu the paywall opens keeps it.
final class _RestagePaywallEventRegistrationScope extends InheritedTheme
    with RestageEventScope {
  const _RestagePaywallEventRegistrationScope({
    required this.registration,
    required super.child,
  });

  final RestagePaywallEventDispatchRegistration registration;

  @override
  Widget wrap(BuildContext context, Widget child) =>
      _RestagePaywallEventRegistrationScope(
        registration: registration,
        child: child,
      );

  @override
  bool updateShouldNotify(_RestagePaywallEventRegistrationScope oldWidget) =>
      !identical(registration, oldWidget.registration);
}
