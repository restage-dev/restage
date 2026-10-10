import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/credentials/credential.dart';
import 'package:restage_cli/src/render_bundles/render_bundle_archive.dart';
import 'package:restage_shared/restage_shared.dart';
// ignore: implementation_imports
import 'package:restage_shared/src/render_bundle/deployed_origin_authority.dart';

/// Exact media type accepted by the local render-bundle upload route.
const renderBundleUploadMediaType = 'application/vnd.restage.render-bundle.v1';

/// A size a bundle exceeded before anything was sent.
@experimental
final class RenderBundleOversize {
  /// Records a measurement against a ceiling.
  const RenderBundleOversize({
    required this.measuredBytes,
    required this.limitBytes,
    required this.compressed,
  });

  /// The size that was measured.
  final int measuredBytes;

  /// The ceiling it exceeded.
  final int limitBytes;

  /// Whether both figures describe the compressed body rather than the archive.
  final bool compressed;
}

/// What one organization already holds staged, and the ceiling it passed.
@experimental
final class RenderBundleStagedBytes {
  /// Records a staging measurement against its ceiling.
  const RenderBundleStagedBytes({
    required this.heldBytes,
    required this.limitBytes,
  });

  /// Staged bytes this organization would have been brought to.
  final int heldBytes;

  /// The most it may hold staged at once.
  final int limitBytes;
}

/// A fail-closed upload failure.
///
/// [statusCode] carries the upload response status when a responder answered,
/// and [oversize] the measurement when the refusal was local. No response
/// body, header, or server message is ever retained.
@experimental
final class RenderBundleUploadException implements Exception {
  const RenderBundleUploadException({this.statusCode, this.transferBytes})
    : oversize = null,
      staged = null;

  /// A refusal the client made itself, before anything went on the wire.
  const RenderBundleUploadException.oversize(RenderBundleOversize this.oversize)
    : statusCode = null,
      transferBytes = null,
      staged = null;

  /// A refusal that names how much the organization already holds staged.
  const RenderBundleUploadException.staged(
    RenderBundleStagedBytes this.staged, {
    this.statusCode,
  }) : oversize = null,
       transferBytes = null;

  /// The upload response status, when the request reached a responder.
  final int? statusCode;

  /// Size of the compressed body that was put on the wire.
  final int? transferBytes;

  /// The measurement that refused the upload locally.
  final RenderBundleOversize? oversize;

  /// The staging measurement the service refused on, when it sent one.
  final RenderBundleStagedBytes? staged;

  @override
  String toString() {
    final staging = staged;
    if (staging != null) {
      return 'RenderBundleUploadException(staged_bytes_exceeded, '
          '${staging.heldBytes} of ${staging.limitBytes})';
    }
    final measurement = oversize;
    if (measurement != null) {
      return 'RenderBundleUploadException(oversize, '
          '${measurement.measuredBytes} of ${measurement.limitBytes})';
    }
    return statusCode == null
        ? 'RenderBundleUploadException(upload_failed)'
        : 'RenderBundleUploadException(upload_failed, status: $statusCode)';
  }
}

/// The status-safe part of one discovered channel head.
@experimental
final class RenderBundleDiscovery {
  const RenderBundleDiscovery({
    required this.version,
    required this.contentHash,
  });

  final int version;
  final String contentHash;
}

/// Status-safe projection of one selected render-bundle channel.
///
/// Bundle and actor identifiers remain behind the authenticated control API.
@experimental
final class RenderBundleChannelDiscovery {
  const RenderBundleChannelDiscovery({
    required this.channel,
    required this.activeVersion,
    required this.updatedAt,
  });

  final String channel;
  final int activeVersion;
  final DateTime updatedAt;
}

/// Reveal-once browser bootstrap prepared by the authenticated control plane.
///
/// The grant is intentionally not serializable and is redacted from
/// [toString]. Callers may submit it only as the body of the exact bootstrap
/// URL; it must never enter render data, environment, or seam messages.
@experimental
final class PreparedRenderBundleBootstrap {
  const PreparedRenderBundleBootstrap({
    required this.renderBundleId,
    required this.bootstrapUrl,
    required this.bootstrapGrant,
    required this.expiresAt,
  });

