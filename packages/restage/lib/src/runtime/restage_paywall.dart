import 'dart:async';

import 'package:restage_measurement_schema/restage_measurement_schema.dart'
    show MeasurementOccurrenceChannelV1;

import 'package:flutter/material.dart' show ColorScheme, TextTheme, Theme;
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart' show internal;
import 'package:restage_material/restage_material_runtime.dart';
import 'package:restage_shared/restage_shared.dart' hide WidgetLibrary;
import 'package:rfw/rfw.dart';

import '../delivery/delivered_fonts.dart';
import '../delivery/raced_surface_resolver.dart';
import '../delivery/surface_sections_carrier.dart';
import '../delivery/render_deadline.dart';
import '../delivery/surface_delivery_paint_boundary.dart';
import '../delivery/surface_race.dart';
import '../delivery/surface_delivery_receipt.dart';
import '../authoring/event_dispatch_admission.dart';
import '../analytics/root_analytics_context.dart';
import '../authoring/event_dispatcher.dart';
import '../authoring/paywall_event_dispatch.dart';
import '../events/event_enums.dart';
import '../events/restage_event.dart';
import '../flow/flow_controller.dart';
import '../flow/flow_descriptors.dart';
import '../flow/flow_experiment_mount.dart' show FlowMountRevalidationBoundary;
import '../flow/flow_resolver.dart';
import '../flow/restage_flow_view.dart';
import '../measurement/measurement_event_sanitizer.dart';
import 'local_values.dart';
import '../measurement/measurement_host_session.dart';
import '../measurement/restage_measurement.dart' show attachPurchaseExposure;
import '../measurement/placement_mount_attribution.dart';
import '../delivery/surface_delivery_receipt_batch.dart';
import '../measurement/measurement_resolved_publication_provenance.dart'
    show measurementExperimentAssignmentFor;
import '../resolver/surface_delivery_observations.dart'
    show
        SurfaceDeliveryObservationCell,
        readSurfaceDeliveryObservations,
        requestingViewShortestLogicalSide,
        withSurfaceDeliveryObservations;
import '../measurement/measurement_rfw_presentation.dart';
import '../refresh/surface_refresh_registry.dart';
import '../refresh/surface_refresh_trigger.dart';
import '../refresh/surface_update_channel.dart';
import '../resolver/resolved_paywall_payload.dart';
import '../resolver/resolved_variant.dart';
import '../resolver/surface_assignment_key_provider.dart';
import '../resolver/variant_resolver.dart';
import '../resolver/asset_variant_resolver.dart';
import '../resolver/placement_mount_resolver.dart';
import 'placement_presentation.dart';
import 'error_boundary.dart';
import 'event_demux.dart';
import 'first_paint_lease_guard.dart';
import 'library_runtime_registry.dart';
import 'restage_widget_libraries.dart';
import 'context_data.dart';
import 'restage.dart';
import 'paywall_controller.dart';
import 'paywall_error.dart';
import 'placement_mount.dart';
import 'surface_vocabulary.dart';
import 'state_variables.dart';

/// Internal: kept for callers that reset SDK state; there is no paywall cache.
void resetRestagePaywallCache() {}

/// Visible-for-testing alias for [resetRestagePaywallCache], exported so
/// tests can clear the cache without going through the full
/// [Restage.debugReset] surface.
@internal
void debugClearRestagePaywallCache() => resetRestagePaywallCache();

/// RFW paywall rendered as native Flutter widgets.
///
/// Prefer generated `*Surface(...)` widgets for typed bindings, registration,
/// compiled fallbacks and implicit placements.
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
///     if (event is PaywallCustomEvent) handlePaywallEvent(event);
///   },
/// )
/// ```
///
/// Constructor note: the presentation-related parameters ([loadingBuilder],
/// [errorBuilder], [cacheLastRender]) are intentionally kept as flat named
/// parameters. If a fourth presentation knob is ever added, they would be
/// grouped into a single `RestagePaywallPresentation` value object (passed as
/// a `presentation:` parameter) to keep the call site readable.
class RestagePaywall extends StatefulWidget implements RestagePlacementMount {
  /// Const constructor.
  const RestagePaywall({
    super.key,
    required this.id,
    @Deprecated('Use a generated surface placement binding instead.')
    this.placementId,
    this.placementBinding,
    this.resolver,
    this.onEvent,
    this.controller,
    @Deprecated('Has no effect; the last accepted content is always kept.')
    this.cacheLastRender = false,
    this.loadingBuilder,
    this.errorBuilder,
    this.fallbackBuilder,
    this.locale,
    this.liveRefresh,

    /// Host-supplied render data published as `data.context.*`.
    ///
    /// Maps and lists can nest 32 levels deep below the root. A context holds
    /// up to 10,000 values, counting the root, and each update reads at most
    /// 100,000 map entries or list elements. Null map values are left out, and
    /// null list elements are removed so the list closes up. In debug builds,
    /// an invalid value, an unreadable collection, or a value over a limit
    /// throws; in release builds the SDK reports it and leaves that value or
    /// collection out. The SDK copies the values when you pass them. Passing
    /// equal values doesn't update the surface; null removes all host data.
    Map<String, Object?>? context,
  }) : _context = context;

  /// Creates the generated host facts without requiring new authored imports.
  static GeneratedPlacementDefinition generatedPlacementDefinition({
    required String id,
    required Map<String, Object?> defaultSurfaceLocatorJson,
    required Map<String, Object?> hostContractJson,
    SurfaceVocabulary vocabulary = SurfaceVocabulary.none,
  }) =>
      GeneratedPlacementDefinition.generated(
        defaultSurface: PaywallRef(id),
        defaultSurfaceLocatorJson: defaultSurfaceLocatorJson,
        hostContractJson: hostContractJson,
        vocabulary: vocabulary,
      );

  /// Creates the inert binding forwarded by a generated mount.
  static PlacementMountBinding generatedPlacementBinding({
    required GeneratedPlacementDefinition Function() definition,
    String? name,
  }) =>
      PlacementMountBinding(definition: definition, name: name);

  /// Stable paywall identifier (e.g. `'pro_upgrade'`).
  final String id;

  /// Optional placement identifier for delivery and analytics routing.
  @Deprecated('Use a generated surface placement binding instead.')
  final String? placementId;

  /// The generated default definition and optional named placement.
  @override
  final PlacementMountBinding? placementBinding;

  /// Variant resolver. Defaults to [Restage.defaultResolver] when null.
  final VariantResolver? resolver;

  /// Per-paywall callback for [RestageEvent]s fired by this paywall.
  /// Events also flow through [Restage.events] for app-wide listeners.
  final void Function(RestageEvent event)? onEvent;

  /// Optional handle for programmatic dismiss / fireEvent from the host.
  final RestagePaywallController? controller;

  /// Has no effect: the last content this install accepted is always kept.
  @Deprecated('Has no effect; the last accepted content is always kept.')
  final bool cacheLastRender;

  /// Builder shown while the paywall is loading, for at most the render
  /// deadline when [fallbackBuilder] is set. Default: [SizedBox.shrink].
  final WidgetBuilder? loadingBuilder;

  /// Builder shown when the paywall fails to load. Default: [SizedBox.shrink].
  final Widget Function(BuildContext context, RestagePaywallError error)?
      errorBuilder;

  /// Compiled authored widget used if initial delivery is unavailable.
  /// Generated paywall mounts supply the original constructor here. Events
  /// retain the paywall dispatcher; no hosted attribution is invented.
  final WidgetBuilder? fallbackBuilder;

  /// Locale to use when resolving and rendering the paywall.
  final Locale? locale;

  /// Per-widget live-refresh override. Null inherits the app-level
  /// configuration (`Restage.configure`); a provided set replaces it wholesale
  /// (an empty set opts this surface out entirely).
  final Set<SurfaceRefreshTrigger>? liveRefresh;

  final Map<String, Object?>? _context;

  @override
  State<RestagePaywall> createState() => _RestagePaywallState();
}

class _RestagePaywallState extends State<RestagePaywall> {
  static const String _paywallRootWidget = 'Paywall';

  static const LibraryName _paywallLibrary =
      LibraryName(<String>['restage', 'paywall']);

  _BlobStage? _blobPresentation;
  _BlobStage? _pendingBlobStage;
  SurfaceDeliveryObservationCell? _observationCell;
  int _loadEpoch = 0;
  RestagePaywallError? _error;
  bool _useAuthoredFallback = false;
  late final RenderDeadline _renderDeadline;

  /// The compiled widget shown because nothing was ready by the deadline.
  bool _showDeadlineFallback = false;
  static const RestagePaywallError _deadlineFallbackError = RestagePaywallError(
    code: RestageErrorCodes.deliveryUnavailable,
    message: 'No content was ready by the render deadline.',
  );
  DateTime? _mountedAt;
  bool _viewedFired = false;
  final Expando<bool> _viewedPresentations =
      Expando<bool>('viewed paywall presentations');
  bool _dismissedFired = false;
  late final RootAnalyticsAnonymousContext _anonymousAnalyticsOwner;

  /// The server-assigned published version of the last successfully-resolved
  /// variant. Null for bundled or custom resolutions.
  int? _resolvedPaywallPublishedVersion;

  /// This surface's live-refresh participation handle, registered at mount and
  /// unregistered at dispose. Null until [initState] registers it.
  SurfaceRefreshHandle? _refreshHandle;

  /// True once any authored event has been dispatched from the rendered
  /// content (a tap or input). Deliberately broad: any interaction
  /// makes the surface dirty for the rest of this mount so a live swap never
  /// pulls the rug from under a user who has started engaging.
  bool _userInteracted = false;

