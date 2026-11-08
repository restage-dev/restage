import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:restage_shared/restage_shared.dart' show Surface;

import '../refresh/surface_refresh_trigger.dart';
import '../runtime/context_data.dart';
import '../runtime/surface_unavailable_policy.dart';
import 'flow_descriptors.dart';
import 'flow_resolver.dart';
import 'flow_seed.dart';
import 'flow_transitions.dart';
import 'restage_surface_flow.dart';
import 'system_back_policy.dart';

/// Backward-compatible onboarding-only facade over [RestageFlowGraph].
///
/// Generated onboarding descriptors continue to work unchanged. A descriptor
/// for another surface fails closed before any resolver or refresh work starts.
final class RestageOnboarding<R> extends StatefulWidget {
  /// Creates an onboarding flow surface.
  const RestageOnboarding({
    super.key,
    required this.flow,
    this.initialState,
    this.fallbackBuilder,
    this.errorBuilder,
    this.actions,
    this.installedSignalNames = const <String>{},
    this.resolver,
    this.onFlowUnavailable,
    this.onComplete,
    this.loadingBuilder,
    this.transition,
    this.systemBack = SystemBackPolicy.popHost,
    this.liveRefresh,
    this.context,
  });

  /// Generated flow descriptor to load.
  final SurfaceFlowRef<R> flow;

  /// Optional host-supplied initial flow-state values.
  final FlowSeed? initialState;

  /// Shown in place of the compiled original when no published, saved or
  /// bundled version of the flow can render. Null shows the compiled
  /// original; without one, nothing shows while the host waits for content.
  final WidgetBuilder? fallbackBuilder;

  /// Shown instead of restarting the user when the flow fails after they
  /// made progress in this load, and for any failure when neither a fallback
  /// nor a compiled original is left to show. Null shows the fallback, the
  /// original, or nothing.
  final Widget Function(BuildContext context, FlowUnavailableError error)?
      errorBuilder;

  /// Optional host action registry for action-backed flow transitions. A new
  /// registry with the same contracts takes effect without reloading; one with
  /// changed contracts reloads the flow.
  final FlowActionRegistry? actions;

  /// Installed custom-event and host-signal names reviewed by the host.
  final Set<String> installedSignalNames;

  /// Optional resolver used to load the flow descriptor. A new resolver object
  /// reloads the flow, so hold one rather than creating it in `build`.
  final FlowResolver? resolver;

  /// Called when the flow cannot be made available.
  final void Function(FlowUnavailableError error)? onFlowUnavailable;

  /// Called with the typed terminal result after declaration filtering.
  final void Function(R result)? onComplete;

  /// Builder shown while the flow is loading.
  final WidgetBuilder? loadingBuilder;

  /// Overrides the screen transition. Defaults to the platform page
  /// transition, which follows the app's `pageTransitionsTheme`.
  final FlowTransitionBuilder? transition;

  /// What happens after in-flow back is exhausted.
  final SystemBackPolicy systemBack;

  /// Per-widget live-refresh override.
  final Set<SurfaceRefreshTrigger>? liveRefresh;

  /// Host-supplied render data, published to each screen as `data.context.*`.
  ///
  /// Maps and lists can nest 32 levels deep below the root. A context holds up
  /// to 10,000 values, counting the root, and each update reads at most 100,000
  /// map entries or list elements. Null map values are left out, and null list
  /// elements are removed so the list closes up. In debug builds, an invalid
  /// value, an unreadable collection, or a value over a limit throws; in
  /// release builds the SDK reports it and leaves that value or collection out.
  /// The SDK copies the values when you pass them. Passing equal values doesn't
  /// update the surface; null removes all host data.
  final Map<String, Object?>? context;

  @override
  State<RestageOnboarding<R>> createState() => _RestageOnboardingState<R>();
}

class _RestageOnboardingState<R> extends State<RestageOnboarding<R>> {
  String? _reportedUnsupportedIdentity;
  int _unavailableCallbackGeneration = 0;
  ContextSnapshot? _context;

  void _refreshContext() {
    final raw = widget.context;
    _context = raw == null ? null : ContextSnapshot.of(raw, previous: _context);
  }

  bool get _acceptsFlow => widget.flow.surfaceType == Surface.onboarding;

  FlowUnavailableError? get _unsupportedError {
    if (_acceptsFlow) return null;
    return FlowUnavailableError(
      flowId: widget.flow.id,
      flowVersion: widget.flow.version,
      reason: 'unsupported_surface_type',
      message: 'RestageOnboarding accepts onboarding flows only.',
    );
  }

  String? get _unsupportedIdentity {
    if (_acceptsFlow) return null;
    return '${widget.flow.surfaceType.wireName}\u0000'
        '${widget.flow.id}\u0000${widget.flow.version}';
  }

  @override
  void initState() {
    super.initState();
    _refreshContext();
    _scheduleUnavailableCallback();
  }

  @override
  void didUpdateWidget(RestageOnboarding<R> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _refreshContext();
    if (oldWidget.flow.surfaceType != widget.flow.surfaceType ||
        oldWidget.flow.id != widget.flow.id ||
        oldWidget.flow.version != widget.flow.version) {
      _reportedUnsupportedIdentity = null;
    }
    _scheduleUnavailableCallback();
  }

  void _scheduleUnavailableCallback() {
    final error = _unsupportedError;
    final identity = _unsupportedIdentity;
    if (error == null || identity == null) {
      _unavailableCallbackGeneration += 1;
      _reportedUnsupportedIdentity = null;
      return;
    }
    if (_reportedUnsupportedIdentity == identity) return;
    _reportedUnsupportedIdentity = identity;
    final generation = ++_unavailableCallbackGeneration;
    scheduleMicrotask(() {
      if (!mounted ||
          generation != _unavailableCallbackGeneration ||
          _unsupportedIdentity != identity) {
        return;
      }
      widget.onFlowUnavailable?.call(error);
    });
  }

  @override
  void dispose() {
    _unavailableCallbackGeneration += 1;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _unsupportedError;
    if (error != null) {
      // Nothing loaded, so nothing advanced.
      final builder = surfaceUnavailableBuilder(
          SurfaceUnavailablePolicy<FlowUnavailableError>(
              fallbackBuilder: widget.fallbackBuilder,
              errorBuilder: widget.errorBuilder),
          advanced: false);
      if (builder == null) return const SizedBox.shrink();
      // Nothing loaded, so a builder that throws only shows nothing.
      return guardSurfaceUnavailableWidget(
          debugLabel: widget.flow.id,
          onFailed: () {},
          child: Builder(builder: (context) => builder(context, error)));
    }
    return RestageContextSnapshotScope(
      snapshot: _context,
      child: RestageFlowGraph<R>(
        flow: widget.flow,
        initialState: widget.initialState,
        fallbackBuilder: widget.fallbackBuilder,
        errorBuilder: widget.errorBuilder,
        actions: widget.actions,
        installedSignalNames: widget.installedSignalNames,
        resolver: widget.resolver,
        onFlowUnavailable: widget.onFlowUnavailable,
        onComplete: widget.onComplete,
        loadingBuilder: widget.loadingBuilder,
        transition: widget.transition,
        systemBack: widget.systemBack,
        liveRefresh: widget.liveRefresh,
        host: 'RestageOnboarding',
      ),
    );
  }
}
