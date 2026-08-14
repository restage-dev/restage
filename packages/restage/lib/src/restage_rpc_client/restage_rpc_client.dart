import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:restage_shared/flow_experiment.dart'
    show kFlowExperimentClientContractVersionV1, kFlowExperimentContractKind;
import 'package:restage_shared/restage_shared.dart';

import '../billing/purchase_token_digest.dart';
import '../resolver/surface_metering_key_provider.dart';
import '../secure_transport.dart';
import 'surface_artifact_assembly.dart';
import 'surface_delivery_evidence.dart';

/// The header a fetch presents its artifact pass in.
const String surfaceArtifactPassHeader = 'X-Restage-Artifact-Pass';

/// SDK-internal fence evaluated immediately before a surface request posts.
@internal
typedef SurfaceRequestPublicationGuard = bool Function();

/// Signals that a guarded surface request became stale before publication.
@internal
final class SurfaceRequestPublicationRejected implements Exception {
  /// Creates the internal stale-publication signal.
  const SurfaceRequestPublicationRejected();
}

/// Strict flow-contract identity attached to one hosted surface fetch.
final class FlowContractFetchRequest {
  /// Sends only [flowContractHash] for the first content-addressed lookup.
  const FlowContractFetchRequest.hashOnly(this.flowContractHash)
      : canonicalBytes = null;

  /// Retries a cache miss with the exact canonical V1 contract bytes.
  factory FlowContractFetchRequest.retry(
    String flowContractHash,
    List<int> canonicalBytes,
  ) {
    return FlowContractFetchRequest._(
      flowContractHash,
      List<int>.unmodifiable(canonicalBytes),
    );
  }

  const FlowContractFetchRequest._(
    this.flowContractHash,
    this.canonicalBytes,
  );

  /// Exact `sha256:<lowercase hex>` content identity.
  final String flowContractHash;

  /// Canonical V1 bytes included only on a cache-miss retry.
  final List<int>? canonicalBytes;
}

/// Result of a successful hosted surface fetch.
final class SurfaceFetchResult {
  /// Creates a hosted surface fetch result.
  const SurfaceFetchResult({
    required this.artifact,
    this.decision,
    this.experimentId,
    this.variantId,
    this.experimentEpoch,
    this.contractRequired = false,
    this.flowContractRequired = false,
  });

  /// What the artifact half of this delivery produced: the assembled document,
  /// nothing (the fetch did not deliver it), or a refusal to decode it.
  ///
  /// A result exists whenever the SERVER answered, so the retry signals below
  /// are readable even when the artifact is not — a client asked to re-send its
  /// capability contract must be able to do so without the artifact of a
  /// response it is about to discard.
  @internal
  final SurfaceArtifactOutcome artifact;

  /// The server's serve decision for this fetch, when present. Carried
  /// verbatim as an opaque string — an unrecognised value is preserved as-is,
  /// never rejected — so a newer server can introduce new decision values
  /// without breaking this client.
  final String? decision;

  /// Experiment id selected by the server, when the served artifact is an arm.
  final String? experimentId;

  /// Variant id selected by the server, when the served artifact is an arm.
  final String? variantId;

  /// Experiment epoch selected by the server, when the served artifact is an
  /// arm.
  final int? experimentEpoch;

  /// Whether the server needs the full client contract uploaded to resolve
  /// eligibility (a content-hash cache miss). The caller retries the fetch
  /// once with the contract attached.
  final bool contractRequired;

  /// Whether the server needs the strict canonical flow contract uploaded.
  ///
  /// This is independent from the legacy blob [contractRequired] channel.
  final bool flowContractRequired;
}

/// The active-version stamp for a surface.
final class SurfaceStamp {
  /// Creates a surface stamp.
  const SurfaceStamp({required this.version, this.watchChannel});

  /// The surface's current active published version.
  final int version;

  /// An opaque realtime-channel token, when one is available.
  final String? watchChannel;
}

/// Outcome of a strict standalone-screen delivery request.
///
/// Only [SurfaceScreenDeliveryAbsent] and
/// [SurfaceScreenDeliveryTransportUnavailable] are eligible for bundled
/// fallback. A present response that fails strict decoding or correlation is
/// represented by [SurfaceScreenDeliveryInvalidResponse].
sealed class SurfaceScreenDeliveryResult {
  /// Creates a strict standalone-screen delivery outcome.
  const SurfaceScreenDeliveryResult();
}

