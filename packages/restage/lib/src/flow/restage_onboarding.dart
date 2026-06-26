import 'dart:async';

import 'package:flutter/widgets.dart';

import '../authoring/onboarding_event_dispatcher.dart';
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

  @override
  State<RestageOnboarding<R>> createState() => _RestageOnboardingState<R>();
}

class _RestageOnboardingState<R> extends State<RestageOnboarding<R>> {
  RestageFlowController<R>? _controller;
  FlowUnavailableError? _unavailableError;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(RestageOnboarding<R> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.flow, widget.flow) ||
        !identical(oldWidget.resolver, widget.resolver) ||
        !identical(oldWidget.actions, widget.actions)) {
      _start();
    }
  }

  void _start() {
    _disposeController();
    _unavailableError = null;
    late final RestageFlowController<R> controller;
    controller = RestageFlowController<R>(
      flow: widget.flow,
      resolver: widget.resolver ?? Restage.defaultFlowResolver,
      initialState: widget.initialState,
      actions: widget.actions,
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

  void _disposeController() {
    final controller = _controller;
    if (controller == null) return;
    controller.dispose();
    if (identical(_controller, controller)) {
      _controller = null;
    }
  }

  void _handleAuthoredEvent(String eventId, Object? value) {
    // Normalize through the same point the RFW render paths use so a scalar
    // authored-event value reaches the controller in the canonical shape and a
    // flow `.capture()` resolves identically on the local-Dart path.
    _controller?.handleEvent(eventId, normalizeEventArgs(value));
  }

  @override
  void dispose() {
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
    return RestageOnboardingEventDispatcher(
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
    );
  }
}
