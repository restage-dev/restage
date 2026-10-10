import 'dart:ui' show Locale;
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:rfw/rfw.dart' as rfw;

import '../delivery/raced_surface_resolver.dart';
import '../delivery/surface_artifact_store.dart';
import '../delivery/surface_sections_carrier.dart';
import '../flow/flow_descriptors.dart';
import '../flow/flow_resolver.dart';
import '../restage_rpc_client/placement_delivery_adapter.dart';
import '../runtime/installed_widget_vocabulary.dart';
import '../runtime/placement_registry.dart';
import '../refresh/surface_update_channel.dart';
import '../runtime/paywall_error.dart';
import '../runtime/placement_presentation.dart';
import '../measurement/placement_mount_attribution.dart';
import '../measurement/measurement_resolved_publication_provenance.dart';
import '../surface_screen/surface_screen_types.dart';
import 'resolved_paywall_payload.dart';
import 'resolved_variant.dart';
import 'surface_resolution_report.dart';
import 'variant_resolver.dart';

/// The existing host race's key for one captured placement declaration.
@internal
abstract interface class PlacementBoundResolver {
  SurfaceStoreKey get storeKey;
  PlacementDeliveryAdmission? get currentAdmission;
  PlacementFallbackWatch? get currentFallback;
}

/// A watched fallback decision, kept until the mount accepts a delivery.
@internal
final class PlacementFallbackWatch {
  PlacementFallbackWatch(this.decision, this.watch);
  final PlacementBatchUseFallbackV1 decision;
  final PlacementDeliveryWatchV1 watch;

  PlacementRefreshStateV1 get refreshState => (
        mount: decision.descriptor,
        decisionIdentityDigest: watch.decisionIdentityDigest,
        dependencies: {decision.fallbackWatchScope},
      );
}

/// The live watch of a placement host currently rendering its fallback.
@internal
PlacementFallbackWatch? placementFallbackFor(Object? resolver) =>
    resolver is PlacementBoundResolver ? resolver.currentFallback : null;

/// Probes the accepted delivery, else the watched fallback of [resolver].
@internal
Future<PlacementRefreshProbeV1> probeRenderedPlacement(
        PlacementDeliveryAdmission? accepted,
        Object? resolver,
        PlacementRefreshStateV1 rendered) =>
    accepted != null
        ? accepted.probe(rendered)
        : resolver is PlacementMountResolver
            ? resolver.probeFallback(rendered)
            : Future.value(const PlacementRefreshProbeV1.unavailable());

final _placementAdmissions = Expando<PlacementDeliveryAdmission>();

@internal
T copyPlacementAdmission<T extends Object>(Object original, T copy) {
  _placementAdmissions[copy] = placementAdmissionFor(original);
  return copy;
}

@internal
PlacementDeliveryAdmission? placementAdmissionFor(Object resolved) =>
    _placementAdmissions[resolved];

/// Verified selected identity and fit, retained by its original host.
@internal
final class PlacementDeliveryAdmission {
  PlacementDeliveryAdmission(
      {required this.decision,
      required this.context,
      required this.host,
      required this.registry,
      required this.document});
  final PlacementBatchAvailableV1 decision;
  final PlacementRequestContext context;
  final SurfaceHostContractV1 host;
  final PlacementRegistry registry;
  final SurfaceDocument document;

  PublicPlacementDeliveryV1 get delivery => decision.publicDelivery;
  bool get isAssigned => delivery.assignment != null;

  PlacementRefreshStateV1? get refreshState {
    final watch = decision.watch;
    return watch == null
        ? null
        : (
            mount: decision.descriptor,
            decisionIdentityDigest: watch.decisionIdentityDigest,
            dependencies: delivery.dependencyClosure,
          );
  }

  SurfaceRef get renderedSurface => SurfaceRef(
      surfaceType: document.surfaceType.wireName, slug: document.surfaceSlug);

  Future<void> invalidateCache() => registry.decisions.removeAccepted(
      registry.decisions.decisionKey(
          context.request, context.request.mounts.single, context.inputStamp,
          target: decision.descriptor.placement.target),
      decision);