/// A strict standalone-screen delivery response matching the request identity.
final class SurfaceScreenDeliveryAvailable extends SurfaceScreenDeliveryResult {
  /// Creates an available standalone-screen delivery outcome.
  const SurfaceScreenDeliveryAvailable(this.response);

  /// The strict shared delivery response.
  final SurfaceScreenDeliveryResponseV1 response;
}

/// The requested standalone screen has no active hosted response.
final class SurfaceScreenDeliveryAbsent extends SurfaceScreenDeliveryResult {
  /// Creates an ordinary hosted-absence outcome.
  const SurfaceScreenDeliveryAbsent();
}

/// The request could not obtain a hosted response.
final class SurfaceScreenDeliveryTransportUnavailable
    extends SurfaceScreenDeliveryResult {
  /// Creates a transport-unavailable outcome.
  const SurfaceScreenDeliveryTransportUnavailable();
}

/// Why a present standalone-screen response was rejected.
enum SurfaceScreenDeliveryInvalidResponseReason {
  /// The server deterministically rejected the strict delivery request.
  requestRejected,

  /// The strict shared response codec rejected the response.
  malformed,

  /// The response document did not match the requested surface identity.
  identityMismatch,

  /// The response contract version did not match the requested pin.
  contractMismatch,
}

/// A present standalone-screen response that cannot be trusted.
final class SurfaceScreenDeliveryInvalidResponse
    extends SurfaceScreenDeliveryResult {
  /// Creates an invalid-response outcome with a safe classification.
  const SurfaceScreenDeliveryInvalidResponse(this.reason);

  /// The failed response check.
  final SurfaceScreenDeliveryInvalidResponseReason reason;
}

/// HTTP/JSON client for the SDK's `/sdk/v1` endpoints.
///
/// The SDK's shared `/sdk/v1` RPC client: it syncs entitlements, reports
/// transactions, and mints native promotional-offer signatures.
///
/// Transport failure mode: on a network error, malformed body, or non-2xx
/// response, both methods log a diagnostic and return `null` — distinct
/// from a server response that successfully returned no entitlements
/// (an empty `List<EntitlementSummary>`). Callers use the null vs empty
/// distinction to preserve local state on transport failure rather than
/// confusing it with "server says nothing's entitled". Transaction retry and
/// native-store replay are owned by the configure-installed purchase
/// coordinator; entitlement sync only reconciles the resulting entitlement
/// view.
class RestageRpcClient {
  /// Creates a client targeting [baseUrl] and authenticating as [apiKey].
  ///
  /// [httpClient] is the seam tests use to inject `MockClient`; production
  /// callers omit it and a default [http.Client] is constructed.
  RestageRpcClient({
    required String baseUrl,
    required String apiKey,
    http.Client? httpClient,
    @visibleForTesting bool? debugFailTransactionReports,
  })  : _baseUrl = baseUrl,
        _apiKey = apiKey,
        _client = httpClient ?? http.Client(),
        _debugFailTransactionReports = _debugTransactionReportOutageEnabled(
          debugFailTransactionReports,
        ) {
    if (baseUrl.isEmpty) {
      throw ArgumentError.value(baseUrl, 'baseUrl', 'must not be empty');
    }
    if (baseUrl.endsWith('/')) {
      throw ArgumentError.value(
        baseUrl,
        'baseUrl',
        'must not end with a trailing slash',
      );
    }
    // Credentials, the anonymous purchaser token, and receipt data ride this
    // origin — require TLS (loopback excepted for local development).
    assertSecureUrl(baseUrl, label: 'baseUrl');
    if (apiKey.isEmpty) {
      throw ArgumentError.value(apiKey, 'apiKey', 'must not be empty');
    }
  }

  final String _baseUrl;
  final String _apiKey;
  final http.Client _client;
  final bool _debugFailTransactionReports;

  /// Artifacts fetched and verified by this client, by identity.
  ///
  /// Per client and in memory only — the durable offline floor is the app's own
  /// bundled asset, and always was. This exists to stop a re-resolve of the
  /// same surface paying for the same bytes twice in one session.
  final Map<_ArtifactIdentity, Uint8List> _artifacts =
      <_ArtifactIdentity, Uint8List>{};

