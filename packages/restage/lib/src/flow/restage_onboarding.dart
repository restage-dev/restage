import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:restage_shared/restage_shared.dart' show SurfaceType;

import '../authoring/onboarding_event_dispatcher.dart';
import '../events/restage_event.dart' show RestageEvent;
import '../refresh/surface_refresh_registry.dart';
import '../refresh/surface_refresh_trigger.dart';
import '../refresh/surface_update_channel.dart';
import '../runtime/restage.dart';
import '../runtime/state_variables.dart';
import 'flow_chrome.dart';
import 'flow_controller.dart';
import 'flow_descriptors.dart';
import 'flow_resolver.dart';
import 'flow_runtime_support.dart' show normalizeEventArgs;
import 'flow_seed.dart';
import 'flow_transitions.dart';
import 'restage_flow_view.dart';
import 'system_back_policy.dart';

/// Builds host UI when an onboarding flow is unavailable.
typedef FlowUnavailableBuilder = Widget Function(
  BuildContext context,
  FlowUnavailableError error,
);

/// Explicit policies for unavailable onboarding flows.
///
/// Every `RestageOnboarding` must choose a policy so missing, incompatible, or
/// unrenderable artifacts fail closed in a visible way.
final class FlowUnavailablePolicy {
  /// Presents host-provided UI when the onboarding flow is unavailable.
  const FlowUnavailablePolicy.fallback({
    required FlowUnavailableBuilder builder,
  })  : _kind = _FlowUnavailablePolicyKind.fallback,
        fallbackBuilder = builder;

  /// Hides the onboarding surface when the flow is unavailable.
  ///
  /// Use this only when an absent onboarding UI is an intentional app state.
  const FlowUnavailablePolicy.hide()
      : _kind = _FlowUnavailablePolicyKind.hide,
        fallbackBuilder = null;

  final _FlowUnavailablePolicyKind _kind;

  /// Builder used when [isFallback] is true.
  final FlowUnavailableBuilder? fallbackBuilder;

  /// Whether this policy should present host-provided fallback UI.
  bool get isFallback => _kind == _FlowUnavailablePolicyKind.fallback;

  /// Whether this policy should hide unavailable onboarding UI.
  bool get isHide => _kind == _FlowUnavailablePolicyKind.hide;
}

enum _FlowUnavailablePolicyKind { fallback, hide }

/// Fail-closed onboarding flow surface.
///
/// Loads a generated [OnboardingFlowRef], resolves its pinned artifacts, runs
/// typed app-owned actions when declared, and calls [onComplete] only after the
/// terminal result has been filtered and decoded.
final class RestageOnboarding<R> extends StatefulWidget {
  /// Creates an onboarding flow surface.
  const RestageOnboarding({
    super.key,
    required this.flow,
    this.initialState,
    required this.unavailable,
    this.actions,
    this.installedSignalNames = const <String>{},
    this.resolver,
    this.onFlowUnavailable,
    this.onComplete,
    this.loadingBuilder,
    this.transition,
    this.systemBack = SystemBackPolicy.popHost,
    this.enableSkip = false,
    this.chromeTheme,
    this.persistentChrome = true,
    this.backBuilder,
    this.skipBuilder,
    this.chromeBuilder,
    this.persistentChromeBuilder,
    this.priceQueries = const {},
    this.liveRefresh,
  });

  /// Generated flow descriptor to load.
  final OnboardingFlowRef<R> flow;

  /// Optional host-supplied initial flow-state values.
  ///
  /// Read once when the flow starts — the seed is *initial* state. Changing
  /// only [initialState] on a rebuild does not restart a running flow; remount
  /// the widget (for example via a new [key]) to apply a different seed.
  final FlowSeed? initialState;

  /// Required policy for unavailable flows.
  final FlowUnavailablePolicy unavailable;

  /// Optional host action registry for action-backed flow transitions.
  ///
  /// Required only when the resolved flow document declares host actions.
  final FlowActionRegistry? actions;

  /// The installed custom-event / host-signal names the host has a reviewed
  /// handler for. On a GENERAL surface this caps the custom-event channel
  /// alongside [actions]: a signal name the document did not ship a handler for
  /// fails closed. Ignored on typed surfaces. Empty by default.
  ///
  /// A generated flow registry passed as [actions] installs its own flow's
  /// custom-event names automatically, so this set is usually left empty. It is
  /// still needed for names a generated registry does not enumerate — a
  /// sub-flow's own custom events (the parent registry covers only the parent
  /// flow) or a hand-rolled registry — which the runtime unions with this set.
  final Set<String> installedSignalNames;