  Future<PlacementRefreshProbeV1> probe(PlacementRefreshStateV1 rendered) =>
      registry.probe(this, rendered);

  bool matchesDecision(PlacementDeliveryAdmission? other) =>
      other != null &&
      delivery.publicProjectionDigest ==
          other.delivery.publicProjectionDigest &&
      decision.watch?.decisionIdentityDigest ==
          other.decision.watch?.decisionIdentityDigest;

  bool get isCurrent =>
      placementHostIsCurrent(host) &&
      context.isCurrent() &&
      registry.target == decision.descriptor.placement.target &&
      currentInstalledCapability().contentHash ==
          context.request.buildContract.installedCapabilityHash &&
      registry.now().toUtc().compareTo(context.capturedAt) >= 0 &&
      placementCacheIsValid(delivery.cacheValidity,
          now: registry.now(), clock: context.request.localClock);

  DateTime? get nextBoundary {
    final validity = delivery.cacheValidity;
    final candidates = <DateTime>[
      for (final micros in [
        validity.receiptExpiresAtMicros,
        validity.assignmentExpiresAtMicros,
        validity.contentExpiresAtMicros
      ])
        if (micros != null)
          DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true),
      if (validity.expiresBeforeLocal case final end?)
        DateTime.utc(
                end.year, end.month, end.day, end.hour, end.minute, end.second)
            .subtract(Duration(
                minutes: context.request.localClock!.utcOffsetMinutes)),
    ]..sort();
    return candidates.isEmpty ? null : candidates.first;
  }
}

/// Tests returned bounds only; no audience or policy is evaluated locally.
@internal
bool placementCacheIsValid(DeliveryCacheValidityV1 validity,
    {required DateTime now, required DeliveryLocalClockV1? clock}) {
  final utc = now.toUtc().microsecondsSinceEpoch;
  if ([
    validity.receiptExpiresAtMicros,
    validity.assignmentExpiresAtMicros,
    validity.contentExpiresAtMicros
  ].any((expiry) => expiry != null && utc >= expiry)) {
    return false;
  }
  if (validity.notBeforeLocal == null && validity.expiresBeforeLocal == null) {
    return true;
  }
  if (clock == null || clock.utcOffsetMinutes != now.timeZoneOffset.inMinutes) {
    return false;
  }
  final civil = clock.localNow(nowMicros: utc);
  return (validity.notBeforeLocal == null ||
          civil.compareTo(validity.notBeforeLocal!) >= 0) &&
      (validity.expiresBeforeLocal == null ||
          civil.compareTo(validity.expiresBeforeLocal!) < 0);
}