  /// How much held content one client keeps, in bytes.
  ///
  /// Bounded by SIZE rather than by count, because size is what runs out. A
  /// count of eight sounds small and is eighty megabytes at the publish
  /// ceiling — an unbounded cache with a polite name. Eviction is
  /// insertion-ordered rather than by use: a cleverer policy would need
  /// per-entry bookkeeping to beat "forget the oldest" at this scale, and would
  /// cost more than the fetch it saves.
  ///
  /// A single artifact larger than this is simply never held. It is served
  /// normally; it just does not evict everything else on the way past.
  static const int _maxHeldArtifactBytes = 8 * 1024 * 1024;

  int _heldArtifactBytes = 0;

  /// Durably creates or exactly replays an immutable purchase intent.
  ///
  /// Returns the correlated response only when the server echoes the exact
  /// client-generated intent UUID. Any transport or shape failure returns
  /// `null`, which callers treat as a hard stop before opening store UI.
  Future<CreatePurchaseIntentResponse?> createPurchaseIntent(
    CreatePurchaseIntentRequest request,
  ) async {
    final json = await _postJsonObject(
      path: '/sdk/v1/purchase-intent',
      body: request.toJson(),
    );
    if (json == null) return null;
    try {
      final response = CreatePurchaseIntentResponse.fromJson(json);
      if (response.purchaseIntentId != request.purchaseIntentId) {
        debugPrint('[restage] purchase intent response did not correlate');
        return null;
      }
      return response;
    } on Object {
      debugPrint('[restage] purchase intent response was malformed');
      return null;
    }
  }

  /// Reports a store transaction. Returns explicit durable acceptance, or
  /// `null` when transport, parsing, correlation, or acceptance validation
  /// fails.
  Future<ReportTransactionResponse?> reportTransaction(
    ReportTransactionRequest request,
  ) async {
    if (_debugFailTransactionReports) {
      debugPrint(
        '[restage] transaction report blocked by local debug outage injection',
      );
      return null;
    }
    final reportId = request.reportId;
    if (reportId == null) {
      debugPrint('[restage] transaction report is missing reportId');
      return null;
    }
    final json = await _postJsonObject(
      path: '/sdk/v1/reportTransaction',
      body: request.toJson(),
    );
    if (json == null) return null;
    try {
      final response = ReportTransactionResponse.fromJson(json);
      if (!response.accepted ||
          response.reportId != reportId ||
          !_evidenceMatchesRequest(response.evidence, request)) {
        debugPrint(
          '[restage] transaction report response was not completion-safe',
        );
        return null;
      }
      return response;
    } on Object {
      // Parser exceptions may retain malformed wire values. Do not interpolate
      // them here because a hostile response could reflect a purchase token.
      debugPrint('[restage] transaction report response was malformed');
      return null;
    }
  }

  /// Reports paywall attribution for a **receipt-less** purchase — one made
  /// through an external billing provider (e.g. RevenueCat) that keeps the
  /// receipt. This carries the store transaction id + paywall id as an
  /// attribution hint only; it is never a verified signal and never returns an
  /// entitlement set (unlike [reportTransaction], whose receipt the server can
  /// validate).
  ///
  /// The attribution endpoint is not yet wired, so this method intentionally
  /// does not POST. It mirrors the no-op posture the runtime already applies
  /// when no `baseUrl` is configured; the attribution-only report becomes a
  /// live call when the route lands.
  Future<void> reportAttribution({
    required String store,
    required String storeProductId,
    required String storeTransactionId,
    String? paywallId,
    int? paywallPublishedVersion,
  }) async {
    // Intentionally a no-op until the attribution endpoint is wired. Kept as
    // the typed routing seam so the runtime branches receipt-less successes
    // here (never down the receipt-validation path) from day one. The
    // [paywallPublishedVersion] is carried here so MAR attribution stays
    // version-complete across the external-provider path; it serializes onto
    // the request when the attribution endpoint lands.
  }

  /// Asks the server for the authoritative entitlement set. Returns the
  /// list, or `null` when the request fails — the SDK keeps its local
  /// state until the next sync succeeds. An empty list (non-null) is
  /// the server's explicit "nothing entitled" answer and reconciles
  /// normally.
  Future<List<EntitlementSummary>?> syncEntitlements(
    EntitlementSyncRequest request,
  ) =>
      _postEntitlements(
        path: '/sdk/v1/syncEntitlements',
        body: request.toJson(),
      );

