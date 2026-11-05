import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../measurement/measurement_event_sanitizer.dart'
    show isMeasurementTapEventName;
import '../runtime/event_demux.dart' show isReservedCommerceEventName;
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

/// Returns the exact current handler, or a refusing handler when lookup is
/// ambiguous. Returns `null` when no dispatcher is mounted.
///
/// Public so authoring helpers can look up the active dispatcher without a
/// `BuildContext`.
PaywallEventHandler? activeDispatcher() =>
    RestagePaywallEventDispatchAuthority.capture();

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
    this.scoped = true,
    this.mount,
  });

  /// Called when an authored helper fires for this dispatcher.
  final PaywallEventHandler onEvent;

  /// Whether every build below runs inside this dispatcher's registration.
  /// When false, only islands that fire events do, through
  /// [RestagePaywallEventDispatcher.island].
  final bool scoped;

  /// The generated mount this dispatcher renders, which its recorded events
  /// dispatch through.
  final Object? mount;

  /// Builds [island], an app widget placed in a surface, inside the
  /// registration of the nearest unscoped dispatcher above [context].
  static Widget island(BuildContext context, Widget island) {
    final scope = context
        .getInheritedWidgetOfExactType<_RestagePaywallEventRegistrationScope>();
    if (scope == null || scope.scoped) return island;
    return _RestagePaywallEventBuildScope(
      registration: scope.registration,
      child: island,
    );
  }

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
        scoped: widget.scoped,
        child: widget.scoped
            ? _RestagePaywallEventBuildScope(
                registration: _registration,
                child: widget.child,
              )
            : widget.child,
      );
}

// The registration islands below an unscoped dispatcher build inside.
final class _RestagePaywallEventRegistrationScope extends InheritedWidget {
  const _RestagePaywallEventRegistrationScope({
    required this.registration,
    required this.scoped,
    required super.child,
  });

  final RestagePaywallEventDispatchRegistration registration;
  final bool scoped;

  @override
  bool updateShouldNotify(_RestagePaywallEventRegistrationScope oldWidget) =>
      !identical(registration, oldWidget.registration) ||
      scoped != oldWidget.scoped;
}

/// Rebuilds its subtree inside the dispatch registration.
///
/// After the first build, the subtree is only rebuilt during layout, so
/// elements this scope still lists as dirty cannot be unmounted before it
/// flushes them.
final class _RestagePaywallEventBuildScope extends RenderObjectWidget {
  const _RestagePaywallEventBuildScope({
    required this.registration,
    required this.child,
  });

  final RestagePaywallEventDispatchRegistration registration;
  final Widget child;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderRestagePaywallEventBuildScope();

  @override
  RenderObjectElement createElement() =>
      _RestagePaywallEventBuildScopeElement(this);
}

final class _RestagePaywallEventBuildScopeElement extends RenderObjectElement {
  _RestagePaywallEventBuildScopeElement(
    _RestagePaywallEventBuildScope super.widget,
  );

  late final BuildScope _buildScope = BuildScope(
    scheduleRebuild: _scheduleFlush,
  );
  Element? _child;
  var _childNeedsUpdate = false;
  var _deferredFlushScheduled = false;

  @override
  BuildScope get buildScope => _buildScope;

  @override
  _RenderRestagePaywallEventBuildScope get renderObject =>
      super.renderObject as _RenderRestagePaywallEventBuildScope;

  _RestagePaywallEventBuildScope get _scope =>
      widget as _RestagePaywallEventBuildScope;

  void _scheduleFlush() {
    if (_deferredFlushScheduled) return;
    switch (SchedulerBinding.instance.schedulerPhase) {
      case SchedulerPhase.idle:
      case SchedulerPhase.postFrameCallbacks:
        // Keep the render tree clean outside a frame; flush in the next one.
        _deferredFlushScheduled = true;
        SchedulerBinding.instance.scheduleFrameCallback(_flushInNextFrame);
      case SchedulerPhase.transientCallbacks:
      case SchedulerPhase.midFrameMicrotasks:
      case SchedulerPhase.persistentCallbacks:
        renderObject.scheduleFlush();
    }
  }

  void _flushInNextFrame(Duration _) {
    _deferredFlushScheduled = false;
    if (mounted) renderObject.scheduleFlush();
  }

  void _flush() {
    final buildOwner = owner;
    if (!mounted || buildOwner == null) return;
    RestagePaywallEventDispatchAuthority.runBuild(
      _scope.registration,
      () => buildOwner.buildScope(this, () {
        if (!_childNeedsUpdate) return;
        _childNeedsUpdate = false;
        _child = updateChild(_child, _scope.child, null);
      }),
    );
  }

  @override
  void visitChildren(ElementVisitor visitor) {
    final child = _child;
    if (child != null) visitor(child);
  }

  @override
  void forgetChild(Element child) {
    assert(identical(child, _child));
    _child = null;
    super.forgetChild(child);
  }

  @override
  void mount(Element? parent, Object? newSlot) {
    super.mount(parent, newSlot);
    renderObject.flush = _flush;
    RestagePaywallEventDispatchAuthority.runBuild(
      _scope.registration,
      () => _child = updateChild(_child, _scope.child, null),
    );
  }

  @override
  void update(_RestagePaywallEventBuildScope newWidget) {
    super.update(newWidget);
    _childNeedsUpdate = true;
    renderObject.scheduleFlush();
  }

  @override
  void unmount() {
    renderObject.flush = null;
    super.unmount();
  }

  @override
  void insertRenderObjectChild(RenderObject child, Object? slot) {
    renderObject.child = child as RenderBox;
  }

  @override
  void moveRenderObjectChild(
    RenderObject child,
    Object? oldSlot,
    Object? newSlot,
  ) {
    assert(false);
  }

  @override
  void removeRenderObjectChild(RenderObject child, Object? slot) {
    assert(identical(renderObject.child, child));
    renderObject.child = null;
  }
}

final class _RenderRestagePaywallEventBuildScope extends RenderProxyBox {
  VoidCallback? flush;
  var _needsFlush = false;

  void scheduleFlush() {
    if (_needsFlush) return;
    _needsFlush = true;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    if (_needsFlush) {
      _needsFlush = false;
      final flush = this.flush;
      if (flush != null) invokeLayoutCallback<Constraints>((_) => flush());
    }
    super.performLayout();
  }
}
