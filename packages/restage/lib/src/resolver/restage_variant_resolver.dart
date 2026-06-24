import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:restage_shared/restage_shared.dart'
    show
        BlobSurfacePayload,
        LibraryRequirement,
        SurfaceDocument,
        SurfaceDocumentCodec,
        SurfaceType;

import '../restage_rpc_client/restage_rpc_client.dart';
import '../runtime/builtin_catalog_capabilities.dart';
import '../runtime/library_runtime_registry.dart';
import '../runtime/paywall_error.dart';
import 'asset_variant_resolver.dart';
import 'resolved_paywall_payload.dart';
import 'resolved_variant.dart';
import 'variant_resolver.dart';

/// Resolves paywalls from Restage-hosted delivery.
///
/// On each [resolve] this fetches the currently-active published version from
/// the delivery service, decodes it, asserts it is a single-screen blob,
/// enforces the capability floor (the installed built-in catalog version + the
/// required custom libraries), and returns the blob bytes plus the served
/// version (for conversion attribution).
///
/// Delivery is fail-closed and tiered. A fresh fetch that fails (network /
/// non-2xx) OR is rejected (not a blob / fails to decode / requires a higher
/// client than supported) funnels into the same fallback ladder — a rejected
/// blob is never rendered:
///   1. fresh hosted fetch (the active version);
///   2. the last good blob held in memory this session (hold-last-good);
///   3. the dev's bundled `assets/paywalls/<id>.rfw` (app-bundle-trusted);
///   4. a typed [RestagePaywallError] the `RestagePaywall` error builder renders.
///
/// You normally never construct this directly — `Restage.configure` installs it
/// as the default resolver, threading the configured `baseUrl`. A bundled-only
/// app can supply an [AssetVariantResolver] instead.
final class RestageVariantResolver
    implements VariantResolver, FlowCapableVariantResolver {
  /// Creates a [RestageVariantResolver] targeting [apiKey] / [environment].
  ///
  /// [baseUrl] is the delivery service origin (config-supplied, never baked in).
  /// When null or empty the hosted fetch tier is unavailable and resolution goes
  /// straight to [assetFallback]. [httpClient] is the test seam. [assetFallback]
  /// is the bundled-asset tier (defaults to a standard [AssetVariantResolver]);
  /// supply one with a custom `assetPathPrefix` if your bundled paywalls live
  /// elsewhere.
  RestageVariantResolver({
    required this.apiKey,
    required this.environment,
    String? baseUrl,
    http.Client? httpClient,
    VariantResolver assetFallback = const AssetVariantResolver(),
  })  : _assetFallback = assetFallback,
        _client = (baseUrl == null || baseUrl.isEmpty)
            ? null
            : RestageRpcClient(
                baseUrl: baseUrl,
                apiKey: apiKey,
                httpClient: httpClient,
              );

  /// Publishable Restage key used by hosted paywall delivery.
  final String apiKey;

  /// Environment the API key targets (sandbox vs production).
  final RestageEnvironment environment;

  final RestageRpcClient? _client;
  final VariantResolver _assetFallback;

  /// In-memory hold-last-good cache keyed by paywall id. Holds ONLY blobs that
  /// already passed decode + the blob assertion + the capability floor. The
  /// capability floor is re-checked on every cache hit (a custom library can be
  /// unregistered/downgraded after caching), so the cached blob's manifest is
  /// retained alongside it. Per-instance + within-session; the bundled asset is
  /// the durable cross-restart offline floor.
  final Map<String, _CachedBlob> _cache = {};

  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async {
    // Tier 1 — fetch fresh (active arm). A fresh blob that fails to fetch OR is
    // rejected (non-blob / decode-fail / minClient-above-floor) returns a null
    // variant and funnels into the SAME ladder below — a rejected blob NEVER
    // renders.
    final fresh = await _resolveFresh(id);
    if (fresh.variant != null) {
      _cache[id] = fresh.toCacheEntry();
      return fresh.variant!;
    }

    // Tier 2 — hold-last-good (in-memory). Re-run the capability gate: a custom
    // library may have been unregistered/downgraded since caching, so a stale
    // cached blob is not served without re-affirming the floor.
    final cached = _cache[id];
    if (cached != null && _cacheStillRenderable(cached)) {
      return _asCacheHit(cached.variant);
    }

    // Tier 3 — the dev's bundled asset (app-bundle-trusted, durable floor).
    try {
      return await _assetFallback.resolve(
        id,
        placementId: placementId,
        locale: locale,
      );
    } on RestagePaywallError {
      // Tier 4 — nothing renderable anywhere. Surface the hosted-unavailable
      // error (more informative than the bundled-asset-not-found): the
      // RestagePaywall loading/error builder renders this throw. When the active
      // version was rejected for a capability gap, name it.
      throw _unavailable(id, fresh.capabilityGap);
    }
  }

  // Internal flow-capable seam (the [FlowCapableVariantResolver] override) — not
  // part of the public resolver API. The public SPI stays [resolve] (blob-only);
  // this carries the blob-or-flow payload for the built-in resolvers and may
  // change without a public-API break.
  @internal
  @override
  Future<ResolvedPaywallPayload> resolvePayload(
    String id, {
    String? placementId,
    Locale? locale,
  }) async {
    // Tier 1 - hosted fresh. _resolveFresh rejects non-blob payloads, including
    // hosted flows, so they fall through to the same cache/asset/error ladder.
    final fresh = await _resolveFresh(id);
    if (fresh.variant != null) {
      _cache[id] = fresh.toCacheEntry();
      return BlobPaywallPayload(fresh.variant!);
    }

    // Tier 2 - hold-last-good (blob-only). Re-run the capability gate before
    // serving a cached blob (a required library may have changed since caching).
    final cached = _cache[id];
    if (cached != null && _cacheStillRenderable(cached)) {
      return BlobPaywallPayload(_asCacheHit(cached.variant));
    }

    // Tier 3 - bundled asset fallback. Built-in asset resolvers can return a
    // blob or bundled flow; custom host resolvers stay blob-only.
    try {
      final fallback = _assetFallback;
      if (fallback is FlowCapableVariantResolver) {
        final flowCapableFallback = fallback as FlowCapableVariantResolver;
        return await flowCapableFallback.resolvePayload(
          id,
          placementId: placementId,
          locale: locale,
        );
      }
      final variant = await fallback.resolve(
        id,
        placementId: placementId,
        locale: locale,
      );
      return BlobPaywallPayload(variant);
    } on RestagePaywallError {
      // Tier 4 - nothing renderable anywhere. Keep the public hosted resolver's
      // existing unavailable error shape; name the capability gap when the
      // active version was rejected for one.
      throw _unavailable(id, fresh.capabilityGap);
    }
  }

  /// Fetches + validates the active hosted version. Returns a renderable
  /// [_FreshResolution] (carrying the variant plus the manifest needed to
  /// re-gate a cache hit), or a rejected one on any fetch failure OR validation
  /// reject — both funnel into the same fallback ladder; a rejected blob never
  /// renders.
  Future<_FreshResolution> _resolveFresh(String id) async {
    final client = _client;
    if (client == null) {
      return const _FreshResolution.rejected(); // no hosted tier (no baseUrl)
    }

    final bytes = await client.fetchSurface(
      surfaceType: SurfaceType.paywall.wireName,
      surfaceSlug: id,
      // version omitted → the delivery service's active-version arm.
    );
    if (bytes == null) {
      return const _FreshResolution.rejected(); // transport failure
    }

    final SurfaceDocument document;
    try {
      document = SurfaceDocumentCodec.decode(bytes);
    } on FormatException catch (error) {
      debugPrint('[restage] hosted paywall "$id" failed to decode: $error');
      return const _FreshResolution.rejected();
    }

    final payload = document.payload;
    if (payload is! BlobSurfacePayload) {
      debugPrint(
        '[restage] hosted paywall "$id" did not contain a blob payload',
      );
      return const _FreshResolution.rejected();
    }

    // Defense-in-depth: the served document must be the paywall we asked for.
    // A correct server returns the requested (type, slug) under tenant scoping,
    // but a server bug / routing error / substituted response must fall through
    // rather than render-or-cache the wrong surface. Mirrors the flow resolver's
    // flow-id cross-check; rejects via the same ladder, never a throw.
    if (document.surfaceType != SurfaceType.paywall ||
        document.surfaceSlug != id) {
      debugPrint(
        '[restage] hosted paywall "$id" served a mismatched surface '
        '(${document.surfaceType.wireName} "${document.surfaceSlug}")',
      );
      return const _FreshResolution.rejected();
    }

    // Pre-render capability gate (the integrity checks — content hash + the
    // header/payload manifest cross-check — already ran inside decode). A
    // surface this build cannot faithfully render is rejected before render and
    // falls through the ladder, never rendered, with a diagnostic naming the gap.
    final installedVersion = RestageBuiltInCatalogCapabilities.currentVersion;
    if (document.minClient > installedVersion) {
      final gap = 'requires built-in catalog version ${document.minClient}, '
          'above the installed $installedVersion';
      debugPrint('[restage] hosted paywall "$id" $gap');
      return _FreshResolution.rejected(capabilityGap: gap);
    }
    for (final requirement in document.requiredLibraries) {
      if (!LibraryRuntimeRegistry.satisfies(requirement)) {
        final gap = 'requires library "${requirement.namespace}" '
            '>= v${requirement.minVersion} '
            '(${LibraryRuntimeRegistry.describeGap(requirement)})';
        debugPrint('[restage] hosted paywall "$id" $gap');
        return _FreshResolution.rejected(capabilityGap: gap);
      }
    }

    return _FreshResolution.renderable(
      variant: ResolvedVariant(
        bytes: payload.blob,
        paywallId: id,
        paywallPublishedVersion: document.version,
      ),
      minClient: document.minClient,
      requiredLibraries: document.requiredLibraries,
    );
  }

  /// Whether a cached blob still passes the capability floor. Re-checked on
  /// every hold-last-good hit because the custom-library registry can change
  /// after caching (a library unregistered/downgraded). The installed built-in
  /// catalog version is a compile-time const and cannot drift, but is cheap to
  /// re-affirm alongside.
  bool _cacheStillRenderable(_CachedBlob cached) {
    if (cached.minClient > RestageBuiltInCatalogCapabilities.currentVersion) {
      return false;
    }
    for (final requirement in cached.requiredLibraries) {
      if (!LibraryRuntimeRegistry.satisfies(requirement)) {
        return false;
      }
    }
    return true;
  }

  // Re-emit [variant] as a cache hit. Mirrors every ResolvedVariant field —
  // keep in sync when a field is added (the public DTO has no copyWith, kept
  // minimal by design; a missed field here would silently reset on cache hits).
  ResolvedVariant _asCacheHit(ResolvedVariant variant) => ResolvedVariant(
        bytes: variant.bytes,
        paywallId: variant.paywallId,
        variantId: variant.variantId,
        experimentId: variant.experimentId,
        paywallVersion: variant.paywallVersion,
        paywallPublishedVersion: variant.paywallPublishedVersion,
        cacheHit: true,
      );

  RestagePaywallError _unavailable(String id, [String? capabilityGap]) =>
      RestagePaywallError(
        code: RestageErrorCodes.deliveryUnavailable,
        message: capabilityGap == null
            ? 'Hosted paywall "$id" is unavailable: the fetch failed and no '
                'cached or bundled paywall was available.'
            : 'Hosted paywall "$id" is unavailable: the active version $capabilityGap, '
                'and no cached or bundled paywall was available.',
        retryable: true,
      );
}