  /// Fetches a surface document envelope for [surfaceSlug] of [surfaceType].
  ///
  /// Pass an explicit [version] to fetch that exact published version. Omit it
  /// (pass `null`) to ask the server for the currently-active version — the
  /// `version` key is then left out of the request body, which the serve route
  /// treats as the active-version request for surface types that support it
  /// (paywalls). Returns the base64-decoded envelope bytes, or `null` on any
  /// failure (network error, non-2xx status, a missing/invalid `envelope`
  /// field, or malformed assignment metadata). A `null` is the caller's signal
  /// to treat the surface as unavailable. The served version is carried inside
  /// the decoded envelope, so the active-version caller reads it back after
  /// decoding.
  Future<SurfaceFetchResult?> fetchSurface({
    required String surfaceType,
    required String surfaceSlug,
    int? version,
    String? assignmentKey,
    String? contractHash,
    InstalledCapability? contract,
    FlowContractFetchRequest? flowContract,
    SurfaceRequestPublicationGuard? publicationGuard,
  }) async {
    final meteringKey = await SurfaceMeteringKeyProvider.currentKey();
    if (publicationGuard != null) {
      final bool canPublish;
      try {
        canPublish = publicationGuard();
      } on Object {
        throw const SurfaceRequestPublicationRejected();
      }
      if (!canPublish) {
        throw const SurfaceRequestPublicationRejected();
      }
    }
    final json = await _postJsonObject(
      path: '/sdk/v1/surface',
      body: {
        'surfaceType': surfaceType,
        'surfaceSlug': surfaceSlug,
        if (version != null) 'version': version,
        if (assignmentKey != null) 'assignmentKey': assignmentKey,
        if (meteringKey != null) 'meteringKey': meteringKey,
        if (contractHash != null) 'contractHash': contractHash,
        if (contract != null) 'contract': contract.toJson(),
        if (flowContract != null) ...{
          'flowContractKind': kFlowExperimentContractKind,
          'flowContractVersion': kFlowExperimentClientContractVersionV1,
          'flowContractHash': flowContract.flowContractHash,
          if (flowContract.canonicalBytes case final bytes?)
            'flowContractBytes': base64UrlEncode(bytes).replaceAll('=', ''),
        },
      },
    );
    if (json == null) return null;

    final assignment = _parseSurfaceAssignmentMetadata(json);
    if (assignment == null) {
      debugPrint('[restage] surface assignment metadata was malformed');
      return null;
    }
    final rawDecision = json['decision'];
    final decision = rawDecision is String ? rawDecision : null;
    final rawContractRequired = json['contractRequired'];
    final contractRequired =
        rawContractRequired is bool ? rawContractRequired : false;
    final rawFlowContractRequired = json['flowContractRequired'];
    final flowContractRequired =
        rawFlowContractRequired is bool ? rawFlowContractRequired : false;

    final SurfaceArtifactDescriptorV1 descriptor;
    try {
      descriptor = SurfaceArtifactDescriptorV1Codec.decode(json['artifact']);
    } on FormatException catch (error) {
      // Includes the version gates: a delivery this build does not understand
      // is refused HERE, before a byte of it is fetched.
      debugPrint('[restage] surface delivery was not readable: $error');
      return null;
    }

    // A response that only asks for the capability contract is about to be
    // discarded by the caller, so fetching its artifact would spend a request
    // on bytes nobody will read — and a failure of that request would look like
    // a delivery failure instead of the retry it actually is.
    final artifact = contractRequired || flowContractRequired
        ? const SurfaceArtifactUnavailable(
            SurfaceArtifactFetchFailure.transport,
          )
        : await _resolveArtifact(descriptor);

    return SurfaceFetchResult(
      artifact: artifact,
      decision: decision,
      experimentId: assignment.experimentId,
      variantId: assignment.variantId,
      experimentEpoch: assignment.experimentEpoch,
      contractRequired: contractRequired,
      flowContractRequired: flowContractRequired,
    );
  }

