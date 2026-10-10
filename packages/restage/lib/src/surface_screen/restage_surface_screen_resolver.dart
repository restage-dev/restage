import 'package:flutter/foundation.dart' show listEquals;
import 'package:meta/meta.dart';
import 'package:restage_shared/restage_shared.dart';

import '../delivery/surface_sections_carrier.dart';
import '../delivery/raced_surface_resolver.dart';
import '../delivery/surface_artifact_store.dart';
import '../delivery/surface_delivery_receipt.dart';
import '../flow/flow_descriptors.dart';
import '../measurement/measurement_resolved_publication_provenance.dart';
import '../resolver/restage_variant_resolver.dart' show RestageEnvironment;
import '../resolver/surface_resolution_report.dart';
import '../resolver/surface_canonical_carrier_provider.dart';
import '../resolver/delivery_input_budget.dart';
import '../resolver/surface_request_inputs.dart';
import '../restage_rpc_client/restage_rpc_client.dart';
import '../runtime/installed_widget_vocabulary.dart';
import 'asset_surface_screen_resolver.dart';
import 'surface_screen_runtime_provenance.dart';
import 'surface_screen_types.dart';

/// Resolves one generated screen from hosted delivery with verified bundled fallback.
///
/// A mount races [fresh] (the hosted screen, gated) against [bestLocal] (the
/// last accepted delivery on this device, re-gated, then the bundled copy).
final class RestageScreenResolver implements SurfaceScreenResolver {
  /// Creates the standard hosted standalone-screen resolver.
  RestageScreenResolver({
    required this.apiKey,
    required this.environment,
    this.baseUrl,
    this.assetFallback = const AssetSurfaceScreenResolver(),
    RestageRpcClient? Function()? rpcClientProvider,
  }) : _rpcClientProvider = rpcClientProvider {
    registerRacedResolver(this, _raced);
  }

  /// Credential used when this resolver constructs its own RPC client.
  final String apiKey;

  /// Configured delivery environment.
  final RestageEnvironment environment;

  /// Hosted service origin. A null origin uses the bundled resolver directly.
  final String? baseUrl;

  /// Exact generated bundled fallback resolver.
  final BundledSurfaceScreenResolver assetFallback;

  final RestageRpcClient? Function()? _rpcClientProvider;
  late final RacedSurfaceDelegate<ResolvedSurfaceScreen> _raced =
      RacedSurfaceDelegate<ResolvedSurfaceScreen>(
    bestLocal: bestLocal,
    fresh: fresh,
    surfaceFor: _reportSurfaceFor,
  );
  RestageRpcClient? _ownedClient;

  /// The screen each raced store key was issued for.
  final Map<SurfaceStoreKey, SurfaceScreenRef<Object?>> _refs =
      <SurfaceStoreKey, SurfaceScreenRef<Object?>>{};
  final Map<SurfaceStoreKey, SurfaceScreenUnavailableError> _bundledErrors =
      <SurfaceStoreKey, SurfaceScreenUnavailableError>{};

  /// Where accepted deliveries persist.
  @internal
  SurfaceArtifactStore get store => sharedSurfaceArtifactStore;

  /// The store key for [screen], at its generated contract version.
  @internal
  SurfaceStoreKey storeKeyFor<E>(SurfaceScreenRef<E> screen) {
    final key = SurfaceStoreKey(
      scope: SurfaceStoreKey.scopeFor(
        apiKey: apiKey,
        environment: environment.name,
      ),
      surfaceType: SurfaceSourceKind.screen.wireName,
      slug: screen.slug,
      contractVersion: screen.contractVersion,
    );
    _refs[key] = screen as SurfaceScreenRef<Object?>;
    return key;
  }

  Surface _reportSurfaceFor(SurfaceStoreKey key) =>
      _refs[key]?.surface ?? Surface.fromWireName(key.surfaceType);

