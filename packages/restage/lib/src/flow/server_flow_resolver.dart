import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show AssetBundle;
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart'
    show
        CanonicalSurfaceExperimentAssignmentV1,
        SurfaceRoutingSelectionProvenanceV1,
        FlowActiveRenderGate,
        FlowContentHash,
        FlowDeliveryMode,
        FlowDocument,
        FlowDocumentCodec,
        FlowDocumentValidation,
        FlowSurfacePayload,
        GeneralFlowRenderGate,
        LibraryRequirement,
        SurfaceDocument,
        Surface;

import '../delivery/surface_sections_carrier.dart';
import '../runtime/local_values.dart' show SurfaceSections;
import '../delivery/raced_surface_resolver.dart';
import '../delivery/surface_artifact_store.dart';
import '../delivery/surface_delivery_receipt.dart';
import '../assets/bundled_asset_source.dart';
import '../measurement/measurement_resolved_publication_provenance.dart';
import '../restage_rpc_client/restage_rpc_client.dart';
import '../restage_rpc_client/surface_artifact_assembly.dart';
import '../resolver/restage_variant_resolver.dart' show RestageEnvironment;
import '../resolver/surface_assignment_key_provider.dart';
import '../resolver/report_surface_resolution.dart';
import '../resolver/surface_resolution_report.dart';
import '../runtime/builtin_catalog_capabilities.dart';
import '../runtime/library_runtime_registry.dart';
import '../runtime/restage.dart';
import '../runtime/surface_vocabulary.dart';
import 'bundled_flow_loader.dart';
import 'compiled_flow.dart';
import 'flow_descriptors.dart';
import 'flow_experiment_artifact_metadata.dart';
import 'flow_experiment_mount.dart';
import 'flow_resolver.dart';

/// Creates a dynamic exact-version hosted flow reference.
///
/// The reference uses the built-in catalog capability installed by this SDK as
/// its client floor. The resolver still applies its authoritative document and
/// per-artifact capability gates before returning a flow.
///
/// Pass [vocabulary] when the app knows what the hosted flow draws: the
/// generated `SurfaceVocabulary` of the surface it serves. Passing none
/// installs nothing, so an app serving content it cannot know ahead of time
/// installs the whole catalog itself at startup with
/// `InstalledWidgetLibraries.install(RestageWidgetLibraries.builtIn())` and
/// `InstalledIconTable.install(builtInIconTable())`.
SurfaceFlowRef<R> hostedSurfaceFlowRef<R>({
  required String id,
  required int version,
  required Surface surfaceType,
  required FlowResultDecoder<R> decodeResult,
  SurfaceVocabulary vocabulary = SurfaceVocabulary.none,
}) {
  return SurfaceFlowRef<R>(
    id: id,
    version: version,
    minClient: RestageBuiltInCatalogCapabilities.currentVersion,
    surface: surfaceType,
    decodeResult: decodeResult,
    vocabulary: vocabulary,
  );
}

