import 'dart:async';

import 'package:flutter/material.dart' show Theme;
import 'package:flutter/widgets.dart';
import 'package:restage_material/restage_material_runtime.dart';
import 'package:restage_core/restage_core.dart' show RestageIslandStage;
import 'package:restage_shared/restage_shared.dart' hide WidgetLibrary;
import 'package:rfw/rfw.dart'
    show DynamicContent, RemoteWidget, Runtime, WidgetLibrary;

import '../delivery/decoded_surface_library.dart';
import '../delivery/delivered_fonts.dart';
import '../delivery/raced_surface_resolver.dart';
import '../delivery/surface_sections_carrier.dart';
import '../delivery/render_deadline.dart';
import '../delivery/surface_load_cycle.dart';
import '../delivery/surface_delivery_paint_boundary.dart';
import '../delivery/surface_race.dart';
import '../analytics/root_analytics_context.dart';
import '../authoring/event_dispatch_admission.dart' show RestageEventEpoch;
import '../authoring/onboarding_event.dart' show RecordedEventHost;
import '../authoring/onboarding_event_dispatcher.dart'
    show RestageEventDispatcher, SurfaceEventHandler;
import '../events/restage_event.dart'
    show PagerPageChanged, SurfaceLoadFailureReason, SurfaceLoadSource;
import '../flow/flow_descriptors.dart';
import '../flow/flow_runtime_support.dart';
import '../measurement/measurement_event_sanitizer.dart';
import '../measurement/measurement_host_session.dart';
import '../measurement/measurement_resolved_publication_provenance.dart';
import '../measurement/placement_mount_attribution.dart';
import '../delivery/surface_delivery_receipt_batch.dart';
import '../resolver/placement_mount_resolver.dart';
import '../refresh/surface_refresh_registry.dart';
import '../refresh/surface_update_channel.dart' show SurfaceRef;
import '../runtime/placement_presentation.dart';
import 'restage_surface_screen_resolver.dart';
import '../resolver/surface_delivery_observations.dart'
    show
        SurfaceDeliveryObservationCell,
        readSurfaceDeliveryObservations,
        requestingViewShortestLogicalSide,
        withSurfaceDeliveryObservations;
import '../runtime/context_data.dart';
import '../runtime/user_interaction.dart';
import '../runtime/error_boundary.dart';
import '../runtime/first_paint_lease_guard.dart';
import '../runtime/event_demux.dart' show isReservedCommerceEventName;
import '../runtime/installed_widget_vocabulary.dart';
import '../runtime/local_values.dart';
import '../runtime/placement_mount.dart';
import '../runtime/surface_vocabulary.dart';
import '../runtime/restage.dart';
import '../runtime/source_badge.dart';
import '../runtime/surface_unavailable_policy.dart';
import '../runtime/state_variables.dart'
    show currentDevicePlatform, populateDeviceData, populateThemeData;
import 'surface_screen_runtime_provenance.dart';
import 'surface_screen_types.dart';

/// Category-neutral host for one independently published screen.
///
/// Prefer generated `*Surface(...)` widgets for typed bindings, registration,
/// compiled fallbacks and implicit placements.
///
/// The host accepts only a generated [SurfaceScreenRef]. It validates that
/// reference against its compiled-in generated provenance before consulting a
/// resolver, and validates whatever the resolver returns against the same
/// provenance, so a resolver cannot introduce an arbitrary artifact or event
/// contract.
final class RestageScreen<E> extends StatefulWidget
    implements RestagePlacementMount {
  /// Creates a standalone generated-screen host.
  const RestageScreen({
    super.key,
    required this.screen,
    this.fallbackBuilder,
    this.errorBuilder,
    this.placementBinding,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
    this.context,
  });

  /// Creates the generated host facts without requiring new authored imports.
  static GeneratedPlacementDefinition generatedPlacementDefinition({
    required RestageSurfaceRef defaultSurface,
    required Map<String, Object?> defaultSurfaceLocatorJson,
    required Map<String, Object?> hostContractJson,
    required SurfaceVocabulary vocabulary,
    String? surfaceWidget,
  }) {
    if (defaultSurface is SurfaceScreenRef<Object?> && surfaceWidget != null) {
      nameSurfaceScreenWidget(defaultSurface, surfaceWidget);
    }
    return GeneratedPlacementDefinition.generated(
      defaultSurface: defaultSurface,
      defaultSurfaceLocatorJson: defaultSurfaceLocatorJson,
      hostContractJson: hostContractJson,
      vocabulary: vocabulary,
    );
  }

  /// Creates the inert binding forwarded by a generated mount.
  static PlacementMountBinding generatedPlacementBinding({
    required GeneratedPlacementDefinition Function() definition,
    String? name,
    Object? eventOwner,
  }) =>
      PlacementMountBinding(
          definition: definition, name: name, eventOwner: eventOwner);

  /// The exact generated standalone-screen reference to render.
  final SurfaceScreenRef<E> screen;

  /// The generated default definition and optional named placement.
  @override
  final PlacementMountBinding? placementBinding;

  /// Shown in place of the compiled original when no published, saved or
  /// bundled version of the screen can render. Null shows the compiled
  /// original; without one, nothing shows while the host waits for content.
  /// Events these widgets fire with `surfaceEvent` reach [onEvent] through the
  /// screen's generated event contract.
  final WidgetBuilder? fallbackBuilder;

  /// Shown instead of restarting the user when the screen fails after they
  /// made progress in this load, and for any failure when neither a fallback
  /// nor a compiled original is left to show. Null shows the fallback, the
  /// original, or nothing.
  final Widget Function(
      BuildContext context, SurfaceScreenUnavailableError error)? errorBuilder;

  /// Receives only generated, schema-validated event values.
  final ValueChanged<E>? onEvent;

  /// Optional resolver. The configured default is used when omitted. A new
  /// resolver object reloads the screen, so hold one rather than creating it
  /// in `build`.
  final SurfaceScreenResolver? resolver;

  /// Observes a classified unavailable condition.
  final ValueChanged<SurfaceScreenUnavailableError>? onUnavailable;

  /// Optional content shown while the screen resolves.
  final WidgetBuilder? loadingBuilder;

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
  final Map<String, Object?>? context;

  @override
  State<RestageScreen<E>> createState() => _RestageScreenState<E>();
}

class _RestageScreenState<E> extends State<RestageScreen<E>> {
  _ScreenStage? _stage;