  /// The anonymous-identity generation that selected the rendered hosted
  /// artifact. A later generation cannot replace it within this presentation.
  SurfaceAssignmentResolutionLease? _renderedAssignmentLease;

  /// Rendered-content identity of the currently visible blob. This is separate
  /// from publication attribution, which continues to use the published
  /// revision when one exists.
  String? _renderedSurfaceVersion;

  /// The hosted flow controller when the resolved payload is flow-shaped (a
  /// lowered navigation paywall); null for a single-blob paywall.
  RestageFlowController<void>? _flowController;
  FirstPaintLeaseTransaction? _flowTransaction;
  int? _flowEpoch;
  final Map<RestageFlowController<void>, RootAnalyticsPresentation>
      _flowPresentations =
      <RestageFlowController<void>, RootAnalyticsPresentation>{};

  /// Each exact flow root owns its own Measurement session, including every
  /// screen and sub-flow it reaches. A refresh candidate remains separate until
  /// its host transaction promotes it, so a rollback cannot contaminate the
  /// retained presentation's session.
  final Set<RestageFlowController<void>> _measurementOwnedFlowControllers =
      <RestageFlowController<void>>{};
  final Map<RestageFlowController<void>, MeasurementHostSessionController>
      _flowMeasurementSessions =
      <RestageFlowController<void>, MeasurementHostSessionController>{};
  final Map<RestageFlowController<void>, MountAttributionSnapshotV1>
      _flowMountAttributions = {};
  Object? _fallbackAttributionIdentity;
  MountAttributionSnapshotV1? _fallbackMountAttribution;
  RestageFlowController<void>? _activeFlowMeasurementController;
  final Set<RestageFlowController<void>> _terminalMeasurementControllers = {};

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
  // instance every build), but ColorScheme / IconThemeData / TextStyle /
  // TextTheme each do — and they are exactly populateThemeData's inputs, so
  // keep the two in sync.
  ColorScheme? _lastThemeColorScheme;
  IconThemeData? _lastThemeIconTheme;
  TextStyle? _lastThemeTextStyle;
  TextTheme? _lastThemeTextTheme;
  MediaQueryData? _lastDeviceMediaQuery;
  ContextSnapshot? _context;

  void _refreshContext() {
    final raw = widget._context;
    _context = raw == null ? null : ContextSnapshot.of(raw, previous: _context);
  }

