import 'dart:async';
import 'dart:ui' show AppLifecycleState, Locale;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart'
    show WidgetsBinding, WidgetsBindingObserver;
import 'package:restage_shared/restage_shared.dart';

import '../analytics/analytics_identity.dart';
import '../analytics/root_analytics_context.dart';
import '../commerce/restage_commerce.dart'
    show RestageCommerce, restageCommerceInstance;
import '../metering/metering_token_store.dart';
import '../measurement/governed_measurement_transport.dart';
import '../measurement/governed_measurement_rpc_transport.dart';
import '../measurement/measurement_assignment_transport.dart';
import '../measurement/measurement_host_construction_owner.dart';
import '../measurement/measurement_host_session.dart';
import '../measurement/measurement_worker_delivery.dart'
    show
        measurementWorkerDeliverySupported,
        MeasurementWorkerOwnedDeliveryRuntime;
import '../measurement/hosted_measurement_construction_profile_read_port.dart';
import '../measurement/itt_assignment_rpc_adapter.dart';
import '../measurement/restage_measurement.dart';
import '../measurement/restage_privacy.dart';
import '../restage_rpc_client/restage_rpc_client.dart';
import '../restage_rpc_client/surface_delivery_evidence.dart';
import '../events/restage_event.dart';
import '../flow/flow_resolver.dart';
import '../surface_screen/asset_surface_screen_resolver.dart';
import '../surface_screen/restage_surface_screen_resolver.dart';
import '../surface_screen/surface_screen_types.dart';
import '../refresh/surface_refresh_registry.dart';
import '../refresh/surface_refresh_trigger.dart';
import '../refresh/restage_hosted_update_channel.dart';
import '../refresh/surface_update_channel.dart';
import '../resolver/asset_variant_resolver.dart';
import '../resolver/restage_variant_resolver.dart';
import '../resolver/surface_resolution_report.dart';
import '../resolver/surface_assignment_key_provider.dart';
import '../resolver/surface_assignment_credential_store.dart';
import '../resolver/surface_assignment_persistence.dart';
import '../resolver/surface_assignment_built_ins.dart';
import '../resolver/surface_canonical_carrier_provider.dart';
import '../resolver/surface_analytics_identity_provider.dart';
import '../resolver/surface_metering_key_provider.dart';
import '../resolver/variant_resolver.dart';
import 'library_runtime_registry.dart';
import 'first_paint_lease_guard.dart';
import 'restage_identity.dart';
import 'restage_paywall.dart';
import 'restage_widget_factory.dart';
import 'restage_widget_library_registration.dart';

/// Restage SDK static facade.
///
/// Configure app-wide delivery, analytics, privacy, Measurement, and rendering
/// settings at startup when needed. Bundled paywalls and onboarding flows can
/// also be rendered directly with `AssetVariantResolver` and
/// `AssetFlowResolver`.
abstract final class Restage {
  /// App-wide commerce operations and state.
  static final RestageCommerce commerce = restageCommerceInstance;

  /// Explicit, opt-in governed Measurement operations.
  static final RestageMeasurement measurement = RestageMeasurement.internal();

  /// Explicit coordinator over independently-owned privacy operations.
  static final RestagePrivacy privacy = RestagePrivacy.internal();

  static void Function(SurfaceResolutionReport report)? _onSurfaceResolution;
  static String? _apiKey;
  static String? _baseUrl;
  static RestageEnvironment _environment = RestageEnvironment.production;
  static VariantResolver _defaultResolver = const AssetVariantResolver();
  static FlowResolver _defaultFlowResolver = const AssetFlowResolver();
  static SurfaceScreenResolver _defaultSurfaceScreenResolver =
      const AssetSurfaceScreenResolver();
  static int _configurationGeneration = 0;
  static bool _measurementEnabled = true;
  static MeasurementHostConstructionOwner? _measurementHostOwner;
  static final Set<MeasurementHostConstructionOwner>
      _measurementRetiringOwners = {};
  static Future<void> _measurementHostBarrier = Future<void>.value();