  /// Optional resolver used to load the flow descriptor.
  ///
  /// Defaults to `Restage.defaultFlowResolver`, which currently uses bundled
  /// onboarding assets.
  final FlowResolver? resolver;

  /// Called when the flow cannot be made available.
  final void Function(FlowUnavailableError error)? onFlowUnavailable;

  /// Called with the typed terminal result after declaration filtering.
  final void Function(R result)? onComplete;

  /// Builder shown while the flow is loading.
  final WidgetBuilder? loadingBuilder;

  /// Overrides the screen transition. Defaults to the platform-adaptive forward
  /// transition (Cupertino push on iOS/macOS, Material-3 shared-axis elsewhere).
  final FlowTransitionBuilder? transition;

  /// What happens on a platform system-back gesture once in-flow back is
  /// exhausted. Defaults to [SystemBackPolicy.popHost].
  final SystemBackPolicy systemBack;

  /// Whether to show the default skip affordance (off by default; shown only
  /// when the current screen has a skip destination).
  final bool enableSkip;

  /// Visual tokens for the built-in chrome (the *Theme* rung). Null keeps the
  /// platform-appropriate defaults.
  final FlowChromeTheme? chromeTheme;

  /// Whether the built-in chrome frames the flow persistently (`true`, default)
  /// or rides inside the animated slot (`false`).
  final bool persistentChrome;

  /// Supplies the back affordance widget (the *Slots* rung). Null uses the
  /// themed default chevron.
  final FlowChromeAffordanceBuilder? backBuilder;

  /// Supplies the skip affordance widget (the *Slots* rung). Null uses the
  /// themed default skip control.
  final FlowChromeAffordanceBuilder? skipBuilder;

  /// Owns the per-screen chrome layout (the *Layout* rung). Null uses the
  /// built-in chrome.
  final FlowChromeBuilder? chromeBuilder;

  /// Frames the whole flow (the *Layout* rung). Null uses the built-in
  /// persistent chrome.
  final FlowPersistentChromeBuilder? persistentChromeBuilder;

  /// Map of productId -> live [PriceInfo] for paywall blobs rendered as flow
  /// screens.
  final Map<String, PriceInfo> priceQueries;

  /// Per-widget live-refresh override. Null inherits the app-level
  /// configuration (`Restage.configure`); a provided set replaces it wholesale
  /// (an empty set opts this surface out entirely).
  final Set<SurfaceRefreshTrigger>? liveRefresh;

  @override
  State<RestageOnboarding<R>> createState() => _RestageOnboardingState<R>();
}

class _RestageOnboardingState<R> extends State<RestageOnboarding<R>> {
  RestageFlowController<R>? _controller;

  /// A controller re-resolving the flow during a live refresh. Once it installs
  /// a screen it is staged visibly above the retained current controller, but
  /// stays noninteractive and semantics-hidden until that screen's boundary
  /// acknowledges a successful first build.
  RestageFlowController<R>? _pendingController;
  VoidCallback? _pendingReadinessListener;
  bool _pendingIsStaged = false;
  bool _pendingPromotionScheduled = false;
  FlowUnavailableError? _unavailableError;
  SurfaceRefreshHandle? _refreshHandle;

  @override
  void initState() {
    super.initState();
    _start();
    // Join the live-refresh registry so a reload / resume sweep / update
    // signal can re-resolve the flow in place while it is pristine.
    final handle = SurfaceRefreshHandle(
      surface: SurfaceRef(
        surfaceType: SurfaceType.onboarding.wireName,
        slug: widget.flow.id,
      ),
      triggers: Restage.effectiveLiveRefreshTriggers(
        widget.flow.id,
        widgetOverride: widget.liveRefresh,
      ),
      canSwap: _canSwap,
      refresh: _refresh,
      renderedVersion: () => _controller?.resolvedVersion,
      stampable: widget.resolver == null && Restage.activeRpcClient != null,
    );
    _refreshHandle = handle;
    SurfaceRefreshRegistry.instance.register(handle);
  }

  /// The swap-safety gate: a flow is safe to re-host only while it is pristine
  /// (no user-contributed state), idle (no transition/action in flight), not
  /// yet complete, and not experiment-assigned. An assigned presentation stays
  /// pinned until remount so a live refresh cannot move it out of its arm.
  bool _canSwap() =>
      _controller?.renderedAssignment == null &&
      !(_controller?.hasUserContributedState ?? false) &&
      !(_controller?.isBusy ?? false) &&
      !(_controller?.isComplete ?? false);

