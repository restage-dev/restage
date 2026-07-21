import 'dart:typed_data';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;
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
        SurfaceDocumentCodec,
        SurfaceType;

import '../restage_rpc_client/restage_rpc_client.dart';
import '../runtime/builtin_catalog_capabilities.dart';
import '../runtime/library_runtime_registry.dart';
import 'bundled_flow_loader.dart';
import 'flow_assignment.dart';
import 'flow_descriptors.dart';
import 'flow_resolver.dart';

/// Creates a dynamic exact-version hosted flow reference.
///
/// The reference uses the built-in catalog capability installed by this SDK as
/// its client floor. The resolver still applies its authoritative document and
/// per-artifact capability gates before returning a flow.
SurfaceFlowRef<R> hostedSurfaceFlowRef<R>({
  required String id,
  required int version,
  required SurfaceType surfaceType,
  required FlowResultDecoder<R> decodeResult,
}) {
  return SurfaceFlowRef<R>(
    id: id,
    version: version,
    minClient: RestageBuiltInCatalogCapabilities.currentVersion,
    surfaceType: surfaceType,
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
final class ServerFlowResolver implements FlowResolver, ActiveArmFlowResolver {
  /// Creates a resolver backed by the SDK surface endpoint.
  ///
  /// [active] opts into the active arm (default false → exact-only, byte
  /// unchanged). [bundle] supplies the bundled flow assets the active arm reads
  /// as the client contract + bundled fallback (defaults to the app's
  /// `rootBundle`); it is unused on the exact path. Exact requests derive their
  /// surface namespace solely from the resolved flow descriptor. The active arm
  /// currently supports onboarding descriptors only.
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

  AssetBundle get _effectiveBundle => _bundle ?? rootBundle;

  @internal
  @override
  bool get activeArmEnabled => _active;

  @override
  Future<ResolvedFlow> resolve<R>(OnboardingFlowRef<R> flow) async {
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
      return cached.toResolvedFlow(cacheHit: true);
    }

    final result = await _client.fetchSurface(
      surfaceType: flow.surfaceType.wireName,
      surfaceSlug: flow.id,
      version: flow.version,
    );
    if (result == null) {
      throw _error(
        flow,
        'unavailable',
        'Flow "${flow.id}" version ${flow.version} is unavailable.',
      );
    }

    final surfaceDocument = _decode(flow, result.envelopeBytes);
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
    return cachedFlow.toResolvedFlow(cacheHit: false);
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

    // The active delivery contract and bundled asset conventions remain
    // onboarding-only. The descriptor owns identity, so reject any other
    // surface before bundle access, cache access, or network work.
    if (flow.surfaceType != SurfaceType.onboarding) {
      throw _error(
        flow,
        'unsupported_surface_type',
        'The active flow arm supports onboarding descriptors only.',
      );
    }
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
        return active.toResolvedFlow(cacheHit: false);
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
        return cached.toResolvedFlow(cacheHit: true);
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

  /// Loads the client's bundled flow document + screen blobs by convention
  /// (`assets/onboarding/flows/<id>.flow.json`). Genuine onboarding screens
  /// load from the onboarding screen directory; embedded paywall-owned screens
  /// load from the paywall screen directory. Returns null when no bundled asset
  /// is present or it fails to load — the "no contract ⇒ fail closed" signal
  /// for the active arm.
  Future<BundledFlowArtifacts?> _loadBundledContract<R>(
    OnboardingFlowRef<R> flow,
  ) async {
    try {
      return await loadBundledFlowArtifacts(
        bundle: _effectiveBundle,
        flowJsonPath: 'assets/onboarding/flows/${flow.id}.flow.json',
        screenAssetPathPrefix: 'assets/onboarding/screens',
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
    } on FlowUnavailableError {
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
    final SurfaceDocument surfaceDocument;
    try {
      surfaceDocument = SurfaceDocumentCodec.decode(result.envelopeBytes);
    } on FormatException {
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
    return ResolvedFlow(
      document: bundled.document,
      screenBlobs: bundled.screenBlobs,
      contentHash: bundled.documentHash,
      cacheHit: false,
    );
  }

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

  SurfaceDocument _decode<R>(OnboardingFlowRef<R> flow, Uint8List bytes) {
    try {
      return SurfaceDocumentCodec.decode(bytes);
    } on FormatException catch (e) {
      throw _error(
        flow,
        'decode_failed',
        'Failed to decode surface document for "${flow.id}": $e.',
        e,
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
