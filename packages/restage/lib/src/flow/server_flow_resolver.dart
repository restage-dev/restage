import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show AssetBundle;
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:restage_shared/restage_shared.dart'
    show
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

import '../assets/bundled_asset_source.dart';
import '../restage_rpc_client/restage_rpc_client.dart';
import '../restage_rpc_client/surface_artifact_assembly.dart';
import '../resolver/surface_assignment_key_provider.dart';
import '../runtime/builtin_catalog_capabilities.dart';
import '../runtime/library_runtime_registry.dart';
import 'bundled_flow_loader.dart';
import 'flow_assignment.dart';
import 'flow_descriptors.dart';
import 'flow_experiment_artifact_metadata.dart';
import 'flow_experiment_mount.dart';
import 'flow_resolver.dart';

/// Creates a dynamic exact-version hosted flow reference.
///
/// The reference uses the built-in catalog capability installed by this SDK as
/// its client floor. The resolver still applies its authoritative document and
/// per-artifact capability gates before returning a flow.
SurfaceFlowRef<R> hostedSurfaceFlowRef<R>({
  required String id,
  required int version,
  required Surface surfaceType,
  required FlowResultDecoder<R> decodeResult,
}) {
  return SurfaceFlowRef<R>(
    id: id,
    version: version,
    minClient: RestageBuiltInCatalogCapabilities.currentVersion,
    surface: surfaceType,
    decodeResult: decodeResult,
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
/// path byte-unchanged. The active arm needs the bundled flow asset present (the
/// build emits it) — with no bundled contract it fails closed.
final class ServerFlowResolver
    implements
        FlowResolver,
        ActiveArmFlowResolver,
        FlowExperimentMountFactory,
        FlowExperimentArtifactMetadataProvider {
  /// Creates a resolver backed by the SDK surface endpoint.
  ///
  /// [active] opts into the active arm (default false → exact-only, byte
  /// unchanged). [bundle] supplies the bundled flow assets the active arm reads
  /// as the client contract + bundled fallback (defaults to the app's
  /// `rootBundle`); it is unused on the exact path. Exact requests derive their
  /// surface namespace solely from the resolved flow descriptor, and the active
  /// arm uses that same descriptor-owned namespace.
  ServerFlowResolver({
    required String baseUrl,
    required String apiKey,
    http.Client? httpClient,
    bool active = false,
    AssetBundle? bundle,
  })  : _active = active,
        _bundle = bundle,
        _client = RestageRpcClient(
          baseUrl: baseUrl,
          apiKey: apiKey,
          httpClient: httpClient,
        );

  final RestageRpcClient _client;
  final bool _active;
  final AssetBundle? _bundle;

  /// The version-pinned exact cache, keyed by (surface type, slug, version).
  final Map<String, _CachedServerFlow> _cache = {};

  /// The active-arm hold-last-good cache, keyed by (surface type, flow id), not
  /// version: it holds the last gate-accepted active document for a flow,
  /// re-gated against the current bundled contract on every hit so a
  /// stale-but-incompatible active is never served. Separate from [_cache] so
  /// contract-version (the exact key) never collides with resolved-active-
  /// version.
  final Map<String, _CachedServerFlow> _activeCache = {};
  final Map<String, _ExperimentHostedFlow> _experimentActiveCache = {};

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
  }) async {
    final cacheKey = _cacheKey(flow);
    final cached = _cache[cacheKey];
    if (cached != null) {
      // Re-run the capability gate on every cache hit: a custom library may have
      // been unregistered or downgraded since the document was cached, so a
      // stale renderable must not be served without re-affirming the floor. The
      // installed built-in catalog dimension is a compile-time const (it cannot
      // drift at runtime) but is cheap to re-affirm alongside.
      if (cached.document.minClient >
          RestageBuiltInCatalogCapabilities.currentVersion) {
        throw _error(
          flow,
          'unsupported_min_client',
          'Flow minClient ${cached.document.minClient} exceeds the installed '
              'built-in catalog version '
              '${RestageBuiltInCatalogCapabilities.currentVersion}.',
        );
      }
      _checkRequiredLibraries(flow, cached.requiredLibraries);
      return _own(
        cached.toResolvedFlow(cacheHit: true),
        requiredLibraries: cached.requiredLibraries,
      );
    }

    final SurfaceFetchResult? result;
    try {
      result = await _client.fetchSurface(
        surfaceType: flow.surfaceType.wireName,
        surfaceSlug: flow.id,
        version: flow.version,
        publicationGuard: publicationGuard,
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

    // The exact arm has never had a soft ladder — it throws, and it says WHY.
    // Keeping the two reasons apart matters here: a host told "could not read
    // the content" for a delivery whose content never arrived would go looking
    // at the wrong thing entirely.
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
    final screenBlobs = payload.screenBlobs;
    _checkCompatibility(flow, document);
    // The flow capability gate is envelope-level: the required custom libraries
    // ride the SurfaceDocument manifest (not the flow document), verified
    // against the runtime registry before render. The flow document's own
    // contract is untouched.
    _checkRequiredLibraries(flow, surfaceDocument.requiredLibraries);
    _checkValidation(flow, document);

    final cachedFlow = _CachedServerFlow.from(
      document,
      screenBlobs,
      surfaceDocument.requiredLibraries,
      assignment: _assignmentOf(result),
    );
    _cache[cacheKey] = cachedFlow;
    return _own(
      cachedFlow.toResolvedFlow(cacheHit: false),
      requiredLibraries: cachedFlow.requiredLibraries,
    );
  }

  @internal
  @override
  Future<ResolvedFlow> resolveActiveRoot<R>(OnboardingFlowRef<R> flow) async {
    // Self-enforce the opt-in: the active arm runs ONLY when this resolver was
    // constructed `active: true`. The controller already gates on
    // [activeArmEnabled], so this is a no-op on the real path; it makes the flag
    // load-bearing where the behavior lives, so a direct call on a non-active
    // resolver fails safe to the exact path rather than going active off-flag.
    if (!_active) return resolve(flow);

    final activeCacheKey = _activeCacheKey(flow);

    // Load the client's bundled contract: it is BOTH the render gate's `client`
    // argument AND the Tier-3 fallback. If it is not loadable (no bundled asset
    // / hash mismatch) there is no contract to gate against, so the active
    // document can never be accepted — the ladder fails closed rather than
    // performing an ungated accept.
    final bundled = await _loadBundledContract(flow);

    if (bundled != null) {
      // Tier 1 — fresh active fetch + contract gate. A fetch failure or a
      // rejected document (any retained backstop check OR the gate) funnels
      // into the SAME ladder; a rejected active is NEVER rendered.
      final active = await _fetchActive(flow);
      if (active != null &&
          _renderGateAccepts(
            client: bundled.document,
            active: active.document,
          )) {
        _activeCache[activeCacheKey] = active;
        return _own(
          active.toResolvedFlow(cacheHit: false),
          requiredLibraries: active.requiredLibraries,
        );
      }

      // Tier 2 — hold-last-good (in-memory, keyed by flow id). Re-run the gate
      // AND the capability floor/library checks against the CURRENT bundled
      // contract + runtime registry: a stale active that no longer renders
      // safely is not served.
      final cached = _activeCache[activeCacheKey];
      if (cached != null &&
          _renderGateAccepts(
            client: bundled.document,
            active: cached.document,
          ) &&
          _passesRetainedChecks(
              flow, cached.document, cached.requiredLibraries)) {
        return _own(
          cached.toResolvedFlow(cacheHit: true),
          requiredLibraries: cached.requiredLibraries,
        );
      }

      // Tier 3 — the client's own bundled document (exact; its version equals
      // the requested version, so the controller's retained version pin passes).
      return _bundledResolvedFlow(bundled);
    }

    // Tier 4 — nothing renderable: no bundled contract and no servable active.
    throw _error(
      flow,
      'unavailable',
      'Active flow "${flow.id}" is unavailable and no bundled fallback exists.',
    );
  }

  Future<_ExperimentFreshFlow?> _fetchExperimentActive(
    OnboardingFlowRef<Object?> flow,
    FlowMountContractSnapshot snapshot,
    FlowMountSeedCapture captureSeed,
  ) async {
    _requireExperimentSnapshotCurrent(
      snapshot,
      FlowMountRevalidationBoundary.request,
      captureSeed,
    );
    var result = await _fetchExperimentSurface(
      flow: flow,
      snapshot: snapshot,
      captureSeed: captureSeed,
      boundary: FlowMountRevalidationBoundary.request,
      flowContract: FlowContractFetchRequest.hashOnly(
        snapshot.contentHash.value,
      ),
    );
    _requireExperimentSnapshotCurrent(
      snapshot,
      FlowMountRevalidationBoundary.request,
      captureSeed,
    );
    if (result == null) return null;

    if (result.flowContractRequired) {
      final current = _captureExperimentSeed(captureSeed);
      final bytes = snapshot.bytesForRetry(
        FlowMountRevalidationBoundary.uploadRetry,
        current,
      );
      if (bytes == null) throw const _ExperimentSeedDrift();
      result = await _fetchExperimentSurface(
        flow: flow,
        snapshot: snapshot,
        captureSeed: captureSeed,
        boundary: FlowMountRevalidationBoundary.uploadRetry,
        flowContract: FlowContractFetchRequest.retry(
          snapshot.contentHash.value,
          bytes,
        ),
      );
      _requireExperimentSnapshotCurrent(
        snapshot,
        FlowMountRevalidationBoundary.uploadRetry,
        captureSeed,
      );
      if (result == null || result.flowContractRequired) return null;
    }

    // Both artifact refusals reach the same `null` the decode failure always
    // did — this arm's ladder treats an unrenderable active exactly like an
    // absent one.
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

    final assignment = _assignmentOf(result);
    if ((assignment != null) != (result.decision == 'assigned')) {
      return null;
    }
    if (assignment != null && snapshot.assignmentKey == null) {
      return null;
    }
    final cached = _CachedServerFlow.from(
      payload.flowDocument,
      payload.screenBlobs,
      surfaceDocument.requiredLibraries,
      assignment: assignment,
    );
    return _ExperimentFreshFlow(
      candidateRoot: _own(
        cached.toResolvedFlow(cacheHit: false),
        requiredLibraries: cached.requiredLibraries,
      ),
      serverVerdictAccepted:
          assignment == null || result.decision == 'assigned',
    );
  }

  Future<SurfaceFetchResult?> _fetchExperimentSurface({
    required OnboardingFlowRef<Object?> flow,
    required FlowMountContractSnapshot snapshot,
    required FlowMountSeedCapture captureSeed,
    required FlowMountRevalidationBoundary boundary,
    required FlowContractFetchRequest flowContract,
  }) async {
    try {
      return await _client.fetchSurface(
        surfaceType: flow.surfaceType.wireName,
        surfaceSlug: flow.id,
        assignmentKey: snapshot.assignmentKey,
        flowContract: flowContract,
        publicationGuard: () => _experimentSnapshotIsCurrent(
          snapshot,
          boundary,
          captureSeed,
        ),
      );
    } on SurfaceRequestPublicationRejected {
      throw const _ExperimentSeedDrift();
    }
  }

  /// Loads the client's bundled flow document + screen blobs from its surface
  /// directory by convention (`assets/<surface>/flows/<id>.flow.json`).
  /// Embedded paywall-owned screens still load from the paywall screen
  /// directory. Returns null when no bundled asset is present or it fails to
  /// load — the "no contract ⇒ fail closed" signal for the active arm.
  Future<BundledFlowArtifacts?> _loadBundledContract<R>(
    OnboardingFlowRef<R> flow,
  ) async {
    try {
      final surface = flow.surfaceType.wireName;
      return await loadBundledFlowArtifacts(
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
    } on FlowUnavailableError catch (error) {
      debugPrint(
        '[restage] rejected bundled ${flow.surfaceType.wireName} flow baseline '
        '"${flow.id}" (${error.reason}); active selection failed closed.',
      );
      return null;
    }
  }

  /// Fetches + validates the server's ACTIVE flow version. Runs every retained
  /// runtime validity check EXCEPT the bare version pin (the binding backstop:
  /// flow id, schemaVersion, doc + per-artifact floors, required libraries,
  /// document validation) on the active document. Returns null on any fetch
  /// failure, decode failure, envelope mismatch, or rejected check — a rejected
  /// active never renders; it funnels into the fallback ladder.
  Future<_CachedServerFlow?> _fetchActive<R>(OnboardingFlowRef<R> flow) async {
    final result = await _client.fetchSurface(
      surfaceType: flow.surfaceType.wireName,
      surfaceSlug: flow.id,
      // version omitted → the delivery service's active-version arm.
    );
    if (result == null) return null;

    // Flow requests intentionally omit an assignment key. Any valid assignment
    // metadata on the response remains passive and is attached only after the
    // artifact passes the validation checks below.
    // Both artifact refusals reach the same `null` the decode failure always
    // did — this arm's ladder treats an unrenderable active exactly like an
    // absent one.
    final SurfaceDocument surfaceDocument;
    switch (result.artifact) {
      case SurfaceArtifactAssembled(:final document):
        surfaceDocument = document;
      case SurfaceArtifactUnavailable():
      case SurfaceArtifactUndecodable():
        return null;
    }

    // Envelope identity, version-relaxed: the surface type + slug must still
    // match (a substituted/mis-routed surface fails closed), but the version is
    // the server's active version — the ONE identity dimension the active arm
    // does not pin.
    if (surfaceDocument.surfaceType != flow.surfaceType ||
        surfaceDocument.surfaceSlug != flow.id) {
      return null;
    }

    final payload = surfaceDocument.payload;
    if (payload is! FlowSurfacePayload) return null;

    final document = payload.flowDocument;
    if (!_passesRetainedChecks(
      flow,
      document,
      surfaceDocument.requiredLibraries,
    )) {
      return null;
    }

    return _CachedServerFlow.from(
      // Assignment metadata is stored only with an accepted artifact so
      // attribution describes what rendered.
      document,
      payload.screenBlobs,
      surfaceDocument.requiredLibraries,
      assignment: _assignmentOf(result),
    );
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
      return GeneralFlowRenderGate.evaluate(client: client, active: active)
          .accepted;
    }

    return FlowActiveRenderGate.evaluate(client: client, active: active)
        .accepted;
  }

  /// Runs the retained backstop checks (everything except the version pin) on a
  /// candidate active document, returning false (→ ladder) on any rejection
  /// rather than throwing. Used both for a fresh active fetch and to re-affirm a
  /// held-last-good document against the current registry/installed capability
  /// (the caller re-runs the render gate against the current bundled contract).
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
      ResolvedFlow(
        document: bundled.document,
        screenBlobs: bundled.screenBlobs,
        contentHash: bundled.documentHash,
        cacheHit: false,
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
  /// `version ==` exact-pin is skipped (the P2 render gate replaces it), while
  /// EVERY other check — flow id, schemaVersion, the doc + per-artifact
  /// capability floors — keeps running on the active document (the binding
  /// backstop). The exact path calls this with the default `checkVersion: true`,
  /// so its behavior is unchanged.
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
    if (document.schemaVersion != 1) {
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

  String _cacheKey<R>(OnboardingFlowRef<R> flow) {
    return '${flow.surfaceType.wireName}\u0000${flow.id}\u0000${flow.version}';
  }

  String _activeCacheKey<R>(OnboardingFlowRef<R> flow) =>
      '${flow.surfaceType.wireName}\u0000${flow.id}';

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
    implements
        FlowExperimentPresentationResolver,
        FlowExperimentArtifactMetadataProvider {
  _ServerFlowExperimentPresentation({
    required this.owner,
    required this.flow,
    required this.captureSeed,
  }) : _baselineResolver = _BundledExperimentResolver(owner);

  final ServerFlowResolver owner;
  final OnboardingFlowRef<Object?> flow;
  final FlowMountSeedCapture captureSeed;
  final _BundledExperimentResolver _baselineResolver;

  FlowMountContractSnapshot? _snapshot;
  FlowResolver? _selectedResolver;
  _ExperimentHostedFlow? _provisional;
  bool _disposed = false;

  @override
  bool get activeArmEnabled => owner.activeArmEnabled;

  @override
  Future<ResolvedFlow> resolveActiveRoot<R>(
    OnboardingFlowRef<R> requestedFlow,
  ) async {
    if (!activeArmEnabled) return owner.resolve(requestedFlow);
    for (var attempt = 0; attempt < 3 && !_disposed; attempt += 1) {
      final snapshotOutcome = await FlowMountContractSnapshotBuilder(
        captureSeed: captureSeed,
        resolveAssignmentKey: SurfaceAssignmentKeyProvider.resolve,
        resolver: _baselineResolver,
      ).seal();
      if (_disposed) throw _unavailable('disposed');
      if (snapshotOutcome is FlowMountSnapshotRejected) {
        if (snapshotOutcome.reason == FlowMountSnapshotRejection.seedDrift) {
          continue;
        }
        throw _unavailable('invalid_baseline_closure');
      }
      final snapshot = (snapshotOutcome as FlowMountSnapshotSealed).snapshot;
      _snapshot = snapshot;

      try {
        final fresh = await owner._fetchExperimentActive(
          flow,
          snapshot,
          captureSeed,
        );
        if (_disposed) throw _unavailable('disposed');
        if (fresh != null) {
          final prefetched = await FlowCandidatePrefetcher.prefetch(
            snapshot: snapshot,
            captureSeed: captureSeed,
            candidateRoot: fresh.candidateRoot,
            resolver: this,
            serverVerdictAccepted: fresh.serverVerdictAccepted,
          );
          if (_disposed) throw _unavailable('disposed');
          if (prefetched is FlowCandidatePrefetchAccepted) {
            _selectedResolver = prefetched.resolver;
            _provisional = _ExperimentHostedFlow(
              snapshot: snapshot,
              accepted: prefetched,
            );
            return prefetched.candidateRoot;
          }
          if (prefetched is FlowCandidatePrefetchRejected &&
              prefetched.reason == FlowCandidatePrefetchRejection.seedDrift) {
            continue;
          }
        }
      } on _ExperimentSeedDrift {
        continue;
      }

      final key = owner._activeCacheKey(flow);
      final held = owner._experimentActiveCache[key];
      if (held != null) {
        if (held.matches(snapshot) &&
            _experimentSnapshotIsCurrent(
              held.snapshot,
              FlowMountRevalidationBoundary.fallback,
              captureSeed,
            )) {
          final accepted = held.accepted.asCacheHit();
          _selectedResolver = accepted.resolver;
          _provisional = null;
          return accepted.candidateRoot;
        }
        owner._experimentActiveCache.remove(key);
      }

      if (!_experimentSnapshotIsCurrent(
        snapshot,
        FlowMountRevalidationBoundary.fallback,
        captureSeed,
      )) {
        continue;
      }
      _selectedResolver = snapshot.baselineResolver;
      _provisional = null;
      return snapshot.baselineRoot;
    }
    throw _unavailable('unstable_mount_identity');
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
    final snapshot = _snapshot;
    if (_disposed || snapshot == null) return false;
    try {
      return snapshot.revalidate(boundary, captureSeed());
    } on Object {
      return false;
    }
  }

  @override
  void publishHostedLastGood() {
    final provisional = _provisional;
    if (provisional == null) return;
    if (!revalidate(FlowMountRevalidationBoundary.cachePublication)) {
      _provisional = null;
      return;
    }
    owner._experimentActiveCache[owner._activeCacheKey(flow)] = provisional;
    _provisional = null;
  }

  @override
  void abandonHostedLastGood() {
    _provisional = null;
  }

  @override
  void disposePresentation() {
    _disposed = true;
    abandonHostedLastGood();
  }

  FlowUnavailableError _unavailable(String reason) => FlowUnavailableError(
        flowId: flow.id,
        flowVersion: flow.version,
        reason: reason,
        message: 'Hosted flow "${flow.id}" could not complete its experiment '
            'mount transaction ($reason).',
      );
}

final class _BundledExperimentResolver
    implements FlowResolver, FlowExperimentArtifactMetadataProvider {
  const _BundledExperimentResolver(this.owner);

  final ServerFlowResolver owner;

  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> flow) async {
    final bundled = await owner._loadBundledContract(flow);
    if (bundled == null) {
      throw FlowUnavailableError(
        flowId: flow.id,
        flowVersion: flow.version,
        reason: 'missing_bundled_baseline',
        message: 'Bundled baseline flow "${flow.id}" is unavailable.',
      );
    }
    return owner._bundledResolvedFlow(bundled);
  }

  @override
  FlowExperimentArtifactMetadata metadataFor(ResolvedFlow flow) =>
      owner.metadataFor(flow);
}

final class _ExperimentFreshFlow {
  const _ExperimentFreshFlow({
    required this.candidateRoot,
    required this.serverVerdictAccepted,
  });

  final ResolvedFlow candidateRoot;
  final bool serverVerdictAccepted;
}

final class _ExperimentHostedFlow {
  const _ExperimentHostedFlow({
    required this.snapshot,
    required this.accepted,
  });

  final FlowMountContractSnapshot snapshot;
  final FlowCandidatePrefetchAccepted accepted;

  bool matches(FlowMountContractSnapshot current) {
    return snapshot.seed.sameIdentityAs(current.seed) &&
        snapshot.assignmentKey == current.assignmentKey &&
        snapshot.contentHash == current.contentHash;
  }
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

FlowMountLeaseSeed _captureExperimentSeed(
  FlowMountSeedCapture captureSeed,
) {
  try {
    return captureSeed();
  } on Object {
    throw const _ExperimentSeedDrift();
  }
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
  final FlowAssignment? assignment;

  const _CachedServerFlow(
    this.document,
    this.screenBlobs,
    this.contentHash,
    this.requiredLibraries,
    this.assignment,
  );

  /// Builds a cache entry, computing the canonical-document content hash (the
  /// single source for that recipe across the exact and active paths).
  factory _CachedServerFlow.from(
    FlowDocument document,
    Map<String, Uint8List> screenBlobs,
    List<LibraryRequirement> requiredLibraries, {
    required FlowAssignment? assignment,
  }) {
    return _CachedServerFlow(
      document,
      screenBlobs,
      FlowContentHash.compute(FlowDocumentCodec.encodeCanonicalJson(document)),
      requiredLibraries,
      assignment,
    );
  }

  final FlowDocument document;
  final Map<String, Uint8List> screenBlobs;
  final FlowContentHash contentHash;

  /// The envelope's required-library manifest, retained so a cache hit can
  /// re-run the capability gate (the library registry can change after caching).
  final List<LibraryRequirement> requiredLibraries;

  ResolvedFlow toResolvedFlow({required bool cacheHit}) {
    return ResolvedFlow(
      document: document,
      screenBlobs: screenBlobs,
      contentHash: contentHash,
      cacheHit: cacheHit,
      assignment: assignment,
    );
  }
}

FlowAssignment? _assignmentOf(SurfaceFetchResult result) {
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