/// Maps qualified batch content into the existing host's result and race.
@internal
abstract class PlacementMountResolver<T extends Object>
    with RacedSurfaceReporting<T>
    implements RacedSurfaceResolver<T>, PlacementBoundResolver {
  PlacementMountResolver({required this.registry, required this.declaration}) {
    registry.remember(declaration);
  }
  final PlacementRegistry registry;
  final PlacementDeclaration declaration;
  @override
  PlacementDeliveryAdmission? currentAdmission;
  @override
  PlacementFallbackWatch? currentFallback;

  /// Called when a fresh fallback decision changes the watched fallback.
  void Function()? onFallbackChanged;

  @override
  SurfaceStoreKey get storeKey =>
      registry.decisions.mountKey(declaration.mount);
  @override
  SurfaceArtifactStore get store => sharedSurfaceArtifactStore;
  @override
  Surface reportSurfaceFor(SurfaceStoreKey key) =>
      Surface.fromWireName(currentAdmission?.document.surfaceType.wireName ??
          declaration.mount.defaultSurface?.surfaceType.value ??
          'paywall');

  @override
  Object reportedLeafOf(T winner) => placementResolvedLeaf(winner);
  @override
  String reportSlugFor(SurfaceStoreKey key, T winner) =>
      placementAdmissionFor(winner)?.document.surfaceSlug ??
      declaration.mount.defaultSurface?.slug ??
      key.slug;

  Future<T?> original();
  T? convert(PlacementDeliveryAdmission admission,
      PlacementDeliveryArtifacts artifacts,
      {required bool cacheHit});

  T? _accept(PlacementBatchAvailableV1 entry,
      PlacementDeliveryArtifacts artifacts, PlacementRequestContext context,
      {required bool cacheHit}) {
    final admission = PlacementDeliveryAdmission(
        decision: entry,
        context: context,
        host: declaration.host,
        registry: registry,
        document:
            artifacts.publications[entry.publicDelivery.actualPublication]!);
    if (!admission.isCurrent ||
        (admission.isAssigned &&
            (!context.lease.assignmentsAllowed ||
                context.lease.assignmentKey == null ||
                (!cacheHit &&
                    context.request.assignmentKey !=
                        context.lease.assignmentKey))) ||
        !SurfaceFitEvaluator.evaluate(
                host: declaration.host,
                requirement: entry.publicDelivery.fitRequirement,
                installed: context.request.buildContract.installedCapability)
            .accepted) {
      return null;
    }
    for (final reference in entry.artifactClosure) {
      final publication = artifacts.documents[reference]!;
      final verdict = BlobRenderCapabilityGate.evaluate(
          required: CapabilityManifest(
              builtInFloor: publication.minClient,
              requiredLibraries: publication.requiredLibraries),
          installed: context.request.buildContract.installedCapability);
      if (verdict is BlobRenderRejected) return null;
    }
    final resolved = convert(admission, artifacts, cacheHit: cacheHit);
    if (resolved == null) return null;
    _placementAdmissions[resolved] = admission;
    attachSurfaceAssignmentLease(resolved, context.lease);
    attachResolvedPlacementDelivery(resolved, entry.publicDelivery,
        selectedDocument: admission.document);
    final leaf = placementResolvedLeaf(resolved);
    attachMeasurementPublicationBindingReference(
        leaf, entry.publicDelivery.actualPublication.publicationBindingRef,
        routingSelectionReceipt: entry.publicDelivery.routingSelectionReceipt,
        registrationFingerprint: admission.isAssigned
            ? context.lease.registration?.fingerprint
            : null);
    currentAdmission = admission;
    currentFallback = null;
    labelSurfaceSource(
        leaf,
        cacheHit
            ? SurfaceResolutionSource.holdLastGood
            : SurfaceResolutionSource.fresh);
    return labelSurfaceSource(
        resolved,
        cacheHit
            ? SurfaceResolutionSource.holdLastGood
            : SurfaceResolutionSource.fresh);
  }

  /// Checks the watched fallback through the side-effect-free refresh route.
  Future<PlacementRefreshProbeV1> probeFallback(
      PlacementRefreshStateV1 rendered) async {
    final fallback = currentFallback;
    if (fallback == null ||
        fallback.watch.decisionIdentityDigest !=
            rendered.decisionIdentityDigest) {
      return const PlacementRefreshProbeV1.requiresResolution();
    }
    final context = await registry.capture(
        mounts: [declaration.mount],
        sendAssignmentKey: false,
        mode: PlacementBatchModeV1.refresh,
        publicationGuard: () => placementHostIsCurrent(declaration.host));
    if (context == null) return const PlacementRefreshProbeV1.unavailable();
    Duration? retryAfter;
    final response = await registry.client().fetchPlacements(context.request,
        publicationGuard: context.isCurrent,
        registrationLease: context.lease,
        expectedTarget: fallback.decision.descriptor.placement.target,
        onRateLimited: (delay) => retryAfter = delay);
    if (retryAfter != null) {
      return PlacementRefreshProbeV1.rateLimited(retryAfter!);
    }
    final entry = response is PlacementBatchResolvedV1 && context.isCurrent()
        ? response.decisions.single
        : null;
    final watch = entry is PlacementBatchUseFallbackV1 ? entry.watch : null;
    return watch == null
        ? const PlacementRefreshProbeV1.requiresResolution()
        : PlacementRefreshProbeV1.unchanged(watch.decisionIdentityDigest,
            watch: watch);
  }

  @override
  Future<T?> fresh(SurfaceStoreKey key,
      {required bool sendAssignmentKey, Future<void>? keyDeadline}) async {
    final context = await registry.capture(
        mounts: [declaration.mount],
        sendAssignmentKey: sendAssignmentKey,
        keyDeadline: keyDeadline,
        publicationGuard: () => placementHostIsCurrent(declaration.host));
    if (context == null) return null;
    final fetched = await registry.fetch(context);
    if (fetched == null) return null;
    final entry = fetched.response.decisions.single;
    if (entry is PlacementBatchUseFallbackV1) {
      final watch = entry.watch;
      final previous = currentFallback?.watch;
      currentFallback =
          watch == null ? null : PlacementFallbackWatch(entry, watch);
      // A renewed token resubscribes even when the decision is unchanged.
      if (watch != previous) onFallbackChanged?.call();
    }
    return entry is PlacementBatchAvailableV1
        ? _accept(entry, fetched.artifacts, context, cacheHit: false)
        : null;
  }

  @override
  Future<T?> bestLocal(SurfaceStoreKey key) async {
    final context = await registry.capture(
        mounts: [declaration.mount],
        sendAssignmentKey: false,
        publicationGuard: () => placementHostIsCurrent(declaration.host));
    if (context != null) {
      final local = await registry.local(context);
      if (local != null) {
        final resolved = _accept(local.decision, local.artifacts, local.context,
            cacheHit: true);
        if (resolved != null) return resolved;
      }
    }
    currentAdmission = null;
    return original();
  }

  @override
  Future<void> forgetStored(SurfaceStoreKey key) async {
    final context = await registry.capture(
        mounts: [declaration.mount],
        sendAssignmentKey: false,
        publicationGuard: () => placementHostIsCurrent(declaration.host));
    if (context != null && registry.target != null) {
      await registry.decisions.remove(registry.decisions.decisionKey(
          context.request, declaration.mount, context.inputStamp,
          target: registry.target!));
    }
  }

  SurfaceDocument root(PlacementDeliveryAdmission admission,
          PlacementDeliveryArtifacts artifacts) =>
      artifacts.publications[admission.delivery.actualPublication]!;
}

