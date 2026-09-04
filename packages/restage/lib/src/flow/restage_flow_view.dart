import 'dart:math' show max;

import 'package:flutter/foundation.dart' show defaultTargetPlatform, internal;
import 'package:flutter/scheduler.dart' show SchedulerBinding, SchedulerPhase;
import 'package:flutter/widgets.dart';
import 'package:rfw/rfw.dart';

import '../analytics/render_event_privacy.dart';
import '../authoring/onboarding_event_dispatcher.dart'
    show RestageFlowEventRegistration;
import '../runtime/context_data.dart';
import '../runtime/error_boundary.dart';
import '../runtime/event_demux.dart' show isReservedCommerceEventName;
import 'flow_controller.dart';
import 'flow_runtime_support.dart';
import 'flow_transitions.dart';
import 'system_back_policy.dart';

/// Controller-driven rendering surface for a server-driven flow.
///
/// Given a [RestageFlowController], renders the current screen as an RFW
/// `RemoteWidget` in its own isolated runtime, behind the fail-closed
/// [RuntimeErrorBoundary]. Each screen visit gets its own [Runtime] +
/// [DynamicContent] slot so screens never share live render state.
///
/// On forward navigation the prior screen stays **mounted** (kept offstage) so
/// its element — and therefore all of its state — is preserved; back restores
/// that still-mounted instance. The view mirrors the controller's reachable
/// screen history (bounded by the controller's per-frame cap), so what is
/// mounted always matches what `canBack` can reach.
///
/// The view paints no navigation controls. While the flow has history behind
/// the current screen it registers matching [LocalHistoryEntry]s on the
/// enclosing [ModalRoute], so an `AppBar` or `CupertinoNavigationBar` in the
/// screen implies a back control, and the app bar's back button and system back
/// each pop one screen.
///
/// The in-flow leading-edge swipe on iOS is the view's own. A route holding
/// local history turns its own back gesture off, so the two are never live at
/// the same time: the view owns the gesture while the flow has history, and the
/// host route owns it again once in-flow back is exhausted.
///
/// The controller is the single source of truth: the view never advances the
/// flow itself; it renders what the controller exposes and routes the current
/// screen's events back through [RestageFlowController.handleEvent]. The owner
/// calls [RestageFlowController.load]; the view only reacts to notifications.
/// Intercepts a screen-fired event before it reaches the controller.
///
/// Returns `true` to consume the event (the controller does not see it),
/// `false` to let it flow through to [RestageFlowController.handleEvent].
///
/// This is a host-owned escape hatch that runs BEFORE the controller's capped
/// path, so the event [name] is NOT filtered by the general-surface
/// custom-event/host-signal cap. Its arguments have had the SDK-private
/// Measurement namespace removed. Treat the name as untrusted content on a
/// general / server-delivered surface — see [RestageFlowView.onScreenEvent].
typedef FlowScreenEventInterceptor = bool Function(
  String name,
  Map<String, Object?> args,
);

final class RestageFlowView<R> extends StatefulWidget {
  /// Creates a flow rendering surface bound to [controller].
  const RestageFlowView({
    super.key,
    required this.controller,
    this.transition,
    this.loadingBuilder,
    this.onRuntimeError,
    this.onScreenEvent,
    this.systemBack = SystemBackPolicy.popHost,
    this.context,
  }) : staged = false;

  const RestageFlowView._staged({
    required this.controller,
    this.transition,
    this.loadingBuilder,
    this.systemBack = SystemBackPolicy.popHost,
  })  : staged = true,
        onRuntimeError = null,
        onScreenEvent = null,
        context = null;

  /// The flow brain whose current screen this view renders.
  final RestageFlowController<R> controller;

  /// Overrides the screen transition. Defaults to a platform-adaptive forward
  /// transition (Cupertino push on iOS/macOS, Material-3 shared-axis elsewhere).
  final FlowTransitionBuilder? transition;

  /// Builder shown while no screen is mounted (loading / before the first
  /// screen).
  final WidgetBuilder? loadingBuilder;