  final int renderBundleId;
  final Uri bootstrapUrl;
  final String bootstrapGrant;
  final DateTime expiresAt;

  @override
  String toString() =>
      'PreparedRenderBundleBootstrap(renderBundleId: $renderBundleId, '
      'bootstrapUrl: $bootstrapUrl, bootstrapGrant: <redacted>, '
      'expiresAt: $expiresAt)';
}

/// Hand-written control client for the bounded render-bundle upload lane.
@experimental
final class RenderBundleApi {
  RenderBundleApi({
    required RestageApi rpc,
    required Uri apiEndpoint,
    required Credential credential,
    Uri? trustedBundleOrigin,
    http.Client? uploadClient,
  }) : _rpc = rpc,
       _apiEndpoint = apiEndpoint,
       _credential = credential,
       _trustedBundleOrigin = trustedBundleOrigin,
       _uploadClient = uploadClient ?? http.Client();

  final RestageApi _rpc;
  final Uri _apiEndpoint;
  final Credential _credential;
  final Uri? _trustedBundleOrigin;
  final http.Client _uploadClient;

  /// Prepares and performs one raw channel upload without retry.
  Future<void> upload({
    required String project,
    required String channel,
    required Uint8List archive,
    int? organizationId,
  }) async {
    if (!isValidRenderBundleChannel(channel) || archive.isEmpty) {
      throw const RenderBundleUploadException();
    }
    if (archive.length > renderBundleMaxArchiveBytes) {
      throw RenderBundleUploadException.oversize(
        RenderBundleOversize(
          measuredBytes: archive.length,
          limitBytes: renderBundleMaxArchiveBytes,
          compressed: false,
        ),
      );
    }

    try {
      final authorization = _authorizationHeader(_credential);
      final raw = await _rpc
          .call('renderBundle', 'prepareUpload', <String, dynamic>{
            'projectSlug': project,
            'channel': channel,
            'organizationId': ?organizationId,
          });
      if (raw is! String) throw const RenderBundleUploadException();
      final uploadUri = _validatedUploadUri(
        raw,
        apiEndpoint: _apiEndpoint,
        trustedBundleOrigin: _trustedBundleOrigin,
        project: project,
        channel: channel,
        organizationId: organizationId,
      );
      // The raw container goes on the wire gzipped: the serving platform
      // refuses a single request body over 32 MiB, and a Flutter web bundle
      // is comfortably past that. Compression is TRANSPORT ONLY - the
      // RBSRAW1 container, its content hash, and the deterministic
      // double-build comparison all remain defined on the raw bytes.
      final transfer = Uint8List.fromList(gzip.encode(archive));
      if (transfer.length > renderBundleMaxUploadTransferBytes) {
        // Past the single-request ceiling the stream is split into parts and
        // reassembled server-side, which the whole-archive hash then has to
        // match before anything is stored.
        await _uploadInParts(
          project: project,
          channel: channel,
          organizationId: organizationId,
          uploadUri: uploadUri,
          authorization: authorization,
          transfer: transfer,
          contentHash: 'sha256:${crypto.sha256.convert(archive)}',
        );
        return;
      }
      final request = http.Request('POST', uploadUri)
        ..followRedirects = false
        ..maxRedirects = 0
        ..headers['authorization'] = authorization
        ..headers['content-type'] = renderBundleUploadMediaType
        ..headers['content-encoding'] = 'gzip'
        ..bodyBytes = transfer;
      final response = await _uploadClient.send(request);
      var empty = true;
      await for (final chunk in response.stream) {
        if (chunk.isNotEmpty) {
          empty = false;
          break;
        }
      }
      if (response.statusCode != 204 ||
          (response.contentLength != null && response.contentLength != 0) ||
          !empty) {
        throw RenderBundleUploadException(
          statusCode: response.statusCode,
          transferBytes: transfer.length,
        );
      }
    } on RenderBundleUploadException {
      rethrow;
    } on Object {
      throw const RenderBundleUploadException();
    }
  }