  // App-global live-refresh configuration. `_liveRefresh` is the fallback
  // trigger set; `_liveRefreshOverrides` pins a per-surface set by id; both are
  // resolved by [effectiveLiveRefreshTriggers]. `_updateChannel` is the
  // optional change-signal source for the updateChannel trigger.
  static Set<SurfaceRefreshTrigger> _liveRefresh = const {};
  static Map<String, Set<SurfaceRefreshTrigger>> _liveRefreshOverrides =
      const {};
  static SurfaceUpdateChannel? _updateChannel;

  static StreamController<RestageEvent>? _events;
  static MeteringTokenStore? _meteringTokenStore;
  static RestageRpcClient? _rpcClient;
  static _RestageLifecycleObserver? _lifecycleObserver;

  // The behavioral-analytics transport. Active only when [configure] is given a
  // [baseUrl]; otherwise `track`/`identify`/`reset` are inert (no endpoint).
  static AnalyticsIdentity? _analyticsIdentity;

  // Observes every event passed to [fireEvent], after the host broadcast leg.
  // Registered by the recording runtime when it is configured and cleared when
  // it is torn down; there is no host-facing way to install one. Keeping it a
  // registration rather than a hard call in [fireEvent] is what lets the event
  // stream and the recording path be reasoned about — and retired — separately.
  static ({String apiKey, RestageEnvironment environment})? _analyticsAuthority;

