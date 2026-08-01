import 'dart:async';

import 'package:flutter/material.dart' show ColorScheme, Theme;
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart' show internal;
import 'package:restage_core/library_registration.dart' as restage_core;
import 'package:restage_cupertino/library_registration.dart'
    as restage_cupertino;
import 'package:restage_material/library_registration.dart' as restage_material;
import 'package:restage_shared/restage_shared.dart' hide WidgetLibrary;
import 'package:rfw/rfw.dart';

import '../authoring/event_dispatcher.dart';
import '../billing/billing_gateway.dart';
import '../billing/purchase_attribution.dart';
import '../events/event_enums.dart';
import '../events/restage_event.dart';
import '../flow/flow_controller.dart';
import '../flow/flow_descriptors.dart';
import '../flow/flow_resolver.dart';
import '../flow/restage_flow_view.dart';
import '../refresh/surface_refresh_registry.dart';
import '../refresh/surface_refresh_trigger.dart';
import '../refresh/surface_update_channel.dart';
import '../resolver/resolved_paywall_payload.dart';
import '../resolver/resolved_variant.dart';
import '../resolver/surface_assignment_key_provider.dart';
import '../resolver/variant_resolver.dart';
import 'error_boundary.dart';
import 'event_demux.dart';
import 'first_paint_lease_guard.dart';
import 'library_runtime_registry.dart';
import 'restage.dart';
import 'paywall_controller.dart';
import 'paywall_error.dart';
import 'state_variables.dart';

/// SDK-internal cache for the most-recently successfully resolved+rendered
/// payload per paywall id — a blob (its bytes + served version) or a flow (its
/// resolved document + screen blobs). Populated only when
/// [RestagePaywall.cacheLastRender] is true at the time of a successful render.
/// Cleared on [Restage.debugReset]. The sealed payload carries the served
/// published version, so a cache-fallback render reports the version of the
/// surface the user actually sees (or null for a bundled / custom resolution).
final Map<String, ResolvedPaywallPayload> _lastSuccessfulPayloads =
    <String, ResolvedPaywallPayload>{};

/// Internal: clears the in-memory paywall cache. Called by [Restage.debugReset]
/// to drop cached state between test runs and from app startup paths that need
/// to invalidate the cache.
void resetRestagePaywallCache() {
  _lastSuccessfulPayloads.clear();
}

/// Visible-for-testing alias for [resetRestagePaywallCache], exported so
/// tests can clear the cache without going through the full
/// [Restage.debugReset] surface.
@internal
void debugClearRestagePaywallCache() => resetRestagePaywallCache();

/// RFW paywall rendered as native Flutter widgets.
///
/// Looks up the paywall variant via [resolver] (or [Restage.defaultResolver]
/// if omitted), decodes the returned `.rfw` blob, and renders the resulting
/// widget tree using the three built-in widget libraries (`restage.core`,
/// `restage.material`, `restage.cupertino`) registered at mount time.
///
/// Lifecycle events flow through [Restage.events]:
///   - [PaywallLoadStarted] — fired before resolver is invoked
///   - [PaywallLoadCompleted] — fired after a successful decode
///   - [PaywallViewed] — fired in a post-frame callback after first render
///   - [PaywallLoadFailed] — fired when the resolver or decode fails
///   - [PaywallDismissed] — fired in [State.dispose] if the paywall was viewed
///
/// ```dart
/// RestagePaywall(
///   id: 'pro_upgrade',
///   onEvent: (event) {
///     if (event is PurchaseSucceeded) unlockPro();
///   },
/// )
/// ```
///
/// Constructor note: the presentation-related parameters ([loadingBuilder],
/// [errorBuilder], [cacheLastRender]) are intentionally kept as flat named
/// parameters. If a fourth presentation knob is ever added, they would be
/// grouped into a single `RestagePaywallPresentation` value object (passed as
/// a `presentation:` parameter) to keep the call site readable.
class RestagePaywall extends StatefulWidget {
  /// Const constructor.
  const RestagePaywall({
    super.key,
    required this.id,
    this.placementId,
    this.resolver,
    this.onEvent,
    this.controller,
    this.cacheLastRender = false,
    this.loadingBuilder,
    this.errorBuilder,
    this.locale,
    this.priceQueries = const {},
    this.liveRefresh,
  });

  /// Stable paywall identifier (e.g. `'pro_upgrade'`).
  final String id;

  /// Optional placement identifier for delivery and analytics routing.
  final String? placementId;

  /// Variant resolver. Defaults to [Restage.defaultResolver] when null.
  final VariantResolver? resolver;

  /// Per-paywall callback for [RestageEvent]s fired by this paywall.
  /// Events also flow through [Restage.events] for app-wide listeners.
  final void Function(RestageEvent event)? onEvent;

  /// Optional handle for programmatic dismiss / fireEvent from the host.
  final RestagePaywallController? controller;

  /// When true, the most recently successfully decoded blob for [id] is
  /// retained in an SDK-internal cache. On a subsequent failed resolution,
  /// the cached blob is rendered as a fallback. Default: false.
  final bool cacheLastRender;

  /// Builder shown while the paywall is loading. Default: [SizedBox.shrink].
  final WidgetBuilder? loadingBuilder;

  /// Builder shown when the paywall fails to load. Default: [SizedBox.shrink].
  final Widget Function(BuildContext context, RestagePaywallError error)?
      errorBuilder;

  /// Locale to use when resolving and rendering the paywall.
  final Locale? locale;

  /// Map of productId -> live [PriceInfo] resolved from StoreKit / Play.
  /// Host apps supply this map (or leave it empty); the SDK reads it when
  /// populating product data.
  final Map<String, PriceInfo> priceQueries;

  /// Per-widget live-refresh override. Null inherits the app-level
  /// configuration (`Restage.configure`); a provided set replaces it wholesale
  /// (an empty set opts this surface out entirely).
  final Set<SurfaceRefreshTrigger>? liveRefresh;

  @override
  State<RestagePaywall> createState() => _RestagePaywallState();
}

class _RestagePaywallState extends State<RestagePaywall> {
  static const LibraryName _paywallLibrary =
      LibraryName(<String>['restage', 'paywall']);

  _BlobStage? _blobPresentation;
  _BlobStage? _pendingBlobStage;
  int _loadEpoch = 0;
  RestagePaywallError? _error;
  DateTime? _mountedAt;
  bool _viewedFired = false;
  bool _dismissedFired = false;

  /// The server-assigned published version of the last successfully-resolved
  /// variant, captured at load so a later purchase attributes its conversion to
  /// the exact served version (MAR). Null for bundled / custom resolutions.
  int? _resolvedPaywallPublishedVersion;

  /// This surface's live-refresh participation handle, registered at mount and
  /// unregistered at dispose. Null until [initState] registers it.
  SurfaceRefreshHandle? _refreshHandle;

  /// True once any authored event has been dispatched from the rendered
  /// content (a tap, an input, a purchase). Deliberately broad: any interaction
  /// makes the surface dirty for the rest of this mount so a live swap never
  /// pulls the rug from under a user who has started engaging.
  bool _userInteracted = false;

  /// The experiment id of the currently-rendered resolution, when it was
  /// served under an A/B arm. Non-null locks the surface out of live swaps so
  /// exposure accounting stays clean (a remount re-resolves fresh).
  String? _renderedExperimentId;
  String? _renderedExperimentVariantId;
  int? _renderedExperimentEpoch;

  /// The anonymous-identity generation that selected the rendered hosted
  /// artifact. A later generation cannot replace it within this presentation.
  SurfaceAssignmentResolutionLease? _renderedAssignmentLease;

  /// Content hash of the currently-rendered blob, used to skip an unchanged
  /// re-apply when the resolution carries no published version (bundled /
  /// custom). The canonical SHA-256 the rest of the delivery path uses; only
  /// populated for versionless resolutions (the version compare covers the
  /// rest). Null until a versionless blob has rendered.
  FlowContentHash? _renderedContentHash;

  /// The hosted flow controller when the resolved payload is flow-shaped (a
  /// lowered navigation paywall); null for a single-blob paywall. The paywall
  /// intercepts this controller's purchase/restore events out-of-band so they
  /// bill instead of driving a graph transition (see
  /// [_interceptFlowScreenEvent]).
  RestageFlowController<void>? _flowController;
  FirstPaintLeaseTransaction? _flowTransaction;
  int? _flowEpoch;

  VoidCallback? _initialFlowReadinessListener;
  bool _initialFlowIsStaged = false;

  /// A flow controller loading a freshly-resolved flow during a live refresh.
  /// Once its first screen installs, it is staged above last-good while
  /// remaining noninteractive and semantics-hidden. The paint guard moves
  /// ownership synchronously; the boundary acknowledgement then completes the
  /// structural promotion. Failure discards the candidate silently.
  RestageFlowController<void>? _pendingFlowController;
  VoidCallback? _pendingFlowReadinessListener;
  bool _pendingFlowIsStaged = false;
  bool _pendingFlowPromotionScheduled = false;
  FirstPaintLeaseTransaction? _pendingFlowTransaction;
  int? _pendingFlowEpoch;
  RestageFlowController<void>? _flowToDisposeAfterPromotion;
  _BlobStage? _blobToDisposeAfterPromotion;

  /// Guards a native purchase/restore so a double-tap cannot start a second
  /// billing call while one is already in flight. Shared by the blob and flow
  /// paths — both route through [_runPurchase] / [_runRestore] — and released
  /// on EVERY outcome (success/pending/cancelled/failed/error), so a legitimate
  /// sequential purchase or retry is never blocked; it is a pure
  /// concurrent-re-entrancy guard, transparent to sequential purchases.
  bool _billingInFlight = false;