  /// Splits one compressed stream into parts and commits it by hash.
  ///
  /// Nothing is stored until the server reassembles the parts and agrees on
  /// [contentHash]; a failure discards the staged parts.
  Future<void> _uploadInParts({
    required String project,
    required String channel,
    required int? organizationId,
    required Uri uploadUri,
    required String authorization,
    required Uint8List transfer,
    required String contentHash,
  }) async {
    final prepared = await _rpc.call(
      'renderBundle',
      'prepareChunkedUpload',
      <String, dynamic>{
        'projectSlug': project,
        'channel': channel,
        'organizationId': ?organizationId,
      },
    );
    if (prepared is! Map<String, dynamic>) {
      throw const RenderBundleUploadException();
    }
    final uploadId = prepared['uploadId'];
    final nonce = prepared['nonce'];
    final expiresAtSource = prepared['expiresAt'];
    final partByteLimit = prepared['partByteLimit'];
    final maxParts = prepared['maxParts'];
    final expiresAt = expiresAtSource is String
        ? DateTime.tryParse(expiresAtSource)
        : null;
    if (uploadId is! String ||
        !RegExp(r'^[0-9a-f]{32}$').hasMatch(uploadId) ||
        nonce is! String ||
        !RegExp(r'^[0-9a-f]{32}$').hasMatch(nonce) ||
        expiresAt == null ||
        partByteLimit is! int ||
        partByteLimit < 1 ||
        maxParts is! int ||
        maxParts < 1) {
      throw const RenderBundleUploadException();
    }
    // The prepared part URL must be the same authority the whole-archive URL
    // was validated against; only the part coordinates may differ.
    if (prepared['uploadUrl'] != uploadUri.toString()) {
      throw const RenderBundleUploadException();
    }

    final partCount = (transfer.length + partByteLimit - 1) ~/ partByteLimit;
    if (partCount > maxParts) {
      // Chunking removes the single-request ceiling; what is left is the
      // service's total, and it is still worth reporting with its figures.
      throw RenderBundleUploadException.oversize(
        RenderBundleOversize(
          measuredBytes: transfer.length,
          limitBytes: partByteLimit * maxParts,
          compressed: true,
        ),
      );
    }

    for (var index = 0; index < partCount; index++) {
      final start = index * partByteLimit;
      final end = start + partByteLimit < transfer.length
          ? start + partByteLimit
          : transfer.length;
      final body = Uint8List.sublistView(transfer, start, end);
      // Re-staging a part with identical bytes is accepted, so a part that
      // fails in transit is worth one more attempt before the whole upload is
      // thrown away.
      var sent = false;
      RenderBundleUploadException? laneRefusal;
      for (var attempt = 0; attempt < 2 && !sent; attempt++) {
        try {
          await _sendPart(
            uploadUri: uploadUri,
            authorization: authorization,
            uploadId: uploadId,
            nonce: nonce,
            expiresAt: expiresAt,
            partIndex: index,
            partCount: partCount,
            body: body,
          );
          sent = true;
        } on RenderBundleUploadException catch (error) {
          // A busy lane means the service wants this part to wait its turn.
          // The upload is still sound, so it is retried like a transport
          // failure.
          if (error.statusCode == 429 || error.statusCode == 503) {
            laneRefusal = error;
            continue;
          }
          // Any other refusal is the server's answer.
          await _discardParts(
            project: project,
            uploadId: uploadId,
            organizationId: organizationId,
          );
          rethrow;
        } on Object {
          // Transport failure; the next attempt re-stages the same bytes.
        }
      }
      if (!sent) {
        // Every exit discards, including one the transport threw.
        await _discardParts(
          project: project,
          uploadId: uploadId,
          organizationId: organizationId,
        );
        throw laneRefusal ?? const RenderBundleUploadException();
      }
    }

    try {
      await _rpc.call('renderBundle', 'commitChunkedUpload', <String, dynamic>{
        'projectSlug': project,
        'uploadId': uploadId,
        'nonce': nonce,
        'expiresAt': expiresAt.toUtc().toIso8601String(),
        'contentHash': contentHash,
        'channel': channel,
        'organizationId': ?organizationId,
      });
    } on Object {
      await _discardParts(
        project: project,
        uploadId: uploadId,
        organizationId: organizationId,
      );
      throw const RenderBundleUploadException();
    }
  }

