import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

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
    if (isReservedCommerceEventName(name)) return;
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
  });

  /// Called when an authored helper fires for this dispatcher.
  final PaywallEventHandler onEvent;

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
    _registration.updateTarget(
      RestagePaywallEventTargetScope.maybeOf(context),
    );
  }

  @override
  void didUpdateWidget(RestagePaywallEventDispatcher old) {
    super.didUpdateWidget(old);
    if (!identical(old.onEvent, widget.onEvent)) {
      _registration.updateHandler(_dropReservedEvents(widget.onEvent));
    }
  }

  @override
  void dispose() {
    _registration.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _RestagePaywallEventBuildScope(
        registration: _registration,
        child: widget.child,
      );
}

final class _RestagePaywallEventBuildScope extends StatelessWidget {
  const _RestagePaywallEventBuildScope({
    required this.registration,
    required this.child,
  });

  final RestagePaywallEventDispatchRegistration registration;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;

  @override
  StatelessElement createElement() =>
      _RestagePaywallEventBuildScopeElement(this);
}

final class _RestagePaywallEventBuildScopeElement extends StatelessElement {
  _RestagePaywallEventBuildScopeElement(
    _RestagePaywallEventBuildScope super.widget,
  );

  late final BuildScope _buildScope = BuildScope(
    scheduleRebuild: _scheduleBuildScopeFlush,
  );
  int? _frameCallbackId;
  var _postFrameCallbackScheduled = false;

  @override
  BuildScope get buildScope => _buildScope;

  void _scheduleBuildScopeFlush() {
    if (_frameCallbackId != null || _postFrameCallbackScheduled) return;
    _frameCallbackId = SchedulerBinding.instance.scheduleFrameCallback(
      _beginBuildScopeFlush,
    );
  }

  void _beginBuildScopeFlush(Duration _) {
    _frameCallbackId = null;
    scheduleMicrotask(_flushWhenAncestorsAreClean);
  }

  void _flushWhenAncestorsAreClean() {
    if (!mounted) return;
    var hasDirtyAncestor = false;
    visitAncestorElements((ancestor) {
      hasDirtyAncestor = ancestor.dirty;
      return !hasDirtyAncestor;
    });
    if (hasDirtyAncestor) {
      _postFrameCallbackScheduled = true;
      SchedulerBinding.instance.addPostFrameCallback(_flushAfterFrame);
      return;
    }
    _flushBuildScope();
  }

  void _flushAfterFrame(Duration _) {
    _postFrameCallbackScheduled = false;
    _flushBuildScope();
  }

  void _flushBuildScope() {
    final buildOwner = owner;
    if (!mounted || buildOwner == null) return;
    final scope = widget as _RestagePaywallEventBuildScope;
    RestagePaywallEventDispatchAuthority.runBuild(
      scope.registration,
      () => buildOwner.buildScope(this),
    );
  }

  @override
  void performRebuild() {
    final scope = widget as _RestagePaywallEventBuildScope;
    RestagePaywallEventDispatchAuthority.runBuild(
      scope.registration,
      () => super.performRebuild(),
    );
  }

  @override
  void unmount() {
    final callbackId = _frameCallbackId;
    if (callbackId != null) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(callbackId);
    }
    _frameCallbackId = null;
    _postFrameCallbackScheduled = false;
    super.unmount();
  }
}