  /// Configure the SDK at app startup.
  ///
  /// Pass [resolver] to choose the paywall delivery source. When omitted, the
  /// default is a [RestageVariantResolver] wired to [baseUrl] for Restage-hosted
  /// delivery (fetch the active version, hold-last-good, then fall back to a
  /// bundled `assets/paywalls/<id>.rfw`). With no [baseUrl] the hosted tier is
  /// inactive and resolution uses the bundled asset directly. Apps shipping only
  /// bundled `.rfw` paywalls can pass [AssetVariantResolver] here or on each
  /// `RestagePaywall`.
  ///
  /// [onSurfaceResolution] reports each public hosted paywall resolution source.
  /// Exceptions thrown by this optional callback are ignored.
  ///
  /// Pass [flowResolver] to choose the onboarding flow source. When omitted,
  /// flows use [AssetFlowResolver]; this method does not enable hosted flow
  /// delivery.
  ///
  /// Pass [surfaceScreenResolver] to choose the independently published screen
  /// source. When omitted, the generated manifest-aware hosted resolver is
  /// installed and falls back only to the exact bundled screen closure.
  ///
  /// [baseUrl] is the hosted service origin (e.g.
  /// `'https://api.example.com'`). When omitted, hosted delivery, metering, and
  /// governed operations remain inactive.
  ///
  /// [analyticsEnabled] (default `true`) gates local anonymous identity and
  /// automatic assignment credential registration. When `false`, no identifier
  /// is minted; hosted delivery and governed operations remain available.
  ///
  /// [measurementEnabled] (default `true`) controls new Measurement sessions.
  /// When `false`, new sessions do not load publications or submit data.
  ///
  /// Hosted surface requests describe the device so the service can choose a
  /// published version of a surface for it, such as a version for one country
  /// or for tablets. Without that description it can only serve the default.
  /// Every request carries the platform (e.g. `ios`); it also carries the app
  /// build ordinal (e.g. `412`), the device region (e.g. `se`) and the device
  /// class (e.g. `phone`) whenever the device can supply them, and omits any it
  /// cannot. These facts travel regardless of [analyticsEnabled] and
  /// [measurementEnabled].
  ///
  /// With analytics disabled, hosted requests carry no analytics identifier and
  /// no assignment credential. The metering token that counts use of the hosted
  /// service is separate and is unaffected by that flag; the package README
  /// describes it in full. The device facts above are stored only when
  /// measurement is enabled and a session is created.
  ///
  /// Pass [liveRefreshEdgeUrl] with [baseUrl] to use Restage-hosted realtime
  /// update signals. A custom [updateChannel] takes precedence when both are
  /// provided. If hosted refresh is unavailable, mounted surfaces continue
  /// without realtime refresh.
  ///
  /// [identity] is an **experimental, not-yet-active** hook (see
  /// [RestageIdentity]). The callback is accepted but is not currently invoked,
  /// and the identity it would return is not yet attached to resolver requests
  /// or analytics. Wiring it has no runtime effect today; it is accepted now so
  /// the integration shape can stabilize.
  ///
  /// Set [governedMeasurementTransportEnabled] only after the host has
  /// configured its direct host/IDP proof source. It installs the SDK's
  /// authenticated canonical transport over [baseUrl]. Supplying
  /// [governedMeasurementTransport] installs an explicit alternate transport
  /// instead. With neither option, governed Measurement and privacy calls fail
  /// closed and legacy analytics identity remains unaffected.
  static void configure({
    required String apiKey,
    String? baseUrl,
    bool analyticsEnabled = true,
    bool measurementEnabled = true,
    RestageEnvironment environment = RestageEnvironment.production,
    void Function(SurfaceResolutionReport report)? onSurfaceResolution,
    VariantResolver? resolver,
    FlowResolver? flowResolver,
    SurfaceScreenResolver? surfaceScreenResolver,
    Locale? locale,
    Future<RestageIdentity?> Function()? identity,
    Set<SurfaceRefreshTrigger> liveRefresh = const {},
    Map<String, Set<SurfaceRefreshTrigger>> liveRefreshOverrides = const {},
    SurfaceUpdateChannel? updateChannel,
    Uri? liveRefreshEdgeUrl,
    bool governedMeasurementTransportEnabled = false,
    RestageGovernedMeasurementTransport? governedMeasurementTransport,
  }) {
    if (governedMeasurementTransportEnabled &&
        governedMeasurementTransport != null) {
      throw ArgumentError(
        'Configure either governedMeasurementTransportEnabled or '
        'governedMeasurementTransport, not both.',
      );
    }
    _configurationGeneration += 1;
    _measurementEnabled = measurementEnabled;
    _onSurfaceResolution = onSurfaceResolution;
    _apiKey = apiKey;
    _baseUrl = baseUrl;
    // A reconfiguration must never retain a client bound to the previous
    // origin or credential. Test clients can be reinstalled after configure.
    _rpcClient = null;
    _installIttAssignmentTransport();
    if (governedMeasurementTransport != null) {
      GovernedMeasurementPortRegistry.install(governedMeasurementTransport);
    } else if (governedMeasurementTransportEnabled) {
      final client = _requireRpcClient();
      GovernedMeasurementPortRegistry.install(
        client == null ? null : RestageGovernedMeasurementRpcTransport(client),
      );
    } else {
      GovernedMeasurementPortRegistry.install(null);
    }
    _environment = environment;
    _defaultResolver = resolver ??
        RestageVariantResolver(
          apiKey: apiKey,
          environment: environment,
          baseUrl: baseUrl,
        );
    _defaultFlowResolver = flowResolver ?? const AssetFlowResolver();
    _defaultSurfaceScreenResolver = surfaceScreenResolver ??
        RestageScreenResolver(
          apiKey: apiKey,
          environment: environment,
          baseUrl: baseUrl,
          rpcClientProvider: _requireRpcClient,
        );
    _liveRefresh = Set.unmodifiable(liveRefresh);
    _liveRefreshOverrides = Map.unmodifiable({
      for (final entry in liveRefreshOverrides.entries)
        entry.key: Set<SurfaceRefreshTrigger>.unmodifiable(entry.value),
    });
    _updateChannel = updateChannel;
    if (_updateChannel == null &&
        liveRefreshEdgeUrl != null &&
        baseUrl != null) {
      try {
        final client = _requireRpcClient();
        if (client != null) {
          _updateChannel = RestageHostedUpdateChannel(
            rpcClient: client,
            edgeUrl: liveRefreshEdgeUrl,
          );
        }
      } catch (_) {
        // Live refresh is optional. Invalid or unavailable hosted
        // configuration leaves the rest of the SDK operational.
      }
    }
    // The current bundled asset resolvers do not read `locale` or `identity`.
    _registerLifecycleObserver();
    _configureAnalytics(
      apiKey: apiKey,
      baseUrl: baseUrl,
      locale: locale,
      enabled: analyticsEnabled,
      environment: environment,
    );
    _configureSurfaceAssignmentKeyProvider(
      baseUrl: baseUrl,
      enabled: analyticsEnabled && measurementEnabled,
    );
    _configureSurfaceMeteringKeyProvider(baseUrl: baseUrl);
    SurfaceDeliveryEvidence.installRateLimited(
      _emitSurfaceDeliveryRateLimited,
    );
    _configureMeasurementHost(enabled: analyticsEnabled && measurementEnabled);
    if (_analyticsAuthority != null) {
      // Defer the best-effort identity warm-up to keep configuration synchronous.
      scheduleMicrotask(() async {
        if (_analyticsAuthority == null) return;
        try {
          await _analyticsIdentity?.anonymousId();
        } on Object catch (_) {}
      });
    }
  }