  /// Fetches, verifies and assembles the artifact [descriptor] names.
  ///
  /// The single place the two halves of a delivery are joined. Every failure
  /// on the way — the request, the store's answer, the bytes themselves —
  /// funnels into one outcome type and is reported once, here, so a resolver's
  /// fallback is never taken in silence.
  Future<SurfaceArtifactOutcome> _resolveArtifact(
    SurfaceArtifactDescriptorV1 descriptor,
  ) async {
    // An artifact is content-addressed, so a re-resolve that names the same one
    // is naming bytes this client already holds and verified. Re-fetching them
    // would spend a request to learn nothing.
    //
    // Keyed on the artifact's WHOLE identity, not on its hash alone. The hash
    // is only half of it: the same bytes stored under two payload formats are
    // two different artifacts, in two different places, read by two different
    // decoders. Keying on the hash would make them one entry, and the first one
    // fetched would answer for the other. Harmless while one format exists;
    // wrong the moment a second does, and silently so.
    final identity = _ArtifactIdentity(
      payloadFormatVersion: descriptor.payloadFormatVersion,
      contentHash: descriptor.contentHash,
    );
    final held = _artifacts[identity];
    if (held != null) {
      // Re-assembled from THIS delivery's description, never replayed from the
      // one that filled the cache: the version, publication time and shape
      // claim belong to the resolve, not to the bytes.
      return _reported(
        descriptor,
        assembleSurfaceArtifact(descriptor: descriptor, artifactBytes: held),
      );
    }

    Uint8List? bytes;
    var failure = SurfaceArtifactFetchFailure.transport;
    try {
      // The pass travels with this request, so the request has to be encrypted
      // — the same rule, from the same function, that the configured origin is
      // held to. A description naming a cleartext origin is a description this
      // client will not act on, whoever wrote it.
      assertSecureUrl(descriptor.artifactUrl, label: 'artifact URL');
      bytes = await _fetchArtifactBytes(descriptor);
    } on InsecureBaseUrlException {
      failure = SurfaceArtifactFetchFailure.unreadableDescription;
    } on _ArtifactFetchRefused catch (refused) {
      failure = refused.failure;
    } on Object {
      // Shape-only: the URL carries a pass.
      failure = SurfaceArtifactFetchFailure.transport;
    }

    final outcome = assembleSurfaceArtifact(
      descriptor: descriptor,
      artifactBytes: bytes,
      fetchFailure: failure,
    );
    if (outcome is SurfaceArtifactAssembled && bytes != null) {
      // Held only once it has been verified and decoded. Caching bytes that
      // failed either gate would hand the next resolve a refusal it had already
      // earned, and would do it without a fetch that might now succeed.
      if (bytes.length <= _maxHeldArtifactBytes) {
        while (_artifacts.isNotEmpty &&
            _heldArtifactBytes + bytes.length > _maxHeldArtifactBytes) {
          _heldArtifactBytes -=
              _artifacts.remove(_artifacts.keys.first)!.length;
        }
        _artifacts[identity] = bytes;
        _heldArtifactBytes += bytes.length;
      }
    }
    return _reported(descriptor, outcome);
  }

  /// Reports [outcome] if it is a refusal, and returns it either way.
  ///
  /// Both the fetched and the held path funnel through here. A refusal that
  /// only one of them reported would be a failure whose visibility depended on
  /// whether the same artifact had been resolved earlier in the session.
  SurfaceArtifactOutcome _reported(
    SurfaceArtifactDescriptorV1 descriptor,
    SurfaceArtifactOutcome outcome,
  ) {
    if (outcome is SurfaceArtifactUnavailable) {
      debugPrint(
        '[restage] surface "${descriptor.surfaceSlug}" resolved but its '
        'content could not be fetched (${outcome.reason.wireName})',
      );
      SurfaceDeliveryEvidence.artifactFetchFailed(
        surfaceType: descriptor.surfaceType,
        surfaceSlug: descriptor.surfaceSlug,
        version: descriptor.version,
        reason: outcome.reason.wireName,
      );
    }
    return outcome;
  }