  /// Whether the paywall lifecycle (`PaywallLoadCompleted` + `PaywallViewed`)
  /// has been announced for a flow-hosted paywall. The flow runtime fires its
  /// own onboarding-shaped lifecycle (suppressed here); the paywall announces
  /// its own paywall-shaped lifecycle exactly once when the flow's first screen
  /// loads.
  bool _flowLoadAnnounced = false;

  // Last theme values published to `data.theme.*` — the didChangeDependencies
  // re-push gate, and the *only* dedup: `DynamicContent.update` deep-clones
  // its value, so it can't identity-compare a re-push away. ThemeData has no
  // value `==` (a `Theme(data: x.copyWith(...))` ancestor mints a fresh
  // instance every build), but ColorScheme / IconThemeData / TextStyle each do
  // — and they are exactly populateThemeData's inputs, so keep the two in sync.
  ColorScheme? _lastThemeColorScheme;
  IconThemeData? _lastThemeIconTheme;
  TextStyle? _lastThemeTextStyle;

  @override
  void initState() {
    super.initState();
    // Begin the surface-presentation session so events fired during this mount
    // carry a stable surfaceSessionId (ended in dispose).
    Restage.beginSurfaceSession();
    _mountedAt = DateTime.now();
    widget.controller?.attachInternal(
      onDismiss: ({required DismissReason reason}) {
        _fireDismissed(reason);
      },
      onFireEvent: (name, {Map<String, Object?>? args}) {
        _handleRfwEvent(name, args ?? const <String, Object?>{});
      },
    );
    _load();
    // Join the live-refresh registry so producers (an explicit reload, the
    // app-resume sweep, an update-channel signal) can re-resolve this surface
    // in place. Registration is inert when the surface has no triggers and
    // nothing calls reload — it just carries the gate + refresh callback.
    final handle = SurfaceRefreshHandle(
      surface: SurfaceRef(
        surfaceType: SurfaceType.paywall.wireName,
        slug: widget.id,
      ),
      triggers: Restage.effectiveLiveRefreshTriggers(
        widget.id,
        widgetOverride: widget.liveRefresh,
      ),
      canSwap: _canSwap,
      refresh: _refresh,
      renderedVersion: () => _resolvedPaywallPublishedVersion,
      stampable: widget.resolver == null && Restage.activeRpcClient != null,
    );
    _refreshHandle = handle;
    SurfaceRefreshRegistry.instance.register(handle);
  }

  /// The swap-safety gate. A surface is safe to live-swap only when no store
  /// operation is in flight, the user has not interacted, the render is not
  /// experiment-assigned, and any hosted flow is pristine and idle.
  bool _canSwap() =>
      !_billingInFlight &&
      !_userInteracted &&
      _renderedExperimentId == null &&
      (_renderedAssignmentLease?.isCurrent ?? true) &&
      !(_flowController?.hasUserContributedState ?? false) &&
      !(_flowController?.isBusy ?? false);

