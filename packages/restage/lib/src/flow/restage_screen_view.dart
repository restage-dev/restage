import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';
import 'package:rfw/rfw.dart';

import '../runtime/error_boundary.dart';
import '../runtime/state_variables.dart';
import 'flow_controller.dart';
import 'flow_runtime_support.dart';

/// A lower-level rendering surface that renders a [RestageFlowController]'s
/// **current screen only** — the single decoded screen plus its events — with
/// no transitions, no kept-mounted back-stack, and no chrome.
///
/// This sits below [RestageFlowView] on the customization ladder: for hosts that
/// want more control than the full surface but not full DIY. The controller
/// stays the single source of truth (it owns the server-driven topology, A/B,
/// OTA, and the four runtime safety invariants); this surface only renders the
/// current screen in its own isolated [Runtime] + [DynamicContent], behind the
/// fail-closed [RuntimeErrorBoundary], and routes the screen's events back
/// through [RestageFlowController.handleEvent].
///
/// **Bring-your-own-driver.** Pair this with your own switcher: drive a
/// [RestageFlowController], render each screen through a `RestageScreenView`,
/// and supply your own transitions, back affordance, and chrome around it. You
/// keep the controller's server-driven topology/experiments/OTA while owning the
/// presentation entirely. Because every screen still renders through the
/// controller's fail-closed boundary, this is the *safe* low-level path — there
/// is no controller-free "render an arbitrary blob" escape hatch, which would
/// bypass the runtime's safety invariants.
///
/// **Transitions.** Because this renders the controller's *current* screen, it
/// composes with incoming-style transitions (animate the new screen in on each
/// advance; the old one is replaced). A two-screens-visible (opposing-slide)
/// cross-transition needs the outgoing screen too — use
/// [RestageFlowView] with a `transition`, which owns the kept-mounted stack.
///
/// This API is [experimental] and may change.
@experimental
final class RestageScreenView<R> extends StatefulWidget {
  /// Creates a single-screen rendering surface bound to [controller].
  const RestageScreenView({
    super.key,
    required this.controller,
    this.onRuntimeError,
    this.loadingBuilder,
    this.priceQueries = const {},
  });

  /// The flow brain whose current screen this surface renders.
  final RestageFlowController<R> controller;

  /// Called when the current screen's subtree throws during build. The owner
  /// decides any host-facing response; the controller has already failed closed.
  final void Function(Object error, StackTrace stack)? onRuntimeError;

  /// Built when there is no current screen to render — before the first screen
  /// loads, while crossing a sub-flow boundary, or after the flow fails closed.
  final WidgetBuilder? loadingBuilder;

  /// Map of productId -> live [PriceInfo] for paywall blobs rendered as flow
  /// screens.
  final Map<String, PriceInfo> priceQueries;

  @override
  State<RestageScreenView<R>> createState() => _RestageScreenViewState<R>();
}

class _RestageScreenViewState<R> extends State<RestageScreenView<R>> {
  late final FlowScreenLibraries _libraries;

  Runtime? _runtime;
  DynamicContent? _data;
  int? _entryId;
  bool _dependenciesReady = false;

  @override
  void initState() {
    super.initState();
    _libraries = FlowScreenLibraries();
    widget.controller.addListener(_controllerChanged);
    _sync();
  }

  @override
  void didUpdateWidget(RestageScreenView<R> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_controllerChanged);
      widget.controller.addListener(_controllerChanged);
      _disposeRuntime();
      _entryId = null;
      _sync();
    }
    if (!identical(oldWidget.priceQueries, widget.priceQueries)) {
      _populateData();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dependenciesReady = true;
    _populateData();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_controllerChanged);
    _disposeRuntime();
    super.dispose();
  }

  void _controllerChanged() {
    if (!mounted) return;
    setState(_sync);
  }

  /// Reconciles the mounted runtime with the controller's current screen. A new
  /// current screen builds a fresh isolated runtime; the same screen is a no-op
  /// (its instance is preserved across a re-render); no current screen (loading,
  /// a sub-flow boundary, or a fail-closed flow) tears the runtime down.
  void _sync() {
    final controller = widget.controller;
    final entryId = controller.currentScreenEntryId;
    final library = controller.currentLibrary;
    if (entryId == null || library == null || controller.isUnavailable) {
      _disposeRuntime();
      _entryId = null;
      return;
    }
    if (entryId == _entryId && _runtime != null) return;
    _disposeRuntime();
    _entryId = entryId;
    _runtime = _libraries.runtimeFor(library);
    _data = DynamicContent();
    _populateData();
  }

  void _disposeRuntime() {
    final runtime = _runtime;
    _runtime = null;
    _data = null;
    if (runtime == null) return;
    // Dispose after the frame, once the rebuild has detached the RemoteWidget
    // (so the runtime has no remaining listeners).
    WidgetsBinding.instance.addPostFrameCallback((_) => runtime.dispose());
  }

  void _populateData() {
    final data = _data;
    if (data == null) return;
    populateFlowScreenData(
      context,
      data,
      priceQueries: widget.priceQueries,
      includeInheritedData: _dependenciesReady,
    );
  }

  @override
  Widget build(BuildContext context) {
    final runtime = _runtime;
    final data = _data;
    if (runtime == null || data == null) {
      return widget.loadingBuilder?.call(context) ?? const SizedBox.shrink();
    }
    // Capture the controller + entry so a stale event or render failure routes
    // to the owner gated to the owner's current entry.
    final controller = widget.controller;
    final entryId = _entryId;
    return RuntimeErrorBoundary(
      onError: (error, stack) {
        if (entryId == controller.currentScreenEntryId) {
          controller.reportRenderFailure(error);
        }
        widget.onRuntimeError?.call(error, stack);
      },
      errorReplacement: (_, __, ___) => const SizedBox.shrink(),
      child: RemoteWidget(
        runtime: runtime,
        data: data,
        widget: kFlowScreenWidget,
        onEvent: (name, args) {
          // Inert unless this is the owning controller's current screen.
          if (entryId != controller.currentScreenEntryId) return;
          controller.handleEvent(name, normalizeRfwEventArgs(args));
        },
      ),
    );
  }
}
