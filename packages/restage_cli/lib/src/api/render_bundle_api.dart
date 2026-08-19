import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

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

/// A fail-closed upload failure whose rendering contains no server detail.
@experimental
final class RenderBundleUploadException implements Exception {
  const RenderBundleUploadException();

  @override
  String toString() => 'RenderBundleUploadException(upload_failed)';
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
    if (!isValidRenderBundleChannel(channel) ||
        archive.isEmpty ||
        archive.length > renderBundleMaxArchiveBytes) {
      throw const RenderBundleUploadException();
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
        throw const RenderBundleUploadException();
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
        throw const RenderBundleUploadException();
      }
    } on RenderBundleUploadException {
      rethrow;
    } on Object {
      throw const RenderBundleUploadException();
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
        !canDeriveMaxSignedRenderBundleExecutionOrigin(trustedBundleOrigin) ||
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
  return _isDefaultHttps(uri) ||
      canDeriveMaxSignedRenderBundleExecutionOrigin(uri);
}
