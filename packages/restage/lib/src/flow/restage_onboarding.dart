import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:restage_shared/restage_shared.dart' show Surface;

import '../refresh/surface_refresh_trigger.dart';
import '../runtime/context_data.dart';
import 'flow_chrome.dart';
import 'flow_descriptors.dart';
import 'flow_resolver.dart';
import 'flow_seed.dart';
import 'flow_transitions.dart';
import 'restage_surface_flow.dart';
import 'system_back_policy.dart';

export 'restage_surface_flow.dart'
    show FlowUnavailableBuilder, FlowUnavailablePolicy;

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
    this.liveRefresh,
    this.context,
  });

  /// Generated flow descriptor to load.
  final SurfaceFlowRef<R> flow;

  /// Optional host-supplied initial flow-state values.
  final FlowSeed? initialState;

  /// Required policy for unavailable flows.
  final FlowUnavailablePolicy unavailable;

  /// Optional host action registry for action-backed flow transitions.
  final FlowActionRegistry? actions;

  /// Installed custom-event and host-signal names reviewed by the host.
  final Set<String> installedSignalNames;

  /// Optional resolver used to load the flow descriptor.
  final FlowResolver? resolver;

  /// Called when the flow cannot be made available.
  final void Function(FlowUnavailableError error)? onFlowUnavailable;

  /// Called with the typed terminal result after declaration filtering.
  final void Function(R result)? onComplete;

  /// Builder shown while the flow is loading.
  final WidgetBuilder? loadingBuilder;

  /// Overrides the screen transition.
  final FlowTransitionBuilder? transition;

  /// What happens after in-flow back is exhausted.
  final SystemBackPolicy systemBack;

  /// Whether to show the default skip affordance.
  final bool enableSkip;

  /// Visual tokens for the built-in chrome.
  final FlowChromeTheme? chromeTheme;

  /// Whether built-in chrome frames the flow persistently.
  final bool persistentChrome;

  /// Supplies the back affordance widget.
  final FlowChromeAffordanceBuilder? backBuilder;

  /// Supplies the skip affordance widget.
  final FlowChromeAffordanceBuilder? skipBuilder;

  /// Owns the per-screen chrome layout.
  final FlowChromeBuilder? chromeBuilder;

  /// Frames the whole flow.
  final FlowPersistentChromeBuilder? persistentChromeBuilder;

  /// Per-widget live-refresh override.
  final Set<SurfaceRefreshTrigger>? liveRefresh;

  /// Host-supplied render data, published to each screen as `data.context.*`.
  ///
  /// Values support 32 collection levels below the root, 10,000 retained
  /// normalized nodes including the root, and 100,000 inspected map entries or
  /// list elements per normalization. Null map values are omitted; null list
  /// elements are dropped and lists compact. Invalid values, unreadable
  /// collections, and exceeded limits throw in debug. Release reports
  /// diagnostics and omits the offending value or collection. Accepted input
  /// is normalized and copied synchronously. Equal normalized snapshots issue
  /// no renderer update; null withdraws the namespace.
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
      if (widget.unavailable.isFallback) {
        return widget.unavailable.fallbackBuilder!(context, error);
      }
      return const SizedBox.shrink();
    }
    return RestageContextSnapshotScope(
      snapshot: _context,
      child: RestageFlowGraph<R>(
        flow: widget.flow,
        initialState: widget.initialState,
        unavailable: widget.unavailable,
        actions: widget.actions,
        installedSignalNames: widget.installedSignalNames,
        resolver: widget.resolver,
        onFlowUnavailable: widget.onFlowUnavailable,
        onComplete: widget.onComplete,
        loadingBuilder: widget.loadingBuilder,
        transition: widget.transition,
        systemBack: widget.systemBack,
        enableSkip: widget.enableSkip,
        chromeTheme: widget.chromeTheme,
        persistentChrome: widget.persistentChrome,
        backBuilder: widget.backBuilder,
        skipBuilder: widget.skipBuilder,
        chromeBuilder: widget.chromeBuilder,
        persistentChromeBuilder: widget.persistentChromeBuilder,
        liveRefresh: widget.liveRefresh,
      ),
    );
  }
}
