import 'dart:async';
import 'dart:ui' show AppLifecycleState, Locale;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart'
    show WidgetsBinding, WidgetsBindingObserver;
import 'package:http/http.dart' as http;
import 'package:restage_shared/restage_shared.dart';

import '../analytics/analytics_event_mapper.dart';
import '../analytics/analytics_identity.dart';
import '../analytics/analytics_transport.dart';
import '../billing/anonymous_token.dart';
import '../billing/billing_gateway.dart';
import '../billing/in_app_purchase_gateway.dart';
import '../billing/signed_native_offer.dart';
import '../restage_rpc_client/restage_rpc_client.dart';
import '../events/event_enums.dart';
import '../events/restage_event.dart';
import '../flow/flow_resolver.dart';
import '../resolver/asset_variant_resolver.dart';
import '../resolver/restage_variant_resolver.dart';
import '../resolver/variant_resolver.dart';
import 'library_runtime_registry.dart';
import 'restage_identity.dart';
import 'restage_paywall.dart';
import 'restage_widget_factory.dart';

/// Restage SDK static facade.
///
/// Configure app-wide product, billing, entitlement, and resolver settings at
/// startup when needed. Bundled paywalls and onboarding flows can also be
/// rendered directly with `AssetVariantResolver` and `AssetFlowResolver`.
abstract final class Restage {
  Restage._();

  static String? _apiKey;
  static String? _baseUrl;
  static RestageEnvironment _environment = RestageEnvironment.production;
  static VariantResolver _defaultResolver = const AssetVariantResolver();
  static FlowResolver _defaultFlowResolver = const AssetFlowResolver();
  static List<RestageProduct> _products = const [];
  static Map<String, RestageProduct> _productsBySlot = const {};
  static Map<String, RestageProduct> _productsById = const {};

  static StreamController<RestageEvent>? _events;

  /// Stored keyed by entitlement id so re-grants from a different `source`
  /// (e.g. purchase → restore) replace the metadata in place rather than
  /// creating a duplicate entry alongside the existing one.
  static final Map<String, RestageEntitlement> _entitlementsById = {};
  static StreamController<Set<RestageEntitlement>>? _entitlementsController;
  // Lazily instantiated. Direct construction touches `InAppPurchase.instance`,
  // which depends on platform channels — eager init breaks pure-Dart unit
  // tests. The `billingGateway` getter materializes on first read; tests that
  // never invoke a purchase / restore never instantiate it.
  static BillingGateway? _billingGateway;

  /// Tracks the server's last-reported state per entitlement id. Drives
  /// the reconciliation transition matrix in [_reconcileFromServer]:
  /// transitions (active ↔ expired/refunded, missing) compare the
  /// incoming summary against this snapshot.
  static final Map<String, EntitlementSummary> _lastSyncedSummaryById = {};

  static AnonymousTokenStore _anonymousTokenStore = AnonymousTokenStore();
  static RestageRpcClient? _rpcClient;
  static _RestageLifecycleObserver? _lifecycleObserver;

  /// The Restage SDK version stamped into every analytics event's app context.
  static const String sdkVersion = '0.1.0';

  // The behavioral-analytics transport. Active only when [configure] is given a
  // [baseUrl]; otherwise `track`/`identify`/`reset` are inert (no endpoint).
  static AnalyticsIdentity? _analyticsIdentity;
  static AnalyticsTransport? _analyticsTransport;
  static AnalyticsAppContext? _analyticsAppContext;

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
  /// Pass [flowResolver] to choose the onboarding flow source. When omitted,
  /// flows use [AssetFlowResolver]; this method does not enable hosted flow
  /// delivery.
  ///
  /// [baseUrl] is the entitlement service origin (e.g.
  /// `'https://api.example.com'`). When omitted, the SDK does not call
  /// the entitlement endpoints — the optimistic local-grant path stays
  /// the only source of entitlement state. Set this once your hosted
  /// (or self-hosted) entitlement service is reachable.
  ///
  /// [analyticsEnabled] (default `true`) controls the conversion-analytics
  /// transport. When `false`, no analytics events are sent even if [baseUrl] is
  /// set — keeps hosted delivery + entitlement sync while opting out of
  /// analytics. With no [baseUrl] analytics is already inactive regardless of
  /// this flag.
  ///
  /// [identity] is an **experimental, not-yet-active** hook (see
  /// [RestageIdentity]). The callback is accepted but is not currently invoked,
  /// and the identity it would return is not yet attached to resolver requests
  /// or analytics. Wiring it has no runtime effect today; it is accepted now so
  /// the integration shape can stabilize.
  static void configure({
    required String apiKey,
    String? baseUrl,
    bool analyticsEnabled = true,
    RestageEnvironment environment = RestageEnvironment.production,
    VariantResolver? resolver,
    FlowResolver? flowResolver,
    List<RestageProduct> products = const [],
    Locale? locale,
    Future<RestageIdentity?> Function()? identity,
    BillingGateway? billingGateway,
  }) {
    assert(
      products.map((p) => p.slot).toSet().length == products.length,
      'Restage.configure: products contain duplicate slots',
    );
    assert(
      products.map((p) => p.id).toSet().length == products.length,
      'Restage.configure: products contain duplicate ids',
    );
    _apiKey = apiKey;
    _baseUrl = baseUrl;
    _environment = environment;
    _defaultResolver = resolver ??
        RestageVariantResolver(
          apiKey: apiKey,
          environment: environment,
          baseUrl: baseUrl,
        );
    _defaultFlowResolver = flowResolver ?? const AssetFlowResolver();
    _products = List.unmodifiable(products);
    _productsBySlot = Map.unmodifiable({for (final p in products) p.slot: p});
    _productsById = Map.unmodifiable({for (final p in products) p.id: p});
    // The current bundled asset resolvers do not read `locale` or `identity`.
    if (billingGateway != null) {
      _billingGateway = billingGateway;
    }
    _registerLifecycleObserver();
    _configureAnalytics(
      apiKey: apiKey,
      baseUrl: baseUrl,
      locale: locale,
      enabled: analyticsEnabled,
    );
    if (baseUrl != null) {
      // Microtask-defer so `configure` stays sync-returning. The cold-start
      // sync runs after the host's `runApp` settles. Re-calls of
      // `configure` re-schedule — supporting hosts that switch
      // environment / base-URL at runtime.
      scheduleMicrotask(() async {
        // Warm the persisted anonymous id so events firing during cold start
        // carry it synchronously rather than racing the prefs read. Best-effort
        // — the bridge resolves it lazily, so a prefs fault never breaks boot.
        try {
          await _analyticsIdentity?.anonymousId();
        } on Object catch (_) {}
        await syncEntitlements();
      });
    }
  }