  /// GETs the artifact [descriptor] names, presenting its pass.
  ///
  /// Redirects are NOT followed. A redirect would re-send the pass to whatever
  /// host the response named — and the whole blast radius of a leaked pass is
  /// "one object, ten minutes", which only holds while the pass reaches the
  /// origin the server chose and nobody else.
  Future<Uint8List> _fetchArtifactBytes(
    SurfaceArtifactDescriptorV1 descriptor,
  ) async {
    final request = http.Request('GET', Uri.parse(descriptor.artifactUrl))
      ..followRedirects = false
      ..headers[surfaceArtifactPassHeader] = descriptor.artifactPass;
    final response = await http.Response.fromStream(
      await _client.send(request),
    );
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const _ArtifactFetchRefused(SurfaceArtifactFetchFailure.refused);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const _ArtifactFetchRefused(SurfaceArtifactFetchFailure.status);
    }
    return response.bodyBytes;
  }

  /// Fetches one exact standalone-screen contract family.
  ///
  /// The request and successful response use the strict shared V1 codecs.
  /// Absence and transport unavailability remain distinct from a present
  /// response that is malformed or does not correlate to [request], allowing
  /// callers to apply their own fallback policy without accepting an
  /// untrusted response.
  Future<SurfaceScreenDeliveryResult> fetchSurfaceScreen(
    SurfaceScreenDeliveryRequestV1 request,
  ) async {
    final uri = Uri.parse('$_baseUrl/sdk/v1/surface');
    final body = SurfaceScreenDeliveryRequestV1Codec.encodeCanonicalJson(
      request,
    );

    final http.Response response;
    try {
      response = await _client.post(
        uri,
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: body,
      );
    } on TimeoutException {
      debugPrint(
        '[restage] standalone-screen delivery request failed before a response',
      );
      return const SurfaceScreenDeliveryTransportUnavailable();
    } on http.ClientException {
      debugPrint(
        '[restage] standalone-screen delivery request failed before a response',
      );
      return const SurfaceScreenDeliveryTransportUnavailable();
    } on Object {
      debugPrint(
        '[restage] standalone-screen delivery request failed unexpectedly',
      );
      return const SurfaceScreenDeliveryInvalidResponse(
        SurfaceScreenDeliveryInvalidResponseReason.requestRejected,
      );
    }

    if (response.statusCode == 204 || response.statusCode == 404) {
      return const SurfaceScreenDeliveryAbsent();
    }
    if (_isRetryableSurfaceScreenDeliveryStatus(response.statusCode)) {
      debugPrint(
        '[restage] standalone-screen delivery request failed with '
        'status ${response.statusCode}',
      );
      return const SurfaceScreenDeliveryTransportUnavailable();
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint(
        '[restage] standalone-screen delivery request was rejected with '
        'status ${response.statusCode}',
      );
      return const SurfaceScreenDeliveryInvalidResponse(
        SurfaceScreenDeliveryInvalidResponseReason.requestRejected,
      );
    }

    final SurfaceScreenDeliveryDescriptorV1 described;
    try {
      described = SurfaceScreenDeliveryDescriptorV1Codec.decodeJson(
        response.body,
      );
    } on Object {
      debugPrint('[restage] standalone-screen delivery response was malformed');
      return const SurfaceScreenDeliveryInvalidResponse(
        SurfaceScreenDeliveryInvalidResponseReason.malformed,
      );
    }

    // The content is fetched and assembled through the same seam every other
    // surface uses, and only then handed to the delivery response's own
    // constructor — so the fingerprint is recomputed against the document that
    // was actually assembled out of the fetched bytes, which is the only
    // version of that check that says anything about them.
    final artifact = await _resolveArtifact(described.artifact);
    final SurfaceScreenDeliveryResponseV1 delivery;
    switch (artifact) {
      case SurfaceArtifactAssembled(:final document):
        try {
          delivery = described.completeWith(document);
        } on FormatException {
          debugPrint(
            '[restage] standalone-screen delivery did not match its content',
          );
          return const SurfaceScreenDeliveryInvalidResponse(
            SurfaceScreenDeliveryInvalidResponseReason.malformed,
          );
        }
      case SurfaceArtifactUnavailable():
        // The delivery resolved and its content did not arrive. Treated as
        // transport unavailability, which is what it is, and which is the one
        // classification eligible for the bundled fallback — the alternative
        // would fail a screen the app can render perfectly well offline.
        return const SurfaceScreenDeliveryTransportUnavailable();
      case SurfaceArtifactUndecodable():
        debugPrint('[restage] standalone-screen content was malformed');
        return const SurfaceScreenDeliveryInvalidResponse(
          SurfaceScreenDeliveryInvalidResponseReason.malformed,
        );
    }

    if (delivery.document.surfaceType != request.surface ||
        delivery.document.surfaceSlug != request.slug) {
      debugPrint(
        '[restage] standalone-screen delivery response did not match '
        'the requested identity',
      );
      return const SurfaceScreenDeliveryInvalidResponse(
        SurfaceScreenDeliveryInvalidResponseReason.identityMismatch,
      );
    }
    if (delivery.contractVersion != request.contractVersion) {
      debugPrint(
        '[restage] standalone-screen delivery response did not match '
        'the requested contract version',
      );
      return const SurfaceScreenDeliveryInvalidResponse(
        SurfaceScreenDeliveryInvalidResponseReason.contractMismatch,
      );
    }
    return SurfaceScreenDeliveryAvailable(delivery);
  }

  /// Fetches the active-version stamp for a surface without downloading its
  /// content envelope.
  ///
  /// Returns `null` on any failure so callers can keep their current render.
  Future<SurfaceStamp?> fetchSurfaceStamp({
    required String surfaceType,
    required String surfaceSlug,
  }) async {
    final json = await _postJsonObject(
      path: '/sdk/v1/surface-stamp',
      body: {
        'surfaceType': surfaceType,
        'surfaceSlug': surfaceSlug,
      },
    );
    final version = json?['version'];
    if (version is! int) return null;
    // A malformed watchChannel degrades to a null field, never discards the
    // valid version stamp (a hard cast would throw and lose the whole stamp).
    final rawWatchChannel = json?['watchChannel'];
    return SurfaceStamp(
      version: version,
      watchChannel: rawWatchChannel is String ? rawWatchChannel : null,
    );
  }

  /// Mints a native promotional-offer signature for [request]. Returns the
  /// typed response, or `null` when the request fails — a network error, a
  /// non-2xx status (e.g. the server declined to authorize the offer), or a
  /// malformed body. This is the same fail-closed transport posture as
  /// [reportTransaction]: a `null` is the SDK's signal to treat the offer as
  /// unavailable, never to fall back to a silent full-price purchase.
  Future<OfferSignatureResponse?> mintOfferSignature(
    OfferSignatureRequest request,
  ) async {
    final json = await _postJsonObject(
      path: '/sdk/v1/offer-signature',
      body: request.toJson(),
    );
    if (json == null) return null;
    try {
      return OfferSignatureResponse.fromJson(json);
    } on Object {
      debugPrint('[restage] offer-signature response was malformed');
      return null;
    }
  }

  /// Mints an Apple promotional-offer signature from a durable intent.
  ///
  /// The server derives the immutable product, offer, and account-token tuple
  /// from [request], so no caller-supplied tuple can drift after intent commit.
  Future<OfferSignatureResponse?> mintIntentBoundOfferSignature(
    IntentBoundOfferSignatureRequest request,
  ) async {
    final json = await _postJsonObject(
      path: '/sdk/v1/offer-signature',
      body: request.toJson(),
    );
    if (json == null) return null;
    try {
      return OfferSignatureResponse.fromJson(json);
    } on Object {
      debugPrint('[restage] offer-signature response was malformed');
      return null;
    }
  }

  /// Releases the underlying HTTP resources. Callers that constructed
  /// the client should invoke this when they're done with it; callers
  /// that supplied a custom [http.Client] in the constructor own its
  /// lifecycle and should not call this method.
  void close() => _client.close();

  Future<List<EntitlementSummary>?> _postEntitlements({
    required String path,
    required Map<String, dynamic> body,
  }) async {
    final json = await _postJsonObject(path: path, body: body);
    if (json == null) return null;
    try {
      return _parseEntitlements(json);
    } on Object catch (error) {
      // A 200 with a malformed entitlement entry (the fail-loud
      // EntitlementSummary.fromJson throws) degrades to null rather than
      // throwing out of the call, preserving the transport's fail-closed
      // posture — the SDK keeps local state until the next sync.
      debugPrint('[restage] entitlements from $path were malformed: $error');
      return null;
    }
  }

  /// POSTs [body] as JSON to [path] with bearer auth and returns the decoded
  /// JSON object, or `null` on any failure (network throw, non-2xx status, or a
  /// body that is not a JSON object). The shared fail-closed transport for the
  /// `/sdk/v1` endpoints.
  Future<Map<String, dynamic>?> _postJsonObject({
    required String path,
    required Map<String, dynamic> body,
  }) async {
    final uri = Uri.parse('$_baseUrl$path');
    try {
      final response = await _client.post(
        uri,
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
          '[restage] request to $path failed with '
          'status ${response.statusCode}',
        );
        return null;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        debugPrint('[restage] response from $path was not a JSON object');
        return null;
      }
      return decoded.cast<String, dynamic>();
    } on Object {
      // Transport exceptions can include request details. Keep diagnostics
      // shape-only because transaction requests may carry receipts or tokens.
      debugPrint('[restage] request to $path failed before a response');
      return null;
    }
  }

  static List<EntitlementSummary> _parseEntitlements(
    Map<String, dynamic> json,
  ) {
    final raw = json['entitlements'];
    if (raw is! List) return const [];
    final out = <EntitlementSummary>[];
    for (final entry in raw) {
      if (entry is Map) {
        out.add(EntitlementSummary.fromJson(entry.cast<String, dynamic>()));
      }
    }
    return out;
  }
}