  /// Sends one part, applying the response checks the whole-archive path makes.
  Future<void> _sendPart({
    required Uri uploadUri,
    required String authorization,
    required String uploadId,
    required String nonce,
    required DateTime expiresAt,
    required int partIndex,
    required int partCount,
    required Uint8List body,
  }) async {
    final request =
        http.Request(
            'POST',
            _partUri(
              uploadUri,
              uploadId: uploadId,
              nonce: nonce,
              expiresAt: expiresAt,
              partIndex: partIndex,
              partCount: partCount,
            ),
          )
          ..followRedirects = false
          ..maxRedirects = 0
          ..headers['authorization'] = authorization
          ..headers['content-type'] = renderBundleUploadMediaType
          ..bodyBytes = body;
    final response = await _uploadClient.send(request);
    final answer = await response.stream.toBytes();
    if (response.statusCode != 204 ||
        (response.contentLength != null && response.contentLength != 0) ||
        answer.isNotEmpty) {
      throw _partRefusal(response.statusCode, answer);
    }
  }

  /// Reads a typed refusal, falling back to the status when there is none.
  RenderBundleUploadException _partRefusal(int statusCode, Uint8List answer) {
    if (answer.isNotEmpty) {
      try {
        final decoded = jsonDecode(utf8.decode(answer));
        if (decoded is Map<String, Object?> &&
            decoded['reason'] == 'staged_bytes_exceeded') {
          final held = decoded['heldBytes'];
          final limit = decoded['limitBytes'];
          if (held is int && limit is int) {
            return RenderBundleUploadException.staged(
              RenderBundleStagedBytes(heldBytes: held, limitBytes: limit),
              statusCode: statusCode,
            );
          }
        }
      } on Object {
        // A body that will not parse is no worse than none: the status stands.
      }
    }
    return RenderBundleUploadException(statusCode: statusCode);
  }

  Future<void> _discardParts({
    required String project,
    required String uploadId,
    required int? organizationId,
  }) async {
    try {
      await _rpc.call('renderBundle', 'discardChunkedUpload', <String, dynamic>{
        'projectSlug': project,
        'uploadId': uploadId,
        'organizationId': ?organizationId,
      });
    } on Object {
      // The server discards staged parts on its own failure paths; a failed
      // courtesy discard must not replace the original refusal.
    }
  }

  /// Compatibility convenience for the default channel.
  Future<void> uploadMain({
    required String project,
    required Uint8List archive,
    int? organizationId,
  }) => upload(
    project: project,
    channel: renderBundleMainChannel,
    archive: archive,
    organizationId: organizationId,
  );

  /// Reads the selected channel head for status-only confirmation.
  Future<RenderBundleDiscovery?> discover({
    required String project,
    required String channel,
    int? organizationId,
  }) async {
    if (!isValidRenderBundleChannel(channel)) {
      throw const RenderBundleUploadException();
    }
    try {
      final raw = await _rpc.call('renderBundle', 'discover', <String, dynamic>{
        'projectSlug': project,
        'channel': channel,
        'organizationId': ?organizationId,
      });
      if (raw == null) return null;
      if (raw is! Map<String, dynamic>) {
        throw const RenderBundleUploadException();
      }
      final version = raw['version'];
      final contentHash = raw['contentHash'];
      if (version is! int ||
          version < 1 ||
          contentHash is! String ||
          !RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(contentHash)) {
        throw const RenderBundleUploadException();
      }
      return RenderBundleDiscovery(version: version, contentHash: contentHash);
    } on RenderBundleUploadException {
      rethrow;
    } on Object {
      throw const RenderBundleUploadException();
    }
  }

  /// Compatibility convenience for the default channel.
  Future<RenderBundleDiscovery?> discoverMain({
    required String project,
    int? organizationId,
  }) => discover(
    project: project,
    channel: renderBundleMainChannel,
    organizationId: organizationId,
  );