  @override
  void initState() {
    super.initState();
    _refreshContext();
    _anonymousAnalyticsOwner = RootAnalyticsAnonymousContext(
      surface: Surface.paywall.wireName,
      surfaceId: widget.id,
    );
    _mountedAt = DateTime.now();
    _renderDeadline = RenderDeadline.start(Restage.renderDeadline);
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
        surfaceType: Surface.paywall.wireName,
        slug: widget.id,
      ),
      triggers: Restage.effectiveLiveRefreshTriggers(
        widget.id,
        widgetOverride: widget.liveRefresh,
      ),
      canSwap: _canSwap,
      refresh: _refresh,
      renderedVersion: () => _resolvedPaywallPublishedVersion,
      stampable: widget.placementBinding == null &&
          widget.resolver == null &&
          Restage.activeRpcClient != null,
      localValidity: widget.placementBinding == null
          ? null
          : () => _renderedPlacementAdmission()?.isCurrent ?? true,
      localBoundary: () => _renderedPlacementAdmission()?.nextBoundary,
      invalidateLocal: _invalidateLocalPlacement,
      placementState: () => _renderedPlacementAdmission() == null
          ? placementFallbackFor(_placementResolver)?.refreshState
          : _renderedPlacementAdmission()?.refreshState,
      placementWatch: () => _renderedPlacementAdmission() == null
          ? placementFallbackFor(_placementResolver)?.watch
          : _renderedPlacementAdmission()?.decision.watch,
      renderedSurface: () =>
          _renderedPlacementAdmission()?.renderedSurface ??
          SurfaceRef(surfaceType: Surface.paywall.wireName, slug: widget.id),
      invalidatePlacement: () async {
        final accepted = _renderedPlacementAdmission();
        await accepted?.invalidateCache();
      },
      probePlacement: (rendered) => probeRenderedPlacement(
          _renderedPlacementAdmission(), _placementResolver, rendered),
    );
    _refreshHandle = handle;
    SurfaceRefreshRegistry.instance.register(handle);
  }

  /// The swap-safety gate. A surface is safe to live-swap only when the user
  /// has not interacted, the render is not
  /// experiment-assigned, and any hosted flow is pristine and idle.
  bool _payloadPresentationIsCurrent(
    ResolvedPaywallPayload payload,
    FlowMountRevalidationBoundary boundary,
  ) =>
      (payload.assignmentLease?.isCurrent ?? true) &&
      (placementAdmissionFor(payload)?.isCurrent ?? true) &&
      payload.revalidateHostedPresentation(boundary);

  bool _controllerPresentationIsCurrent(
    RestageFlowController<void>? controller,
    FlowMountRevalidationBoundary boundary,
  ) {
    final resolver = controller?.resolver;
    return resolver is! _PreResolvedFlowResolver ||
        resolver.revalidate(boundary);
  }

  PlacementDeliveryAdmission? _renderedPlacementAdmission() {
    final blob = _blobPresentation;
    if (blob != null) return placementAdmissionFor(blob.payload.variant);
    final resolver = _flowController?.resolver;
    if (resolver is _PreResolvedFlowResolver) {
      return placementAdmissionFor(resolver._payload.flow);
    }
    return null;
  }

  Future<void> _invalidateLocalPlacement() async {
    if (!mounted || !_canSwap()) return;
    final resolver = _placementResolver;
    if (resolver is! PlacementPaywallResolver) return;
    final original = await resolver.original();
    if (!mounted || !_canSwap()) return;
    if (original != null) {
      await _presentPayload(original,
          stopwatch: Stopwatch()..start(),
          epoch: ++_loadEpoch,
          isRefresh: true);
    } else if (widget.fallbackBuilder != null) {
      final blob = _blobPresentation;
      final flow = _flowController;
      setState(() {
        _blobPresentation = null;
        _flowController = null;
        _flowTransaction = null;
        _showDeadlineFallback = true;
      });
      if (blob != null) _disposeBlobStageAfterDetach(blob);
      if (flow != null) _disposeFlowControllerAfterDetach(flow);
    }
  }

  bool _canSwap() =>
      !_userInteracted &&
      !(_renderedPlacementAdmission()?.isAssigned ?? false) &&
      (_renderedAssignmentLease?.isCurrent ?? true) &&
      _controllerPresentationIsCurrent(
        _flowController,
        FlowMountRevalidationBoundary.pendingPromotion,
      ) &&
      !(_flowController?.hasUserContributedState ?? false) &&
      !(_flowController?.isBusy ?? false);

  /// Re-resolve this surface in place. Never throws into the widget — a failed
  /// refresh keeps the current render (staleness is never an error state).
  Future<void> _refresh() async {
    // Nothing has rendered yet: the in-flight mount fetch is already
    // fresh-first, so a refresh would be redundant (and could race it).
    // A settled load error has no fetch in flight and may refresh.
    if (_blobPresentation == null &&
        !(_flowTransaction?.isCommitted ?? false) &&
        !_showDeadlineFallback &&
        _error == null) {
      return;
    }
    await _load(isRefresh: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Publish the host theme into `data.theme.*` — once at mount, then on
    // every ambient-theme change. Reading Theme / DefaultTextStyle here
    // registers the dependency, so this re-fires when either changes.
    // `themeChanged` gates the theme republish only (an unrelated dependency
    // change, or a fresh-but-equal ThemeData instance, must not re-publish
    // unchanged theme data).
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final iconTheme = theme.iconTheme;
    final defaultTextStyle = DefaultTextStyle.of(context).style;
    final textTheme = theme.textTheme;
    final themeChanged = colorScheme != _lastThemeColorScheme ||
        iconTheme != _lastThemeIconTheme ||
        defaultTextStyle != _lastThemeTextStyle ||
        textTheme != _lastThemeTextTheme;
    if (themeChanged) {
      _lastThemeColorScheme = colorScheme;
      _lastThemeIconTheme = iconTheme;
      _lastThemeTextStyle = defaultTextStyle;
      _lastThemeTextTheme = textTheme;
    }
    // Republish `data.device.*` on a rotation or resize, not on every
    // unrelated MediaQuery change.
    final mediaQuery = MediaQuery.maybeOf(context);
    final deviceChanged =
        mediaQuery != null && !_publishesSameDevice(mediaQuery);
    if (deviceChanged) _lastDeviceMediaQuery = mediaQuery;
    for (final stage in <_BlobStage?>[
      _blobPresentation,
      _pendingBlobStage,
    ]) {
      if (stage == null) continue;
      if (themeChanged) {
        populateThemeData(
          stage.data,
          colorScheme: colorScheme,
          iconTheme: iconTheme,
          defaultTextStyle: defaultTextStyle,
          textTheme: textTheme,
        );
      }
      if (deviceChanged) {
        populateDeviceData(
          stage.data,
          locale: widget.locale ?? const Locale('en'),
          mediaQuery: mediaQuery,
          platform: currentDevicePlatform(),
        );
      }
    }
  }

  /// Whether [mediaQuery] would publish the same `data.device.*` values as the
  /// last publish.
  bool _publishesSameDevice(MediaQueryData mediaQuery) {
    final last = _lastDeviceMediaQuery;
    return last != null &&
        last.size == mediaQuery.size &&
        last.devicePixelRatio == mediaQuery.devicePixelRatio &&
        last.padding == mediaQuery.padding &&
        last.viewPadding == mediaQuery.viewPadding;
  }

  @override
  void didUpdateWidget(RestagePaywall oldWidget) {
    super.didUpdateWidget(oldWidget);
    _refreshContext();
    if (!(oldWidget.placementBinding
            ?.sameDeclarationAs(widget.placementBinding) ??
        widget.placementBinding == null)) {
      unawaited(_load(announceLoadStarted: false));
    }
    for (final stage in <_BlobStage?>[
      _blobPresentation,
      _pendingBlobStage,
    ]) {
      stage?.contextPublisher.publishSnapshot(_context);
    }
  }

  /// Fire [event] on both the per-widget [RestagePaywall.onEvent] callback
  /// and the app-wide [Restage.events] stream.
  ///
  /// The global stream is unconditional: events fired after this widget
  /// unmounts still reach app-wide listeners. The per-paywall
  /// callback is mounted-guarded so the host doesn't receive callbacks
  /// for a widget that no longer exists.
  /// The presented-content arbiter: a live flow wins, else the blob. Both
  /// presentation-derived accessors below branch on this one decision.
  bool get _flowIsPresented => _flowController != null;

  RootAnalyticsPresentation? get _activeAnalyticsPresentation {
    if (_flowIsPresented) return _flowPresentations[_flowController];
    return _blobPresentation?.analyticsPresentation;
  }

  void _fireEvent(
    RestageEvent event, {
    RootAnalyticsContextSource? attribution,
  }) {
    if (event is PaywallCustomEvent) {
      final flow = _flowController;
      final stage = _blobPresentation;
      MeasurementHostSessionController? session;
      if (flow != null) {
        if (_flowTransaction?.isPaintAcknowledged ?? false) {
          session = _flowMeasurementSessions[flow];
        }
      } else if (stage != null && stage.transaction.isPaintAcknowledged) {
        session = stage.measurementSession;
      }
      if (session != null) {
        attachPurchaseExposure(event, prepare: session.preparePurchaseExposure);
      }
    }
    final source =
        attribution ?? _activeAnalyticsPresentation ?? _anonymousAnalyticsOwner;
    void dispatch() {
      source.runWithEventContext(() => Restage.fireEvent(event));
      if (mounted) widget.onEvent?.call(event);
    }

    final mountContext =
        MountAttributionEventContext.current ?? _activeMountEventContext;
    if (mountContext == null) {
      dispatch();
    } else {
      mountContext.run(dispatch);
    }
  }

  MountAttributionEventContext? get _activeMountEventContext {
    final controller = _flowController;
    if (controller != null) {
      final snapshot = _flowMountAttributions[controller];
      return snapshot == null
          ? null
          : MountAttributionEventContext(
              snapshot: snapshot,
              isCurrent: () =>
                  mounted &&
                  identical(_flowController, controller) &&
                  (_flowTransaction?.isPaintAcknowledged ?? false));
    }
    final stage = _blobPresentation;
    final snapshot = stage?.mountAttribution;
    return stage == null || snapshot == null
        ? null
        : MountAttributionEventContext(
            snapshot: snapshot,
            isCurrent: () =>
                _isBlobEventStageCurrent(stage) &&
                stage.transaction.isPaintAcknowledged);
  }

  bool _isPagerBlobStageCurrent(_BlobStage stage) {
    return mounted &&
        identical(_blobPresentation, stage) &&
        stage.transaction.isCommitted &&
        stage.analyticsPresentation.isActive;
  }

  RestagePagerEventSink _pagerSinkForBlobStage(_BlobStage stage) {
    return RestagePagerEventSink(
      stageToken: stage,
      isCurrent: (token) =>
          identical(token, stage) && _isPagerBlobStageCurrent(stage),
      onPageChanged: (pageIndex, pageCount) {
        if (!_isPagerBlobStageCurrent(stage)) return;
        _fireEvent(
          PagerPageChanged(pageIndex: pageIndex, pageCount: pageCount),
          attribution: stage.analyticsPresentation,
        );
      },
    );
  }

  bool _isPagerFlowStageCurrent(
    RestageFlowController<void> controller,
    FirstPaintLeaseTransaction? transaction,
    RootAnalyticsPresentation presentation,
  ) {
    return mounted &&
        identical(_flowController, controller) &&
        identical(_flowTransaction, transaction) &&
        identical(_flowPresentations[controller], presentation) &&
        (transaction == null || transaction.isCommitted) &&
        presentation.isActive;
  }

  RestagePagerEventSink _pagerSinkForFlowStage(
    RestageFlowController<void> controller,
    FirstPaintLeaseTransaction? transaction,
    RootAnalyticsPresentation presentation,
  ) {
    return RestagePagerEventSink(
      stageToken: controller,
      isCurrent: (token) =>
          identical(token, controller) &&
          _isPagerFlowStageCurrent(controller, transaction, presentation),
      onPageChanged: (pageIndex, pageCount) {
        if (!_isPagerFlowStageCurrent(controller, transaction, presentation)) {
          return;
        }
        _fireEvent(
          PagerPageChanged(pageIndex: pageIndex, pageCount: pageCount),
          attribution: presentation,
        );
      },
    );
  }

  /// Fire `PaywallDismissed` exactly once per mount, regardless of which
  /// path triggered the dismiss (controller dismiss + dispose race).
  void _fireDismissed(DismissReason reason) {
    if (_dismissedFired) return;
    _dismissedFired = true;
    final owner = _activeFlowMeasurementController;
    if (owner != null && !_terminalMeasurementControllers.contains(owner)) {
      _flowMeasurementSessions[owner]?.recordSurfaceEnd();
    }
    _blobPresentation?.measurementSession.recordSurfaceEnd();
    _fireEvent(PaywallDismissed(
      paywallId: widget.id,
      reason: reason,
      timeOnPaywall: _mountedAt == null
          ? Duration.zero
          : DateTime.now().difference(_mountedAt!),
    ));
  }

  SurfaceDeliveryObservationCell _presentationObservations() =>
      _observationCell ??= SurfaceDeliveryObservationCell(
        () => readSurfaceDeliveryObservations(
          shortestLogicalSide:
              mounted ? requestingViewShortestLogicalSide(context) : null,
        ),
      );

  VariantResolver? _placementResolver;
  PlacementMountBinding? _capturedBinding;
  int _placementGeneration = -1;
  late final _placementDiscovery = PlacementHostDiscovery(
      configurationGeneration: () => Restage.configurationGeneration,
      discovery: () => Restage.placementDiscovery);

  VariantResolver _resolver() {
    final original = widget.resolver ?? Restage.defaultResolver;
    final binding = widget.placementBinding;
    final declaration = _placementDiscovery.capture(binding, widget, context);
    final registry = Restage.placementRegistry;
    if (widget.resolver == null &&
        Restage.placementPaywallsEnabled &&
        (binding?.isExplicit ?? false) &&
        registry == null) {
      return const UnavailablePlacementPaywallResolver();
    }
    if (widget.resolver != null ||
        !Restage.placementPaywallsEnabled ||
        binding == null ||
        registry == null) {
      return original;
    }
    if (_placementResolver == null ||
        !binding.sameDeclarationAs(_capturedBinding) ||
        _placementGeneration != Restage.configurationGeneration) {
      _capturedBinding = binding;
      _placementGeneration = Restage.configurationGeneration;
      _placementResolver = PlacementPaywallResolver(
          registry: registry,
          declaration: declaration!,
          id: widget.id,
          originalResolver: const AssetVariantResolver())
        ..onFallbackChanged = () {
          if (_refreshHandle case final handle?) {
            SurfaceRefreshRegistry.instance.acceptedPlacementChanged(handle);
          }
        };
    }
    return _placementResolver!;
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
    final resolver = _resolver();
    try {
      final payload = await withSurfaceDeliveryObservations(
        cell: _presentationObservations(),
        resolve: () => isRefresh
            ? _resolveStablePayload(resolver, epoch)
            : _raceInitialPayload(resolver, epoch, stopwatch),
      );
      if (payload == null) return;
      await _presentPayload(
        payload,
        stopwatch: stopwatch,
        epoch: epoch,
        isRefresh: isRefresh,
      );
    } on RestagePaywallError catch (e) {
      if (!mounted || epoch != _loadEpoch) return;
      // A failed refresh keeps the current render and stays silent.
      if (isRefresh) return;
      await _finishInitialLoadFailure(e, stopwatch, epoch);
    } catch (e, st) {
      if (!mounted || epoch != _loadEpoch) return;
      // A failed refresh keeps the current render and stays silent.
      if (isRefresh) return;
      _reportUnexpectedLoadFailure(e, st);
      await _finishInitialLoadFailure(
        _unexpectedLoadError(e, st),
        stopwatch,
        epoch,
      );
    }
  }

  /// Races fresh content against local candidates until the render deadline.
  ///
  /// Returns null when the mount shows its compiled widget or keeps waiting.
  Future<ResolvedPaywallPayload?> _raceInitialPayload(
    VariantResolver resolver,
    int epoch,
    Stopwatch stopwatch,
  ) async {
    final raced = racedResolverOf<ResolvedPaywallPayload>(resolver);
    final key = raced == null
        ? null
        : Restage.storeKeyFor(PaywallRef(widget.id), resolver: resolver);
    void report(ResolvedPaywallPayload? rendered) {
      if (raced != null) reportRaceWinner(raced, key!, rendered);
    }

    late final Future<ResolvedPaywallPayload?> freshFuture;
    final outcome = await withPaywallPresentationGuard(
      guard: () => mounted && epoch == _loadEpoch,
      resolve: () => raceSurface<ResolvedPaywallPayload>(
        deadline: _renderDeadline,
        fresh: () => freshFuture = raced == null
            ? _resolveStablePayload(resolver, epoch)
            : raced.fresh(
                key!,
                sendAssignmentKey: true,
                keyDeadline: _renderDeadline.reached,
              ),
        bestLocal:
            raced == null ? () async => null : () => raced.bestLocal(key!),
        onLateFresh: (payload) =>
            _presentLateFresh(payload, epoch, stopwatch, report),
      ),
    );
    if (!mounted || epoch != _loadEpoch) {
      outcome.value?.abandonHostedLastGood();
      return null;
    }
    switch (outcome) {
      case RaceFresh(:final value) || RaceLocal(:final value):
        report(value);
        return value;
      case RaceNone(freshPending: true):
        if (widget.fallbackBuilder != null && !_viewedFired) {
          report(null);
          setState(() => _showDeadlineFallback = true);
        } else {
          // Nothing to show yet: the mount settles on fresh's outcome.
          unawaited(freshFuture.then(
            (payload) {
              if (payload == null) {
                _failLate(null, null, epoch, stopwatch, report);
              }
            },
            onError: (Object error, StackTrace stack) =>
                _failLate(error, stack, epoch, stopwatch, report),
          ));
        }
        return null;
      case RaceNone(:final freshError):
        report(null);
        if (freshError != null) throw freshError;
        throw RestagePaywallError(
          code: RestageErrorCodes.deliveryUnavailable,
          message: 'No content is available for ${widget.id}.',
        );
    }
  }

  /// A mount that showed nothing at the deadline fails once fresh fails.
  void _failLate(
    Object? error,
    StackTrace? stack,
    int epoch,
    Stopwatch stopwatch,
    void Function(ResolvedPaywallPayload?) report,
  ) {
    if (!mounted || epoch != _loadEpoch || !_nothingShown) return;
    report(null);
    final RestagePaywallError failure;
    if (error == null) {
      failure = RestagePaywallError(
        code: RestageErrorCodes.deliveryUnavailable,
        message: 'No content is available for ${widget.id}.',
      );
    } else if (error is RestagePaywallError) {
      failure = error;
    } else {
      _reportUnexpectedLoadFailure(error, stack ?? StackTrace.current);
      failure = _unexpectedLoadError(error, stack ?? StackTrace.current);
    }
    unawaited(_finishInitialLoadFailure(failure, stopwatch, epoch));
  }

  bool get _nothingShown =>
      _blobPresentation == null &&
      _pendingBlobStage == null &&
      _flowController == null &&
      _error == null &&
      !_showDeadlineFallback;

  /// Fresh content accepted after the mount already settled.
  void _presentLateFresh(
    ResolvedPaywallPayload payload,
    int epoch,
    Stopwatch stopwatch,
    void Function(ResolvedPaywallPayload?) report,
  ) {
    if (!mounted || epoch != _loadEpoch) {
      payload.abandonHostedLastGood();
      return;
    }
    if (_nothingShown) {
      _lateReports[payload] = LateRenderReport(() => report(payload));
      unawaited(_presentGuarded(payload, stopwatch, epoch, isRefresh: false));
      return;
    }
    final liveRefresh = Restage.effectiveLiveRefreshTriggers(
      widget.id,
      widgetOverride: widget.liveRefresh,
    ).isNotEmpty;
    // Assigned content arriving after the mount settled is kept for the next
    // mount; showing it now would expose an arm the mount did not wait for.
    if (!liveRefresh ||
        _error != null ||
        !_canSwap() ||
        _carriesAssignment(payload)) {
      payload.abandonHostedLastGood();
      return;
    }
    _lateReports[payload] = LateRenderReport(() => report(payload));
    unawaited(
      _presentGuarded(payload, stopwatch, ++_loadEpoch, isRefresh: true),
    );
  }

  static bool _carriesAssignment(ResolvedPaywallPayload payload) {
    final owner = switch (payload) {
      BlobPaywallPayload(:final variant) => variant,
      FlowPaywallPayload(:final flow) => flow,
    };
    return payload.hasHostedExperimentAuthority ||
        measurementExperimentAssignmentFor(owner) != null ||
        (placementAdmissionFor(owner)?.isAssigned ?? false);
  }

  Future<void> _presentGuarded(
    ResolvedPaywallPayload payload,
    Stopwatch stopwatch,
    int epoch, {
    required bool isRefresh,
  }) async {
    try {
      await _presentPayload(
        payload,
        stopwatch: stopwatch,
        epoch: epoch,
        isRefresh: isRefresh,
      );
    } on RestagePaywallError catch (e) {
      if (!mounted || epoch != _loadEpoch || isRefresh) return;
      await _finishInitialLoadFailure(e, stopwatch, epoch);
    } catch (e, st) {
      if (!mounted || epoch != _loadEpoch || isRefresh) return;
      _reportUnexpectedLoadFailure(e, st);
      await _finishInitialLoadFailure(
        _unexpectedLoadError(e, st),
        stopwatch,
        epoch,
      );
    }
  }

  Future<void> _presentPayload(
    ResolvedPaywallPayload payload, {
    required Stopwatch stopwatch,
    required int epoch,
    required bool isRefresh,
  }) async {
    {
      // This check is intentionally the first work after the await. A newer
      // load supersedes this result, while an actor boundary re-enters the same
      // resolver ladder before payload shape, decode, or host state can move.
      if (!mounted || epoch != _loadEpoch) return;
      if (!_payloadPresentationIsCurrent(
        payload,
        FlowMountRevalidationBoundary.pendingPromotion,
      )) {
        if (!isRefresh &&
            payload is FlowPaywallPayload &&
            payload.canRetryHostedPresentation) {
          payload.abandonHostedCandidate();
          unawaited(
            _retryInitialFlowPayload(payload, stopwatch, epoch),
          );
          return;
        }
        payload.abandonHostedLastGood();
        _retryLoadAfterRejectedLease(epoch, isRefresh: isRefresh);
        return;
      }
      // A flow-shaped payload (a lowered navigation paywall) is hosted by the
      // flow runtime. The blob path below uses the same event demux boundary.
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
        markSurfaceDeliveryRenderFailed(
          variant,
          reason: SurfaceDeliveryReceiptReason.decodeFailed,
        );
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
        // User interaction, flow activity, or an assignment change during the
        // async resolve makes the surface unsafe; abort the swap (defer =
        // drop — the next remount is fresh-first anyway).
        if (!_canSwap()) {
          payload.abandonHostedLastGood();
          return;
        }
      }
      await _stageBlob(
        payload,
        library,
        epoch: epoch,
        isRefresh: isRefresh,
        loadDuration: stopwatch.elapsed,
        cacheHit: variant.cacheHit,
      );
    }
  }

  Future<void> _finishInitialLoadFailure(
    RestagePaywallError error,
    Stopwatch stopwatch,
    int epoch,
  ) async {
    if (!mounted || epoch != _loadEpoch) return;
    setState(() => _setInitialError(error));
    _fireEvent(PaywallLoadFailed(
      paywallId: widget.id,
      errorCode: error.code,
      message: error.message,
      retryable: error.retryable,
    ));
  }

  void _setInitialError(RestagePaywallError error) {
    _error = error;
    _useAuthoredFallback = widget.fallbackBuilder != null && !_viewedFired;
  }

  void _reportUnexpectedLoadFailure(Object error, StackTrace stackTrace) {
    // Surface the original exception + stack to the developer console so
    // a buggy custom resolver doesn't get hidden behind a generic
    // "unknown" error code in their crash reports.
    FlutterError.reportError(FlutterErrorDetails(
      exception: error,
      stack: stackTrace,
      library: 'restage',
      context: ErrorDescription('resolving + decoding paywall ${widget.id}'),
    ));
  }

  RestagePaywallError _unexpectedLoadError(
    Object error,
    StackTrace stackTrace,
  ) =>
      RestagePaywallError(
        code: RestageErrorCodes.unknown,
        message: 'Unexpected: $error',
        cause: error,
        stackTrace: stackTrace,
      );

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
  /// currently rendered, so a live refresh should skip the swap.
  bool _isUnchangedBlob(ResolvedVariant variant) {
    final accepted = _renderedPlacementAdmission();
    final candidate = placementAdmissionFor(variant);
    if (accepted != null || candidate != null) {
      return accepted?.matchesDecision(candidate) ?? false;
    }
    return _renderedSurfaceVersion == variant.surfaceVersion;
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
    final accepted = _renderedPlacementAdmission();
    final candidate = placementAdmissionFor(payload.flow);
    if ((accepted != null || candidate != null)
        ? (accepted?.matchesDecision(candidate) ?? false)
        : (freshVersion != null &&
            renderedVersion != null &&
            freshVersion == renderedVersion)) {
      payload.abandonHostedLastGood();
      return; // unchanged — nothing to re-host
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
    final analyticsPresentation = RootAnalyticsRuntime.createPresentation(
      surface: Surface.paywall.wireName,
      surfaceId: widget.id,
    );
    _flowPresentations[pending] = analyticsPresentation;
    late final FirstPaintLeaseTransaction transaction;
    transaction = FirstPaintLeaseTransaction(
      isReady: () => pending.currentScreenEntryId != null,
      isInvalidatedByIdentityReset: () =>
          analyticsPresentation.isInvalidatedByIdentityReset ||
          !_payloadPresentationIsCurrent(
            payload,
            FlowMountRevalidationBoundary.firstPaint,
          ),
      canCommit: () =>
          _canCommitPendingFlow(
            pending,
            payload,
            epoch,
            transaction,
          ) &&
          !analyticsPresentation.isInvalidatedByIdentityReset,
      commit: () {
        _commitPendingFlowAtPaint(
          pending,
          payload,
          epoch,
          transaction,
        );
        _stagePaywallAnalyticsPresentation(analyticsPresentation, payload);
      },
      onPainted: () {
        _placementDiscovery.markPainted();
        if (_refreshHandle case final handle?) {
          SurfaceRefreshRegistry.instance.acceptedPlacementChanged(handle);
        }
        surfaceDeliveryReceiptFor(placementResolvedLeaf(payload))
            ?.paintedSinceOpened();
        final oldFlow = _flowToDisposeAfterPromotion;
        if (oldFlow != null) {
          _finalizeMeasurementSessionForFlow(oldFlow);
        }
        final oldBlob = _blobToDisposeAfterPromotion;
        if (oldBlob != null) {
          unawaited(oldBlob.measurementSession.teardown());
        }
        _activateFlowMeasurementOwner(pending);
        analyticsPresentation.activate();
        _publishRenderedPayload(payload);
      },
      afterCommit: () => _finishPendingFlowPaintCommit(pending),
      afterRejection: () => _rejectPendingFlowTransaction(
        pending,
        payload,
        epoch,
      ),
      onAbandon: () {
        analyticsPresentation.abandon();
        payload.abandonHostedLastGood();
      },
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
      if (error.reason == 'render_failed') _forgetStoredCandidate();
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
      _payloadPresentationIsCurrent(
        payload,
        FlowMountRevalidationBoundary.firstPaint,
      ) &&
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
    _renderedAssignmentLease = payload.assignmentLease;
    _renderedSurfaceVersion = null;
  }

  /// Publishes both resolver and widget last-good only after descendant paint
  /// returned normally for the exact authority transaction.
  void _publishRenderedPayload(ResolvedPaywallPayload payload) {
    payload.publishHostedLastGood();
    _lateReports[payload]?.painted();
  }

  /// Late content reported only once it paints.
  final Expando<LateRenderReport> _lateReports =
      Expando<LateRenderReport>('late paywall reports');

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
    final analyticsInvalidated =
        _flowPresentations[pending]?.isInvalidatedByIdentityReset ?? false;
    final shouldRetry = epoch == _loadEpoch &&
        (analyticsInvalidated ||
            !_payloadPresentationIsCurrent(
              payload,
              FlowMountRevalidationBoundary.firstPaint,
            ));
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
  Future<ResolvedPaywallPayload> _resolvePayload(
    VariantResolver resolver,
    int epoch,
  ) {
    if (resolver is PresentationPaywallResolver) {
      return withPaywallPresentationGuard(
        guard: () => mounted && epoch == _loadEpoch,
        resolve: () => (resolver as PresentationPaywallResolver)
            .resolvePayloadForPresentation(
          widget.id,
          placementId: widget.placementId,
          locale: widget.locale,
        ),
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
        final payload = await _resolvePayload(resolver, epoch);
        if (!mounted || epoch != _loadEpoch) {
          payload.abandonHostedLastGood();
          return null;
        }
        if (_payloadPresentationIsCurrent(
          payload,
          FlowMountRevalidationBoundary.pendingPromotion,
        )) {
          return payload;
        }
        if (payload is FlowPaywallPayload &&
            payload.canRetryHostedPresentation) {
          payload.abandonHostedCandidate();
          final retained =
              await _resolveRetainedInitialFlowPayload(payload, epoch);
          // This is intentionally the first work after the await. The caller
          // performs the next presentation revalidation without recreating the
          // strict authority or its frozen baseline.
          if (!mounted || epoch != _loadEpoch) {
            retained?.abandonHostedLastGood();
            payload.disposeHostedPresentation();
            return null;
          }
          return retained;
        }
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
  /// The flow's onboarding-shaped lifecycle is suppressed in favor of paywall
  /// lifecycle keyed on [RestagePaywall.id].
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
            !_payloadPresentationIsCurrent(
              payload,
              FlowMountRevalidationBoundary.firstPaint,
            )) {
          _retryStaleInitialFlow(
            controller,
            payload,
            epoch,
            transaction,
            stopwatch,
          );
          return;
        }
        _removeInitialFlowReadinessListener(controller);
        _handleFlowComplete(controller);
      },
      onUnavailable: (error) {
        if (!_flowLoadAnnounced &&
            !_payloadPresentationIsCurrent(
              payload,
              FlowMountRevalidationBoundary.firstPaint,
            )) {
          _retryStaleInitialFlow(
            controller,
            payload,
            epoch,
            transaction,
            stopwatch,
          );
          return;
        }
        _removeInitialFlowReadinessListener(controller);
        _handleFlowUnavailable(controller, error);
      },
    );
    final analyticsPresentation = RootAnalyticsRuntime.createPresentation(
      surface: Surface.paywall.wireName,
      surfaceId: widget.id,
    );
    _flowPresentations[controller] = analyticsPresentation;
    transaction = FirstPaintLeaseTransaction(
      isReady: () => controller.currentScreenEntryId != null,
      isInvalidatedByIdentityReset: () =>
          analyticsPresentation.isInvalidatedByIdentityReset ||
          !_payloadPresentationIsCurrent(
            payload,
            FlowMountRevalidationBoundary.firstPaint,
          ),
      canCommit: () =>
          _canCommitInitialFlow(
            controller,
            payload,
            epoch,
            transaction,
          ) &&
          !analyticsPresentation.isInvalidatedByIdentityReset,
      commit: () {
        _commitInitialFlowAtPaint(
          controller,
          payload,
          epoch,
          transaction,
        );
        _stagePaywallAnalyticsPresentation(analyticsPresentation, payload);
      },
      onPainted: () {
        _placementDiscovery.markPainted();
        if (_refreshHandle case final handle?) {
          SurfaceRefreshRegistry.instance.acceptedPlacementChanged(handle);
        }
        surfaceDeliveryReceiptFor(placementResolvedLeaf(payload))
            ?.paintedSinceOpened();
        if (_refreshHandle case final handle?) {
          SurfaceRefreshRegistry.instance.localValidityChanged(handle);
        }
        analyticsPresentation.activate();
        _publishRenderedPayload(payload);
        _activateFlowMeasurementOwner(controller);
      },
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
        stopwatch,
      ),
      onAbandon: () {
        analyticsPresentation.abandon();
        payload.abandonHostedCandidate();
      },
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
        if (!_payloadPresentationIsCurrent(
          payload,
          FlowMountRevalidationBoundary.firstPaint,
        )) {
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
      publishedVersion: payload.paywallPublishedVersion,
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
    Stopwatch stopwatch,
  ) {
    final analyticsInvalidated =
        _flowPresentations[controller]?.isInvalidatedByIdentityReset ?? false;
    if (!analyticsInvalidated &&
        _payloadPresentationIsCurrent(
          payload,
          FlowMountRevalidationBoundary.firstPaint,
        )) {
      return;
    }
    if (!mounted ||
        !identical(_flowController, controller) ||
        !identical(_flowTransaction, transaction) ||
        _flowEpoch != epoch ||
        epoch != _loadEpoch ||
        transaction.isCommitted) {
      return;
    }
    final resolver = controller.resolver;
    final preservesPresentation = resolver is _PreResolvedFlowResolver &&
        resolver.detachHostedPresentationForRetry();
    _removeInitialFlowReadinessListener(controller);
    _initialFlowIsStaged = false;
    transaction.supersede();
    _flowTransaction = null;
    _flowEpoch = null;
    setState(() => _flowController = null);
    if (preservesPresentation) {
      unawaited(_retryInitialFlowPayload(payload, stopwatch, epoch));
    } else {
      unawaited(_load(announceLoadStarted: false));
    }
    _disposeFlowControllerAfterDetach(controller);
  }

  Future<void> _retryInitialFlowPayload(
    FlowPaywallPayload rejectedPayload,
    Stopwatch stopwatch,
    int epoch,
  ) async {
    try {
      final next =
          await _resolveRetainedInitialFlowPayload(rejectedPayload, epoch);
      // This is intentionally the first work after the await. A widget
      // supersession or newer load epoch cannot stage or request later work.
      if (!mounted || epoch != _loadEpoch) {
        next?.abandonHostedLastGood();
        rejectedPayload.disposeHostedPresentation();
        return;
      }
      if (next != null) {
        _startFlow(next, stopwatch, epoch: epoch);
      }
    } on RestagePaywallError catch (error) {
      if (!mounted || epoch != _loadEpoch) return;
      await _finishInitialLoadFailure(error, stopwatch, epoch);
    } catch (error, stackTrace) {
      if (!mounted || epoch != _loadEpoch) return;
      _reportUnexpectedLoadFailure(error, stackTrace);
      await _finishInitialLoadFailure(
        _unexpectedLoadError(error, stackTrace),
        stopwatch,
        epoch,
      );
    }
  }

  Future<FlowPaywallPayload?> _resolveRetainedInitialFlowPayload(
    FlowPaywallPayload rejectedPayload,
    int epoch,
  ) async {
    var retainedPayload = rejectedPayload;
    while (mounted && epoch == _loadEpoch) {
      final FlowPaywallPayload? next;
      try {
        next = await retainedPayload.resolveNextHostedPresentation();
      } on Object {
        retainedPayload.disposeHostedPresentation();
        rethrow;
      }
      // This is intentionally the first work after the await. A widget
      // supersession or newer load epoch cannot stage or request later work.
      if (!mounted || epoch != _loadEpoch) {
        next?.abandonHostedLastGood();
        retainedPayload.disposeHostedPresentation();
        return null;
      }
      if (next == null) {
        retainedPayload.disposeHostedPresentation();
        throw RestagePaywallError(
          code: RestageErrorCodes.deliveryUnavailable,
          message: 'Strict flow retry ended without a renderable payload.',
        );
      }
      if (_payloadPresentationIsCurrent(
        next,
        FlowMountRevalidationBoundary.pendingPromotion,
      )) {
        return next;
      }
      next.abandonHostedCandidate();
      retainedPayload = next;
    }
    retainedPayload.disposeHostedPresentation();
    return null;
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
        _payloadPresentationIsCurrent(
          payload,
          FlowMountRevalidationBoundary.firstPaint,
        );
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
    _renderedAssignmentLease = payload.assignmentLease;
    _renderedSurfaceVersion = null;
  }

  void _stagePaywallAnalyticsPresentation(
    RootAnalyticsPresentation presentation,
    ResolvedPaywallPayload payload,
  ) {
    final attribution = switch (payload) {
      BlobPaywallPayload(:final variant) => (version: variant.surfaceVersion),
      FlowPaywallPayload(
        :final flow,
        :final paywallPublishedVersion,
      ) =>
        (
          version:
              (paywallPublishedVersion ?? flow.document.version).toString(),
        ),
    };
    presentation.stage(surfaceVersion: attribution.version);
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
    Stopwatch stopwatch,
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
    _retryStaleInitialFlow(
      controller,
      payload,
      epoch,
      transaction,
      stopwatch,
    );
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
    late final RestageFlowController<void> controller;
    controller = createHostMeasurementFlowController<void>(
      flow: OnboardingFlowRef<void>(
        id: document.flow,
        version: document.version,
        minClient: document.minClient,
        surface: Surface.paywall,
        deliveryMode: document.deliveryMode,
        decodeResult: (_) {},
      ),
      resolver: _PreResolvedFlowResolver(payload),
      actions: null,
      onEvent: onEvent,
      onComplete: onComplete,
      onUnavailable: onUnavailable,
      onMeasurementLifecycle: (channel, screenId) {
        if (channel == MeasurementOccurrenceChannelV1.completion) {
          _terminalMeasurementControllers.add(controller);
        } else if (channel == MeasurementOccurrenceChannelV1.skip) {
          // Suppress dismissal when this skip closes the host in its next
          // frame. A skip that leaves the flow mounted is not a root terminal.
          _terminalMeasurementControllers.add(controller);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!controller.isComplete) {
              _terminalMeasurementControllers.remove(controller);
            }
          });
          WidgetsBinding.instance.ensureVisualUpdate();
        } else if (channel == MeasurementOccurrenceChannelV1.presentation) {
          _terminalMeasurementControllers.remove(controller);
        }
        _flowMeasurementSessions[controller]
            ?.recordLifecycle(channel, screenId: screenId);
      },
      onRootResolved: (_) =>
          _openMeasurementSessionForFlow(controller, payload),
      sanitizeAndRecordEvent: (rawValue) =>
          _sanitizeAndRecordFlowEvent(controller, rawValue),
    );
    _measurementOwnedFlowControllers.add(controller);
    return controller;
  }

  /// Attaches the background Measurement session before installing a screen.
  /// Uses [payload]'s resolved provenance after root admission, preserving hosted
  /// precedence or bundled identity without rereading mutable controller state.
  Future<void> _openMeasurementSessionForFlow(
    RestageFlowController<void> controller,
    FlowPaywallPayload payload,
  ) async {
    final snapshot = captureMountAttribution(
        _placementDiscovery.declaration?.mount,
        resolved: payload);
    if (snapshot != null) _flowMountAttributions[controller] = snapshot;
    bindSurfaceDeliveryMountAttribution(payload, snapshot);
    final session = MeasurementHostSessionController.openDeferred(
      payload,
      mountAttribution: snapshot,
      presentationObservations: _observationCell?.read,
    );
    if (!_measurementOwnedFlowControllers.contains(controller)) {
      unawaited(session.teardown());
      return;
    }
    final previous = _flowMeasurementSessions[controller];
    if (previous != null && !identical(previous, session)) {
      unawaited(previous.teardown());
    }
    _flowMeasurementSessions[controller] = session;
  }

  /// Runs through the exact owning root session before the flow view invokes
  /// its paywall interceptor, controller transition table, or app callbacks.
  Object? _sanitizeAndRecordFlowEvent(
    RestageFlowController<void> controller,
    Object? rawValue,
  ) {
    final session = _flowMeasurementSessions[controller];
    if (session != null) return session.sanitizeAndRecordEvent(rawValue);
    return MeasurementEventSanitizer.sanitize(rawValue).businessValue;
  }

  void _activateFlowMeasurementOwner(RestageFlowController<void> controller) {
    if (!_measurementOwnedFlowControllers.contains(controller)) return;
    final previous = _activeFlowMeasurementController;
    if (previous != null && !identical(previous, controller)) {
      _finalizeMeasurementSessionForFlow(previous);
    }
    _activeFlowMeasurementController = controller;
  }

  void _finalizeMeasurementSessionForFlow(
    RestageFlowController<void> controller,
  ) {
    _terminalMeasurementControllers.remove(controller);
    final session = _flowMeasurementSessions.remove(controller);
    if (session != null) unawaited(session.teardown());
    if (identical(_activeFlowMeasurementController, controller)) {
      _activeFlowMeasurementController = null;
    }
  }

  /// Routes a screen-fired event for a flow-hosted paywall. Navigation events
  /// (the synthetic `restageNav<N>`, the reserved `back` / `skip`) flow through
  /// to the controller's graph. Other events are handled by the paywall demux
  /// and consumed, so a custom event is keyed to the paywall rather than the
  /// flow. Returns true when consumed.
  bool _interceptFlowScreenEvent(String name, Map<String, Object?> args) {
    if (_isFlowNavigationEvent(name)) return false;
    // Mirror the controller's own event gate. A stale event during a
    // transition or after the flow has ended is consumed rather than reaching
    // the graph.
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
    _announceFlowLoaded(
      stopwatch.elapsed,
      fromCache || payload.flow.cacheHit,
      publishedVersion: payload.paywallPublishedVersion,
    );
  }

  /// Announces the paywall-shaped load lifecycle for a flow-hosted paywall
  /// exactly once: `PaywallLoadCompleted` now + `PaywallViewed` after the first
  /// frame. Mirrors [_finishCommittedBlobStage]'s blob lifecycle, keyed on
  /// paywallId.
  void _announceFlowLoaded(
    Duration loadDuration,
    bool cacheHit, {
    required int? publishedVersion,
  }) {
    if (_flowLoadAnnounced || !mounted) return;
    _flowLoadAnnounced = true;
    final presentation = _activeAnalyticsPresentation;
    if (presentation == null) {
      _fireEvent(PaywallLoadCompleted(
        paywallId: widget.id,
        loadDuration: loadDuration,
        cacheHit: cacheHit,
      ));
      return;
    }
    _announceRenderedPaywall(
      presentation: presentation,
      loadDuration: loadDuration,
      cacheHit: cacheHit,
      publishedVersion: publishedVersion,
    );
  }

  void _announceRenderedPaywall({
    required RootAnalyticsPresentation presentation,
    required Duration loadDuration,
    required bool cacheHit,
    required int? publishedVersion,
  }) {
    presentation.captureDeferredContextOnActivation((attribution) {
      _fireEvent(
        PaywallLoadCompleted(
          paywallId: widget.id,
          loadDuration: loadDuration,
          cacheHit: cacheHit,
        ),
        attribution: attribution,
      );
      _schedulePaywallViewed(
        presentation: presentation,
        attribution: attribution,
        publishedVersion: publishedVersion,
      );
    });
  }

  /// Fires `PaywallViewed` exactly once in a post-frame callback after the first
  /// render. Shared by the blob lifecycle ([_finishCommittedBlobStage]) and the
  /// flow-hosted lifecycle ([_announceFlowLoaded]).
  void _schedulePaywallViewed({
    required RootAnalyticsPresentation presentation,
    required RootAnalyticsDeferredContext attribution,
    required int? publishedVersion,
  }) {
    final event = PaywallViewed(
      paywallId: widget.id,
      publishedVersion: publishedVersion,
    );
    void fire() {
      if (!mounted || _viewedPresentations[presentation] == true) return;
      _viewedPresentations[presentation] = true;
      _viewedFired = true;
      _fireEvent(event, attribution: attribution);
    }

    final debugScheduler = RootAnalyticsRuntime.debugPostFrameScheduler;
    if (debugScheduler != null) {
      debugScheduler(fire);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => fire());
    }
  }

  /// The flow reached its end state (the entry screen's skip/dismiss → end): the
  /// user backed out of the paywall. Surface a paywall dismiss keyed on
  /// paywallId — not an onboarding completion.
  void _handleFlowComplete(RestageFlowController<void> controller) {
    if (!mounted || !identical(_flowController, controller)) return;
    _finalizeMeasurementSessionForFlow(controller);
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
    if (error.reason == 'render_failed') _forgetStoredCandidate();
    _finalizeMeasurementSessionForFlow(controller);
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
      _setInitialError(err);
    });
    _disposeFlowControllerAfterDetach(controller);
    _fireEvent(PaywallLoadFailed(
      paywallId: widget.id,
      errorCode: err.code,
      message: err.message,
      retryable: false,
    ));
  }

  /// Stages a decoded blob in an isolated runtime. The current presentation
  /// stays mounted until this exact candidate commits at first paint.
  Future<bool> _stageBlob(
    BlobPaywallPayload payload,
    WidgetLibrary library, {
    required int epoch,
    required bool isRefresh,
    required Duration loadDuration,
    required bool cacheHit,
  }) async {
    final snapshot = captureMountAttribution(
        _placementDiscovery.declaration?.mount,
        resolved: payload);
    bindSurfaceDeliveryMountAttribution(payload, snapshot);
    final measurementSession = MeasurementHostSessionController.openDeferred(
      payload,
      mountAttribution: snapshot,
      presentationObservations: _observationCell?.read,
    );
    if (!mounted || epoch != _loadEpoch) {
      unawaited(measurementSession.teardown());
      payload.abandonHostedLastGood();
      return false;
    }
    final runtime = _createBlobRuntime()..update(_paywallLibrary, library);
    final data = DynamicContent();
    final analyticsPresentation = RootAnalyticsRuntime.createPresentation(
      surface: Surface.paywall.wireName,
      surfaceId: widget.id,
    );
    late final _BlobStage stage;
    final transaction = FirstPaintLeaseTransaction(
      isInvalidatedByIdentityReset: () =>
          analyticsPresentation.isInvalidatedByIdentityReset ||
          !(stage.payload.assignmentLease?.isCurrent ?? true),
      canCommit: () => _canCommitBlobStage(stage),
      commit: () {
        _commitBlobStage(stage);
        _stagePaywallAnalyticsPresentation(
          analyticsPresentation,
          payload,
        );
      },
      onPainted: () {
        _placementDiscovery.markPainted();
        if (_refreshHandle case final handle?) {
          SurfaceRefreshRegistry.instance.acceptedPlacementChanged(handle);
        }
        surfaceDeliveryReceiptFor(placementResolvedLeaf(payload))
            ?.paintedSinceOpened();
        final previousBlob = stage.previousBlob;
        if (previousBlob != null) {
          unawaited(previousBlob.measurementSession.teardown());
        }
        final previousFlow = stage.previousFlow;
        if (previousFlow != null) {
          _finalizeMeasurementSessionForFlow(previousFlow);
        }
        analyticsPresentation.activate();
        _publishRenderedPayload(payload);
      },
      afterCommit: () => _finishCommittedBlobStage(stage),
      afterRejection: () => _rejectBlobStage(stage),
      onAbandon: () {
        analyticsPresentation.abandon();
        payload.abandonHostedLastGood();
      },
    );
    stage = _BlobStage(
      payload: payload,
      runtime: runtime,
      data: data,
      sections: surfaceSectionsFor(payload.variant),
      epoch: epoch,
      isRefresh: isRefresh,
      loadDuration: loadDuration,
      cacheHit: cacheHit,
      transaction: transaction,
      analyticsPresentation: analyticsPresentation,
      measurementSession: measurementSession,
      mountAttribution: snapshot,
    );
    final eventLease = RestageTargetEventDispatchLease(
      isCurrent: () => _isBlobEventStageCurrent(stage),
    );
    stage.eventHandler = (name, args) {
      eventLease.invoke(() => _handleBlobRfwEvent(stage, name, args));
    };
    _populateBlobData(stage);

    final superseded = _pendingBlobStage;
    if (superseded != null && !superseded.transaction.isCommitted) {
      superseded.transaction.supersede();
      _disposeBlobStageAfterDetach(superseded);
    }
    _pendingBlobStage = stage;
    setState(() => _error = null);
    return true;
  }

  Runtime _createBlobRuntime() {
    final runtime = Runtime();
    InstalledWidgetLibraries.current.installInto(
      runtime,
      coreName: const LibraryName(<String>['restage', 'core']),
      materialName: const LibraryName(<String>['restage', 'material']),
      cupertinoName: const LibraryName(<String>['restage', 'cupertino']),
    );
    LibraryRuntimeRegistry.applyTo(runtime);
    installMeasurementRfwPresentationLibrary(runtime);
    return runtime;
  }

  void _populateBlobData(_BlobStage stage) {
    stage.contextPublisher.publishSnapshot(_context);
    final mq = MediaQuery.maybeOf(context);
    if (mq != null) {
      _lastDeviceMediaQuery = mq;
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
    final textTheme = _lastThemeTextTheme;
    if (colorScheme != null &&
        iconTheme != null &&
        textStyle != null &&
        textTheme != null) {
      populateThemeData(
        stage.data,
        colorScheme: colorScheme,
        iconTheme: iconTheme,
        defaultTextStyle: textStyle,
        textTheme: textTheme,
      );
    }
  }

  bool _canCommitBlobStage(_BlobStage stage) {
    if (!mounted ||
        !identical(_pendingBlobStage, stage) ||
        stage.epoch != _loadEpoch ||
        stage.analyticsPresentation.isInvalidatedByIdentityReset ||
        !(stage.payload.assignmentLease?.isCurrent ?? true)) {
      return false;
    }
    return !stage.isRefresh || _canSwap();
  }

  bool _isBlobEventStageCurrent(_BlobStage stage) =>
      mounted &&
      !stage._disposed &&
      identical(_blobPresentation, stage) &&
      stage.transaction.isCommitted;

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
    _renderedAssignmentLease = stage.payload.assignmentLease;
    _renderedSurfaceVersion = variant.surfaceVersion;
    if (_refreshHandle case final handle?) {
      SurfaceRefreshRegistry.instance.localValidityChanged(handle);
    }
  }

  void _finishCommittedBlobStage(_BlobStage stage) {
    if (!mounted || !stage.transaction.isCommitted) return;
    if (identical(_pendingBlobStage, stage)) {
      setState(() {
        _pendingBlobStage = null;
        _error = null;
      });
    }
    final variant = stage.payload.variant;
    _announceRenderedPaywall(
      presentation: stage.analyticsPresentation,
      loadDuration: stage.loadDuration,
      cacheHit: stage.cacheHit,
      publishedVersion: variant.paywallPublishedVersion,
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
        (stage.analyticsPresentation.isInvalidatedByIdentityReset ||
            !(stage.payload.assignmentLease?.isCurrent ?? true));
    setState(() => _pendingBlobStage = null);
    _disposeBlobStageAfterDetach(stage);
    if (shouldRetry) {
      _retryLoadAfterRejectedLease(
        stage.epoch,
        isRefresh: stage.isRefresh,
      );
    }
  }

  /// Drops this paywall's stored copy after a candidate failed to render, so
  /// the next mount falls back instead of rendering it again.
  void _forgetStoredCandidate() {
    final resolver = _resolver();
    final raced = racedResolverOf<ResolvedPaywallPayload>(resolver);
    if (raced == null) return;
    unawaited(raced.forgetStored(
      Restage.storeKeyFor(PaywallRef(widget.id), resolver: resolver),
    ));
  }

  void _handleBlobBuildFailure(_BlobStage stage, Object error) {
    _forgetStoredCandidate();
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
      cause: error,
    );
    setState(() {
      _pendingBlobStage = null;
      _setInitialError(failure);
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

  void _disposeFlowControllerAfterDetach(
    RestageFlowController<void> controller,
  ) {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _disposeFlowController(controller),
    );
  }

  void _disposeFlowController(RestageFlowController<void> controller) {
    _finalizeMeasurementSessionForFlow(controller);
    _measurementOwnedFlowControllers.remove(controller);
    _flowPresentations.remove(controller)?.dispose();
    _flowMountAttributions.remove(controller);
    final resolver = controller.resolver;
    if (resolver is _PreResolvedFlowResolver) {
      resolver.disposePresentation();
    }
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
    _placementDiscovery.dispose();
    _renderDeadline.cancel();
    if (_refreshHandle case final handle?) {
      SurfaceRefreshRegistry.instance.unregister(handle);
    }
    _refreshHandle = null;
    widget.controller?.detachInternal();
    // Fire dismissed before disposing the presentation that owns its context.
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
    for (final presentation in _flowPresentations.values) {
      presentation.dispose();
    }
    _flowPresentations.clear();
    _blobPresentation = null;
    _pendingBlobStage = null;
    _blobToDisposeAfterPromotion = null;
    _observationCell = null;
    super.dispose();
  }

  /// Translates RFW events into [RestageEvent]s.
  ///
  /// Reserved commerce event names are ignored. Other events remain available
  /// to host apps as [PaywallCustomEvent]s.
  void _handleRfwEvent(
    String name,
    Object? args, {
    MeasurementHostSessionController? measurementSession,
    RootAnalyticsContextSource? attribution,
  }) {
    if (isReservedCommerceEventName(name)) return;
    final businessArgs = measurementSession == null
        ? MeasurementEventSanitizer.sanitize(args).businessValue
        : measurementSession.sanitizeAndRecordEvent(args);
    // Any authored event from the rendered content marks the surface dirty for
    // the swap-safety gate. Deliberately broad, so a live swap never lands
    // under an engaged user. Theme and system changes use dependencies instead.
    _userInteracted = true;
    if (isMeasurementTapEventName(name)) return;
    final argsMap = businessArgs is Map<String, Object?>
        ? businessArgs
        : (businessArgs is Map
            ? businessArgs.cast<String, Object?>()
            : <String, Object?>{});
    final event = demuxRfwEvent(
      paywallId: widget.id,
      name: name,
      args: argsMap,
    );
    if (event != null) _fireEvent(event, attribution: attribution);
  }

  void _handleBlobRfwEvent(
    _BlobStage stage,
    String name,
    Object? args,
  ) {
    if (stage.local.intercept(name, args)) {
      _userInteracted = true;
      return;
    }
    args = withoutContextItemIndexes(args);
    _handleRfwEvent(
      name,
      args,
      measurementSession: stage.measurementSession,
      attribution: stage.analyticsPresentation,
    );
  }

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
      final error = _error!;
      final builder = widget.errorBuilder;
      final fallback = _useAuthoredFallback && widget.fallbackBuilder != null
          ? _buildAuthoredFallback(
              error,
              isCurrent: () =>
                  mounted && _useAuthoredFallback && identical(_error, error),
            )
          : builder == null
              ? const SizedBox.shrink()
              : builder(context, error);
      // A refreshed flow stages beside the fallback until it paints.
      final staged = _pendingFlowIsStaged ? _pendingFlowController : null;
      if (staged == null || !_canBuildHostedFlow(staged)) return fallback;
      return Stack(
        fit: StackFit.passthrough,
        children: <Widget>[
          fallback,
          Positioned.fill(
            child: _buildHostedFlowLayer(staged, staged: true),
          ),
        ],
      );
    }
    final flowController = _flowController;
    final Widget current =
        flowController != null && _canBuildHostedFlow(flowController)
            ? _buildHostedFlowLayer(flowController, staged: false)
            : _blobPresentation != null
                ? _buildBlobLayer(_blobPresentation!, staged: false)
                : _showDeadlineFallback && widget.fallbackBuilder != null
                    ? _buildAuthoredFallback(
                        _deadlineFallbackError,
                        isCurrent: () =>
                            mounted &&
                            _showDeadlineFallback &&
                            _blobPresentation == null &&
                            _flowController == null,
                      )
                    : (widget.loadingBuilder?.call(context) ??
                        const SizedBox.shrink());
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

  Widget _buildAuthoredFallback(
    RestagePaywallError error, {
    required bool Function() isCurrent,
  }) {
    if (!identical(_fallbackAttributionIdentity, error)) {
      _fallbackAttributionIdentity = error;
      _fallbackMountAttribution =
          captureMountAttribution(_placementDiscovery.declaration?.mount);
    }
    final snapshot = _fallbackMountAttribution;
    return RestageContextSnapshotScope(
      snapshot: _context,
      child: RestagePaywallEventTargetScope(
        owner: this,
        content: error,
        isCurrent: isCurrent,
        child: RestagePaywallEventDispatcher(
          onEvent: (name, args) {
            if (!isCurrent()) return;
            if (snapshot == null) {
              _handleRfwEvent(name, args);
            } else {
              MountAttributionEventContext(
                      snapshot: snapshot,
                      isCurrent: () =>
                          mounted &&
                          isCurrent() &&
                          identical(_fallbackMountAttribution, snapshot))
                  .run(() => _handleRfwEvent(name, args));
            }
          },
          child: RuntimeErrorBoundary(
            debugLabel: widget.id,
            onFirstPaintSuccess: () {
              if (isCurrent()) _placementDiscovery.markPainted();
            },
            onFirstBuildSuccess: () {
              if (!isCurrent() || _viewedFired) return;
              _viewedFired = true;
              _fireEvent(PaywallViewed(paywallId: widget.id));
            },
            onError: (exception, stack) {
              if (!isCurrent()) return;
              _reportUnexpectedLoadFailure(exception, stack);
            },
            errorReplacement: (context, exception, stack) =>
                widget.errorBuilder
                    ?.call(context, _unexpectedLoadError(exception, stack)) ??
                const SizedBox.shrink(),
            child: Builder(builder: widget.fallbackBuilder!),
          ),
        ),
      ),
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
    Widget child = RestageContextSnapshotScope(
      snapshot: _context,
      child: LocalWriteListener(
        onWrite: () => _userInteracted = true,
        child: RestageFlowView<void>(
          controller: controller,
          onScreenEvent: _interceptFlowScreenEvent,
          loadingBuilder: widget.loadingBuilder,
        ),
      ),
    );
    final measurementSession = _flowMeasurementSessions[controller];
    if (measurementSession != null) {
      child = measurementSession.wrapRootSubtree(
        transaction == null
            ? child
            : FirstPaintLeaseScope(
                // The Measurement commit hook owns an inner first-paint
                // lease. Re-expose this candidate's lease at the actual flow
                // boundary so a trapped screen build error rejects the
                // candidate rather than committing an error replacement.
                transaction: transaction,
                child: child,
              ),
      );
    }
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
    final presentation = _flowPresentations[controller];
    if (presentation != null) {
      child = RestagePagerEventScope(
        sink: _pagerSinkForFlowStage(controller, transaction, presentation),
        child: child,
      );
    }
    return KeyedSubtree(
      key: ObjectKey(controller),
      child: ExcludeSemantics(
        excluding: staged || candidatePending,
        child: AbsorbPointer(
          absorbing: staged || candidatePending,
          // A lowered navigation paywall: host the flow. A staged refresh is
          // visibly built above last-good, but inert.
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
              child: RestagePagerEventScope(
                sink: _pagerSinkForBlobStage(stage),
                child: RestagePaywallEventTargetScope(
                  owner: this,
                  content: stage,
                  isCurrent: () => _isBlobEventStageCurrent(stage),
                  child: RestagePaywallEventDispatcher(
                    onEvent: stage.eventHandler,
                    child: RuntimeErrorBoundary(
                      debugLabel: widget.id,
                      onError: (error, _) {
                        markSurfaceDeliveryRenderFailed(stage.payload.variant);
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
                            message:
                                'A widget in the paywall threw during build.',
                          ),
                        );
                      },
                      child: stage.measurementSession.wrapRootSubtree(
                        // Keep paint authority at the RFW boundary so a build
                        // failure rejects the candidate.
                        FirstPaintLeaseScope(
                          transaction: stage.transaction,
                          child: SurfaceDeliveryPaintBoundary(
                            resolved: stage.payload.variant,
                            child: DeliveredIconFontLoader.scope(
                              stage.sections.iconFonts,
                              child: RemoteWidget(
                                runtime: stage.runtime,
                                data: stage.data,
                                widget: placementWidgetNameFor(
                                    stage.payload.variant,
                                    const FullyQualifiedWidgetName(
                                        _paywallLibrary, _paywallRootWidget)),
                                onEvent: stage.eventHandler,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
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
// graph. Other events surface as paywall custom events. `restageNav<N>` is the
// synthesized nav transition; `back` / `skip` are the flow runtime's reserved
// history-pop / dismiss events.
const String _kFlowBackEvent = 'back';
const String _kFlowSkipEvent = 'skip';
const String _kFlowNavEventPrefix = 'restageNav';

/// A [FlowResolver] that returns an already-resolved flow verbatim.
///
/// The paywall variant resolver has already loaded + validated the flow
/// document and its screen blobs (a [ResolvedFlow]); this lets [_startFlow] feed
/// that result straight into a [RestageFlowController] without re-fetching, so
/// the controller's standard load/validate path runs over the bundled flow.
final class _PreResolvedFlowResolver implements FlowResolver {
  _PreResolvedFlowResolver(this._payload);

  final FlowPaywallPayload _payload;
  var _ownsHostedPresentation = true;

  bool revalidate(FlowMountRevalidationBoundary boundary) =>
      _payload.revalidateHostedPresentation(boundary);

  bool detachHostedPresentationForRetry() {
    if (!_payload.canRetryHostedPresentation) return false;
    _ownsHostedPresentation = false;
    return true;
  }

  void disposePresentation() {
    if (_ownsHostedPresentation) _payload.disposeHostedPresentation();
  }

  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> flow) async {
    final pinnedResolver = _payload.pinnedFlowResolver;
    if (pinnedResolver == null) return _payload.flow;
    return pinnedResolver.resolve(OnboardingFlowRef<R>(
      id: flow.id,
      version: flow.version,
      minClient: flow.minClient,
      surface: Surface.paywall,
      deliveryMode: flow.deliveryMode,
      decodeResult: flow.decodeResult,
    ));
  }
}

final class _BlobStage {
  _BlobStage({
    required this.payload,
    required this.runtime,
    required this.data,
    required this.sections,
    required this.epoch,
    required this.isRefresh,
    required this.loadDuration,
    required this.cacheHit,
    required this.transaction,
    required this.analyticsPresentation,
    required this.measurementSession,
    required this.mountAttribution,
  }) : local = LocalValues(
          data,
          seed: sections.localSeeds[_RestagePaywallState._paywallRootWidget],
        );

  final BlobPaywallPayload payload;
  final Runtime runtime;
  final DynamicContent data;
  final SurfaceSections sections;
  final LocalValues local;
  late final ContextPublisher contextPublisher = ContextPublisher(data);
  final int epoch;
  final bool isRefresh;
  final Duration loadDuration;
  final bool cacheHit;
  final FirstPaintLeaseTransaction transaction;
  final RootAnalyticsPresentation analyticsPresentation;
  final MeasurementHostSessionController measurementSession;
  final MountAttributionSnapshotV1? mountAttribution;
  late final PaywallEventHandler eventHandler;

  _BlobStage? previousBlob;
  RestageFlowController<void>? previousFlow;
  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    local.clear();
    transaction.supersede();
    unawaited(measurementSession.teardown());
    analyticsPresentation.dispose();
    runtime.dispose();
  }
}