  /// Resolves the effective live-refresh trigger set for [surfaceSlug].
  ///
  /// Most-specific-wins, used verbatim (never merged): the per-widget
  /// [widgetOverride] if provided, else the per-surface override configured on
  /// [configure], else the app-global set, else empty (off).
  static Set<SurfaceRefreshTrigger> effectiveLiveRefreshTriggers(
    String surfaceSlug, {
    Set<SurfaceRefreshTrigger>? widgetOverride,
  }) =>
      widgetOverride ?? _liveRefreshOverrides[surfaceSlug] ?? _liveRefresh;

  /// The app-global change-signal source, if one was configured. Internal:
  /// the refresh registry reads it to open update subscriptions.
  @internal
  static SurfaceUpdateChannel? get configuredUpdateChannel => _updateChannel;

  /// Re-resolves mounted Restage surfaces in place, applying new published
  /// content where the surface is safely swappable (no user interaction or
  /// contributed state, no busy flow, and no locked assignment). Restricts
  /// to surfaces whose id equals [surfaceId] when provided. Explicit calls run
  /// regardless of the configured live-refresh triggers — an explicit call is
  /// its own consent — but still pass through the swap-safety gate.
  static Future<void> reloadSurfaces({String? surfaceId}) =>
      SurfaceRefreshRegistry.instance.reload(slug: surfaceId);

  /// Configures the analytics transport from [apiKey] + [baseUrl]. With no
  /// [baseUrl], or when [enabled] is false, the transport is disabled (no
  /// endpoint) and `track`/`identify`/`reset` are inert.
  static void _configureAnalytics({
    required String apiKey,
    String? baseUrl,
    Locale? locale,
    bool enabled = true,
    required RestageEnvironment environment,
  }) {
    if (!enabled || baseUrl == null || baseUrl.isEmpty) {
      if (_analyticsAuthority != null) {
        _retireAnalyticsAuthority();
      }
      _analyticsAuthority = null;
      SurfaceAnalyticsIdentityProvider.clear();
      return;
    }
    final authority = (apiKey: apiKey, environment: environment);
    final previousAuthority = _analyticsAuthority;
    if (previousAuthority != null && previousAuthority != authority) {
      _retireAnalyticsAuthority();
    }
    _analyticsAuthority = authority;
    _analyticsIdentity ??= RootAnalyticsRuntime.createIdentity();
    SurfaceAnalyticsIdentityProvider.install(_analyticsIdentity!.anonymousId);
    RootAnalyticsRuntime.install(identity: _analyticsIdentity!);
  }

  static void _retireAnalyticsAuthority() {
    RootAnalyticsRuntime.retireAuthority();
    FirstPaintLeaseTransaction.revalidatePendingAfterIdentityReset();
  }