  /// Re-resolve the flow in place. Reached only when the gate passed. Resolves
  /// into a PENDING controller without tearing down the current one: promotes
  /// it once its first screen is ready, and discards it silently on failure so
  /// a failed refresh keeps the current render (staleness is never an error
  /// state, and there is no loading flash on a successful re-host).
  Future<void> _refresh() async {
    if (!mounted || _controller == null) return;
    _disposePending(); // supersede any in-flight pending (the loser)
    late final RestageFlowController<R> pending;
    pending = _buildController(
      onEvent: (event) {
        if (identical(_pendingController, pending)) {
          // Suppress the pending flow's lifecycle until promotion.
          return;
        }
        if (!mounted || !identical(_controller, pending)) return;
        Restage.fireEvent(event);
      },
      onComplete: (result) {
        if (identical(_pendingController, pending)) {
          _scheduleDiscardPending(pending);
          return;
        }
        if (!mounted || !identical(_controller, pending)) return;
        widget.onComplete?.call(result);
      },
      onUnavailable: (error) {
        if (identical(_pendingController, pending)) {
          // Silent: keep the current render. No fallback UI, no host callback.
          _scheduleDiscardPending(pending);
          return;
        }
        if (!mounted || !identical(_controller, pending)) return;
        setState(() => _unavailableError = error);
        widget.onFlowUnavailable?.call(error);
      },
    );
    _pendingController = pending;
    late final VoidCallback readinessListener;
    readinessListener = () {
      if (!identical(_pendingController, pending) || !mounted) return;
      if (pending.currentScreenEntryId != null && !_pendingIsStaged) {
        // Re-check before the candidate becomes visible. The user may have
        // interacted while resolution was in flight, and an assigned artifact
        // must never be live-staged even for a single frame.
        if (pending.installedArtifactAssignment != null || !_canSwap()) {
          _scheduleDiscardPending(pending);
          return;
        }
        setState(() => _pendingIsStaged = true);
      }
      if (!pending.hasRenderedContent || _pendingPromotionScheduled) return;
      // Never dispose or promote a notifier from inside its own notification.
      _pendingPromotionScheduled = true;
      scheduleMicrotask(() => _promotePending(pending));
    };
    _pendingReadinessListener = readinessListener;
    pending.addListener(readinessListener);
    unawaited(pending.load());
  }

  void _promotePending(RestageFlowController<R> pending) {
    _pendingPromotionScheduled = false;
    if (!identical(_pendingController, pending) || !mounted) return;
    if (!pending.hasRenderedContent) return;
    // Never live-swap into an experiment arm. The pending controller exposes
    // the assignment only after its first screen rendered successfully, so a
    // rejected or unavailable candidate can never change the current render's
    // identity. Re-check the current gate as well: the re-resolve runs the full
    // ladder (possibly a network fetch), so the user may have advanced while it
    // was in flight.
    if (pending.renderedAssignment != null || !_canSwap()) {
      _discardPending(pending);
      return;
    }
    _removePendingReadinessListener(pending);
    _pendingController = null;
    final old = _controller;
    setState(() {
      _controller = pending;
      _pendingIsStaged = false;
      _unavailableError = null;
    });
    old?.dispose();
  }

  void _scheduleDiscardPending(RestageFlowController<R> pending) {
    scheduleMicrotask(() => _discardPending(pending));
  }

  void _discardPending(RestageFlowController<R> pending) {
    if (!identical(_pendingController, pending)) return; // already superseded
    _removePendingReadinessListener(pending);
    _pendingController = null;
    _pendingIsStaged = false;
    _pendingPromotionScheduled = false;
    if (mounted) setState(() {});
    pending.dispose();
  }

  void _removePendingReadinessListener(
    RestageFlowController<R> pending,
  ) {
    if (!identical(_pendingController, pending)) return;
    final listener = _pendingReadinessListener;
    if (listener == null) return;
    _pendingReadinessListener = null;
    pending.removeListener(listener);
  }