/// Outcome of a fresh hosted fetch: either a renderable variant plus the
/// manifest needed to re-gate a future cache hit, or a rejection.
final class _FreshResolution {
  const _FreshResolution.rejected({this.capabilityGap})
      : variant = null,
        minClient = 0,
        requiredLibraries = const [];

  const _FreshResolution.renderable({
    required this.variant,
    required this.minClient,
    required this.requiredLibraries,
  }) : capabilityGap = null;

  final ResolvedVariant? variant;
  final int minClient;
  final List<LibraryRequirement> requiredLibraries;

  /// Set only when the fresh fetch was rejected for a capability reason
  /// (minClient above the installed catalog, or an unsatisfied library) — a
  /// short phrase naming the gap, carried through the fallback ladder so the
  /// exhausted-fallback error names it (rather than a generic "fetch failed").
  final String? capabilityGap;

  _CachedBlob toCacheEntry() => _CachedBlob(
        variant: variant!,
        minClient: minClient,
        requiredLibraries: requiredLibraries,
      );
}

/// A hold-last-good cache entry: the renderable variant plus the capability
/// manifest it passed, retained so a cache hit can re-run the floor check.
final class _CachedBlob {
  const _CachedBlob({
    required this.variant,
    required this.minClient,
    required this.requiredLibraries,
  });

  final ResolvedVariant variant;
  final int minClient;
  final List<LibraryRequirement> requiredLibraries;
}

/// Environment hint passed to `Restage.configure` and [RestageVariantResolver].
enum RestageEnvironment {
  /// Sandbox environment — paired with `rs_pk_test_…` API keys. Test
  /// purchases route through the platform sandbox; events are not metered.
  sandbox,

  /// Production environment — paired with `rs_pk_live_…` API keys. Real
  /// charges; events are metered for billing.
  production,
}