bool _isRetryableSurfaceScreenDeliveryStatus(int statusCode) =>
    switch (statusCode) {
      408 || 429 || 500 || 502 || 503 || 504 => true,
      _ => false,
    };

const bool _debugTransactionReportOutageRequested = bool.fromEnvironment(
  'RESTAGE_DEBUG_FAIL_TRANSACTION_REPORTS',
);

bool _debugTransactionReportOutageEnabled(bool? testOverride) {
  var enabled = false;
  assert(() {
    enabled = testOverride ?? _debugTransactionReportOutageRequested;
    return true;
  }());
  return enabled;
}

bool _evidenceMatchesRequest(
  AcceptedStoreEvidence evidence,
  ReportTransactionRequest request,
) {
  return switch (evidence) {
    AppleAcceptedStoreEvidence(:final submittedTransactionId) =>
      request.store == 'appStore' &&
          submittedTransactionId == request.storeTransactionId,
    GoogleAcceptedStoreEvidence(
      :final submittedOrderId,
      :final acceptedPurchaseTokenDigest,
    ) =>
      request.store == 'playStore' &&
          acceptedPurchaseTokenDigest ==
              googlePurchaseTokenDigest(request.storeVerificationData) &&
          // Deliberately symmetric: an order id present on only one side is a
          // correlation failure, not a bonus.
          submittedOrderId == request.storeTransactionId,
  };
}

