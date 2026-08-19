import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:restage_shared/restage_shared.dart' hide WidgetLibrary;
import 'package:rfw/rfw.dart'
    show
        DynamicContent,
        RemoteWidget,
        Runtime,
        WidgetLibrary,
        decodeLibraryBlob;

import '../analytics/root_analytics_context.dart';
import '../flow/flow_descriptors.dart';
import '../flow/flow_runtime_support.dart';
import '../runtime/builtin_catalog_capabilities.dart';
import '../runtime/error_boundary.dart';
import '../runtime/library_runtime_registry.dart';
import '../runtime/restage.dart';
import '../runtime/state_variables.dart' show PriceInfo;
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
final class RestageSurfaceScreen<E> extends StatefulWidget {
  /// Creates a standalone generated-screen host.
  const RestageSurfaceScreen({
    super.key,
    required this.screen,
    required this.unavailable,
    this.onEvent,
    this.resolver,
    this.onUnavailable,
    this.loadingBuilder,
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

  @override
  State<RestageSurfaceScreen<E>> createState() =>
      _RestageSurfaceScreenState<E>();
}

class _RestageSurfaceScreenState<E> extends State<RestageSurfaceScreen<E>> {
  late final FlowScreenLibraries _libraries;

  _ScreenStage? _stage;
  SurfaceScreenUnavailableError? _unavailableError;
  var _resolutionEpoch = 0;
  var _dependenciesReady = false;

  @override
  void initState() {
    super.initState();
    _libraries = FlowScreenLibraries();
    _restart();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dependenciesReady = true;
    _populateData();
  }

  @override
  void didUpdateWidget(RestageSurfaceScreen<E> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.screen, widget.screen) ||
        !identical(oldWidget.resolver, widget.resolver)) {
      _restart();
    }
  }

  @override
  void dispose() {
    _resolutionEpoch += 1;
    _disposeStage();
    super.dispose();
  }

  void _restart() {
    final epoch = ++_resolutionEpoch;
    _disposeStage();
    setState(() => _unavailableError = null);
    unawaited(_resolve(epoch));
  }

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
      installed: InstalledCapability(
        builtInCatalogVersion: RestageBuiltInCatalogCapabilities.currentVersion,
        installedLibraries: LibraryRuntimeRegistry.installedSnapshot(),
      ),
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

    final runtime = _libraries.runtimeFor(library);
    final presentation = RootAnalyticsRuntime.createPresentation(
      surface: provenance.surface.wireName,
      surfaceId: provenance.slug,
      sourceKind: SurfaceScreenRuntimeProvenance.sourceKind,
      payloadKind: SurfaceScreenRuntimeProvenance.payloadKind,
    );
    final assignment = resolved.assignment;
    presentation.stage(
      surfaceVersion:
          (resolved.publishedRevision ?? provenance.contractVersion).toString(),
      experimentId: assignment?.experimentId,
      variantId: assignment?.variantId,
      experimentEpoch: assignment?.experimentEpoch,
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
    populateFlowScreenData(
      context,
      stage.data,
      priceQueries: const <String, PriceInfo>{},
      includeInheritedData: _dependenciesReady,
    );
  }

  void _handleEvent(_ScreenStage stage, String name, Object? value) {
    if (!identical(_stage, stage)) return;
    try {
      final arguments = normalizeEventArgs(value);
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
      child: RemoteWidget(
        runtime: stage.runtime,
        data: stage.data,
        widget: kFlowScreenWidget,
        onEvent: (name, value) => _handleEvent(stage, name, value),
      ),
    );
  }
}

final class _ScreenStage {
  const _ScreenStage({
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
  final RootAnalyticsPresentation presentation;

  void dispose() {
    presentation.dispose();
    WidgetsBinding.instance.addPostFrameCallback((_) => runtime.dispose());
  }
}