/// One verified single surface with its actual publication and family.
@internal
final class PlacementSingleSurface {
  PlacementSingleSurface(this.document, this.admission);
  final SurfaceDocument document;
  final PlacementDeliveryAdmission admission;
  BlobSurfacePayload get payload => document.payload as BlobSurfacePayload;
}

/// Render fields shared by the typed result and normalized placement content.
@internal
final class SingleSurfaceRenderContent {
  SingleSurfaceRenderContent._(
      {required this.blob,
      required this.capabilities,
      required this.contentHash,
      required this.version,
      required this.surface,
      required this.slug});
  factory SingleSurfaceRenderContent.fromResolved(Object resolved) {
    if (resolved is ResolvedSurfaceScreen) {
      return SingleSurfaceRenderContent._(
          blob: resolved.blob,
          capabilities: resolved.capabilities,
          contentHash: resolved.contentHash,
          version: (resolved.publishedRevision ?? resolved.contractVersion)
              .toString(),
          surface: resolved.surface,
          slug: resolved.slug);
    }
    final single = resolved as PlacementSingleSurface;
    return SingleSurfaceRenderContent._(
        blob: single.payload.blob,
        capabilities: CapabilityManifest(
            builtInFloor: single.document.minClient,
            requiredLibraries: single.document.requiredLibraries),
        contentHash: single.payload.contentHash,
        version: single.document.version.toString(),
        surface: single.document.surfaceType,
        slug: single.document.surfaceSlug);
  }
  final Uint8List blob;
  final CapabilityManifest capabilities;
  final String contentHash;
  final String version;
  final Surface surface;
  final String slug;
}

@internal
String placementRootWidgetFor(Object resolved, String original) {
  final admission = placementAdmissionFor(resolved);
  final payload = surfacePayloadFor(resolved);
  if (admission == null || payload is! BlobSurfacePayload) return original;
  final library = rfw.decodeLibraryBlob(payload.blob);
  final expected = admission.document.surfaceType.wireName == 'paywall'
      ? 'Paywall'
      : 'OnboardingScreen';
  if (library.widgets.any((widget) => widget.name == expected)) return expected;
  if (library.widgets.length == 1) return library.widgets.single.name;
  throw const FormatException(
      'The selected surface has no recognized root widget.');
}