  // The surface events come from; it changes when another screen takes this
  // element.
  Object _eventIdentity = Object();
  _ScreenStage? _acceptedStage;
  SurfaceScreenUnavailableError? _unavailableError;
  SurfaceDeliveryObservationCell? _observationCell;
  RenderDeadline? _renderDeadline;
  SurfaceLoad? _surfaceLoad;

  /// Delivered content that arrived after the compiled fallback painted.
  ({Object? version})? _late;

  static Object? _versionOf(Object resolved) {
    try {
      return SingleSurfaceRenderContent.fromResolved(resolved).version;
    } on Object {
      return null;
    }
  }

  /// The compiled widget shown because nothing was ready by the deadline.
  bool _showDeadlineFallback = false;
  var _resolutionEpoch = 0;
  int _fallbackAttributionEpoch = -1;
  RootAnalyticsPresentation? _fallbackReadOwner;
  MountAttributionSnapshotV1? _fallbackMountAttribution;
  var _dependenciesReady = false;
  ContextSnapshot? _context;
  late final SurfaceEventHandler _fallbackEventHandler = _handleFallbackEvent;

  void _refreshContext() {
    final raw = widget.context;
    _context = raw == null ? null : ContextSnapshot.of(raw, previous: _context);
  }

  @override
  void initState() {
    super.initState();
    _refreshContext();
    _restart();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dependenciesReady = true;
    _populateData();
  }

  @override
  void didUpdateWidget(RestageScreen<E> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _refreshContext();
    // Another screen taking this element: what the old one showed in a
    // dialog no longer reaches it. A new handler for the same screen does.
    if (!identical(oldWidget.screen, widget.screen)) {
      _eventIdentity = Object();
    }
    if (!identical(oldWidget.screen, widget.screen) ||
        !identical(oldWidget.resolver, widget.resolver) ||
        !(oldWidget.placementBinding
                ?.sameDeclarationAs(widget.placementBinding) ??
            widget.placementBinding == null)) {
      _restart();
      return;
    }
    _stage?.contextPublisher.publishSnapshot(_context);
  }

  @override
  void dispose() {
    _fallbackReadOwner?.dispose();
    _placementDiscovery.dispose();
    _renderDeadline?.cancel();
    _resolutionEpoch += 1;
    _unregisterPlacementValidity();
    _disposeStages();
    _observationCell = null;
    super.dispose();
  }

  SurfaceDeliveryObservationCell _presentationObservations() =>
      _observationCell ??= SurfaceDeliveryObservationCell(
        () => readSurfaceDeliveryObservations(
          shortestLogicalSide:
              mounted ? requestingViewShortestLogicalSide(context) : null,
        ),
      );

  void _restart() {
    _fallbackReadOwner?.dispose();
    _fallbackReadOwner = null;
    // Installing here is what makes a screen swapped into this position
    // render with its own vocabulary.
    widget.screen.provenance.vocabulary.addToInstalled();
    _observationCell = null;
    _placementInteracted = false;
    _loadAdvanced = false;
    final epoch = ++_resolutionEpoch;
    _renderDeadline?.cancel();
    final deadline = _renderDeadline = RenderDeadline.start(
        Restage.firstLaunchWaitFor(widget.screen.slug),
        window: Restage.freshWindow);
    _surfaceLoad = SurfaceLoad(
        surfaceId: widget.screen.slug,
        surface: widget.screen.surface,
        deadline: deadline)
      ..start(Restage.fireEvent);
    _unregisterPlacementValidity();
    assert(() {
      _debugHandleRegistered = false;
      return true;
    }());
    _disposeStages();
    setState(() {
      _unavailableError = null;
      _showDeadlineFallback = false;
      _late = null;
    });
    if (!_presentHeld(epoch)) unawaited(_resolveInScope(epoch));
  }

  // Stages a decision this process already accepted before the first build.
  // Fresh still answers, as it does after a local candidate wins the race.
  bool _presentHeld(int epoch) {
    final resolver = _resolver();
    final cell = _presentationObservations();
    return presentHeldPlacement<Object>(
      racedResolverOf<Object>(resolver),
      key: () => Restage.storeKeyFor(widget.screen, resolver: resolver),
      inScope: <R>(R Function() body) =>
          withSurfaceDeliveryObservations(cell: cell, resolve: body),
      present: (held) => withSurfaceDeliveryObservations(
          cell: cell, resolve: () => _stageResolved(epoch, held)),
      // A stage that fails reports its own failure.
      onPresentFailed: () {},
      keyDeadline: _renderDeadline!.reached,
      freshWindow: _renderDeadline!.windowPassed,
      onLateFresh: (resolved, report) =>
          _presentLateFresh(resolved, epoch, report),
    );
  }

  Future<void> _resolveInScope(int epoch) => withSurfaceDeliveryObservations(
        cell: _presentationObservations(),
        resolve: () => _resolve(epoch),
      );

  SurfaceRefreshHandle? _placementValidityHandle;
  bool _placementInteracted = false;

  /// Whether this load advanced: the user interacted or an event reached the
  /// host. Read when the load fails.
  bool _loadAdvanced = false;
  SurfaceScreenResolver? _placementResolver;
  PlacementMountBinding? _capturedBinding;
  int _placementGeneration = -1;
  late final _placementDiscovery = PlacementHostDiscovery(
      configurationGeneration: () => Restage.configurationGeneration,
      discovery: () => Restage.placementDiscovery);

  SurfaceScreenResolver _resolver() {
    final original = widget.resolver ?? Restage.defaultSurfaceScreenResolver;
    final binding = widget.placementBinding;
    if (widget.resolver == null) {
      if (binding?.isGenerated ?? false) binding!.definition();
      Restage.reportUnconfiguredMount(
          widget.screen.surfaceWidget ?? widget.screen.provenance.slug);
    }
    final declaration = _placementDiscovery.capture(binding, widget, context);
    final registry = Restage.placementRegistry;
    if (widget.resolver != null ||
        !Restage.placementScreensEnabled ||
        binding == null ||
        registry == null ||
        original is! RestageScreenResolver) {
      return original;
    }
    if (_placementResolver == null ||
        !binding.sameDeclarationAs(_capturedBinding) ||
        _placementGeneration != Restage.configurationGeneration) {
      _capturedBinding = binding;
      _placementGeneration = Restage.configurationGeneration;
      _placementResolver = PlacementScreenResolver(
          registry: registry,
          declaration: declaration!,
          screen: widget.screen as SurfaceScreenRef<Object?>,
          originalResolver: original.assetFallback)
        ..onFallbackChanged = () {
          _registerPlacementValidity();
          assert(_debugCheckStageInvariants());
        };
    }
    return _placementResolver!;
  }