/// Resolves flows from exact-version surface documents.
///
/// A server-resolved flow is fetched by flow id and version, then decoded,
/// compatibility-checked, validated, and returned with its pinned screen blobs.
///
/// When constructed with `active: true` the resolver ALSO exposes the opt-in
/// active arm ([ActiveArmFlowResolver.resolveActiveRoot]): the ROOT flow is
/// served from the server's currently-active version, contract-gated against
/// the client's bundled document and fail-closed through a hold-last-good →
/// bundled → typed-error ladder. The default (`active: false`) leaves the exact
/// path intact. The active arm uses the generated Dart contract when present;
/// older references still require the bundled graph and screen artifacts.
final class ServerFlowResolver
    implements
        FlowResolver,
        ActiveArmFlowResolver,
        FlowExperimentMountFactory,
        FlowExperimentArtifactMetadataProvider {
  /// Creates a resolver using the SDK surface endpoint.
  /// [active] enables active delivery; otherwise requests are exact-version only.
  /// The flow descriptor supplies the namespace. [bundle] supplies active-delivery
  /// contracts and fallback assets, defaulting to `rootBundle`.
  /// [environment] defaults to the SDK configuration.
  ServerFlowResolver({
    required String baseUrl,
    required String apiKey,
    http.Client? httpClient,
    bool active = false,
    AssetBundle? bundle,
    RestageEnvironment? environment,
    RestageRpcClient? Function()? rpcClientProvider,
  })  : _active = active,
        _bundle = bundle,
        _apiKey = apiKey,
        _environment = environment,
        _rpcClientProvider = rpcClientProvider,
        _baseUrl = baseUrl,
        _httpClient = httpClient {
    if (rpcClientProvider == null) _ownedClient;
    registerRacedResolver(this, _raced);
  }

  final String _baseUrl;
  final http.Client? _httpClient;
  late final RestageRpcClient _ownedClient = RestageRpcClient(
    baseUrl: _baseUrl,
    apiKey: _apiKey,
    httpClient: _httpClient,
  );
  final RestageRpcClient? Function()? _rpcClientProvider;
  RestageRpcClient get _client => _rpcClientProvider?.call() ?? _ownedClient;
  final bool _active;
  final AssetBundle? _bundle;
  final String _apiKey;
  final RestageEnvironment? _environment;

  // The configured environment when none was passed.
  String get _scope => SurfaceStoreKey.scopeFor(
        apiKey: _apiKey,
        environment: (_environment ?? Restage.configuredEnvironment).name,
      );
  late final RacedSurfaceDelegate<ResolvedFlow> _raced =
      RacedSurfaceDelegate<ResolvedFlow>(bestLocal: bestLocal, fresh: fresh);

  /// Where accepted deliveries persist.
  @internal
  SurfaceArtifactStore get store => sharedSurfaceArtifactStore;

  /// The store key for [flow]'s active root. Active content is re-gated
  /// against the current contract on read, so it carries no version.
  @internal
  SurfaceStoreKey storeKeyFor<R>(SurfaceFlowRef<R> flow) {
    final key = SurfaceStoreKey(
      scope: _scope,
      surfaceType: flow.surfaceType.wireName,
      slug: flow.id,
      contractVersion: 0,
    );
    _refs[key] = flow as SurfaceFlowRef<Object?>;
    return key;
  }

  SurfaceStoreKey _exactStoreKeyFor<R>(SurfaceFlowRef<R> flow) =>
      SurfaceStoreKey(
        scope: _scope,
        surfaceType: flow.surfaceType.wireName,
        slug: flow.id,
        contractVersion: flow.version,
      );

  /// The flow each raced store key was issued for.
  final Map<SurfaceStoreKey, SurfaceFlowRef<Object?>> _refs =
      <SurfaceStoreKey, SurfaceFlowRef<Object?>>{};

  AssetBundle get _effectiveBundle => restageAssetSource(_bundle);

  @internal
  @override
  bool get activeArmEnabled => _active;

  @internal
  @override
  bool get experimentMountsEnabled => _active;

  @internal
  @override
  FlowExperimentPresentationResolver createExperimentPresentation({
    required OnboardingFlowRef<Object?> flow,
    required FlowMountSeedCapture captureSeed,
  }) {
    return _ServerFlowExperimentPresentation(
      owner: this,
      flow: flow,
      captureSeed: captureSeed,
    );
  }

  @internal
  @override
  FlowResolver createUnassignedFallbackResolver() =>
      _BundledExperimentResolver(this);

  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> flow) =>
      _resolveExact(flow);

  Future<ResolvedFlow> _resolveExact<R>(
    OnboardingFlowRef<R> flow, {
    bool Function()? publicationGuard,
    bool sendAssignmentKey = true,
    Future<void>? keyDeadline,
    List<(SurfaceStoreKey, StoredSurface)>? acceptedInto,
  }) async {
    final exactKey = _exactStoreKeyFor(flow);
    // An exact version is immutable, so the stored copy answers first. It
    // passes the same checks a fetched one does.
    final held = await _readStored(exactKey);
    if (held != null) {
      try {
        return _acceptExact(flow, held, cacheHit: true);
      } on FlowUnavailableError {
        // A stored copy that no longer passes is fetched again.
      }
    }

    final SurfaceFetchResult? result;
    try {
      result = await _client.fetchSurface(
        surfaceType: flow.surfaceType.wireName,
        surfaceSlug: flow.id,
        version: flow.version,
        publicationGuard: publicationGuard,
        sendAssignmentKey: sendAssignmentKey,
        keyDeadline: keyDeadline,
      );
    } on SurfaceRequestPublicationRejected {
      throw const _ExperimentSeedDrift();
    }
    _requireExactPublicationCurrent(publicationGuard);
    if (result == null) {
      throw _error(
        flow,
        'unavailable',
        'Flow "${flow.id}" version ${flow.version} is unavailable.',
      );
    }
    final resolved = _acceptExact(flow, result, cacheHit: false);
    final stored = result.stored;
    if (stored != null) {
      if (acceptedInto != null) {
        acceptedInto.add((exactKey, stored));
      } else {
        await _persist(exactKey, stored);
      }
    }
    return resolved;
  }

  /// Runs every exact-version check on [result]; throws with the reason.
  ResolvedFlow _acceptExact<R>(
    OnboardingFlowRef<R> flow,
    SurfaceFetchResult result, {
    required bool cacheHit,
  }) {
    // The exact arm throws, and says why.
    final SurfaceDocument surfaceDocument;
    switch (result.artifact) {
      case SurfaceArtifactAssembled(:final document):
        surfaceDocument = document;
      case SurfaceArtifactUnavailable():
        throw _error(
          flow,
          'unavailable',
          'Flow "${flow.id}" version ${flow.version} is unavailable.',
        );
      case SurfaceArtifactUndecodable(:final error):
        throw _error(
          flow,
          'decode_failed',
          'Failed to decode surface document for "${flow.id}": $error.',
          error,
        );
    }
    _checkEnvelopeIdentity(flow, surfaceDocument);
    final payload = surfaceDocument.payload;
    if (payload is! FlowSurfacePayload) {
      throw _error(
        flow,
        'unsupported_payload',
        'Surface document for "${flow.id}" did not contain a flow payload.',
      );
    }

    final document = payload.flowDocument;
    _checkCompatibility(flow, document);
    // The required custom libraries ride the envelope, not the flow document.
    _checkRequiredLibraries(flow, surfaceDocument.requiredLibraries);
    _checkValidation(flow, document);

    final cachedFlow = _cachedFrom(result, surfaceDocument, payload);
    // An exact version is a deliberate pin, so serving it again is not a hold.
    return reportSurfaceResolution(
      flow.surface,
      flow.id,
      _own(
        cachedFlow.toResolvedFlow(cacheHit: cacheHit),
        requiredLibraries: cachedFlow.requiredLibraries,
      ),
      SurfaceResolutionSource.fresh,
    );
  }

  _CachedServerFlow _cachedFrom(
    SurfaceFetchResult result,
    SurfaceDocument surfaceDocument,
    FlowSurfacePayload payload,
  ) =>
      _CachedServerFlow.from(
        payload.flowDocument,
        payload.screenBlobs,
        surfaceDocument.requiredLibraries,
        publicationBindingReference: result.publicationBindingReference,
        canonicalExperimentAssignment: result.canonicalExperimentAssignment,
        routingSelectionReceipt: result.routingSelectionReceipt,
        routingSelectionProvenance: result.routingSelectionProvenance,
        sections: surfaceSectionsOf(payload),
      );

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

  @internal
  @override
  Future<ResolvedFlow> resolveActiveRoot<R>(OnboardingFlowRef<R> flow) async {
    // The active arm runs only when this resolver was constructed active.
    if (!_active) return resolve(flow);
    final key = storeKeyFor(flow);
    final resolved = await resolveRacedInOrder(_raced, key);
    if (resolved != null) return resolved;
    throw _error(
      flow,
      'unavailable',
      'Active flow "${flow.id}" is unavailable and no bundled fallback exists.',
    );
  }

  /// Local candidates for [key]: the stored active re-gated, then the baseline.
  @internal
  Future<ResolvedFlow?> bestLocal(SurfaceStoreKey key) async {
    final flow = _refs[key];
    if (flow == null) return null;
    final baseline = await _loadClientBaseline(flow);
    if (baseline == null) return null;
    final held = await _readStored(key);
    if (held != null) {
      final active = await _acceptActive(flow, baseline, held, cacheHit: true);
      if (active != null) {
        return labelSurfaceSource<ResolvedFlow>(
            active, SurfaceResolutionSource.holdLastGood);
      }
    }
    return labelSurfaceSource<ResolvedFlow>(
        baseline, SurfaceResolutionSource.bundled);
  }

  /// The active hosted flow for [key], gated and persisted on accept.
  @internal
  Future<ResolvedFlow?> fresh(
    SurfaceStoreKey key, {
    required bool sendAssignmentKey,
    Future<void>? keyDeadline,
  }) async {
    // A key this resolver issued no ref for cannot be gated; nothing to do.
    final flow = _refs[key];
    if (flow == null) return null;
    _raced.freshStarted(key);
    // With no client contract there is nothing to gate an active against.
    final baseline = await _loadClientBaseline(flow);
    if (baseline == null) {
      _raced.freshRefused(key, SurfaceDeliveryReceiptReason.unsupported);
      return null;
    }
    final result = await _client.fetchSurface(
      surfaceType: flow.surfaceType.wireName,
      surfaceSlug: flow.id,
      sendAssignmentKey: sendAssignmentKey,
      keyDeadline: keyDeadline,
      // version omitted → the delivery service's active-version arm.
    );
    if (result == null) {
      _raced.freshRefused(key, SurfaceDeliveryReceiptReason.offline);
      return null;
    }
    final active = await _acceptActive(flow, baseline, result, cacheHit: false);
    if (active == null) {
      _raced.freshRefused(key, SurfaceDeliveryReceiptReason.unsupported);
      return null;
    }
    await _persist(key, result.stored);
    return labelSurfaceSource<ResolvedFlow>(
        active, SurfaceResolutionSource.fresh);
  }

  /// An active delivery that passes every retained check, the render gate
  /// against [baseline], and, when stored under an assignment, the held
  /// assignment check. Null otherwise.
  Future<ResolvedFlow?> _acceptActive<R>(
    OnboardingFlowRef<R> flow,
    ResolvedFlow baseline,
    SurfaceFetchResult result, {
    required bool cacheHit,
  }) async {
    final SurfaceDocument surfaceDocument;
    switch (result.artifact) {
      case SurfaceArtifactAssembled(:final document):
        surfaceDocument = document;
      case SurfaceArtifactUnavailable():
      case SurfaceArtifactUndecodable():
        return null;
    }
    // The version is the server's active one; type and slug must still match.
    if (surfaceDocument.surfaceType != flow.surfaceType ||
        surfaceDocument.surfaceSlug != flow.id) {
      return null;
    }
    final payload = surfaceDocument.payload;
    if (payload is! FlowSurfacePayload) return null;
    if (!_passesRetainedChecks(
          flow,
          payload.flowDocument,
          surfaceDocument.requiredLibraries,
        ) ||
        !_renderGateAccepts(
          client: baseline.document,
          active: payload.flowDocument,
        )) {
      return null;
    }
    if (cacheHit) {
      final stored = result.stored;
      if (stored == null ||
          !(await storedDeliveryIdentity(
            stored: stored,
            assignment: result.canonicalExperimentAssignment,
            surface: flow.surfaceType.wireName,
            slug: flow.id,
          ))
              .reusable) {
        return null;
      }
    }
    final cached = _cachedFrom(result, surfaceDocument, payload);
    return _own(
      cached.toResolvedFlow(cacheHit: cacheHit),
      requiredLibraries: cached.requiredLibraries,
    );
  }

  Future<_ExperimentFreshFlow?> _fetchExperimentActive(
    OnboardingFlowRef<Object?> flow,
    FlowMountContractSnapshot snapshot,
    FlowMountSeedCapture captureSeed, {
    required Future<void>? keyDeadline,
    required bool sendAssignmentKey,
    required SurfaceAssignmentResolutionLease registrationLease,
  }) async {
    _requireExperimentSnapshotCurrent(
      snapshot,
      FlowMountRevalidationBoundary.request,
      captureSeed,
    );
    final SurfaceFetchResult? result;
    try {
      result = await _client.fetchSurface(
        surfaceType: flow.surfaceType.wireName,
        surfaceSlug: flow.id,
        assignmentKey: snapshot.assignmentKey,
        sendAssignmentKey: sendAssignmentKey,
        registrationLease: registrationLease,
        keyDeadline: keyDeadline,
        publicationGuard: () => _experimentSnapshotIsCurrent(
          snapshot,
          FlowMountRevalidationBoundary.request,
          captureSeed,
        ),
      );
    } on SurfaceRequestPublicationRejected {
      throw const _ExperimentSeedDrift();
    }
    _requireExperimentSnapshotCurrent(
      snapshot,
      FlowMountRevalidationBoundary.request,
      captureSeed,
    );
    if (result == null) return null;
    final candidate = _experimentCandidate(flow, result, cacheHit: false);
    return candidate == null
        ? null
        : _ExperimentFreshFlow(candidateRoot: candidate, stored: result.stored);
  }

  /// The active candidate in [result] when it passes the retained checks.
  ResolvedFlow? _experimentCandidate(
    OnboardingFlowRef<Object?> flow,
    SurfaceFetchResult result, {
    required bool cacheHit,
  }) {
    final SurfaceDocument surfaceDocument;
    switch (result.artifact) {
      case SurfaceArtifactAssembled(:final document):
        surfaceDocument = document;
      case SurfaceArtifactUnavailable():
      case SurfaceArtifactUndecodable():
        return null;
    }
    if (surfaceDocument.surfaceType != flow.surfaceType ||
        surfaceDocument.surfaceSlug != flow.id) {
      return null;
    }
    final payload = surfaceDocument.payload;
    if (payload is! FlowSurfacePayload) return null;
    if (!_passesRetainedChecks(
      flow,
      payload.flowDocument,
      surfaceDocument.requiredLibraries,
    )) {
      return null;
    }
    final cached = _cachedFrom(result, surfaceDocument, payload);
    return _own(
      cached.toResolvedFlow(cacheHit: cacheHit),
      requiredLibraries: cached.requiredLibraries,
    );
  }

  /// Selects the compiler-retained original, or the legacy bundled baseline.
  Future<ResolvedFlow?> _loadClientBaseline<R>(OnboardingFlowRef<R> flow,
      {CompiledFlow? compiledClosure}) async {
    final compiled =
        flow.compiled ?? compiledClosure?.find(flow.id, flow.version);
    if (compiled != null && compiled.hasCompleteScreenBuilders) {
      return _own(compiled.resolve(), requiredLibraries: const []);
    }
    try {
      final surface = flow.surfaceType.wireName;
      final bundled = await loadBundledFlowArtifacts(
        bundle: _effectiveBundle,
        flowJsonPath: 'assets/$surface/flows/${flow.id}.flow.json',
        screenAssetPathPrefix: 'assets/$surface/screens',
        flowId: flow.id,
        // The bundled document IS the client's own version (codegen emits it at
        // flow.version), so pin it — parity with the exact bundled path. A
        // mis-versioned bundled asset fails to load → no contract → fail closed,
        // and the Tier-3 fallback renders a version-verified document (so the
        // controller's active-scoped version-pin skip stays a provable no-op).
        expectedVersion: flow.version,
        supportedMinClient: flow.minClient,
        buildError: (reason, message, [cause]) =>
            _error(flow, reason, message, cause),
      );
      return _bundledResolvedFlow(bundled);
    } on FlowUnavailableError catch (error) {
      debugPrint(
        '[restage] rejected bundled ${flow.surfaceType.wireName} flow baseline '
        '"${flow.id}" (${error.reason}); active selection failed closed.',
      );
      return null;
    }
  }

  /// Fail-closed render-gate selection. A general-marked bundled client can use
  /// the structural-permissive general gate; any other client uses the
  /// content-only strict gate. The general gate refuses a non-general document
  /// by construction, so a mis-selection fails closed. A typed document is never
  /// evaluated permissively.
  ///
  /// Delivery-mode agreement is required, symmetrically: an active document is
  /// served only under the gate matching the client's own delivery mode, so a
  /// mode mismatch in EITHER direction fails closed to the bundled document —
  /// including a general active document served to a typed client (which the
  /// content-only gate would otherwise accept as a content-only change, since it
  /// does not compare the delivery-mode marker). The general gate independently
  /// re-checks that both documents are general; this precheck also closes the
  /// typed-client / general-active direction.
  bool _renderGateAccepts({
    required FlowDocument client,
    required FlowDocument active,
  }) {
    if (client.deliveryMode != active.deliveryMode) return false;
    if (client.deliveryMode == FlowDeliveryMode.general) {
      return GeneralFlowRenderGate.evaluate(
        client: client,
        active: active,
      ).accepted;
    }

    return FlowActiveRenderGate.evaluate(
      client: client,
      active: active,
    ).accepted;
  }

  /// Runs the retained backstop checks (everything except the version pin) on a
  /// candidate active document, returning false (→ ladder) on any rejection
  /// rather than throwing. Used both for a fresh active fetch and to re-affirm a
  /// held-last-good document against the current registry/installed capability
  /// (the caller re-runs the render gate against the current client contract).
  bool _passesRetainedChecks<R>(
    OnboardingFlowRef<R> flow,
    FlowDocument document,
    List<LibraryRequirement> requiredLibraries,
  ) {
    try {
      _checkCompatibility(flow, document, checkVersion: false);
      _checkRequiredLibraries(flow, requiredLibraries);
      _checkValidation(flow, document);
      return true;
    } on FlowUnavailableError {
      return false;
    }
  }

  ResolvedFlow _bundledResolvedFlow(BundledFlowArtifacts bundled) {
    return _own(
      attachSurfaceSections(
        ResolvedFlow(
          document: bundled.document,
          screenBlobs: bundled.screenBlobs,
          contentHash: bundled.documentHash,
          cacheHit: false,
        ),
        bundled.sections,
      ),
      requiredLibraries: const [],
    );
  }

  ResolvedFlow _own(
    ResolvedFlow flow, {
    required List<LibraryRequirement> requiredLibraries,
  }) {
    FlowExperimentArtifactOwnership.attach(
      owner: this,
      flow: flow,
      metadata: FlowExperimentArtifactOwnership.verifiedMetadata(
        requiredLibraries: requiredLibraries,
      ),
    );
    return flow;
  }

  @override
  FlowExperimentArtifactMetadata metadataFor(ResolvedFlow flow) =>
      FlowExperimentArtifactOwnership.metadataFor(owner: this, flow: flow);

  /// Rejects a decoded envelope whose header identity (`surfaceType` /
  /// `surfaceSlug` / `version`) does not match the requested flow. The inner
  /// FlowDocument identity is checked separately in [_checkCompatibility]; this
  /// closes the residual where a wrong-surface envelope carries a payload whose
  /// inner document happens to match. Mirrors the blob path's envelope-identity
  /// check (a server bug / routing error / substituted response must fail closed
  /// rather than render the wrong surface).
  void _checkEnvelopeIdentity<R>(
    OnboardingFlowRef<R> flow,
    SurfaceDocument surfaceDocument,
  ) {
    if (surfaceDocument.surfaceType != flow.surfaceType ||
        surfaceDocument.surfaceSlug != flow.id ||
        surfaceDocument.version != flow.version) {
      throw _error(
        flow,
        'surface_mismatch',
        'Surface envelope (${surfaceDocument.surfaceType.wireName} '
            '"${surfaceDocument.surfaceSlug}" v${surfaceDocument.version}) does '
            'not match the requested flow "${flow.id}" v${flow.version}.',
      );
    }
  }

  /// Runs the flow-document compatibility checks. [checkVersion] is the ONE
  /// dimension the active arm relaxes: with `checkVersion: false` the bare
  /// `version ==` exact-pin is skipped (the render gate replaces it), while
  /// EVERY other check — flow id, schemaVersion, the doc + per-artifact
  /// capability floors — keeps running on the active document (the binding
  /// backstop). The exact path calls this with the default `checkVersion:
  /// true`, so its behavior is unchanged.
  void _checkCompatibility<R>(
    OnboardingFlowRef<R> flow,
    FlowDocument document, {
    bool checkVersion = true,
  }) {
    if (document.flow != flow.id) {
      throw _error(
        flow,
        'flow_mismatch',
        'Flow document id "${document.flow}" does not match requested '
            'flow "${flow.id}".',
      );
    }
    if (checkVersion && document.version != flow.version) {
      throw _error(
        flow,
        'version_mismatch',
        'Flow document version ${document.version} does not match requested '
            'version ${flow.version}.',
      );
    }
    if (document.schemaVersion != 1 && document.schemaVersion != 2) {
      throw _error(
        flow,
        'unsupported_schema_version',
        'Unsupported flow schemaVersion ${document.schemaVersion}.',
      );
    }
    if (document.minClient > flow.minClient) {
      throw _error(
        flow,
        'unsupported_min_client',
        'Flow minClient ${document.minClient} exceeds requested client '
            '${flow.minClient}.',
      );
    }
    // The authoritative installed-capability gate (parity with the blob path):
    // the delivered floor must be at or below the built-in catalog version this
    // build installs, regardless of the compiled ref floor. The ref check above
    // is a build-time consistency check; this is the one that fails closed when
    // a ref/SDK version skew would otherwise render an unsupported document.
    if (document.minClient > RestageBuiltInCatalogCapabilities.currentVersion) {
      throw _error(
        flow,
        'unsupported_min_client',
        'Flow minClient ${document.minClient} exceeds the installed built-in '
            'catalog version ${RestageBuiltInCatalogCapabilities.currentVersion}.',
      );
    }

    for (final entry in document.screenArtifacts.entries) {
      final artifact = entry.value;
      if (artifact.schemaVersion != 1) {
        throw _error(
          flow,
          'unsupported_schema_version',
          'Unsupported screen artifact schemaVersion '
              '${artifact.schemaVersion} for "${entry.key}".',
        );
      }
      if (artifact.minClient > flow.minClient) {
        throw _error(
          flow,
          'unsupported_min_client',
          'Screen artifact minClient ${artifact.minClient} for "${entry.key}" '
              'exceeds requested client ${flow.minClient}.',
        );
      }
      if (artifact.minClient >
          RestageBuiltInCatalogCapabilities.currentVersion) {
        throw _error(
          flow,
          'unsupported_min_client',
          'Screen artifact minClient ${artifact.minClient} for "${entry.key}" '
              'exceeds the installed built-in catalog version '
              '${RestageBuiltInCatalogCapabilities.currentVersion}.',
        );
      }
    }
  }

  /// Verifies every custom library the surface envelope requires is satisfied
  /// by the runtime registry (registered AND at or above the required version),
  /// failing closed with a typed error naming the gap. Envelope-level only —
  /// the flow document's contract is untouched.
  void _checkRequiredLibraries<R>(
    OnboardingFlowRef<R> flow,
    List<LibraryRequirement> requiredLibraries,
  ) {
    for (final requirement in requiredLibraries) {
      if (!LibraryRuntimeRegistry.satisfies(requirement)) {
        throw _error(
          flow,
          'unsupported_required_library',
          'Flow "${flow.id}" requires library "${requirement.namespace}" '
              '>= v${requirement.minVersion} '
              '(${LibraryRuntimeRegistry.describeGap(requirement)}).',
        );
      }
    }
  }

  // Intentional defense-in-depth — DO NOT remove as dead code. Today an invalid
  // document already fails closed one layer earlier (the surface codec re-runs
  // document validation while decoding, surfacing `decode_failed`), so this pass
  // is currently caught-earlier. It is kept as the resolver-layer integrity
  // backstop between server-controlled bytes and the renderer: if the codec's
  // decode-time validation ever diverges from this check, an unvalidated
  // document would still fail closed here. It also keeps this resolver
  // structurally parallel to the bundled resolver, whose validation IS the
  // primary check because bundled flow JSON bypasses the codec.
  void _checkValidation<R>(OnboardingFlowRef<R> flow, FlowDocument document) {
    final issues = FlowDocumentValidation.validate(document);
    if (issues.isEmpty) {
      return;
    }

    final reason = issues.any((issue) => issue.code == 'unsupportedStateKind')
        ? 'unsupported_state_kind'
        : issues.any((issue) => issue.code == 'unsupportedFeature')
            ? 'unsupported_feature'
            : 'validation_failed';
    throw _error(
      flow,
      reason,
      'Flow document failed validation: ${issues.join('; ')}.',
    );
  }

  FlowUnavailableError _error<R>(
    OnboardingFlowRef<R> flow,
    String reason,
    String message, [
    Object? cause,
  ]) {
    return FlowUnavailableError(
      flowId: flow.id,
      flowVersion: flow.version,
      reason: reason,
      message: cause == null ? message : '$message Cause: $cause',
    );
  }
}

