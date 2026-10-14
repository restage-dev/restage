import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoApp, CupertinoPage;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, internal;
import 'package:flutter/material.dart' show MaterialApp, MaterialPage, Theme;
import 'package:flutter/scheduler.dart' show SchedulerBinding, SchedulerPhase;
import 'package:flutter/widgets.dart';
import 'package:restage_shared/restage_shared.dart' show DeliveredIconFont;
import 'package:rfw/rfw.dart';

import '../delivery/delivered_fonts.dart';
import '../delivery/raced_surface_resolver.dart';
import '../delivery/surface_sections_carrier.dart';
import '../delivery/surface_delivery_paint_boundary.dart';
import '../authoring/event_dispatcher.dart';
import '../authoring/onboarding_event_dispatcher.dart'
    show RestageFlowEventRegistration, RestageFlowEventHandlerAssociation;
import '../authoring/paywall_event_dispatch.dart';
import '../measurement/measurement_event_sanitizer.dart'
    show isMeasurementTapEventName;
import '../runtime/context_data.dart';
import '../runtime/error_boundary.dart';
import '../runtime/event_demux.dart' show isReservedCommerceEventName;
import '../runtime/local_values.dart';
import '../runtime/restage.dart';
import 'compiled_flow.dart';
import 'flow_controller.dart';
import 'flow_resolver.dart' show ResolvedFlow;
import 'flow_runtime_support.dart';
import 'flow_transitions.dart';
import 'system_back_policy.dart';

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

/// Controller-driven rendering surface for a server-driven flow.
///
/// Given a [RestageFlowController], renders the flow's screens on a nested
/// [Navigator]: one page per screen visit in-flow back can still reach, each an
/// RFW `RemoteWidget` in its own isolated runtime behind the fail-closed
/// [RuntimeErrorBoundary]. Because the screens are routes, their motion is the
/// app's own page transition, `Hero` flies between them, and the iOS
/// leading-edge swipe and Android predictive back work as they do anywhere
/// else. A [transition] replaces that motion for this flow.
///
/// A screen stays mounted while its visit is reachable, so back restores the
/// preserved instance rather than re-decoding it.
///
/// The view paints no navigation controls. A screen with history behind it
/// reports `canPop` on its own route, so an `AppBar` or
/// `CupertinoNavigationBar` in the screen implies a back control, and that
/// control and system back each pop one screen. A bar that must persist across
/// screens belongs outside the view, in the host, reading the controller.
///
/// The view needs bounded constraints, like any [Navigator].
///
/// The controller is the single source of truth: the view never advances the
/// flow itself; it renders what the controller exposes, routes the current
/// screen's events back through [RestageFlowController.handleEvent], and
/// mirrors a user-driven pop onto [RestageFlowController.back]. The owner calls
/// [RestageFlowController.load]; the view only reacts to notifications.
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

  /// Overrides the screen transition.
  ///
  /// Null (the default) uses the platform page transition — whatever the app's
  /// `pageTransitionsTheme` gives a `MaterialPage`, and the Cupertino page
  /// transition on iOS/macOS — so a flow moves like the rest of the app,
  /// including the iOS leading-edge swipe and Android's predictive back.
  ///
  /// Supplying a builder replaces that motion for every screen in this flow,
  /// including the platform's gesture-driven previews. System back and a
  /// navigation bar's back control still pop one screen.
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
  /// Events handled here appear in the build's dropped-event warning unless
  /// the flow declares them as custom events.
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
  /// While in-flow back is still available the surface takes the gesture and
  /// pops one screen; on iOS the leading-edge swipe pops one screen too.
  final SystemBackPolicy systemBack;

  /// Host-supplied render data, published to the surface as `data.context.*`.
  ///
  /// Maps and lists can nest 32 levels deep below the root. A context holds up
  /// to 10,000 values, counting the root, and each update reads at most 100,000
  /// map entries or list elements. Null map values are left out, and null list
  /// elements are removed so the list closes up. In debug builds, an invalid
  /// value, an unreadable collection, or a value over a limit throws; in
  /// release builds the SDK reports it and leaves that value or collection out.
  ///
  /// The SDK copies the values when you pass them. Passing equal values
  /// doesn't update the surface. Null, the default, publishes no host data.
  ///
  /// An enclosing Restage surface that publishes its own render data supersedes
  /// this value; it applies whenever no enclosing surface supplies any.
  final Map<String, Object?>? context;

  /// Whether this is the offstage candidate layer of a surface swap. A staged
  /// view never blocks a pop, so the visible layer keeps sole ownership of the
  /// route's pop.
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