  static void _configureSurfaceMeteringKeyProvider({String? baseUrl}) {
    if (baseUrl == null || baseUrl.isEmpty) {
      SurfaceMeteringKeyProvider.clear();
      return;
    }
    _meteringTokenStore ??= MeteringTokenStore();
    SurfaceMeteringKeyProvider.install(store: _meteringTokenStore!);
  }

  static void _configureSurfaceAssignmentKeyProvider({
    String? baseUrl,
    required bool enabled,
  }) {
    final identity = _analyticsIdentity;
    SurfaceCanonicalCarrierProvider.clear();
    // Observations describe the device for delivery selection, so they do not
    // depend on measurement support or an assignment credential.
    if (baseUrl != null && baseUrl.isNotEmpty) {
      SurfaceCanonicalCarrierProvider.installBuiltIns(
          readSurfaceAssignmentBuiltIns);
    }
    if (!enabled ||
        !measurementWorkerDeliverySupported ||
        baseUrl == null ||
        baseUrl.isEmpty ||
        identity == null) {
      SurfaceAssignmentKeyProvider.clear();
      return;
    }
    final namespace = '$baseUrl|$_apiKey|${_environment.name}';
    final configurationGeneration = _configurationGeneration;
    final credentialStore = SurfaceAssignmentCredentialStore(
      namespace: namespace,
      actor: identity.anonymousId,
      onRetentionRollover: SurfaceCanonicalCarrierProvider.clearHeldAssignments,
      identityGeneration: () => identity.generation,
      client: () => configurationGeneration == _configurationGeneration
          ? _requireRpcClient()
          : null,
    );
    SurfaceCanonicalCarrierProvider.enableAssignmentRetention(namespace);
    SurfaceAssignmentKeyProvider.install(
      key: credentialStore.resolve,
      identityGeneration: () => credentialStore.generation,
    );
  }

  static void _configureMeasurementHost({
    required bool enabled,
    bool privacyReset = true,
  }) {
    final previous = _measurementHostOwner;
    _measurementHostOwner = null;
    MeasurementHostSessionConstructionRegistry.installProduction(null);
    final baseUrl = _baseUrl;
    final apiKey = _apiKey;
    final admitted =
        enabled && baseUrl != null && baseUrl.isNotEmpty && apiKey != null;
    if (previous != null) _measurementRetiringOwners.add(previous);
    final previousBarrier = _measurementHostBarrier;
    if (!admitted && privacyReset) {
      final completed = Completer<void>();
      final owners = _measurementRetiringOwners.toList();
      final cancellations = [
        for (final owner in owners)
          owner.cancelCollection(purgeCompletion: completed.future),
      ];
      final cleanup = () async {
        // A new cleanup attempt may recover from an earlier failed deletion.
        await previousBarrier.catchError((Object _) {});
        await Future.wait(cancellations);
        await MeasurementWorkerOwnedDeliveryRuntime.purgePersisted();
        _measurementRetiringOwners.removeAll(owners);
      }();
      _measurementHostBarrier = completed.future;
      unawaited(
          cleanup.then(completed.complete, onError: completed.completeError));
      // Keep the failure on the startup barrier while avoiding an unobserved
      // asynchronous error when collection remains disabled.
      unawaited(completed.future.catchError((Object _) {}));
      return;
    }
    if (previous != null) {
      final retirement = previous.close();
      _measurementHostBarrier = Future.wait<void>([previousBarrier, retirement])
          .then((_) => _measurementRetiringOwners.remove(previous));
      unawaited(_measurementHostBarrier.catchError((Object _) {}));
    }
    if (!admitted) return;
    final generation = _configurationGeneration;
    final owner = MeasurementHostConstructionOwner.production(
      startupBarrier: _measurementHostBarrier,
      profileReadPort: HostedMeasurementConstructionProfileReadPort(
        client: () =>
            generation == _configurationGeneration ? _requireRpcClient() : null,
        baseUrl: baseUrl,
        apiKey: apiKey,
      ),
    );
    _measurementHostOwner = owner;
    MeasurementHostSessionConstructionRegistry.installProduction(
      MeasurementHostSessionConstructionAuthority.production(
          constructionOwner: owner),
    );
  }

