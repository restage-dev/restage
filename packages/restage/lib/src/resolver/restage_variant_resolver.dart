import 'dart:typed_data';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:restage_shared/flow_experiment.dart';
import 'package:restage_shared/restage_shared.dart'
    show
        BlobRenderCapabilityGate,
        BlobRenderRejected,
        BlobSurfacePayload,
        CapabilityManifest,
        FlowContentHash,
        FlowDocument,
        FlowDocumentCodec,
        FlowDocumentValidation,
        FlowSurfacePayload,
        InstalledCapability,
        LibraryRequirement,
        SurfaceDocument,
        SurfaceDocumentCodec,
        SurfaceType;

import '../flow/flow_assignment.dart';
import '../flow/flow_descriptors.dart';
import '../flow/flow_experiment_artifact_metadata.dart';
import '../flow/flow_experiment_mount.dart';
import '../flow/flow_resolver.dart';
import '../restage_rpc_client/restage_rpc_client.dart';
import '../runtime/builtin_catalog_capabilities.dart';
import '../runtime/library_runtime_registry.dart';
import '../runtime/paywall_error.dart';
import 'asset_variant_resolver.dart';
import 'asset_paywall_flow_preflight.dart';
import 'flow_paywall_active_arm.dart';
import 'resolved_paywall_payload.dart';
import 'resolved_variant.dart';
import 'surface_assignment_key_provider.dart';
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
/// The internal [resolvePayload] path additionally serves a hosted flow-shaped
/// (Navigator-lowered) paywall through the active arm: it gates the served flow
/// against the client's bundled flow contract (render gate + retained checks),
/// holds the last gate-accepted flow (re-gated on every hit), and falls closed
/// to the bundled flow. The public [resolve] SPI stays
/// blob-only (a flow is not a [ResolvedVariant]); a flow reached through it
/// simply falls through, exactly as before.
///
/// You normally never construct this directly — `Restage.configure` installs it
/// as the default resolver, threading the configured `baseUrl`. A bundled-only
/// app can supply an [AssetVariantResolver] instead.
final class RestageVariantResolver
    implements
        VariantResolver,
        FlowCapableVariantResolver,
        PresentationPaywallResolver {
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

  /// In-memory hold-last-good cache keyed by paywall id. Holds ONLY payloads
  /// that already passed their gate — a decoded blob past the blob capability
  /// floor, or a gate-accepted active flow. Both are re-affirmed on every cache
  /// hit (a custom library can be unregistered/downgraded, and an active flow is
  /// re-gated against the current bundled contract), so a stale entry is never
  /// served without re-passing its gate. Per-instance + within-session; the
  /// bundled asset is the durable cross-restart offline floor.
  final Map<String, _CachedPayload> _cache = {};
  final Map<String, _PaywallExperimentHostedFlow> _experimentFlowCache = {};

  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async {
    while (true) {
      try {
        return await _resolveBlobOnce(
          id,
          placementId: placementId,
          locale: locale,
        );
      } on StaleSurfaceAssignmentResolution {
        // Public callers have no host commit boundary to perform the retry.
      }
    }
  }

  Future<ResolvedVariant> _resolveBlobOnce(
    String id, {
    String? placementId,
    Locale? locale,
  }) async {
    // Tier 1 — fetch fresh (active arm). A fresh blob that fails to fetch OR is
    // rejected (non-blob / decode-fail / minClient-above-floor) funnels into the
    // SAME ladder below — a rejected blob NEVER renders. The public SPI is
    // blob-only, so a hosted flow falls through here exactly as before.
    final fresh = await _resolveFresh(id);
    if (fresh is _FreshBlob) {
      _requireCurrent(fresh.cacheEntry.assignmentLease);
      _cache[id] = fresh.cacheEntry;
      return fresh.cacheEntry.variant;
    }

    // Tier 2 — hold-last-good (blob-only on the public path). Re-run the
    // capability gate: a custom library may have been unregistered/downgraded
    // since caching, so a stale cached blob is not served without re-affirming.
    final cached = _cache[id];
    if (cached is _CachedBlob &&
        _cacheLeaseIsCurrent(id, cached) &&
        _cacheStillRenderable(cached)) {
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
      throw _unavailable(id, _capabilityGapOf(fresh));
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
    while (true) {
      try {
        return await _resolvePayloadOnce(
          id,
          placementId: placementId,
          locale: locale,
          deferFreshPublication: false,
        );
      } on StaleSurfaceAssignmentResolution {
        // Ordinary callers have no host transaction to perform the retry.
      }
    }
  }

  @internal
  @override
  Future<ResolvedPaywallPayload> resolvePayloadForPresentation(
    String id, {
    String? placementId,
    Locale? locale,
  }) async {
    final guard = currentPaywallPresentationGuard();
    if (!guard()) throw const StaleSurfaceAssignmentResolution();
    final fallback = _assetFallback;
    if (_client != null && fallback is AssetVariantResolver) {
      final preflight = await fallback.preflightFlowBaseline(id);
      if (!guard()) throw const StaleSurfaceAssignmentResolution();
      if (preflight is AssetPaywallFlowBaseline) {
        final document = preflight.root.document;
        final flow = OnboardingFlowRef<Object?>(
          id: document.flow,
          version: document.version,
          minClient: document.minClient,
          surfaceType: SurfaceType.paywall,
          deliveryMode: document.deliveryMode,
          decodeResult: _identityPaywallFlowResult,
        );
        final seedSource = FlowMountRuntimeSeedSource(
          flow: flow,
          actions: null,
          installedSignalNames: const <String>{},
        );
        final presentation = _RestagePaywallExperimentPresentation(
          owner: this,
          paywallId: id,
          flow: flow,
          baseline: preflight,
          captureSeed: seedSource.capture,
          presentationGuard: guard,
        );
        try {
          final payload = await presentation.resolvePayload();
          if (payload != null) return payload;
          presentation.disposePresentation();
        } on Object {
          presentation.disposePresentation();
          rethrow;
        }
        if (!guard()) throw const StaleSurfaceAssignmentResolution();
      }
    }
    if (!guard()) throw const StaleSurfaceAssignmentResolution();
    return _resolvePayloadOnce(
      id,
      placementId: placementId,
      locale: locale,
      deferFreshPublication: true,
    );
  }

  Future<ResolvedPaywallPayload> _resolvePayloadOnce(
    String id, {
    String? placementId,
    Locale? locale,
    required bool deferFreshPublication,
  }) async {
    // Tier 1 — hosted fresh (blob).
    final fresh = await _resolveFresh(id);
    if (fresh is _FreshBlob) {
      _requireCurrent(fresh.cacheEntry.assignmentLease);
      if (!deferFreshPublication) {
        _cache[id] = fresh.cacheEntry;
      }
      return fresh.payload(
        hostedPublication: deferFreshPublication
            ? _provisionalPublication(id, fresh.cacheEntry)
            : null,
      );
    }

    // A flow — fresh OR held-last-good — is gated against the client's bundled
    // flow contract. Load it ONCE: it is the render gate's `client` contract,
    // the Tier-2 re-gate input, AND the Tier-3 flow fallback. With no bundled
    // flow contract there is nothing to gate against, so an active flow can
    // never be accepted — the ladder fails closed rather than serving it ungated.
    final held = _cache[id];
    final bundled = (fresh is _FreshFlow || held is _CachedFlow)
        ? await _bundledFlowPayload(id,
            placementId: placementId, locale: locale)
        : null;

    // Tier 1 (flow) — gate the fresh active document. A retained-check failure
    // or a render-gate rejection funnels into the SAME ladder; a rejected active
    // flow is NEVER rendered.
    if (fresh is _FreshFlow && bundled != null) {
      _requireCurrent(fresh.assignmentLease);
      final arm = resolveFlowActiveArm(
        activePayload: fresh.activePayload,
        bundledDocument: bundled.flow.document,
        paywallId: id,
        activeVersion: fresh.version,
        experimentId: fresh.experimentId,
        variantId: fresh.variantId,
        experimentEpoch: fresh.experimentEpoch,
      );
      if (arm is FlowPaywallActiveAccepted) {
        _requireCurrent(fresh.assignmentLease);
        final cacheEntry = _CachedFlow(
          activePayload: fresh.activePayload,
          version: fresh.version,
          experimentId: fresh.experimentId,
          variantId: fresh.variantId,
          experimentEpoch: fresh.experimentEpoch,
          assignmentLease: fresh.assignmentLease,
        );
        if (!deferFreshPublication) {
          _cache[id] = cacheEntry;
        }
        return stampFlowPayloadForDelivery(
          arm.payload,
          fresh.assignmentLease,
          hostedPublication: deferFreshPublication
              ? _provisionalPublication(id, cacheEntry)
              : null,
        );
      }
    }

    // Tier 2 — hold-last-good (shape-aware): a cached blob re-floored, or a
    // cached active flow re-gated against the CURRENT bundled contract + registry.
    final regated = _revalidateCache(id, bundled);
    if (regated != null) return regated;

    // Tier 3 — the client's own bundled flow (already loaded), else the bundled
    // asset fallback (a blob or bundled flow; custom host resolvers stay
    // blob-only).
    if (bundled != null) return bundled;
    try {
      final fallback = _assetFallback;
      if (fallback is FlowCapableVariantResolver) {
        final payload =
            await (fallback as FlowCapableVariantResolver).resolvePayload(
          id,
          placementId: placementId,
          locale: locale,
        );
        return withoutAssignmentLeaseForDelivery(payload);
      }
      final variant = await fallback.resolve(
        id,
        placementId: placementId,
        locale: locale,
      );
      return BlobPaywallPayload(variant);
    } on RestagePaywallError {
      // Tier 4 — nothing renderable anywhere. Keep the public hosted resolver's
      // existing unavailable error shape; name the capability gap when the
      // active version was rejected for one.
      throw _unavailable(id, _capabilityGapOf(fresh));
    }
  }

  HostedPayloadPublication _provisionalPublication(
    String id,
    _CachedPayload cacheEntry,
  ) =>
      HostedPayloadPublication(onCommit: () {
        // Paint-time host validation already checked the same lease. Re-affirm
        // here so a token can never publish after an identity boundary even if
        // it is invoked independently or more than once.
        if (!cacheEntry.assignmentLease.isCurrent) return;
        _cache[id] = cacheEntry;
      });

  /// Fetches + validates the active hosted version. Returns the fresh outcome:
  /// a renderable blob (with the manifest needed to re-gate a cache hit), a
  /// flow-shaped payload pending the active-arm gate, or a rejection — all
  /// funnel into the same fallback ladder; a rejected fetch never renders.
  Future<_FreshOutcome> _resolveFresh(String id) async {
    final client = _client;
    if (client == null) {
      return const _FreshRejected(); // no hosted tier (no baseUrl)
    }

    // The client contract (built-in catalog version + installed libraries) the
    // server resolves eligibility against; its content hash is byte-identical
    // to the server's, so a verdict is identity by construction.
    final installed = InstalledCapability(
      builtInCatalogVersion: RestageBuiltInCatalogCapabilities.currentVersion,
      installedLibraries: LibraryRuntimeRegistry.installedSnapshot(),
    );
    final assignmentLease = await SurfaceAssignmentKeyProvider.captureLease();
    _requireCurrent(assignmentLease);

    var result = await client.fetchSurface(
      surfaceType: SurfaceType.paywall.wireName,
      surfaceSlug: id,
      assignmentKey: assignmentLease.assignmentKey,
      contractHash: installed.contentHash,
      // version omitted → the delivery service's active-version arm.
    );
    _requireCurrent(assignmentLease);
    if (result == null) {
      return const _FreshRejected(); // transport failure
    }
    if (result.contractRequired) {
      // Upload-on-miss: the server has no cached contract for this hash. Retry
      // ONCE with the full contract attached. A second consecutive
      // contractRequired is treated as a fetch failure — never loop.
      result = await client.fetchSurface(
        surfaceType: SurfaceType.paywall.wireName,
        surfaceSlug: id,
        assignmentKey: assignmentLease.assignmentKey,
        contractHash: installed.contentHash,
        contract: installed,
      );
      _requireCurrent(assignmentLease);
      if (result == null || result.contractRequired) {
        return const _FreshRejected();
      }
    }

    final SurfaceDocument document;
    try {
      document = SurfaceDocumentCodec.decode(result.envelopeBytes);
    } on FormatException catch (error) {
      debugPrint('[restage] hosted paywall "$id" failed to decode: $error');
      return const _FreshRejected();
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
      return const _FreshRejected();
    }

    final payload = document.payload;
    if (payload is BlobSurfacePayload) {
      // Pre-render capability gate (the integrity checks — content hash + the
      // header/payload manifest cross-check — already ran inside decode). A
      // surface this build cannot faithfully render is rejected before render
      // and falls through the ladder, never rendered, with a diagnostic naming
      // the gap.
      final gateVerdict = BlobRenderCapabilityGate.evaluate(
        required: CapabilityManifest(
          builtInFloor: document.minClient,
          requiredLibraries: document.requiredLibraries,
        ),
        installed: installed,
      );
      if (gateVerdict is BlobRenderRejected) {
        debugPrint('[restage] hosted paywall "$id" ${gateVerdict.message}');
        return _FreshRejected(capabilityGap: gateVerdict.message);
      }

      final variant = ResolvedVariant(
        bytes: payload.blob,
        paywallId: id,
        variantId: result.variantId,
        experimentId: result.experimentId,
        experimentEpoch: result.experimentEpoch,
        paywallPublishedVersion: document.version,
      );
      return _FreshBlob(
        _CachedBlob(
          variant: variant,
          minClient: document.minClient,
          requiredLibraries: document.requiredLibraries,
          assignmentLease: assignmentLease,
        ),
      );
    }

    if (payload is FlowSurfacePayload) {
      // Flow-shaped (Navigator-lowered) paywall: hand the served active document
      // to the flow active arm (gated in [resolvePayload] against the bundled
      // contract). The served version + experiment arm ride along for attribution.
      return _FreshFlow(
        payload,
        document.version,
        result.experimentId,
        result.variantId,
        result.experimentEpoch,
        assignmentLease,
      );
    }

    debugPrint(
      '[restage] hosted paywall "$id" did not contain a renderable payload',
    );
    return const _FreshRejected();
  }

  /// Loads the client's bundled flow paywall (`assets/paywalls/<id>.flow.json`
  /// + its screen blobs) via the asset fallback. Returns null when the fallback
  /// is not flow-capable, has no bundled flow for this id (a blob or nothing),
  /// or fails to load — the "no flow contract ⇒ fail closed" signal for the
  /// active arm. The returned payload is ALSO the Tier-3 flow fallback, so it is
  /// loaded once per resolve.
  Future<FlowPaywallPayload?> _bundledFlowPayload(
    String id, {
    String? placementId,
    Locale? locale,
  }) async {
    final fallback = _assetFallback;
    if (fallback is! FlowCapableVariantResolver) return null;
    try {
      final payload = await (fallback as FlowCapableVariantResolver)
          .resolvePayload(id, placementId: placementId, locale: locale);
      return payload is FlowPaywallPayload ? payload : null;
    } on RestagePaywallError {
      return null;
    }
  }

  /// Re-affirms the hold-last-good cache entry against the current runtime state,
  /// returning a renderable payload or null (→ the caller falls to Tier 3). A
  /// cached blob is re-floored; a cached active flow is re-gated + re-checked
  /// against the current [bundledFlow] contract (null when the bundled contract
  /// is unavailable, so a cached active flow cannot be re-served without it).
  ResolvedPaywallPayload? _revalidateCache(
    String id,
    FlowPaywallPayload? bundledFlow,
  ) {
    final cached = _cache[id];
    if (cached != null && !_cacheLeaseIsCurrent(id, cached)) return null;
    if (cached is _CachedBlob) {
      return _cacheStillRenderable(cached)
          ? BlobPaywallPayload(
              _asCacheHit(cached.variant),
              assignmentLease: cached.assignmentLease,
            )
          : null;
    }
    if (cached is _CachedFlow && bundledFlow != null) {
      final arm = resolveFlowActiveArm(
        activePayload: cached.activePayload,
        bundledDocument: bundledFlow.flow.document,
        paywallId: id,
        activeVersion: cached.version,
        experimentId: cached.experimentId,
        variantId: cached.variantId,
        experimentEpoch: cached.experimentEpoch,
        cacheHit: true,
      );
      if (arm is FlowPaywallActiveAccepted) {
        return stampFlowPayloadForDelivery(
          arm.payload,
          cached.assignmentLease,
        );
      }
    }
    return null;
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

  bool _cacheLeaseIsCurrent(String id, _CachedPayload cached) {
    if (cached.assignmentLease.isCurrent) return true;
    if (identical(_cache[id], cached)) _cache.remove(id);
    return false;
  }

  static void _requireCurrent(SurfaceAssignmentResolutionLease lease) {
    if (!lease.isCurrent) throw const StaleSurfaceAssignmentResolution();
  }

  // Re-emit [variant] as a cache hit. copyWith carries every field through, so
  // a field added to ResolvedVariant can't be silently reset on cache hits.
  ResolvedVariant _asCacheHit(ResolvedVariant variant) =>
      variant.copyWith(cacheHit: true);

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

String? _capabilityGapOf(_FreshOutcome fresh) =>
    fresh is _FreshRejected ? fresh.capabilityGap : null;

final class _RestagePaywallExperimentPresentation
    implements
        FlowPaywallExperimentRetryAuthority,
        FlowResolver,
        FlowExperimentArtifactMetadataProvider {
  _RestagePaywallExperimentPresentation({
    required this.owner,
    required this.paywallId,
    required this.flow,
    required this.baseline,
    required this.captureSeed,
    required this.presentationGuard,
  });

  final RestageVariantResolver owner;
  final String paywallId;
  final OnboardingFlowRef<Object?> flow;
  final AssetPaywallFlowBaseline baseline;
  final FlowMountSeedCapture captureSeed;
  final bool Function() presentationGuard;

  FlowMountContractSnapshot? _snapshot;
  _PaywallExperimentHostedFlow? _provisional;
  bool _published = false;
  bool _disposed = false;
  var _attempts = 0;

  Future<FlowPaywallPayload?> resolvePayload() async {
    while (_attempts < 3) {
      _attempts += 1;
      if (_disposed || !presentationGuard()) {
        throw const StaleSurfaceAssignmentResolution();
      }
      _snapshot = null;
      _provisional = null;

      try {
        final snapshotOutcome = await FlowMountContractSnapshotBuilder(
          captureSeed: captureSeed,
          resolveAssignmentKey: SurfaceAssignmentKeyProvider.resolve,
          resolver: baseline,
        ).seal();
        if (_disposed || !presentationGuard()) {
          throw const StaleSurfaceAssignmentResolution();
        }
        if (snapshotOutcome is FlowMountSnapshotRejected) {
          if (snapshotOutcome.reason == FlowMountSnapshotRejection.seedDrift) {
            continue;
          }
          return null;
        }

        final snapshot = (snapshotOutcome as FlowMountSnapshotSealed).snapshot;
        if (!_baselineCanAdvertise(snapshot)) return null;
        _snapshot = snapshot;

        final fresh = await _fetchActive(snapshot);
        if (_disposed || !presentationGuard()) {
          throw const StaleSurfaceAssignmentResolution();
        }
        if (fresh != null) {
          final prefetched = await FlowCandidatePrefetcher.prefetch(
            snapshot: snapshot,
            captureSeed: captureSeed,
            candidateRoot: fresh.candidateRoot,
            resolver: this,
            serverVerdictAccepted: fresh.serverVerdictAccepted,
          );
          if (_disposed || !presentationGuard()) {
            throw const StaleSurfaceAssignmentResolution();
          }
          if (prefetched is FlowCandidatePrefetchAccepted) {
            final provisional = _PaywallExperimentHostedFlow(
              snapshot: snapshot,
              accepted: prefetched,
              paywallPublishedVersion: fresh.paywallPublishedVersion,
            );
            _provisional = provisional;
            return FlowPaywallPayload.experiment(
              acceptedCandidate: prefetched,
              paywallId: paywallId,
              paywallPublishedVersion: fresh.paywallPublishedVersion,
              resolvedFromActiveArm: true,
              experimentAuthority: this,
            );
          }
          if (prefetched is FlowCandidatePrefetchRejected &&
              prefetched.reason == FlowCandidatePrefetchRejection.seedDrift) {
            throw const StaleSurfaceAssignmentResolution();
          }
        }

        final held = owner._experimentFlowCache[paywallId];
        if (held != null) {
          if (held.matches(snapshot) &&
              revalidate(FlowMountRevalidationBoundary.fallback)) {
            final accepted = held.accepted.asCacheHit();
            return FlowPaywallPayload.experiment(
              acceptedCandidate: accepted,
              paywallId: paywallId,
              paywallPublishedVersion: held.paywallPublishedVersion,
              resolvedFromActiveArm: true,
              experimentAuthority: this,
            );
          }
          owner._experimentFlowCache.remove(paywallId);
        }

        if (!revalidate(FlowMountRevalidationBoundary.fallback)) {
          throw const StaleSurfaceAssignmentResolution();
        }
        return FlowPaywallPayload.experimentBaseline(
          flow: snapshot.baselineRoot,
          pinnedFlowResolver: snapshot.baselineResolver,
          paywallId: paywallId,
          experimentAuthority: this,
        );
      } on StaleSurfaceAssignmentResolution {
        if (_disposed || !presentationGuard()) rethrow;
      }
    }

    if (!presentationGuard()) throw const StaleSurfaceAssignmentResolution();
    disposePresentation();
    return FlowPaywallPayload.experimentBaseline(
      flow: baseline.root,
      pinnedFlowResolver: baseline,
      paywallId: paywallId,
    );
  }

  @override
  Future<FlowPaywallPayload?> resolveNextPayload() => resolvePayload();

  bool _baselineCanAdvertise(FlowMountContractSnapshot snapshot) {
    final verdict = FlowExperimentEligibilityEvaluatorV1.evaluate(
      FlowExperimentVerdictInputV1(
        clientBaselineClosure: snapshot.clientBaselineClosure,
        candidateArmClosure: snapshot.clientBaselineClosure,
        installedCapability: snapshot.seed.installedCapability,
        actionBindings: snapshot.seed.actionBindings,
        installedSignals: snapshot.seed.installedSignals,
        surfaceType: SurfaceType.paywall,
        deliveryMode: snapshot.seed.deliveryMode,
        flowGateRevision: kFlowExperimentGateLogicRevisionV1,
      ),
    );
    return verdict.accepted;
  }

  Future<_PaywallExperimentFreshFlow?> _fetchActive(
    FlowMountContractSnapshot snapshot,
  ) async {
    _requireCurrent(snapshot, FlowMountRevalidationBoundary.request);
    var result = await _fetchSurface(
      snapshot: snapshot,
      boundary: FlowMountRevalidationBoundary.request,
      flowContract: FlowContractFetchRequest.hashOnly(
        snapshot.contentHash.value,
      ),
    );
    _requireCurrent(snapshot, FlowMountRevalidationBoundary.request);
    if (result == null) return null;

    if (result.flowContractRequired) {
      final bytes = snapshot.bytesForRetry(
        FlowMountRevalidationBoundary.uploadRetry,
        _captureCurrentSeed(),
      );
      if (bytes == null) throw const StaleSurfaceAssignmentResolution();
      result = await _fetchSurface(
        snapshot: snapshot,
        boundary: FlowMountRevalidationBoundary.uploadRetry,
        flowContract: FlowContractFetchRequest.retry(
          snapshot.contentHash.value,
          bytes,
        ),
      );
      _requireCurrent(snapshot, FlowMountRevalidationBoundary.uploadRetry);
      if (result == null || result.flowContractRequired) return null;
    }

    final decoded = _decodeHostedFlow(
      result,
      requestedFlow: flow,
      exactVersion: false,
    );
    if (decoded == null) return null;
    final assignment = _flowAssignmentOf(result);
    if ((assignment != null) != (result.decision == 'assigned')) return null;
    if (assignment != null && snapshot.assignmentKey == null) return null;

    final candidate = _own(
      ResolvedFlow(
        document: decoded.document,
        screenBlobs: decoded.screenBlobs,
        contentHash: FlowContentHash.compute(
          FlowDocumentCodec.encodeCanonicalJson(decoded.document),
        ),
        cacheHit: false,
        assignment: assignment,
      ),
      requiredLibraries: decoded.requiredLibraries,
    );
    return _PaywallExperimentFreshFlow(
      candidateRoot: candidate,
      paywallPublishedVersion: decoded.publishedVersion,
      serverVerdictAccepted:
          assignment == null || result.decision == 'assigned',
    );
  }

  Future<SurfaceFetchResult?> _fetchSurface({
    required FlowMountContractSnapshot snapshot,
    required FlowMountRevalidationBoundary boundary,
    required FlowContractFetchRequest flowContract,
  }) async {
    try {
      return await owner._client!.fetchSurface(
        surfaceType: SurfaceType.paywall.wireName,
        surfaceSlug: paywallId,
        assignmentKey: snapshot.assignmentKey,
        flowContract: flowContract,
        publicationGuard: () => _snapshotIsCurrent(snapshot, boundary),
      );
    } on SurfaceRequestPublicationRejected {
      throw const StaleSurfaceAssignmentResolution();
    }
  }

  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> requestedFlow) async {
    final snapshot = _snapshot;
    if (_disposed || snapshot == null) {
      throw FlowUnavailableError(
        flowId: requestedFlow.id,
        flowVersion: requestedFlow.version,
        reason: 'presentation_disposed',
        message: 'The paywall flow presentation no longer owns resolution.',
      );
    }
    _requireCurrent(
      snapshot,
      FlowMountRevalidationBoundary.candidatePrefetch,
    );
    final SurfaceFetchResult? result;
    try {
      result = await owner._client!.fetchSurface(
        surfaceType: SurfaceType.paywall.wireName,
        surfaceSlug: requestedFlow.id,
        version: requestedFlow.version,
        publicationGuard: () => _snapshotIsCurrent(
          snapshot,
          FlowMountRevalidationBoundary.candidatePrefetch,
        ),
      );
    } on SurfaceRequestPublicationRejected {
      throw const StaleSurfaceAssignmentResolution();
    }
    _requireCurrent(
      snapshot,
      FlowMountRevalidationBoundary.candidatePrefetch,
    );
    if (result == null ||
        result.decision == 'assigned' ||
        _flowAssignmentOf(result) != null) {
      throw FlowUnavailableError(
        flowId: requestedFlow.id,
        flowVersion: requestedFlow.version,
        reason: 'candidate_prefetch_failed',
        message: 'Exact paywall flow "${requestedFlow.id}" version '
            '${requestedFlow.version} was unavailable.',
      );
    }
    final decoded = _decodeHostedFlow(
      result,
      requestedFlow: requestedFlow,
      exactVersion: true,
    );
    if (decoded == null) {
      throw FlowUnavailableError(
        flowId: requestedFlow.id,
        flowVersion: requestedFlow.version,
        reason: 'candidate_prefetch_rejected',
        message: 'Exact paywall flow "${requestedFlow.id}" version '
            '${requestedFlow.version} failed validation.',
      );
    }
    return _own(
      ResolvedFlow(
        document: decoded.document,
        screenBlobs: decoded.screenBlobs,
        contentHash: FlowContentHash.compute(
          FlowDocumentCodec.encodeCanonicalJson(decoded.document),
        ),
        cacheHit: false,
      ),
      requiredLibraries: decoded.requiredLibraries,
    );
  }

  _DecodedPaywallHostedFlow? _decodeHostedFlow<R>(
    SurfaceFetchResult result, {
    required OnboardingFlowRef<R> requestedFlow,
    required bool exactVersion,
  }) {
    final SurfaceDocument surface;
    try {
      surface = SurfaceDocumentCodec.decode(result.envelopeBytes);
    } on FormatException {
      return null;
    }
    if (surface.surfaceType != SurfaceType.paywall ||
        surface.surfaceSlug != requestedFlow.id ||
        (exactVersion && surface.version != requestedFlow.version)) {
      return null;
    }
    final payload = surface.payload;
    if (payload is! FlowSurfacePayload) return null;
    final document = payload.flowDocument;
    if (document.flow != requestedFlow.id ||
        (exactVersion && document.version != requestedFlow.version) ||
        document.schemaVersion != 1 ||
        document.deliveryMode != flow.deliveryMode ||
        document.minClient > flow.minClient ||
        document.minClient > RestageBuiltInCatalogCapabilities.currentVersion) {
      return null;
    }
    for (final artifact in document.screenArtifacts.values) {
      if (artifact.schemaVersion != 1 ||
          artifact.minClient > flow.minClient ||
          artifact.minClient >
              RestageBuiltInCatalogCapabilities.currentVersion) {
        return null;
      }
    }
    for (final requirement in surface.requiredLibraries) {
      if (!LibraryRuntimeRegistry.satisfies(requirement)) return null;
    }
    if (FlowDocumentValidation.validate(document).isNotEmpty) return null;
    return _DecodedPaywallHostedFlow(
      document: document,
      screenBlobs: payload.screenBlobs,
      requiredLibraries: surface.requiredLibraries,
      publishedVersion: surface.version,
    );
  }

  ResolvedFlow _own(
    ResolvedFlow resolved, {
    required List<LibraryRequirement> requiredLibraries,
  }) {
    FlowExperimentArtifactOwnership.attach(
      owner: this,
      flow: resolved,
      metadata: FlowExperimentArtifactOwnership.verifiedMetadata(
        requiredLibraries: requiredLibraries,
      ),
    );
    return resolved;
  }

  @override
  FlowExperimentArtifactMetadata metadataFor(ResolvedFlow flow) =>
      FlowExperimentArtifactOwnership.metadataFor(owner: this, flow: flow);

  @override
  bool revalidate(FlowMountRevalidationBoundary boundary) {
    final snapshot = _snapshot;
    return !_disposed &&
        snapshot != null &&
        _snapshotIsCurrent(snapshot, boundary);
  }

  @override
  void publishHostedLastGood() {
    final provisional = _provisional;
    if (!revalidate(FlowMountRevalidationBoundary.cachePublication)) {
      _provisional = null;
      return;
    }
    if (provisional != null) {
      owner._experimentFlowCache[paywallId] = provisional;
    }
    _provisional = null;
    _published = true;
  }

  @override
  void abandonHostedLastGood() {
    _provisional = null;
  }

  @override
  void disposePresentation() {
    if (_disposed) return;
    _disposed = true;
    abandonHostedLastGood();
  }

  FlowMountLeaseSeed _captureCurrentSeed() {
    try {
      return captureSeed();
    } on Object {
      throw const StaleSurfaceAssignmentResolution();
    }
  }

  bool _snapshotIsCurrent(
    FlowMountContractSnapshot snapshot,
    FlowMountRevalidationBoundary boundary,
  ) {
    if (_disposed || (!_published && !presentationGuard())) return false;
    try {
      return snapshot.revalidate(boundary, captureSeed());
    } on Object {
      return false;
    }
  }

  void _requireCurrent(
    FlowMountContractSnapshot snapshot,
    FlowMountRevalidationBoundary boundary,
  ) {
    if (!_snapshotIsCurrent(snapshot, boundary)) {
      throw const StaleSurfaceAssignmentResolution();
    }
  }
}

final class _PaywallExperimentFreshFlow {
  const _PaywallExperimentFreshFlow({
    required this.candidateRoot,
    required this.paywallPublishedVersion,
    required this.serverVerdictAccepted,
  });

  final ResolvedFlow candidateRoot;
  final int paywallPublishedVersion;
  final bool serverVerdictAccepted;
}

final class _DecodedPaywallHostedFlow {
  const _DecodedPaywallHostedFlow({
    required this.document,
    required this.screenBlobs,
    required this.requiredLibraries,
    required this.publishedVersion,
  });

  final FlowDocument document;
  final Map<String, Uint8List> screenBlobs;
  final List<LibraryRequirement> requiredLibraries;
  final int publishedVersion;
}

final class _PaywallExperimentHostedFlow {
  const _PaywallExperimentHostedFlow({
    required this.snapshot,
    required this.accepted,
    required this.paywallPublishedVersion,
  });

  final FlowMountContractSnapshot snapshot;
  final FlowCandidatePrefetchAccepted accepted;
  final int paywallPublishedVersion;

  bool matches(FlowMountContractSnapshot current) {
    return snapshot.seed.sameIdentityAs(current.seed) &&
        snapshot.assignmentKey == current.assignmentKey &&
        snapshot.contentHash == current.contentHash;
  }
}

FlowAssignment? _flowAssignmentOf(SurfaceFetchResult result) {
  final experimentId = result.experimentId;
  final variantId = result.variantId;
  final experimentEpoch = result.experimentEpoch;
  if (experimentId == null || variantId == null || experimentEpoch == null) {
    return null;
  }
  return FlowAssignment(
    experimentId: experimentId,
    variantId: variantId,
    experimentEpoch: experimentEpoch,
  );
}

Map<String, Object?> _identityPaywallFlowResult(
  Map<String, Object?> value,
) =>
    value;

/// Outcome of a fresh hosted fetch: a renderable blob (+ its cache entry), a
/// flow-shaped payload pending the active-arm gate, or a rejection.
sealed class _FreshOutcome {
  const _FreshOutcome();
}

final class _FreshBlob extends _FreshOutcome {
  const _FreshBlob(this.cacheEntry);

  final _CachedBlob cacheEntry;

  /// Derived from [cacheEntry] so the returned payload and the cache entry can
  /// never disagree (they carry the same variant).
  BlobPaywallPayload payload({HostedPayloadPublication? hostedPublication}) =>
      BlobPaywallPayload(
        cacheEntry.variant,
        assignmentLease: cacheEntry.assignmentLease,
        hostedPublication: hostedPublication,
      );
}

final class _FreshFlow extends _FreshOutcome {
  const _FreshFlow(
    this.activePayload,
    this.version,
    this.experimentId,
    this.variantId,
    this.experimentEpoch,
    this.assignmentLease,
  );

  final FlowSurfacePayload activePayload;
  final int version;
  final String? experimentId;
  final String? variantId;
  final int? experimentEpoch;
  final SurfaceAssignmentResolutionLease assignmentLease;
}

final class _FreshRejected extends _FreshOutcome {
  const _FreshRejected({this.capabilityGap});

  /// Set only when the fresh fetch was rejected for a capability reason
  /// (minClient above the installed catalog, or an unsatisfied library) — a
  /// short phrase naming the gap, carried through the fallback ladder so the
  /// exhausted-fallback error names it (rather than a generic "fetch failed").
  final String? capabilityGap;
}

/// A hold-last-good cache entry. Sealed: a renderable blob (+ the capability
/// manifest it passed) or a gate-accepted active flow (+ the metadata needed to
/// re-gate it against the current bundled contract).
sealed class _CachedPayload {
  const _CachedPayload({required this.assignmentLease});

  final SurfaceAssignmentResolutionLease assignmentLease;
}

final class _CachedBlob extends _CachedPayload {
  const _CachedBlob({
    required this.variant,
    required this.minClient,
    required this.requiredLibraries,
    required super.assignmentLease,
  });

  final ResolvedVariant variant;
  final int minClient;
  final List<LibraryRequirement> requiredLibraries;
}

final class _CachedFlow extends _CachedPayload {
  const _CachedFlow({
    required this.activePayload,
    required this.version,
    required this.experimentId,
    required this.variantId,
    required this.experimentEpoch,
    required super.assignmentLease,
  });

  /// The served active flow payload, retained so a cache hit can re-run the
  /// full active-arm gate (render gate + retained checks) against the CURRENT
  /// bundled contract — a stale active flow that no longer renders safely is
  /// never re-served.
  final FlowSurfacePayload activePayload;
  final int version;
  final String? experimentId;
  final String? variantId;
  final int? experimentEpoch;
}

/// Adds the exact assignment/publication transaction to a flow payload.
///
/// Kept package-internal so accepted-candidate identity remains SDK-owned.
@internal
FlowPaywallPayload stampFlowPayloadForDelivery(
  FlowPaywallPayload payload,
  SurfaceAssignmentResolutionLease assignmentLease, {
  HostedPayloadPublication? hostedPublication,
}) =>
    payload.copyForDelivery(
      assignmentLease: assignmentLease,
      hostedPublication: hostedPublication,
    );

/// Removes hosted assignment/publication state without unpinning a candidate.
///
/// Kept package-internal for exact transform-path regression coverage.
@internal
ResolvedPaywallPayload withoutAssignmentLeaseForDelivery(
  ResolvedPaywallPayload payload,
) =>
    switch (payload) {
      BlobPaywallPayload(:final variant) => BlobPaywallPayload(variant),
      FlowPaywallPayload() => payload.copyForDelivery(assignmentLease: null),
    };

/// Environment hint passed to `Restage.configure` and [RestageVariantResolver].
enum RestageEnvironment {
  /// Sandbox environment — paired with `rs_pk_test_…` API keys. Test
  /// purchases route through the platform sandbox; events are not metered.
  sandbox,

  /// Production environment — paired with `rs_pk_live_…` API keys. Real
  /// charges; events are metered for billing.
  production,
}
