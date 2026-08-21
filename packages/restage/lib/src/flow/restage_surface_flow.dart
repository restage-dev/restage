import 'dart:async';

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/widgets.dart';

import '../analytics/root_analytics_context.dart';
import '../authoring/onboarding_event_dispatcher.dart';
import '../events/restage_event.dart'
    show FlowStarted, FlowUnavailable, OnboardingStepViewed, RestageEvent;
import '../measurement/measurement_event_sanitizer.dart';
import '../measurement/measurement_host_session.dart';
import '../refresh/surface_refresh_registry.dart';
import '../refresh/surface_refresh_trigger.dart';
import '../refresh/surface_update_channel.dart';
import '../runtime/restage.dart';
import '../runtime/first_paint_lease_guard.dart';
import '../runtime/state_variables.dart';
import 'flow_chrome.dart';
import 'flow_controller.dart';
import 'flow_descriptors.dart';
import 'flow_experiment_mount.dart';
import 'flow_resolver.dart';
import 'flow_runtime_support.dart' show normalizeEventArgs;
import 'flow_seed.dart';
import 'flow_transitions.dart';
import 'restage_flow_view.dart';
import 'system_back_policy.dart';

/// Builds host UI when a flow is unavailable.
typedef FlowUnavailableBuilder = Widget Function(
  BuildContext context,
  FlowUnavailableError error,
);

/// Explicit policies for unavailable flows.
///
/// Every `RestageFlowGraph` must choose a policy so missing, incompatible, or
/// unrenderable artifacts fail closed in a visible way.
final class FlowUnavailablePolicy {
  /// Presents host-provided UI when the flow is unavailable.
  const FlowUnavailablePolicy.fallback({
    required FlowUnavailableBuilder builder,
  })  : _kind = _FlowUnavailablePolicyKind.fallback,
        fallbackBuilder = builder;

  /// Hides the surface when the flow is unavailable.
  ///
  /// Use this only when an absent flow UI is an intentional app state.
  const FlowUnavailablePolicy.hide()
      : _kind = _FlowUnavailablePolicyKind.hide,
        fallbackBuilder = null;

  final _FlowUnavailablePolicyKind _kind;

  /// Builder used when [isFallback] is true.
  final FlowUnavailableBuilder? fallbackBuilder;

  /// Whether this policy should present host-provided fallback UI.
  bool get isFallback => _kind == _FlowUnavailablePolicyKind.fallback;

  /// Whether this policy should hide unavailable flow UI.
  bool get isHide => _kind == _FlowUnavailablePolicyKind.hide;
}

enum _FlowUnavailablePolicyKind { fallback, hide }

