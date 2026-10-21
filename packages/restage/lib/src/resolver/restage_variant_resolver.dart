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
        LibraryRequirement,
        SurfaceDocument,
        Surface;

import '../delivery/surface_sections_carrier.dart';
import '../delivery/raced_surface_resolver.dart';
import '../delivery/surface_artifact_store.dart';
import '../delivery/surface_delivery_receipt.dart';
import '../flow/flow_descriptors.dart';
import '../flow/flow_experiment_artifact_metadata.dart';
import '../flow/flow_experiment_mount.dart';
import '../flow/flow_resolver.dart';
import '../measurement/measurement_resolved_publication_provenance.dart';
import '../restage_rpc_client/restage_rpc_client.dart';
import '../restage_rpc_client/surface_artifact_assembly.dart';
import '../runtime/builtin_catalog_capabilities.dart';
import '../runtime/installed_widget_vocabulary.dart';
import '../runtime/library_runtime_registry.dart';
import '../runtime/local_values.dart' show SurfaceSections;
import '../runtime/paywall_error.dart';
import 'asset_variant_resolver.dart';
import 'asset_paywall_flow_preflight.dart';
import 'delivery_input_budget.dart';
import 'flow_paywall_active_arm.dart';
import 'resolved_paywall_payload.dart';
import 'resolved_variant.dart';
import 'surface_assignment_key_provider.dart';
import 'surface_request_inputs.dart';
import 'surface_resolution_report.dart';
import 'variant_resolver.dart';

