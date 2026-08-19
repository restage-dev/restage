import 'package:flutter/foundation.dart' show listEquals;
import 'package:restage_shared/restage_shared.dart';

import '../flow/flow_descriptors.dart';
import '../resolver/restage_variant_resolver.dart' show RestageEnvironment;
import '../resolver/surface_assignment_key_provider.dart';
import '../resolver/surface_metering_key_provider.dart';
import '../restage_rpc_client/restage_rpc_client.dart';
import '../runtime/builtin_catalog_capabilities.dart';
import '../runtime/library_runtime_registry.dart';
import 'asset_surface_screen_resolver.dart';
import 'surface_screen_runtime_provenance.dart';
import 'surface_screen_types.dart';

/// Resolves one generated screen from hosted delivery with verified bundled fallback.
final class RestageSurfaceScreenResolver implements SurfaceScreenResolver {
  /// Creates the standard hosted standalone-screen resolver.
  RestageSurfaceScreenResolver({
    required this.apiKey,
    required this.environment,
    this.baseUrl,
    this.assetFallback = const AssetSurfaceScreenResolver(),
    RestageRpcClient? Function()? rpcClientProvider,
  }) : _rpcClientProvider = rpcClientProvider;

  /// Credential used when this resolver constructs its own RPC client.
  final String apiKey;

  /// Configured delivery environment.
  final RestageEnvironment environment;

  /// Hosted service origin. A null origin uses the bundled resolver directly.
  final String? baseUrl;

  /// Exact generated bundled fallback resolver.
  final BundledSurfaceScreenResolver assetFallback;

  final RestageRpcClient? Function()? _rpcClientProvider;
  final Map<_ScreenCacheKey, _CachedHostedScreen> _cache =
      <_ScreenCacheKey, _CachedHostedScreen>{};
  RestageRpcClient? _ownedClient;

  @override
  Future<ResolvedSurfaceScreen> resolve<E>(SurfaceScreenRef<E> screen) async {
    final provenance = screen.provenance;
    for (var attempt = 0; attempt != _maxIdentityAttempts; attempt += 1) {
      final lease = await SurfaceAssignmentKeyProvider.captureLease();
      if (!lease.isCurrent) continue;
      final key = _ScreenCacheKey(
        surface: screen.surface,
        slug: screen.slug,
        contractVersion: screen.contractVersion,
        assignmentKey: lease.assignmentKey,
      );
      final cached = _cache[key];
      if (cached != null) {
        if (cached.lease.isCurrent) return cached.screen.withCacheHit();
        _cache.remove(key);
      }

      final client = _rpcClient();
      if (client == null) {
        return _resolveBundled(screen, provenance);
      }
      final meteringKey = await SurfaceMeteringKeyProvider.currentKey();
      if (!lease.isCurrent) continue;
      final request = SurfaceScreenDeliveryRequestV1(
        surface: screen.surface,
        slug: screen.slug,
        contractVersion: screen.contractVersion,
        assignmentKey: lease.assignmentKey,
        meteringKey: meteringKey,
      );
      final result = await client.fetchSurfaceScreen(request);
      if (!lease.isCurrent) continue;
      switch (result) {
        case SurfaceScreenDeliveryAvailable(:final response):
          final resolved = _resolveHosted(response, provenance);
          if (resolved.assignment != null && lease.assignmentKey == null) {
            throw const SurfaceScreenUnavailableError(
              reason: SurfaceScreenUnavailableReason.contractMismatch,
              message:
                  'Hosted screen assignment does not match the request context.',
            );
          }
          _cache[key] = _CachedHostedScreen(screen: resolved, lease: lease);
          return resolved;
        case SurfaceScreenDeliveryAbsent():
        case SurfaceScreenDeliveryTransportUnavailable():
          return _resolveBundled(screen, provenance);
        case SurfaceScreenDeliveryInvalidResponse(:final reason):
          throw _invalidHostedResponse(reason);
      }
    }
    throw const SurfaceScreenUnavailableError(
      reason: SurfaceScreenUnavailableReason.missing,
      message: 'Hosted screen resolution crossed an identity boundary.',
    );
  }

  static const int _maxIdentityAttempts = 3;

  RestageRpcClient? _rpcClient() {
    final provided = _rpcClientProvider?.call();
    if (provided != null) return provided;
    final origin = baseUrl;
    if (origin == null || origin.isEmpty) return null;
    return _ownedClient ??= RestageRpcClient(baseUrl: origin, apiKey: apiKey);
  }