@internal
rfw.FullyQualifiedWidgetName placementWidgetNameFor(
        Object resolved, rfw.FullyQualifiedWidgetName original) =>
    rfw.FullyQualifiedWidgetName(
        original.library, placementRootWidgetFor(resolved, original.widget));

@internal
final class PlacementScreenResolver extends PlacementMountResolver<Object>
    implements SurfaceScreenResolver {
  PlacementScreenResolver(
      {required super.registry,
      required super.declaration,
      required this.screen,
      required this.originalResolver});
  final SurfaceScreenRef<Object?> screen;
  final BundledSurfaceScreenResolver originalResolver;
  @override
  Future<Object?> original() async {
    if (declaration.mount.defaultSurface == null) return null;
    try {
      return await originalResolver.resolve(screen);
    } on Object {
      return null;
    }
  }

  @override
  Future<ResolvedSurfaceScreen> resolve<E>(SurfaceScreenRef<E> screen) =>
      originalResolver.resolve(screen);
  @override
  Object? convert(PlacementDeliveryAdmission admission,
      PlacementDeliveryArtifacts artifacts,
      {required bool cacheHit}) {
    final document = root(admission, artifacts);
    if (document.payload is! BlobSurfacePayload) return null;
    return attachSurfacePayload(
        PlacementSingleSurface(document, admission), document.payload);
  }
}

@internal
final class PlacementFlowResolver extends PlacementMountResolver<ResolvedFlow>
    implements FlowResolver, ActiveArmFlowResolver {
  PlacementFlowResolver(
      {required super.registry,
      required super.declaration,
      required this.flow,
      required this.originalResolver});
  final SurfaceFlowRef<Object?> flow;
  final FlowResolver originalResolver;
  Map<PlacementArtifactReferenceV1, SurfaceDocument> _closure = const {};
  @override
  bool get activeArmEnabled => true;
  @override
  Future<ResolvedFlow> resolveActiveRoot<R>(OnboardingFlowRef<R> flow) async =>
      await fresh(storeKey, sendAssignmentKey: true) ??
      await bestLocal(storeKey) ??
      (throw FlowUnavailableError(
          flowId: flow.id,
          flowVersion: flow.version,
          reason: 'placement_unavailable',
          message: 'No placement content is available.'));
  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> child) async {
    for (final document in _closure.values) {
      final payload = document.payload;
      if (payload is FlowSurfacePayload &&
          document.surfaceSlug == child.id &&
          payload.flowDocument.flow == child.id &&
          payload.flowDocument.version == child.version) {
        return _flow(document, cacheHit: false);
      }
    }
    if (_closure.isNotEmpty) {
      throw FlowUnavailableError(
          flowId: child.id,
          flowVersion: child.version,
          reason: 'placement_closure_unavailable',
          message: 'The exact child is absent from this placement closure.');
    }
    return originalResolver.resolve(child);
  }

  @override
  Future<ResolvedFlow?> original() async {
    _closure = const {};
    if (declaration.mount.defaultSurface == null) return null;
    try {
      return await originalResolver.resolve(flow);
    } on Object {
      return null;
    }
  }

  @override
  ResolvedFlow? convert(PlacementDeliveryAdmission admission,
      PlacementDeliveryArtifacts artifacts,
      {required bool cacheHit}) {
    final document = root(admission, artifacts);
    if (document.payload is! FlowSurfacePayload) return null;
    _closure = Map.unmodifiable({
      for (final reference in admission.decision.artifactClosure)
        reference: artifacts.documents[reference]!,
    });
    return _flow(document, cacheHit: cacheHit);
  }

  ResolvedFlow _flow(SurfaceDocument document, {required bool cacheHit}) {
    final payload = document.payload as FlowSurfacePayload;
    return attachSurfacePayload(
        ResolvedFlow(
            document: payload.flowDocument,
            screenBlobs: payload.screenBlobs,
            contentHash: FlowContentHash.compute(
                FlowDocumentCodec.encodeCanonicalJson(payload.flowDocument)),
            cacheHit: cacheHit),
        payload);
  }
}