final class _ServerFlowExperimentPresentation
    with RacedSurfaceReporting<ResolvedFlow>
    implements
        FlowExperimentPresentationResolver,
        FlowExperimentArtifactMetadataProvider,
        RacedSurfaceResolver<ResolvedFlow> {
  _ServerFlowExperimentPresentation({
    required this.owner,
    required this.flow,
    required this.captureSeed,
  }) : _baselineResolver = _BundledExperimentResolver(owner, flow.compiled);

  final ServerFlowResolver owner;
  final OnboardingFlowRef<Object?> flow;
  final FlowMountSeedCapture captureSeed;
  final _BundledExperimentResolver _baselineResolver;

  FlowMountContractSnapshot? _snapshot;
  FlowResolver? _selectedResolver;
  bool _disposed = false;
  bool _baselineSelected = false;
  bool _unstableIdentity = false;

  /// The snapshot and closure resolver each candidate was chosen under.
  final Expando<(FlowMountContractSnapshot?, FlowResolver)> _chosenWith =
      Expando<(FlowMountContractSnapshot?, FlowResolver)>();

  @override
  bool get activeArmEnabled => owner.activeArmEnabled;

  @override
  SurfaceArtifactStore get store => owner.store;

  @override
  SurfaceStoreKey get storeKey => owner.storeKeyFor(flow);

  @override
  Future<ResolvedFlow> resolveActiveRoot<R>(
    OnboardingFlowRef<R> requestedFlow,
  ) async {
    if (!activeArmEnabled) return owner.resolve(requestedFlow);
    final key = storeKey;
    final fresh = await this.fresh(key, sendAssignmentKey: true);
    if (fresh == null && _unstableIdentity) {
      throw _unavailable('unstable_mount_identity');
    }
    final resolved = fresh ?? await bestLocal(key);
    reportRacedSurface(this, key, resolved);
    if (resolved != null) return resolved;
    throw _unavailable('missing_bundled_baseline');
  }

  @override
  void winnerReported(SurfaceStoreKey key, ResolvedFlow winner) {
    final chosen = _chosenWith[winner];
    if (chosen == null) return;
    _baselineSelected = chosen.$1 == null;
    _snapshot = chosen.$1 ?? _snapshot;
    _selectedResolver = chosen.$2;
  }

  ResolvedFlow _chose(
    ResolvedFlow root,
    FlowMountContractSnapshot? snapshot,
    FlowResolver resolver,
  ) {
    _chosenWith[root] = (snapshot, resolver);
    return root;
  }

  @override
  Future<ResolvedFlow?> fresh(
    SurfaceStoreKey key, {
    required bool sendAssignmentKey,
    Future<void>? keyDeadline,
  }) async {
    freshStarted(key);
    _unstableIdentity = false;
    var sealDrifts = 0;
    for (var attempt = 0; attempt < 3 && !_disposed; attempt += 1) {
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
        resolver: _baselineResolver,
      ).seal();
      if (_disposed) break;
      if (snapshotOutcome is FlowMountSnapshotRejected) {
        if (snapshotOutcome.reason == FlowMountSnapshotRejection.seedDrift) {
          sealDrifts += 1;
          continue;
        }
        break;
      }
      var snapshot = (snapshotOutcome as FlowMountSnapshotSealed).snapshot;
      _snapshot ??= snapshot;

      try {
        final fetched = await owner._fetchExperimentActive(
          flow,
          snapshot,
          captureSeed,
          keyDeadline: keyDeadline,
          sendAssignmentKey: sendAssignmentKey,
          registrationLease: registrationLease!,
        );
        if (_disposed) break;
        if (fetched == null) {
          freshRefused(key, SurfaceDeliveryReceiptReason.offline);
          return null;
        }
        snapshot = snapshot.withAssignmentKey(fetched.stored == null
            ? registrationLease!.assignmentKey
            : storedSurfaceAssignmentKey(fetched.stored!));
        _snapshot = snapshot;
        final children = <(SurfaceStoreKey, StoredSurface)>[];
        final prefetched = await FlowCandidatePrefetcher.prefetch(
          snapshot: snapshot,
          captureSeed: captureSeed,
          candidateRoot: fetched.candidateRoot,
          resolver: _CandidateChildResolver(
            owner: owner,
            isLive: () => !_disposed,
            snapshot: snapshot,
            captureSeed: captureSeed,
            keyDeadline: keyDeadline,
            accepted: children,
          ),
        );
        if (_disposed) break;
        if (prefetched is FlowCandidatePrefetchAccepted) {
          await owner._persist(key, fetched.stored);
          for (final (childKey, stored) in children) {
            await owner._persist(childKey, stored);
          }
          return labelSurfaceSource<ResolvedFlow>(
            _chose(prefetched.candidateRoot, snapshot, prefetched.resolver),
            SurfaceResolutionSource.fresh,
          );
        }
        if ((prefetched is FlowCandidatePrefetchRejected &&
                prefetched.reason ==
                    FlowCandidatePrefetchRejection.seedDrift) ||
            !_experimentSnapshotIsCurrent(
              snapshot,
              FlowMountRevalidationBoundary.fallback,
              captureSeed,
            )) {
          continue;
        }
        freshRefused(key, SurfaceDeliveryReceiptReason.unsupported);
        return null;
      } on _ExperimentSeedDrift {
        continue;
      }
    }
    _unstableIdentity = sealDrifts == 3;
    freshRefused(key, SurfaceDeliveryReceiptReason.offline);
    return null;
  }

  @override
  Future<ResolvedFlow?> bestLocal(SurfaceStoreKey key) async {
    if (_disposed) return null;
    final held = await owner._readStored(key);
    if (held != null) {
      final local = await _heldCandidate(key, held);
      if (local != null) {
        return labelSurfaceSource<ResolvedFlow>(
            local, SurfaceResolutionSource.holdLastGood);
      }
    }
    try {
      final baseline = await _baselineResolver.resolve(flow);
      return labelSurfaceSource<ResolvedFlow>(
        _chose(baseline, null, _baselineResolver),
        SurfaceResolutionSource.bundled,
      );
    } on FlowUnavailableError {
      return null;
    }
  }

  /// A stored candidate re-derived against the current snapshot, its
  /// sub-flows read from the store only.
  Future<ResolvedFlow?> _heldCandidate(
    SurfaceStoreKey key,
    SurfaceFetchResult held,
  ) async {
    final identity = await storedDeliveryIdentity(
      stored: held.stored!,
      assignment: held.canonicalExperimentAssignment,
      surface: flow.surfaceType.wireName,
      slug: flow.id,
    );
    if (!identity.reusable) return null;
    final assignmentKey = identity.key;
    final candidate = owner._experimentCandidate(flow, held, cacheHit: true);
    if (candidate == null) return null;
    final snapshotOutcome = await FlowMountContractSnapshotBuilder(
      captureSeed: captureSeed,
      resolveAssignmentKey: () => assignmentKey,
      resolver: _baselineResolver,
    ).seal();
    if (_disposed || snapshotOutcome is! FlowMountSnapshotSealed) return null;
    final snapshot = snapshotOutcome.snapshot;
    final prefetched = await FlowCandidatePrefetcher.prefetch(
      snapshot: snapshot,
      captureSeed: captureSeed,
      candidateRoot: candidate,
      resolver: _StoredChildResolver(owner),
    );
    if (_disposed || prefetched is! FlowCandidatePrefetchAccepted) return null;
    final accepted = prefetched.asCacheHit();
    return _chose(accepted.candidateRoot, snapshot, accepted.resolver);
  }

  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> flow) {
    final selected = _selectedResolver;
    if (selected == null) {
      final snapshot = _snapshot;
      if (_disposed || snapshot == null) {
        return Future<ResolvedFlow>.error(_unavailable('root_not_resolved'));
      }
      return owner._resolveExact(
        flow,
        publicationGuard: () =>
            !_disposed &&
            _experimentSnapshotIsCurrent(
              snapshot,
              FlowMountRevalidationBoundary.candidatePrefetch,
              captureSeed,
            ),
      );
    }
    return selected.resolve(flow);
  }

  @override
  FlowExperimentArtifactMetadata metadataFor(ResolvedFlow flow) =>
      owner.metadataFor(flow);

  @override
  bool revalidate(FlowMountRevalidationBoundary boundary) {
    // The bundled baseline carries no hosted choice to go stale.
    if (_baselineSelected) return !_disposed;
    final snapshot = _snapshot;
    if (_disposed || snapshot == null) return false;
    try {
      return snapshot.revalidate(boundary, captureSeed());
    } on Object {
      return false;
    }
  }

  // Accepted candidates persist when accepted; render commitment adds nothing.
  @override
  void publishHostedLastGood() {}

  @override
  void abandonHostedLastGood() {}

  @override
  void disposePresentation() {
    _disposed = true;
  }

  FlowUnavailableError _unavailable(String reason) => FlowUnavailableError(
        flowId: flow.id,
        flowVersion: flow.version,
        reason: reason,
        message: 'Hosted flow "${flow.id}" could not complete its experiment '
            'mount transaction ($reason).',
      );
}