  /// App-wide event stream. Receives presentation and interaction events.
  ///
  /// Broadcast — multiple listeners supported; events are not buffered for
  /// late subscribers.
  static Stream<RestageEvent> get events {
    _events ??= StreamController<RestageEvent>.broadcast();
    return _events!.stream;
  }

  /// Rotates the on-device pseudonymous actor.
  ///
  /// What it does, exactly: mints a fresh pseudonymous id, rotates the session,
  /// removes persisted assignment credentials and held assignments,
  /// and clears the current surface-session identity rather than carrying it
  /// across. The next hosted resolution registers a new assignment credential,
  /// so the installation becomes a new, unlinked randomized unit. Assignment is
  /// re-drawn on the next surface presentation, and no relationship is recorded
  /// or claimed between the old unit and the new one. Pending hosted first-paint
  /// work selected under the previous id is invalidated; presentations already
  /// accepted stay pinned.
  ///
  /// What it does **not** do. It is a local operation: it sends nothing and
  /// notifies no server. It does **not** erase, amend, or unlink anything
  /// already uploaded — records sent before the call are untouched. It does
  /// **not** clear the metering identifier, which is separate and survives the
  /// rotation. It is **not** a server-side erasure request; the
  /// governed privacy request is [privacy], which coordinates the separately
  /// owned privacy operations once the hosted side serves them.
  ///
  /// Inert until [configure] is given a `baseUrl`.
  static void reset() {
    _measurementHostOwner?.resetSdkRuntimeSession();
    final identity = _analyticsIdentity;
    if (identity == null) return;
    // reset() advances the in-memory generation synchronously before its first
    // persistence await. Reject pending hosted paint work against that new
    // generation now; accepted presentations remain pinned.
    final identityReset = identity.reset();
    SurfaceCanonicalCarrierProvider.clearHeldAssignments();
    unawaited(SurfaceAssignmentPersistence.forget(
      afterIdentityReset: identityReset,
    ));
    RootAnalyticsRuntime.retireAll();
    FirstPaintLeaseTransaction.revalidatePendingAfterIdentityReset();
  }

  /// Register an app-defined widget [library] so its [widgets] can be
  /// used in paywalls. Call in `main()` before any `RestagePaywall` mounts.
  /// Re-registering the same namespace replaces the prior registration.
  ///
  /// `widgets` is normally produced by `restage_codegen` from
  /// `@RestageWidget`-annotated classes — adding `restage_codegen` as a
  /// `dev_dependency` and running `dart run build_runner build` generates
  /// the factory list passed here.
  ///
  /// [capabilityVersion] is the library's declared monotonic capability version
  /// (its `@RestageLibrary(capabilityVersion: …)`), recorded so a delivered
  /// surface's required-library floor can be verified before render. The
  /// generated registration helper passes it automatically for a library that
  /// requires a delivery-time capability floor; a library that needs none
  /// registers unversioned. Omit it for an unversioned library (which then
  /// satisfies no positive requirement).
  ///
  /// Asserts (debug only): [library] must not use a reserved built-in or
  /// preview-only namespace, [widgets] must not claim a preview-only
  /// constructor or contain duplicate names, and [capabilityVersion] (when
  /// provided) must be >= 1.
  static void registerWidgetLibrary(
    WidgetLibrary library, {
    required List<RestageWidgetFactory> widgets,
    int? capabilityVersion,
  }) {
    LibraryRuntimeRegistry.register(
      library,
      widgets,
      capabilityVersion: capabilityVersion,
    );
  }

  /// Immutable snapshot of the app widget libraries registered so far.
  ///
  /// This lets a caller-owned RFW runtime use the same generated registration
  /// calls as the main SDK runtime without creating a second registry.
  static List<RestageWidgetLibraryRegistration>
      get widgetLibraryRegistrations =>
          LibraryRuntimeRegistry.registrationSnapshot();

  // --- Runtime API ---