/// Fail-closed surface flow host.
///
/// Loads a generated [SurfaceFlowRef], resolves its pinned artifacts, runs
/// typed app-owned actions when declared, and calls [onComplete] only after the
/// terminal result has been filtered and decoded.
final class RestageFlowGraph<R> extends StatefulWidget {
  /// Creates a flow surface.
  const RestageFlowGraph({
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
  final SurfaceFlowRef<R> flow;

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
  /// assets under the descriptor's surface directory.
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
  State<RestageFlowGraph<R>> createState() => _RestageFlowGraphState<R>();
}

class _RestageFlowGraphState<R> extends State<RestageFlowGraph<R>> {
  static const int _maxHostedIdentityAttempts = 3;

  RestageFlowController<R>? _controller;
  FirstPaintLeaseTransaction? _transaction;
  RootAnalyticsPresentation? _presentation;
  final Set<RestageFlowController<R>> _ownedControllers =
      <RestageFlowController<R>>{};
  final Map<RestageFlowController<R>, MeasurementHostSessionController>
      _measurementSessions =
      <RestageFlowController<R>, MeasurementHostSessionController>{};

  /// The accepted Measurement owner. This remains on the retained controller
  /// while a live-refresh controller is only provisionally painted, so a
  /// rollback can restore it without reopening or reviving a finalized
  /// session.
  RestageFlowController<R>? _activeMeasurementController;
  int _rejectedHostedIdentityAttempts = 0;
  bool _forceUnassignedFallback = false;

  /// A controller re-resolving the flow during a live refresh. Once it installs
  /// a screen it is staged visibly above the retained current controller, but
  /// stays noninteractive and semantics-hidden until that screen's boundary
  /// acknowledges a successful first build.
  RestageFlowController<R>? _pendingController;
  FirstPaintLeaseTransaction? _pendingTransaction;
  RootAnalyticsPresentation? _pendingPresentation;
  VoidCallback? _pendingReadinessListener;
  bool _pendingIsStaged = false;
  bool _pendingPromotionScheduled = false;
  RestageFlowController<R>? _controllerToDisposeAfterPromotion;
  FirstPaintLeaseTransaction? _transactionToDisposeAfterPromotion;
  RootAnalyticsPresentation? _presentationToDisposeAfterPromotion;
  FlowUnavailableError? _unavailableError;
  SurfaceRefreshHandle? _refreshHandle;

  @override
  void initState() {
    super.initState();
    _start();
    _registerRefreshHandle();
  }

  void _registerRefreshHandle() {
    // Join the live-refresh registry so a reload / resume sweep / update
    // signal can re-resolve the flow in place while it is pristine.
    late final SurfaceRefreshHandle handle;
    handle = SurfaceRefreshHandle(
      surface: SurfaceRef(
        surfaceType: widget.flow.surfaceType.wireName,
        slug: widget.flow.id,
      ),
      triggers: Restage.effectiveLiveRefreshTriggers(
        widget.flow.id,
        widgetOverride: widget.liveRefresh,
      ),
      canSwap: () => _isCurrentRefreshHandle(handle) && _canSwap(),
      refresh: () async {
        if (!_isCurrentRefreshHandle(handle)) return;
        await _refresh();
      },
      renderedVersion: () =>
          _isCurrentRefreshHandle(handle) ? _controller?.resolvedVersion : null,
      stampable: widget.resolver == null && Restage.activeRpcClient != null,
    );
    _refreshHandle = handle;
    SurfaceRefreshRegistry.instance.register(handle);
  }

  bool _isCurrentRefreshHandle(SurfaceRefreshHandle handle) =>
      identical(_refreshHandle, handle);

  void _unregisterRefreshHandle() {
    final handle = _refreshHandle;
    if (handle == null) return;
    _refreshHandle = null;
    SurfaceRefreshRegistry.instance.unregister(handle);
  }

  /// The swap-safety gate: a flow is safe to re-host only while it is pristine
  /// (no user-contributed state), idle (no transition/action in flight), not
  /// yet complete, and not experiment-assigned. An assigned presentation stays
  /// pinned until remount so a live refresh cannot move it out of its arm.
  bool _canSwap() =>
      _controller?.renderedAssignment == null &&
      _controller?.installedArtifactAssignment == null &&
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
        _fireControllerEvent(pending, event);
      },
      onComplete: (result) {
        if (identical(_pendingController, pending)) {
          _finalizeMeasurementSessionFor(pending);
          _scheduleDiscardPending(pending);
          return;
        }
        if (!mounted || !identical(_controller, pending)) return;
        _finalizeMeasurementSessionFor(pending);
        widget.onComplete?.call(result);
      },
      onUnavailable: (error) {
        if (identical(_pendingController, pending)) {
          // Silent: keep the current render. No fallback UI, no host callback.
          _finalizeMeasurementSessionFor(pending);
          _scheduleDiscardPending(pending);
          return;
        }
        if (!mounted || !identical(_controller, pending)) return;
        _finalizeMeasurementSessionFor(pending);
        setState(() => _unavailableError = error);
        widget.onFlowUnavailable?.call(error);
      },
    );
    final presentation = RootAnalyticsRuntime.createPresentation(
      surface: widget.flow.surfaceType.wireName,
      surfaceId: widget.flow.id,
    );
    late final FirstPaintLeaseTransaction? transaction;
    transaction = _buildFirstPaintTransaction(
      pending,
      presentation: presentation,
      isCurrent: () =>
          identical(_pendingController, pending) &&
          identical(_pendingTransaction, transaction) &&
          identical(_pendingPresentation, presentation),
      canCommitPresentation: () =>
          pending.installedArtifactAssignment == null && _canSwap(),
      commitPresentation: () => _commitPendingAtPaint(
        pending,
        transaction,
        presentation,
      ),
      afterRejection: () => _discardPending(pending),
    );
    _pendingController = pending;
    _pendingTransaction = transaction;
    _pendingPresentation = presentation;
    late final VoidCallback readinessListener;
    readinessListener = () {
      if (!identical(_pendingController, pending) || !mounted) return;
      if (pending.currentScreenEntryId != null && !_pendingIsStaged) {
        final current = _controller;
        if (current != null &&
            RootAnalyticsArtifactRegistry.isSameArtifact(current, pending)) {
          _scheduleDiscardPending(pending);
          return;
        }
        // Re-check before the candidate becomes visible. The user may have
        // interacted while resolution was in flight, and an assigned artifact
        // must never be live-staged even for a single frame.
        if (pending.installedArtifactAssignment != null || !_canSwap()) {
          _scheduleDiscardPending(pending);
          return;
        }
        setState(() => _pendingIsStaged = true);
      }
      if (!pending.hasRenderedContent ||
          !(transaction?.isPaintAcknowledged ?? false) ||
          _pendingPromotionScheduled) {
        return;
      }
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
    final pendingTransaction = _pendingTransaction;
    if (!pending.hasRenderedContent ||
        pendingTransaction == null ||
        !pendingTransaction.isPaintAcknowledged) {
      return;
    }
    _finalizeCommittedPending(pending);
  }