  /// Called when a screen's subtree throws during build. The owner decides any
  /// host-facing response; the controller has already failed closed.
  final void Function(Object error, StackTrace stack)? onRuntimeError;

  /// Optional per-screen event interceptor consulted *before* the controller.
  ///
  /// When supplied and it returns `true`, the event is treated as consumed and
  /// is **not** forwarded to [RestageFlowController.handleEvent] — the owner has
  /// handled it out-of-band. When it returns `false` (or is null), the event is
  /// forwarded to the controller exactly as before. This lets a host handle an
  /// app-owned action while still forwarding navigation events to the flow.
  /// Null keeps the default behavior verbatim, so onboarding is untouched.
  ///
  /// > **This is an UNCAPPED, host-owned escape hatch.** It receives the screen
  /// > event name *before* the controller's capped path — so it is NOT
  /// > governed by the general-surface custom-event/host-signal cap (which
  /// > governs the `onEvent`/`FlowCustomEvent` channel). Its arguments exclude
  /// > the SDK-private Measurement namespace. On a general / server-delivered
  /// > surface the event name is untrusted content the document author chose; a
  /// > host that switches on the name here owns that decision as reviewed app
  /// > code and **must not** branch an unrecognized name into a privileged
  /// > action. Prefer the capped `onEvent` channel for general-surface behavior;
  /// > use this only for host-reviewed handling.
  final FlowScreenEventInterceptor? onScreenEvent;

  /// What happens on a platform system-back gesture once in-flow back is
  /// exhausted (the first screen / a barrier). Defaults to
  /// [SystemBackPolicy.popHost].
  ///
  /// While in-flow back is still available the enclosing route's local history
  /// owns the gesture and it pops one screen; on iOS the in-flow leading-edge
  /// swipe is the surface's own.
  final SystemBackPolicy systemBack;

  /// Host-supplied render data, published to the surface as `data.context.*`.
  ///
  /// Values support 32 collection levels below the root, 10,000 retained
  /// normalized nodes including the root, and 100,000 inspected map entries or
  /// list elements per normalization. Null map values are omitted; null list
  /// elements are dropped and lists compact. Invalid values, unreadable
  /// collections, and exceeded limits throw in debug. Release reports
  /// diagnostics and omits the offending value or collection.
  ///
  /// Accepted input is normalized and copied synchronously. Equal normalized
  /// snapshots issue no renderer update. Null (the default) publishes no
  /// `data.context` namespace at all.
  ///
  /// An enclosing Restage surface that publishes its own render data supersedes
  /// this value; it applies whenever no enclosing surface supplies any.
  final Map<String, Object?>? context;

  /// Whether this is the offstage candidate layer of a surface swap. A staged
  /// view owns no route state — no local history entries, no [PopScope] — so
  /// the visible layer keeps sole ownership of the route's pop.
  ///
  /// Package-internal: the surface owns staging; a host never sets this.
  @internal
  final bool staged;

  /// Builds the candidate layer of a surface swap.
  @internal
  static RestageFlowView<R> staging<R>({
    required RestageFlowController<R> controller,
    FlowTransitionBuilder? transition,
    WidgetBuilder? loadingBuilder,
    SystemBackPolicy systemBack = SystemBackPolicy.popHost,
  }) =>
      RestageFlowView<R>._staged(
        controller: controller,
        transition: transition,
        loadingBuilder: loadingBuilder,
        systemBack: systemBack,
      );

  @override
  State<RestageFlowView<R>> createState() => _RestageFlowViewState<R>();
}