  @override
  void didUpdateWidget(RestageOnboarding<R> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.flow, widget.flow) ||
        !identical(oldWidget.resolver, widget.resolver) ||
        !identical(oldWidget.actions, widget.actions) ||
        !identical(
          oldWidget.installedSignalNames,
          widget.installedSignalNames,
        )) {
      _start();
    }
  }

  void _start() {
    // A hard (re)start renders immediately and fails closed to the fallback,
    // exactly as the first mount does. Any in-flight refresh pending controller
    // is abandoned — a config-identity change supersedes a live refresh. This
    // is a new presentation, not an in-place swap, so an assigned artifact may
    // mount here; the live-refresh lockout applies after it renders.
    _disposePending();
    _disposeController();
    _unavailableError = null;
    late final RestageFlowController<R> controller;
    controller = _buildController(
      onEvent: (event) {
        if (!mounted || !identical(_controller, controller)) return;
        Restage.fireEvent(event);
      },
      onComplete: (result) {
        if (!mounted || !identical(_controller, controller)) return;
        widget.onComplete?.call(result);
      },
      onUnavailable: (error) {
        if (!mounted || !identical(_controller, controller)) return;
        setState(() => _unavailableError = error);
        widget.onFlowUnavailable?.call(error);
      },
    );
    _controller = controller;
    unawaited(controller.load());
  }

  /// Constructs a flow controller from the widget's configuration. Shared by the
  /// mount/restart path ([_start]) and the live-refresh path ([_refresh]); only
  /// the lifecycle callbacks differ.
  RestageFlowController<R> _buildController({
    required void Function(RestageEvent) onEvent,
    required void Function(R result) onComplete,
    required void Function(FlowUnavailableError error) onUnavailable,
  }) =>
      RestageFlowController<R>(
        flow: widget.flow,
        resolver: widget.resolver ?? Restage.defaultFlowResolver,
        initialState: widget.initialState,
        actions: widget.actions,
        installedSignalNames: widget.installedSignalNames,
        onEvent: onEvent,
        onComplete: onComplete,
        onUnavailable: onUnavailable,
      );

  void _disposeController() {
    final controller = _controller;
    if (controller == null) return;
    controller.dispose();
    if (identical(_controller, controller)) {
      _controller = null;
    }
  }

  void _disposePending() {
    final pending = _pendingController;
    if (pending == null) {
      _pendingReadinessListener = null;
      _pendingIsStaged = false;
      _pendingPromotionScheduled = false;
      return;
    }
    _removePendingReadinessListener(pending);
    _pendingController = null;
    _pendingIsStaged = false;
    _pendingPromotionScheduled = false;
    pending.dispose();
  }

  void _handleAuthoredEvent(String eventId, Object? value) {
    // Normalize through the same point the RFW render paths use so a scalar
    // authored-event value reaches the controller in the canonical shape and a
    // flow `.capture()` resolves identically on the local-Dart path.
    _controller?.handleEvent(eventId, normalizeEventArgs(value));
  }

  @override
  void dispose() {
    if (_refreshHandle case final handle?) {
      SurfaceRefreshRegistry.instance.unregister(handle);
    }
    _refreshHandle = null;
    _disposePending();
    _disposeController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _unavailableError;
    if (error != null) {
      if (widget.unavailable.isFallback) {
        return widget.unavailable.fallbackBuilder!(context, error);
      }
      return const SizedBox.shrink();
    }
    final controller = _controller;
    if (controller == null) {
      final builder = widget.loadingBuilder;
      return builder == null ? const SizedBox.shrink() : builder(context);
    }
    // The convenience widget is a thin assembly over the public primitives —
    // the brain, the rendering surface, and authored events routed through the
    // controller's public `handleEvent`. Render failures fail closed in the
    // controller (its `onUnavailable` drives the fallback above), so there is
    // no private back-channel here that an advanced composition could not use.
    final pending = _pendingIsStaged ? _pendingController : null;
    return Stack(
      fit: StackFit.passthrough,
      children: <Widget>[
        _buildFlowLayer(controller, staged: false),
        if (pending != null) _buildFlowLayer(pending, staged: true),
      ],
    );
  }

  Widget _buildFlowLayer(
    RestageFlowController<R> controller, {
    required bool staged,
  }) {
    return KeyedSubtree(
      key: ObjectKey(controller),
      child: ExcludeSemantics(
        excluding: staged,
        child: AbsorbPointer(
          absorbing: staged,
          child: RestageOnboardingEventDispatcher(
            onEvent: _handleAuthoredEvent,
            child: RestageFlowView<R>(
              controller: controller,
              transition: widget.transition,
              loadingBuilder: widget.loadingBuilder,
              systemBack: widget.systemBack,
              enableSkip: widget.enableSkip,
              chromeTheme: widget.chromeTheme,
              persistentChrome: widget.persistentChrome,
              backBuilder: widget.backBuilder,
              skipBuilder: widget.skipBuilder,
              chromeBuilder: widget.chromeBuilder,
              persistentChromeBuilder: widget.persistentChromeBuilder,
              priceQueries: widget.priceQueries,
            ),
          ),
        ),
      ),
    );
  }
}