/// Fetches a candidate's exact sub-flows under its snapshot, collecting what
/// to persist if the candidate is accepted.
final class _CandidateChildResolver
    implements FlowResolver, FlowExperimentArtifactMetadataProvider {
  _CandidateChildResolver({
    required this.owner,
    required this.isLive,
    required this.snapshot,
    required this.captureSeed,
    required this.keyDeadline,
    required this.accepted,
  });

  final ServerFlowResolver owner;
  final bool Function() isLive;
  final FlowMountContractSnapshot snapshot;
  final FlowMountSeedCapture captureSeed;
  final Future<void>? keyDeadline;
  final List<(SurfaceStoreKey, StoredSurface)> accepted;

  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> flow) =>
      owner._resolveExact(
        flow,
        publicationGuard: () =>
            isLive() &&
            _experimentSnapshotIsCurrent(
              snapshot,
              FlowMountRevalidationBoundary.candidatePrefetch,
              captureSeed,
            ),
        sendAssignmentKey: snapshot.assignmentKey != null,
        keyDeadline: keyDeadline,
        acceptedInto: accepted,
      );

  @override
  FlowExperimentArtifactMetadata metadataFor(ResolvedFlow flow) =>
      owner.metadataFor(flow);
}

/// Reads a stored candidate's exact sub-flows from the store only.
final class _StoredChildResolver
    implements FlowResolver, FlowExperimentArtifactMetadataProvider {
  const _StoredChildResolver(this.owner);

  final ServerFlowResolver owner;

  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> flow) async {
    final held = await owner._readStored(owner._exactStoreKeyFor(flow));
    if (held == null) {
      throw FlowUnavailableError(
        flowId: flow.id,
        flowVersion: flow.version,
        reason: 'not_stored',
        message: 'Flow "${flow.id}" version ${flow.version} is not stored.',
      );
    }
    return owner._acceptExact(flow, held, cacheHit: true);
  }

  @override
  FlowExperimentArtifactMetadata metadataFor(ResolvedFlow flow) =>
      owner.metadataFor(flow);
}

