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
import '../events/event_enums.dart';
import '../events/restage_event.dart';
import '../flow/flow_controller.dart';
import '../flow/flow_descriptors.dart';
import '../flow/flow_resolver.dart';
import '../flow/restage_flow_view.dart';
import '../resolver/resolved_paywall_payload.dart';
import '../resolver/variant_resolver.dart';
import 'error_boundary.dart';
import 'event_demux.dart';
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

  @override
  State<RestagePaywall> createState() => _RestagePaywallState();
}

class _RestagePaywallState extends State<RestagePaywall> {
  late final Runtime _runtime;
  final DynamicContent _data = DynamicContent();
  static const LibraryName _paywallLibrary =
      LibraryName(<String>['restage', 'paywall']);

  WidgetLibrary? _decoded;
  RestagePaywallError? _error;
  DateTime? _mountedAt;
  bool _viewedFired = false;
  bool _dismissedFired = false;

  /// The server-assigned published version of the last successfully-resolved
  /// variant, captured at load so a later purchase attributes its conversion to
  /// the exact served version (MAR). Null for bundled / custom resolutions.
  int? _resolvedPaywallPublishedVersion;

  /// The hosted flow controller when the resolved payload is flow-shaped (a
  /// lowered navigation paywall); null for a single-blob paywall. The paywall
  /// intercepts this controller's purchase/restore events out-of-band so they
  /// bill instead of driving a graph transition (see
  /// [_interceptFlowScreenEvent]).
  RestageFlowController<void>? _flowController;

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
    _runtime = Runtime()
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
    LibraryRuntimeRegistry.applyTo(_runtime);
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
    populateThemeData(
      _data,
      colorScheme: colorScheme,
      iconTheme: iconTheme,
      defaultTextStyle: defaultTextStyle,
    );
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

