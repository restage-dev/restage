import 'dart:async';

import 'package:flutter/material.dart' show Theme;
import 'package:flutter/widgets.dart';
import 'package:restage_material/restage_material_runtime.dart';
import 'package:restage_shared/restage_shared.dart' hide WidgetLibrary;
import 'package:rfw/rfw.dart'
    show
        DynamicContent,
        RemoteWidget,
        Runtime,
        WidgetLibrary,
        decodeLibraryBlob;

import '../delivery/delivered_fonts.dart';
import '../delivery/raced_surface_resolver.dart';
import '../delivery/surface_sections_carrier.dart';
import '../delivery/render_deadline.dart';
import '../delivery/surface_delivery_paint_boundary.dart';
import '../delivery/surface_race.dart';
import '../analytics/root_analytics_context.dart';
import '../authoring/onboarding_event_dispatcher.dart'
    show DeclaredEventDispatcher, SurfaceEventHandler;
import '../events/restage_event.dart' show PagerPageChanged;
import '../flow/flow_descriptors.dart';
import '../flow/flow_runtime_support.dart';
import '../measurement/measurement_event_sanitizer.dart';
import '../measurement/measurement_host_session.dart';
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
import '../runtime/error_boundary.dart';
import '../runtime/first_paint_lease_guard.dart';
import '../runtime/event_demux.dart' show isReservedCommerceEventName;
import '../runtime/installed_widget_vocabulary.dart';
import '../runtime/local_values.dart';
import '../runtime/placement_mount.dart';
import '../runtime/surface_vocabulary.dart';
import '../runtime/restage.dart';
import '../runtime/state_variables.dart'
    show currentDevicePlatform, populateDeviceData, populateThemeData;
import 'surface_screen_runtime_provenance.dart';
import 'surface_screen_unavailable_policy.dart';
import 'surface_screen_types.dart';

/// Category-neutral host for one independently published screen.
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
    required this.unavailable,
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
  }) =>
      GeneratedPlacementDefinition.generated(
        defaultSurface: defaultSurface,
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

  /// The exact generated standalone-screen reference to render.
  final SurfaceScreenRef<E> screen;

  /// The generated default definition and optional named placement.
  @override
  final PlacementMountBinding? placementBinding;

  /// Required behavior if the screen cannot be made available.
  final SurfaceScreenUnavailablePolicy unavailable;

  /// Receives only generated, schema-validated event values.
  final ValueChanged<E>? onEvent;

  /// Optional resolver. The configured default is used when omitted.
  final SurfaceScreenResolver? resolver;

  /// Observes a classified unavailable condition.
  final ValueChanged<SurfaceScreenUnavailableError>? onUnavailable;

  /// Optional content shown while the screen resolves.
  final WidgetBuilder? loadingBuilder;

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
  final Map<String, Object?>? context;

  @override
  State<RestageScreen<E>> createState() => _RestageScreenState<E>();
}

class _RestageScreenState<E> extends State<RestageScreen<E>> {
  _ScreenStage? _stage;
  _ScreenStage? _acceptedStage;
  SurfaceScreenUnavailableError? _unavailableError;
  SurfaceDeliveryObservationCell? _observationCell;
  RenderDeadline? _renderDeadline;