  @override
  Future<ResolvedSurfaceScreen> resolve<E>(SurfaceScreenRef<E> screen) async {
    final key = storeKeyFor(screen);
    final resolved = await resolveRacedInOrder(_raced, key);
    if (resolved != null) return resolved;
    final bundledError = _bundledErrors.remove(key);
    if (bundledError != null) throw bundledError;
    throw const SurfaceScreenUnavailableError(
      reason: SurfaceScreenUnavailableReason.missing,
      message: 'Hosted screen resolution crossed an identity boundary.',
    );
  }

  /// The hosted screen, gated and persisted on accept. Throws for a present
  /// response that cannot be trusted; it is never eligible for fallback.
  @internal
  Future<ResolvedSurfaceScreen?> fresh(
    SurfaceStoreKey key, {
    required bool sendAssignmentKey,
    Future<void>? keyDeadline,
  }) async {
    // A key this resolver issued no ref for cannot be gated; nothing to do.
    final screen = _refs[key];
    if (screen == null) return null;
    _raced.freshStarted(key);
    final client = _rpcClient();
    if (client == null) {
      _raced.freshRefused(key, SurfaceDeliveryReceiptReason.none);
      return null;
    }
    final supportedPolicyRevisions = supportedPolicyRevisionsCarrier();
    // Three attempts in all when the identity changes under a request.
    for (var attempt = 0; attempt != _maxIdentityAttempts; attempt += 1) {
      final accepted = await DeliveryInputBudget.run(
        (budget) => _attempt(
          key,
          screen,
          client,
          budget,
          supportedPolicyRevisions,
          sendAssignmentKey: sendAssignmentKey,
          keyDeadline: keyDeadline,
        ),
      );
      if (accepted case (final resolved?,)) return resolved;
      if (accepted != null) return null;
    }
    _raced.freshRefused(key, SurfaceDeliveryReceiptReason.offline);
    return null;
  }

  /// One attempt: `(screen)` when accepted, `(null)` when refused, and null
  /// when the identity changed under it.
  Future<(ResolvedSurfaceScreen?,)?> _attempt(
    SurfaceStoreKey key,
    SurfaceScreenRef<Object?> screen,
    RestageRpcClient client,
    DeliveryInputBudget budget,
    String? supportedPolicyRevisions, {
    required bool sendAssignmentKey,
    required Future<void>? keyDeadline,
  }) async {
    final provenance = screen.provenance;
    final inputs = await SurfaceRequestInputs.gather(
      budget: budget,
      surface: screen.surface.wireName,
      slug: screen.slug,
      contractVersion: screen.contractVersion,
      sendAssignmentKey: sendAssignmentKey,
      keyDeadline: keyDeadline,
    );
    final lease = inputs.lease;
    if (!lease.isCurrent) return null;
    final assignmentKey = sendAssignmentKey ? lease.assignmentKey : null;
    final request = SurfaceScreenDeliveryRequest(
      surface: screen.surface,
      slug: screen.slug,
      contractVersion: screen.contractVersion,
      assignmentKey: assignmentKey,
      meteringKey: inputs.meteringKey,
      analyticsAnonymousId: inputs.analyticsAnonymousId,
      sdkSupportedPolicyRevisions: supportedPolicyRevisions,
      sdkBuiltInsCanonicalBase64: inputs.builtIns,
      assignmentCanonicalBase64: sendAssignmentKey && assignmentKey != null
          ? inputs.heldAssignment
          : null,
    );
    final result = await client.fetchSurfaceScreen(
      request,
      readerHostDataContractHash: provenance.hostDataContractHash,
      registrationLease: lease,
    );
    if (!lease.isCurrent) return null;
    switch (result) {
      case SurfaceScreenDeliveryAvailable(
          :final canonicalExperimentAssignment,
          :final stored,
        ):
        if (lease.assignmentKey != null) {
          await budget.bound(SurfaceCanonicalCarrierProvider.retain(
            surface: screen.surface.wireName,
            slug: screen.slug,
            contractVersion: screen.contractVersion,
            lease: lease,
            assignment: canonicalExperimentAssignment,
          ));
        }
        if (!lease.isCurrent) return null;
        final resolved = attachSurfaceAssignmentLease(
          _resolveHosted(result, provenance, cacheHit: false),
          lease,
        );
        await persistAcceptedDelivery(store, key, stored);
        return (
          labelSurfaceSource<ResolvedSurfaceScreen>(
              resolved, SurfaceResolutionSource.fresh),
        );
      case SurfaceScreenDeliveryAbsent():
        _raced.freshRefused(key, SurfaceDeliveryReceiptReason.none);
        return (null,);
      case SurfaceScreenDeliveryTransportUnavailable():
        _raced.freshRefused(key, SurfaceDeliveryReceiptReason.offline);
        return (null,);
      case SurfaceScreenDeliveryInvalidResponse(:final reason):
        _raced.freshRefused(key, SurfaceDeliveryReceiptReason.unsupported);
        throw _invalidHostedResponse(reason);
    }
  }