/// Resolves paywalls from hosted delivery, retained content and bundled assets.
/// Mounts race [fresh] against [bestLocal]; rejected content is never rendered.
/// [resolve], [resolvePayload] and [resolvePayloadForPresentation] try these
/// sources in sequence without a deadline.
///
/// Hosted flows must satisfy the bundled flow contract. [resolve] returns blobs.
/// `Restage.configure` installs this resolver; bundled-only apps can use
/// [AssetVariantResolver].
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
              ) {
    registerRacedResolver(this, _raced);
  }

  /// Publishable Restage key used by hosted paywall delivery.
  final String apiKey;

  /// Environment the API key targets (sandbox vs production).
  final RestageEnvironment environment;

  final RestageRpcClient? _client;
  final VariantResolver _assetFallback;
  late final RacedSurfaceDelegate<ResolvedPaywallPayload> _raced =
      RacedSurfaceDelegate<ResolvedPaywallPayload>(
    bestLocal: bestLocal,
    fresh: fresh,
    leafOf: _leafOf,
  );
  final Map<SurfaceStoreKey, String> _capabilityGaps =
      <SurfaceStoreKey, String>{};

  /// Where accepted deliveries persist.
  @internal
  SurfaceArtifactStore get store => sharedSurfaceArtifactStore;

  /// The store key for paywall [id]; paywalls carry no contract version.
  @internal
  SurfaceStoreKey storeKeyFor(String id) => SurfaceStoreKey(
        scope: SurfaceStoreKey.scopeFor(
          apiKey: apiKey,
          environment: environment.name,
        ),
        surfaceType: Surface.paywall.wireName,
        slug: id,
        contractVersion: 0,
      );

  @override
  Future<ResolvedVariant> resolve(
    String id, {
    String? placementId,
    Locale? locale,
  }) async {
    final key = storeKeyFor(id);
    final fresh = await _freshPlain(
      key,
      sendAssignmentKey: true,
      keyDeadline: null,
      blobOnly: true,
    );
    final winner = fresh ??
        await _storedBlobOnly(key) ??
        await _bundledBlob(id, placementId: placementId, locale: locale);
    reportRacedSurface<ResolvedPaywallPayload>(_raced, key, winner);
    if (winner is BlobPaywallPayload) return winner.variant;
    throw _unavailable(id, _capabilityGaps[key]);
  }

  @internal
  @override
  Future<ResolvedPaywallPayload> resolvePayload(
    String id, {
    String? placementId,
    Locale? locale,
  }) =>
      _resolveInOrder(id, placementId: placementId, locale: locale);

  @internal
  @override
  Future<ResolvedPaywallPayload> resolvePayloadForPresentation(
    String id, {
    String? placementId,
    Locale? locale,
  }) =>
      _resolveInOrder(id, placementId: placementId, locale: locale);

  Future<ResolvedPaywallPayload> _resolveInOrder(
    String id, {
    String? placementId,
    Locale? locale,
  }) async {
    final key = storeKeyFor(id);
    final winner = await fresh(key, sendAssignmentKey: true) ??
        await _bestLocal(key, placementId: placementId, locale: locale);
    reportRacedSurface<ResolvedPaywallPayload>(_raced, key, winner);
    if (winner == null) throw _unavailable(id, _capabilityGaps[key]);
    return winner;
  }

  /// Local candidates for [key]: the stored delivery re-gated, then bundled.
  @internal
  Future<ResolvedPaywallPayload?> bestLocal(SurfaceStoreKey key) =>
      _bestLocal(key);

  Future<ResolvedPaywallPayload?> _bestLocal(
    SurfaceStoreKey key, {
    String? placementId,
    Locale? locale,
  }) async {
    final id = key.slug;
    final guard = currentPaywallPresentationGuard();
    final baseline = await _experimentBaseline(id);
    if (!guard()) throw const StaleSurfaceAssignmentResolution();

    final stored = await _readStored(key);
    if (stored != null) {
      final held = await _storedPayload(key, stored, baseline, guard);
      if (held != null) {
        return _label(held, SurfaceResolutionSource.holdLastGood);
      }
    }

    if (baseline != null) {
      return _label(
        FlowPaywallPayload.experimentBaseline(
          flow: baseline.root,
          pinnedFlowResolver: baseline,
          paywallId: id,
        ),
        SurfaceResolutionSource.bundled,
      );
    }
    final fallback = _assetFallback;
    try {
      if (fallback is FlowCapableVariantResolver) {
        final payload = await (fallback as FlowCapableVariantResolver)
            .resolvePayload(id, placementId: placementId, locale: locale);
        return _label(
          withoutAssignmentLeaseForDelivery(payload),
          SurfaceResolutionSource.bundled,
        );
      }
    } on RestagePaywallError {
      return null;
    }
    return _bundledBlob(id, placementId: placementId, locale: locale);
  }

  /// The hosted delivery for [key], gated and persisted on accept.
  @internal
  Future<ResolvedPaywallPayload?> fresh(
    SurfaceStoreKey key, {
    required bool sendAssignmentKey,
    Future<void>? keyDeadline,
  }) async {
    _raced.freshStarted(key);
    _capabilityGaps.remove(key);
    if (_client == null) {
      // No hosted tier: the bundled copy is the design, not a fallback.
      _raced.freshRefused(key, SurfaceDeliveryReceiptReason.none);
      return null;
    }
    final guard = currentPaywallPresentationGuard();
    final baseline = await _experimentBaseline(key.slug);
    if (!guard()) throw const StaleSurfaceAssignmentResolution();
    if (baseline != null) {
      final presentation = _RestagePaywallExperimentPresentation.forBaseline(
        owner: this,
        key: key,
        baseline: baseline,
        presentationGuard: guard,
        sendAssignmentKey: sendAssignmentKey,
        keyDeadline: keyDeadline,
      );
      final outcome = await presentation.fresh();
      if (outcome.applicable) {
        if (outcome.payload == null) presentation.disposePresentation();
        return outcome.payload;
      }
      presentation.disposePresentation();
    }
    return _freshPlain(
      key,
      sendAssignmentKey: sendAssignmentKey,
      keyDeadline: keyDeadline,
      blobOnly: false,
    );
  }

  /// The active hosted version, gated; persisted on accept.
  Future<ResolvedPaywallPayload?> _freshPlain(
    SurfaceStoreKey key, {
    required bool sendAssignmentKey,
    required Future<void>? keyDeadline,
    required bool blobOnly,
  }) async {
    _raced.freshStarted(key);
    if (_client == null) {
      _raced.freshRefused(key, SurfaceDeliveryReceiptReason.none);
      return null;
    }
    final id = key.slug;
    final guard = currentPaywallPresentationGuard();
    for (var attempt = 0; attempt < _maxIdentityAttempts; attempt += 1) {
      try {
        final fresh = await _resolveFresh(
          id,
          sendAssignmentKey: sendAssignmentKey,
          keyDeadline: keyDeadline,
        );
        switch (fresh) {
          case _FreshBlob():
            _requireCurrent(fresh.assignmentLease);
            await _persist(key, fresh.stored);
            return _label(
              fresh.payload(),
              SurfaceResolutionSource.fresh,
            );
          case _FreshFlow():
            if (blobOnly) {
              _raced.freshRefused(
                  key, SurfaceDeliveryReceiptReason.unsupported);
              return null;
            }
            final bundled = await _bundledFlowPayload(id);
            if (bundled == null) {
              _raced.freshRefused(
                  key, SurfaceDeliveryReceiptReason.unsupported);
              return null;
            }
            _requireCurrent(fresh.assignmentLease);
            final arm = _gateActiveFlow(
                id, fresh.result, fresh.activePayload, fresh.version, bundled,
                cacheHit: false);
            if (arm == null) {
              _raced.freshRefused(
                  key, SurfaceDeliveryReceiptReason.unsupported);
              return null;
            }
            _requireCurrent(fresh.assignmentLease);
            await _persist(key, fresh.result.stored);
            return _label(
              stampFlowPayloadForDelivery(arm, fresh.assignmentLease),
              SurfaceResolutionSource.fresh,
            );
          case _FreshRejected(:final reason, :final capabilityGap):
            if (capabilityGap != null) _capabilityGaps[key] = capabilityGap;
            _raced.freshRefused(key, reason);
            return null;
        }
      } on StaleSurfaceAssignmentResolution {
        if (!guard()) rethrow;
      }
    }
    _raced.freshRefused(key, SurfaceDeliveryReceiptReason.offline);
    return null;
  }

  static const int _maxIdentityAttempts = 3;

  Future<void> _persist(SurfaceStoreKey key, StoredSurface? stored) =>
      persistAcceptedDelivery(store, key, stored);

  Future<SurfaceFetchResult?> _readStored(SurfaceStoreKey key) async {
    try {
      final stored = await store.read(key);
      return stored == null ? null : await replayStoredSurface(stored);
    } on Object {
      return null;
    }
  }

  /// The frozen bundled flow baseline for experiment-capable presentation.
  Future<AssetPaywallFlowBaseline?> _experimentBaseline(String id) async {
    final fallback = _assetFallback;
    if (_client == null || fallback is! AssetVariantResolver) return null;
    final preflight = await fallback.preflightFlowBaseline(id);
    return preflight is AssetPaywallFlowBaseline ? preflight : null;
  }

  /// A stored delivery re-gated exactly as a fresh one would be.
  Future<ResolvedPaywallPayload?> _storedPayload(
    SurfaceStoreKey key,
    SurfaceFetchResult stored,
    AssetPaywallFlowBaseline? baseline,
    bool Function() guard,
  ) async {
    final id = key.slug;
    final document = _assembled(stored);
    if (document == null ||
        document.surfaceType != Surface.paywall ||
        document.surfaceSlug != id) {
      return null;
    }
    final identity = await _storedIdentity(stored, id);
    if (!identity.reusable) return null;
    final localKey = identity.key;
    final payload = document.payload;
    if (payload is BlobSurfacePayload) {
      return _storedBlob(id, stored, document, payload, identity.lease);
    }
    if (payload is! FlowSurfacePayload) return null;
    if (baseline != null) {
      final presentation = _RestagePaywallExperimentPresentation.forBaseline(
        owner: this,
        key: key,
        baseline: baseline,
        presentationGuard: guard,
        sendAssignmentKey: true,
        keyDeadline: null,
      );
      final held = await presentation.local(stored, localKey);
      if (held == null) presentation.disposePresentation();
      return held;
    }
    final bundled = await _bundledFlowPayload(id);
    if (bundled == null) return null;
    final arm = _gateActiveFlow(id, stored, payload, document.version, bundled,
        cacheHit: true);
    return arm == null
        ? null
        : stampFlowPayloadForDelivery(
            arm,
            identity.lease!,
          );
  }

  Future<BlobPaywallPayload?> _storedBlobOnly(SurfaceStoreKey key) async {
    final stored = await _readStored(key);
    if (stored == null) return null;
    final document = _assembled(stored);
    if (document == null ||
        document.surfaceType != Surface.paywall ||
        document.surfaceSlug != key.slug) {
      return null;
    }
    final payload = document.payload;
    if (payload is! BlobSurfacePayload) return null;
    final identity = await _storedIdentity(stored, key.slug);
    if (!identity.reusable) return null;
    final blob =
        _storedBlob(key.slug, stored, document, payload, identity.lease);
    return blob == null
        ? null
        : _label(blob, SurfaceResolutionSource.holdLastGood);
  }

  BlobPaywallPayload? _storedBlob(
    String id,
    SurfaceFetchResult stored,
    SurfaceDocument document,
    BlobSurfacePayload payload,
    SurfaceAssignmentResolutionLease? lease,
  ) {
    final verdict = BlobRenderCapabilityGate.evaluate(
      required: CapabilityManifest(
        builtInFloor: document.minClient,
        requiredLibraries: document.requiredLibraries,
      ),
      installed: currentInstalledCapability(),
    );
    if (verdict is BlobRenderRejected) return null;
    return BlobPaywallPayload(
      _hostedVariant(id, document, payload, stored, cacheHit: true),
      assignmentLease: lease,
    );
  }

  Future<
      ({
        bool reusable,
        String? key,
        SurfaceAssignmentResolutionLease? lease
      })> _storedIdentity(
    SurfaceFetchResult stored,
    String id,
  ) =>
      storedDeliveryIdentity(
        stored: stored.stored!,
        assignment: stored.canonicalExperimentAssignment,
        surface: Surface.paywall.wireName,
        slug: id,
      );

  Future<BlobPaywallPayload?> _bundledBlob(
    String id, {
    String? placementId,
    Locale? locale,
  }) async {
    try {
      final variant = await _assetFallback.resolve(
        id,
        placementId: placementId,
        locale: locale,
      );
      return _label(
        BlobPaywallPayload(variant),
        SurfaceResolutionSource.bundled,
      );
    } on RestagePaywallError {
      return null;
    }
  }

  FlowPaywallPayload? _gateActiveFlow(
    String id,
    SurfaceFetchResult result,
    FlowSurfacePayload activePayload,
    int version,
    FlowPaywallPayload bundled, {
    required bool cacheHit,
  }) {
    final arm = resolveFlowActiveArm(
      activePayload: activePayload,
      bundledDocument: bundled.flow.document,
      paywallId: id,
      activeVersion: version,
      publicationBindingReference: result.publicationBindingReference,
      canonicalExperimentAssignment: result.canonicalExperimentAssignment,
      routingSelectionReceipt: result.routingSelectionReceipt,
      routingSelectionProvenance: result.routingSelectionProvenance,
      cacheHit: cacheHit,
    );
    return arm is FlowPaywallActiveAccepted ? arm.payload : null;
  }

  ResolvedVariant _hostedVariant(
    String id,
    SurfaceDocument document,
    BlobSurfacePayload payload,
    SurfaceFetchResult result, {
    required bool cacheHit,
  }) =>
      attachMeasurementPublicationBindingReference(
        attachSurfaceSections(
          ResolvedVariant(
            bytes: payload.blob,
            paywallId: id,
            surfaceVersion: document.version.toString(),
            paywallPublishedVersion: document.version,
            assignment:
                projectSurfaceAssignment(result.canonicalExperimentAssignment),
            cacheHit: cacheHit,
          ),
          surfaceSectionsOf(payload),
        ),
        result.publicationBindingReference,
        canonicalExperimentAssignment: result.canonicalExperimentAssignment,
        routingSelectionReceipt: result.routingSelectionReceipt,
        routingSelectionProvenance: result.routingSelectionProvenance,
      );

  /// Fetches + validates the active hosted version: a renderable blob, a
  /// flow-shaped payload pending the active-arm gate, or a rejection.
  Future<_FreshOutcome> _resolveFresh(
    String id, {
    required bool sendAssignmentKey,
    required Future<void>? keyDeadline,
  }) async {
    final client = _client!;

    // The client contract (built-in catalog version + installed libraries) the
    // server resolves eligibility against.
    final installed = currentInstalledCapability();
    final (assignmentLease, result) = await DeliveryInputBudget.run(
      (budget) async {
        final inputs = await SurfaceRequestInputs.gather(
          budget: budget,
          surface: Surface.paywall.wireName,
          slug: id,
          sendAssignmentKey: sendAssignmentKey,
          keyDeadline: keyDeadline,
        );
        _requireCurrent(inputs.lease);
        return (
          inputs.lease,
          await client.fetchSurface(
            surfaceType: Surface.paywall.wireName,
            surfaceSlug: id,
            inputs: inputs,
            sendAssignmentKey: sendAssignmentKey,
            // version omitted → the delivery service's active-version arm.
          ),
        );
      },
    );
    _requireCurrent(assignmentLease);
    if (result == null) {
      return const _FreshRejected(); // transport failure
    }

    final SurfaceDocument document;
    switch (result.artifact) {
      case SurfaceArtifactAssembled(document: final assembled):
        document = assembled;
      case SurfaceArtifactUnavailable():
        return const _FreshRejected();
      case SurfaceArtifactUndecodable(:final error):
        debugPrint('[restage] hosted paywall "$id" failed to decode: $error');
        return const _FreshRejected(
            reason: SurfaceDeliveryReceiptReason.decodeFailed);
    }

    // The served document must be the paywall asked for; anything else falls
    // through rather than rendering the wrong surface.
    if (document.surfaceType != Surface.paywall || document.surfaceSlug != id) {
      debugPrint(
        '[restage] hosted paywall "$id" served a mismatched surface '
        '(${document.surfaceType.wireName} "${document.surfaceSlug}")',
      );
      return const _FreshRejected(
          reason: SurfaceDeliveryReceiptReason.serverError);
    }

    final payload = document.payload;
    if (payload is BlobSurfacePayload) {
      final gateVerdict = BlobRenderCapabilityGate.evaluate(
        required: CapabilityManifest(
          builtInFloor: document.minClient,
          requiredLibraries: document.requiredLibraries,
        ),
        installed: installed,
      );
      if (gateVerdict is BlobRenderRejected) {
        debugPrint('[restage] hosted paywall "$id" ${gateVerdict.message}');
        return _FreshRejected(
          capabilityGap: gateVerdict.message,
          reason: SurfaceDeliveryReceiptReason.unsupported,
        );
      }
      return _FreshBlob(
        _hostedVariant(id, document, payload, result, cacheHit: false),
        assignmentLease,
        result.stored,
      );
    }

    if (payload is FlowSurfacePayload) {
      return _FreshFlow(payload, document.version, result, assignmentLease);
    }

    debugPrint(
      '[restage] hosted paywall "$id" did not contain a renderable payload',
    );
    return const _FreshRejected(
        reason: SurfaceDeliveryReceiptReason.serverError);
  }

  /// Loads the client's bundled flow paywall via the asset fallback, or null
  /// when there is none: with no flow contract an active flow never renders.
  Future<FlowPaywallPayload?> _bundledFlowPayload(String id) async {
    final fallback = _assetFallback;
    if (fallback is! FlowCapableVariantResolver) return null;
    try {
      final payload =
          await (fallback as FlowCapableVariantResolver).resolvePayload(id);
      return payload is FlowPaywallPayload ? payload : null;
    } on RestagePaywallError {
      return null;
    }
  }

  static void _requireCurrent(SurfaceAssignmentResolutionLease lease) {
    if (!lease.isCurrent) throw const StaleSurfaceAssignmentResolution();
  }

  RestagePaywallError _unavailable(
    String id, [
    String? capabilityGap,
  ]) =>
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

