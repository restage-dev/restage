import 'dart:async';
import 'dart:convert';
import 'dart:ui' show AppLifecycleState, Locale;

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter/widgets.dart'
    show WidgetsBinding, WidgetsBindingObserver;
import 'package:restage_shared/restage_shared.dart';
import 'package:restage_core/restage_core.dart'
    show InstalledIconTable, RestageIconTable;

import '../analytics/analytics_identity.dart';
import '../analytics/root_analytics_context.dart';
import '../commerce/commerce_store_adapter.dart' show CommerceStoreAdapter;
import '../commerce/restage_commerce.dart'
    show
        RestageCommerce,
        CommerceRuntimeContext,
        activateRestageCommerce,
        debugRestageCommerceAdapter,
        debugResetRestageCommerce,
        notifyRestageCommerceConfigurationChanged,
        notifyRestageCommerceForegrounded,
        notifyRestageCommerceIdentityChanged,
        restageCommerceInstance;
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
import '../delivery/raced_surface_resolver.dart';
import '../delivery/render_deadline.dart';
import '../delivery/surface_artifact_store.dart';
import '../delivery/surface_ref.dart';
import '../delivery/surface_delivery_receipt.dart';
import '../delivery/surface_delivery_receipt_batch.dart';
import '../delivery/surface_delivery_receipt_uploader.dart';
import '../events/restage_event.dart';
import '../flow/flow_descriptors.dart';
import '../flow/flow_experiment_mount.dart'
    show FlowExperimentPresentationResolver;