  /// Lists selected channels through a status-safe, token-free projection.
  Future<List<RenderBundleChannelDiscovery>> listChannels({
    required String project,
    int? organizationId,
  }) async {
    if (project.isEmpty || (organizationId != null && organizationId < 1)) {
      throw const RenderBundleUploadException();
    }
    try {
      final raw = await _rpc.call(
        'renderBundle',
        'listChannels',
        <String, dynamic>{
          'projectSlug': project,
          'organizationId': ?organizationId,
        },
      );
      if (raw is! List<dynamic>) {
        throw const RenderBundleUploadException();
      }
      final channels = <RenderBundleChannelDiscovery>[];
      final seen = <String>{};
      for (final item in raw) {
        if (item is! Map<String, dynamic>) {
          throw const RenderBundleUploadException();
        }
        final channel = item['channel'];
        final activeRenderBundleId = item['activeRenderBundleId'];
        final activeVersion = item['activeVersion'];
        final updatedByUserInfoId = item['updatedByUserInfoId'];
        final updatedAtSource = item['updatedAt'];
        final updatedAt = updatedAtSource is String
            ? DateTime.tryParse(updatedAtSource)
            : null;
        if (channel is! String ||
            !isValidRenderBundleChannel(channel) ||
            !seen.add(channel) ||
            activeRenderBundleId is! int ||
            activeRenderBundleId < 1 ||
            activeVersion is! int ||
            activeVersion < 1 ||
            updatedByUserInfoId is! int ||
            updatedByUserInfoId < 1 ||
            updatedAt == null ||
            !updatedAt.isUtc) {
          throw const RenderBundleUploadException();
        }
        channels.add(
          RenderBundleChannelDiscovery(
            channel: channel,
            activeVersion: activeVersion,
            updatedAt: updatedAt,
          ),
        );
      }
      return List<RenderBundleChannelDiscovery>.unmodifiable(channels);
    } on RenderBundleUploadException {
      rethrow;
    } on Object {
      throw const RenderBundleUploadException();
    }
  }

  /// Mints one reveal-once bootstrap after exact per-bundle origin validation.
  Future<PreparedRenderBundleBootstrap> prepareBrowserBootstrap({
    required String project,
    required String channel,
    required Uri trustedBundleOrigin,
    int? organizationId,
    int? version,
  }) async {
    if (project.isEmpty ||
        !isValidRenderBundleChannel(channel) ||
        (organizationId != null && organizationId < 1) ||
        (version != null && version < 1) ||
        !_isExactTrustedBundleOrigin(trustedBundleOrigin) ||
        !canDeriveRenderBundleExecutionOrigin(trustedBundleOrigin) ||
        !_isAllowedApiControlPair(
          apiEndpoint: _apiEndpoint,
          trustedBundleOrigin: trustedBundleOrigin,
        )) {
      throw const RenderBundleUploadException();
    }
    try {
      final raw = await _rpc
          .call('renderBundle', 'prepareBrowserBootstrap', <String, dynamic>{
            'projectSlug': project,
            'channel': channel,
            'version': ?version,
            'organizationId': ?organizationId,
          });
      if (raw is! Map<String, dynamic>) {
        throw const RenderBundleUploadException();
      }
      final renderBundleId = raw['renderBundleId'];
      final bootstrapUrlSource = raw['bootstrapUrl'];
      final bootstrapGrant = raw['bootstrapGrant'];
      final expiresAtSource = raw['expiresAt'];
      final bootstrapUrl = bootstrapUrlSource is String
          ? Uri.tryParse(bootstrapUrlSource)
          : null;
      final expiresAt = expiresAtSource is String
          ? DateTime.tryParse(expiresAtSource)?.toUtc()
          : null;
      final expectedExecutionOrigin = renderBundleId is int
          ? deriveRenderBundleExecutionOrigin(
              trustedBundleOrigin,
              renderBundleId,
            )
          : null;
      if (renderBundleId is! int ||
          renderBundleId < 1 ||
          bootstrapUrl == null ||
          expectedExecutionOrigin == null ||
          bootstrapUrl.origin != expectedExecutionOrigin.origin ||
          bootstrapUrl.userInfo.isNotEmpty ||
          bootstrapUrl.hasQuery ||
          bootstrapUrl.hasFragment ||
          bootstrapUrl.path !=
              '/render-bundles/v1/b/$renderBundleId/bootstrap' ||
          bootstrapGrant is! String ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(bootstrapGrant) ||
          expiresAt == null) {
        throw const RenderBundleUploadException();
      }
      return PreparedRenderBundleBootstrap(
        renderBundleId: renderBundleId,
        bootstrapUrl: bootstrapUrl,
        bootstrapGrant: bootstrapGrant,
        expiresAt: expiresAt,
      );
    } on RenderBundleUploadException {
      rethrow;
    } on Object {
      throw const RenderBundleUploadException();
    }
  }