class _RestageFlowViewState<R> extends State<RestageFlowView<R>>
    with SingleTickerProviderStateMixin {
  static const Duration _transitionDuration = Duration(milliseconds: 320);

  static const double _iosEdgeSwipeWidth = 20;
  static const double _iosEdgeSwipeMinFlingVelocity = 1;
  static const Duration _iosEdgeSwipeSettleDuration =
      Duration(milliseconds: 350);
  static const Curve _iosEdgeSwipeSettleCurve = Curves.fastEaseInToSlowEaseOut;

  late final FlowScreenLibraries _libraries;

  final List<_MountedScreen> _stack = <_MountedScreen>[];

  late final AnimationController _transition;

  /// Whether the current transition is a back (pop). Drives the transition
  /// direction (`isForward: false`) and, on settle, the removal of the popped
  /// screen(s). The single [_transition] controller runs forward for a push and
  /// reverse for a pop.
  bool _isPopping = false;

  /// While [_isPopping], the index in [_stack] of the screen being revealed; the
  /// entries above it are the ones being popped (removed when the pop settles).
  int _popTargetIndex = 0;
  bool _dependenciesReady = false;
  bool _iosEdgeSwipeInProgress = false;
  ContextSnapshot? _widgetContext;
  ContextSnapshot? _context;
  bool _inheritsContextSnapshot = false;

  /// The enclosing route, if any, that carries this flow's back history.
  ModalRoute<dynamic>? _hostRoute;

  /// One entry per screen the controller can still pop back to.
  final List<LocalHistoryEntry> _historyEntries = <LocalHistoryEntry>[];

  /// Set while the view removes its own entries, so the route's synchronous
  /// `onRemove` callback does not pop the controller a second time.
  bool _removingHistory = false;

  /// Set while a deferred history sync is queued, so a burst of notifications
  /// inside one build phase schedules a single post-frame sync.
  bool _historySyncScheduled = false;

  void _refreshWidgetContext() {
    final raw = widget.context;
    _widgetContext =
        raw == null ? null : ContextSnapshot.of(raw, previous: _widgetContext);
    if (!_inheritsContextSnapshot) _context = _widgetContext;
  }

  @override
  void initState() {
    super.initState();
    _refreshWidgetContext();
    _transition = AnimationController(
      vsync: this,
      duration: _transitionDuration,
      value: 1,
    )..addStatusListener(_onTransitionStatus);
    _libraries = FlowScreenLibraries();
    widget.controller.addListener(_controllerChanged);
    _syncFromController();
  }

  void _onTransitionStatus(AnimationStatus status) {
    if (!mounted) return;
    if (status == AnimationStatus.completed && !_isPopping) {
      // A forward transition settled: the outgoing screen drops offstage, and
      // any screen the controller no longer lists as reachable (e.g. a
      // completed sub-flow's) is pruned. A pop that starts from rest passes
      // through this status on its way to `reverse`, and must not prune yet.
      setState(_pruneToReachable);
    } else if (status == AnimationStatus.dismissed &&
        _isPopping &&
        !_iosEdgeSwipeInProgress) {
      // A back transition settled: drop the popped screen(s). The controller
      // is left at rest where it stopped; a screen at rest does not read it.
      setState(_finishPop);
    }
  }

  @override
  void didUpdateWidget(RestageFlowView<R> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _refreshWidgetContext();
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_controllerChanged);
      widget.controller.addListener(_controllerChanged);
      // Abandon any in-flight transition from the old controller so a stale
      // pop can't settle into the new controller's freshly-synced stack.
      _transition.stop();
      _isPopping = false;
      _iosEdgeSwipeInProgress = false;
      _clearStack();
      _dropLocalHistory();
      _syncFromController();
      _requestLocalHistorySync();
      return;
    }
    if (oldWidget.staged != widget.staged) {
      if (widget.staged) _dropLocalHistory();
      _requestLocalHistorySync();
    }
    _publishAllContext();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = RestageContextSnapshotScope.maybeOf(context);
    // Only a scope that actually carries a snapshot supersedes this widget's
    // own [context]; an enclosing surface with none leaves this widget
    // self-published.
    _inheritsContextSnapshot = scope?.snapshot != null;
    _context = scope?.snapshot ?? _widgetContext;
    _dependenciesReady = true;
    _populateAllData();
    final route = ModalRoute.of(context);
    if (!identical(route, _hostRoute)) {
      _dropLocalHistory();
      _hostRoute = route;
    }
    _requestLocalHistorySync();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_controllerChanged);
    _dropLocalHistory();
    _transition.dispose();
    // The screen RemoteWidgets are already detached by the time the view
    // disposes, so each runtime has no remaining listeners and disposes
    // cleanly. (DynamicContent is not disposable and is reclaimed by GC.)
    for (final screen in _stack) {
      screen.runtime.dispose();
    }
    _stack.clear();
    super.dispose();
  }

  void _controllerChanged() {
    if (!mounted) return;
    setState(_syncFromController);
    _requestLocalHistorySync();
  }

  /// Runs [_syncLocalHistory], deferring to a post-frame callback while the
  /// build phase is running.
  ///
  /// Adding an entry calls `Route.changedInternalState` directly, and a route
  /// skips its own `setState` during that phase — the inherited pop state would
  /// stay stale for the frame. Removal already defers itself.
  void _requestLocalHistorySync() {
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      _syncLocalHistory();
      return;
    }
    if (_historySyncScheduled) return;
    _historySyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _historySyncScheduled = false;
      if (!mounted) return;
      _syncLocalHistory();
    });
  }

  /// Matches the route's local-history entries to the controller's back depth.
  ///
  /// Adding or removing an entry marks the host route's state dirty, so this
  /// runs from the controller listener and the lifecycle callbacks, never from
  /// `build`. With no enclosing route, and on a staged layer, there is nothing
  /// to mirror.
  void _syncLocalHistory() {
    final route = _hostRoute;
    if (route == null || widget.staged) return;
    final hadEntries = _historyEntries.isNotEmpty;
    final depth = widget.controller.backDepth;
    if (_historyEntries.length > depth) {
      _removingHistory = true;
      try {
        while (_historyEntries.length > depth) {
          _historyEntries.removeLast().remove();
        }
      } finally {
        _removingHistory = false;
      }
    }
    while (_historyEntries.length < depth) {
      final entry = LocalHistoryEntry(onRemove: _handleLocalHistoryRemoved);
      _historyEntries.add(entry);
      route.addLocalHistoryEntry(entry);
    }
    if (hadEntries != _historyEntries.isNotEmpty) {
      _announceRouteCanHandlePop(route);
    }
  }

  /// Tells the platform that the framework now handles back, or hands the
  /// question back to the route.
  ///
  /// A route dispatches [NavigationNotification] when a [PopScope] registers or
  /// changes, never when its local history does, so the engine would otherwise
  /// keep the answer it was given before the flow had history — and Android
  /// system back would leave the app instead of stepping back a screen.
  void _announceRouteCanHandlePop(ModalRoute<dynamic> route) {
    if (!mounted) return;
    NavigationNotification(
      // Mirrors the route's own recomputation. An enclosing navigator raises a
      // false to true when it can pop for its own reasons.
      canHandlePop: _historyEntries.isNotEmpty ||
          route.popDisposition == RoutePopDisposition.doNotPop,
    ).dispatch(context);
  }

  /// Drops every entry this view registered, without popping the controller.
  void _dropLocalHistory() {
    if (_historyEntries.isEmpty) return;
    final entries = List<LocalHistoryEntry>.of(_historyEntries);
    _historyEntries.clear();
    _removingHistory = true;
    try {
      for (final entry in entries.reversed) {
        entry.remove();
      }
    } finally {
      _removingHistory = false;
    }
  }

  /// The route popped one of this view's entries (an app bar back button,
  /// system back, or the route's back gesture): navigate the flow to match.
  void _handleLocalHistoryRemoved() {
    if (_removingHistory) return;
    if (_historyEntries.isNotEmpty) _historyEntries.removeLast();
    if (!mounted) return;
    widget.controller.back();
    // `back()` is a no-op while the controller is busy, and the route has
    // already dropped the entry. Re-add what the flow still needs so route and
    // flow can never stay disagreed.
    if (_historyEntries.length != widget.controller.backDepth) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncLocalHistory();
      });
    }
  }

  /// Reconciles the mounted stack with the controller's current screen.
  ///
  /// The view is a mirror of the controller: a brand-new current screen is a
  /// forward push (mount + animate in); a current screen already mounted below
  /// the top is a back (reverse-animate, popping the entries above it on
  /// settle); screens the controller no longer lists as reachable (e.g. a
  /// completed sub-flow's) are pruned once a transition settles. The
  /// controller's per-frame history cap is the only bound, so what is mounted
  /// always matches what `canBack` can reach.
  void _syncFromController() {
    final controller = widget.controller;
    final entryId = controller.currentScreenEntryId;
    final library = controller.currentLibrary;
    if (entryId == null || library == null) {
      // No current screen. If the flow failed closed, drop the stack so a
      // broken screen never lingers; otherwise this is a transient gap (e.g.
      // crossing a sub-flow boundary) and the prior screen is held visible.
      if (controller.isUnavailable) {
        _clearStack();
      }
      return;
    }
    if (_stack.isNotEmpty && _stack.last.entryId == entryId) return;
    final existingIndex = _stack.indexWhere((s) => s.entryId == entryId);
    if (existingIndex >= 0) {
      // BACK: the target is still mounted below the top — reverse-animate to it
      // (its preserved instance is restored, not re-decoded); the popped
      // entries are removed when the pop settles. If a pop is already in flight
      // (a second back arrived before it settled — e.g. queued system-back),
      // just retarget it deeper rather than restarting the controller, which
      // would re-start an already-active ticker.
      _popTargetIndex = existingIndex;
      if (!_isPopping) {
        _isPopping = true;
        _transition.reverse(from: 1);
      }
      return;
    }
    // FORWARD: a new screen (a same-frame push or entering a sub-flow). Keep the
    // prior screens mounted and push this one on top.
    _isPopping = false;
    final isFirstScreen = _stack.isEmpty;
    final mounted = _MountedScreen(
      entryId: entryId,
      runtime: _libraries.runtimeFor(library),
      data: DynamicContent(),
    );
    _stack.add(mounted);
    _populateData(mounted);
    if (isFirstScreen) {
      // The first screen appears at rest — no enter animation.
      _transition.value = 1;
    } else {
      _transition.forward(from: 0);
    }
  }

  void _populateAllData() {
    for (final screen in _stack) {
      _populateData(screen);
    }
  }

  void _populateData(_MountedScreen screen) {
    populateFlowScreenData(
      context,
      screen.data,
      includeInheritedData: _dependenciesReady,
      contextPublisher: screen.contextPublisher,
      hostContext: _context,
    );
  }

  void _publishAllContext() {
    for (final screen in _stack) {
      screen.contextPublisher.publishSnapshot(_context);
    }
  }

  /// Drops mounted screens the controller no longer lists as reachable (e.g. a
  /// completed sub-flow's), disposing their runtimes. Called once a transition
  /// settles, so an outgoing screen stays mounted while it animates out.
  void _pruneToReachable() {
    final reachable = widget.controller.reachableScreenEntryIds.toSet();
    _stack.removeWhere((screen) {
      if (reachable.contains(screen.entryId)) return false;
      _disposeRuntimeAfterFrame(screen.runtime);
      return true;
    });
  }

  /// Removes the screen(s) popped by a back (everything above the revealed
  /// target), disposing their runtimes.
  void _finishPop() {
    while (_stack.length - 1 > _popTargetIndex) {
      final removed = _stack.removeLast();
      _disposeRuntimeAfterFrame(removed.runtime);
    }
    _iosEdgeSwipeInProgress = false;
    _isPopping = false;
  }

  void _clearStack() {
    if (_stack.isEmpty) return;
    for (final screen in _stack) {
      _disposeRuntimeAfterFrame(screen.runtime);
    }
    _stack.clear();
  }

  /// Disposes a runtime after the current frame, once the rebuild has detached
  /// its `RemoteWidget` (so it has no remaining listeners).
  void _disposeRuntimeAfterFrame(Runtime runtime) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      runtime.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_stack.isEmpty) {
      body = widget.loadingBuilder?.call(context) ?? const SizedBox.shrink();
    } else {
      final topIndex = _stack.length - 1;
      final transitionRunning =
          _transition.isAnimating || _iosEdgeSwipeInProgress;
      // The screen paired with the top during a transition: it plays the
      // secondary animation and stays visible while the top animates. On a
      // forward push it's the screen just beneath the top; on a back pop it's
      // the revealed target — which can be more than one below the top for a
      // multi-step back, so the screens strictly between it and the top stay
      // offstage. Outside a transition there is no companion (-1 matches no
      // index), so "who is the companion" has one source of truth.
      final companionIndex = transitionRunning
          ? (_isPopping ? _popTargetIndex : topIndex - 1)
          : -1;
      // passthrough (not expand) so the view sizes like the underlying screen:
      // it fills tight (full-screen) constraints and sizes to content under
      // unbounded ones, rather than forcing an infinite extent.
      final stack = Stack(
        fit: StackFit.passthrough,
        children: <Widget>[
          for (var i = 0; i < _stack.length; i++)
            KeyedSubtree(
              key: ValueKey<int>(_stack[i].entryId),
              child: _buildEntry(
                context,
                _stack[i],
                isTop: i == topIndex,
                isCompanion: i == companionIndex,
              ),
            ),
        ],
      );
      // While a transition is in flight no screen is interactive: the incoming
      // screen may still be transparent or off-screen, so a tap must not fire
      // its event (matching a Flutter route transition).
      body = IgnorePointer(ignoring: transitionRunning, child: stack);
    }
    return _wrapWithSystemBack(context, _wrapWithIosEdgeSwipe(context, body));
  }

  bool get _canStartIosEdgeSwipe {
    if (defaultTargetPlatform != TargetPlatform.iOS) return false;
    if (_stack.length < 2) return false;
    if (!widget.controller.canBack || widget.controller.isBusy) return false;
    if (_isPopping || _iosEdgeSwipeInProgress) return false;
    return !_transition.isAnimating;
  }

  /// Mirrors Flutter's Cupertino route edge detector for in-flow back. A route
  /// holding local history turns its own back gesture off, so the flow owns
  /// this narrow edge band exactly while controller history exists.
  Widget _wrapWithIosEdgeSwipe(BuildContext context, Widget child) {
    if (!_canStartIosEdgeSwipe && !_iosEdgeSwipeInProgress) return child;
    final textDirection = Directionality.of(context);
    final safe = MediaQuery.maybeOf(context)?.padding ?? EdgeInsets.zero;
    final dragAreaWidth = switch (textDirection) {
      TextDirection.rtl => safe.right,
      TextDirection.ltr => safe.left,
    };
    return Stack(
      fit: StackFit.passthrough,
      children: <Widget>[
        child,
        Positioned.directional(
          textDirection: textDirection,
          start: 0,
          top: 0,
          bottom: 0,
          width: max(dragAreaWidth, _iosEdgeSwipeWidth),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            excludeFromSemantics: true,
            onHorizontalDragStart: _handleIosEdgeSwipeStart,
            onHorizontalDragUpdate: _handleIosEdgeSwipeUpdate,
            onHorizontalDragEnd: _handleIosEdgeSwipeEnd,
            onHorizontalDragCancel: _cancelIosEdgeSwipe,
          ),
        ),
      ],
    );
  }

  void _handleIosEdgeSwipeStart(DragStartDetails details) {
    if (!_canStartIosEdgeSwipe) return;
    setState(() {
      _transition.stop();
      _isPopping = true;
      _iosEdgeSwipeInProgress = true;
      _popTargetIndex = _stack.length - 2;
      _transition.value = 1;
    });
  }

  void _handleIosEdgeSwipeUpdate(DragUpdateDetails details) {
    if (!_iosEdgeSwipeInProgress) return;
    final width = context.size?.width ?? 0;
    final primaryDelta = details.primaryDelta;
    if (width <= 0 || primaryDelta == null) return;
    final delta = _logicalIosEdgeDelta(primaryDelta) / width;
    _transition.value = (_transition.value - delta).clamp(0.0, 1.0);
  }

  void _handleIosEdgeSwipeEnd(DragEndDetails details) {
    if (!_iosEdgeSwipeInProgress) return;
    final width = context.size?.width ?? 0;
    if (width <= 0) {
      _cancelIosEdgeSwipe();
      return;
    }
    final velocity =
        _logicalIosEdgeDelta(details.velocity.pixelsPerSecond.dx) / width;
    final shouldCommit = _shouldCommitIosEdgeSwipe(velocity);
    if (shouldCommit) {
      _commitIosEdgeSwipe();
    } else {
      _cancelIosEdgeSwipe();
    }
  }

  double _logicalIosEdgeDelta(double value) {
    return switch (Directionality.of(context)) {
      TextDirection.rtl => -value,
      TextDirection.ltr => value,
    };
  }

  bool _shouldCommitIosEdgeSwipe(double velocity) {
    if (velocity.abs() >= _iosEdgeSwipeMinFlingVelocity) {
      return velocity > 0;
    }
    return _transition.value <= 0.5;
  }

  void _commitIosEdgeSwipe() {
    if (!_iosEdgeSwipeInProgress) return;
    if (_popTargetIndex >= _stack.length) {
      _cancelIosEdgeSwipe();
      return;
    }
    final targetEntryId = _stack[_popTargetIndex].entryId;
    // The controller listener drops the matching route entry under the removal
    // guard, so the commit pops exactly once.
    widget.controller.back();
    if (!mounted) return;
    if (widget.controller.currentScreenEntryId != targetEntryId) {
      _cancelIosEdgeSwipe();
      return;
    }
    _iosEdgeSwipeInProgress = false;
    if (_transition.value <= 0) {
      setState(_finishPop);
      return;
    }
    _transition.animateBack(
      0,
      duration: _iosEdgeSwipeSettleDuration,
      curve: _iosEdgeSwipeSettleCurve,
    );
  }

  void _cancelIosEdgeSwipe() {
    if (!_iosEdgeSwipeInProgress) return;
    final animation = _transition.animateTo(
      1,
      duration: _iosEdgeSwipeSettleDuration,
      curve: _iosEdgeSwipeSettleCurve,
    );
    animation.whenCompleteOrCancel(() {
      if (!mounted) return;
      setState(() {
        _iosEdgeSwipeInProgress = false;
        _isPopping = false;
      });
    });
  }

  /// Applies the [RestageFlowView.systemBack] policy to an exhausted system
  /// back gesture.
  ///
  /// While the flow still has history the route's local-history entries own the
  /// gesture, and a route consults its [PopScope]s before its local history —
  /// so the scope must allow the pop in that state or the history pop is
  /// starved. It is held back only while the controller is busy, when a pop
  /// would silently do nothing and leave the route a screen ahead of the flow.
  ///
  /// A staged candidate layer keeps a scope that always allows the pop: a route
  /// consults every scope, so a candidate that blocked would starve the visible
  /// layer and run its own exhausted policy.
  Widget _wrapWithSystemBack(BuildContext context, Widget child) {
    final controller = widget.controller;
    final policy = widget.systemBack;
    final staged = widget.staged;
    return PopScope<Object?>(
      canPop: staged ||
          (controller.canBack ? !controller.isBusy : policy.propagatesToHost),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || staged) return;
        // In-flow back is still available and the flow is busy: the gesture is
        // inert until the controller settles, and the policy does not apply.
        if (controller.canBack) return;
        // `dismiss` is invoked only by SystemBackPolicy.complete(), which
        // dismisses via the reserved `skip` signal. If the flow wired no skip
        // destination there is nothing to dismiss to, so warn loudly rather than
        // silently swallowing the gesture (which would trap the user, like
        // .block()) — the dev either wires skip or picks .popHost/.block().
        policy.handleExhausted(
          context,
          dismiss: () {
            if (!controller.canSkip) {
              debugPrint(
                '[restage] SystemBackPolicy.complete(): exhausted system-back '
                "has no skip destination wired (a screen on['skip'] transition "
                "or a declared customEvents['skip']), so the gesture is a no-op. "
                'Wire skip, or use SystemBackPolicy.popHost / .block().',
              );
              return;
            }
            controller.skip();
          },
        );
      },
      child: child,
    );
  }

  Widget _buildEntry(
    BuildContext context,
    _MountedScreen screen, {
    required bool isTop,
    required bool isCompanion,
  }) {
    // Capture the controller that owns this screen, so a stale event or render
    // failure routes to its owner (gated to the owner's current entry) and
    // never to a controller the view was later swapped to.
    final controller = widget.controller;
    final child = RuntimeErrorBoundary(
      key: ValueKey<int>(screen.entryId),
      onFirstBuildSuccess: () {
        controller.acknowledgeRenderedEntry(screen.entryId);
      },
      onError: (error, stack) {
        if (screen.entryId == controller.currentScreenEntryId) {
          controller.reportRenderFailure(error);
        }
        widget.onRuntimeError?.call(error, stack);
      },
      errorReplacement: (_, __, ___) => const SizedBox.shrink(),
      child: RestagePrivacyAwareRemoteWidget(
        runtime: screen.runtime,
        data: screen.data,
        widget: kFlowScreenWidget,
        mayExposeNonEmptyHostContext: () =>
            screen.contextPublisher.mayExposeNonEmptyHostContext,
        onEvent: (name, args) {
          RestageRenderEventPrivacy.run<void>(
            mayExposeNonEmptyHostContext:
                screen.contextPublisher.mayExposeNonEmptyHostContext,
            body: () {
              if (isReservedCommerceEventName(name)) return;
              // Inert unless this is the owning controller's current screen.
              if (screen.entryId != controller.currentScreenEntryId) return;
              final normalized = normalizeEventArgs(
                sanitizeAndRecordHostFlowEvent(controller, args),
              );
              // The owner's interceptor runs first. If it consumes the event,
              // the controller never sees it.
              if (widget.onScreenEvent?.call(name, normalized) ?? false) {
                return;
              }
              controller.handleEvent(name, normalized);
            },
          );
        },
      ),
    );

    // The RFW content keeps a stable key so its element, and the screen state
    // it holds, survives a change of transition wrapper.
    final content = KeyedSubtree(key: screen.contentKey, child: child);

    final visible = isTop || isCompanion;
    // While a transition runs, the top screen plays the primary animation
    // (entering on a push, exiting on a pop) and its companion the mirror
    // (secondary) animation. At rest every screen reads constant animations,
    // so the controller's resting value can never paint a screen that is on
    // its way out. The pop direction is the same builder run in reverse.
    final running = _transition.isAnimating || _iosEdgeSwipeInProgress;
    Animation<double> primary = kAlwaysCompleteAnimation;
    Animation<double> secondary = kAlwaysDismissedAnimation;
    if (running && isTop) {
      primary = _transition.view;
    } else if (running && isCompanion) {
      secondary = _transition.view;
    }
    final builder = widget.transition ?? defaultFlowTransitionBuilder;
    final transitioned =
        builder(context, primary, secondary, content, !_isPopping);

    // Offstage screens stay mounted (state preserved) but are not painted, not
    // hit-tested, and their tickers are paused.
    return RestageFlowEventRegistration(
      controller: controller,
      registration: screen,
      contentToken: screen.entryId,
      associatedHandler: controller.handleEvent,
      isCurrent: () =>
          identical(widget.controller, controller) &&
          controller.currentScreenEntryId == screen.entryId,
      mayExposeNonEmptyHostContext: () =>
          screen.contextPublisher.mayExposeNonEmptyHostContext,
      child: Offstage(
        offstage: !visible,
        child: TickerMode(
          enabled: visible,
          child: transitioned,
        ),
      ),
    );
  }
}

/// One mounted screen in the view's bounded stack: an isolated runtime + data
/// slot keyed by its controller-minted entry id.
class _MountedScreen {
  _MountedScreen({
    required this.entryId,
    required this.runtime,
    required this.data,
  });

  final int entryId;
  final Runtime runtime;
  final DynamicContent data;
  late final ContextPublisher contextPublisher = ContextPublisher(data);

  /// A stable key for this screen's RFW content subtree, so its element and
  /// preserved state (RFW `state.x`, scroll position, entered data) survive a
  /// change of transition wrapper.
  final GlobalKey contentKey = GlobalKey();
}
