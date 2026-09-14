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

import '../analytics/root_analytics_context.dart';
import '../events/restage_event.dart' show PagerPageChanged;
import '../flow/flow_descriptors.dart';
import '../flow/flow_runtime_support.dart';
import '../measurement/measurement_event_sanitizer.dart';
import '../measurement/measurement_host_session.dart';
import '../resolver/surface_delivery_observations.dart'
    show
        SurfaceDeliveryObservationCell,
        readSurfaceDeliveryObservations,
        requestingViewShortestLogicalSide,
        withSurfaceDeliveryObservations;
import '../runtime/context_data.dart';
import '../runtime/error_boundary.dart';
import '../runtime/event_demux.dart' show isReservedCommerceEventName;
import '../runtime/installed_widget_vocabulary.dart';
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
final class RestageScreen<E> extends StatefulWidget {
  /// Creates a standalone generated-screen host.
  const RestageScreen({
    super.key,
    required this.screen,
    required this.unavailable,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
    this.context,
  });

  /// The exact generated standalone-screen reference to render.
  final SurfaceScreenRef<E> screen;

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
  SurfaceScreenUnavailableError? _unavailableError;
  SurfaceDeliveryObservationCell? _observationCell;
  var _resolutionEpoch = 0;
  var _dependenciesReady = false;
  ContextSnapshot? _context;

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
        !identical(oldWidget.resolver, widget.resolver)) {
      _restart();
      return;
    }
    _stage?.contextPublisher.publishSnapshot(_context);
  }

  @override
  void dispose() {
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
    final epoch = ++_resolutionEpoch;
    _disposeStage();
    setState(() => _unavailableError = null);
    unawaited(_resolveInScope(epoch));
  }

  Future<void> _resolveInScope(int epoch) => withSurfaceDeliveryObservations(
        cell: _presentationObservations(),
        resolve: () => _resolve(epoch),
      );

  Future<void> _resolve(int epoch) async {
    final screen = widget.screen;
    final provenance = screen.provenance;

    final resolver = widget.resolver ?? Restage.defaultSurfaceScreenResolver;
    final ResolvedSurfaceScreen resolved;
    try {
      resolved = await resolver.resolve(screen);
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

    try {
      final stage = _validateAndBuildStage(provenance, resolved);
      await _attachMeasurementSession(stage, resolved);
      if (!_isCurrent(epoch)) {
        stage.dispose();
        return;
      }
      setState(() => _stage = stage);
      _populateData();
    } on SurfaceScreenUnavailableError catch (error) {
      _fail(epoch, error);
    } on Object catch (error) {
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

  /// Opens Measurement only after the host has independently validated the
  /// exact resolved artifact, and before that artifact can enter the tree.
  ///
  /// The controller owns all host-independent resolution and degrades to an
  /// inert session. Its failure must never make a validated screen unavailable.
  Future<void> _attachMeasurementSession(
    _ScreenStage stage,
    ResolvedSurfaceScreen resolved,
  ) async {
    try {
      stage.attachMeasurementSession(
        await MeasurementHostSessionController.openForResolvedArtifact(
          resolved,
          presentationObservations: _observationCell?.read,
        ),
      );
    } on Object {
      // Measurement is fail-closed and observational. A construction failure
      // leaves the independently validated screen on its existing path.
    }
  }

  _ScreenStage _validateAndBuildStage(
    SurfaceScreenRuntimeProvenance provenance,
    ResolvedSurfaceScreen resolved,
  ) {
    // The host re-runs the same validation the resolver ran. A resolver is a
    // replaceable seam, so the host never takes its word for identity,
    // contract, content hash, or bundled provenance.
    provenance.validateResolved(resolved);

    final capabilityVerdict = BlobRenderCapabilityGate.evaluate(
      required: provenance.capabilities,
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
      library = decodeLibraryBlob(resolved.blob);
    } on Object catch (error) {
      throw SurfaceScreenUnavailableError(
        reason: SurfaceScreenUnavailableReason.invalidPayload,
        message: 'The resolved screen blob cannot be decoded.',
        cause: error,
      );
    }

    final runtime = flowScreenRuntime(library);
    final presentation = RootAnalyticsRuntime.createPresentation(
      surface: provenance.surface.wireName,
      surfaceId: provenance.slug,
      sourceKind: SurfaceScreenRuntimeProvenance.sourceKind,
      payloadKind: SurfaceScreenRuntimeProvenance.payloadKind,
    );
    presentation.stage(
      surfaceVersion:
          (resolved.publishedRevision ?? provenance.contractVersion).toString(),
    );
    return _ScreenStage(
      provenance: provenance,
      resolved: resolved,
      runtime: runtime,
      data: DynamicContent(),
      presentation: presentation,
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

  void _handleEvent(_ScreenStage stage, String name, Object? value) {
    if (!identical(_stage, stage)) return;
    if (isReservedCommerceEventName(name)) return;
    try {
      final arguments = normalizeEventArgs(
        stage.sanitizeAndRecordEvent(value),
      );
      stage.provenance.eventSchema.validateEvent(name, arguments);
      final callback = widget.onEvent;
      if (callback == null) {
        throw const FormatException('No typed event callback is installed.');
      }
      final event =
          widget.screen.eventContract.decodeValidated(name, arguments);
      stage.presentation.runWithEventContext(() => callback(event));
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

  void _handleRenderFailure(_ScreenStage stage, Object error) {
    if (!identical(_stage, stage)) return;
    _fail(
      _resolutionEpoch,
      SurfaceScreenUnavailableError(
        reason: SurfaceScreenUnavailableReason.renderFailure,
        message: 'The screen failed while rendering.',
        cause: error,
      ),
    );
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
    _disposeStage();
    setState(() => _unavailableError = error);
    widget.onUnavailable?.call(error);
  }

  bool _isCurrent(int epoch) => mounted && epoch == _resolutionEpoch;

  void _disposeStage() {
    final stage = _stage;
    _stage = null;
    stage?.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _unavailableError;
    if (error != null) {
      if (widget.unavailable.hide) return const SizedBox.shrink();
      return widget.unavailable.fallbackBuilder!(context, error);
    }
    final stage = _stage;
    if (stage == null) {
      return widget.loadingBuilder?.call(context) ?? const SizedBox.shrink();
    }
    return RuntimeErrorBoundary(
      key: ValueKey<String>(
        '${stage.resolved.contentHash}/${stage.resolved.publishedRevision ?? stage.resolved.contractVersion}',
      ),
      onFirstBuildSuccess: () {
        if (identical(_stage, stage)) stage.presentation.activate();
      },
      onError: (error, _) => _handleRenderFailure(stage, error),
      errorReplacement: (_, __, ___) => const SizedBox.shrink(),
      child: stage.wrapMeasuredRoot(
        RestagePagerEventScope(
          sink: _pagerSinkForStage(stage),
          child: RemoteWidget(
            runtime: stage.runtime,
            data: stage.data,
            widget: kFlowScreenWidget,
            onEvent: (name, value) => _handleEvent(stage, name, value),
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
    required this.runtime,
    required this.data,
    required this.presentation,
  });

  final SurfaceScreenRuntimeProvenance provenance;
  final ResolvedSurfaceScreen resolved;
  final Runtime runtime;
  final DynamicContent data;
  late final ContextPublisher contextPublisher = ContextPublisher(data);
  final RootAnalyticsPresentation presentation;

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