@internal
final class PlacementPaywallResolver
    extends PlacementMountResolver<ResolvedPaywallPayload>
    implements VariantResolver, FlowCapableVariantResolver {
  PlacementPaywallResolver(
      {required super.registry,
      required super.declaration,
      required this.id,
      required this.originalResolver});
  final String id;
  final VariantResolver originalResolver;
  @override
  Future<ResolvedPaywallPayload?> original() async {
    if (declaration.mount.defaultSurface == null) return null;
    try {
      final resolver = originalResolver;
      return resolver is FlowCapableVariantResolver
          ? await (resolver as FlowCapableVariantResolver).resolvePayload(id)
          : BlobPaywallPayload(await resolver.resolve(id));
    } on Object {
      return null;
    }
  }

  @override
  Future<ResolvedVariant> resolve(String id,
      {String? placementId, Locale? locale}) async {
    final payload =
        await resolvePayload(id, placementId: placementId, locale: locale);
    if (payload is BlobPaywallPayload) return payload.variant;
    throw StateError('The placement contains a flow.');
  }

  @override
  Future<ResolvedPaywallPayload> resolvePayload(String id,
          {String? placementId, Locale? locale}) async =>
      await fresh(storeKey, sendAssignmentKey: true) ??
      await bestLocal(storeKey) ??
      (throw StateError('No placement content is available.'));
  @override
  ResolvedPaywallPayload? convert(PlacementDeliveryAdmission admission,
      PlacementDeliveryArtifacts artifacts,
      {required bool cacheHit}) {
    final document = root(admission, artifacts);
    final payload = document.payload;
    if (payload is BlobSurfacePayload) {
      final variant = attachSurfacePayload(
          ResolvedVariant(
              bytes: payload.blob,
              paywallId: document.surfaceSlug,
              surfaceVersion: payload.contentHash,
              paywallPublishedVersion: document.version,
              cacheHit: cacheHit),
          payload);
      _placementAdmissions[variant] = admission;
      attachSurfaceAssignmentLease(variant, admission.context.lease);
      return BlobPaywallPayload(variant,
          assignmentLease: admission.context.lease);
    }
    final resolver = PlacementFlowResolver(
        registry: registry,
        declaration: declaration,
        flow: SurfaceFlowRef<Map<String, Object?>>(
            id: document.surfaceSlug,
            version: document.version,
            minClient: document.minClient,
            surface: document.surfaceType,
            decodeResult: (value) => value),
        originalResolver: const AssetFlowResolver());
    final flow = resolver.convert(admission, artifacts, cacheHit: cacheHit);
    if (flow == null) return null;
    _placementAdmissions[flow] = admission;
    attachSurfaceAssignmentLease(flow, admission.context.lease);
    return FlowPaywallPayload.experimentBaseline(
        flow: flow,
        pinnedFlowResolver: resolver,
        paywallId: document.surfaceSlug,
        paywallPublishedVersion: document.version,
        resolvedFromActiveArm: true,
        assignmentLease: admission.context.lease);
  }
}

/// A low-level mount has no implicit bundled publication.
@internal
final class UnavailablePlacementPaywallResolver implements VariantResolver {
  const UnavailablePlacementPaywallResolver();
  @override
  Future<ResolvedVariant> resolve(String id,
          {String? placementId, Locale? locale}) async =>
      throw RestagePaywallError(
          code: RestageErrorCodes.deliveryUnavailable,
          message: 'No configured placement content is available.');
}

@internal
final class UnavailablePlacementFlowResolver implements FlowResolver {
  const UnavailablePlacementFlowResolver();
  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> flow) async =>
      throw FlowUnavailableError(
          flowId: flow.id,
          flowVersion: flow.version,
          reason: 'placement_unavailable',
          message: 'No configured placement content is available.');
}