  Future<void> _resolve(int epoch) async {
    final screen = widget.screen;
    final resolver = _resolver();
    final Object resolved;
    try {
      final raced = await _race(resolver, screen, epoch);
      if (raced == null) return;
      resolved = raced;
    } on SurfaceScreenUnavailableError catch (error) {
      _fail(epoch, error);
      return;
    } on Object catch (error) {
      _fail(
        epoch,
        SurfaceScreenUnavailableError(
          reason: SurfaceScreenUnavailableReason.invalidPayload,
          message: 'The screen could not be resolved.',
          cause: error,
        ),
      );
      return;
    }
    if (!_isCurrent(epoch)) return;
    await _stageResolved(epoch, resolved);
  }

  Future<void> _stageResolved(int epoch, Object resolved,
      {bool isRefresh = false}) async {
    if (!((surfaceAssignmentLeaseFor(resolved)?.isCurrent ?? true) &&
        (placementAdmissionFor(resolved)?.isCurrent ?? true))) {
      if (!isRefresh) await _resolveLocalAfterInvalidation(epoch);
      return;
    }
    final provenance = widget.screen.provenance;
    try {
      final stage = _validateAndBuildStage(provenance, resolved);
      // The accepted stage stays until this one paints, and returns if it is
      // refused.
      stage.previousStage = _acceptedStage;
      bindSurfaceDeliveryMountAttribution(resolved, stage.mountAttribution);
      stage.transaction = FirstPaintLeaseTransaction(
        canCommit: () =>
            _isCurrent(epoch) &&
            identical(_stage, stage) &&
            (!isRefresh ||
                stage.previousStage == null ||
                (identical(stage.previousStage, _acceptedStage) &&
                    _canRefreshPlacement())) &&
            (surfaceAssignmentLeaseFor(resolved)?.isCurrent ?? true) &&
            (placementAdmissionFor(resolved)?.isCurrent ?? true) &&
            !stage.presentation.isInvalidatedByIdentityReset,
        isInvalidatedByIdentityReset: () =>
            stage.presentation.isInvalidatedByIdentityReset ||
            !((surfaceAssignmentLeaseFor(resolved)?.isCurrent ?? true) &&
                (placementAdmissionFor(resolved)?.isCurrent ?? true)),
        commit: () {},
        onPainted: () {
          _placementDiscovery.markPainted(resolved);
          _acceptedStage = stage;
          _acceptedDecision = null;
          _registerPlacementValidity();
          assert(_debugCheckStageInvariants(shown: true));
        },
        afterCommit: () {
          if (identical(_stage, stage)) {
            stage.presentation.activate();
            // The replaced stage left the tree with the commit frame.
            final previous = stage.previousStage;
            stage.previousStage = null;
            previous?.dispose();
          }
          assert(_debugCheckStageInvariants());
        },
        afterRejection: () {
          if (!mounted || !identical(_stage, stage)) return;
          // A refused stage shows the accepted stage again while its decision
          // holds, else local content.
          if (_canRestorePrevious(stage)) {
            _restorePreviousStage(stage);
            return;
          }
          _disposeStages();
          assert(_debugCheckStageInvariants());
          unawaited(_resolveLocalAfterInvalidation(_resolutionEpoch));
        },
      );
      _attachMeasurementSession(stage, resolved);
      if (isRefresh &&
          (!_canRefreshPlacement() ||
              (placementAdmissionFor(resolved)?.isAssigned ?? false))) {
        stage.dispose();
        return;
      }
      if (!_isCurrent(epoch) ||
          !stage.transaction.isPending ||
          !((surfaceAssignmentLeaseFor(resolved)?.isCurrent ?? true) &&
              (placementAdmissionFor(resolved)?.isCurrent ?? true))) {
        stage.dispose();
        if (_isCurrent(epoch) && !isRefresh) {
          await _resolveLocalAfterInvalidation(epoch);
        }
        return;
      }
      final previous = _stage;
      setState(() {
        _stage = stage;
        _unavailableError = null;
        _showDeadlineFallback = false;
        _late = null;
      });
      assert(_debugCheckStageInvariants());
      // The accepted stage is kept to restore; any other displaced stage goes.
      if (previous != null && !identical(previous, stage.previousStage)) {
        WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
      }
      _populateData();
    } on SurfaceScreenUnavailableError catch (error) {
      if (isRefresh) return;
      _fail(epoch, error);
    } on Object catch (error) {
      if (isRefresh) return;
      _fail(
        epoch,
        SurfaceScreenUnavailableError(
          reason: SurfaceScreenUnavailableReason.invalidPayload,
          message: 'The resolved screen content is invalid.',
          cause: error,
        ),
      );
    }
  }

  /// Watches the accepted delivery, or the fallback's watch while it shows.
  void _registerPlacementValidity() {
    if (!mounted) return;
    final previous = _placementValidityHandle;
    if (previous != null) {
      SurfaceRefreshRegistry.instance.acceptedPlacementChanged(previous);
      SurfaceRefreshRegistry.instance.localValidityChanged(previous);
      return;
    }
    if (_acceptedAdmission == null &&
        placementFallbackFor(_placementResolver) == null) {
      return;
    }
    final content = _acceptedStage?.content;
    final handle = SurfaceRefreshHandle(
        surface: SurfaceRef(
            surfaceType: (content?.surface ?? widget.screen.surface).wireName,
            slug: content?.slug ?? widget.screen.slug),
        triggers: Restage.effectiveLiveRefreshTriggers(widget.screen.slug),
        canSwap: _canRefreshPlacement,
        refresh: _refreshPlacement,
        localValidity: () => _acceptedAdmission?.isCurrent ?? true,
        localBoundary: () => _acceptedAdmission?.nextBoundary,
        placementState: () => _acceptedAdmission == null
            ? placementFallbackFor(_placementResolver)?.refreshState
            : _acceptedAdmission?.refreshState,
        placementWatch: () => _acceptedAdmission == null
            ? placementFallbackFor(_placementResolver)?.watch
            : _acceptedAdmission?.decision.watch,
        renderedSurface: () =>
            _acceptedAdmission?.renderedSurface ??
            SurfaceRef(
                surfaceType: widget.screen.surface.wireName,
                slug: widget.screen.slug),
        invalidatePlacement: () async {
          final accepted = _acceptedAdmission;
          accepted?.markStale();
        },
        probePlacement: (rendered) => probeRenderedPlacement(
            _acceptedAdmission, _placementResolver, rendered),
        invalidateLocal: () async {
          final resolver = _placementResolver;
          if (resolver is! PlacementScreenResolver) return;
          final original = await resolver.original();
          if (!mounted ||
              !identical(_stage, _acceptedStage) ||
              _progressed ||
              (_acceptedAdmission?.isAssigned ?? false)) {
            return;
          }
          if (original != null) {
            await _stageResolved(++_resolutionEpoch, original);
          } else {
            _disposeStages();
            _fail(++_resolutionEpoch, _missing);
            assert(_debugCheckStageInvariants());
          }
        });
    _placementValidityHandle = handle;
    SurfaceRefreshRegistry.instance.register(handle);
    assert(() {
      _debugHandleRegistered = true;
      return true;
    }());
  }

