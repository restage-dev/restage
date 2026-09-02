import 'dart:async';

import 'package:flutter/widgets.dart';

import '../analytics/render_event_privacy.dart';
import 'authoring_dispatch_access.dart';
import 'authoring_refusal_diagnostic.dart';

/// Signature for authored flow-screen event callbacks.
typedef SurfaceEventHandler = void Function(
  String eventId,
  Object? value,
);

/// Deprecated compatibility spelling for [SurfaceEventHandler].
@Deprecated('Use SurfaceEventHandler instead.')
typedef OnboardingEventHandler = SurfaceEventHandler;

final Object _dispatcherOwnerZoneKey = Object();
final List<_RestageEventDispatcherState> _dispatchers =
    <_RestageEventDispatcherState>[];

/// Returns the sole authored flow-event dispatcher, if one can be proven.
SurfaceEventHandler? activeSurfaceEventDispatcher() {
  if (_dispatchers.isEmpty) {
    recordAuthoringDispatcherRefusal(
      AuthoringRefusalKind.missingDispatcher,
    );
    return null;
  }
  if (_dispatchers.length != 1) {
    recordAuthoringDispatcherRefusal(
      AuthoringRefusalKind.ambiguousDispatcher,
    );
    return null;
  }
  final dispatcher = _dispatchers.single._capture(binding: null);
  if (dispatcher == null) {
    recordAuthoringDispatcherRefusal(
      AuthoringRefusalKind.ambiguousDispatcher,
    );
  }
  return dispatcher;
}

SurfaceEventHandler? surfaceEventDispatcherOf(BuildContext context) {
  final scope = context
      .dependOnInheritedWidgetOfExactType<_RestageEventDispatcherScope>();
  if (scope == null) {
    recordAuthoringDispatcherRefusal(
      AuthoringRefusalKind.missingDispatcher,
    );
    return null;
  }
  final dispatcher = scope._capture(
    binding: RestageFlowRenderEventPrivacyScope.maybeOf(context),
  );
  if (dispatcher == null) {
    recordAuthoringDispatcherRefusal(
      AuthoringRefusalKind.ambiguousDispatcher,
    );
  }
  return dispatcher;
}

Object? surfaceEventDispatcherOwnerOf(BuildContext context) => context
    .dependOnInheritedWidgetOfExactType<_RestageEventDispatcherScope>()
    ?._owner;

Object? get currentSurfaceEventDispatcherOwner =>
    Zone.current[_dispatcherOwnerZoneKey];

/// Deprecated compatibility spelling for [activeSurfaceEventDispatcher].
@Deprecated('Use activeSurfaceEventDispatcher instead.')
OnboardingEventHandler? activeOnboardingEventDispatcher() =>
    activeSurfaceEventDispatcher();

/// Provides an authored flow-event dispatch handler to its subtree.
///
/// Authored events fired in the subtree route to the flow controller's current
/// screen. Generated screen event references replace the helper at build time;
/// this dispatcher serves local-Dart widget compositions.
class RestageEventDispatcher extends StatefulWidget {
  /// Wraps [child] and routes authored flow events fired in its subtree.
  const RestageEventDispatcher({
    super.key,
    required this.onEvent,
    required this.child,
  });

  /// Called when an authored flow-event helper fires.
  final SurfaceEventHandler onEvent;

  /// The subtree under which authored flow-event helpers resolve to [onEvent].
  final Widget child;

  @override
  State<RestageEventDispatcher> createState() => _RestageEventDispatcherState();
}

final class RestageFlowEventRegistration extends StatefulWidget {
  const RestageFlowEventRegistration({
    super.key,
    required this.controller,
    required this.registration,
    required this.contentToken,
    required this.associatedHandler,
    required this.isCurrent,
    required this.mayExposeNonEmptyHostContext,
    required this.child,
  });

  final Object controller;
  final Object registration;
  final Object contentToken;
  final SurfaceEventHandler associatedHandler;
  final bool Function() isCurrent;
  final bool Function() mayExposeNonEmptyHostContext;
  final Widget child;

  @override
  State<RestageFlowEventRegistration> createState() =>
      _RestageFlowEventRegistrationState();
}