  ResolvedSurfaceScreen _resolveHosted(
    SurfaceScreenDeliveryResponseV1 response,
    SurfaceScreenRuntimeProvenance provenance,
  ) {
    final document = response.document;
    final payload = document.payload;
    if (document.surfaceType != provenance.surface ||
        document.surfaceSlug != provenance.slug ||
        response.contractVersion != provenance.contractVersion) {
      throw const SurfaceScreenUnavailableError(
        reason: SurfaceScreenUnavailableReason.identityMismatch,
        message:
            'Hosted screen identity does not match the generated reference.',
      );
    }
    if (response.sourceKind != SurfaceSourceKind.screen ||
        response.payloadKind != SurfacePayloadKind.blob ||
        payload is! BlobSurfacePayload ||
        response.contractFingerprint != provenance.contractFingerprint ||
        response.eventContractHash != provenance.eventContractHash ||
        document.minClient != provenance.capabilities.builtInFloor ||
        !listEquals(
          document.requiredLibraries,
          provenance.capabilities.requiredLibraries,
        )) {
      throw const SurfaceScreenUnavailableError(
        reason: SurfaceScreenUnavailableReason.contractMismatch,
        message:
            'Hosted screen contract does not match the generated contract.',
      );
    }
    final capabilityVerdict = BlobRenderCapabilityGate.evaluate(
      required: provenance.capabilities,
      installed: InstalledCapability(
        builtInCatalogVersion: RestageBuiltInCatalogCapabilities.currentVersion,
        installedLibraries: LibraryRuntimeRegistry.installedSnapshot(),
      ),
    );
    if (capabilityVerdict is BlobRenderRejected) {
      throw SurfaceScreenUnavailableError(
        reason: SurfaceScreenUnavailableReason.incompatible,
        message: 'The installed runtime cannot render the hosted screen.',
        cause: capabilityVerdict,
      );
    }
    return ResolvedSurfaceScreen.hosted(
      surface: document.surfaceType,
      slug: document.surfaceSlug,
      contractVersion: response.contractVersion,
      publishedRevision: response.publishedRevision,
      sourceKind: response.sourceKind,
      payloadKind: response.payloadKind,
      capabilities: provenance.capabilities,
      contractFingerprint: response.contractFingerprint,
      eventContractHash: response.eventContractHash,
      blob: payload.blob,
      contentHash: document.contentHash,
      assignment: response.assignment,
      cacheHit: false,
    );
  }

  Future<ResolvedSurfaceScreen> _resolveBundled<E>(
    SurfaceScreenRef<E> screen,
    SurfaceScreenRuntimeProvenance provenance,
  ) async {
    final resolved = await assetFallback.resolve(screen);
    if (resolved.origin != SurfaceScreenOrigin.bundled) {
      throw const SurfaceScreenUnavailableError(
        reason: SurfaceScreenUnavailableReason.contractMismatch,
        message: 'The bundled fallback did not return bundled content.',
      );
    }
    provenance.validateResolved(resolved);
    return resolved;
  }

  SurfaceScreenUnavailableError _invalidHostedResponse(
    SurfaceScreenDeliveryInvalidResponseReason reason,
  ) =>
      SurfaceScreenUnavailableError(
        reason: switch (reason) {
          SurfaceScreenDeliveryInvalidResponseReason.requestRejected =>
            SurfaceScreenUnavailableReason.invalidPayload,
          SurfaceScreenDeliveryInvalidResponseReason.identityMismatch =>
            SurfaceScreenUnavailableReason.identityMismatch,
          SurfaceScreenDeliveryInvalidResponseReason.contractMismatch =>
            SurfaceScreenUnavailableReason.contractMismatch,
          SurfaceScreenDeliveryInvalidResponseReason.malformed =>
            SurfaceScreenUnavailableReason.invalidPayload,
        },
        message: 'Hosted screen delivery returned an invalid response.',
      );
}

final class _ScreenCacheKey {
  const _ScreenCacheKey({
    required this.surface,
    required this.slug,
    required this.contractVersion,
    required this.assignmentKey,
  });

  final Surface surface;
  final String slug;
  final int contractVersion;
  final String? assignmentKey;

  @override
  bool operator ==(Object other) =>
      other is _ScreenCacheKey &&
      other.surface == surface &&
      other.slug == slug &&
      other.contractVersion == contractVersion &&
      other.assignmentKey == assignmentKey;

  @override
  int get hashCode =>
      Object.hash(surface, slug, contractVersion, assignmentKey);
}

final class _CachedHostedScreen {
  const _CachedHostedScreen({required this.screen, required this.lease});

  final ResolvedSurfaceScreen screen;
  final SurfaceAssignmentResolutionLease lease;
}