  /// The compiled widget shown because nothing was ready by the deadline.
  bool _showDeadlineFallback = false;
  var _resolutionEpoch = 0;
  int _fallbackAttributionEpoch = -1;
  MountAttributionSnapshotV1? _fallbackMountAttribution;
  var _dependenciesReady = false;
  ContextSnapshot? _context;
  late final SurfaceEventHandler _fallbackEventHandler = _handleFallbackEvent;
  late final bool Function(String eventId) _declares = _declaresEvent;
  Set<String>? _declaredEventIds;

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
    _placementDiscovery.dispose();
    _renderDeadline?.cancel();
    _resolutionEpoch += 1;
    _disposeStage();
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
    // Installing here is what makes a screen swapped into this position
    // render with its own vocabulary.
    widget.screen.provenance.vocabulary.addToInstalled();
    _observationCell = null;
    _declaredEventIds = null;
    _placementInteracted = false;
    final epoch = ++_resolutionEpoch;
    _renderDeadline?.cancel();
    _renderDeadline = RenderDeadline.start(Restage.renderDeadline);
    _disposeStage();
    setState(() {
      _unavailableError = null;
      _showDeadlineFallback = false;
    });
    unawaited(_resolveInScope(epoch));
  }

  Future<void> _resolveInScope(int epoch) => withSurfaceDeliveryObservations(
        cell: _presentationObservations(),
        resolve: () => _resolve(epoch),
      );

  SurfaceRefreshHandle? _placementValidityHandle;
  bool _placementInteracted = false;
  SurfaceScreenResolver? _placementResolver;
  PlacementMountBinding? _capturedBinding;
  int _placementGeneration = -1;
  late final _placementDiscovery = PlacementHostDiscovery(
      configurationGeneration: () => Restage.configurationGeneration,
      discovery: () => Restage.placementDiscovery);

  SurfaceScreenResolver _resolver() {
    final original = widget.resolver ?? Restage.defaultSurfaceScreenResolver;
    final binding = widget.placementBinding;
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
          if (_acceptedStage case final stage?) {
            _registerPlacementValidity(stage);
          }
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
      if (isRefresh) stage.previousStage = _acceptedStage;
      bindSurfaceDeliveryMountAttribution(resolved, stage.mountAttribution);
      stage.transaction = FirstPaintLeaseTransaction(
        canCommit: () =>
            _isCurrent(epoch) &&
            identical(_stage, stage) &&
            (stage.previousStage == null ||
                (identical(stage.previousStage, _acceptedStage) &&
                    _canRefreshPlacement())) &&
            (surfaceAssignmentLeaseFor(resolved)?.isCurrent ?? true) &&
            (placementAdmissionFor(resolved)?.isCurrent ?? true),
        isInvalidatedByIdentityReset: () =>
            !((surfaceAssignmentLeaseFor(resolved)?.isCurrent ?? true) &&
                (placementAdmissionFor(resolved)?.isCurrent ?? true)),
        commit: () {},
        onPainted: () {
          _placementDiscovery.markPainted();
          _acceptedStage = stage;
          _registerPlacementValidity(stage);
        },
        afterCommit: () {
          if (identical(_stage, stage)) {
            stage.presentation.activate();
            final previous = stage.previousStage;
            stage.previousStage = null;
            if (previous != null) {
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => previous.dispose());
            }
          }
        },
        afterRejection: () {
          if (!_isCurrent(epoch) || !identical(_stage, stage)) return;
          if (stage.previousStage != null) {
            _restorePreviousStage(stage);
            return;
          }
          _disposeStage();
          unawaited(_resolveLocalAfterInvalidation(epoch));
        },
      );
      await _attachMeasurementSession(stage, resolved);
      if (isRefresh &&
          (!_canRefreshPlacement() ||
              (placementAdmissionFor(resolved)?.isAssigned ?? false))) {
        stage.dispose();
        return;
      }
      if (!_isCurrent(epoch) ||
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
        _showDeadlineFallback = false;
      });
      if (previous != null && !isRefresh) {
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

  void _registerPlacementValidity(_ScreenStage stage) {
    final previous = _placementValidityHandle;
    if (previous != null) {
      SurfaceRefreshRegistry.instance.acceptedPlacementChanged(previous);
      SurfaceRefreshRegistry.instance.localValidityChanged(previous);
      return;
    }
    final admission = placementAdmissionFor(stage.resolved);
    if (admission == null && placementFallbackFor(_placementResolver) == null) {
      return;
    }
    final handle = SurfaceRefreshHandle(
        surface: SurfaceRef(
            surfaceType: stage.content.surface.wireName,
            slug: stage.content.slug),
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
          await accepted?.invalidateCache();
        },
        probePlacement: (rendered) => probeRenderedPlacement(
            _acceptedAdmission, _placementResolver, rendered),
        invalidateLocal: () async {
          final resolver = _placementResolver;
          if (resolver is! PlacementScreenResolver) return;
          final original = await resolver.original();
          if (!mounted ||
              !identical(_stage, _acceptedStage) ||
              _placementInteracted ||
              (_acceptedAdmission?.isAssigned ?? false)) {
            return;
          }
          if (original != null) {
            await _stageResolved(++_resolutionEpoch, original);
          } else {
            _disposeStage();
            _fail(++_resolutionEpoch, _missing);
          }
        });
    _placementValidityHandle = handle;
    SurfaceRefreshRegistry.instance.register(handle);
  }

  PlacementDeliveryAdmission? get _acceptedAdmission => _acceptedStage == null
      ? null
      : placementAdmissionFor(_acceptedStage!.resolved);

  bool _canRefreshPlacement() =>
      mounted &&
      _acceptedStage != null &&
      !_placementInteracted &&
      !(_acceptedAdmission?.isAssigned ?? false);

  Future<void> _refreshPlacement() async {
    final previous = _acceptedStage;
    final resolver = _placementResolver;
    if (previous == null ||
        resolver is! PlacementScreenResolver ||
        !_canRefreshPlacement()) {
      return;
    }
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
      if ((candidate?.isAssigned ?? false) ||
          (_acceptedAdmission?.matchesDecision(candidate) ?? false)) {
        return;
      }
      await _stageResolved(epoch, fresh, isRefresh: true);
    } on Object {
      // A failed refresh keeps the accepted presentation.
    }
  }

  void _restorePreviousStage(_ScreenStage rejected) {
    final previous = rejected.previousStage;
    if (previous == null) return;
    rejected.previousStage = null;
    setState(() => _stage = previous);
    rejected.dispose();
    _populateData();
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
      deadline: deadline,
      fresh: fresh,
      bestLocal: raced == null ? () async => null : () => raced.bestLocal(key!),
      onLateFresh: (resolved) => _presentLateFresh(resolved, epoch, report),
    );
    if (!_isCurrent(epoch)) return null;
    switch (outcome) {
      case RaceLocal(:final freshError?):
        // A hosted response that failed its checks never falls back.
        report(null);
        throw freshError;
      case RaceFresh(:final value) || RaceLocal(:final value):
        report(value);
        return value;
      case RaceNone(freshPending: true):
        if (!widget.unavailable.hide) {
          report(null);
          setState(() => _showDeadlineFallback = true);
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
    void Function(Object?) report,
  ) {
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
  Future<void> _attachMeasurementSession(
    _ScreenStage stage,
    Object resolved,
  ) async {
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
      library = decodeLibraryBlob(content.blob);
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

  void _handleEvent(_ScreenStage stage, String name, Object? value) {
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
    } on Object catch (error) {
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

  bool _declaresEvent(String eventId) => (_declaredEventIds ??= {
        for (final event in widget.screen.provenance.eventSchema.events)
          event.id,
      })
          .contains(eventId);

  void _handleRenderFailure(_ScreenStage stage, Object error) {
    if (!identical(_stage, stage)) return;
    _forgetStoredCandidate();
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
    if (pending?.previousStage != null) {
      _restorePreviousStage(pending!);
      return;
    }
    _disposeStage();
    setState(() => _unavailableError = error);
    widget.onUnavailable?.call(error);
  }

  bool _isCurrent(int epoch) => mounted && epoch == _resolutionEpoch;

  static const SurfaceScreenUnavailableError _deadlineFallbackError =
      SurfaceScreenUnavailableError(
    reason: SurfaceScreenUnavailableReason.missing,
    message: 'No content was ready by the render deadline.',
  );

  void _disposeStage() {
    final handle = _placementValidityHandle;
    if (handle != null) SurfaceRefreshRegistry.instance.unregister(handle);
    _placementValidityHandle = null;
    final stage = _stage;
    _stage = null;
    final accepted = _acceptedStage;
    _acceptedStage = null;
    if (accepted != null && !identical(stage, accepted)) accepted.dispose();
    stage?.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _unavailableError ??
        (_showDeadlineFallback && _stage == null
            ? _deadlineFallbackError
            : null);
    if (error != null) {
      if (widget.unavailable.hide) return const SizedBox.shrink();
      if (_fallbackAttributionEpoch != _resolutionEpoch) {
        _fallbackAttributionEpoch = _resolutionEpoch;
        _fallbackMountAttribution =
            captureMountAttribution(_placementDiscovery.declaration?.mount);
      }
      final screen = widget.screen;
      return DeclaredEventDispatcher(
        surfaceName: screen.slug,
        declares: _declares,
        onEvent: _fallbackEventHandler,
        child: Builder(
          builder: (context) =>
              widget.unavailable.fallbackBuilder!(context, error),
        ),
      );
    }
    final stage = _stage;
    if (stage == null) {
      return widget.loadingBuilder?.call(context) ?? const SizedBox.shrink();
    }
    return FirstPaintLeaseScope(
      transaction: stage.transaction,
      child: FirstPaintLeaseGuard(
        transaction: stage.transaction,
        armed: true,
        child: RuntimeErrorBoundary(
          key: ValueKey<String>(
            '${stage.content.contentHash}/${stage.content.version}',
          ),
          onError: (error, _) {
            markSurfaceDeliveryRenderFailed(stage.resolved);
            _handleRenderFailure(stage, error);
          },
          errorReplacement: (_, __, ___) => const SizedBox.shrink(),
          child: stage.wrapMeasuredRoot(
            RestagePagerEventScope(
              sink: _pagerSinkForStage(stage),
              child: SurfaceDeliveryPaintBoundary(
                resolved: stage.resolved,
                child: DeliveredIconFontLoader.scope(
                  stage.sections.iconFonts,
                  child: Listener(
                      onPointerDown: (_) => _placementInteracted = true,
                      child: RemoteWidget(
                        runtime: stage.runtime,
                        data: stage.data,
                        widget: placementWidgetNameFor(
                            stage.resolved, kFlowScreenWidget),
                        onEvent: (name, value) =>
                            _handleEvent(stage, name, value),
                      )),
                ),
              ),
            ),
          ),
        ),
      ),
    );
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
  });

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

  MeasurementHostSessionController? _measurementSession;
  var _disposed = false;

  void attachMeasurementSession(MeasurementHostSessionController session) {
    if (_disposed || _measurementSession != null) {
      unawaited(session.teardown());
      return;
    }
    _measurementSession = session;
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
    transaction.supersede();
    local.clear();
    final measurementSession = _measurementSession;
    if (measurementSession != null) unawaited(measurementSession.teardown());
    presentation.dispose();
    WidgetsBinding.instance.addPostFrameCallback((_) => runtime.dispose());
  }
}

/// Deprecated spelling of [RestageScreen].
///
/// The host widget is named after the `@Screen` annotation that produces
/// what it mounts. Removed at 3.0.
@Deprecated('Use RestageScreen')
typedef RestageSurfaceScreen<E> = RestageScreen<E>;