  /// Configures the analytics transport from [apiKey] + [baseUrl]. With no
  /// [baseUrl], or when [enabled] is false, the transport is disabled (no
  /// endpoint) and `track`/`identify`/`reset` are inert.
  static void _configureAnalytics({
    required String apiKey,
    String? baseUrl,
    Locale? locale,
    bool enabled = true,
  }) {
    if (!enabled || baseUrl == null || baseUrl.isEmpty) {
      _analyticsTransport = null;
      return;
    }
    _analyticsIdentity ??= AnalyticsIdentity();
    _analyticsAppContext = AnalyticsAppContext(
      platform: _platformWireName(),
      locale: locale?.toLanguageTag() ?? 'und',
      sdkVersion: sdkVersion,
    );
    _analyticsTransport = AnalyticsTransport(
      endpointUrl: _analyticsEndpoint(baseUrl),
      apiKey: apiKey,
      httpClient: debugAnalyticsHttpClient,
      onError: (error, _) =>
          debugPrint('[restage][analytics] dropped a batch: $error'),
    );
  }

  static String _analyticsEndpoint(String baseUrl) {
    final trimmed = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return '$trimmed/analytics/events';
  }

  static String _platformWireName() {
    if (kIsWeb) return AnalyticsPlatform.web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return AnalyticsPlatform.ios;
      case TargetPlatform.android:
        return AnalyticsPlatform.android;
      case TargetPlatform.macOS:
        return AnalyticsPlatform.macos;
      case TargetPlatform.windows:
        return AnalyticsPlatform.windows;
      case TargetPlatform.linux:
        return AnalyticsPlatform.linux;
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }

  /// App-wide event stream. Receives presentation, interaction, conversion,
  /// and lifecycle events (entitlement changes fire even when no paywall
  /// is mounted).
  ///
  /// Broadcast — multiple listeners supported; events are not buffered for
  /// late subscribers, so **subscribe before [Restage.configure] returns**
  /// to avoid missing entitlement / purchase events fired during cold-start
  /// auto-restore.
  static Stream<RestageEvent> get events {
    _events ??= StreamController<RestageEvent>.broadcast();
    return _events!.stream;
  }

  /// Stream of the full set of currently-granted entitlements. Emits the
  /// updated [Set] on every grant or revoke.
  ///
  /// Broadcast — multiple listeners supported; not buffered for late
  /// subscribers. Use [currentEntitlements] for a synchronous snapshot.
  static Stream<Set<RestageEntitlement>> get entitlements {
    _entitlementsController ??=
        StreamController<Set<RestageEntitlement>>.broadcast();
    return _entitlementsController!.stream;
  }

  /// Synchronous snapshot of the currently-granted entitlements.
  static Set<RestageEntitlement> get currentEntitlements =>
      Set.unmodifiable(_entitlementsById.values);

  /// Attaches the customer's [userId] to subsequent analytics events.
  ///
  /// Opt-in only — the host owns consent. Inert until [configure] is given a
  /// `baseUrl`.
  ///
  /// **[attributes] is experimental and not yet active.** It is a reserved hook
  /// for a future trait channel: values passed today are accepted but silently
  /// dropped — never uploaded or attached to any event. The parameter is
  /// published now so the call shape can stabilize; do not depend on any
  /// runtime effect from it yet.
  static void identify(String userId, {Map<String, Object?>? attributes}) {
    _analyticsIdentity?.identify(userId);
  }

