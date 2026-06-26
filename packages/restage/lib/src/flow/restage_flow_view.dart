// Chrome icons are Material `Icons` (bundled via `uses-material-design`); the
// widgets layer is imported directly. See `_backIcon` for why the iOS back
// affordance does not use `CupertinoIcons` (font-bundling robustness).
import 'dart:math' show max;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:rfw/rfw.dart';

import '../runtime/error_boundary.dart';
import '../runtime/state_variables.dart';
import 'flow_chrome.dart';
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
/// The controller is the single source of truth: the view never advances the
/// flow itself; it renders what the controller exposes and routes the current
/// screen's events back through [RestageFlowController.handleEvent]. The owner
/// calls [RestageFlowController.load]; the view only reacts to notifications.
/// Intercepts a screen-fired event before it reaches the controller.
///
/// Returns `true` to consume the event (the controller does not see it),
/// `false` to let it flow through to [RestageFlowController.handleEvent].
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
    this.enableSkip = false,
    this.chromeTheme,
    this.persistentChrome = true,
    this.backBuilder,
    this.skipBuilder,
    this.chromeBuilder,
    this.persistentChromeBuilder,
    this.priceQueries = const {},
  });

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
  /// forwarded to the controller exactly as before. This is the seam a paywall
  /// host uses to intercept purchase/restore initiation (running billing rather
  /// than a graph transition) while still forwarding navigation events to the
  /// flow. Null keeps the default behavior verbatim, so onboarding is untouched.
  final FlowScreenEventInterceptor? onScreenEvent;

  /// What happens on a platform system-back gesture once in-flow back is
  /// exhausted (the first screen / a barrier). Defaults to
  /// [SystemBackPolicy.popHost].
  final SystemBackPolicy systemBack;

  /// Whether to show the default skip affordance. Off by default; even when on,
  /// the affordance appears only when the current screen has a skip destination
  /// ([RestageFlowController.canSkip]), so there is never a dead skip control.
  final bool enableSkip;

  /// Visual tokens for the built-in chrome (the *Theme* rung of the
  /// customization ladder). Null keeps the platform-appropriate defaults.
  final FlowChromeTheme? chromeTheme;

  /// Whether the built-in chrome frames the flow persistently (`true`, the
  /// default — a stable bar that does not slide with content) or rides inside
  /// the animated slot (`false` — chrome animates with the screen). Governs only
  /// the built-in chrome's layer.
  final bool persistentChrome;

  /// Supplies the back affordance *widget* (the *Slots* rung). The SDK still
  /// positions it (start edge) and shows it only when [RestageFlowController.canBack];
  /// the widget owns its own [Semantics]. Null uses the themed default chevron.
  final FlowChromeAffordanceBuilder? backBuilder;

  /// Supplies the skip affordance *widget* (the *Slots* rung). The SDK still
  /// positions it (end edge) and shows it only when [enableSkip] *and* the
  /// screen has a skip destination; the widget owns its own [Semantics]. Null
  /// uses the themed default skip control.
  final FlowChromeAffordanceBuilder? skipBuilder;

  /// Owns the whole *per-screen* layout (the *Layout* rung). Receives the
  /// current [FlowChromeState] and the rendered screen, and composes them
  /// however it likes (affordances anywhere, overlays via a [Stack]). Lives
  /// inside the animated slot, so it animates with the screen. When supplied it
  /// supersedes the built-in chrome (the dev places their own affordances using
  /// `state.onBack`/`onSkip`).
  final FlowChromeBuilder? chromeBuilder;

  /// Frames the *whole flow* (the *Layout* rung). Receives the current
  /// [FlowChromeState] and the animated flow body, and frames it (a top progress
  /// bar, a persistent close). Lives outside the transition, so it stays put
  /// while screens animate beneath. When supplied it supersedes the built-in
  /// persistent chrome.
  final FlowPersistentChromeBuilder? persistentChromeBuilder;

  /// Map of productId -> live [PriceInfo] for paywall blobs rendered as flow
  /// screens.
  final Map<String, PriceInfo> priceQueries;

  @override
  State<RestageFlowView<R>> createState() => _RestageFlowViewState<R>();
}