final class _SurfaceAssignmentMetadata {
  const _SurfaceAssignmentMetadata({
    this.experimentId,
    this.variantId,
    this.experimentEpoch,
  });

  final String? experimentId;
  final String? variantId;
  final int? experimentEpoch;
}

_SurfaceAssignmentMetadata? _parseSurfaceAssignmentMetadata(
  Map<String, dynamic> json,
) {
  final experimentId = json['experimentId'];
  final variantId = json['variantId'];
  final experimentEpoch = json['experimentEpoch'];
  if (experimentId == null && variantId == null && experimentEpoch == null) {
    return const _SurfaceAssignmentMetadata();
  }
  if (experimentId is! String ||
      variantId is! String ||
      experimentEpoch is! int ||
      experimentEpoch < 1) {
    return null;
  }
  if (!_isValidSurfaceAssignmentToken(experimentId) ||
      !_isValidSurfaceAssignmentToken(variantId)) {
    return null;
  }
  return _SurfaceAssignmentMetadata(
    experimentId: experimentId,
    variantId: variantId,
    experimentEpoch: experimentEpoch,
  );
}

bool _isValidSurfaceAssignmentToken(String value) {
  return value.isNotEmpty && value.trim() == value && !value.contains('\u0000');
}

/// A store answered, and not with the artifact.
final class _ArtifactFetchRefused implements Exception {
  const _ArtifactFetchRefused(this.failure);

  final SurfaceArtifactFetchFailure failure;
}

/// What makes two fetched artifacts the same artifact.
///
/// Both parts, always. The content hash says what the bytes are; the payload
/// format version says what shape they are stored in and which decoder reads
/// them — and it is part of the object's physical location, so the same hash
/// under two formats is two objects.
@immutable
final class _ArtifactIdentity {
  const _ArtifactIdentity({
    required this.payloadFormatVersion,
    required this.contentHash,
  });

  final int payloadFormatVersion;
  final String contentHash;

  @override
  bool operator ==(Object other) =>
      other is _ArtifactIdentity &&
      other.payloadFormatVersion == payloadFormatVersion &&
      other.contentHash == contentHash;

  @override
  int get hashCode => Object.hash(payloadFormatVersion, contentHash);
}