  /// Resets the anonymous analytics actor (the privacy "forget me" primitive):
  /// mints a fresh `anonymousId`, clears any identified `userId`, and rotates
  /// the session. Inert until [configure] is given a `baseUrl`.
  static void reset() {
    final identity = _analyticsIdentity;
    if (identity != null) unawaited(identity.reset());
  }

  /// Records a custom analytics event named [eventName] with optional [args].
  ///
  /// Inert until [configure] is given a `baseUrl`. `args` becomes the event's
  /// `properties` after the reserved-key scrub — **`data` and `context` are
  /// reserved top-level keys** (host render context) and are dropped.
  static void track(String eventName, {Map<String, Object?>? args}) {
    final transport = _analyticsTransport;
    final identity = _analyticsIdentity;
    final appContext = _analyticsAppContext;
    if (transport == null || identity == null || appContext == null) return;
    final snapshot = _IdentitySnapshot.capture(identity);
    unawaited(
      _enqueue(
        transport,
        identity,
        (anonymousId) => AnalyticsEvent(
          eventId: identity.newEventId(),
          name: eventName,
          occurredAt: DateTime.now().toUtc(),
          surface: null,
          surfaceSessionId: snapshot.surfaceSessionId,
          anonymousId: anonymousId,
          sessionId: snapshot.sessionId,
          userId: snapshot.userId,
          appContext: appContext,
          properties: scrubReservedKeys(args ?? const {}),
        ),
        label: 'track("$eventName")',
      ),
    );
  }

  /// Resolves the anonymous id (cached, else awaited) and enqueues the event
  /// built by [build]. The shared fail-safe enqueue path for both the custom
  /// `track` call and the `fireEvent` bridge — never throws into host code.
  static Future<void> _enqueue(
    AnalyticsTransport transport,
    AnalyticsIdentity identity,
    AnalyticsEvent Function(String anonymousId) build, {
    required String label,
  }) async {
    try {
      final anonymousId =
          identity.cachedAnonymousId ?? await identity.anonymousId();
      transport.enqueue(build(anonymousId));
    } on Object catch (error) {
      debugPrint('[restage][analytics] $label dropped: $error');
    }
  }

  /// Begins a surface-presentation session (mount), minting a new
  /// `surfaceSessionId` for events fired during this presentation. Internal —
  /// called by `RestagePaywall` on mount. Paired with [endSurfaceSession].
  static void beginSurfaceSession() {
    final identity = _analyticsIdentity;
    if (identity != null) identity.surfaceSessionId = identity.newEventId();
  }

  /// Ends the current surface-presentation session (dismiss). Internal.
  static void endSurfaceSession() {
    _analyticsIdentity?.surfaceSessionId = null;
  }

  /// Register a customer-defined widget [library] so its [widgets] can be
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
  /// generated registration helper passes it automatically; omit it for an
  /// unversioned library (which then satisfies no positive requirement).
  ///
  /// Asserts (debug only): [library] must not use a reserved built-in
  /// namespace (`restage.core` / `restage.material` / `restage.cupertino`),
  /// [widgets] must not contain duplicate names, and [capabilityVersion] (when
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

  // --- Internal API used by RestagePaywall + billing layer ---

  /// Adds [event] to the [events] broadcast stream AND bridges it to the
  /// analytics transport. Internal — used by `RestagePaywall` and the billing
  /// layer.
  ///
  /// The broadcast leg short-circuits when nothing is listening to [events]; the
  /// analytics leg is independent (it must capture events even when the host
  /// does not subscribe to [events]).
  static void fireEvent(RestageEvent event) {
    final controller = _events;
    if (controller != null && controller.hasListener) {
      controller.add(event);
    }
    _bridgeEventToAnalytics(event);
  }

  static void _bridgeEventToAnalytics(RestageEvent event) {
    final transport = _analyticsTransport;
    final identity = _analyticsIdentity;
    final appContext = _analyticsAppContext;
    if (transport == null || identity == null || appContext == null) return;
    // Prod does not emit the Tier-2 session summary (capture is v1).
    if (isProdSuppressedAnalyticsEvent(event.name)) return;
    // Capture the mutable identity snapshot SYNCHRONOUSLY: `surfaceSessionId`
    // can change on the next mount/dismiss before the (possibly async)
    // anonymousId resolves, so the event must bind the values at fire time.
    final snapshot = _IdentitySnapshot.capture(identity);
    unawaited(
      _enqueue(
        transport,
        identity,
        (anonymousId) => mapRestageEventToEnvelope(
          event,
          eventId: identity.newEventId(),
          anonymousId: anonymousId,
          sessionId: snapshot.sessionId,
          surfaceSessionId: snapshot.surfaceSessionId,
          userId: snapshot.userId,
          appContext: appContext,
          now: DateTime.now().toUtc(),
        ),
        label: event.name,
      ),
    );
  }