class _RestageFlowViewState<R> extends State<RestageFlowView<R>>
    with SingleTickerProviderStateMixin {
  static const Duration _transitionDuration = Duration(milliseconds: 320);

  /// Tint for the default back/skip chrome (a recognizable interactive color).
  /// Overridable via [RestageFlowView.chromeTheme] (the Theme rung).
  static const Color _chromeColor = Color(0xFF007AFF);

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

  @override
  void initState() {
    super.initState();
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
    if (status == AnimationStatus.completed) {
      // A forward transition settled: the outgoing screen drops offstage, and
      // any screen the controller no longer lists as reachable (e.g. a
      // completed sub-flow's) is pruned.
      setState(_pruneToReachable);
    } else if (status == AnimationStatus.dismissed &&
        _isPopping &&
        !_iosEdgeSwipeInProgress) {
      // A back transition settled: remove the popped screen(s), then reset the
      // controller to rest so the revealed screen renders fully entered. NOTE:
      // `_finishPop` clears `_isPopping` first, so the `value = 1` below re-fires
      // `completed` *synchronously from within this status listener* — that arm
      // only `setState`s (which just schedules), so it is safe and terminates.
      // Do not set `_transition.value` inside `_pruneToReachable` or this would
      // loop.
      _finishPop();
      _transition.value = 1;
    }
  }

  @override
  void didUpdateWidget(RestageFlowView<R> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_controllerChanged);
      widget.controller.addListener(_controllerChanged);
      // Abandon any in-flight transition from the old controller so a stale
      // pop can't settle into the new controller's freshly-synced stack.
      _transition.stop();
      _isPopping = false;
      _iosEdgeSwipeInProgress = false;
      _clearStack();
      _syncFromController();
    }
    if (!identical(oldWidget.priceQueries, widget.priceQueries)) {
      _populateAllData();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dependenciesReady = true;
    _populateAllData();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_controllerChanged);
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
      priceQueries: widget.priceQueries,
      includeInheritedData: _dependenciesReady,
    );
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
  /// target), disposing their runtimes, and re-initializes the revealed
  /// screen's transition wrapper so it settles fully visible.
  void _finishPop() {
    while (_stack.length - 1 > _popTargetIndex) {
      final removed = _stack.removeLast();
      _disposeRuntimeAfterFrame(removed.runtime);
    }
    // Re-init the revealed screen's transition wrapper so it settles fully
    // visible (see [_MountedScreen.episode] for why a fresh wrapper is needed
    // here). The guard holds on every real path — the loop above leaves
    // `_popTargetIndex` at `_stack.length - 1` — but stays defensive in case the
    // stack was cleared mid-pop (e.g. a controller swap or fail-closed).
    if (_popTargetIndex < _stack.length) {
      _stack[_popTargetIndex].episode++;
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
      final screens = IgnorePointer(ignoring: transitionRunning, child: stack);
      if (widget.persistentChromeBuilder != null) {
        // Layout rung (frame): the host owns the persistent layer, framing the
        // whole animated flow body.
        body =
            widget.persistentChromeBuilder!(context, _chromeState(), screens);
      } else if (widget.persistentChrome && widget.chromeBuilder == null) {
        // Built-in persistent chrome frames the flow outside the animated stack,
        // so it stays put while screens animate beneath. Suppressed when a
        // per-screen chromeBuilder owns the chrome, or when persistentChrome is
        // false (the per-screen path in _buildEntry builds it instead).
        body = Stack(
          fit: StackFit.passthrough,
          children: <Widget>[
            screens,
            ..._buildBuiltInChrome(context),
          ],
        );
      } else {
        body = screens;
      }
    }
    return _wrapWithSystemBack(context, _wrapWithIosEdgeSwipe(context, body));
  }

  /// Snapshots the controller's chrome-relevant state (plus the view-local
  /// transition direction) for the Layout-rung builders. `canSkip` reflects the
  /// controller's capability (a skip destination exists), independent of
  /// [enableSkip] — a Layout-rung dev decides for themselves whether to show a
  /// skip control.
  FlowChromeState _chromeState() {
    final controller = widget.controller;
    return FlowChromeState(
      onBack: controller.back,
      onSkip: controller.skip,
      canBack: controller.canBack,
      canSkip: controller.canSkip,
      isForward: !_isPopping,
      screenId: controller.currentScreenId,
      isComplete: controller.isComplete,
      isBusy: controller.isBusy,
    );
  }

  /// The built-in back/skip chrome — a platform-styled back affordance shown
  /// when [RestageFlowController.canBack], and an optional skip affordance shown
  /// only when [RestageFlowView.enableSkip] *and* the screen has a skip
  /// destination. Restyled by [RestageFlowView.chromeTheme] (the Theme rung) and
  /// placed either persistently or per-screen by
  /// [RestageFlowView.persistentChrome]. Both affordances are
  /// Semantics-reachable. (The Slots/Layout rungs layer over this default.)
  List<Widget> _buildBuiltInChrome(BuildContext context) {
    final controller = widget.controller;
    final theme = widget.chromeTheme;
    final textDirection = Directionality.of(context);
    // Inset inside the device's safe area (status bar / notch) when a
    // MediaQuery is available; degrade gracefully to zero when embedded without
    // one. (Avoids requiring a MediaQuery ancestor that SafeArea would.)
    final safe = MediaQuery.maybeOf(context)?.padding ?? EdgeInsets.zero;
    final color = theme?.color ?? _chromeColor;
    final padding = theme?.padding ?? const EdgeInsets.all(12);
    // While the controller is busy a back/skip tap would be a no-op (the same
    // gate as handleEvent/back/skip), so the auto-shown chrome is held inert
    // without changing visual opacity.
    final busy = controller.isBusy;
    Widget inertWhenBusy(Widget child) => IgnorePointer(
          ignoring: busy,
          child: child,
        );
    return <Widget>[
      if (controller.canBack)
        Positioned.directional(
          textDirection: textDirection,
          top: safe.top,
          start: safe.left,
          // The SDK's auto-shown back affordance is a pure history pop — an
          // unambiguous "go back one screen", consistent with the platform
          // system-back gesture (see _wrapWithSystemBack). The reserved `back`
          // event hook is for an author-PLACED in-screen back control. A Slots
          // backBuilder supplies the widget (owning its own Semantics) but is
          // still wired to the same pure pop.
          child: inertWhenBusy(
            widget.backBuilder?.call(context, controller.back) ??
                _chromeButton(
                  label: 'Back',
                  padding: padding,
                  onPressed: controller.back,
                  child: Icon(
                    theme?.backIcon ?? _backIcon,
                    color: color,
                    size: theme?.size ?? 28,
                  ),
                ),
          ),
        ),
      if (widget.enableSkip && controller.canSkip)
        Positioned.directional(
          textDirection: textDirection,
          top: safe.top,
          end: safe.right,
          child: inertWhenBusy(
            widget.skipBuilder?.call(context, controller.skip) ??
                _chromeButton(
                  label: 'Skip',
                  padding: padding,
                  onPressed: controller.skip,
                  child: Text(
                    theme?.skipLabel ?? 'Skip',
                    style: theme?.skipTextStyle ??
                        TextStyle(
                          color: color,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
          ),
        ),
    ];
  }

  Widget _chromeButton({
    required String label,
    required EdgeInsetsGeometry padding,
    required VoidCallback onPressed,
    required Widget child,
  }) {
    return Semantics(
      button: true,
      label: label,
      // The visual content (an icon, or a `Skip` text) is decorative: its own
      // semantics are excluded so the button exposes exactly one clean label
      // ([label]) rather than merging a duplicate (e.g. a `Skip` text label into
      // the explicit `Skip` label). The GestureDetector's tap action is an
      // ancestor of the excluded subtree, so it is preserved.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Padding(
          padding: padding,
          child: ExcludeSemantics(child: child),
        ),
      ),
    );
  }

  IconData get _backIcon {
    // Material `Icons`, not `CupertinoIcons.back`: the CupertinoIcons font ships
    // only when the consuming app depends on `cupertino_icons`, so a Cupertino
    // glyph renders as a missing-glyph box on iOS in apps that don't bundle it.
    // `Icons.arrow_back_ios_new` is the Material thin back chevron — an
    // iOS-appropriate shape that ships with `uses-material-design`.
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return Icons.arrow_back_ios_new;
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        return Icons.arrow_back;
    }
  }

  bool get _canStartIosEdgeSwipe {
    if (defaultTargetPlatform != TargetPlatform.iOS) return false;
    if (_stack.length < 2) return false;
    if (!widget.controller.canBack || widget.controller.isBusy) return false;
    if (_isPopping || _iosEdgeSwipeInProgress) return false;
    return _transition.status == AnimationStatus.completed;
  }

  /// Mirrors Flutter's Cupertino route edge detector for in-flow back. The
  /// platform route gesture cannot start while `PopScope.canPop` is false, so
  /// the flow owns this narrow edge band only when controller history exists.
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
    widget.controller.back();
    if (!mounted) return;
    if (widget.controller.currentScreenEntryId != targetEntryId) {
      _cancelIosEdgeSwipe();
      return;
    }
    _iosEdgeSwipeInProgress = false;
    if (_transition.value <= 0) {
      _finishPop();
      _transition.value = 1;
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

  /// Routes the platform system-back gesture through the controller: while
  /// in-flow back is available it is consumed (`canPop:false` → `controller`
  /// pops); once exhausted the [RestageFlowView.systemBack] policy decides.
  Widget _wrapWithSystemBack(BuildContext context, Widget child) {
    final controller = widget.controller;
    final policy = widget.systemBack;
    return PopScope<Object?>(
      canPop: !controller.canBack && policy.propagatesToHost,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (controller.canBack) {
          controller.back();
          return;
        }
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
      onError: (error, stack) {
        if (screen.entryId == controller.currentScreenEntryId) {
          controller.reportRenderFailure(error);
        }
        widget.onRuntimeError?.call(error, stack);
      },
      errorReplacement: (_, __, ___) => const SizedBox.shrink(),
      child: RemoteWidget(
        runtime: screen.runtime,
        data: screen.data,
        widget: kFlowScreenWidget,
        onEvent: (name, args) {
          // Inert unless this is the owning controller's current screen.
          if (screen.entryId != controller.currentScreenEntryId) return;
          final normalized = normalizeEventArgs(args);
          // The owner's interceptor runs first: if it consumes the event
          // (e.g. a paywall host running billing for purchase/restore), the
          // controller never sees it — no speculative graph transition.
          if (widget.onScreenEvent?.call(name, normalized) ?? false) return;
          controller.handleEvent(name, normalized);
        },
      ),
    );

    // Hold the RFW content under a stable key so that when an episode rebuilds
    // the transition wrapper fresh (see below), the content's element — and its
    // RFW state — is *moved* into the new wrapper rather than re-inflated.
    final content = KeyedSubtree(key: screen.contentKey, child: child);

    // Per-screen chrome rides inside the animated slot with the current (top)
    // screen. The Layout-rung chromeBuilder owns the whole per-screen layout
    // when supplied; otherwise the built-in chrome rides here when
    // persistentChrome is false (the persistent path overlays it in `build`).
    Widget framed = content;
    if (isTop) {
      if (widget.chromeBuilder != null) {
        framed = widget.chromeBuilder!(context, _chromeState(), content);
      } else if (!widget.persistentChrome) {
        framed = Stack(
          fit: StackFit.passthrough,
          children: <Widget>[content, ..._buildBuiltInChrome(context)],
        );
      }
    }

    final visible = isTop || isCompanion;
    // The top screen plays the primary animation (entering on a push, exiting
    // on a pop); its companion plays the mirror (secondary) animation as it is
    // covered/revealed. Settled (and offstage) screens stay at rest. The pop
    // direction is the same builder run in reverse (`isForward: false`).
    Animation<double> primary = kAlwaysCompleteAnimation;
    Animation<double> secondary = kAlwaysDismissedAnimation;
    if (isTop) {
      primary = _transition.view;
    } else if (isCompanion) {
      secondary = _transition.view;
    }
    final builder = widget.transition ?? defaultFlowTransitionBuilder;
    final transitioned =
        builder(context, primary, secondary, framed, !_isPopping);

    // Offstage screens stay mounted (state preserved) but are not painted, not
    // hit-tested, and their tickers are paused. The transition wrapper is keyed
    // by the screen's episode so that when a back settles this screen it
    // rebuilds fresh (see `_finishPop` / [_MountedScreen.episode]) — the
    // transition re-derives from the screen's current role instead of a stale
    // one — while [content]'s stable key moves the screen's element (and state)
    // into the new wrapper unharmed.
    return Offstage(
      offstage: !visible,
      child: TickerMode(
        enabled: visible,
        child: KeyedSubtree(
          key: ValueKey<int>(screen.episode),
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

  /// A stable key for this screen's RFW content subtree. When a cover→reveal
  /// episode rebuilds the transition wrapper fresh (see [episode]), the content
  /// element is *moved* under this key rather than re-inflated, so the screen's
  /// preserved state (RFW `state.x`, scroll position, entered data) survives —
  /// the keep-mounted keystone.
  final GlobalKey contentKey = GlobalKey();

  /// Incremented when a back settles this screen as the revealed top (see
  /// `_finishPop`). The transition wrapper is keyed by this so the settled
  /// screen builds a *fresh* wrapper.
  ///
  /// The shared-axis/Cupertino transitions wrap the child in nested
  /// `DualTransitionBuilder`s, which repoint their internal proxy animations
  /// only when their effective direction *changes*. Reused on a persistent
  /// element across a cover (which leaves the secondary path resolved against
  /// the shared controller) and then the pop's rest reset, the wrapper reads
  /// the controller's rest value as "fully covered" and stays played out (faded
  /// to opacity 0 / slid off) — onstage but invisible. Rebuilding the wrapper
  /// fresh on settle re-derives from the now-current roles, so the screen lands
  /// fully visible. The content element survives via [contentKey].
  int episode = 0;
}