  /// Re-resolve this surface in place. Never throws into the widget — a failed
  /// refresh keeps the current render (staleness is never an error state).
  Future<void> _refresh() async {
    // Nothing has rendered yet: the in-flight mount fetch is already
    // fresh-first, so a refresh would be redundant (and could race it).
    if (_blobPresentation == null &&
        !(_flowTransaction?.isCommitted ?? false)) {
      return;
    }
    await _load(isRefresh: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Publish the host theme into `data.theme.*` — once at mount, then on
    // every ambient-theme change. Reading Theme / DefaultTextStyle here
    // registers the dependency, so this re-fires when either changes. Gated
    // so an unrelated dependency change (or a fresh-but-equal ThemeData
    // instance) does not re-publish.
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final iconTheme = theme.iconTheme;
    final defaultTextStyle = DefaultTextStyle.of(context).style;
    if (colorScheme == _lastThemeColorScheme &&
        iconTheme == _lastThemeIconTheme &&
        defaultTextStyle == _lastThemeTextStyle) {
      return;
    }
    _lastThemeColorScheme = colorScheme;
    _lastThemeIconTheme = iconTheme;
    _lastThemeTextStyle = defaultTextStyle;
    for (final stage in <_BlobStage?>[
      _blobPresentation,
      _pendingBlobStage,
    ]) {
      if (stage == null) continue;
      populateThemeData(
        stage.data,
        colorScheme: colorScheme,
        iconTheme: iconTheme,
        defaultTextStyle: defaultTextStyle,
      );
    }
  }

  /// Fire [event] on both the per-widget [RestagePaywall.onEvent] callback
  /// and the app-wide [Restage.events] stream.
  ///
  /// The global stream is unconditional: events fired after this widget
  /// unmounts (e.g. a purchase outcome that resolves after the user
  /// navigates away) still reach app-wide listeners. The per-paywall
  /// callback is mounted-guarded so the host doesn't receive callbacks
  /// for a widget that no longer exists.
  void _fireEvent(RestageEvent event) {
    Restage.fireEvent(event);
    if (mounted) widget.onEvent?.call(event);
  }

  /// Fire `PaywallDismissed` exactly once per mount, regardless of which
  /// path triggered the dismiss (controller dismiss + dispose race).
  void _fireDismissed(DismissReason reason) {
    if (_dismissedFired) return;
    _dismissedFired = true;
    _fireEvent(PaywallDismissed(
      paywallId: widget.id,
      reason: reason,
      timeOnPaywall: _mountedAt == null
          ? Duration.zero
          : DateTime.now().difference(_mountedAt!),
    ));
  }

  Future<void> _load({
    bool isRefresh = false,
    bool announceLoadStarted = true,
  }) async {
    final epoch = ++_loadEpoch;
    // A refresh is a silent, in-place re-resolve: no load-started lifecycle,
    // no error state on failure. A fresh mount announces its lifecycle as
    // before.
    if (!isRefresh && announceLoadStarted) {
      _fireEvent(PaywallLoadStarted(paywallId: widget.id));
    }
    final stopwatch = Stopwatch()..start();
    final resolver = widget.resolver ?? Restage.defaultResolver;
    try {
      final payload = await _resolveStablePayload(resolver, epoch);
      if (payload == null) return;
      // This check is intentionally the first work after the await. A newer
      // load supersedes this result, while an actor boundary re-enters the same
      // resolver ladder before payload shape, decode, or host state can move.
      if (!mounted || epoch != _loadEpoch) return;
      if (!(payload.assignmentLease?.isCurrent ?? true)) {
        _retryLoadAfterRejectedLease(epoch, isRefresh: isRefresh);
        return;
      }
      // A flow-shaped payload (a lowered navigation paywall) is hosted by the
      // flow runtime; a purchase on any of its screens is intercepted to bill
      // (see [_startFlow] / [_interceptFlowScreenEvent]). The blob path below is
      // unchanged — the sealed demux only adds the flow branch.
      if (payload is FlowPaywallPayload) {
        if (!mounted) {
          payload.abandonHostedLastGood();
          return;
        }
        if (isRefresh) {
          _refreshFlow(payload, stopwatch, epoch);
          return;
        }
        // The flow is cached only after its first screen commits successfully
        // (in [_commitInitialFlow]), mirroring the blob path which caches a
        // decoded blob, so an unrenderable flow is never cached.
        _startFlow(payload, stopwatch, epoch: epoch);
        return;
      }
      final variant = (payload as BlobPaywallPayload).variant;
      final WidgetLibrary library;
      try {
        library = decodeLibraryBlob(variant.bytes);
      } catch (e, st) {
        payload.abandonHostedLastGood();
        throw RestagePaywallError(
          code: RestageErrorCodes.decodeFailed,
          message: 'Could not decode .rfw blob for ${widget.id}: $e',
          cause: e,
          stackTrace: st,
        );
      }
      if (!mounted) {
        payload.abandonHostedLastGood();
        return;
      }
      if (isRefresh) {
        // Identical served content re-renders nothing.
        if (_isUnchangedBlob(variant)) {
          payload.abandonHostedLastGood();
          return;
        }
        // Never live-swap a surface INTO a new experiment arm: enrolling a live
        // view would count an exposure the user never freshly saw. Defer to
        // remount (symmetric to the current-render experiment lockout in the
        // gate).
        if (variant.experimentId != null) {
          payload.abandonHostedLastGood();
          return;
        }
        // A user interaction or store op that began during the async resolve
        // makes the surface dirty; abort the swap (defer = drop — the next
        // remount is fresh-first anyway).
        if (!_canSwap()) {
          payload.abandonHostedLastGood();
          return;
        }
      }
      _stageBlob(
        payload,
        library,
        epoch: epoch,
        isRefresh: isRefresh,
        loadDuration: stopwatch.elapsed,
        cacheHit: variant.cacheHit,
      );
    } on RestagePaywallError catch (e) {
      if (!mounted || epoch != _loadEpoch) return;
      // A failed refresh keeps the current render and stays silent.
      if (isRefresh) return;
      if (_tryFallbackToCache(stopwatch, epoch)) return;
      setState(() => _error = e);
      _fireEvent(PaywallLoadFailed(
        paywallId: widget.id,
        errorCode: e.code,
        message: e.message,
        retryable: e.retryable,
      ));
    } catch (e, st) {
      if (!mounted || epoch != _loadEpoch) return;
      // A failed refresh keeps the current render and stays silent.
      if (isRefresh) return;
      // Surface the original exception + stack to the developer console so
      // a buggy custom resolver doesn't get hidden behind a generic
      // "unknown" error code in their crash reports.
      FlutterError.reportError(FlutterErrorDetails(
        exception: e,
        stack: st,
        library: 'restage',
        context: ErrorDescription('resolving + decoding paywall ${widget.id}'),
      ));
      if (_tryFallbackToCache(stopwatch, epoch)) return;
      final err = RestagePaywallError(
        code: RestageErrorCodes.unknown,
        message: 'Unexpected: $e',
        cause: e,
        stackTrace: st,
      );
      setState(() => _error = err);
      _fireEvent(PaywallLoadFailed(
        paywallId: widget.id,
        errorCode: err.code,
        message: err.message,
        retryable: false,
      ));
    }
  }

  void _retryLoadAfterRejectedLease(
    int epoch, {
    required bool isRefresh,
  }) {
    if (!mounted || epoch != _loadEpoch) return;
    unawaited(_load(
      isRefresh: isRefresh,
      announceLoadStarted: false,
    ));
  }

  /// Whether a freshly-resolved [variant] carries the same content as what is
  /// currently rendered, so a live refresh should skip the swap. Prefers the
  /// server-assigned published version; falls back to the blob content hash for
  /// versionless (bundled / custom) resolutions.
  bool _isUnchangedBlob(ResolvedVariant variant) {
    final freshVersion = variant.paywallPublishedVersion;
    final renderedVersion = _resolvedPaywallPublishedVersion;
    // When either side carries a published version, that is the identity: equal
    // versions are unchanged; a mixed null/non-null pair means the delivery
    // mode itself moved, so it counts as changed.
    if (freshVersion != null || renderedVersion != null) {
      return freshVersion == renderedVersion;
    }
    // Both versionless (bundled / custom): fall back to the content hash.
    final rendered = _renderedContentHash;
    return rendered != null &&
        rendered.value == FlowContentHash.compute(variant.bytes).value;
  }

  /// Re-host a flow-shaped paywall from a freshly-resolved [payload]. Reached
  /// only when the gate already passed (the flow is pristine + idle). The old
  /// controller stays mounted until the candidate commits successfully.
  void _refreshFlow(
    FlowPaywallPayload payload,
    Stopwatch stopwatch,
    int epoch,
  ) {
    final freshVersion = payload.paywallPublishedVersion;
    final renderedVersion = _resolvedPaywallPublishedVersion;
    if (freshVersion != null &&
        renderedVersion != null &&
        freshVersion == renderedVersion) {
      payload.abandonHostedLastGood();
      return; // unchanged — nothing to re-host
    }
    // Never live-swap INTO a new experiment arm (symmetric to the blob path +
    // the current-render lockout); defer enrolling a live view to remount.
    if (payload.experimentId != null) {
      payload.abandonHostedLastGood();
      return;
    }
    // Re-check the gate after the async resolve (an interaction could have
    // landed during it); defer = drop if the surface went dirty.
    if (!_canSwap()) {
      payload.abandonHostedLastGood();
      return;
    }
    // Resolve-then-swap: load the fresh flow in a PENDING controller without
    // touching the live one. Promote only once it renders its first screen;
    // discard it silently on failure so a failed refresh keeps the current
    // render (staleness is never an error state).
    _disposePendingFlow(); // supersede any in-flight pending (loser)
    late final RestageFlowController<void> pending;
    pending = _buildFlowController(
      payload,
      onEvent: (event) =>
          _handleRefreshFlowEvent(pending, event, stopwatch, payload),
      onComplete: (_) => _handleRefreshFlowComplete(pending),
      onUnavailable: (error) => _handleRefreshFlowUnavailable(pending, error),
    );
    late final FirstPaintLeaseTransaction transaction;
    transaction = FirstPaintLeaseTransaction(
      isReady: () => pending.currentScreenEntryId != null,
      isInvalidatedByIdentityReset: () =>
          !(payload.assignmentLease?.isCurrent ?? true),
      canCommit: () => _canCommitPendingFlow(
        pending,
        payload,
        epoch,
        transaction,
      ),
      commit: () => _commitPendingFlowAtPaint(
        pending,
        payload,
        epoch,
        transaction,
      ),
      onPainted: () => _publishRenderedPayload(payload),
      afterCommit: () => _finishPendingFlowPaintCommit(pending),
      afterRejection: () => _rejectPendingFlowTransaction(
        pending,
        payload,
        epoch,
      ),
      onAbandon: payload.abandonHostedLastGood,
    );
    _pendingFlowController = pending;
    _pendingFlowTransaction = transaction;
    _pendingFlowEpoch = epoch;
    late final VoidCallback readinessListener;
    readinessListener = () {
      if (!mounted || !identical(_pendingFlowController, pending)) return;
      if (pending.currentScreenEntryId != null && !_pendingFlowIsStaged) {
        if (!transaction.isPending && !transaction.isCommitted) return;
        if (!_canSwap()) {
          _scheduleDiscardPendingFlow(pending);
          return;
        }
        setState(() => _pendingFlowIsStaged = true);
      }
      if (!pending.hasRenderedContent ||
          !transaction.isCommitted ||
          _pendingFlowPromotionScheduled) {
        return;
      }
      _pendingFlowPromotionScheduled = true;
      scheduleMicrotask(() => _promotePendingFlow(pending));
    };
    _pendingFlowReadinessListener = readinessListener;
    pending.addListener(readinessListener);
    unawaited(pending.load());
  }

  /// Routes a lifecycle event from a controller that started life as a refresh
  /// pending controller. Pending lifecycle is suppressed: controller readiness
  /// only arms the exact screen for its paint-time transaction, and an early
  /// [FlowStarted] can never commit it.
  void _handleRefreshFlowEvent(
    RestageFlowController<void> controller,
    RestageEvent event,
    Stopwatch stopwatch,
    FlowPaywallPayload payload,
  ) {
    if (identical(_pendingFlowController, controller)) return;
    if (identical(_flowController, controller)) {
      _handleFlowLifecycleEvent(event, stopwatch, payload, false);
    }
  }

  void _handleRefreshFlowComplete(RestageFlowController<void> controller) {
    if (identical(_pendingFlowController, controller)) {
      _scheduleDiscardPendingFlow(controller);
      return;
    }
    _handleFlowComplete(controller);
  }

  void _handleRefreshFlowUnavailable(
    RestageFlowController<void> controller,
    FlowUnavailableError error,
  ) {
    if (identical(_pendingFlowController, controller)) {
      // Silent: keep the current render. No _error, no PaywallLoadFailed, and no
      // cache eviction — the pending flow was never what the user saw.
      _scheduleDiscardPendingFlow(controller);
      return;
    }
    _handleFlowUnavailable(controller, error);
  }

  /// Promotes the pending flow after its first screen commits successfully,
  /// then records the served identity and tears down the old controller. A
  /// failed candidate therefore cannot corrupt what the current render owns.
  void _promotePendingFlow(RestageFlowController<void> pending) {
    _pendingFlowPromotionScheduled = false;
    if (!identical(_pendingFlowController, pending) || !mounted) return;
    final transaction = _pendingFlowTransaction;
    if (!pending.hasRenderedContent ||
        transaction == null ||
        !transaction.isCommitted) {
      return;
    }
    _finalizeCommittedPendingFlow(pending);
  }

  /// Clears refresh-pending bookkeeping for authority that already committed.
  /// A newer refresh can then stage above this controller without treating the
  /// actual current presentation as a disposable loser.
  void _finalizeCommittedPendingFlow(
    RestageFlowController<void> pending,
  ) {
    final transaction = _pendingFlowTransaction;
    if (!mounted ||
        !identical(_pendingFlowController, pending) ||
        transaction == null ||
        !transaction.isCommitted) {
      return;
    }
    _removePendingFlowReadinessListener(pending);
    _pendingFlowController = null;
    _pendingFlowTransaction = null;
    _pendingFlowEpoch = null;
    setState(() {
      _pendingFlowIsStaged = false;
      _error = null;
    });
    final oldFlow = _flowToDisposeAfterPromotion;
    final oldBlob = _blobToDisposeAfterPromotion;
    _flowToDisposeAfterPromotion = null;
    _blobToDisposeAfterPromotion = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (oldFlow != null) _disposeFlowController(oldFlow);
      if (oldBlob != null) _disposeBlobStage(oldBlob);
    });
  }

  bool _canCommitPendingFlow(
    RestageFlowController<void> pending,
    FlowPaywallPayload payload,
    int epoch,
    FirstPaintLeaseTransaction transaction,
  ) =>
      mounted &&
      identical(_pendingFlowController, pending) &&
      identical(_pendingFlowTransaction, transaction) &&
      _pendingFlowEpoch == epoch &&
      epoch == _loadEpoch &&
      pending.currentScreenEntryId != null &&
      (payload.assignmentLease?.isCurrent ?? true) &&
      _canSwap();

  /// Paint-time authority mutation. Keep this synchronous and callback-free.
  void _commitPendingFlowAtPaint(
    RestageFlowController<void> pending,
    FlowPaywallPayload payload,
    int epoch,
    FirstPaintLeaseTransaction transaction,
  ) {
    _flowToDisposeAfterPromotion = _flowController;
    _blobToDisposeAfterPromotion = _blobPresentation;
    _flowController = pending;
    _flowTransaction = transaction;
    _flowEpoch = epoch;
    _blobPresentation = null;
    _resolvedPaywallPublishedVersion = payload.paywallPublishedVersion;
    _renderedExperimentId = payload.experimentId;
    _renderedExperimentVariantId = payload.variantId;
    _renderedExperimentEpoch = payload.experimentEpoch;
    _renderedAssignmentLease = payload.assignmentLease;
    _renderedContentHash = null;
  }

  /// Publishes both resolver and widget last-good only after descendant paint
  /// returned normally for the exact authority transaction.
  void _publishRenderedPayload(ResolvedPaywallPayload payload) {
    payload.publishHostedLastGood();
    if (widget.cacheLastRender) {
      _lastSuccessfulPayloads[widget.id] = payload;
    }
  }

  void _finishPendingFlowPaintCommit(
    RestageFlowController<void> pending,
  ) {
    if (!mounted || !identical(_pendingFlowController, pending)) return;
    setState(() {});
    if (pending.hasRenderedContent && !_pendingFlowPromotionScheduled) {
      _pendingFlowPromotionScheduled = true;
      scheduleMicrotask(() => _promotePendingFlow(pending));
    }
  }

  void _rejectPendingFlowTransaction(
    RestageFlowController<void> pending,
    FlowPaywallPayload payload,
    int epoch,
  ) {
    if (!mounted || !identical(_pendingFlowController, pending)) return;
    final shouldRetry =
        epoch == _loadEpoch && !(payload.assignmentLease?.isCurrent ?? true);
    _discardPendingFlow(pending);
    if (shouldRetry) {
      _retryLoadAfterRejectedLease(epoch, isRefresh: true);
    }
  }

  void _discardPendingFlow(RestageFlowController<void> pending) {
    // Already superseded by a newer pending (which disposed this one).
    if (!identical(_pendingFlowController, pending)) return;
    _removePendingFlowReadinessListener(pending);
    _pendingFlowTransaction?.supersede();
    _pendingFlowController = null;
    _pendingFlowTransaction = null;
    _pendingFlowEpoch = null;
    _pendingFlowIsStaged = false;
    _pendingFlowPromotionScheduled = false;
    if (mounted) setState(() {});
    _disposeFlowControllerAfterDetach(pending);
  }

  void _scheduleDiscardPendingFlow(RestageFlowController<void> pending) {
    scheduleMicrotask(() => _discardPendingFlow(pending));
  }

  void _removePendingFlowReadinessListener(
    RestageFlowController<void> pending,
  ) {
    if (!identical(_pendingFlowController, pending)) return;
    final listener = _pendingFlowReadinessListener;
    if (listener == null) return;
    _pendingFlowReadinessListener = null;
    pending.removeListener(listener);
  }

  void _disposePendingFlow() {
    final pending = _pendingFlowController;
    if (pending == null) {
      _pendingFlowReadinessListener = null;
      _pendingFlowTransaction = null;
      _pendingFlowEpoch = null;
      _pendingFlowIsStaged = false;
      _pendingFlowPromotionScheduled = false;
      return;
    }
    if (_pendingFlowTransaction?.isCommitted ?? false) {
      _finalizeCommittedPendingFlow(pending);
      return;
    }
    _removePendingFlowReadinessListener(pending);
    _pendingFlowTransaction?.supersede();
    _pendingFlowController = null;
    _pendingFlowTransaction = null;
    _pendingFlowEpoch = null;
    _pendingFlowIsStaged = false;
    _pendingFlowPromotionScheduled = false;
    if (mounted) {
      setState(() {});
      _disposeFlowControllerAfterDetach(pending);
    } else {
      _disposeFlowController(pending);
    }
  }

  /// Resolves [RestagePaywall.id] into a sealed payload. The built-in resolvers
  /// can return a blob OR a lowered flow; a host-supplied custom resolver stays
  /// blob-only (the public [VariantResolver.resolve] SPI), and its
  /// [ResolvedVariant] is wrapped as a [BlobPaywallPayload].
  Future<ResolvedPaywallPayload> _resolvePayload(VariantResolver resolver) {
    if (resolver is PresentationPaywallResolver) {
      return (resolver as PresentationPaywallResolver)
          .resolvePayloadForPresentation(
        widget.id,
        placementId: widget.placementId,
        locale: widget.locale,
      );
    }
    if (resolver is FlowCapableVariantResolver) {
      return (resolver as FlowCapableVariantResolver).resolvePayload(
        widget.id,
        placementId: widget.placementId,
        locale: widget.locale,
      );
    }
    return resolver
        .resolve(
          widget.id,
          placementId: widget.placementId,
          locale: widget.locale,
        )
        .then(BlobPaywallPayload.new);
  }

  /// Re-enters the same resolver when hosted work crossed an anonymous-actor
  /// boundary. Bundled and custom payloads have no lease and pass directly.
  Future<ResolvedPaywallPayload?> _resolveStablePayload(
    VariantResolver resolver,
    int epoch,
  ) async {
    while (mounted && epoch == _loadEpoch) {
      try {
        final payload = await _resolvePayload(resolver);
        if (!mounted || epoch != _loadEpoch) {
          payload.abandonHostedLastGood();
          return null;
        }
        if (payload.assignmentLease?.isCurrent ?? true) return payload;
        payload.abandonHostedLastGood();
      } on StaleSurfaceAssignmentResolution {
        // The resolver's existing tiered ladder runs again under the new actor.
      }
    }
    return null;
  }

  /// Hosts a flow-shaped paywall (a lowered navigation paywall) by constructing
  /// a flow controller over the already-resolved document + a synthesized
  /// descriptor, rendered via [RestageFlowView] in [build].
  ///
  /// The paywall runtime contract is preserved on every screen: purchase/restore
  /// initiation is intercepted to bill (never to drive a graph transition, see
  /// [_interceptFlowScreenEvent]), and the flow's onboarding-shaped lifecycle is
  /// suppressed in favor of paywall lifecycle keyed on [RestagePaywall.id].
  void _startFlow(
    FlowPaywallPayload payload,
    Stopwatch stopwatch, {
    required int epoch,
    bool fromCache = false,
  }) {
    // A fresh mount (or cache fallback) hosts immediately, but does not stamp
    // identity, cache, or lifecycle until its first concrete screen reaches
    // guarded paint without a boundary-recorded build failure. The live-refresh
    // path stages above last-good first.
    late final RestageFlowController<void> controller;
    late final FirstPaintLeaseTransaction transaction;
    controller = _buildFlowController(
      payload,
      onEvent: (_) {},
      onComplete: (_) {
        if (!_flowLoadAnnounced &&
            !(payload.assignmentLease?.isCurrent ?? true)) {
          _retryStaleInitialFlow(
            controller,
            payload,
            epoch,
            transaction,
          );
          return;
        }
        _removeInitialFlowReadinessListener(controller);
        _handleFlowComplete(controller);
      },
      onUnavailable: (error) {
        if (!_flowLoadAnnounced &&
            !(payload.assignmentLease?.isCurrent ?? true)) {
          _retryStaleInitialFlow(
            controller,
            payload,
            epoch,
            transaction,
          );
          return;
        }
        _removeInitialFlowReadinessListener(controller);
        _handleFlowUnavailable(controller, error);
      },
    );
    transaction = FirstPaintLeaseTransaction(
      isReady: () => controller.currentScreenEntryId != null,
      isInvalidatedByIdentityReset: () =>
          !(payload.assignmentLease?.isCurrent ?? true),
      canCommit: () => _canCommitInitialFlow(
        controller,
        payload,
        epoch,
        transaction,
      ),
      commit: () => _commitInitialFlowAtPaint(
        controller,
        payload,
        epoch,
        transaction,
      ),
      onPainted: () => _publishRenderedPayload(payload),
      afterCommit: () => _finishInitialFlowPaintCommit(
        controller,
        payload,
        stopwatch,
        fromCache,
      ),
      afterRejection: () => _rejectInitialFlowTransaction(
        controller,
        payload,
        epoch,
        transaction,
      ),
      onAbandon: payload.abandonHostedLastGood,
    );
    setState(() {
      _flowController = controller;
      _flowTransaction = transaction;
      _flowEpoch = epoch;
      _initialFlowIsStaged = false;
      _error = null;
    });
    late final VoidCallback readinessListener;
    readinessListener = () {
      if (!mounted || !identical(_flowController, controller)) return;
      if (controller.currentScreenEntryId != null) {
        final assignmentLease = payload.assignmentLease;
        if (assignmentLease != null && !assignmentLease.isCurrent) {
          return;
        }
        if (!_initialFlowIsStaged && transaction.isPending) {
          setState(() => _initialFlowIsStaged = true);
        }
      }
      if (!controller.hasRenderedContent || !transaction.isCommitted) return;
      _removeInitialFlowReadinessListener(controller);
      scheduleMicrotask(() => _commitInitialFlow(
            controller,
            payload,
            stopwatch,
            fromCache,
          ));
    };
    _initialFlowReadinessListener = readinessListener;
    controller.addListener(readinessListener);
    unawaited(controller.load());
  }

  void _commitInitialFlow(
    RestageFlowController<void> controller,
    FlowPaywallPayload payload,
    Stopwatch stopwatch,
    bool fromCache,
  ) {
    if (!mounted ||
        !identical(_flowController, controller) ||
        !controller.hasRenderedContent ||
        !(_flowTransaction?.isCommitted ?? false) ||
        _flowLoadAnnounced) {
      return;
    }
    _initialFlowIsStaged = false;
    _announceFlowLoaded(
      stopwatch.elapsed,
      fromCache || payload.flow.cacheHit,
      experimentId: payload.experimentId,
      variantId: payload.variantId,
      experimentEpoch: payload.experimentEpoch,
    );
  }

  void _removeInitialFlowReadinessListener(
    RestageFlowController<void> controller,
  ) {
    if (!identical(_flowController, controller)) return;
    final listener = _initialFlowReadinessListener;
    if (listener == null) return;
    _initialFlowReadinessListener = null;
    controller.removeListener(listener);
  }

  void _retryStaleInitialFlow(
    RestageFlowController<void> controller,
    FlowPaywallPayload payload,
    int epoch,
    FirstPaintLeaseTransaction transaction,
  ) {
    final assignmentLease = payload.assignmentLease;
    if (assignmentLease == null || assignmentLease.isCurrent) return;
    if (!mounted ||
        !identical(_flowController, controller) ||
        !identical(_flowTransaction, transaction) ||
        _flowEpoch != epoch ||
        epoch != _loadEpoch ||
        transaction.isCommitted) {
      return;
    }
    _removeInitialFlowReadinessListener(controller);
    _initialFlowIsStaged = false;
    transaction.supersede();
    _flowTransaction = null;
    _flowEpoch = null;
    setState(() => _flowController = null);
    unawaited(_load(announceLoadStarted: false));
    _disposeFlowControllerAfterDetach(controller);
  }

  bool _canCommitInitialFlow(
    RestageFlowController<void> controller,
    FlowPaywallPayload payload,
    int epoch,
    FirstPaintLeaseTransaction transaction,
  ) {
    final result = mounted &&
        identical(_flowController, controller) &&
        identical(_flowTransaction, transaction) &&
        _flowEpoch == epoch &&
        epoch == _loadEpoch &&
        controller.currentScreenEntryId != null &&
        (payload.assignmentLease?.isCurrent ?? true);
    return result;
  }

  /// Paint-time authority mutation. Keep this synchronous and callback-free.
  void _commitInitialFlowAtPaint(
    RestageFlowController<void> controller,
    FlowPaywallPayload payload,
    int epoch,
    FirstPaintLeaseTransaction transaction,
  ) {
    _resolvedPaywallPublishedVersion = payload.paywallPublishedVersion;
    _renderedExperimentId = payload.experimentId;
    _renderedExperimentVariantId = payload.variantId;
    _renderedExperimentEpoch = payload.experimentEpoch;
    _renderedAssignmentLease = payload.assignmentLease;
    _renderedContentHash = null;
  }

  void _finishInitialFlowPaintCommit(
    RestageFlowController<void> controller,
    FlowPaywallPayload payload,
    Stopwatch stopwatch,
    bool fromCache,
  ) {
    if (!mounted || !identical(_flowController, controller)) return;
    setState(() {});
    if (controller.hasRenderedContent) {
      _commitInitialFlow(controller, payload, stopwatch, fromCache);
    }
  }

  void _rejectInitialFlowTransaction(
    RestageFlowController<void> controller,
    FlowPaywallPayload payload,
    int epoch,
    FirstPaintLeaseTransaction transaction,
  ) {
    if (!mounted ||
        !identical(_flowController, controller) ||
        !identical(_flowTransaction, transaction) ||
        _flowEpoch != epoch) {
      return;
    }
    if (epoch != _loadEpoch) {
      _removeInitialFlowReadinessListener(controller);
      _flowController = null;
      _flowTransaction = null;
      _flowEpoch = null;
      _initialFlowIsStaged = false;
      setState(() {});
      _disposeFlowControllerAfterDetach(controller);
      return;
    }
    _retryStaleInitialFlow(controller, payload, epoch, transaction);
  }

  /// Builds a flow controller over an already-resolved [payload]. Construction
  /// is shared by the mount path ([_startFlow]) and the refresh path
  /// ([_refreshFlow]); only the lifecycle callbacks differ.
  RestageFlowController<void> _buildFlowController(
    FlowPaywallPayload payload, {
    required void Function(RestageEvent) onEvent,
    required void Function(void) onComplete,
    required void Function(FlowUnavailableError) onUnavailable,
  }) {
    final document = payload.flow.document;
    return RestageFlowController<void>(
      flow: OnboardingFlowRef<void>(
        id: document.flow,
        version: document.version,
        minClient: document.minClient,
        decodeResult: (_) {},
      ),
      resolver: _PreResolvedFlowResolver(payload.flow),
      actions: null,
      onEvent: onEvent,
      onComplete: onComplete,
      onUnavailable: onUnavailable,
    );
  }

  /// Routes a screen-fired event for a flow-hosted paywall. Navigation events
  /// (the synthetic `restageNav<N>`, the reserved `back` / `skip`) flow through
  /// to the controller's graph. Everything else — purchase/restore initiation
  /// and custom events — is handled by the paywall demux out-of-band and
  /// consumed, so the controller never drives a speculative transition and a
  /// custom event surfaces as a paywall-keyed [PaywallCustomEvent], not a
  /// flowId-bearing FlowCustomEvent. Returns true when consumed.
  bool _interceptFlowScreenEvent(String name, Map<String, Object?> args) {
    if (_isFlowNavigationEvent(name)) return false;
    // Mirror the controller's own event gate (flow_controller.handleEvent): a
    // purchase/restore from a screen whose flow is mid-transition, complete, or
    // failed must NOT bill — a stale tap during a skip/back/nav transition, or
    // after the flow has ended, must never charge. Consume-and-drop so the
    // event still never reaches the graph.
    final controller = _flowController;
    if (controller != null &&
        (controller.isBusy ||
            controller.isComplete ||
            controller.isUnavailable)) {
      return true;
    }
    _handleRfwEvent(name, args);
    return true;
  }

  /// Matches exactly the synthesized navigation events (`restageNav<N>`), so a
  /// look-alike custom event (`restageNavFoo`) is NOT mistaken for navigation
  /// and instead surfaces as a paywall custom event.
  static final RegExp _navEventPattern =
      RegExp('^$_kFlowNavEventPrefix' r'\d+$');

  static bool _isFlowNavigationEvent(String name) =>
      name == _kFlowBackEvent ||
      name == _kFlowSkipEvent ||
      _navEventPattern.hasMatch(name);

  /// Suppresses the flow runtime's onboarding-shaped, flowId-bearing lifecycle
  /// and keeps paywall lifecycle exact-once after render commitment. A pending
  /// refresh's initial [FlowStarted] is suppressed before promotion; later
  /// start events cannot promote or restamp the presentation.
  void _handleFlowLifecycleEvent(
    RestageEvent event,
    Stopwatch stopwatch,
    FlowPaywallPayload payload,
    bool fromCache,
  ) {
    if (event is! FlowStarted) return;
    // Render commitment already happened before a refresh controller could be
    // promoted. Keep its committed payload cached; lifecycle announcement is
    // exact-once and is therefore inert for later start events.
    if (widget.cacheLastRender) {
      _lastSuccessfulPayloads[widget.id] = payload;
    }
    _announceFlowLoaded(
      stopwatch.elapsed,
      fromCache || payload.flow.cacheHit,
      experimentId: payload.experimentId,
      variantId: payload.variantId,
      experimentEpoch: payload.experimentEpoch,
    );
  }

  /// Announces the paywall-shaped load lifecycle for a flow-hosted paywall
  /// exactly once: `PaywallLoadCompleted` now + `PaywallViewed` after the first
  /// frame. Mirrors [_finishCommittedBlobStage]'s blob lifecycle, keyed on
  /// paywallId.
  /// [experimentId], [variantId], and [experimentEpoch] are the server-selected
  /// experiment assignment for a hosted active flow (null for a bundled/custom
  /// resolution) — threaded onto `PaywallViewed` at parity with the blob path.
  void _announceFlowLoaded(
    Duration loadDuration,
    bool cacheHit, {
    String? experimentId,
    String? variantId,
    int? experimentEpoch,
  }) {
    if (_flowLoadAnnounced || !mounted) return;
    _flowLoadAnnounced = true;
    _fireEvent(PaywallLoadCompleted(
      paywallId: widget.id,
      loadDuration: loadDuration,
      cacheHit: cacheHit,
    ));
    _schedulePaywallViewed(
      experimentId: experimentId,
      variantId: variantId,
      experimentEpoch: experimentEpoch,
    );
  }

  /// Fires `PaywallViewed` exactly once in a post-frame callback after the first
  /// render. Shared by the blob lifecycle ([_finishCommittedBlobStage]) and the
  /// flow-hosted lifecycle ([_announceFlowLoaded]); assignment fields default
  /// to null for resolutions that are not part of an experiment.
  void _schedulePaywallViewed({
    String? variantId,
    String? experimentId,
    int? experimentEpoch,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _viewedFired) return;
      _viewedFired = true;
      _fireEvent(PaywallViewed(
        paywallId: widget.id,
        productIds:
            Restage.configuredProducts.map((p) => p.id).toList(growable: false),
        variantId: variantId,
        experimentId: experimentId,
        experimentEpoch: experimentEpoch,
        publishedVersion: _resolvedPaywallPublishedVersion,
      ));
    });
  }

  /// The flow reached its end state (the entry screen's skip/dismiss → end): the
  /// user backed out of the paywall. Surface a paywall dismiss keyed on
  /// paywallId — NOT an onboarding completion. (A successful purchase does NOT
  /// route here; per the paywall contract the host owns dismissal, identical to
  /// a blob paywall.)
  void _handleFlowComplete(RestageFlowController<void> controller) {
    if (!mounted || !identical(_flowController, controller)) return;
    _fireDismissed(DismissReason.userClose);
  }

  /// The flow failed closed (a missing / incompatible / unrenderable artifact,
  /// or a screen that threw during build). Surface a paywall load failure + the
  /// error UI, mirroring the blob path's fail-closed posture.
  void _handleFlowUnavailable(
    RestageFlowController<void> controller,
    FlowUnavailableError error,
  ) {
    if (!mounted || !identical(_flowController, controller)) return;
    // Evict a poisonous cached flow so a later fallback does not re-host an
    // unrenderable flow forever (mirrors the blob path's cache eviction on a
    // decode failure). A no-op when nothing is cached.
    _lastSuccessfulPayloads.remove(widget.id);
    final err = RestagePaywallError(
      code: RestageErrorCodes.renderError,
      message: 'The navigation paywall "${widget.id}" could not be hosted '
          '(${error.reason}): ${error.message}',
    );
    _removeInitialFlowReadinessListener(controller);
    _flowTransaction?.supersede();
    setState(() {
      _flowController = null;
      _flowTransaction = null;
      _flowEpoch = null;
      _initialFlowIsStaged = false;
      _error = err;
    });
    _disposeFlowControllerAfterDetach(controller);
    _fireEvent(PaywallLoadFailed(
      paywallId: widget.id,
      errorCode: err.code,
      message: err.message,
      retryable: false,
    ));
  }

  /// Feeds a synthesized purchase/restore OUTCOME event to a hosted flow
  /// controller after billing resolves, so a flow screen can transition on a
  /// CONFIRMED outcome — never on `PaywallFlowEvents.purchase`, which would
  /// navigate on initiation, before charging. A flow screen with no transition
  /// on the outcome event simply ignores it (and a blob paywall has no flow
  /// controller, so this is always a no-op there).
  void _feedFlowOutcome(String outcomeEvent) {
    _flowController?.handleEvent(outcomeEvent, const <String, Object?>{});
  }

  /// Stages a decoded blob in an isolated runtime. The current presentation
  /// stays mounted until this exact candidate commits at first paint.
  void _stageBlob(
    BlobPaywallPayload payload,
    WidgetLibrary library, {
    required int epoch,
    required bool isRefresh,
    required Duration loadDuration,
    required bool cacheHit,
  }) {
    final runtime = _createBlobRuntime()..update(_paywallLibrary, library);
    final data = DynamicContent();
    late final _BlobStage stage;
    final transaction = FirstPaintLeaseTransaction(
      isInvalidatedByIdentityReset: () =>
          !(stage.payload.assignmentLease?.isCurrent ?? true),
      canCommit: () => _canCommitBlobStage(stage),
      commit: () => _commitBlobStage(stage),
      onPainted: () => _publishRenderedPayload(payload),
      afterCommit: () => _finishCommittedBlobStage(stage),
      afterRejection: () => _rejectBlobStage(stage),
      onAbandon: payload.abandonHostedLastGood,
    );
    stage = _BlobStage(
      payload: payload,
      runtime: runtime,
      data: data,
      epoch: epoch,
      isRefresh: isRefresh,
      loadDuration: loadDuration,
      cacheHit: cacheHit,
      transaction: transaction,
    );
    _populateBlobData(stage);

    final superseded = _pendingBlobStage;
    if (superseded != null && !superseded.transaction.isCommitted) {
      superseded.transaction.supersede();
      _disposeBlobStageAfterDetach(superseded);
    }
    _pendingBlobStage = stage;
    setState(() => _error = null);
  }

  Runtime _createBlobRuntime() {
    final runtime = Runtime()
      ..update(
        const LibraryName(<String>['restage', 'core']),
        restage_core.buildCoreWidgetLibrary(),
      )
      ..update(
        const LibraryName(<String>['restage', 'material']),
        restage_material.buildMaterialWidgetLibrary(),
      )
      ..update(
        const LibraryName(<String>['restage', 'cupertino']),
        restage_cupertino.buildCupertinoWidgetLibrary(),
      );
    LibraryRuntimeRegistry.applyTo(runtime);
    return runtime;
  }

  void _populateBlobData(_BlobStage stage) {
    populateProductData(
      stage.data,
      products: Restage.configuredProducts,
      priceQueries: widget.priceQueries,
    );
    final mq = MediaQuery.maybeOf(context);
    if (mq != null) {
      populateDeviceData(
        stage.data,
        locale: widget.locale ?? const Locale('en'),
        mediaQuery: mq,
        platform: currentDevicePlatform(),
      );
    }
    final colorScheme = _lastThemeColorScheme;
    final iconTheme = _lastThemeIconTheme;
    final textStyle = _lastThemeTextStyle;
    if (colorScheme != null && iconTheme != null && textStyle != null) {
      populateThemeData(
        stage.data,
        colorScheme: colorScheme,
        iconTheme: iconTheme,
        defaultTextStyle: textStyle,
      );
    }
  }

  bool _canCommitBlobStage(_BlobStage stage) {
    if (!mounted ||
        !identical(_pendingBlobStage, stage) ||
        stage.epoch != _loadEpoch ||
        !(stage.payload.assignmentLease?.isCurrent ?? true)) {
      return false;
    }
    return !stage.isRefresh || _canSwap();
  }

  /// Paint-time authority mutation. Keep this synchronous and callback-free.
  void _commitBlobStage(_BlobStage stage) {
    final variant = stage.payload.variant;
    stage
      ..previousBlob = _blobPresentation
      ..previousFlow = _flowController;
    _blobPresentation = stage;
    _flowController = null;
    _flowTransaction = null;
    _flowEpoch = null;
    _resolvedPaywallPublishedVersion = variant.paywallPublishedVersion;
    _renderedExperimentId = variant.experimentId;
    _renderedExperimentVariantId = variant.variantId;
    _renderedExperimentEpoch = variant.experimentEpoch;
    _renderedAssignmentLease = stage.payload.assignmentLease;
    _renderedContentHash = variant.paywallPublishedVersion == null
        ? FlowContentHash.compute(variant.bytes)
        : null;
  }

  void _finishCommittedBlobStage(_BlobStage stage) {
    if (!mounted || !stage.transaction.isCommitted) return;
    if (identical(_pendingBlobStage, stage)) {
      setState(() {
        _pendingBlobStage = null;
        _error = null;
      });
    }
    _fireEvent(PaywallLoadCompleted(
      paywallId: widget.id,
      loadDuration: stage.loadDuration,
      cacheHit: stage.cacheHit,
    ));
    _viewedFired = false;
    final variant = stage.payload.variant;
    _schedulePaywallViewed(
      variantId: variant.variantId,
      experimentId: variant.experimentId,
      experimentEpoch: variant.experimentEpoch,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final previousBlob = stage.previousBlob;
      if (previousBlob != null) _disposeBlobStage(previousBlob);
      final previousFlow = stage.previousFlow;
      if (previousFlow != null) _disposeFlowController(previousFlow);
      stage
        ..previousBlob = null
        ..previousFlow = null;
    });
  }

  void _rejectBlobStage(_BlobStage stage) {
    if (!mounted || !identical(_pendingBlobStage, stage)) {
      _disposeBlobStage(stage);
      return;
    }
    final shouldRetry = stage.epoch == _loadEpoch &&
        !(stage.payload.assignmentLease?.isCurrent ?? true);
    setState(() => _pendingBlobStage = null);
    _disposeBlobStageAfterDetach(stage);
    if (shouldRetry) {
      _retryLoadAfterRejectedLease(
        stage.epoch,
        isRefresh: stage.isRefresh,
      );
    }
  }

  void _handleBlobBuildFailure(_BlobStage stage, Object error) {
    if (stage.transaction.isCommitted) {
      _fireEvent(PaywallLoadFailed(
        paywallId: widget.id,
        errorCode: RestageErrorCodes.renderError,
        message: error.toString(),
        retryable: false,
      ));
      return;
    }
    if (!identical(_pendingBlobStage, stage)) {
      _disposeBlobStage(stage);
      return;
    }
    if (!(stage.payload.assignmentLease?.isCurrent ?? true)) {
      _rejectBlobStage(stage);
      return;
    }
    final preserveLastGood = stage.isRefresh ||
        _blobPresentation != null ||
        (_flowTransaction?.isCommitted ?? false);
    if (preserveLastGood) {
      setState(() => _pendingBlobStage = null);
      _disposeBlobStageAfterDetach(stage);
      return;
    }
    final failure = RestagePaywallError(
      code: RestageErrorCodes.renderError,
      message: error.toString(),
    );
    setState(() {
      _pendingBlobStage = null;
      _error = failure;
    });
    _disposeBlobStageAfterDetach(stage);
    _fireEvent(PaywallLoadFailed(
      paywallId: widget.id,
      errorCode: failure.code,
      message: failure.message,
      retryable: false,
    ));
  }

  void _disposeBlobStageAfterDetach(_BlobStage stage) {
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _disposeBlobStage(stage));
  }

  /// Attempt to render from the SDK-internal cache. Returns `true` if a cached
  /// payload was found and applied (a blob decoded + rendered, or a flow
  /// re-hosted) — in which case the caller should abort its error path. Returns
  /// `false` if no cache was available or the cached blob failed to decode.
  ///
  /// On cache decode failure: evict the poisonous entry so a later success
  /// can repopulate, and fire a structured `PaywallLoadFailed` event so the
  /// host sees the cache failure separately from the original resolver
  /// failure (otherwise the cached-blob corruption is invisible).
  bool _tryFallbackToCache(Stopwatch stopwatch, int epoch) {
    if (!widget.cacheLastRender) return false;
    final cached = _lastSuccessfulPayloads[widget.id];
    if (cached == null) return false;
    final assignmentLease = cached.assignmentLease;
    if (assignmentLease != null && !assignmentLease.isCurrent) {
      _lastSuccessfulPayloads.remove(widget.id);
      return false;
    }
    switch (cached) {
      case FlowPaywallPayload(:final resolvedFromActiveArm):
        // An ACTIVE-resolved flow must NOT be re-hosted here un-re-gated: a
        // server-resolved active document whose contract no longer subsets the
        // (app-updated) bundled contract, or whose required libraries were
        // unregistered, would be re-served unchecked. Defer to the resolver's
        // own re-gated hold-last-good (it re-runs the render gate + retained
        // checks against the CURRENT bundled contract). A
        // BUNDLED flow re-hosts directly — its document + screen blobs are
        // app-bundle-trusted, so there is no active contract to drift.
        if (resolvedFromActiveArm) return false;
        if (!mounted) return false;
        _startFlow(cached, stopwatch, epoch: epoch, fromCache: true);
        return true;
      case BlobPaywallPayload(:final variant):
        try {
          final library = decodeLibraryBlob(variant.bytes);
          if (!mounted) return false;
          _stageBlob(
            cached,
            library,
            epoch: epoch,
            isRefresh: false,
            loadDuration: stopwatch.elapsed,
            cacheHit: true,
          );
          return true;
        } catch (e, st) {
          // Evict the poisonous payload (bytes + version travel together on the
          // sealed payload, so there is no orphaned version to mis-attribute).
          _lastSuccessfulPayloads.remove(widget.id);
          FlutterError.reportError(FlutterErrorDetails(
            exception: e,
            stack: st,
            library: 'restage',
            context: ErrorDescription(
              'decoding cached paywall blob for ${widget.id} (cache evicted)',
            ),
          ));
          _fireEvent(PaywallLoadFailed(
            paywallId: widget.id,
            errorCode: RestageErrorCodes.decodeFailed,
            message: 'Cached .rfw blob for ${widget.id} failed to decode '
                '(cache evicted): $e',
            retryable: true,
          ));
          return false;
        }
    }
  }

  void _disposeFlowControllerAfterDetach(
    RestageFlowController<void> controller,
  ) {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _disposeFlowController(controller),
    );
  }

  void _disposeFlowController(RestageFlowController<void> controller) {
    controller.dispose();
  }

  void _disposeBlobStage(_BlobStage stage) {
    final previousBlob = stage.previousBlob;
    final previousFlow = stage.previousFlow;
    stage
      ..previousBlob = null
      ..previousFlow = null
      ..dispose();
    if (previousBlob != null) _disposeBlobStage(previousBlob);
    if (previousFlow != null) _disposeFlowController(previousFlow);
  }

  @override
  void dispose() {
    if (_refreshHandle case final handle?) {
      SurfaceRefreshRegistry.instance.unregister(handle);
    }
    _refreshHandle = null;
    widget.controller?.detachInternal();
    // Fire dismissed FIRST (it binds the current surfaceSessionId synchronously),
    // then end the surface session.
    if (_viewedFired) _fireDismissed(DismissReason.programmatic);
    // Tear down every authority candidate directly. State.dispose runs while
    // mounted is still true, so it must not route through helpers that setState
    // or defer ownership cleanup. Controller/stage disposal is idempotent, so
    // callbacks already queued for a later frame remain harmless.
    final flowController = _flowController;
    if (flowController != null) {
      _removeInitialFlowReadinessListener(flowController);
    }
    final pendingFlowController = _pendingFlowController;
    if (pendingFlowController != null) {
      _removePendingFlowReadinessListener(pendingFlowController);
    }
    _flowTransaction?.supersede();
    _pendingFlowTransaction?.supersede();
    for (final controller in <RestageFlowController<void>?>{
      flowController,
      pendingFlowController,
      _flowToDisposeAfterPromotion,
    }) {
      if (controller != null) _disposeFlowController(controller);
    }
    for (final stage in <_BlobStage?>{
      _blobPresentation,
      _pendingBlobStage,
      _blobToDisposeAfterPromotion,
    }) {
      if (stage != null) _disposeBlobStage(stage);
    }
    _flowController = null;
    _flowTransaction = null;
    _flowEpoch = null;
    _pendingFlowController = null;
    _pendingFlowReadinessListener = null;
    _pendingFlowTransaction = null;
    _pendingFlowEpoch = null;
    _flowToDisposeAfterPromotion = null;
    _blobPresentation = null;
    _pendingBlobStage = null;
    _blobToDisposeAfterPromotion = null;
    Restage.endSurfaceSession();
    super.dispose();
  }

  /// Single helper that translates RFW events into [RestageEvent]s.
  ///
  /// SDK-owned events (`restage.purchase`, `restage.restore`) become typed
  /// `PurchaseInitiated` / `RestoreInitiated`; everything else flows through
  /// as [PaywallCustomEvent]. See [demuxRfwEvent].
  ///
  /// When the demuxed event is [PurchaseInitiated] / [RestoreInitiated] the
  /// SDK also invokes [Restage.billingGateway] and fires the resulting
  /// follow-up event (`PurchaseSucceeded`, `PurchasePending`, etc.).
  void _handleRfwEvent(String name, Object? args) {
    // Any authored event from the rendered content marks the surface dirty for
    // the swap-safety gate. Deliberately broad — taps, inputs, purchases — so a
    // live swap never lands under an engaged user. Only reached for authored
    // content events (theme/system changes flow through didChangeDependencies).
    _userInteracted = true;
    final argsMap = args is Map<String, Object?>
        ? args
        : (args is Map ? args.cast<String, Object?>() : <String, Object?>{});
    final event = demuxRfwEvent(
      paywallId: widget.id,
      name: name,
      args: argsMap,
    );

    // Reserve the in-flight billing guard BEFORE firing the initiation event,
    // so a double-tap (or a synchronous re-entrant `onEvent` listener) fires the
    // initiation AND bills exactly once — a second concurrent initiation is
    // dropped whole (no duplicate `PurchaseInitiated`/`RestoreInitiated`, no
    // second charge). Billing is dispatched before the event fires so its
    // `finally` owns the guard release even if the synchronous event fire throws
    // (a host `onEvent` could). _runPurchase/_runRestore only RELEASE the guard.
    if (event is PurchaseInitiated && event.productId.isNotEmpty) {
      if (_billingInFlight) return;
      _billingInFlight = true;
      unawaited(_runPurchase(event.productId, offerId: event.offerId));
      _fireEvent(event);
      return;
    }
    if (event is RestoreInitiated) {
      if (_billingInFlight) return;
      _billingInFlight = true;
      unawaited(_runRestore());
      _fireEvent(event);
      return;
    }
    _fireEvent(event);
  }

  Future<void> _runPurchase(String productId, {String? offerId}) async {
    // The in-flight billing guard is reserved by the caller (_handleRfwEvent)
    // before the initiation event fires; here we only RELEASE it in the
    // `finally` on EVERY outcome (success/pending/cancelled/failed/thrown
    // error), so a legitimate sequential purchase or retry is never blocked.
    try {
      final gateway = Restage.billingGateway;
      final coordinatorOwned = BundledPurchaseOwnership.isInstalled(gateway);
      final attribution = _capturePurchaseAttribution(offerId);
      final purchase = PurchaseAttributionScope.run(
        attribution,
        () => Restage.purchaseProduct(productId, offerId: offerId),
      );
      final outcome = await purchase;
      // Don't early-return on !mounted: the global event stream + entitlement
      // grant must run even when the user has navigated away mid-flow,
      // otherwise a user who taps Buy and then dismisses gets charged but
      // never receives the entitlement. The per-paywall onEvent callback is
      // mounted-guarded inside _fireEvent.
      switch (outcome) {
        case PurchaseOutcomeSucceeded(
            :final transactionId,
            :final verificationData,
            :final priceMicros,
            :final currency,
          ):
          _fireEvent(PurchaseSucceeded(
            paywallId: widget.id,
            productId: productId,
            transactionId: transactionId,
            priceMicros: priceMicros,
            currency: currency,
            offerId: offerId,
          ));
          if (!coordinatorOwned) {
            Restage.grantEntitlementForProduct(
              productId,
              EntitlementSource.purchase,
            );
            if (verificationData != null) {
              // Verified purchase (the bundled gateway surfaced the store
              // receipt): report it to the entitlement service in the
              // background. The optimistic local grant above keeps UX
              // immediate; the report converges the server's view and feeds
              // the reserved subscription events on the next reconciliation.
              // No-ops cleanly when the SDK was configured without a baseUrl.
              unawaited(Restage.reportTransaction(
                storeProductId: productId,
                storeTransactionId: transactionId,
                storeVerificationData: verificationData,
                paywallId: widget.id,
                paywallPublishedVersion: _resolvedPaywallPublishedVersion,
              ));
            } else {
              // Receipt-less, attribution-only success: an external-provider
              // gateway delegated the purchase and kept the receipt, so there
              // is nothing to validate. Report the attribution hint
              // (transaction id + paywall id) — never down the
              // receipt-validation path. No-ops cleanly when the SDK was
              // configured without a baseUrl.
              unawaited(Restage.reportAttribution(
                storeProductId: productId,
                storeTransactionId: transactionId,
                paywallId: widget.id,
                paywallPublishedVersion: _resolvedPaywallPublishedVersion,
              ));
            }
          }
          _feedFlowOutcome(_kPurchaseSucceededEvent);
        case PurchaseOutcomePending(:final reason):
          _fireEvent(PurchasePending(
            paywallId: widget.id,
            productId: productId,
            reason: reason,
          ));
          _feedFlowOutcome(_kPurchasePendingEvent);
        case PurchaseOutcomeCancelled():
          _fireEvent(PurchaseCancelled(
            paywallId: widget.id,
            productId: productId,
          ));
          _feedFlowOutcome(_kPurchaseCancelledEvent);
        case PurchaseOutcomeFailed(
            :final errorCode,
            :final message,
            :final platformErrorCode,
          ):
          _fireEvent(PurchaseFailed(
            paywallId: widget.id,
            productId: productId,
            errorCode: errorCode,
            message: message,
            platformErrorCode: platformErrorCode,
          ));
          _feedFlowOutcome(_kPurchaseFailedEvent);
      }
    } finally {
      _billingInFlight = false;
    }
  }

  Future<void> _runRestore() async {
    // The in-flight billing guard is reserved by the caller (_handleRfwEvent);
    // here we only RELEASE it in the `finally` on every outcome.
    try {
      final gateway = Restage.billingGateway;
      final coordinatorOwned = BundledPurchaseOwnership.isInstalled(gateway);
      final outcome = await gateway.restore();
      // See _runPurchase: global side effects fire regardless of mount.
      switch (outcome) {
        case RestoreOutcomeSucceeded(:final restoredProductIds):
          _fireEvent(RestoreSucceeded(
            paywallId: widget.id,
            restoredProductIds: restoredProductIds,
          ));
          if (!coordinatorOwned) {
            for (final productId in restoredProductIds) {
              Restage.grantEntitlementForProduct(
                productId,
                EntitlementSource.restore,
              );
            }
          }
          _feedFlowOutcome(_kRestoreSucceededEvent);
        case RestoreOutcomeNoPurchases():
          _fireEvent(RestoreNoPurchases(paywallId: widget.id));
          _feedFlowOutcome(_kRestoreNoPurchasesEvent);
        case RestoreOutcomeFailed(:final errorCode, :final message):
          _fireEvent(RestoreFailed(
            paywallId: widget.id,
            errorCode: errorCode,
            message: message,
          ));
          _feedFlowOutcome(_kRestoreFailedEvent);
      }
    } finally {
      _billingInFlight = false;
    }
  }

  PurchaseAttributionSnapshot _capturePurchaseAttribution(String? offerId) {
    final experimentId = _renderedExperimentId;
    final experimentVariantId = _renderedExperimentVariantId;
    final experimentEpoch = _renderedExperimentEpoch;
    final hasCompleteExperiment = experimentId != null &&
        experimentVariantId != null &&
        experimentEpoch != null;
    return PurchaseAttributionSnapshot(
      paywallId: widget.id,
      paywallPublishedVersion: _resolvedPaywallPublishedVersion,
      experimentId: hasCompleteExperiment ? experimentId : null,
      experimentVariantId: hasCompleteExperiment ? experimentVariantId : null,
      experimentEpoch: hasCompleteExperiment ? experimentEpoch : null,
      offerId: offerId,
    );
  }

  /// Adapter so the [RestagePaywallEventDispatcher] (which expects
  /// `void Function(String, Map<String, Object?>)`) can forward to the
  /// shared [_handleRfwEvent] helper.
  void _dispatcherEvent(String name, Map<String, Object?> args) =>
      _handleRfwEvent(name, args);

  bool _canBuildHostedFlow(RestageFlowController<void> controller) {
    if (identical(_flowController, controller)) {
      final transaction = _flowTransaction;
      return transaction != null &&
          (transaction.isPending || transaction.isCommitted);
    }
    if (identical(_pendingFlowController, controller)) {
      final transaction = _pendingFlowTransaction;
      return transaction != null &&
          (transaction.isPending || transaction.isCommitted);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      final builder = widget.errorBuilder;
      return builder == null
          ? const SizedBox.shrink()
          : builder(context, _error!);
    }
    final flowController = _flowController;
    final Widget current = flowController != null &&
            _canBuildHostedFlow(flowController)
        ? _buildHostedFlowLayer(flowController, staged: false)
        : _blobPresentation != null
            ? _buildBlobLayer(_blobPresentation!, staged: false)
            : (widget.loadingBuilder?.call(context) ?? const SizedBox.shrink());
    final pending = _pendingFlowIsStaged ? _pendingFlowController : null;
    // Keep a stable Stack across flow staging and promotion. The controller-keyed
    // candidate moves from the second slot to the first without remounting, so
    // the successful build being committed is the exact element the user sees.
    return Stack(
      fit: StackFit.passthrough,
      children: <Widget>[
        current,
        if (_pendingBlobStage case final stage?)
          if (stage.isRefresh)
            Positioned.fill(child: _buildBlobLayer(stage, staged: true))
          else
            _buildBlobLayer(stage, staged: true),
        if (pending != null && _canBuildHostedFlow(pending))
          Positioned.fill(
            child: _buildHostedFlowLayer(pending, staged: true),
          ),
      ],
    );
  }

  Widget _buildHostedFlowLayer(
    RestageFlowController<void> controller, {
    required bool staged,
  }) {
    final transaction = identical(_pendingFlowController, controller)
        ? _pendingFlowTransaction
        : _flowTransaction;
    final candidatePending =
        transaction != null && transaction.isReady && !transaction.isCommitted;
    Widget child = RestageFlowView<void>(
      controller: controller,
      onScreenEvent: _interceptFlowScreenEvent,
      loadingBuilder: widget.loadingBuilder,
      priceQueries: widget.priceQueries,
      // A paywall is fully self-authored, so built-in flow chrome never
      // overlaps its authored back and dismiss affordances.
      chromeBuilder: (context, state, screen) => screen,
    );
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
          // A lowered navigation paywall: host the flow. Purchase/restore on
          // any screen is intercepted to bill; navigation events drive the
          // flow. A staged refresh is visibly built above last-good, but inert.
          child: child,
        ),
      ),
    );
  }

  Widget _buildBlobLayer(_BlobStage stage, {required bool staged}) {
    final candidatePending = !stage.transaction.isCommitted;
    return KeyedSubtree(
      key: ObjectKey(stage),
      child: ExcludeSemantics(
        excluding: staged || candidatePending,
        child: AbsorbPointer(
          absorbing: staged || candidatePending,
          child: FirstPaintLeaseScope(
            transaction: stage.transaction,
            child: FirstPaintLeaseGuard(
              transaction: stage.transaction,
              armed: true,
              child: RestagePaywallEventDispatcher(
                onEvent: _dispatcherEvent,
                child: RuntimeErrorBoundary(
                  onError: (error, _) {
                    _handleBlobBuildFailure(stage, error);
                  },
                  errorReplacement: (context, _, __) {
                    if (!stage.transaction.isCommitted) {
                      return const SizedBox.shrink();
                    }
                    final eb = widget.errorBuilder;
                    if (eb == null) return const SizedBox.shrink();
                    return eb(
                      context,
                      const RestagePaywallError(
                        code: RestageErrorCodes.renderError,
                        message: 'A widget in the paywall threw during build.',
                      ),
                    );
                  },
                  child: RemoteWidget(
                    runtime: stage.runtime,
                    data: stage.data,
                    widget: const FullyQualifiedWidgetName(
                      _paywallLibrary,
                      'Paywall',
                    ),
                    onEvent: _handleRfwEvent,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Reserved flow navigation events the adapter forwards to the controller's
// graph. Everything else fired by a paywall screen either bills (purchase /
// restore) or surfaces as a paywall custom event. `restageNav<N>` is the
// synthesized nav transition; `back` / `skip` are the flow runtime's reserved
// history-pop / dismiss events.
const String _kFlowBackEvent = 'back';
const String _kFlowSkipEvent = 'skip';
const String _kFlowNavEventPrefix = 'restageNav';

// The synthesized purchase/restore OUTCOME flow events — the named
// outcome-event contract. After billing resolves, the adapter feeds the
// matching one to a hosted flow controller so a flow screen can transition on a
// CONFIRMED outcome, never on `PaywallFlowEvents.purchase` (which fires on
// initiation, before charging). A flow screen that authors no transition on the
// outcome event ignores it.
const String _kPurchaseSucceededEvent = 'restage.purchase.succeeded';
const String _kPurchasePendingEvent = 'restage.purchase.pending';
const String _kPurchaseCancelledEvent = 'restage.purchase.cancelled';
const String _kPurchaseFailedEvent = 'restage.purchase.failed';
const String _kRestoreSucceededEvent = 'restage.restore.succeeded';
const String _kRestoreNoPurchasesEvent = 'restage.restore.noPurchases';
const String _kRestoreFailedEvent = 'restage.restore.failed';

/// A [FlowResolver] that returns an already-resolved flow verbatim.
///
/// The paywall variant resolver has already loaded + validated the flow
/// document and its screen blobs (a [ResolvedFlow]); this lets [_startFlow] feed
/// that result straight into a [RestageFlowController] without re-fetching, so
/// the controller's standard load/validate path runs over the bundled flow.
final class _PreResolvedFlowResolver implements FlowResolver {
  _PreResolvedFlowResolver(this._resolved);

  final ResolvedFlow _resolved;

  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> flow) async => _resolved;
}

final class _BlobStage {
  _BlobStage({
    required this.payload,
    required this.runtime,
    required this.data,
    required this.epoch,
    required this.isRefresh,
    required this.loadDuration,
    required this.cacheHit,
    required this.transaction,
  });

  final BlobPaywallPayload payload;
  final Runtime runtime;
  final DynamicContent data;
  final int epoch;
  final bool isRefresh;
  final Duration loadDuration;
  final bool cacheHit;
  final FirstPaintLeaseTransaction transaction;

  _BlobStage? previousBlob;
  RestageFlowController<void>? previousFlow;
  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    transaction.supersede();
    runtime.dispose();
  }
}
