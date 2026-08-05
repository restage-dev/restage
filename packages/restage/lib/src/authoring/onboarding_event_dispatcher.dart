import 'package:flutter/widgets.dart';

/// Signature for authored flow-surface event callbacks.
///
/// The onboarding-named spelling is retained for compatibility.
typedef OnboardingEventHandler = void Function(
  String eventId,
  Object? value,
);

/// Surface-neutral spelling for [OnboardingEventHandler].
typedef SurfaceEventHandler = OnboardingEventHandler;

final List<OnboardingEventHandler> _dispatcherStack =
    <OnboardingEventHandler>[];

/// Returns the active authored flow-event dispatcher, if any.
///
/// The onboarding-named function is retained for compatibility.
OnboardingEventHandler? activeOnboardingEventDispatcher() =>
    _dispatcherStack.isEmpty ? null : _dispatcherStack.last;

/// Provides an authored flow-event dispatch handler to its subtree.
///
/// Authored events fired in the subtree route to the flow controller's
/// **current** screen — this is a single per-flow channel, not a per-screen
/// one. In the shipping flow runtime, screens are RFW blobs whose events the
/// rendering surface entry-gates to the current screen, and the
/// `onboardingEvent` helper is replaced at build time; so this dispatcher fires
/// only for local-Dart-widget compositions, where an authored event always
/// targets whichever screen is current when it fires. (A context-scoped,
/// per-screen authored-event channel is a tracked follow-up; it would change the
/// `onboardingEvent` authoring signature.)
///
/// The onboarding-named class is retained for compatibility; new
/// surface-neutral integrations can use [RestageSurfaceEventDispatcher].
class RestageOnboardingEventDispatcher extends StatefulWidget {
  /// Wraps [child] and routes authored flow events fired in its subtree.
  const RestageOnboardingEventDispatcher({
    super.key,
    required this.onEvent,
    required this.child,
  });

  /// Called when an authored flow-event helper fires.
  final OnboardingEventHandler onEvent;

  /// The subtree under which authored flow-event helpers resolve to [onEvent].
  final Widget child;

  @override
  State<RestageOnboardingEventDispatcher> createState() =>
      _RestageOnboardingEventDispatcherState();
}

/// Surface-neutral spelling for [RestageOnboardingEventDispatcher].
typedef RestageSurfaceEventDispatcher = RestageOnboardingEventDispatcher;

class _RestageOnboardingEventDispatcherState
    extends State<RestageOnboardingEventDispatcher> {
  @override
  void initState() {
    super.initState();
    _dispatcherStack.add(widget.onEvent);
  }

  @override
  void didUpdateWidget(RestageOnboardingEventDispatcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.onEvent, widget.onEvent)) {
      final index = _dispatcherStack.lastIndexOf(oldWidget.onEvent);
      if (index >= 0) {
        _dispatcherStack[index] = widget.onEvent;
      }
    }
  }

  @override
  void dispose() {
    final index = _dispatcherStack.lastIndexOf(widget.onEvent);
    if (index >= 0) {
      _dispatcherStack.removeAt(index);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