  PlacementDeliveryAdmission? get _acceptedAdmission => _acceptedStage == null
      ? null
      : placementAdmissionFor(_acceptedDecision ?? _acceptedStage!.resolved);

  // A refreshed decision for the accepted stage's unchanged content.
  Object? _acceptedDecision;

  bool get _showsFallback =>
      _stage == null && (_unavailableError != null || _showDeadlineFallback);

  /// Whether the user made progress in this load; a live swap never replaces
  /// such a load. The failure latch only ever copies this.
  bool get _progressed => _placementInteracted;

  SurfaceUnavailablePolicy<SurfaceScreenUnavailableError> get _unavailable =>
      SurfaceUnavailablePolicy(
          fallbackBuilder: widget.fallbackBuilder,
          errorBuilder: widget.errorBuilder);

  bool _canRefreshPlacement() =>
      mounted &&
      !_progressed &&
      (_acceptedStage == null
          ? _showsFallback
          : !(_acceptedAdmission?.isAssigned ?? false));

  Future<void> _refreshPlacement() async {
    final previous = _acceptedStage;
    final resolver = _placementResolver;
    if (resolver is! PlacementScreenResolver || !_canRefreshPlacement()) {
      return;
    }
    if (previous == null) return _refreshFromFallback(resolver);
    final epoch = ++_resolutionEpoch;
    try {
      final fresh =
          await resolver.fresh(resolver.storeKey, sendAssignmentKey: true);
      if (!_isCurrent(epoch) ||
          fresh == null ||
          !identical(previous, _acceptedStage) ||
          !_canRefreshPlacement()) {
        return;
      }
      final candidate = placementAdmissionFor(fresh);
      final accepted = _acceptedAdmission;
      if ((candidate?.isAssigned ?? false) ||
          (accepted?.matchesDecision(candidate) ?? false)) {
        return;
      }
      // Same content under a new decision: keep the shown stage, with its
      // presentation and receipt, and watch the new decision.
      if (candidate != null &&
          accepted != null &&
          accepted.isCurrent &&
          identical(_stage, previous) &&
          candidate.delivery.publicProjectionDigest ==
              accepted.delivery.publicProjectionDigest) {
        _acceptedDecision = fresh;
        _registerPlacementValidity();
        assert(_debugCheckStageInvariants(shown: true));
        return;
      }
      await _stageResolved(epoch, fresh, isRefresh: true);
    } on Object {
      // A failed refresh keeps the accepted presentation.
    }
  }

  // A delivery replaces the shown fallback as a new presentation.
  Future<void> _refreshFromFallback(PlacementScreenResolver resolver) async {
    final epoch = _resolutionEpoch;
    try {
      final fresh =
          await resolver.fresh(resolver.storeKey, sendAssignmentKey: true);
      if (fresh == null || !_isCurrent(epoch) || !_canRefreshPlacement()) {
        return;
      }
      await _stageResolved(++_resolutionEpoch, fresh);
    } on Object {
      // A failed refresh keeps the fallback.
    }
  }

  bool _canRestorePrevious(_ScreenStage stage) =>
      stage.previousStage != null && (_acceptedAdmission?.isCurrent ?? true);

  void _restorePreviousStage(_ScreenStage rejected) {
    final previous = rejected.previousStage;
    if (previous == null) return;
    rejected.previousStage = null;
    setState(() => _stage = previous);
    rejected.dispose();
    _populateData();
    assert(_debugCheckStageInvariants(shown: true));
  }

  Future<void> _resolveLocalAfterInvalidation(int epoch) async {
    final resolver = _resolver();
    final raced = racedResolverOf<Object>(resolver);
    final key = raced == null
        ? null
        : Restage.storeKeyFor(widget.screen, resolver: resolver);
    Object? local;
    try {
      // Keep the original deadline and its ready-local policy. A local lookup
      // that completes after settlement cannot swap into the host floor.
      local = raced == null
          ? null
          : (await raceSurface<Object>(
              deadline: _renderDeadline!,
              fresh: () async => null,
              bestLocal: () => raced.bestLocal(key!),
            ))
              .value;
    } on Object {
      // Local lookup failures still settle on the host's unavailable floor.
    }
    if (!_isCurrent(epoch)) return;
    if (local != null &&
        (surfaceAssignmentLeaseFor(local)?.isCurrent ?? true)) {
      if (raced != null) reportRaceWinner(raced, key!, local);
      await _stageResolved(epoch, local);
    } else {
      if (raced != null) reportRaceWinner(raced, key!, null);
      _fail(epoch, _missing);
    }
  }