  Future<void> _load() async {
    _fireEvent(PaywallLoadStarted(paywallId: widget.id));
    final stopwatch = Stopwatch()..start();
    final resolver = widget.resolver ?? Restage.defaultResolver;
    try {
      final payload = await _resolvePayload(resolver);
      // A flow-shaped payload (a lowered navigation paywall) is hosted by the
      // flow runtime; a purchase on any of its screens is intercepted to bill
      // (see [_startFlow] / [_interceptFlowScreenEvent]). The blob path below is
      // unchanged — the sealed demux only adds the flow branch.
      if (payload is FlowPaywallPayload) {
        if (!mounted) return;
        // The flow is cached only AFTER its first screen renders (in
        // _handleFlowLifecycleEvent), mirroring the blob path which caches a
        // decoded blob — so an unrenderable flow is never cached.
        _startFlow(payload, stopwatch);
        return;
      }
      final variant = (payload as BlobPaywallPayload).variant;
      final WidgetLibrary library;
      try {
        library = decodeLibraryBlob(variant.bytes);
      } catch (e, st) {
        throw RestagePaywallError(
          code: RestageErrorCodes.decodeFailed,
          message: 'Could not decode .rfw blob for ${widget.id}: $e',
          cause: e,
          stackTrace: st,
        );
      }
      // Decode succeeded — this blob is what renders. Capture its served
      // published version (AFTER decode, so a failed fresh blob never records
      // its version) so a subsequent purchase attributes to the version the
      // user actually saw.
      _resolvedPaywallPublishedVersion = variant.paywallPublishedVersion;
      // Populate the cache before the !mounted bail so a remount of the
      // same paywall id can use the freshly resolved payload — the cache is a
      // global side effect, not a widget-lifecycle event, and should not
      // depend on whether this particular mount is still alive. The sealed
      // payload carries the served version, so a fallback render reports the
      // rendered surface's version.
      if (widget.cacheLastRender) {
        _lastSuccessfulPayloads[widget.id] = payload;
      }
      if (!mounted) return;
      _applyDecodedLibrary(
        library,
        loadDuration: stopwatch.elapsed,
        cacheHit: variant.cacheHit,
        variantId: variant.variantId,
        experimentId: variant.experimentId,
      );
    } on RestagePaywallError catch (e) {
      if (!mounted) return;
      if (_tryFallbackToCache(stopwatch)) return;
      setState(() => _error = e);
      _fireEvent(PaywallLoadFailed(
        paywallId: widget.id,
        errorCode: e.code,
        message: e.message,
        retryable: e.retryable,
      ));
    } catch (e, st) {
      // Surface the original exception + stack to the developer console so
      // a buggy custom resolver doesn't get hidden behind a generic
      // "unknown" error code in their crash reports.
      FlutterError.reportError(FlutterErrorDetails(
        exception: e,
        stack: st,
        library: 'restage',
        context: ErrorDescription('resolving + decoding paywall ${widget.id}'),
      ));
      if (!mounted) return;
      if (_tryFallbackToCache(stopwatch)) return;
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

  /// Resolves [RestagePaywall.id] into a sealed payload. The built-in resolvers
  /// can return a blob OR a lowered flow; a host-supplied custom resolver stays
  /// blob-only (the public [VariantResolver.resolve] SPI), and its
  /// [ResolvedVariant] is wrapped as a [BlobPaywallPayload].
  Future<ResolvedPaywallPayload> _resolvePayload(VariantResolver resolver) {
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
    bool fromCache = false,
  }) {
    _resolvedPaywallPublishedVersion = payload.paywallPublishedVersion;
    final document = payload.flow.document;
    final controller = RestageFlowController<void>(
      flow: OnboardingFlowRef<void>(
        id: document.flow,
        version: document.version,
        minClient: document.minClient,
        decodeResult: (_) {},
      ),
      resolver: _PreResolvedFlowResolver(payload.flow),
      actions: null,
      onEvent: (event) =>
          _handleFlowLifecycleEvent(event, stopwatch, payload, fromCache),
      onComplete: (_) => _handleFlowComplete(),
      onUnavailable: _handleFlowUnavailable,
    );
    setState(() {
      _flowController = controller;
      _error = null;
    });
    unawaited(controller.load());
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
  /// (so a flow-hosted paywall never surfaces as onboarding in analytics) and
  /// surfaces paywall-shaped lifecycle instead. [FlowStarted] signals the first
  /// screen is ready → announce the paywall load; failure is handled by
  /// [_handleFlowUnavailable]; completion (skip → end) by [_handleFlowComplete].
  void _handleFlowLifecycleEvent(
    RestageEvent event,
    Stopwatch stopwatch,
    FlowPaywallPayload payload,
    bool fromCache,
  ) {
    if (event is! FlowStarted) return;
    // The first screen rendered successfully — cache the flow ONLY now (mirrors
    // the blob path caching a decoded blob), so an unrenderable flow is never
    // cached, then announce the paywall load lifecycle. A re-host from the
    // last-good cache reports a cache hit (consistent with the blob fallback);
    // a fresh load reports the resolver's own cache flag.
    if (widget.cacheLastRender) {
      _lastSuccessfulPayloads[widget.id] = payload;
    }
    _announceFlowLoaded(stopwatch.elapsed, fromCache || payload.flow.cacheHit);
  }

  /// Announces the paywall-shaped load lifecycle for a flow-hosted paywall
  /// exactly once: `PaywallLoadCompleted` now + `PaywallViewed` after the first
  /// frame. Mirrors [_applyDecodedLibrary]'s blob lifecycle, keyed on paywallId.
  void _announceFlowLoaded(Duration loadDuration, bool cacheHit) {
    if (_flowLoadAnnounced || !mounted) return;
    _flowLoadAnnounced = true;
    _fireEvent(PaywallLoadCompleted(
      paywallId: widget.id,
      loadDuration: loadDuration,
      cacheHit: cacheHit,
    ));
    _schedulePaywallViewed();
  }

  /// Fires `PaywallViewed` exactly once in a post-frame callback after the first
  /// render. Shared by the blob lifecycle ([_applyDecodedLibrary]) and the
  /// flow-hosted lifecycle ([_announceFlowLoaded]); the flow path carries no
  /// A/B identifiers, so [variantId] / [experimentId] default to null there.
  void _schedulePaywallViewed({String? variantId, String? experimentId}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _viewedFired) return;
      _viewedFired = true;
      _fireEvent(PaywallViewed(
        paywallId: widget.id,
        productIds:
            Restage.configuredProducts.map((p) => p.id).toList(growable: false),
        variantId: variantId,
        experimentId: experimentId,
      ));
    });
  }

  /// The flow reached its end state (the entry screen's skip/dismiss → end): the
  /// user backed out of the paywall. Surface a paywall dismiss keyed on
  /// paywallId — NOT an onboarding completion. (A successful purchase does NOT
  /// route here; per the paywall contract the host owns dismissal, identical to
  /// a blob paywall.)
  void _handleFlowComplete() => _fireDismissed(DismissReason.userClose);

  /// The flow failed closed (a missing / incompatible / unrenderable artifact,
  /// or a screen that threw during build). Surface a paywall load failure + the
  /// error UI, mirroring the blob path's fail-closed posture.
  void _handleFlowUnavailable(FlowUnavailableError error) {
    if (!mounted) return;
    // Evict a poisonous cached flow so a later fallback does not re-host an
    // unrenderable flow forever (mirrors the blob path's cache eviction on a
    // decode failure). A no-op when nothing is cached.
    _lastSuccessfulPayloads.remove(widget.id);
    final err = RestagePaywallError(
      code: RestageErrorCodes.renderError,
      message: 'The navigation paywall "${widget.id}" could not be hosted '
          '(${error.reason}): ${error.message}',
    );
    setState(() {
      _flowController = null;
      _error = err;
    });
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

  /// Apply a decoded library to the runtime: register it, populate state-var
  /// namespaces, surface the rendered widget, fire `PaywallLoadCompleted`,
  /// and schedule the post-frame `PaywallViewed`. Shared between the fresh
  /// load path and the cache-fallback path.
  void _applyDecodedLibrary(
    WidgetLibrary library, {
    required Duration loadDuration,
    required bool cacheHit,
    String? variantId,
    String? experimentId,
  }) {
    _runtime.update(_paywallLibrary, library);
    populateProductData(
      _data,
      products: Restage.configuredProducts,
      priceQueries: widget.priceQueries,
    );
    final mq = MediaQuery.maybeOf(context);
    if (mq != null) {
      populateDeviceData(
        _data,
        locale: widget.locale ?? const Locale('en'),
        mediaQuery: mq,
        platform: currentDevicePlatform(),
      );
    }
    setState(() {
      _decoded = library;
      _error = null;
    });
    _fireEvent(PaywallLoadCompleted(
      paywallId: widget.id,
      loadDuration: loadDuration,
      cacheHit: cacheHit,
    ));
    _schedulePaywallViewed(variantId: variantId, experimentId: experimentId);
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
  bool _tryFallbackToCache(Stopwatch stopwatch) {
    if (!widget.cacheLastRender) return false;
    final cached = _lastSuccessfulPayloads[widget.id];
    if (cached == null) return false;
    switch (cached) {
      case FlowPaywallPayload():
        // A cached flow re-hosts directly: its document + screen blobs are
        // already validated, so the flow runtime renders the entry screen. This
        // is a cache hit (consistent with the blob fallback below).
        if (!mounted) return false;
        _startFlow(cached, stopwatch, fromCache: true);
        return true;
      case BlobPaywallPayload(:final variant):
        try {
          final library = decodeLibraryBlob(variant.bytes);
          if (!mounted) return false;
          // The reported version must match the RENDERED blob: this fallback
          // shows the cached blob, so attribute to the cached blob's version
          // (null if the cached resolution had none), not whatever the failed
          // fresh resolve was.
          _resolvedPaywallPublishedVersion = variant.paywallPublishedVersion;
          _applyDecodedLibrary(
            library,
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

  @override
  void dispose() {
    widget.controller?.detachInternal();
    // Fire dismissed FIRST (it binds the current surfaceSessionId synchronously),
    // then end the surface session.
    if (_viewedFired) _fireDismissed(DismissReason.programmatic);
    // Dispose the hosted flow controller (a no-op for a blob paywall). Done
    // after the dismiss so the dismiss is keyed to the still-open session.
    _flowController?.dispose();
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
      final outcome =
          await Restage.purchaseProduct(productId, offerId: offerId);
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
            // gateway delegated the purchase and kept the receipt, so there is
            // nothing to validate. Report the attribution hint (transaction id +
            // paywall id) — never down the receipt-validation path. No-ops
            // cleanly when the SDK was configured without a baseUrl.
            unawaited(Restage.reportAttribution(
              storeProductId: productId,
              storeTransactionId: transactionId,
              paywallId: widget.id,
              paywallPublishedVersion: _resolvedPaywallPublishedVersion,
            ));
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
      final outcome = await Restage.billingGateway.restore();
      // See _runPurchase: global side effects fire regardless of mount.
      switch (outcome) {
        case RestoreOutcomeSucceeded(:final restoredProductIds):
          _fireEvent(RestoreSucceeded(
            paywallId: widget.id,
            restoredProductIds: restoredProductIds,
          ));
          for (final productId in restoredProductIds) {
            Restage.grantEntitlementForProduct(
              productId,
              EntitlementSource.restore,
            );
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

  /// Adapter so the [RestagePaywallEventDispatcher] (which expects
  /// `void Function(String, Map<String, Object?>)`) can forward to the
  /// shared [_handleRfwEvent] helper.
  void _dispatcherEvent(String name, Map<String, Object?> args) =>
      _handleRfwEvent(name, args);

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      final builder = widget.errorBuilder;
      return builder == null
          ? const SizedBox.shrink()
          : builder(context, _error!);
    }
    final flowController = _flowController;
    if (flowController != null) {
      // A lowered navigation paywall: host the flow. Purchase/restore on any
      // screen is intercepted to bill (never a graph transition,
      // [_interceptFlowScreenEvent]); navigation events drive the flow. The
      // flow view populates per-screen product + theme data for paywall
      // screens, so they render exactly like a single-blob paywall.
      return RestageFlowView<void>(
        controller: flowController,
        onScreenEvent: _interceptFlowScreenEvent,
        loadingBuilder: widget.loadingBuilder,
        priceQueries: widget.priceQueries,
        // A paywall is a fully self-authored surface: it draws its own back and
        // dismiss affordances (an authored back control maps to the flow's
        // reserved back event; an authored dismiss maps to skip). Suppress the
        // built-in flow chrome so its default affordances never overlap the
        // authored ones — matching how a single-screen paywall carries no
        // SDK-drawn chrome. System-back still drives in-flow back automatically.
        chromeBuilder: (context, state, screen) => screen,
      );
    }
    if (_decoded == null) {
      final builder = widget.loadingBuilder;
      return builder == null ? const SizedBox.shrink() : builder(context);
    }
    return RestagePaywallEventDispatcher(
      onEvent: _dispatcherEvent,
      child: RuntimeErrorBoundary(
        onError: (e, _) {
          _fireEvent(PaywallLoadFailed(
            paywallId: widget.id,
            errorCode: RestageErrorCodes.renderError,
            message: e.toString(),
            retryable: false,
          ));
        },
        errorReplacement: (context, _, __) {
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
          runtime: _runtime,
          data: _data,
          widget: const FullyQualifiedWidgetName(_paywallLibrary, 'Paywall'),
          onEvent: _handleRfwEvent,
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