class _RestageFlowEventRegistrationState
    extends State<RestageFlowEventRegistration> {
  ({
    Object controller,
    Object owner,
    Object identity,
    Object contentToken,
    SurfaceEventHandler handler,
  })? _registered;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync(surfaceEventDispatcherOwnerOf(context) ?? this);
  }

  @override
  void didUpdateWidget(RestageFlowEventRegistration oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync(_registered?.owner ?? this);
  }

  void _sync(Object owner) {
    final registered = _registered;
    if (registered != null &&
        identical(registered.controller, widget.controller) &&
        identical(registered.owner, owner) &&
        identical(registered.identity, widget.registration) &&
        registered.contentToken == widget.contentToken &&
        registered.handler == widget.associatedHandler) {
      return;
    }
    _unregister();
    RestageFlowRenderEventPrivacyRegistry.register(
      controller: widget.controller,
      owner: owner,
      registration: widget.registration,
      contentToken: widget.contentToken,
      associatedHandler: widget.associatedHandler,
      isCurrent: _isCurrent,
      mayExposeNonEmptyHostContext: _mayExposeNonEmptyHostContext,
    );
    _registered = (
      controller: widget.controller,
      owner: owner,
      identity: widget.registration,
      contentToken: widget.contentToken,
      handler: widget.associatedHandler,
    );
  }

  bool _isCurrent() => mounted && widget.isCurrent();

  bool _mayExposeNonEmptyHostContext() =>
      !mounted || widget.mayExposeNonEmptyHostContext();

  void _unregister() {
    final registered = _registered;
    if (registered == null) return;
    RestageFlowRenderEventPrivacyRegistry.unregister(
      controller: registered.controller,
      owner: registered.owner,
      registration: registered.identity,
    );
    _registered = null;
  }

  @override
  void dispose() {
    _unregister();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RestageFlowRenderEventPrivacyScope(
        controller: widget.controller,
        registration: widget.registration,
        child: widget.child,
      );
}

final class RestageFlowEventHandlerAssociation extends StatefulWidget {
  const RestageFlowEventHandlerAssociation({
    super.key,
    required this.controller,
    required this.handler,
    required this.isCurrent,
    required this.child,
  });

  final Object controller;
  final SurfaceEventHandler handler;
  final bool Function() isCurrent;
  final Widget child;

  @override
  State<RestageFlowEventHandlerAssociation> createState() =>
      _RestageFlowEventHandlerAssociationState();
}

class _RestageFlowEventHandlerAssociationState
    extends State<RestageFlowEventHandlerAssociation> {
  ({Object controller, Object owner, SurfaceEventHandler handler})? _registered;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync(surfaceEventDispatcherOwnerOf(context));
  }

  @override
  void didUpdateWidget(RestageFlowEventHandlerAssociation oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync(_registered?.owner);
  }

  void _sync(Object? owner) {
    final registered = _registered;
    if (owner != null &&
        registered != null &&
        identical(registered.controller, widget.controller) &&
        identical(registered.owner, owner) &&
        registered.handler == widget.handler) {
      return;
    }
    _unregister();
    if (owner == null) return;
    RestageFlowRenderEventPrivacyRegistry.registerHandlerAssociation(
      controller: widget.controller,
      owner: owner,
      association: this,
      handler: widget.handler,
      isCurrent: _isCurrent,
    );
    _registered = (
      controller: widget.controller,
      owner: owner,
      handler: widget.handler,
    );
  }

  bool _isCurrent() => mounted && widget.isCurrent();

  void _unregister() {
    final registered = _registered;
    if (registered == null) return;
    RestageFlowRenderEventPrivacyRegistry.unregisterHandlerAssociation(
      owner: registered.owner,
      association: this,
    );
    _registered = null;
  }

  @override
  void dispose() {
    _unregister();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Deprecated compatibility spelling for [RestageEventDispatcher].
@Deprecated('Use RestageEventDispatcher instead.')
typedef RestageOnboardingEventDispatcher = RestageEventDispatcher;

class _RestageEventDispatcherState extends State<RestageEventDispatcher> {
  @override
  void initState() {
    super.initState();
    _dispatchers.add(this);
  }

  SurfaceEventHandler? _capture({
    required RestageFlowRenderEventPrivacyBinding? binding,
  }) {
    final handler = widget.onEvent;
    return RestageFlowRenderEventPrivacyRegistry.bindDispatcherHandler(
      owner: this,
      binding: binding,
      handler: handler,
      dispatcherIsActive: () =>
          mounted &&
          _dispatchers.any((dispatcher) => identical(dispatcher, this)),
      handlerIsCurrent: () => widget.onEvent == handler,
      invokeWithOwner: (body) {
        runZoned<void>(
          body,
          zoneValues: <Object, Object?>{_dispatcherOwnerZoneKey: this},
        );
      },
    );
  }

  @override
  void dispose() {
    _dispatchers.removeWhere((dispatcher) => identical(dispatcher, this));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _RestageEventDispatcherScope(
        owner: this,
        handler: widget.onEvent,
        child: widget.child,
      );
}

final class _RestageEventDispatcherScope extends InheritedWidget {
  const _RestageEventDispatcherScope({
    required _RestageEventDispatcherState owner,
    required SurfaceEventHandler handler,
    required super.child,
  })  : _owner = owner,
        _handler = handler;

  final _RestageEventDispatcherState _owner;
  final SurfaceEventHandler _handler;

  SurfaceEventHandler? _capture({
    required RestageFlowRenderEventPrivacyBinding? binding,
  }) =>
      _owner._capture(binding: binding);

  @override
  bool updateShouldNotify(_RestageEventDispatcherScope oldWidget) =>
      !identical(_owner, oldWidget._owner) ||
      !identical(_handler, oldWidget._handler);
}

/// Deprecated spelling of [RestageEventDispatcher].
///
/// Removed at 3.0.
@Deprecated('Use RestageEventDispatcher')
typedef RestageSurfaceEventDispatcher = RestageEventDispatcher;