  /// Races fresh content against local candidates until the render deadline.
  ///
  /// Returns null when the mount shows its compiled widget or keeps waiting.
  Future<Object?> _race(
    SurfaceScreenResolver resolver,
    SurfaceScreenRef<E> screen,
    int epoch,
  ) async {
    final deadline = _renderDeadline!;
    final raced = racedResolverOf<Object>(resolver);
    final key =
        raced == null ? null : Restage.storeKeyFor(screen, resolver: resolver);
    void report(Object? rendered) {
      if (raced != null) reportRaceWinner(raced, key!, rendered);
    }

    late final Future<Object?> freshFuture;
    Future<Object?> fresh() => freshFuture = raced == null
        ? resolver.resolve(screen)
        : raced.fresh(
            key!,
            sendAssignmentKey: true,
            keyDeadline: deadline.reached,
          );
    final outcome = await raceSurface<Object>(
      answerArrived: raced == null ? null : () => raced.freshAnswerArrived,
      deadline: deadline,
      fresh: fresh,
      bestLocal: raced == null ? () async => null : () => raced.bestLocal(key!),
      onLateFresh: (resolved) => _presentLateFresh(resolved, epoch, report,
          kept: () => reportLateAnswerKept(raced, key)),
    );
    if (!_isCurrent(epoch)) return null;
    switch (outcome) {
      // A rejected or failed fetch falls back to the local copies, as on
      // every host.
      case RaceFresh(:final value) || RaceLocal(:final value):
        report(value);
        return value;
      case RaceNone(freshPending: true):
        // Only a fallback shows at the wait; an error builder needs a failure.
        if (surfaceUnavailableView(_unavailable, advanced: false) ==
            SurfaceUnavailableView.original) {
          report(null);
          setState(() => _showDeadlineFallback = true);
          _registerPlacementValidity();
          assert(_debugCheckStageInvariants());
        } else {
          // Nothing to show yet: the mount settles on fresh's outcome.
          unawaited(freshFuture.then(
            (resolved) {
              if (resolved == null) _failLate(null, epoch, report);
            },
            onError: (Object error) => _failLate(error, epoch, report),
          ));
        }
        return null;
      case RaceNone(:final freshError):
        report(null);
        if (freshError != null) throw freshError;
        throw _missing;
    }
  }

  static const SurfaceScreenUnavailableError _missing =
      SurfaceScreenUnavailableError(
    reason: SurfaceScreenUnavailableReason.missing,
    message: 'The screen is not available.',
  );

  void _failLate(
    Object? error,
    int epoch,
    void Function(Object?) report,
  ) {
    if (!_isCurrent(epoch) || _stage != null || _unavailableError != null) {
      return;
    }
    report(null);
    _fail(
      epoch,
      switch (error) {
        null => _missing,
        final SurfaceScreenUnavailableError unavailable => unavailable,
        _ => SurfaceScreenUnavailableError(
            reason: SurfaceScreenUnavailableReason.invalidPayload,
            message: 'The screen could not be resolved.',
            cause: error,
          ),
      },
    );
  }

  // A late initial response waits for the next mount unless nothing is shown.
  void _presentLateFresh(
    Object resolved,
    int epoch,
    void Function(Object?) report, {
    void Function()? kept,
  }) {
    if (_isCurrent(epoch) &&
        _stage == null &&
        _unavailableError == null &&
        _showDeadlineFallback) {
      kept?.call();
      // The badge says delivered content is waiting for the next mount.
      if (Restage.showSourceBadges) {
        setState(() => _late = (version: _versionOf(resolved),));
      }
      return;
    }
    if (!_isCurrent(epoch) ||
        _stage != null ||
        _unavailableError != null ||
        _showDeadlineFallback) {
      return;
    }
    report(resolved);
    unawaited(withSurfaceDeliveryObservations(
      cell: _presentationObservations(),
      resolve: () => _stageResolved(epoch, resolved),
    ));
  }

  /// Opens Measurement in the background once the host has validated the
  /// exact resolved artifact; the screen renders without waiting for it.
  ///
  /// The controller owns all host-independent resolution and degrades to an
  /// inert session. Its failure must never make a validated screen unavailable.
  void _attachMeasurementSession(
    _ScreenStage stage,
    Object resolved,
  ) {
    try {
      stage.attachMeasurementSession(
        MeasurementHostSessionController.openDeferred(
          resolved,
          presentationObservations: _observationCell?.read,
          mountAttribution: stage.mountAttribution,
        ),
      );
    } on Object {
      // Measurement is fail-closed and observational. A construction failure
      // leaves the independently validated screen on its existing path.
    }
  }

  _ScreenStage _validateAndBuildStage(
    SurfaceScreenRuntimeProvenance provenance,
    Object resolved,
  ) {
    // The host re-runs the same validation the resolver ran. A resolver is a
    // replaceable seam, so the host never takes its word for identity,
    // contract, content hash, or bundled provenance.
    final content = SingleSurfaceRenderContent.fromResolved(resolved);
    if (resolved is ResolvedSurfaceScreen) {
      provenance.validateResolved(resolved);
    } else if (resolved is! PlacementSingleSurface ||
        !resolved.admission.isCurrent) {
      throw const SurfaceScreenUnavailableError(
          reason: SurfaceScreenUnavailableReason.invalidPayload,
          message: 'The placement is no longer eligible to render.');
    }

    final capabilityVerdict = BlobRenderCapabilityGate.evaluate(
      required: content.capabilities,
      installed: currentInstalledCapability(),
    );
    if (capabilityVerdict is BlobRenderRejected) {
      throw SurfaceScreenUnavailableError(
        reason: SurfaceScreenUnavailableReason.incompatible,
        message: 'The installed runtime cannot render this screen.',
        cause: capabilityVerdict,
      );
    }

    final WidgetLibrary library;
    try {
      library = decodedSurfaceLibrary(content.blob);
    } on Object catch (error) {
      throw SurfaceScreenUnavailableError(
        reason: SurfaceScreenUnavailableReason.invalidPayload,
        message: 'The resolved screen blob cannot be decoded.',
        cause: error,
      );
    }

    final runtime = flowScreenRuntime(library);
    final presentation = RootAnalyticsRuntime.createPresentation(
      surface: content.surface.wireName,
      surfaceId: content.slug,
      sourceKind: resolved is ResolvedSurfaceScreen
          ? SurfaceScreenRuntimeProvenance.sourceKind
          : null,
      payloadKind: SurfaceScreenRuntimeProvenance.payloadKind,
    );
    presentation.stage(
      surfaceVersion: content.version,
      assignment: resolved is ResolvedSurfaceScreen
          ? resolved.assignment
          : projectResolvedSurfaceAssignment(resolved),
    );
    final data = DynamicContent();
    final sections = surfaceSectionsFor(resolved);
    return _ScreenStage(
      provenance: provenance,
      resolved: resolved,
      content: content,
      runtime: runtime,
      data: data,
      presentation: presentation,
      sections: sections,
      mountAttribution: captureMountAttribution(
          _placementDiscovery.declaration?.mount,
          resolved: resolved),
      local: LocalValues(
        data,
        seed: sections.localSeeds[
            placementRootWidgetFor(resolved, kFlowScreenWidget.widget)],
      ),
    );
  }