final class _BundledExperimentResolver
    implements FlowResolver, FlowExperimentArtifactMetadataProvider {
  const _BundledExperimentResolver(this.owner, [this.compiledClosure]);

  final ServerFlowResolver owner;
  final CompiledFlow? compiledClosure;

  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> flow) async {
    final bundled =
        await owner._loadClientBaseline(flow, compiledClosure: compiledClosure);
    if (bundled == null) {
      throw FlowUnavailableError(
        flowId: flow.id,
        flowVersion: flow.version,
        reason: 'missing_bundled_baseline',
        message: 'Bundled baseline flow "${flow.id}" is unavailable.',
      );
    }
    return bundled;
  }

  @override
  FlowExperimentArtifactMetadata metadataFor(ResolvedFlow flow) =>
      owner.metadataFor(flow);
}

final class _ExperimentFreshFlow {
  const _ExperimentFreshFlow({required this.candidateRoot, this.stored});

  final ResolvedFlow candidateRoot;
  final StoredSurface? stored;
}

final class _ExperimentSeedDrift implements Exception {
  const _ExperimentSeedDrift();
}

void _requireExactPublicationCurrent(bool Function()? publicationGuard) {
  if (publicationGuard == null) return;
  try {
    if (publicationGuard()) return;
  } on Object {
    // A throwing mutable-authority recapture is the same stale publication
    // outcome as an explicit false guard.
  }
  throw const _ExperimentSeedDrift();
}