Object _leafOf(ResolvedPaywallPayload payload) => switch (payload) {
      BlobPaywallPayload(:final variant) => variant,
      FlowPaywallPayload(:final flow) => flow,
    };

/// Labels where [payload]'s content came from, on the object it reports as.
T _label<T extends ResolvedPaywallPayload>(
  T payload,
  SurfaceResolutionSource source,
) {
  labelSurfaceSource(_leafOf(payload), source);
  return payload;
}

SurfaceDocument? _assembled(SurfaceFetchResult result) =>
    switch (result.artifact) {
      SurfaceArtifactAssembled(:final document) => document,
      _ => null,
    };

typedef _PresentationFresh = ({FlowPaywallPayload? payload, bool applicable});

/// One experiment-capable flow paywall presentation: its frozen baseline, the
/// mount snapshot, and the hosted candidate chosen against it.
final class _RestagePaywallExperimentPresentation
    implements
        FlowPaywallExperimentRetryAuthority,
        FlowResolver,
        FlowExperimentArtifactMetadataProvider {
  _RestagePaywallExperimentPresentation._({
    required this.owner,
    required this.key,
    required this.flow,
    required this.baseline,
    required this.captureSeed,
    required this.presentationGuard,
    required this.sendAssignmentKey,
    required this.keyDeadline,
  });

  factory _RestagePaywallExperimentPresentation.forBaseline({
    required RestageVariantResolver owner,
    required SurfaceStoreKey key,
    required AssetPaywallFlowBaseline baseline,
    required bool Function() presentationGuard,
    required bool sendAssignmentKey,
    required Future<void>? keyDeadline,
  }) {
    final document = baseline.root.document;
    final flow = OnboardingFlowRef<Object?>(
      id: document.flow,
      version: document.version,
      minClient: document.minClient,
      surface: Surface.paywall,
      deliveryMode: document.deliveryMode,
      decodeResult: _identityPaywallFlowResult,
    );
    final seedSource = FlowMountRuntimeSeedSource(
      flow: flow,
      actions: null,
      installedSignalNames: const <String>{},
    );
    return _RestagePaywallExperimentPresentation._(
      owner: owner,
      key: key,
      flow: flow,
      baseline: baseline,
      captureSeed: seedSource.capture,
      presentationGuard: presentationGuard,
      sendAssignmentKey: sendAssignmentKey,
      keyDeadline: keyDeadline,
    );
  }

  final RestageVariantResolver owner;
  final SurfaceStoreKey key;
  final OnboardingFlowRef<Object?> flow;
  final AssetPaywallFlowBaseline baseline;
  final FlowMountSeedCapture captureSeed;
  final bool Function() presentationGuard;
  final bool sendAssignmentKey;
  final Future<void>? keyDeadline;

  String get paywallId => key.slug;

  FlowMountContractSnapshot? _snapshot;
  bool _published = false;
  bool _disposed = false;
  bool _localOnly = false;
  var _attempts = 0;
  final List<(SurfaceStoreKey, StoredSurface)> _children =
      <(SurfaceStoreKey, StoredSurface)>[];

  /// Fetches, gates and persists the hosted candidate. Not applicable when the
  /// baseline cannot advertise an experiment; the caller then takes the plain
  /// path.
  Future<_PresentationFresh> fresh() async {
    // Three hosted attempts per presentation, shared with first-paint retries.
    while (_attempts < 3) {
      _attempts += 1;
      if (_disposed || !presentationGuard()) {
        throw const StaleSurfaceAssignmentResolution();
      }
      _snapshot = null;
      _children.clear();
      try {
        SurfaceAssignmentResolutionLease? registrationLease;
        final snapshotOutcome = await FlowMountContractSnapshotBuilder(
          captureSeed: captureSeed,
          resolveAssignmentKey: () async {
            registrationLease = await SurfaceAssignmentKeyProvider.captureLease(
              resolveKey: sendAssignmentKey,
              keyDeadline: keyDeadline,
            );
            return registrationLease!.assignmentKey;
          },
          resolver: baseline,
        ).seal();
        if (_disposed || !presentationGuard()) {
          throw const StaleSurfaceAssignmentResolution();
        }
        if (snapshotOutcome is FlowMountSnapshotRejected) {
          if (snapshotOutcome.reason == FlowMountSnapshotRejection.seedDrift) {
            continue;
          }
          return (payload: null, applicable: false);
        }
        var snapshot = (snapshotOutcome as FlowMountSnapshotSealed).snapshot;
        if (!_baselineCanAdvertise(snapshot)) {
          return (payload: null, applicable: false);
        }
        _snapshot = snapshot;

        final fetched = await _fetchActive(snapshot, registrationLease!);
        if (_disposed || !presentationGuard()) {
          throw const StaleSurfaceAssignmentResolution();
        }
        if (fetched == null) {
          owner._raced.freshRefused(key, SurfaceDeliveryReceiptReason.offline);
          return (payload: null, applicable: true);
        }
        snapshot = snapshot.withAssignmentKey(fetched.result.stored == null
            ? registrationLease!.assignmentKey
            : storedSurfaceAssignmentKey(fetched.result.stored!));
        _snapshot = snapshot;
        final candidate = _candidateFrom(fetched.result, fetched.decoded);
        final prefetched = await FlowCandidatePrefetcher.prefetch(
          snapshot: snapshot,
          captureSeed: captureSeed,
          candidateRoot: candidate,
          resolver: this,
        );
        if (_disposed || !presentationGuard()) {
          throw const StaleSurfaceAssignmentResolution();
        }
        if (prefetched is FlowCandidatePrefetchAccepted) {
          await owner._persist(key, fetched.result.stored);
          for (final (childKey, stored) in _children) {
            await owner._persist(childKey, stored);
          }
          _children.clear();
          return (
            payload: _label(
              FlowPaywallPayload.experiment(
                acceptedCandidate: prefetched,
                paywallId: paywallId,
                paywallPublishedVersion: fetched.decoded.publishedVersion,
                resolvedFromActiveArm: true,
                experimentAuthority: this,
              ),
              SurfaceResolutionSource.fresh,
            ),
            applicable: true,
          );
        }
        if ((prefetched is FlowCandidatePrefetchRejected &&
                prefetched.reason ==
                    FlowCandidatePrefetchRejection.seedDrift) ||
            !revalidate(FlowMountRevalidationBoundary.fallback)) {
          continue;
        }
        owner._raced
            .freshRefused(key, SurfaceDeliveryReceiptReason.unsupported);
        return (payload: null, applicable: true);
      } on StaleSurfaceAssignmentResolution {
        if (_disposed || !presentationGuard()) rethrow;
      }
    }
    owner._raced.freshRefused(key, SurfaceDeliveryReceiptReason.offline);
    return (payload: null, applicable: true);
  }

  /// Re-derives a stored candidate against the current snapshot, reading its
  /// sub-flows from the store only.
  Future<FlowPaywallPayload?> local(
    SurfaceFetchResult stored,
    String? assignmentKey,
  ) async {
    _localOnly = true;
    final snapshotOutcome = await FlowMountContractSnapshotBuilder(
      captureSeed: captureSeed,
      resolveAssignmentKey: () => assignmentKey,
      resolver: baseline,
    ).seal();
    if (_disposed || snapshotOutcome is! FlowMountSnapshotSealed) return null;
    final snapshot = snapshotOutcome.snapshot;
    if (!_baselineCanAdvertise(snapshot)) return null;
    _snapshot = snapshot;
    final decoded = _decodeHostedFlow(
      stored,
      requestedFlow: flow,
      exactVersion: false,
    );
    if (decoded == null) return null;
    final prefetched = await FlowCandidatePrefetcher.prefetch(
      snapshot: snapshot,
      captureSeed: captureSeed,
      candidateRoot: _candidateFrom(stored, decoded, cacheHit: true),
      resolver: this,
    );
    if (_disposed || prefetched is! FlowCandidatePrefetchAccepted) return null;
    return FlowPaywallPayload.experiment(
      acceptedCandidate: prefetched.asCacheHit(),
      paywallId: paywallId,
      paywallPublishedVersion: decoded.publishedVersion,
      resolvedFromActiveArm: true,
      experimentAuthority: this,
    );
  }

  @override
  Future<FlowPaywallPayload?> resolveNextPayload() async {
    _localOnly = false;
    final outcome = await fresh();
    if (!outcome.applicable) return null;
    return outcome.payload ??
        FlowPaywallPayload.experimentBaseline(
          flow: baseline.root,
          pinnedFlowResolver: baseline,
          paywallId: paywallId,
        );
  }

  bool _baselineCanAdvertise(FlowMountContractSnapshot snapshot) {
    final verdict = FlowExperimentEligibilityEvaluator.evaluate(
      FlowExperimentVerdictInput(
        clientBaselineClosure: snapshot.clientBaselineClosure,
        candidateArmClosure: snapshot.clientBaselineClosure,
        installedCapability: snapshot.seed.installedCapability,
        actionBindings: snapshot.seed.actionBindings,
        installedSignals: snapshot.seed.installedSignals,
        surfaceType: Surface.paywall,
        deliveryMode: snapshot.seed.deliveryMode,
        flowGateRevision: kFlowExperimentGateLogicRevisionV1,
      ),
    );
    return verdict.accepted;
  }

  ResolvedFlow _candidateFrom(
    SurfaceFetchResult result,
    _DecodedPaywallHostedFlow decoded, {
    bool cacheHit = false,
  }) =>
      _own(
        attachMeasurementPublicationBindingReference(
          attachSurfaceSections(
            ResolvedFlow(
              document: decoded.document,
              screenBlobs: decoded.screenBlobs,
              contentHash: FlowContentHash.compute(
                FlowDocumentCodec.encodeCanonicalJson(decoded.document),
              ),
              cacheHit: cacheHit,
            ),
            decoded.sections,
          ),
          result.publicationBindingReference,
          canonicalExperimentAssignment: result.canonicalExperimentAssignment,
          routingSelectionReceipt: result.routingSelectionReceipt,
          routingSelectionProvenance: result.routingSelectionProvenance,
        ),
        requiredLibraries: decoded.requiredLibraries,
      );

  Future<({SurfaceFetchResult result, _DecodedPaywallHostedFlow decoded})?>
      _fetchActive(FlowMountContractSnapshot snapshot,
          SurfaceAssignmentResolutionLease registrationLease) async {
    _requireCurrent(snapshot, FlowMountRevalidationBoundary.request);
    final SurfaceFetchResult? result;
    try {
      result = await owner._client!.fetchSurface(
        surfaceType: Surface.paywall.wireName,
        surfaceSlug: paywallId,
        assignmentKey: snapshot.assignmentKey,
        sendAssignmentKey: sendAssignmentKey,
        registrationLease: registrationLease,
        keyDeadline: keyDeadline,
        publicationGuard: () => _snapshotIsCurrent(
          snapshot,
          FlowMountRevalidationBoundary.request,
        ),
      );
    } on SurfaceRequestPublicationRejected {
      throw const StaleSurfaceAssignmentResolution();
    }
    _requireCurrent(snapshot, FlowMountRevalidationBoundary.request);
    if (result == null) return null;
    final decoded = _decodeHostedFlow(
      result,
      requestedFlow: flow,
      exactVersion: false,
    );
    return decoded == null ? null : (result: result, decoded: decoded);
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
    final childKey = SurfaceStoreKey(
      scope: key.scope,
      surfaceType: Surface.paywall.wireName,
      slug: requestedFlow.id,
      contractVersion: requestedFlow.version,
    );
    final SurfaceFetchResult? result;
    if (_localOnly) {
      result = await owner._readStored(childKey);
    } else {
      _requireCurrent(
          snapshot, FlowMountRevalidationBoundary.candidatePrefetch);
      try {
        result = await owner._client!.fetchSurface(
          surfaceType: Surface.paywall.wireName,
          surfaceSlug: requestedFlow.id,
          version: requestedFlow.version,
          sendAssignmentKey: snapshot.assignmentKey != null,
          keyDeadline: keyDeadline,
          publicationGuard: () => _snapshotIsCurrent(
            snapshot,
            FlowMountRevalidationBoundary.candidatePrefetch,
          ),
        );
      } on SurfaceRequestPublicationRejected {
        throw const StaleSurfaceAssignmentResolution();
      }
      _requireCurrent(
          snapshot, FlowMountRevalidationBoundary.candidatePrefetch);
    }
    if (result == null) {
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
    final stored = result.stored;
    if (!_localOnly && stored != null) _children.add((childKey, stored));
    return _candidateFrom(result, decoded, cacheHit: _localOnly);
  }

  _DecodedPaywallHostedFlow? _decodeHostedFlow<R>(
    SurfaceFetchResult result, {
    required OnboardingFlowRef<R> requestedFlow,
    required bool exactVersion,
  }) {
    final surface = _assembled(result);
    if (surface == null ||
        surface.surfaceType != Surface.paywall ||
        surface.surfaceSlug != requestedFlow.id ||
        (exactVersion && surface.version != requestedFlow.version)) {
      return null;
    }
    final payload = surface.payload;
    if (payload is! FlowSurfacePayload) return null;
    final document = payload.flowDocument;
    if (document.flow != requestedFlow.id ||
        (exactVersion && document.version != requestedFlow.version) ||
        (document.schemaVersion != 1 && document.schemaVersion != 2) ||
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
      sections: surfaceSectionsOf(payload),
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

  // Accepted candidates persist when accepted, so render commitment only
  // releases the host guard.
  @override
  void publishHostedLastGood() {
    if (revalidate(FlowMountRevalidationBoundary.cachePublication)) {
      _published = true;
    }
  }

  @override
  void abandonHostedLastGood() {}

  @override
  void disposePresentation() {
    _disposed = true;
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

final class _DecodedPaywallHostedFlow {
  const _DecodedPaywallHostedFlow({
    required this.document,
    required this.screenBlobs,
    required this.requiredLibraries,
    required this.publishedVersion,
    required this.sections,
  });

  final SurfaceSections sections;
  final FlowDocument document;
  final Map<String, Uint8List> screenBlobs;
  final List<LibraryRequirement> requiredLibraries;
  final int publishedVersion;
}

Map<String, Object?> _identityPaywallFlowResult(Map<String, Object?> value) =>
    value;

/// Outcome of a fresh hosted fetch: a renderable blob, a flow-shaped payload
/// pending the active-arm gate, or a rejection.
sealed class _FreshOutcome {
  const _FreshOutcome();
}

final class _FreshBlob extends _FreshOutcome {
  const _FreshBlob(this.variant, this.assignmentLease, this.stored);

  final ResolvedVariant variant;
  final SurfaceAssignmentResolutionLease assignmentLease;
  final StoredSurface? stored;

  BlobPaywallPayload payload() =>
      BlobPaywallPayload(variant, assignmentLease: assignmentLease);
}

final class _FreshFlow extends _FreshOutcome {
  const _FreshFlow(
    this.activePayload,
    this.version,
    this.result,
    this.assignmentLease,
  );

  final FlowSurfacePayload activePayload;
  final int version;
  final SurfaceFetchResult result;
  final SurfaceAssignmentResolutionLease assignmentLease;
}

final class _FreshRejected extends _FreshOutcome {
  const _FreshRejected({
    this.capabilityGap,
    this.reason = SurfaceDeliveryReceiptReason.offline,
  });

  /// Why the fresh copy was not served.
  final SurfaceDeliveryReceiptReason reason;

  /// A short phrase naming a capability gap, when that was the reason.
  final String? capabilityGap;
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

/// Local environment hint passed to `Restage.configure` and resolvers.
/// Hosted authorization and metering use the environment bound to the API key;
/// this hint and the key's readable environment label do not select it.
enum RestageEnvironment {
  /// Sandbox hint, commonly used with `rs_pk_sandbox_…` keys.
  sandbox,

  /// Production hint, commonly used with `rs_pk_live_…` keys.
  production,
}