  void _populateData() {
    final stage = _stage;
    if (stage == null) return;
    stage.contextPublisher.publishSnapshot(_context);
    if (!_dependenciesReady) return;
    final mediaQuery = MediaQuery.maybeOf(context);
    if (mediaQuery != null) {
      populateDeviceData(
        stage.data,
        locale: Localizations.maybeLocaleOf(context) ?? const Locale('en'),
        mediaQuery: mediaQuery,
        platform: currentDevicePlatform(),
      );
    }
    final theme = Theme.of(context);
    populateThemeData(
      stage.data,
      colorScheme: theme.colorScheme,
      iconTheme: theme.iconTheme,
      defaultTextStyle: DefaultTextStyle.of(context).style,
      textTheme: theme.textTheme,
    );
  }

  /// Decodes one screen event through the generated contract, or returns null
  /// for a reserved commerce event. Throws when the contract rejects it.
  ({E event})? _decodeScreenEvent(
    String name,
    Object? value,
    Object? Function(Object? value) sanitize,
  ) {
    if (isReservedCommerceEventName(name)) return null;
    final arguments = normalizeEventArgs(sanitize(value));
    widget.screen.provenance.eventSchema.validateEvent(name, arguments);
    return (
      event: widget.screen.eventContract.decodeValidated(name, arguments),
    );
  }