  void close() => _uploadClient.close();
}

String _authorizationHeader(Credential credential) {
  if (credential.kind != CredentialKind.authKey) {
    throw const RenderBundleUploadException();
  }
  return 'Basic ${base64Encode(utf8.encode(credential.authToken))}';
}

Uri _validatedUploadUri(
  String source, {
  required Uri apiEndpoint,
  required Uri? trustedBundleOrigin,
  required String project,
  required String channel,
  required int? organizationId,
}) {
  final uri = Uri.tryParse(source);
  if (uri == null ||
      !_isAllowedUploadPair(
        apiEndpoint: apiEndpoint,
        uploadUri: uri,
        trustedBundleOrigin: trustedBundleOrigin,
      ) ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment ||
      uri.path != '/render-bundles/v1/upload') {
    throw const RenderBundleUploadException();
  }

  final query = uri.queryParametersAll;
  if (query.length != 3 ||
      query.keys.any(
        (key) =>
            key != 'projectSlug' && key != 'organizationId' && key != 'channel',
      ) ||
      query['projectSlug']?.length != 1 ||
      query['projectSlug']!.single != project ||
      query['organizationId']?.length != 1 ||
      query['channel']?.length != 1 ||
      query['channel']!.single != channel) {
    throw const RenderBundleUploadException();
  }
  final organizationSource = query['organizationId']!.single;
  final preparedOrganizationId = int.tryParse(organizationSource);
  if (preparedOrganizationId == null ||
      preparedOrganizationId <= 0 ||
      organizationSource != '$preparedOrganizationId' ||
      (organizationId != null && preparedOrganizationId != organizationId)) {
    throw const RenderBundleUploadException();
  }
  final canonicalQuery = Uri(
    queryParameters: <String, String>{
      'projectSlug': project,
      'organizationId': organizationSource,
      'channel': channel,
    },
  ).query;
  if (uri.query != canonicalQuery) {
    throw const RenderBundleUploadException();
  }
  return uri;
}

bool _isAllowedUploadPair({
  required Uri apiEndpoint,
  required Uri uploadUri,
  required Uri? trustedBundleOrigin,
}) =>
    trustedBundleOrigin != null &&
    _isExactTrustedBundleOrigin(trustedBundleOrigin) &&
    _isAllowedApiControlPair(
      apiEndpoint: apiEndpoint,
      trustedBundleOrigin: trustedBundleOrigin,
    ) &&
    uploadUri.origin == trustedBundleOrigin.origin;

bool _isAllowedApiControlPair({
  required Uri apiEndpoint,
  required Uri trustedBundleOrigin,
}) =>
    isApprovedRenderBundleLocalApiControlPair(
      apiEndpoint,
      trustedBundleOrigin,
    ) ||
    isApprovedRenderBundleDeployedOriginPair(apiEndpoint, trustedBundleOrigin);

bool _isDefaultHttps(Uri uri) =>
    uri.isAbsolute && uri.scheme == 'https' && !uri.hasPort;

bool _isExactTrustedBundleOrigin(Uri uri) {
  if (!uri.isAbsolute ||
      uri.userInfo.isNotEmpty ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      uri.hasQuery ||
      uri.hasFragment) {
    return false;
  }
  return _isDefaultHttps(uri) || canDeriveRenderBundleExecutionOrigin(uri);
}

/// Adds the part coordinates to a validated upload URL in canonical order.
Uri _partUri(
  Uri uploadUri, {
  required String uploadId,
  required String nonce,
  required DateTime expiresAt,
  required int partIndex,
  required int partCount,
}) => uploadUri.replace(
  queryParameters: <String, String>{
    ...uploadUri.queryParameters,
    'uploadId': uploadId,
    'nonce': nonce,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'partIndex': '$partIndex',
    'partCount': '$partCount',
  },
);
