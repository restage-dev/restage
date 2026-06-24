import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:restage_shared/restage_shared.dart'
    show
        FlowContentHash,
        FlowDocument,
        FlowDocumentCodec,
        FlowDocumentValidation,
        FlowSurfacePayload,
        LibraryRequirement,
        SurfaceDocument,
        SurfaceDocumentCodec,
        SurfaceType;

import '../restage_rpc_client/restage_rpc_client.dart';
import '../runtime/builtin_catalog_capabilities.dart';
import '../runtime/library_runtime_registry.dart';
import 'flow_descriptors.dart';
import 'flow_resolver.dart';

/// Resolves onboarding flows from exact-version surface documents.
///
/// A server-resolved flow is fetched by flow id and version, then decoded,
/// compatibility-checked, validated, and returned with its pinned screen blobs.
final class ServerFlowResolver implements FlowResolver {
  /// Creates a resolver backed by the SDK surface endpoint.
  ServerFlowResolver({
    required String baseUrl,
    required String apiKey,
    http.Client? httpClient,
  }) : _client = RestageRpcClient(
          baseUrl: baseUrl,
          apiKey: apiKey,
          httpClient: httpClient,
        );

  final RestageRpcClient _client;
  final Map<String, _CachedServerFlow> _cache = {};

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

    final bytes = await _client.fetchSurface(
      surfaceType: SurfaceType.onboarding.wireName,
      surfaceSlug: flow.id,
      version: flow.version,
    );
    if (bytes == null) {
      throw _error(
        flow,
        'unavailable',
        'Flow "${flow.id}" version ${flow.version} is unavailable.',
      );
    }

    final surfaceDocument = _decode(flow, bytes);
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

    final contentHash = FlowContentHash.compute(
      FlowDocumentCodec.encodeCanonicalJson(document),
    );
    final cachedFlow = _CachedServerFlow(
      document,
      screenBlobs,
      contentHash,
      surfaceDocument.requiredLibraries,
    );
    _cache[cacheKey] = cachedFlow;
    return cachedFlow.toResolvedFlow(cacheHit: false);
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
    if (surfaceDocument.surfaceType != SurfaceType.onboarding ||
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

  void _checkCompatibility<R>(
    OnboardingFlowRef<R> flow,
    FlowDocument document,
  ) {
    if (document.flow != flow.id) {
      throw _error(
        flow,
        'flow_mismatch',
        'Flow document id "${document.flow}" does not match requested '
            'flow "${flow.id}".',
      );
    }
    if (document.version != flow.version) {
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
    return '${flow.id}\u0000${flow.version}';
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

final class _CachedServerFlow {
  const _CachedServerFlow(
    this.document,
    this.screenBlobs,
    this.contentHash,
    this.requiredLibraries,
  );

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
    );
  }
}
