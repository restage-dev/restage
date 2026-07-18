import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:restage_shared/restage_shared.dart';

import '../secure_transport.dart';

/// Result of a successful hosted surface fetch.
final class SurfaceFetchResult {
  /// Creates a hosted surface fetch result.
  const SurfaceFetchResult({
    required this.envelopeBytes,
    this.decision,
    this.experimentId,
    this.variantId,
    this.experimentEpoch,
    this.contractRequired = false,
  });

  /// Base64-decoded `SurfaceDocument` envelope bytes.
  final Uint8List envelopeBytes;

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
/// confusing it with "server says nothing's entitled". There is no
/// retry-with-backoff in the client, by design — the server's
/// transaction store is the durable backstop and the next sync
/// converges the SDK's view.
class RestageRpcClient {
  /// Creates a client targeting [baseUrl] and authenticating as [apiKey].
  ///
  /// [httpClient] is the seam tests use to inject `MockClient`; production
  /// callers omit it and a default [http.Client] is constructed.
  RestageRpcClient({
    required String baseUrl,
    required String apiKey,
    http.Client? httpClient,
  })  : _baseUrl = baseUrl,
        _apiKey = apiKey,
        _client = httpClient ?? http.Client() {
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

  /// Reports a completed store transaction. Returns the authoritative
  /// entitlement set from the server's response, or `null` when the
  /// request fails — the SDK reconciles via the next sync.
  Future<List<EntitlementSummary>?> reportTransaction(
    ReportTransactionRequest request,
  ) =>
      _postEntitlements(
        path: '/sdk/v1/reportTransaction',
        body: request.toJson(),
      );

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
  }) async {
    final json = await _postJsonObject(
      path: '/sdk/v1/surface',
      body: {
        'surfaceType': surfaceType,
        'surfaceSlug': surfaceSlug,
        if (version != null) 'version': version,
        if (assignmentKey != null) 'assignmentKey': assignmentKey,
        if (contractHash != null) 'contractHash': contractHash,
        if (contract != null) 'contract': contract.toJson(),
      },
    );
    if (json == null) return null;
    final envelope = json['envelope'];
    if (envelope is! String) {
      debugPrint('[restage] surface response missing the envelope field');
      return null;
    }
    try {
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
      return SurfaceFetchResult(
        envelopeBytes: base64Decode(envelope),
        decision: decision,
        experimentId: assignment.experimentId,
        variantId: assignment.variantId,
        experimentEpoch: assignment.experimentEpoch,
        contractRequired: contractRequired,
      );
    } on FormatException catch (error) {
      debugPrint('[restage] surface envelope was not valid base64: $error');
      return null;
    }
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
    } on Object catch (error) {
      debugPrint('[restage] offer-signature response was malformed: $error');
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
    } on Object catch (error) {
      debugPrint('[restage] request to $path threw: $error');
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