  void _finalizeCommittedPending(RestageFlowController<R> pending) {
    final pendingTransaction = _pendingTransaction;
    if (!mounted ||
        !identical(_pendingController, pending) ||
        !identical(_controller, pending) ||
        pendingTransaction == null ||
        !pendingTransaction.isPaintAcknowledged) {
      return;
    }
    final old = _controllerToDisposeAfterPromotion;
    final oldTransaction = _transactionToDisposeAfterPromotion;
    final oldPresentation = _presentationToDisposeAfterPromotion;
    _removePendingReadinessListener(pending);
    _pendingController = null;
    _pendingTransaction = null;
    _pendingPresentation = null;
    _pendingPromotionScheduled = false;
    if (old != null) _finalizeMeasurementSessionFor(old);
    _activateMeasurementOwner(pending);
    setState(() {
      _pendingIsStaged = false;
      _unavailableError = null;
    });
    _controllerToDisposeAfterPromotion = null;
    _transactionToDisposeAfterPromotion = null;
    _presentationToDisposeAfterPromotion = null;
    if (old == null) return;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _disposeOwnedController(
        old,
        oldTransaction,
        oldPresentation,
      ),
    );
  }

  /// Moves provisional refresh authority synchronously at the paint transaction.
  ///
  /// The transaction's final current/assignment/swap checks run immediately
  /// before this callback. Successful descendant paint finalizes the move;
  /// failure restores the retained owner. Listener removal, widget cleanup, and
  /// old-owner disposal remain deferred until paint acknowledgement.
  void _commitPendingAtPaint(
    RestageFlowController<R> pending,
    FirstPaintLeaseTransaction? transaction,
    RootAnalyticsPresentation presentation,
  ) {
    _controllerToDisposeAfterPromotion = _controller;
    _transactionToDisposeAfterPromotion = _transaction;
    _presentationToDisposeAfterPromotion = _presentation;
    _controller = pending;
    _transaction = transaction;
    _presentation = presentation;
  }

  void _scheduleDiscardPending(RestageFlowController<R> pending) {
    scheduleMicrotask(() => _discardPending(pending));
  }

  void _discardPending(RestageFlowController<R> pending) {
    if (!identical(_pendingController, pending)) return; // already superseded
    final pendingTransaction = _pendingTransaction;
    if (pendingTransaction?.isPaintAcknowledged ?? false) {
      _finalizeCommittedPending(pending);
      return;
    }
    if (pendingTransaction?.isCommitted ?? false) {
      _rollbackCommittedPending(pending);
      return;
    }
    _removePendingReadinessListener(pending);
    final presentation = _pendingPresentation;
    pendingTransaction?.supersede();
    _pendingController = null;
    _pendingTransaction = null;
    _pendingPresentation = null;
    _pendingIsStaged = false;
    _pendingPromotionScheduled = false;
    if (mounted) setState(() {});
    _disposeOwnedController(pending, pendingTransaction, presentation);
  }

  void _rollbackCommittedPending(RestageFlowController<R> pending) {
    final pendingTransaction = _pendingTransaction;
    if (!identical(_pendingController, pending) ||
        !identical(_controller, pending) ||
        pendingTransaction == null ||
        !pendingTransaction.isCommitted ||
        pendingTransaction.isPaintAcknowledged) {
      return;
    }
    _removePendingReadinessListener(pending);
    final failedPresentation = _pendingPresentation;
    _controller = _controllerToDisposeAfterPromotion;
    _transaction = _transactionToDisposeAfterPromotion;
    _presentation = _presentationToDisposeAfterPromotion;
    _controllerToDisposeAfterPromotion = null;
    _transactionToDisposeAfterPromotion = null;
    _presentationToDisposeAfterPromotion = null;
    _pendingController = null;
    _pendingTransaction = null;
    _pendingPresentation = null;
    _pendingIsStaged = false;
    _pendingPromotionScheduled = false;
    _unavailableError = null;
    if (mounted) setState(() {});
    _disposeOwnedController(
      pending,
      pendingTransaction,
      failedPresentation,
    );
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
  void didUpdateWidget(RestageFlowGraph<R> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final replaceRefreshHandle =
        oldWidget.flow.surfaceType != widget.flow.surfaceType ||
            oldWidget.flow.id != widget.flow.id ||
            !_sameRefreshTriggers(oldWidget.liveRefresh, widget.liveRefresh) ||
            (oldWidget.resolver == null) != (widget.resolver == null);
    final restartController = !identical(oldWidget.flow, widget.flow) ||
        !identical(oldWidget.resolver, widget.resolver) ||
        !identical(oldWidget.actions, widget.actions) ||
        !identical(
          oldWidget.installedSignalNames,
          widget.installedSignalNames,
        );
    if (replaceRefreshHandle) _unregisterRefreshHandle();
    if (restartController) {
      _start();
    }
    if (replaceRefreshHandle) _registerRefreshHandle();
  }

  bool _sameRefreshTriggers(
    Set<SurfaceRefreshTrigger>? first,
    Set<SurfaceRefreshTrigger>? second,
  ) =>
      first == null
          ? second == null
          : second != null && setEquals(first, second);

  void _start({bool identityRetry = false}) {
    if (!identityRetry) {
      _rejectedHostedIdentityAttempts = 0;
      _forceUnassignedFallback = false;
    }
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
        if (event is FlowUnavailable &&
            _shouldConvertUnstableInitialHostedFailure(
              controller,
              event.reason,
            )) {
          return;
        }
        _fireControllerEvent(controller, event);
      },
      onComplete: (result) {
        if (!mounted || !identical(_controller, controller)) return;
        _finalizeMeasurementSessionFor(controller);
        widget.onComplete?.call(result);
      },
      onUnavailable: (error) {
        if (!mounted || !identical(_controller, controller)) return;
        if (_shouldConvertUnstableInitialHostedFailure(
          controller,
          error.reason,
        )) {
          _forceUnassignedFallback = true;
          scheduleMicrotask(() => _restartUnstableInitial(controller));
          return;
        }
        _finalizeMeasurementSessionFor(controller);
        setState(() => _unavailableError = error);
        widget.onFlowUnavailable?.call(error);
      },
    );
    final presentation = RootAnalyticsRuntime.createPresentation(
      surface: widget.flow.surfaceType.wireName,
      surfaceId: widget.flow.id,
    );
    late final FirstPaintLeaseTransaction? transaction;
    transaction = _buildFirstPaintTransaction(
      controller,
      presentation: presentation,
      isCurrent: () =>
          identical(_controller, controller) &&
          identical(_transaction, transaction) &&
          identical(_presentation, presentation),
      canCommitPresentation: () => true,
      afterRejection: () => _restartRejectedInitial(controller, transaction),
      onPainted: () => _activateMeasurementOwner(controller),
    );
    _controller = controller;
    _transaction = transaction;
    _presentation = presentation;
    unawaited(controller.load());
  }

  bool _shouldConvertUnstableInitialHostedFailure(
    RestageFlowController<R> controller,
    String reason,
  ) =>
      reason == 'unstable_mount_identity' &&
      identical(_controller, controller) &&
      controller.resolver is FlowExperimentPresentationResolver &&
      !_forceUnassignedFallback;

  /// Constructs a flow controller from the widget's configuration. Shared by the
  /// mount/restart path ([_start]) and the live-refresh path ([_refresh]); only
  /// the lifecycle callbacks differ.
  RestageFlowController<R> _buildController({
    required void Function(RestageEvent) onEvent,
    required void Function(R result) onComplete,
    required void Function(FlowUnavailableError error) onUnavailable,
  }) {
    final configuredResolver = widget.resolver ?? Restage.defaultFlowResolver;
    final FlowResolver resolver;
    final experimentFactory = configuredResolver is FlowExperimentMountFactory
        ? configuredResolver as FlowExperimentMountFactory
        : null;
    if (_forceUnassignedFallback &&
        (experimentFactory?.experimentMountsEnabled ?? false)) {
      resolver = experimentFactory!.createUnassignedFallbackResolver();
    } else if (experimentFactory?.experimentMountsEnabled ?? false) {
      final seedSource = FlowMountRuntimeSeedSource(
        flow: widget.flow,
        actions: widget.actions,
        installedSignalNames: widget.installedSignalNames,
      );
      resolver = experimentFactory!.createExperimentPresentation(
        flow: widget.flow,
        captureSeed: seedSource.capture,
      );
    } else {
      resolver = configuredResolver;
    }
    late final RestageFlowController<R> controller;
    controller = createHostMeasurementFlowController<R>(
      flow: widget.flow,
      resolver: resolver,
      initialState: widget.initialState,
      actions: widget.actions,
      installedSignalNames: widget.installedSignalNames,
      onEvent: onEvent,
      onComplete: onComplete,
      onUnavailable: onUnavailable,
      onRootResolved: (resolved) =>
          _openMeasurementSessionForResolvedRoot(controller, resolved),
      sanitizeAndRecordEvent: (rawValue) =>
          _sanitizeAndRecordEvent(controller, rawValue),
    );
    _ownedControllers.add(controller);
    return controller;
  }

  FirstPaintLeaseTransaction? _buildFirstPaintTransaction(
    RestageFlowController<R> controller, {
    required RootAnalyticsPresentation presentation,
    required bool Function() isCurrent,
    required bool Function() canCommitPresentation,
    VoidCallback? commitPresentation,
    VoidCallback? onPainted,
    required VoidCallback afterRejection,
  }) {
    final resolver = controller.resolver;
    final experimentResolver =
        resolver is FlowExperimentPresentationResolver ? resolver : null;
    return FirstPaintLeaseTransaction(
      isReady: () => controller.currentScreenEntryId != null,
      isInvalidatedByIdentityReset: () =>
          presentation.isInvalidatedByIdentityReset ||
          !(experimentResolver?.revalidate(
                FlowMountRevalidationBoundary.firstPaint,
              ) ??
              true),
      canCommit: () =>
          mounted &&
          isCurrent() &&
          canCommitPresentation() &&
          !presentation.isInvalidatedByIdentityReset &&
          (experimentResolver?.revalidate(
                FlowMountRevalidationBoundary.firstPaint,
              ) ??
              true),
      commit: () {
        final assignment = controller.installedArtifactAssignment;
        presentation.stage(
          surfaceVersion:
              RootAnalyticsArtifactRegistry.surfaceVersionFor(controller),
          experimentId: assignment?.experimentId,
          variantId: assignment?.variantId,
          experimentEpoch: assignment?.experimentEpoch,
        );
        commitPresentation?.call();
      },
      onPainted: () {
        presentation.activate();
        experimentResolver?.publishHostedLastGood();
        onPainted?.call();
      },
      afterCommit: () {
        if (mounted && isCurrent()) setState(() {});
      },
      afterRejection: afterRejection,
      onAbandon: () {
        presentation.abandon();
        experimentResolver?.abandonHostedLastGood();
      },
    );
  }

  void _restartRejectedInitial(
    RestageFlowController<R> controller,
    FirstPaintLeaseTransaction? transaction,
  ) {
    if (!mounted ||
        !identical(_controller, controller) ||
        !identical(_transaction, transaction)) {
      return;
    }
    _controller = null;
    _transaction = null;
    final presentation = _presentation;
    _presentation = null;
    _disposeOwnedController(controller, transaction, presentation);
    _rejectedHostedIdentityAttempts += 1;
    if (_rejectedHostedIdentityAttempts >= _maxHostedIdentityAttempts) {
      _forceUnassignedFallback = true;
    }
    _start(identityRetry: true);
    if (mounted) setState(() {});
  }

  void _restartUnstableInitial(RestageFlowController<R> controller) {
    if (!mounted || !identical(_controller, controller)) return;
    final transaction = _transaction;
    final presentation = _presentation;
    _controller = null;
    _transaction = null;
    _presentation = null;
    _disposeOwnedController(controller, transaction, presentation);
    _start(identityRetry: true);
    if (mounted) setState(() {});
  }

  void _disposeController() {
    final controller = _controller;
    if (controller == null) return;
    final transaction = _transaction;
    final presentation = _presentation;
    transaction?.supersede();
    _disposeOwnedController(controller, transaction, presentation);
    if (identical(_controller, controller)) {
      _controller = null;
      _transaction = null;
      _presentation = null;
    }
  }

  void _disposeOwnedController(
    RestageFlowController<R> controller,
    FirstPaintLeaseTransaction? transaction,
    RootAnalyticsPresentation? presentation,
  ) {
    _finalizeMeasurementSessionFor(controller);
    _ownedControllers.remove(controller);
    if (identical(_activeMeasurementController, controller)) {
      _activeMeasurementController = null;
    }
    transaction?.supersede();
    presentation?.dispose();
    final resolver = controller.resolver;
    if (resolver is FlowExperimentPresentationResolver) {
      resolver.disposePresentation();
    }
    controller.dispose();
  }

  void _disposePending() {
    final pending = _pendingController;
    if (pending == null) {
      _pendingReadinessListener = null;
      _pendingTransaction = null;
      _pendingPresentation = null;
      _pendingIsStaged = false;
      _pendingPromotionScheduled = false;
      return;
    }
    final transaction = _pendingTransaction;
    if (transaction?.isPaintAcknowledged ?? false) {
      _finalizeCommittedPending(pending);
      return;
    }
    if (transaction?.isCommitted ?? false) {
      _rollbackCommittedPending(pending);
      return;
    }
    _removePendingReadinessListener(pending);
    final presentation = _pendingPresentation;
    transaction?.supersede();
    _pendingController = null;
    _pendingTransaction = null;
    _pendingPresentation = null;
    _pendingIsStaged = false;
    _pendingPromotionScheduled = false;
    _disposeOwnedController(pending, transaction, presentation);
  }

  void _fireControllerEvent(
    RestageFlowController<R> controller,
    RestageEvent event,
  ) {
    final RootAnalyticsPresentation? presentation;
    if (identical(_controller, controller)) {
      presentation = _presentation;
    } else if (identical(_pendingController, controller)) {
      presentation = _pendingPresentation;
    } else {
      presentation = null;
    }
    if (presentation == null) {
      Restage.fireEvent(event);
      return;
    }
    if (event is FlowStarted || event is OnboardingStepViewed) {
      presentation.captureDeferredContextOnActivation((attribution) {
        attribution.runWithEventContext(() => Restage.fireEvent(event));
      });
      return;
    }
    presentation.runWithEventContext(() => Restage.fireEvent(event));
  }

  Future<void> _openMeasurementSessionForResolvedRoot(
    RestageFlowController<R> controller,
    Object resolvedOrPayload,
  ) async {
    final session =
        await MeasurementHostSessionController.openForResolvedArtifact(
      resolvedOrPayload,
    );
    if (!_ownedControllers.contains(controller)) {
      unawaited(session.teardown());
      return;
    }
    final previous = _measurementSessions[controller];
    if (previous != null && !identical(previous, session)) {
      unawaited(previous.teardown());
    }
    _measurementSessions[controller] = session;
  }

  Object? _sanitizeAndRecordEvent(
    RestageFlowController<R> controller,
    Object? rawValue,
  ) {
    final session = _measurementSessions[controller];
    if (session != null) return session.sanitizeAndRecordEvent(rawValue);
    return MeasurementEventSanitizer.sanitize(rawValue).businessValue;
  }

  void _activateMeasurementOwner(RestageFlowController<R> controller) {
    if (!_ownedControllers.contains(controller)) return;
    final previous = _activeMeasurementController;
    if (previous != null && !identical(previous, controller)) {
      _finalizeMeasurementSessionFor(previous);
    }
    _activeMeasurementController = controller;
  }

  void _finalizeMeasurementSessionFor(RestageFlowController<R> controller) {
    final session = _measurementSessions.remove(controller);
    if (session != null) unawaited(session.teardown());
    if (identical(_activeMeasurementController, controller)) {
      _activeMeasurementController = null;
    }
  }

  void _handleAuthoredEvent(
    RestageFlowController<R> controller,
    String eventId,
    Object? value,
  ) {
    if (!identical(_controller, controller)) return;
    // Normalize through the same point the RFW render paths use so a scalar
    // authored-event value reaches the controller in the canonical shape and a
    // flow `.capture()` resolves identically on the local-Dart path.
    final businessValue = _sanitizeAndRecordEvent(controller, value);
    controller.handleEvent(
      eventId,
      normalizeEventArgs(businessValue),
    );
  }

  @override
  void dispose() {
    _unregisterRefreshHandle();
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
    final transaction = identical(_pendingController, controller)
        ? _pendingTransaction
        : _transaction;
    final candidatePending =
        transaction != null && transaction.isReady && !transaction.isCommitted;
    Widget child = RestageEventDispatcher(
      onEvent: (eventId, value) =>
          _handleAuthoredEvent(controller, eventId, value),
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
    );
    final session = _measurementSessions[controller];
    if (session != null) child = session.wrapRootSubtree(child);
    if (transaction != null) {
      child = FirstPaintLeaseScope(
        transaction: transaction,
        child: FirstPaintLeaseGuard(
          transaction: transaction,
          armed: true,
          child: child,
        ),
      );
    }
    return KeyedSubtree(
      key: ObjectKey(controller),
      child: ExcludeSemantics(
        excluding: staged || candidatePending,
        child: AbsorbPointer(
          absorbing: staged || candidatePending,
          child: child,
        ),
      ),
    );
  }
}

/// Deprecated spelling of [RestageFlowGraph].
///
/// The host widget is named after the `@FlowGraph` annotation that produces
/// what it mounts. Removed at 3.0.
@Deprecated('Use RestageFlowGraph')
typedef RestageSurfaceFlow<R> = RestageFlowGraph<R>;