  /// Adds [event] to the [events] broadcast stream.
  ///
  /// The broadcast leg short-circuits when nothing is listening to [events].
  static void fireEvent(RestageEvent event) {
    final controller = _events;
    if (controller != null && controller.hasListener) {
      controller.add(event);
    }
  }

  static void _emitSurfaceDeliveryRateLimited({
    required Surface surfaceType,
    required String surfaceSlug,
    required Duration retryAfter,
  }) {
    fireEvent(SurfaceDeliveryRateLimited(
      surface: surfaceType,
      surfaceId: surfaceSlug,
      retryAfter: retryAfter,
      firedAt: DateTime.now().toUtc(),
    ));
  }

  /// Resolver used when a `RestagePaywall` is constructed without an explicit
  /// `resolver:` parameter.
  ///
  /// Without [configure], this is [AssetVariantResolver]. After [configure]
  /// without a resolver override, this is [RestageVariantResolver], which
  /// fetches Restage-hosted paywalls from the configured `baseUrl` (and falls
  /// back to a bundled asset when the fetch is unavailable).
  static VariantResolver get defaultResolver => _defaultResolver;

  /// Resolver used when `RestageFlowGraph` is constructed without an explicit
  /// `resolver:` parameter.
  ///
  /// The default is [AssetFlowResolver]; hosted flow delivery is not installed
  /// by [configure].
  static FlowResolver get defaultFlowResolver => _defaultFlowResolver;

  /// Resolver used when [RestageScreen] has no explicit resolver.
  ///
  /// Without [configure], this is [AssetSurfaceScreenResolver]. After
  /// configuration without an override, it validates hosted delivery against
  /// the generated standalone-screen manifest before rendering.
  static SurfaceScreenResolver get defaultSurfaceScreenResolver =>
      _defaultSurfaceScreenResolver;

  /// Monotonic identity of mutable SDK configuration used by hosted mounts.
  @internal
  static int get configurationGeneration => _configurationGeneration;

  @internal
  static bool get isMeasurementEnabled => _measurementEnabled;

  static RestageRpcClient? _requireRpcClient() {
    return _rpcClient ??= _buildRpcClient();
  }

  static void _installIttAssignmentTransport() {
    try {
      _replaceIttAssignmentTransport(_requireRpcClient());
    } on Object {
      _replaceIttAssignmentTransport(null);
    }
  }

  static void _replaceIttAssignmentTransport(RestageRpcClient? client) {
    MeasurementAssignmentTransportRegistry.install<IttAssignmentRpcRequest,
            IttAssignmentRpcOutcome>(
        client == null ? null : IttAssignmentRpcAdapter(client));
  }

  static RestageRpcClient? _buildRpcClient() {
    final baseUrl = _baseUrl;
    final apiKey = _apiKey;
    if (baseUrl == null || apiKey == null) return null;
    return RestageRpcClient(baseUrl: baseUrl, apiKey: apiKey);
  }

  /// The optional host callback for resolved surface sources.
  @internal
  static void Function(SurfaceResolutionReport report)?
      get configuredSurfaceResolutionCallback => _onSurfaceResolution;

  /// The active RPC client, or `null` when no service is configured.
  @internal
  static RestageRpcClient? get activeRpcClient => _requireRpcClient();

  static void _registerLifecycleObserver() {
    if (_lifecycleObserver != null) return;
    final binding = _safeWidgetsBinding();
    if (binding == null) return;
    final observer = _RestageLifecycleObserver();
    _lifecycleObserver = observer;
    binding.addObserver(observer);
  }

  static void _unregisterLifecycleObserver() {
    final observer = _lifecycleObserver;
    if (observer == null) return;
    final binding = _safeWidgetsBinding();
    if (binding != null) {
      binding.removeObserver(observer);
    }
    _lifecycleObserver = null;
  }

