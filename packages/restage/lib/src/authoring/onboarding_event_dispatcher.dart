import 'package:flutter/widgets.dart';

/// Signature for authored flow-screen event callbacks.
typedef SurfaceEventHandler = void Function(
  String eventId,
  Object? value,
);

/// Deprecated compatibility spelling for [SurfaceEventHandler].
@Deprecated('Use SurfaceEventHandler instead.')
typedef OnboardingEventHandler = SurfaceEventHandler;

final List<SurfaceEventHandler> _dispatcherStack = <SurfaceEventHandler>[];

/// Returns the active authored flow-event dispatcher, if any.
SurfaceEventHandler? activeSurfaceEventDispatcher() =>
    _dispatcherStack.isEmpty ? null : _dispatcherStack.last;

/// Deprecated compatibility spelling for [activeSurfaceEventDispatcher].
@Deprecated('Use activeSurfaceEventDispatcher instead.')
OnboardingEventHandler? activeOnboardingEventDispatcher() =>
    activeSurfaceEventDispatcher();

/// Provides an authored flow-event dispatch handler to its subtree.
///
/// Authored events fired in the subtree route to the flow controller's current
/// screen. Generated screen event references replace the helper at build time;
/// this dispatcher serves local-Dart widget compositions.
class RestageSurfaceEventDispatcher extends StatefulWidget {
  /// Wraps [child] and routes authored flow events fired in its subtree.
  const RestageSurfaceEventDispatcher({
    super.key,
    required this.onEvent,
    required this.child,
  });

  /// Called when an authored flow-event helper fires.
  final SurfaceEventHandler onEvent;

  /// The subtree under which authored flow-event helpers resolve to [onEvent].
  final Widget child;

  @override
  State<RestageSurfaceEventDispatcher> createState() =>
      _RestageSurfaceEventDispatcherState();
}

/// Deprecated compatibility spelling for [RestageSurfaceEventDispatcher].
@Deprecated('Use RestageSurfaceEventDispatcher instead.')
typedef RestageOnboardingEventDispatcher = RestageSurfaceEventDispatcher;

class _RestageSurfaceEventDispatcherState
    extends State<RestageSurfaceEventDispatcher> {
  @override
  void initState() {
    super.initState();
    _dispatcherStack.add(widget.onEvent);
  }

  @override
  void didUpdateWidget(RestageSurfaceEventDispatcher oldWidget) {
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