import '../flow/flow_resolver.dart';
import '../flow/server_flow_resolver.dart';
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
import 'builtin_icon_table.dart';
import 'restage_widget_libraries.dart';
import 'restage_widget_registration.dart';
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

  /// Activates commerce with an application-configured store [adapter].
  ///
  /// Call this once during application startup. Adding an adapter package alone
  /// does not activate commerce.
  static void activateCommerce(CommerceStoreAdapter adapter) {
    activateRestageCommerce(
      adapter,
      rpcClientProvider: _requireRpcClient,
      applicationAnonymousTokenProvider: _commerceAnonymousToken,
      runtimeContextProvider: _commerceRuntimeContext,
    );
  }

  static Future<String> _commerceAnonymousToken() {
    final identity =
        _analyticsIdentity ??= RootAnalyticsRuntime.createIdentity();
    return identity.anonymousId();
  }

  static CommerceRuntimeContext? _commerceRuntimeContext() {
    final apiKey = _apiKey;
    final baseUrl = _baseUrl;
    final endpoint =
        baseUrl == null ? null : _normalizedCommerceEndpoint(baseUrl);
    if (apiKey == null || endpoint == null) return null;
    final configurationGeneration = _configurationGeneration;
    final identity =
        _analyticsIdentity ??= RootAnalyticsRuntime.createIdentity();
    final identityGeneration = identity.generation;
    return CommerceRuntimeContext(
      configurationFingerprint: crypto.sha256
          .convert(utf8.encode('$endpoint\u0000$apiKey'))
          .toString(),
      applicationAnonymousTokenProvider: () async {
        // Resolve the captured owner before reset can replace its generation.
        if (identity.generation != identityGeneration) return null;
        return identity.anonymousId();
      },
      isCurrent: () => _isCurrentCommerceContext(
        configurationGeneration: configurationGeneration,
        identity: identity,
        identityGeneration: identityGeneration,
      ),
    );
  }

  static bool _isCurrentCommerceContext({
    required int configurationGeneration,
    required AnalyticsIdentity identity,
    required int identityGeneration,
  }) =>
      _configurationGeneration == configurationGeneration &&
      identical(_analyticsIdentity, identity) &&
      identity.generation == identityGeneration;

  static String? _normalizedCommerceEndpoint(String value) {
    final endpoint = Uri.tryParse(value);
    if (endpoint == null ||
        endpoint.scheme.isEmpty ||
        endpoint.host.isEmpty ||
        endpoint.userInfo.isNotEmpty) {
      return null;
    }
    final scheme = endpoint.scheme.toLowerCase();
    final host = endpoint.host.toLowerCase();
    final defaultPort = (scheme == 'https' && endpoint.port == 443) ||
        (scheme == 'http' && endpoint.port == 80);
    final port = endpoint.hasPort && !defaultPort ? ':${endpoint.port}' : '';
    var path = endpoint.path;
    while (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    if (path.isEmpty) path = '/';
    final query = endpoint.hasQuery ? '?${endpoint.query}' : '';
    return '$scheme://$host$port$path$query';
  }

  /// Explicit, opt-in governed Measurement operations.
  static final RestageMeasurement measurement = RestageMeasurement.internal();

  /// Explicit coordinator over independently-owned privacy operations.
  static final RestagePrivacy privacy = RestagePrivacy.internal();

  static void Function(SurfaceResolutionReport report)? _onSurfaceResolution;
  static String? _apiKey;
  static String? _reportedDeliveryConfiguration;
  static String? _baseUrl;
  static RestageEnvironment _environment = RestageEnvironment.production;
  static VariantResolver _defaultResolver = const AssetVariantResolver();
  static FlowResolver _defaultFlowResolver = const AssetFlowResolver();
  static SurfaceScreenResolver _defaultSurfaceScreenResolver =
      const AssetSurfaceScreenResolver();
  static int _configurationGeneration = 0;
  static bool _measurementEnabled = true;
  static Duration _renderDeadline = RenderDeadline.defaultDuration;
  static MeasurementHostConstructionOwner? _measurementHostOwner;
  static SurfaceAssignmentCredentialStore? _assignmentCredentialStore;
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
  /// With no [apiKey], or an empty or whitespace-only key, default resolvers
  /// use bundled artifacts and hosted clients, analytics, metering, and governed
  /// Measurement remain inactive. Reconfiguring without a key clears any prior
  /// hosted configuration. Explicit resolver overrides and local settings still
  /// apply. Generated typed screens can fall back to their authored widget.
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
  /// build ordinal (e.g. `412`), the device region (e.g. `se`), the device
  /// class (e.g. `phone`), the device language (e.g. `sv`) and the
  /// operating-system version (e.g. `17` on iOS, the API level `34` on
  /// Android) whenever the device can supply them, and omits any it cannot. A
  /// web build reads neither an app build ordinal nor an operating-system
  /// version and sends the rest. These facts travel regardless of
  /// [analyticsEnabled] and [measurementEnabled].
  ///
  /// With analytics disabled, hosted requests carry no analytics identifier and
  /// no assignment credential. The metering token that counts use of the hosted
  /// service is separate and is unaffected by that flag; the package README
  /// describes it in full. The device facts above are stored only when
  /// measurement is enabled and a session is created.
  ///
  /// [deliveryReceiptsEnabled] (default `true`) reports what each hosted
  /// presentation showed. A receipt carries the surface type and slug, the
  /// published version shown, where the content came from (fresh, held or
  /// bundled) and why, whether it painted or failed, the platform and app
  /// build, the selected route and a mount-to-paint latency bucket, bucketed
  /// to the minute. It carries no device, install or user identifier. Receipts
  /// batch in memory and post every 30 seconds and on app pause; a batch lost
  /// with the process is never resent, so the counts are lower bounds. Pass
  /// `false` to send none.
  ///
  /// [surfaces] lists generated surface references whose latest content is
  /// fetched in the background at startup, so a first mount can render it.
  /// Paywalls already stored on the device, and stored surfaces listed here,
  /// are refreshed the same way.
  ///
  /// [renderDeadline] (default 300 ms) bounds how long a mounted surface waits
  /// for fresh content. At the deadline it renders the last content this
  /// install accepted, the bundled asset, or the compiled widget, and the
  /// fetch continues in the background for the next mount.
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
  /// With no explicit catalog selection, installs core and the complete widget
  /// and icon families selected by [includeMaterial] and [includeCupertino].
  /// Both default to true. False omits a complete family contribution; explicit
  /// and generated-required entries remain available, including the shared
  /// Material Icon builder that can render Cupertino icons.
  ///
  /// Pass generated `kRestageWidgetRegistration` as [registerWidgets] to forward
  /// the same options. It runs once after shared configuration and before catalog
  /// bootstrap. The generated registration adds built-in widget and icon entries,
  /// preserving existing entries on collisions. Custom library registration
  /// retains its existing replacement behavior for the same namespace.
  /// Registration errors propagate after configuration has taken effect.
  /// Regenerate older outputs to obtain this registration object. A separate
  /// no-argument full registration stays inclusive and cannot be narrowed here.
  ///
  /// Without [registerWidgets], existing selections, including explicitly empty
  /// selections, are preserved independently for widgets and icons. Use
  /// [configureWithInstalledCatalog] for configuration without catalog bootstrap.
  static void configure({
    String? apiKey,
    String? baseUrl,
    bool analyticsEnabled = true,
    bool measurementEnabled = true,
    bool includeMaterial = true,
    bool includeCupertino = true,
    RestageWidgetRegistration? registerWidgets,
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
    bool deliveryReceiptsEnabled = true,
    Duration renderDeadline = const Duration(milliseconds: 300),
    List<RestageSurfaceRef> surfaces = const <RestageSurfaceRef>[],
  }) {
    configureWithInstalledCatalog(
      apiKey: apiKey,
      baseUrl: baseUrl,
      analyticsEnabled: analyticsEnabled,
      measurementEnabled: measurementEnabled,
      environment: environment,
      onSurfaceResolution: onSurfaceResolution,
      resolver: resolver,
      flowResolver: flowResolver,
      surfaceScreenResolver: surfaceScreenResolver,
      locale: locale,
      identity: identity,
      liveRefresh: liveRefresh,
      liveRefreshOverrides: liveRefreshOverrides,
      updateChannel: updateChannel,
      liveRefreshEdgeUrl: liveRefreshEdgeUrl,
      governedMeasurementTransportEnabled: governedMeasurementTransportEnabled,
      governedMeasurementTransport: governedMeasurementTransport,
      deliveryReceiptsEnabled: deliveryReceiptsEnabled,
      renderDeadline: renderDeadline,
      surfaces: surfaces,
    );
    registerWidgets?.call(
      includeMaterial: includeMaterial,
      includeCupertino: includeCupertino,
    );
    if (!InstalledWidgetLibraries.hasSelection) {
      final builtIn = RestageWidgetLibraries.builtIn(
        includeMaterial: includeMaterial,
        includeCupertino: includeCupertino,
      );
      if (identical(
          InstalledWidgetLibraries.current, RestageWidgetLibraries.none)) {
        InstalledWidgetLibraries.install(builtIn);
      } else {
        InstalledWidgetLibraries.add(builtIn);
      }
    }
    if (!InstalledIconTable.hasSelection) {
      final builtIn = builtInIconTable(
        includeMaterial: includeMaterial,
        includeCupertino: includeCupertino,
      );
      if (identical(InstalledIconTable.current, RestageIconTable.none)) {
        InstalledIconTable.install(builtIn);
      } else {
        InstalledIconTable.add(builtIn);
      }
    }
  }

  /// Configures Restage using only the catalog the app explicitly installs.
  ///
  /// Call generated `registerRestageWidgets()` before this method when using
  /// `catalog: derived`. Generated surface references can also add vocabulary
  /// later, before mounting. An empty selection remains empty. This entrypoint
  /// has no reference to the full built-in widget or icon catalogs, allowing
  /// unused catalog entries to be removed from release builds.
  ///
  /// All delivery, analytics, Measurement and refresh arguments have the same
  /// meaning as in [configure].
  static void configureWithInstalledCatalog({
    String? apiKey,
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
    bool deliveryReceiptsEnabled = true,
    Duration renderDeadline = const Duration(milliseconds: 300),
    List<RestageSurfaceRef> surfaces = const <RestageSurfaceRef>[],
  }) {
    if (governedMeasurementTransportEnabled &&
        governedMeasurementTransport != null) {
      throw ArgumentError(
        'Configure either governedMeasurementTransportEnabled or '
        'governedMeasurementTransport, not both.',
      );
    }
    apiKey = apiKey?.trim();
    if (apiKey == null || apiKey.isEmpty) {
      apiKey = null;
      baseUrl = null;
    }
    _configurationGeneration += 1;
    _measurementEnabled = measurementEnabled;
    _renderDeadline = renderDeadline;
    _onSurfaceResolution = onSurfaceResolution;
    _apiKey = apiKey;
    _baseUrl = baseUrl;
    SurfaceDeliveryReceiptUploader.instance.configure(
      baseUrl: baseUrl,
      apiKey: apiKey,
      enabled: deliveryReceiptsEnabled,
    );
    // A reconfiguration must never retain a client bound to the previous
    // origin or credential. Test clients can be reinstalled after configure.
    _rpcClient = null;
    _installIttAssignmentTransport();
    if (apiKey == null) {
      GovernedMeasurementPortRegistry.install(null);
    } else if (governedMeasurementTransport != null) {
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
        (apiKey == null
            ? const AssetVariantResolver()
            : RestageVariantResolver(
                apiKey: apiKey,
                environment: environment,
                baseUrl: baseUrl,
              ));
    _defaultFlowResolver = flowResolver ?? const AssetFlowResolver();
    _defaultSurfaceScreenResolver = surfaceScreenResolver ??
        (apiKey == null
            ? const AssetSurfaceScreenResolver()
            : RestageScreenResolver(
                apiKey: apiKey,
                environment: environment,
                baseUrl: baseUrl,
                rpcClientProvider: _requireRpcClient,
              ));
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
    SurfaceDeliveryEvidence.install(
      _noteSurfaceDeliveryArtifactFailed,
      rateLimited: _emitSurfaceDeliveryRateLimited,
    );
    _configureMeasurementHost(enabled: analyticsEnabled && measurementEnabled);
    if (apiKey != null) unawaited(_prefetchSurfaces(surfaces));
    notifyRestageCommerceConfigurationChanged();
    _reportDeliveryConfiguration(
      hasResolverOverride: resolver != null ||
          flowResolver != null ||
          surfaceScreenResolver != null,
    );
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

  /// Fetches at most this many surfaces at once when prefetching.
  static const int _prefetchConcurrency = 4;

  // Background fetches create no assignment: they are not mounts.
  static Future<void> _prefetchSurfaces(
      List<RestageSurfaceRef> surfaces) async {
    final apiKey = _apiKey;
    if (apiKey == null) return;
    final generation = _configurationGeneration;
    final scope = SurfaceStoreKey.scopeFor(
      apiKey: apiKey,
      environment: _environment.name,
    );
    // Registers every listed reference with its resolver before revalidating.
    final listed = <SurfaceStoreKey>{
      for (final ref in surfaces) _storeKeyFor(scope, ref),
    };
    final keys = <SurfaceStoreKey>{...listed};
    try {
      for (final key in await sharedSurfaceArtifactStore.keys()) {
        // A stored flow or screen can only be re-gated through its reference.
        if (key.scope != scope) continue;
        if (key.surfaceType != Surface.paywall.wireName &&
            !listed.contains(key)) {
          continue;
        }
        keys.add(key);
      }
    } on Object {
      // An unreadable store still lets the listed surfaces prefetch.
    }
    // Stay off the first frame: prefetch starts once it has rendered.
    try {
      await SchedulerBinding.instance.endOfFrame;
    } on Object {
      // No binding yet: nothing to render, so nothing to stay off.
    }
    if (generation != _configurationGeneration) return;
    final queue = keys.toList();
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        if (generation != _configurationGeneration) return;
        final key = queue.removeAt(0);
        final resolver = _racedResolverFor(key);
        if (resolver == null) continue;
        try {
          await resolver.fresh(key, sendAssignmentKey: false);
        } on Object {
          // A failed prefetch leaves the surface for its next mount.
        }
      }
    }

    await Future.wait([
      for (var i = 0; i < _prefetchConcurrency; i += 1) worker(),
    ]);
  }

  /// The store key for [ref] under the configured credential, using
  /// [resolver]'s own key when it is a built-in hosted resolver.
  @internal
  static SurfaceStoreKey storeKeyFor(RestageSurfaceRef ref,
      {Object? resolver}) {
    final apiKey = _apiKey;
    final scope = apiKey == null
        ? ''
        : SurfaceStoreKey.scopeFor(
            apiKey: apiKey,
            environment: _environment.name,
          );
    return _storeKeyFor(scope, ref, resolver: resolver);
  }

  static SurfaceStoreKey _storeKeyFor(
    String scope,
    RestageSurfaceRef ref, {
    Object? resolver,
  }) {
    final paywalls = resolver ?? _defaultResolver;
    final flows = resolver ?? _defaultFlowResolver;
    final screens = resolver ?? _defaultSurfaceScreenResolver;
    if (resolver is FlowExperimentPresentationResolver &&
        ref is SurfaceFlowRef) {
      return resolver.storeKey;
    }
    return switch (ref) {
      PaywallRef(:final id) when paywalls is RestageVariantResolver =>
        paywalls.storeKeyFor(id),
      SurfaceFlowRef() when flows is ServerFlowResolver =>
        flows.storeKeyFor(ref),
      SurfaceScreenRef() when screens is RestageScreenResolver =>
        screens.storeKeyFor(ref),
      PaywallRef(:final id) => SurfaceStoreKey(
          scope: scope,
          surfaceType: Surface.paywall.wireName,
          slug: id,
          contractVersion: 0,
        ),
      SurfaceFlowRef(:final surface, :final id) => SurfaceStoreKey(
          scope: scope,
          surfaceType: surface.wireName,
          slug: id,
          contractVersion: 0,
        ),
      SurfaceScreenRef(:final slug, :final contractVersion) => SurfaceStoreKey(
          scope: scope,
          surfaceType: SurfaceSourceKind.screen.wireName,
          slug: slug,
          contractVersion: contractVersion,
        ),
      _ => throw ArgumentError.value(ref, 'surfaces', 'unknown reference'),
    };
  }

  static RacedSurfaceResolver<Object?>? _racedResolverFor(SurfaceStoreKey key) {
    final Object resolver;
    if (key.surfaceType == Surface.paywall.wireName) {
      resolver = _defaultResolver;
    } else if (key.surfaceType == SurfaceSourceKind.screen.wireName) {
      resolver = _defaultSurfaceScreenResolver;
    } else {
      resolver = _defaultFlowResolver;
    }
    return racedResolverOf<Object?>(resolver);
  }

  /// The install's last accepted surface deliveries.
  @internal
  static SurfaceArtifactStore get surfaceArtifactStore =>
      sharedSurfaceArtifactStore;

  static void _reportDeliveryConfiguration(
      {required bool hasResolverOverride}) {
    if (!kDebugMode) return;
    final String description;
    if (hasResolverOverride) {
      description = 'custom delivery resolvers configured';
    } else if (_apiKey == null) {
      description = 'bundled artifacts — no credential configured';
    } else if (_baseUrl == null || _baseUrl!.isEmpty) {
      description = 'bundled artifacts — no hosted origin configured';
    } else {
      final uri = Uri.tryParse(_baseUrl!);
      final origin = uri != null &&
              (uri.scheme == 'http' || uri.scheme == 'https') &&
              uri.host.isNotEmpty
          ? uri.origin
          : 'configured origin';
      description = 'hosted delivery — $origin';
    }
    if (_reportedDeliveryConfiguration == description) return;
    _reportedDeliveryConfiguration = description;
    debugPrint('[restage] $description');
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
    required String? apiKey,
    String? baseUrl,
    Locale? locale,
    bool enabled = true,
    required RestageEnvironment environment,
  }) {
    if (!enabled || apiKey == null || baseUrl == null || baseUrl.isEmpty) {
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
    _assignmentCredentialStore = null;
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
    );
    _assignmentCredentialStore = credentialStore;
    SurfaceCanonicalCarrierProvider.enableAssignmentRetention(namespace);
    SurfaceAssignmentKeyProvider.install(
      key: credentialStore.resolve,
      identityGeneration: () => credentialStore.generation,
      localKey: credentialStore.resolveLocal,
      registration: () => configurationGeneration == _configurationGeneration
          ? credentialStore.capture()
          : Future.value(null),
      confirmedKey: () => configurationGeneration == _configurationGeneration
          ? credentialStore.currentHandle
          : null,
      confirmRegistration: (attempt, start, handle, expiry, serverNow) =>
          credentialStore.confirm(
        attempt: attempt,
        localRequestStartMicros: start,
        credentialHandle: handle,
        expiresAtMicros: expiry,
        serverNowMicros: serverNow,
      ),
      refuseRegistration: credentialStore.refuse,
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
    final credentialStore = _assignmentCredentialStore;
    final owner = MeasurementHostConstructionOwner.production(
      startupBarrier: _measurementHostBarrier,
      onRegistrationRefused: credentialStore == null
          ? null
          : (fingerprint) async {
              if (generation != _configurationGeneration ||
                  !identical(_assignmentCredentialStore, credentialStore)) {
                return;
              }
              await credentialStore.refuseFingerprint(fingerprint);
            },
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

  /// Rotates the local pseudonymous actor and session.
  ///
  /// Clears persisted assignment credentials, held assignments and the current
  /// surface-session identity. The next resolution registers a new unlinked
  /// unit and selects a new assignment. Pending first-paint work is invalidated;
  /// accepted presentations stay pinned.
  ///
  /// This sends no server request and does **not** erase uploaded records.
  /// The separate metering identifier remains unchanged. Use [privacy] to
  /// request erasure.
  /// Inert until [configure] supplies a `baseUrl`.
  static void reset() {
    unawaited(clearSurfaceArtifactStores());
    _measurementHostOwner?.resetSdkRuntimeSession();
    _rpcClient?.forgetPublicationBindings();
    final identity = _analyticsIdentity;
    if (identity == null) return;
    // reset() advances the in-memory generation synchronously before its first
    // persistence await. Reject pending hosted paint work against that new
    // generation now; accepted presentations remain pinned.
    final identityReset = identity.reset();
    notifyRestageCommerceIdentityChanged();
    SurfaceCanonicalCarrierProvider.clearHeldAssignments();
    unawaited(SurfaceAssignmentPersistence.forget(
      afterIdentityReset: identityReset,
    ));
    RootAnalyticsRuntime.retireAll();
    FirstPaintLeaseTransaction.revalidatePendingAfterIdentityReset();
  }

  /// Registers app-defined [widgets] under [library] before surfaces mount.
  /// Re-registering a namespace replaces its previous registration.
  ///
  /// Generate the factory list from `@RestageWidget` classes with
  /// `dart run build_runner build`. Generated registration passes the library's
  /// [capabilityVersion] when a delivery requirement needs it. An unversioned
  /// library satisfies no positive version requirement. [compatibleSince]
  /// (default 1) is the oldest required version the library still renders;
  /// content requiring an older version uses its fallback.
  ///
  /// Debug assertions reject reserved namespaces, preview-only constructors,
  /// duplicate widget names and versions below 1. [compatibleSince] must be
  /// between 1 and [capabilityVersion].
  static void registerWidgetLibrary(
    WidgetLibrary library, {
    required List<RestageWidgetFactory> widgets,
    int? capabilityVersion,
    int? compatibleSince,
  }) {
    LibraryRuntimeRegistry.register(
      library,
      widgets,
      capabilityVersion: capabilityVersion,
      compatibleSince: compatibleSince,
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

  static void _noteSurfaceDeliveryArtifactFailed({
    required Surface surfaceType,
    required String surfaceSlug,
    required int version,
    required String reason,
  }) {
    SurfaceDeliveryReceiptBatch.instance.noteRefusal(
      surfaceType,
      surfaceSlug,
      reason == 'transport'
          ? SurfaceDeliveryReceiptReason.offline
          : SurfaceDeliveryReceiptReason.serverError,
    );
  }

  static void _emitSurfaceDeliveryRateLimited({
    required Surface surfaceType,
    required String surfaceSlug,
    required Duration retryAfter,
  }) {
    SurfaceDeliveryReceiptBatch.instance.noteRefusal(
      surfaceType,
      surfaceSlug,
      SurfaceDeliveryReceiptReason.throttled,
    );
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
  /// Without a configured credential, this is [AssetVariantResolver]. After
  /// [configure] with a key and no override, this is [RestageVariantResolver], which
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
  /// Without a configured credential, this is [AssetSurfaceScreenResolver].
  /// With a key and no override, it validates hosted delivery against
  /// the generated standalone-screen manifest before rendering.
  static SurfaceScreenResolver get defaultSurfaceScreenResolver =>
      _defaultSurfaceScreenResolver;

  /// Monotonic identity of mutable SDK configuration used by hosted mounts.
  @internal
  static int get configurationGeneration => _configurationGeneration;

  @internal
  static bool get isMeasurementEnabled => _measurementEnabled;

  /// How long a mount waits before rendering local content.
  @internal
  static Duration get renderDeadline => _renderDeadline;

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

  /// The environment passed to [configure].
  @internal
  static RestageEnvironment get configuredEnvironment => _environment;

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
    notifyRestageCommerceConfigurationChanged();
  }

  /// Test-only — exposes the current [RestageRpcClient] for inspection.
  @internal
  static RestageRpcClient? get debugRestageRpcClient => _rpcClient;

  /// Test-only — exposes the active commerce store adapter.
  @internal
  static CommerceStoreAdapter? get debugCommerceStoreAdapter =>
      debugRestageCommerceAdapter;

  /// Resets all module-global state. **Tests must call this in `setUp`
  /// to avoid leaking state between tests.** Native fixtures that dispose
  /// worker resources must await [debugResetAndWait] instead.
  @visibleForTesting
  static void debugReset() {
    _configurationGeneration += 1;
    _configureMeasurementHost(enabled: false, privacyReset: false);
    _onSurfaceResolution = null;
    _apiKey = null;
    _reportedDeliveryConfiguration = null;
    _baseUrl = null;
    _environment = RestageEnvironment.production;
    _defaultResolver = const AssetVariantResolver();
    _defaultFlowResolver = const AssetFlowResolver();
    _defaultSurfaceScreenResolver = const AssetSurfaceScreenResolver();
    _measurementEnabled = true;
    _renderDeadline = RenderDeadline.defaultDuration;
    unawaited(clearSurfaceArtifactStores());
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
    SurfaceDeliveryReceiptUploader.debugReset();
    SurfaceDeliveryReceiptBatch.debugReset();
    _unregisterLifecycleObserver();
    LibraryRuntimeRegistry.clear();
    resetRestagePaywallCache();
    SurfaceRefreshRegistry.instance.debugReset();
    GovernedMeasurementPortRegistry.debugReset();
    _commerceReset = debugResetRestageCommerce();
  }

  static Future<void> _commerceReset = Future<void>.value();

  /// Resets state synchronously and acknowledges retirement of native workers.
  /// Invoke and await this inside the async context that owns those resources.
  @visibleForTesting
  static Future<void> debugResetAndWait() {
    debugReset();
    return Future.wait<void>(<Future<void>>[
      _measurementHostBarrier,
      _commerceReset,
    ]);
  }

  static void _handleLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        notifyRestageCommerceForegrounded();
        scheduleMicrotask(() => SurfaceRefreshRegistry.instance.onAppResumed());
        return;
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        // Every non-resumed state flushes analytics; only a true background
        // (paused/hidden) pauses the update-channel subscriptions — a
        // transient inactive (e.g. the app switcher) must not tear them down.
        unawaited(SurfaceDeliveryReceiptUploader.instance.flush());
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