  /// Records [e] as granted and fires an [EntitlementGranted] on [events].
  ///
  /// Always fires the event — even when the entitlement was already in the
  /// granted set under the same id. The [source] of the new grant is
  /// preserved in the stored entry (replacing whatever source was there
  /// before). Hosts watching for `restore`-sourced grants on an already-
  /// granted entitlement (e.g. to show a "Welcome back!" toast) rely on
  /// this re-fire signal.
  ///
  /// The [entitlements] stream emits an updated snapshot only when the set
  /// actually changed (new id) or when the stored entry's metadata
  /// differs (new source / expiry).
  ///
  /// Internal — used by the billing layer.
  static void grantEntitlement(
    RestageEntitlement e, {
    String productId = '',
  }) {
    final previous = _entitlementsById[e.id];
    _entitlementsById[e.id] = e;
    fireEvent(EntitlementGranted(
      entitlementId: e.id,
      productId: productId,
      source: e.source,
      expiresAtMs: e.expiresAtMs,
    ));
    if (previous != e) {
      _entitlementsController?.add(currentEntitlements);
    }
  }

  /// Removes the entitlement matching [e]'s id from the granted set, emits
  /// the updated [entitlements] snapshot, and fires an [EntitlementRevoked]
  /// on [events]. No-op when no entitlement under that id was present.
  /// Internal — used by the billing layer.
  static void revokeEntitlement(
    RestageEntitlement e, [
    RevokeReason reason = RevokeReason.expired,
  ]) {
    if (_entitlementsById.remove(e.id) == null) return;
    _entitlementsController?.add(currentEntitlements);
    fireEvent(EntitlementRevoked(
      entitlementId: e.id,
      reason: reason,
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

  /// Resolver used when `RestageOnboarding` is constructed without an explicit
  /// `resolver:` parameter.
  ///
  /// The default is [AssetFlowResolver]; hosted flow delivery is not installed
  /// by [configure].
  static FlowResolver get defaultFlowResolver => _defaultFlowResolver;

  /// Products configured via [configure]. Used by the slot resolution
  /// path in `RestagePaywall` and the billing layer.
  static List<RestageProduct> get configuredProducts => _products;

  /// Look up a product by its author-named slot (e.g. `'primary'`).
  /// Returns `null` when no configured product matches.
  static RestageProduct? findProductBySlot(String slot) =>
      _productsBySlot[slot];

  /// Look up a product by its store identifier. Returns `null` when no
  /// configured product matches.
  static RestageProduct? findProductById(String id) => _productsById[id];

  /// Grant the entitlement associated with [productId] (if any product is
  /// configured under that id), tagging it with [source]. No-op when the
  /// product is not configured. Used by the billing layer's purchase /
  /// restore success paths. The resulting [EntitlementGranted] event
  /// carries [productId] so hosts can correlate grants with purchases.
  ///
  /// When [productId] is not in the configured product set this method
  /// emits a debug-mode warning. Most commonly this happens during
  /// restore when the store returns a historical productId the host no
  /// longer ships — the user paid, but the SDK can't grant the
  /// entitlement without knowing which one to grant. The warning lets the
  /// developer notice the misconfiguration and ship a fix.
  static void grantEntitlementForProduct(
    String productId,
    EntitlementSource source,
  ) {
    final product = _productsById[productId];
    if (product == null) {
      assert(() {
        debugPrint(
          '[restage] ${source.name} returned productId "$productId" but no '
          'matching RestageProduct is configured — entitlement not granted. '
          'If this is a legacy product the user purchased previously, add '
          'it to Restage.configure(products: [...]) so the entitlement can '
          'be re-granted on restore.',
        );
        return true;
      }());
      return;
    }
    grantEntitlement(
      RestageEntitlement(id: product.entitlement, source: source),
      productId: productId,
    );
  }

  /// Billing gateway used by `RestagePaywall` to invoke purchase / restore
  /// flows when an RFW event resolves to [PurchaseInitiated] or
  /// [RestoreInitiated]. Defaults to [InAppPurchaseGateway] (lazily
  /// instantiated on first read); override via
  /// `Restage.configure(billingGateway:)`.
  ///
  /// The lazy-instantiated default threads the anonymous app-user token
  /// through to `PurchaseParam.applicationUserName` on every purchase /
  /// restore call. Hosts that pass an explicit [BillingGateway] via
  /// [configure] own the stamping themselves.
  static BillingGateway get billingGateway => _billingGateway ??=
      InAppPurchaseGateway(anonymousTokenProvider: _resolveAnonymousToken);

  static Future<String?> _resolveAnonymousToken() async {
    try {
      return await _anonymousTokenStore.getOrCreate();
    } on Object catch (error) {
      // SharedPreferences can throw on platforms that haven't initialized
      // their plugins yet. The stamping path is a defense-in-depth signal
      // for fraud detection; losing it on a degraded platform doesn't
      // block the purchase flow.
      debugPrint('[restage] anonymous token resolution failed: $error');
      return null;
    }
  }

  /// Purchases [productId], optionally selecting a Google Play [basePlanId] or
  /// applying the promotional offer named by [offerId]. Used by
  /// `RestagePaywall`'s purchase action; also callable directly.
  ///
  /// With no [offerId] this is a plain (no-discount) purchase. With an [offerId]
  /// the SDK resolves the offer for the current store and transports it through
  /// the gateway, threading one store-account token through both steps: on Apple
  /// it fetches a server-minted signature bound to that token; on Android it lets
  /// the gateway resolve the eligible offer token from the live product (no
  /// server). If the offer cannot be resolved, the active gateway cannot apply
  /// native offers, or the platform is unsupported, it fails closed with
  /// [RestageBillingErrorCodes.offerUnavailable] rather than charging the full
  /// price — the host/paywall decides whether to retry or present the base
  /// price. It never silently charges full price for a discount the user chose.
  ///
  /// [basePlanId] selects a specific Google Play subscription **base plan** at
  /// its standard price. A plain purchase of a Play subscription that has **more
  /// than one base plan** requires it: with no [basePlanId] the SDK fails closed
  /// with [RestageBillingErrorCodes.basePlanSelectionRequired] rather than buy an
  /// arbitrary plan or silently apply a discount. With [offerId] it scopes the
  /// offer to that base plan (disambiguating an offer id shared across base
  /// plans). It has no effect on Apple subscriptions or one-time products, so
  /// cross-platform call sites may pass it unconditionally.
  static Future<PurchaseOutcome> purchaseProduct(
    String productId, {
    String? offerId,
    String? basePlanId,
  }) {
    // Only an absent offerId is a plain purchase. A present-but-empty offerId
    // is a malformed offer request and fails closed below — it must never
    // silently collapse to a full-price purchase.
    if (offerId == null) {
      return billingGateway.purchase(productId, basePlanId: basePlanId);
    }
    return _purchaseWithOffer(productId, offerId, basePlanId);
  }

  static Future<PurchaseOutcome> _purchaseWithOffer(
    String productId,
    String offerId,
    String? basePlanId,
  ) async {
    PurchaseOutcome unavailable(String message) => PurchaseOutcome.failed(
          productId: productId,
          errorCode: RestageBillingErrorCodes.offerUnavailable,
          message: message,
        );

    if (offerId.isEmpty) {
      return unavailable('An empty offer id cannot be applied.');
    }

    final gateway = billingGateway;
    if (gateway is! OfferCapableBillingGateway) {
      return unavailable('The active billing gateway cannot apply offers.');
    }

    // Resolve the store-account token ONCE and thread the same value into the
    // signature request and the purchase: the signature commits to the token,
    // so a mismatch makes the store reject the offer.
    final rawToken = await _resolveAnonymousToken();
    final token =
        (rawToken != null && AnonymousTokenStore.isValidUuid(rawToken))
            ? rawToken
            : null;
    if (token == null) {
      return unavailable('A promotional offer requires a store-account token.');
    }

    // Branch by store platform. The two stores resolve an offer differently:
    // Apple needs a server-minted signature (resolved here), while Google
    // resolves the eligible offer token client-side at the gateway (no server).
    // Both dispatch into the same offer-capable gateway call, threading the same
    // account token (Apple `appAccountToken` / Google `obfuscatedAccountId`).
    if (_isApplePlatform) {
      final client = _requireRpcClient();
      if (client == null) {
        return unavailable(
            'Promotional offers require a configured service URL.');
      }

      final signature = await client.mintOfferSignature(
        OfferSignatureRequest(
          productId: productId,
          offerId: offerId,
          appAccountToken: token,
        ),
      );
      if (signature == null ||
          signature.scheme != OfferSignatureScheme.legacy) {
        return unavailable('No promotional-offer signature was available.');
      }

      return gateway.purchaseWithOffer(
        productId: productId,
        appAccountToken: token,
        offer: AppleSignedOffer.fromSignature(
          offerId: offerId,
          signature: signature,
        ),
      );
    }

    if (_isAndroidPlatform) {
      // Google requires no server crypto: name the requested offer and let the
      // gateway resolve the eligible token from the live product, failing closed
      // if it cannot be matched. An optional basePlanId scopes the offer to a
      // specific base plan, disambiguating the rare case where the same offer id
      // recurs across base plans.
      return gateway.purchaseWithOffer(
        productId: productId,
        appAccountToken: token,
        offer: GoogleOffer(offerId: offerId, basePlanId: basePlanId),
      );
    }

    return unavailable(
        'Native promotional offers are not supported on this platform.');
  }

  /// Internal: reconciles the local entitlement set against the server's
  /// authoritative list. Dispatches the reserved transition events
  /// (`EntitlementGranted`, `SubscriptionRenewed`, `SubscriptionLapsed`,
  /// `EntitlementRevoked`) exactly once per transition, with the right
  /// payload.
  ///
  /// The matrix:
  ///   - Server has active, local didn't track it: `EntitlementGranted`.
  ///     If the entitlement was already in the granted set (optimistic
  ///     local-grant from the purchase path) the event is suppressed —
  ///     `grantEntitlement` already fired it.
  ///   - Server has active, was previously expired/refunded:
  ///     `SubscriptionRenewed`.
  ///   - Server has active with later `expiresAtMs` than the previous
  ///     server-reported active: `SubscriptionRenewed`.
  ///   - Server has `refunded`, was active: `EntitlementRevoked(refunded)`
  ///     — server explicitly named the reason.
  ///   - Server has `expired` (or other non-active), was active:
  ///     `SubscriptionLapsed`.
  ///   - Server stopped reporting an entitlement entirely:
  ///     `SubscriptionLapsed` (honest default — the SDK doesn't actually
  ///     know the reason, so the lifecycle event is the right surface).
  static void _reconcileFromServer(List<EntitlementSummary> summaries) {
    final seenIds = <String>{};
    for (final summary in summaries) {
      seenIds.add(summary.entitlementId);
      final previous = _lastSyncedSummaryById[summary.entitlementId];
      final wasActive = previous != null && previous.isEntitled;
      final isActive = summary.isEntitled;
      _lastSyncedSummaryById[summary.entitlementId] = summary;

      if (!isActive) {
        if (wasActive) {
          _handleActiveToInactive(summary);
        }
        continue;
      }

      if (!wasActive) {
        _handleTransitionIntoActive(summary, previous);
        continue;
      }

      // Stayed active. Detect renewal-with-extended-expiry.
      final previousExpiry = previous.expiresAtMs;
      final currentExpiry = summary.expiresAtMs;
      if (previousExpiry != null &&
          currentExpiry != null &&
          currentExpiry > previousExpiry) {
        _updateEntitlement(summary, source: EntitlementSource.renewal);
        fireEvent(SubscriptionRenewed(
          entitlementId: summary.entitlementId,
          productId: summary.productId,
        ));
      }
    }

    // Entitlements the server stopped reporting on entirely → lapse.
    final droppedIds = _lastSyncedSummaryById.keys
        .where((id) => !seenIds.contains(id))
        .toList(growable: false);
    for (final id in droppedIds) {
      final stale = _lastSyncedSummaryById.remove(id)!;
      final removed = _entitlementsById.remove(id) != null;
      if (removed) {
        fireEvent(SubscriptionLapsed(
          entitlementId: id,
          productId: stale.productId,
        ));
        _entitlementsController?.add(currentEntitlements);
      }
    }
  }

  static void _handleActiveToInactive(EntitlementSummary summary) {
    final removed = _entitlementsById.remove(summary.entitlementId) != null;
    if (!removed) {
      // The granted set was already out of sync with our cached server
      // view (no entitlement to surface the lapse on). Stay silent rather
      // than fire a transition event with no observable change — mirrors
      // the dropped-id loop's gating below.
      return;
    }
    if (summary.status == 'refunded') {
      fireEvent(EntitlementRevoked(
        entitlementId: summary.entitlementId,
        reason: RevokeReason.refunded,
      ));
    } else {
      fireEvent(SubscriptionLapsed(
        entitlementId: summary.entitlementId,
        productId: summary.productId,
      ));
    }
    _entitlementsController?.add(currentEntitlements);
  }

  static void _handleTransitionIntoActive(
    EntitlementSummary summary,
    EntitlementSummary? previous,
  ) {
    final existing = _entitlementsById[summary.entitlementId];
    final alreadyGranted = existing != null;
    if (alreadyGranted) {
      // The optimistic local-grant path already populated the granted
      // set + fired `EntitlementGranted`. Refresh expiresAtMs but
      // preserve the existing source — the event the host already
      // received carries that source, and overwriting it would create
      // a stored-vs-event mismatch.
      if (existing.expiresAtMs != summary.expiresAtMs) {
        _entitlementsById[summary.entitlementId] = RestageEntitlement(
          id: summary.entitlementId,
          source: existing.source,
          expiresAtMs: summary.expiresAtMs,
        );
        _entitlementsController?.add(currentEntitlements);
      }
      // Lifecycle events (`SubscriptionRenewed`/`SubscriptionLapsed`)
      // are orthogonal to the grant event — re-subscribe-after-lapse
      // still wants the lifecycle signal even though `EntitlementGranted`
      // already fired from the optimistic path.
      if (previous != null && !previous.isEntitled) {
        fireEvent(SubscriptionRenewed(
          entitlementId: summary.entitlementId,
          productId: summary.productId,
        ));
      }
      return;
    }
    final source = previous == null
        ? EntitlementSource.purchase
        : EntitlementSource.renewal;
    _updateEntitlement(summary, source: source);
    if (previous == null) {
      fireEvent(EntitlementGranted(
        entitlementId: summary.entitlementId,
        productId: summary.productId,
        source: source,
        expiresAtMs: summary.expiresAtMs,
      ));
    } else {
      fireEvent(SubscriptionRenewed(
        entitlementId: summary.entitlementId,
        productId: summary.productId,
      ));
    }
  }

  static void _updateEntitlement(
    EntitlementSummary summary, {
    required EntitlementSource source,
  }) {
    _entitlementsById[summary.entitlementId] = RestageEntitlement(
      id: summary.entitlementId,
      source: source,
      expiresAtMs: summary.expiresAtMs,
    );
    _entitlementsController?.add(currentEntitlements);
  }

  /// Fetches the authoritative entitlement set from the server and
  /// reconciles against the local set. No-ops cleanly when the SDK was
  /// configured without [baseUrl], or when the request fails — the next
  /// foreground triggers a retry, and the optimistic local grants from
  /// the purchase path are preserved across failed syncs.
  static Future<void> syncEntitlements() async {
    final client = _requireRpcClient();
    if (client == null) return;
    final token = await _resolveAnonymousToken();
    final summaries = await client.syncEntitlements(
      EntitlementSyncRequest(
        appAnonymousToken: token,
        // The SDK does not persist seen transaction IDs; the server
        // back-fills against its own record.
        knownStoreTransactionIds: const [],
      ),
    );
    if (summaries == null) {
      // Transport failure (network, non-2xx, malformed body). Preserve
      // local state — the next foreground triggers a retry. An empty
      // list (non-null) reconciles normally, which is the server's
      // explicit "nothing entitled" answer.
      return;
    }
    _reconcileFromServer(summaries);
  }

  /// Internal: dispatches a `reportTransaction` call to the entitlement
  /// service in the background. Wired by `RestagePaywall._runPurchase`
  /// on a successful purchase outcome. Failures are logged + reconciled
  /// by the next sync.
  static Future<void> reportTransaction({
    required String storeProductId,
    required String storeTransactionId,
    required String storeVerificationData,
    String? paywallId,
    int? paywallPublishedVersion,
  }) async {
    final client = _requireRpcClient();
    if (client == null) return;
    final token = await _resolveAnonymousToken();
    final summaries = await client.reportTransaction(
      ReportTransactionRequest(
        store: _resolvePlatformStore(),
        storeVerificationData: storeVerificationData,
        storeProductId: storeProductId,
        storeTransactionId: storeTransactionId,
        appAnonymousToken: token,
        paywallId: paywallId,
        paywallPublishedVersion: paywallPublishedVersion,
      ),
    );
    // Transport failure or empty response: the optimistic local grant
    // from `RestagePaywall._runPurchase` stays in place; the next
    // `syncEntitlements` reconciles.
    if (summaries == null || summaries.isEmpty) return;
    _reconcileFromServer(summaries);
  }

  /// Internal: dispatches an attribution-only report for a **receipt-less**
  /// purchase — one a host-supplied [BillingGateway] completed through an
  /// external billing provider that keeps the receipt. Wired by
  /// `RestagePaywall._runPurchase` on a [PurchaseOutcomeSucceeded] whose
  /// `verificationData` is `null`: it carries the store transaction id +
  /// paywall id as an attribution hint, never a verified signal, so it is a
  /// separate path from [reportTransaction]. No-ops cleanly when no `baseUrl`
  /// is configured, exactly as [reportTransaction] does; the wire contract
  /// lives on `RestageRpcClient.reportAttribution`.
  static Future<void> reportAttribution({
    required String storeProductId,
    required String storeTransactionId,
    String? paywallId,
    int? paywallPublishedVersion,
  }) async {
    final client = _requireRpcClient();
    if (client == null) return;
    await client.reportAttribution(
      store: _resolvePlatformStore(),
      storeProductId: storeProductId,
      storeTransactionId: storeTransactionId,
      paywallId: paywallId,
      paywallPublishedVersion: paywallPublishedVersion,
    );
  }

  static RestageRpcClient? _requireRpcClient() {
    return _rpcClient ??= _buildRpcClient();
  }

  static RestageRpcClient? _buildRpcClient() {
    final baseUrl = _baseUrl;
    final apiKey = _apiKey;
    if (baseUrl == null || apiKey == null) return null;
    return RestageRpcClient(baseUrl: baseUrl, apiKey: apiKey);
  }

  static String _resolvePlatformStore() =>
      _isApplePlatform ? 'appStore' : 'playStore';

  /// Whether the current platform is an Apple store (iOS / macOS) — the stores
  /// whose offers are resolved via a server-minted signature.
  static bool get _isApplePlatform =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  /// Whether the current platform is Android (the Play store), whose offers are
  /// resolved client-side from the product's eligible subscription offers.
  static bool get _isAndroidPlatform =>
      defaultTargetPlatform == TargetPlatform.android;

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

  /// Test-only — exposes the products passed to [configure].
  @internal
  static List<RestageProduct> get debugProducts => _products;

  /// Test-only — exposes the resolver `RestagePaywall` will use by default.
  @internal
  static VariantResolver get debugDefaultResolver => _defaultResolver;

  /// Test-only — fires [event] on the [events] stream as if it came from
  /// the runtime. Useful for asserting host app reactions to events.
  @visibleForTesting
  static void debugFire(RestageEvent event) => fireEvent(event);

  /// Test-only setter for the billing gateway, so tests can swap in fakes
  /// without going through [configure].
  @internal
  static set debugBillingGateway(BillingGateway gateway) =>
      _billingGateway = gateway;

  /// Test-only — injects a fake [RestageRpcClient]. Used by integration
  /// tests that drive [syncEntitlements] / [reportTransaction] against
  /// a `MockClient`-backed transport.
  @internal
  static set debugRestageRpcClient(RestageRpcClient? client) =>
      _rpcClient = client;

  /// Test-only — exposes the current [RestageRpcClient] for inspection.
  @internal
  static RestageRpcClient? get debugRestageRpcClient => _rpcClient;

  /// Test-only — injects a fake [RestageRpcClient].
  @internal
  @Deprecated('Use debugRestageRpcClient instead.')
  static set debugEntitlementClient(RestageRpcClient? client) =>
      debugRestageRpcClient = client;

  /// Test-only — exposes the current [RestageRpcClient] for inspection.
  @internal
  @Deprecated('Use debugRestageRpcClient instead.')
  static RestageRpcClient? get debugEntitlementClient => debugRestageRpcClient;

  /// Test-only — swaps in an [AnonymousTokenStore] with a pre-seeded
  /// `SharedPreferences` fixture, so tests that drive
  /// [syncEntitlements] / [reportTransaction] don't need to mock the
  /// platform channel for every case.
  @internal
  static set debugAnonymousTokenStore(AnonymousTokenStore store) =>
      _anonymousTokenStore = store;

  /// Test-only — invokes the private reconciliation method directly so
  /// the transition matrix can be exercised without spinning up an HTTP
  /// transport.
  @internal
  static void debugReconcileFromServer(List<EntitlementSummary> summaries) =>
      _reconcileFromServer(summaries);

  /// Resets all module-global state. **Tests must call this in `setUp`
  /// to avoid leaking state between tests.**
  @visibleForTesting
  static void debugReset() {
    _apiKey = null;
    _baseUrl = null;
    _environment = RestageEnvironment.production;
    _defaultResolver = const AssetVariantResolver();
    _defaultFlowResolver = const AssetFlowResolver();
    _products = const [];
    _productsBySlot = const {};
    _productsById = const {};
    _events?.close();
    _events = null;
    _entitlementsById.clear();
    _entitlementsController?.close();
    _entitlementsController = null;
    _billingGateway = null;
    _rpcClient = null;
    _lastSyncedSummaryById.clear();
    _anonymousTokenStore = AnonymousTokenStore();
    _analyticsTransport?.close();
    _analyticsTransport = null;
    _analyticsIdentity = null;
    _analyticsAppContext = null;
    debugAnalyticsHttpClient = null;
    _unregisterLifecycleObserver();
    LibraryRuntimeRegistry.clear();
    resetRestagePaywallCache();
  }

  /// Test-only — injects the [http.Client] the analytics transport uses, so a
  /// test can capture or stub the ingest POST. Cleared by [debugReset].
  @internal
  static http.Client? debugAnalyticsHttpClient;

  /// Test-only — flushes the analytics transport synchronously so a test can
  /// assert on the ingest POST without waiting for the batch threshold.
  @internal
  static Future<void> debugFlushAnalytics() =>
      _analyticsTransport?.flush() ?? Future<void>.value();
}

/// Lifecycle observer that triggers a server reconciliation whenever
/// the app foregrounds. Registered on [Restage.configure] and removed
/// on [Restage.debugReset]. The observer itself is stateless — the
/// reconciliation is driven through [Restage.syncEntitlements].
class _RestageLifecycleObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      scheduleMicrotask(Restage.syncEntitlements);
    }
  }
}

/// An immutable snapshot of the **mutable** identity fields, captured
/// synchronously at event-fire time so a later mount/dismiss cannot change the
/// values the in-flight (async) bridge binds onto the event. The per-event
/// `eventId` is minted inside the build closure (it is a fresh UUID, not
/// captured mutable state).
class _IdentitySnapshot {
  const _IdentitySnapshot({
    required this.sessionId,
    required this.surfaceSessionId,
    required this.userId,
  });

  factory _IdentitySnapshot.capture(AnalyticsIdentity identity) =>
      _IdentitySnapshot(
        sessionId: identity.sessionId,
        surfaceSessionId: identity.surfaceSessionId,
        userId: identity.userId,
      );

  final String sessionId;
  final String? surfaceSessionId;
  final String? userId;
}
