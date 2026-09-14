import 'package:flutter/foundation.dart' show listEquals;
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';

import '../flow/flow_descriptors.dart';
import '../measurement/measurement_resolved_publication_provenance.dart';
import '../resolver/restage_variant_resolver.dart' show RestageEnvironment;
import '../resolver/surface_assignment_key_provider.dart';
import '../resolver/report_surface_resolution.dart';
import '../resolver/surface_resolution_report.dart';
import '../resolver/surface_canonical_carrier_provider.dart';
import '../resolver/surface_delivery_observations.dart'
    show currentSurfaceDeliveryObservationCell;
import '../resolver/surface_analytics_identity_provider.dart';
import '../resolver/surface_metering_key_provider.dart';
import '../restage_rpc_client/restage_rpc_client.dart';
import '../runtime/installed_widget_vocabulary.dart';
import 'asset_surface_screen_resolver.dart';
import 'surface_screen_runtime_provenance.dart';
import 'surface_screen_types.dart';

/// Resolves one generated screen from hosted delivery with verified bundled fallback.
final class RestageScreenResolver implements SurfaceScreenResolver {
  /// Creates the standard hosted standalone-screen resolver.
  RestageScreenResolver({
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
    final observationCell = SurfaceCanonicalCarrierProvider.hasBuiltIns
        ? currentSurfaceDeliveryObservationCell()
        : null;
    final supportedPolicyRevisions = supportedPolicyRevisionsCarrier();
    for (var attempt = 0; attempt != _maxIdentityAttempts; attempt += 1) {
      final lease = await SurfaceAssignmentKeyProvider.captureLease();
      final analyticsGeneration = SurfaceAnalyticsIdentityProvider.generation;
      final analyticsAnonymousId =
          await SurfaceAnalyticsIdentityProvider.anonymousId();
      if (!lease.isCurrent) continue;
      final key = _ScreenCacheKey(
        surface: screen.surface,
        slug: screen.slug,
        contractVersion: screen.contractVersion,
        assignmentKey: lease.assignmentKey,
      );
      final cached = _cache[key];
      if (cached != null && !cached.lease.isCurrent) _cache.remove(key);

      final client = _rpcClient();
      if (client == null) {
        return _resolveBundled(screen, provenance);
      }
      final meteringKey = await SurfaceMeteringKeyProvider.currentKey();
      final builtIns = observationCell != null
          ? (await observationCell.read()).canonicalBuiltInsBase64()
          : await SurfaceCanonicalCarrierProvider.builtIns();
      final heldAssignment =
          await SurfaceCanonicalCarrierProvider.heldAssignment(
        surface: screen.surface.wireName,
        slug: screen.slug,
        contractVersion: screen.contractVersion,
        assignmentKey: lease.assignmentKey,
      );
      if (!lease.isCurrent) continue;
      final request = SurfaceScreenDeliveryRequest(
        surface: screen.surface,
        slug: screen.slug,
        contractVersion: screen.contractVersion,
        assignmentKey: lease.assignmentKey,
        meteringKey: meteringKey,
        analyticsAnonymousId: lease.isCurrent &&
                SurfaceAnalyticsIdentityProvider.generation ==
                    analyticsGeneration
            ? analyticsAnonymousId
            : null,
        sdkSupportedPolicyRevisions: supportedPolicyRevisions,
        sdkBuiltInsCanonicalBase64: builtIns,
        assignmentCanonicalBase64: heldAssignment,
      );
      final result = await client.fetchSurfaceScreen(
        request,
        readerHostDataContractHash: provenance.hostDataContractHash,
      );
      if (!lease.isCurrent) continue;
      switch (result) {
        case SurfaceScreenDeliveryAvailable(
            :final response,
            :final publicationBindingReference,
            :final canonicalExperimentAssignment,
            :final routingSelectionReceipt,
            :final routingSelectionProvenance,
          ):
          await SurfaceCanonicalCarrierProvider.retain(
            surface: screen.surface.wireName,
            slug: screen.slug,
            contractVersion: screen.contractVersion,
            lease: lease,
            assignment: canonicalExperimentAssignment,
          );
          if (!lease.isCurrent) continue;
          final resolved = _resolveHosted(
            response,
            provenance,
            publicationBindingReference,
            canonicalExperimentAssignment,
            routingSelectionReceipt,
            routingSelectionProvenance,
          );
          _cache[key] = _CachedHostedScreen(screen: resolved, lease: lease);
          return reportSurfaceResolution(
              screen.slug, resolved, SurfaceResolutionSource.fresh);
        case SurfaceScreenDeliveryAbsent():
        case SurfaceScreenDeliveryTransportUnavailable():
          final held = _cache[key];
          if (held != null && held.lease.isCurrent) {
            final verdict = BlobRenderCapabilityGate.evaluate(
              required: held.screen.capabilities,
              installed: currentInstalledCapability(),
            );
            if (verdict is! BlobRenderRejected) {
              try {
                provenance.validateResolved(held.screen);
              } on SurfaceScreenUnavailableError {
                return _resolveBundled(screen, provenance);
              }
              return reportSurfaceResolution(
                screen.slug,
                held.screen.withCacheHit(),
                SurfaceResolutionSource.holdLastGood,
              );
            }
          }
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
    SurfaceScreenDeliveryResponse response,
    SurfaceScreenRuntimeProvenance provenance,
    MeasurementPublicationBindingReferenceV1? publicationBindingReference,
    CanonicalSurfaceExperimentAssignmentV1? canonicalExperimentAssignment,
    String? routingSelectionReceipt,
    SurfaceRoutingSelectionProvenanceV1? routingSelectionProvenance,
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
      installed: currentInstalledCapability(),
    );
    if (capabilityVerdict is BlobRenderRejected) {
      throw SurfaceScreenUnavailableError(
        reason: SurfaceScreenUnavailableReason.incompatible,
        message: 'The installed runtime cannot render the hosted screen.',
        cause: capabilityVerdict,
      );
    }
    return attachMeasurementPublicationBindingReference(
      ResolvedSurfaceScreen.hosted(
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
        cacheHit: false,
      ),
      publicationBindingReference,
      canonicalExperimentAssignment: canonicalExperimentAssignment,
      routingSelectionReceipt: routingSelectionReceipt,
      routingSelectionProvenance: routingSelectionProvenance,
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
    return reportSurfaceResolution(
        screen.slug, resolved, SurfaceResolutionSource.bundled);
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

/// Deprecated spelling of [RestageScreenResolver].
///
/// Removed at 3.0.
@Deprecated('Use RestageScreenResolver')
typedef RestageSurfaceScreenResolver = RestageScreenResolver;