bool _experimentSnapshotIsCurrent(
  FlowMountContractSnapshot snapshot,
  FlowMountRevalidationBoundary boundary,
  FlowMountSeedCapture captureSeed,
) {
  try {
    return snapshot.revalidate(boundary, captureSeed());
  } on Object {
    return false;
  }
}

void _requireExperimentSnapshotCurrent(
  FlowMountContractSnapshot snapshot,
  FlowMountRevalidationBoundary boundary,
  FlowMountSeedCapture captureSeed,
) {
  if (!_experimentSnapshotIsCurrent(snapshot, boundary, captureSeed)) {
    throw const _ExperimentSeedDrift();
  }
}

final class _CachedServerFlow {
  const _CachedServerFlow(
    this.document,
    this.screenBlobs,
    this.contentHash,
    this.requiredLibraries,
    this.publicationBindingReference,
    this.canonicalExperimentAssignment,
    this.routingSelectionReceipt,
    this.routingSelectionProvenance,
    this.sections,
  );

  /// Builds a cache entry, computing the canonical-document content hash (the
  /// single source for that recipe across the exact and active paths).
  factory _CachedServerFlow.from(
    FlowDocument document,
    Map<String, Uint8List> screenBlobs,
    List<LibraryRequirement> requiredLibraries, {
    required MeasurementPublicationBindingReferenceV1?
        publicationBindingReference,
    required CanonicalSurfaceExperimentAssignmentV1?
        canonicalExperimentAssignment,
    required String? routingSelectionReceipt,
    required SurfaceRoutingSelectionProvenanceV1? routingSelectionProvenance,
    SurfaceSections sections = SurfaceSections.none,
  }) {
    return _CachedServerFlow(
      document,
      screenBlobs,
      FlowContentHash.compute(FlowDocumentCodec.encodeCanonicalJson(document)),
      requiredLibraries,
      publicationBindingReference,
      canonicalExperimentAssignment,
      routingSelectionReceipt,
      routingSelectionProvenance,
      sections,
    );
  }