  /// Local candidates for [key]: the stored screen re-gated, then bundled.
  @internal
  Future<ResolvedSurfaceScreen?> bestLocal(SurfaceStoreKey key) async {
    _bundledErrors.remove(key);
    final screen = _refs[key];
    if (screen == null) return null;
    final held = await _storedScreen(key, screen);
    if (held != null) {
      return labelSurfaceSource<ResolvedSurfaceScreen>(
          held, SurfaceResolutionSource.holdLastGood);
    }
    try {
      return labelSurfaceSource<ResolvedSurfaceScreen>(
        await _resolveBundled(screen, screen.provenance),
        SurfaceResolutionSource.bundled,
      );
    } on SurfaceScreenUnavailableError catch (error) {
      _bundledErrors[key] = error;
      return null;
    }
  }

  /// The stored delivery for [screen], re-gated exactly as a fresh one.
  Future<ResolvedSurfaceScreen?> _storedScreen(
    SurfaceStoreKey key,
    SurfaceScreenRef<Object?> screen,
  ) async {
    try {
      final stored = await store.read(key);
      if (stored == null) return null;
      final provenance = screen.provenance;
      final replayed = await replayStoredSurfaceScreen(
        stored,
        SurfaceScreenDeliveryRequest(
          surface: screen.surface,
          slug: screen.slug,
          contractVersion: screen.contractVersion,
        ),
        readerHostDataContractHash: provenance.hostDataContractHash,
      );
      if (replayed is! SurfaceScreenDeliveryAvailable) return null;
      final identity = await storedDeliveryIdentity(
        stored: stored,
        assignment: replayed.canonicalExperimentAssignment,
        surface: screen.surface.wireName,
        slug: screen.slug,
        contractVersion: screen.contractVersion,
      );
      if (!identity.reusable) return null;
      final resolved = attachSurfaceAssignmentLease(
        _resolveHosted(replayed, provenance, cacheHit: true),
        identity.lease,
      );
      provenance.validateResolved(resolved);
      return resolved;
    } on Object {
      return null;
    }
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
    SurfaceScreenDeliveryAvailable result,
    SurfaceScreenRuntimeProvenance provenance, {
    required bool cacheHit,
  }) {
    final response = result.response;
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
      attachSurfacePayload(
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
          cacheHit: cacheHit,
        ),
        payload,
      ),
      result.publicationBindingReference,
      canonicalExperimentAssignment: result.canonicalExperimentAssignment,
      routingSelectionReceipt: result.routingSelectionReceipt,
      routingSelectionProvenance: result.routingSelectionProvenance,
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

/// Deprecated spelling of [RestageScreenResolver].
///
/// Removed at 3.0.
@Deprecated('Use RestageScreenResolver')
typedef RestageSurfaceScreenResolver = RestageScreenResolver;