class _RestageFlowViewState<R> extends State<RestageFlowView<R>> {
  final GlobalKey<NavigatorState> _nestedKey = GlobalKey<NavigatorState>();

  /// The flow navigator's own hero controller, so a `Hero` flies between flow
  /// screens and the enclosing app's controller is left to its own navigator.
  late final HeroController _heroes = switch (defaultTargetPlatform) {
    TargetPlatform.iOS ||
    TargetPlatform.macOS =>
      CupertinoApp.createCupertinoHeroController(),
    _ => MaterialApp.createMaterialHeroController(),
  };

  /// Runtime + data slot per screen visit, kept while the visit is reachable or
  /// its route is still on the nested navigator.
  final Map<int, _MountedScreen> _screens = <int, _MountedScreen>{};

  /// Entry ids currently published as pages, oldest first.
  List<int> _entryIds = <int>[];

  bool _dependenciesReady = false;
  ContextSnapshot? _widgetContext;
  ContextSnapshot? _context;
  bool _inheritsContextSnapshot = false;

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
    widget.controller.addListener(_controllerChanged);
    _syncFromController();
  }

  @override
  void didUpdateWidget(RestageFlowView<R> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _refreshWidgetContext();
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_controllerChanged);
      widget.controller.addListener(_controllerChanged);
      _clearScreens();
      _syncFromController();
      return;
    }
    _publishAllContext();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = RestageContextSnapshotScope.maybeOf(context);
    // Only a scope that actually carries a snapshot supersedes this widget's
    // own [context].
    _inheritsContextSnapshot = scope?.snapshot != null;
    _context = scope?.snapshot ?? _widgetContext;
    _dependenciesReady = true;
    _populateAllData();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_controllerChanged);
    _heroes.dispose();
    // The screen RemoteWidgets are already detached by the time the view
    // disposes, so each runtime has no remaining listeners and disposes
    // cleanly. (DynamicContent is not disposable and is reclaimed by GC.)
    for (final screen in _screens.values) {
      screen.local.clear();
      screen.runtime?.dispose();
    }
    _screens.clear();
    _entryIds = <int>[];
    super.dispose();
  }

  void _controllerChanged() {
    if (!mounted) return;
    setState(_syncFromController);
  }

  /// Mirrors the controller's reachable history into the paged entry ids.
  ///
  /// Only the current screen's library is exposed, so a runtime is minted when
  /// a visit first becomes current; earlier visits are already held.
  void _syncFromController() {
    final controller = widget.controller;
    final entryId = controller.currentScreenEntryId;
    final library = controller.currentLibrary;
    final nativeScreen = controller.currentNativeScreen;
    if (entryId == null || (library == null && nativeScreen == null)) {
      // No current screen. A flow that failed closed drops its screens;
      // otherwise this is a transient gap (e.g. crossing a sub-flow boundary)
      // and the prior screen is held.
      if (controller.isUnavailable) _clearScreens();
      return;
    }
    if (!_screens.containsKey(entryId)) {
      final sections = _sectionsOf(controller);
      final data = DynamicContent();
      final screen = _MountedScreen(
        entryId: entryId,
        runtime: library == null ? null : flowScreenRuntime(library),
        nativeScreen: nativeScreen,
        onEvent: (name, args) =>
            _handleScreenEvent(controller, entryId, name, args),
        data: data,
        iconFonts: sections.iconFonts,
        local: LocalValues(
          data,
          seed: switch (controller.currentScreenArtifactId) {
            final id? => sections.localSeeds[id],
            null => null,
          },
        ),
      );
      _screens[entryId] = screen;
      _populateData(screen);
    }
    _entryIds = <int>[
      for (final id in controller.reachableScreenEntryIds)
        if (_screens.containsKey(id)) id,
    ];
  }

  /// The screens hosted as routes: the visits in-flow back can reach that this
  /// view has mounted, so a navigation bar implies back exactly when the
  /// controller can pop.
  List<int> get _pagedIds => <int>[
        for (final id in widget.controller.pagedScreenEntryIds)
          if (_screens.containsKey(id)) id,
      ];

  /// Whether a transparent anchor sits beneath the first screen: the enclosing
  /// route already implies dismissal, so a navigation bar in that screen keeps
  /// implying it and leaves the flow.
  bool get _anchored =>
      !widget.staged &&
      (ModalRoute.of(context)?.impliesAppBarDismissal ?? false);

  void _populateAllData() {
    for (final screen in _screens.values) {
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
    for (final screen in _screens.values) {
      screen.contextPublisher.publishSnapshot(_context);
    }
  }

  void _clearScreens() {
    if (_screens.isEmpty) return;
    for (final screen in _screens.values) {
      screen.local.clear();
      _disposeRuntimeAfterFrame(screen.runtime);
    }
    _screens.clear();
    _entryIds = <int>[];
  }

  void _releaseScreen(int entryId) {
    final screen = _screens.remove(entryId);
    screen?.local.clear();
    if (screen == null) return;
    _disposeRuntimeAfterFrame(screen.runtime);
  }

  /// Disposes a runtime after the current frame, once the rebuild has detached
  /// its `RemoteWidget` (so it has no remaining listeners).
  void _disposeRuntimeAfterFrame(Runtime? runtime) {
    if (runtime == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      runtime.dispose();
    });
  }

  /// Runs [action] now, or after the frame while the build phase is running.
  void _runOutsideBuild(VoidCallback action) {
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      action();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => action());
  }

  /// The nested navigator finished removing a route.
  ///
  /// An entry the view no longer lists was removed because the controller moved
  /// on; an entry it still lists was popped by the user (a navigation bar back
  /// control or the leading-edge swipe), so the controller is navigated to
  /// match.
  void _handleDidRemovePage(Page<Object?> page) {
    final key = page.key;
    if (key is! ValueKey<int>) return;
    final entryId = key.value;
    if (!_entryIds.contains(entryId) ||
        !widget.controller.reachableScreenEntryIds.contains(entryId)) {
      _releaseScreen(entryId);
      return;
    }
    _runOutsideBuild(() {
      if (!mounted) return;
      final controller = widget.controller;
      if (controller.currentScreenEntryId == entryId && controller.canBack) {
        controller.back();
      }
      if (!controller.reachableScreenEntryIds.contains(entryId)) {
        _releaseScreen(entryId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_entryIds.isEmpty) {
      return _wrapWithSystemBack(
        context,
        widget.loadingBuilder?.call(context) ?? const SizedBox.shrink(),
      );
    }
    final pages = <Page<Object?>>[
      if (_anchored) const _FlowAnchorPage(),
      for (final id in _pagedIds) _pageFor(_screens[id]!),
    ];
    final navigator = HeroControllerScope(
      controller: _heroes,
      child: Navigator(
        key: _nestedKey,
        pages: pages,
        onDidRemovePage: _handleDidRemovePage,
      ),
    );
    return _wrapWithSystemBack(
      context,
      // The screens are routes, and a route fills the space its navigator is
      // given, so the view needs bounded constraints. Checked here to name the
      // widget rather than fail deep inside the navigator's overlay.
      LayoutBuilder(
        builder: (context, constraints) {
          assert(_debugCheckBounded(constraints));
          return navigator;
        },
      ),
    );
  }

  bool _debugCheckBounded(BoxConstraints constraints) {
    if (constraints.hasBoundedWidth && constraints.hasBoundedHeight) {
      return true;
    }
    throw FlutterError.fromParts(<DiagnosticsNode>[
      ErrorSummary('RestageFlowView was given unbounded constraints.'),
      ErrorDescription(
        'It hosts each flow screen as a route on its own Navigator, and a '
        'route sizes itself to the space the navigator is given, so the view '
        'needs a bounded width and height. It was given $constraints.',
      ),
      ErrorHint(
        'Give it bounded constraints — make it the body of a Scaffold, wrap it '
        'in an Expanded or a SizedBox with a width and height — rather than '
        'placing it directly in an unbounded slot such as a Column, a Row, or '
        'a scroll view child.',
      ),
    ]);
  }

  Page<Object?> _pageFor(_MountedScreen screen) {
    final key = ValueKey<int>(screen.entryId);
    final child = _buildScreen(screen);
    final transition = widget.transition;
    if (transition != null) {
      return _FlowScreenPage(key: key, transition: transition, child: child);
    }
    // A Theme ancestor may simulate another device's platform (a preview
    // frame); without one the host's platform stands. Theme.of registers the
    // dependency so a changed simulation rebuilds the pages.
    final platform = context.findAncestorWidgetOfExactType<Theme>() == null
        ? defaultTargetPlatform
        : Theme.of(context).platform;
    return switch (platform) {
      TargetPlatform.iOS ||
      TargetPlatform.macOS =>
        CupertinoPage<Object?>(key: key, child: child),
      _ => MaterialPage<Object?>(key: key, child: child),
    };
  }

  /// Applies the [RestageFlowView.systemBack] policy to a system back gesture.
  ///
  /// While the flow has history the gesture is taken here and handed to the
  /// nested navigator, which pops one screen; it is inert while the controller
  /// is busy, when a pop would silently do nothing. Once in-flow back is
  /// exhausted the policy decides.
  ///
  /// A staged candidate layer keeps a scope that always allows the pop: a route
  /// consults every scope, so a candidate that blocked would starve the visible
  /// layer and run its own exhausted policy.
  Widget _wrapWithSystemBack(BuildContext context, Widget child) {
    final controller = widget.controller;
    final policy = widget.systemBack;
    final staged = widget.staged;
    return PopScope<Object?>(
      canPop: staged || (controller.canBack ? false : policy.propagatesToHost),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || staged) return;
        if (controller.canBack) {
          if (controller.isBusy) return;
          // A view re-mounted against a controller that already has history
          // holds only the current screen, so there is no route to pop and the
          // controller is navigated directly.
          if (_pagedIds.length > 1) {
            _nestedKey.currentState?.maybePop();
          } else {
            controller.back();
          }
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

  // The sections of the flow the current screen belongs to.
  static SurfaceSections _sectionsOf(
          RestageFlowController<Object?> controller) =>
      switch (controller.currentResolvedFlow) {
        final flow? => surfaceSectionsFor(flow),
        null => SurfaceSections.none,
      };

  void _handleScreenEvent(RestageFlowController<R> controller, int entryId,
      String name, Object? args) {
    if (isReservedCommerceEventName(name)) return;
    if (!identical(widget.controller, controller) ||
        entryId != controller.currentScreenEntryId) {
      return;
    }
    if (_screens[entryId]?.local.intercept(name, args) ?? false) {
      if (mounted) LocalWriteListener.notify(context);
      return;
    }
    args = withoutContextItemIndexes(args);
    final normalized =
        normalizeEventArgs(sanitizeAndRecordHostFlowEvent(controller, args));
    if (isMeasurementTapEventName(name)) return;
    if (widget.onScreenEvent?.call(name, normalized) ?? false) return;
    controller.handleEvent(name, normalized);
  }

  Widget _buildScreen(_MountedScreen screen) {
    // Capture the controller that owns this screen, so a stale event or render
    // failure routes to its owner (gated to the owner's current entry) and
    // never to a controller the view was later swapped to.
    final controller = widget.controller;
    final isCurrent = screen.entryId == controller.currentScreenEntryId;
    final child = RuntimeErrorBoundary(
      key: ValueKey<int>(screen.entryId),
      debugLabel: controller.flow.id,
      onFirstBuildSuccess: () {
        controller.acknowledgeRenderedEntry(screen.entryId);
      },
      onError: (error, stack) {
        markSurfaceDeliveryRenderFailedFor(
          controller.flow.surface,
          controller.flow.id,
        );
        if (screen.entryId == controller.currentScreenEntryId) {
          _forgetStoredRoot(controller);
          controller.reportRenderFailure(error);
        }
        widget.onRuntimeError?.call(error, stack);
      },
      errorReplacement: (_, __, ___) => const SizedBox.shrink(),
      child: SurfaceDeliveryPaintBoundary.forSurface(
        surfaceType: controller.flow.surface,
        surfaceSlug: controller.flow.id,
        child: screen.nativeScreen != null
            ? Builder(builder: (_) => screen.nativeScreen!())
            : DeliveredIconFontLoader.scope(
                screen.iconFonts,
                child: RemoteWidget(
                    runtime: screen.runtime!,
                    data: screen.data,
                    widget: kFlowScreenWidget,
                    onEvent: screen.onEvent),
              ),
      ),
    );

    // The RFW content keeps a stable key so its element, and the screen state
    // it holds, survives a change of wrapper.
    final content = KeyedSubtree(key: screen.contentKey, child: child);

    final registered = RestageFlowEventRegistration(
      controller: controller,
      registration: screen,
      contentToken: screen.entryId,
      associatedHandler: screen.onEvent,
      isCurrent: () =>
          identical(widget.controller, controller) &&
          controller.currentScreenEntryId == screen.entryId,
      child: screen.nativeScreen == null
          ? content
          : RestagePaywallEventTargetScope(
              owner: controller,
              content: screen,
              isCurrent: () =>
                  identical(widget.controller, controller) &&
                  controller.currentScreenEntryId == screen.entryId &&
                  !controller.isComplete &&
                  !controller.isUnavailable,
              child: RestagePaywallEventDispatcher(
                  onEvent: screen.onEvent, child: content),
            ),
    );

    // Blocks the nested pop (and, on iOS, the leading-edge swipe) while the
    // controller is busy, and over the anchor, where a navigation bar back
    // control leaves the flow through the enclosing route instead. With no
    // anchor beneath, the first screen leaves the pop alone so the platform
    // sees that nothing here handles back.
    return PopScope<Object?>(
      canPop: widget.staged ||
          !isCurrent ||
          (controller.canBack ? !controller.isBusy : !_anchored),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !isCurrent || widget.staged) return;
        if (controller.canBack) return;
        final host = Navigator.maybeOf(context);
        if (host != null && host.canPop()) host.maybePop();
      },
      child: RestageFlowEventHandlerAssociation(
        controller: controller,
        handler: controller.handleEvent,
        isCurrent: () =>
            identical(widget.controller, controller) &&
            controller.currentScreenEntryId == screen.entryId,
        child: registered,
      ),
    );
  }
}

/// A screen page whose motion comes from a host-supplied
/// [FlowTransitionBuilder] instead of the platform page transition.
/// Drops the stored root of a flow whose screen failed to render, so the next
/// mount falls back instead of rendering it again.
void _forgetStoredRoot(RestageFlowController<Object?> controller) {
  final resolver = controller.resolver;
  final raced = racedResolverOf<ResolvedFlow>(resolver);
  if (raced == null) return;
  unawaited(raced.forgetStored(
    Restage.storeKeyFor(controller.flow, resolver: resolver),
  ));
}

class _FlowScreenPage extends Page<Object?> {
  const _FlowScreenPage({
    required super.key,
    required this.transition,
    required this.child,
  });

  static const Duration _duration = Duration(milliseconds: 320);

  final FlowTransitionBuilder transition;
  final Widget child;

  @override
  Route<Object?> createRoute(BuildContext context) => PageRouteBuilder<Object?>(
        settings: this,
        transitionDuration: _duration,
        reverseTransitionDuration: _duration,
        pageBuilder: (_, __, ___) => child,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          // A screen is entering unless one of its animations runs backwards:
          // its own on the way out, or its secondary as the screen above leaves.
          final isForward = animation.status != AnimationStatus.reverse &&
              secondaryAnimation.status != AnimationStatus.reverse;
          return transition(
            context,
            animation,
            secondaryAnimation,
            child,
            isForward,
          );
        },
      );
}

/// A transparent route beneath the first screen, so a navigation bar in that
/// screen implies leaving the flow.
class _FlowAnchorPage extends Page<Object?> {
  const _FlowAnchorPage()
      : super(key: const ValueKey<String>('restage.flow.anchor'));

  @override
  Route<Object?> createRoute(BuildContext context) => PageRouteBuilder<Object?>(
        settings: this,
        opaque: false,
        maintainState: false,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
}

/// One mounted screen visit: an isolated runtime + data slot keyed by its
/// controller-minted entry id.
class _MountedScreen {
  _MountedScreen({
    required this.entryId,
    required this.runtime,
    required this.nativeScreen,
    required this.onEvent,
    required this.data,
    required this.iconFonts,
    required this.local,
  });

  final int entryId;
  final List<DeliveredIconFont> iconFonts;
  final LocalValues local;
  final Runtime? runtime;
  final CompiledFlowScreenBuilder? nativeScreen;
  final void Function(String name, Object? args) onEvent;
  final DynamicContent data;
  late final ContextPublisher contextPublisher = ContextPublisher(data);

  /// A stable key for this screen's RFW content subtree, so its element and
  /// preserved state (RFW `state.x`, scroll position, entered data) survive a
  /// change of wrapper.
  final GlobalKey contentKey = GlobalKey();
}