  final FlowDocument document;
  final Map<String, Uint8List> screenBlobs;
  final FlowContentHash contentHash;

  /// The envelope's required-library manifest, retained so a cache hit can
  /// re-run the capability gate (the library registry can change after caching).
  final List<LibraryRequirement> requiredLibraries;

  /// Exact immutable Measurement provenance retained with these exact bytes.
  final MeasurementPublicationBindingReferenceV1? publicationBindingReference;
  final CanonicalSurfaceExperimentAssignmentV1? canonicalExperimentAssignment;
  final String? routingSelectionReceipt;
  final SurfaceRoutingSelectionProvenanceV1? routingSelectionProvenance;
  final SurfaceSections sections;

  ResolvedFlow toResolvedFlow({required bool cacheHit}) {
    return attachMeasurementPublicationBindingReference(
      attachSurfaceSections(
        ResolvedFlow(
          document: document,
          screenBlobs: screenBlobs,
          contentHash: contentHash,
          cacheHit: cacheHit,
          assignment: projectSurfaceAssignment(canonicalExperimentAssignment),
        ),
        sections,
      ),
      publicationBindingReference,
      canonicalExperimentAssignment: canonicalExperimentAssignment,
      routingSelectionReceipt: routingSelectionReceipt,
      routingSelectionProvenance: routingSelectionProvenance,
    );
  }
}