  static WidgetsBinding? _safeWidgetsBinding() {
    // The lifecycle observer is best-effort: host apps always have a
    // running binding (via `runApp`), but pure-Dart unit tests that
    // don't pump widgets won't. Skip cleanly when no binding is
    // available rather than throwing on construction. The catch is
    // intentionally broad — `WidgetsBinding.instance`'s uninitialized
    // exception type is a Flutter implementation detail that has
    // drifted between releases.
    try {
      return WidgetsBinding.instance;
    } on Object {
      return null;
    }
  }

  // --- Debug / test API (visible for testing) ---

  /// Test-only — exposes the API key passed to [configure].
  @internal
  static String? get debugApiKey => _apiKey;

  /// Test-only — exposes the environment passed to [configure].
  @internal
  static RestageEnvironment get debugEnvironment => _environment;

  /// Test-only — exposes the resolver `RestagePaywall` will use by default.
  @internal
  static VariantResolver get debugDefaultResolver => _defaultResolver;

  /// Test-only — fires [event] on the [events] stream as if it came from
  /// the runtime. Useful for asserting host app reactions to events.
  @visibleForTesting
  static void debugFire(RestageEvent event) => fireEvent(event);

  /// Test-only — injects a fake [RestageRpcClient].
  @internal
  static set debugRestageRpcClient(RestageRpcClient? client) {
    _rpcClient = client;
    _replaceIttAssignmentTransport(client);
  }

  /// Test-only — exposes the current [RestageRpcClient] for inspection.
  @internal
  static RestageRpcClient? get debugRestageRpcClient => _rpcClient;

  /// Resets all module-global state. **Tests must call this in `setUp`
  /// to avoid leaking state between tests.** Native fixtures that dispose
  /// worker resources must await [debugResetAndWait] instead.
  @visibleForTesting
  static void debugReset() {
    _configurationGeneration += 1;
    _configureMeasurementHost(enabled: false, privacyReset: false);
    _onSurfaceResolution = null;
    _apiKey = null;
    _baseUrl = null;
    _environment = RestageEnvironment.production;
    _defaultResolver = const AssetVariantResolver();
    _defaultFlowResolver = const AssetFlowResolver();
    _defaultSurfaceScreenResolver = const AssetSurfaceScreenResolver();
    _measurementEnabled = true;
    _liveRefresh = const {};
    _liveRefreshOverrides = const {};
    _updateChannel = null;
    _events?.close();
    _events = null;
    _rpcClient = null;
    MeasurementAssignmentTransportRegistry.debugReset();
    RootAnalyticsRuntime.clear();
    _analyticsIdentity = null;
    _analyticsAuthority = null;
    SurfaceAnalyticsIdentityProvider.clear();
    SurfaceAssignmentKeyProvider.clear();
    SurfaceCanonicalCarrierProvider.clear();
    _meteringTokenStore = null;
    SurfaceMeteringKeyProvider.clear();
    SurfaceDeliveryEvidence.clear();
    _unregisterLifecycleObserver();
    LibraryRuntimeRegistry.clear();
    resetRestagePaywallCache();
    SurfaceRefreshRegistry.instance.debugReset();
    GovernedMeasurementPortRegistry.debugReset();
  }

  /// Resets state synchronously and acknowledges retirement of native workers.
  /// Invoke and await this inside the async context that owns those resources.
  @visibleForTesting
  static Future<void> debugResetAndWait() {
    debugReset();
    return _measurementHostBarrier;
  }

  static void _handleLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        scheduleMicrotask(() => SurfaceRefreshRegistry.instance.onAppResumed());
        return;
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        // Every non-resumed state flushes analytics; only a true background
        // (paused/hidden) pauses the update-channel subscriptions — a
        // transient inactive (e.g. the app switcher) must not tear them down.
        if (state == AppLifecycleState.hidden ||
            state == AppLifecycleState.paused) {
          SurfaceRefreshRegistry.instance.onAppBackgrounded();
        }
    }
  }
}

/// Lifecycle observer for refresh and analytics work. Registered on
/// [Restage.configure] and removed on [Restage.debugReset].
class _RestageLifecycleObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    Restage._handleLifecycleState(state);
  }
}