  // An event app code fires that the contract rejects is reported and
  // dropped; only one the delivered design fires fails the screen.
  void _handleEvent(
    _ScreenStage stage,
    String name,
    Object? value, {
    bool fromApp = false,
  }) {
    if (!identical(_stage, stage)) return;
    _placementInteracted = true;
    if (stage.local.intercept(name, value)) return;
    value = withoutContextItemIndexes(value);
    if (isMeasurementTapEventName(name)) {
      stage.sanitizeAndRecordEvent(value);
      return;
    }
    try {
      final decoded =
          _decodeScreenEvent(name, value, stage.sanitizeAndRecordEvent);
      if (decoded == null) return;
      final callback = widget.onEvent;
      if (callback == null) {
        throw const FormatException('No typed event callback is installed.');
      }
      void dispatch() =>
          stage.presentation.runWithEventContext(() => callback(decoded.event));
      final snapshot = stage.mountAttribution;
      if (snapshot == null) {
        dispatch();
      } else {
        MountAttributionEventContext(
            snapshot: snapshot,
            isCurrent: () =>
                mounted &&
                identical(_stage, stage) &&
                stage.transaction.isPaintAcknowledged).run(dispatch);
      }
    } on Object catch (error, stack) {
      if (fromApp) {
        FlutterError.reportError(FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'restage',
          context: ErrorDescription(
            'rejecting an app event for screen ${widget.screen.slug}',
          ),
        ));
        return;
      }
      _fail(
        _resolutionEpoch,
        SurfaceScreenUnavailableError(
          reason: SurfaceScreenUnavailableReason.eventRejected,
          message: 'A screen event was rejected by its generated contract.',
          cause: error,
        ),
      );
    }
  }

  // Events from the fallback UI decode through the same generated contract.
  void _handleFallbackEvent(String name, Object? value) {
    if (!mounted || (_unavailableError == null && !_showDeadlineFallback)) {
      return;
    }
    _placementInteracted = true;
    final callback = widget.onEvent;
    if (callback == null) return;
    final ({E event})? decoded;
    try {
      decoded = _decodeScreenEvent(name, value, _sanitizeFallbackEvent);
    } on Object catch (error, stack) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'restage',
        context: ErrorDescription(
          'rejecting a fallback event for screen ${widget.screen.slug}',
        ),
      ));
      return;
    }
    if (decoded == null) return;
    final event = decoded.event;
    final snapshot = _fallbackMountAttribution;
    if (snapshot == null) {
      callback(decoded.event);
    } else {
      final epoch = _resolutionEpoch;
      MountAttributionEventContext(
              snapshot: snapshot,
              isCurrent: () =>
                  mounted &&
                  epoch == _resolutionEpoch &&
                  (_unavailableError != null || _showDeadlineFallback))
          .run(() => callback(event));
    }
  }

  static Object? _sanitizeFallbackEvent(Object? value) =>
      MeasurementEventSanitizer.sanitize(value).businessValue;

  // The surface that receives events a generated mount recorded above it.
  static Widget _hostRecordedEvents(Object? owner, Widget child) =>
      owner == null ? child : RecordedEventHost(owner: owner, child: child);

  void _handleRenderFailure(_ScreenStage stage, Object error) {
    if (!identical(_stage, stage)) return;
    // The stored copy is forgotten only when it is what failed.
    if (surfaceLoadSourceOf(stage.resolved) != SurfaceLoadSource.original) {
      _forgetStoredCandidate();
    }
    _fail(
      _resolutionEpoch,
      SurfaceScreenUnavailableError(
        reason: SurfaceScreenUnavailableReason.renderFailure,
        message: 'The screen failed while rendering.',
        cause: error,
      ),
    );
  }

  /// Drops the stored copy of a screen that failed to render, so the next
  /// mount falls back instead of rendering it again.
  void _forgetStoredCandidate() {
    final resolver = _resolver();
    final raced = racedResolverOf<Object>(resolver);
    if (raced == null) return;
    unawaited(raced.forgetStored(
      Restage.storeKeyFor(widget.screen, resolver: resolver),
    ));
  }

  bool _isPagerStageCurrent(_ScreenStage stage) {
    return mounted && identical(_stage, stage) && stage.presentation.isActive;
  }

  RestagePagerEventSink _pagerSinkForStage(_ScreenStage stage) {
    return RestagePagerEventSink(
      stageToken: stage,
      isCurrent: (token) =>
          identical(token, stage) && _isPagerStageCurrent(stage),
      onPageChanged: (pageIndex, pageCount) {
        if (!_isPagerStageCurrent(stage)) return;
        stage.presentation.runWithEventContext(
          () => Restage.fireEvent(
            PagerPageChanged(pageIndex: pageIndex, pageCount: pageCount),
          ),
        );
      },
    );
  }

  void _fail(int epoch, SurfaceScreenUnavailableError error) {
    if (!_isCurrent(epoch)) return;
    final pending = _stage;
    if (pending != null && _canRestorePrevious(pending)) {
      _restorePreviousStage(pending);
      return;
    }
    _disposeStages();
    _loadAdvanced = _loadAdvanced || _placementInteracted;
    setState(() => _unavailableError = error);
    _registerPlacementValidity();
    assert(_debugCheckStageInvariants());
    widget.onUnavailable?.call(error);
  }

  /// Completes the load inside [presentation]'s context once it is active.
  void _completeLoad(SurfaceLoad? load, _ScreenStage stage) {
    stage.presentation.captureDeferredContextOnActivation((attribution) {
      if (!mounted) return;
      final event = load?.complete(stage.resolved);
      if (event != null) {
        attribution.runWithEventContext(() => Restage.fireEvent(event));
      }
    });
  }

  void _completeLoadWithOriginal(SurfaceLoad? load) {
    if (!mounted) return;
    final event = load?.complete(null);
    if (event == null) return;
    final owner = _fallbackReadOwner;
    if (owner == null) {
      Restage.fireEvent(event);
    } else {
      owner.runWithEventContext(() => Restage.fireEvent(event));
    }
  }

  void _failLoad(SurfaceLoad? load, SurfaceScreenUnavailableError error) {
    if (!mounted) return;
    final event =
        load?.fail(_failureFor(error.reason), detail: _detailOf(error.reason));
    if (event != null) Restage.fireEvent(event);
  }

  /// The snake_case code other hosts use for their own failures.
  static String _detailOf(SurfaceScreenUnavailableReason reason) =>
      reason.name.replaceAllMapped(
          RegExp('[A-Z]'), (match) => '_${match[0]!.toLowerCase()}');

  static SurfaceLoadFailureReason _failureFor(
          SurfaceScreenUnavailableReason reason) =>
      switch (reason) {
        SurfaceScreenUnavailableReason.missing =>
          SurfaceLoadFailureReason.unavailable,
        SurfaceScreenUnavailableReason.renderFailure =>
          SurfaceLoadFailureReason.renderError,
        SurfaceScreenUnavailableReason.identityMismatch ||
        SurfaceScreenUnavailableReason.contractMismatch ||
        SurfaceScreenUnavailableReason.incompatible ||
        SurfaceScreenUnavailableReason.invalidPayload ||
        SurfaceScreenUnavailableReason.eventRejected =>
          SurfaceLoadFailureReason.invalid,
      };

  bool _isCurrent(int epoch) => mounted && epoch == _resolutionEpoch;

  static const SurfaceScreenUnavailableError _policyWidgetFailed =
      SurfaceScreenUnavailableError(
    reason: SurfaceScreenUnavailableReason.renderFailure,
    message: 'The widget shown in place of the screen threw.',
  );

  static const SurfaceScreenUnavailableError _deadlineFallbackError =
      SurfaceScreenUnavailableError(
    reason: SurfaceScreenUnavailableReason.missing,
    message: 'No content was ready by the render deadline.',
  );

  // Only disposal and a restart end the mount's live refresh.
  void _unregisterPlacementValidity() {
    final handle = _placementValidityHandle;
    if (handle != null) SurfaceRefreshRegistry.instance.unregister(handle);
    _placementValidityHandle = null;
  }

  void _disposeStages() {
    final stage = _stage;
    _stage = null;
    final accepted = _acceptedStage;
    _acceptedStage = null;
    _acceptedDecision = null;
    if (accepted != null && !identical(stage, accepted)) accepted.dispose();
    stage?.dispose();
  }

  // Whether a live refresh handle was registered since the last restart;
  // only disposal and a restart may drop it.
  bool _debugHandleRegistered = false;

  /// The screen's stage contract, checked after each transition in debug
  /// builds; a broken rule is reported, so no catch can hide it.
  bool _debugCheckStageInvariants({bool shown = false}) {
    if (!mounted) return true;
    void require(bool holds, String rule) {
      if (holds) return;
      FlutterError.reportError(FlutterErrorDetails(
        exception: StateError(rule),
        library: 'restage',
        context: ErrorDescription('while checking the screen stage contract'),
      ));
    }

    final stage = _stage;
    final accepted = _acceptedStage;
    final handle = _placementValidityHandle;
    if (stage != null) {
      require(!stage._disposed, 'The staged stage is disposed.');
      require(stage.transaction.isPending || stage.transaction.isCommitted,
          'The staged stage can no longer paint.');
      final previous = stage.previousStage;
      require(previous == null || !previous._disposed,
          'The stage kept to restore is disposed.');
    }
    require(accepted == null || !accepted._disposed,
        'The accepted stage is disposed.');
    require(!_debugHandleRegistered || handle != null,
        'The live refresh handle was dropped.');
    require(_acceptedAdmission == null || handle != null,
        'An accepted decision has no live refresh handle.');
    require(
        !_showsFallback ||
            placementFallbackFor(_placementResolver) == null ||
            handle != null,
        'A fallback shown with a watch has no live refresh handle.');
    require(
        !shown ||
            stage == null ||
            !identical(stage, accepted) ||
            (_acceptedAdmission?.isCurrent ?? true),
        'A lapsed decision was put on screen.');
    return true;
  }

  @override
  Widget build(BuildContext context) => UserInteractionWatch(
        onInteraction: () => _placementInteracted = true,
        child: _buildContent(context),
      );

  Widget _buildContent(BuildContext context) {
    final error = _unavailableError ??
        (_showDeadlineFallback && _stage == null
            ? _deadlineFallbackError
            : null);
    if (error != null) {
      final load = _surfaceLoad;
      // Only a failure sets the latch, so the deadline's original never reads
      // as advanced.
      final advanced = _loadAdvanced;
      final policy = _unavailable;
      final view = surfaceUnavailableView(policy, advanced: advanced);
      if (view == SurfaceUnavailableView.nothing) {
        return SurfaceLoadPaint(
            load: load,
            onPainted: () => _failLoad(load, error),
            child: const SizedBox.shrink());
      }
      final builder = surfaceUnavailableBuilder(policy, advanced: advanced)!;
      if (_fallbackAttributionEpoch != _resolutionEpoch) {
        _fallbackAttributionEpoch = _resolutionEpoch;
        _fallbackReadOwner?.dispose();
        _fallbackReadOwner = RootAnalyticsRuntime.createPresentation(
          surface: widget.screen.surface.wireName,
          surfaceId: widget.screen.slug,
          owner: this,
        )..markAssignmentUnknown();
        _fallbackMountAttribution =
            captureMountAttribution(_placementDiscovery.declaration?.mount);
        final epoch = _resolutionEpoch;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_isCurrent(epoch) && _showsFallback) {
            _placementDiscovery.markPainted();
          }
        });
      }
      final screen = widget.screen;
      final owner = widget.placementBinding?.eventOwner;
      final epoch = _resolutionEpoch;
      final identity = _eventIdentity;
      return RestageEventDispatcher(
        onEvent: _fallbackEventHandler,
        child: RestageEventEpoch(
          isCurrent: () =>
              mounted &&
              epoch == _resolutionEpoch &&
              identical(identity, _eventIdentity),
          child: guardSurfaceUnavailableWidget(
            debugLabel: screen.slug,
            onFailed: () => _failLoad(load, _policyWidgetFailed),
            child: _hostRecordedEvents(owner, Builder(builder: (context) {
              final fallback = builder(context, error);
              Widget painted(Widget child) => SurfaceLoadPaint(
                  load: load,
                  onPainted: view == SurfaceUnavailableView.original &&
                          error.reason !=
                              SurfaceScreenUnavailableReason.renderFailure
                      ? () => _completeLoadWithOriginal(load)
                      : () => _failLoad(load, error),
                  child: child);
              // A parent-data fallback stays the direct child of its parent.
              if (fallback is ParentDataWidget) return painted(fallback);
              final late = _late;
              return painted(withSourceBadge(
                  () => late == null
                      ? sourceBadgeLabel(null, null)
                      : lateSourceBadgeLabel(late.version),
                  fallback,
                  description: () => late == null
                      ? null
                      : lateSourceBadgeDescription(late.version)));
            })),
          ),
        ),
      );
    }
    final stage = _stage;
    if (stage == null) {
      return widget.loadingBuilder?.call(context) ?? const SizedBox.shrink();
    }
    return withSourceBadge(
        () => sourceBadgeLabel(
            surfaceResolutionSourceFor(stage.resolved), stage.content.version),
        _buildStage(stage));
  }

  Widget _buildStage(_ScreenStage stage) {
    final identity = _eventIdentity;
    return FirstPaintLeaseScope(
      transaction: stage.transaction,
      child: FirstPaintLeaseGuard(
        transaction: stage.transaction,
        armed: true,
        child: RuntimeErrorBoundary(
          key: ValueKey<String>(
            '${stage.content.contentHash}/${stage.content.version}',
          ),
          debugLabel: widget.screen.slug,
          onError: (error, _) {
            markSurfaceDeliveryRenderFailed(stage.resolved);
            _handleRenderFailure(stage, error);
          },
          errorReplacement: (_, __, ___) => const SizedBox.shrink(),
          // Each version is its own stage, so islands key per version.
          child: RestageIslandStage(
            candidate: false,
            child: stage.wrapMeasuredRoot(
              RestagePagerEventScope(
                sink: _pagerSinkForStage(stage),
                child: SurfaceDeliveryPaintBoundary(
                  resolved: stage.resolved,
                  child: _completeOnPaint(
                      stage,
                      DeliveredIconFontLoader.scope(
                        stage.sections.iconFonts,
                        // App code the design shows fires on this stage.
                        child: RestageEventDispatcher(
                          onEvent: stage.appEventHandler ??= (name, value) =>
                              _handleEvent(stage, name, value, fromApp: true),
                          child: RestageEventEpoch(
                            isCurrent: () =>
                                mounted &&
                                identical(_stage, stage) &&
                                identical(identity, _eventIdentity),
                            child: _hostRecordedEvents(
                              widget.placementBinding?.eventOwner,
                              RemoteWidget(
                                runtime: stage.runtime,
                                data: stage.data,
                                widget: placementWidgetNameFor(
                                    stage.resolved, kFlowScreenWidget),
                                onEvent: (name, value) =>
                                    _handleEvent(stage, name, value),
                              ),
                            ),
                          ),
                        ),
                      )),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _completeOnPaint(_ScreenStage stage, Widget child) {
    final load = _surfaceLoad;
    return SurfaceLoadPaint(
        load: load, onPainted: () => _completeLoad(load, stage), child: child);
  }
}

final class _ScreenStage {
  _ScreenStage({
    required this.provenance,
    required this.resolved,
    required this.content,
    required this.runtime,
    required this.data,
    required this.presentation,
    required this.sections,
    required this.local,
    required this.mountAttribution,
  }) {
    assert(() {
      _live += 1;
      return true;
    }());
  }

  final SurfaceScreenRuntimeProvenance provenance;
  final SurfaceSections sections;
  final LocalValues local;
  final Object resolved;
  final SingleSurfaceRenderContent content;
  final Runtime runtime;
  final DynamicContent data;
  late final ContextPublisher contextPublisher = ContextPublisher(data);
  final RootAnalyticsPresentation presentation;
  final MountAttributionSnapshotV1? mountAttribution;
  _ScreenStage? previousStage;
  late final FirstPaintLeaseTransaction transaction;

  // Receives the events app code shown in this stage fires.
  SurfaceEventHandler? appEventHandler;

  MeasurementHostSessionController? _measurementSession;
  var _disposed = false;
  static var _live = 0;

  void attachMeasurementSession(MeasurementHostSessionController session) {
    if (_disposed || _measurementSession != null) {
      unawaited(session.teardown());
      return;
    }
    _measurementSession = session;
    presentation
        .captureDeferredContextOnActivation(session.bindPointEventContext);
  }

  Object? sanitizeAndRecordEvent(Object? rawValue) {
    final measurementSession = _measurementSession;
    if (measurementSession != null) {
      try {
        return measurementSession.sanitizeAndRecordEvent(rawValue);
      } on Object {
        // Measurement must not change the host's ordinary event behavior.
      }
    }
    return MeasurementEventSanitizer.sanitize(rawValue).businessValue;
  }

  Widget wrapMeasuredRoot(Widget child) =>
      _measurementSession?.wrapRootSubtree(child) ?? child;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    assert(() {
      _live -= 1;
      return true;
    }());
    transaction.supersede();
    local.clear();
    final measurementSession = _measurementSession;
    if (measurementSession != null) unawaited(measurementSession.teardown());
    presentation.dispose();
    WidgetsBinding.instance.addPostFrameCallback((_) => runtime.dispose());
  }
}

/// Screen stages built and not yet disposed; counted in debug builds only.
@visibleForTesting
int get debugLiveScreenStages => _ScreenStage._live;

/// Deprecated spelling of [RestageScreen].
///
/// The host widget is named after the `@Screen` annotation that produces
/// what it mounts. Removed at 3.0.
@Deprecated('Use RestageScreen')
typedef RestageSurfaceScreen<E> = RestageScreen<E>;
