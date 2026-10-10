import 'dart:convert';
import 'dart:io' show InternetAddress, gzip;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:restage_cli/src/api/discovery_models.dart';
import 'package:restage_cli/src/api/restage_api.dart';
import 'package:restage_cli/src/api/typed_error_models.dart';
import 'package:restage_cli/src/credentials/credential.dart';
import 'package:restage_cli/src/render_bundles/bundle_source.dart';
import 'package:restage_cli/src/render_bundles/flutter_render_bundle_builder.dart';
import 'package:restage_cli/src/render_bundles/push_target.dart';
import 'package:restage_shared/restage_shared.dart';
// ignore: implementation_imports
import 'package:restage_shared/src/render_bundle/deployed_origin_authority.dart';

/// The two routes a prepared push may name for bytes.
const _uploadRoutes = <String>{
  '/render-bundles/v1/blob',
  '/render-bundles/v1/engine-file',
};

/// Exact media type accepted by the local render-bundle upload route.
const renderBundleUploadMediaType = 'application/vnd.restage.render-bundle.v1';

/// Header carrying the token one prepared push uploads under.
const renderBundleUploadTokenHeader = 'x-restage-upload-token';

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

  /// Whether both figures describe the compressed body on the wire.
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
  const RenderBundleUploadException({
    this.statusCode,
    this.transferBytes,
    this.reason,
    this.storage,
    this.targetSelection,
    this.incomplete = false,
  }) : oversize = null,
       staged = null;

  /// A refusal the client made itself, before anything went on the wire.
  const RenderBundleUploadException.oversize(RenderBundleOversize this.oversize)
    : statusCode = null,
      transferBytes = null,
      staged = null,
      reason = null,
      storage = null,
      targetSelection = null,
      incomplete = false;

  /// A refusal that names how much the organization already holds staged.
  const RenderBundleUploadException.staged(
    RenderBundleStagedBytes this.staged, {
    this.statusCode,
  }) : oversize = null,
       transferBytes = null,
       reason = null,
       storage = null,
       targetSelection = null,
       incomplete = false;

  /// The upload response status, when the request reached a responder.
  final int? statusCode;

  /// Size of the compressed body that was put on the wire.
  final int? transferBytes;

  /// The measurement that refused the upload locally.
  final RenderBundleOversize? oversize;

  /// The staging measurement the service refused on, when it sent one.
  final RenderBundleStagedBytes? staged;

  /// The short machine reason the service named, when it named one.
  final String? reason;

  /// The storage figures, when the refusal was about room.
  final RenderBundleStorageRefusal? storage;

  /// The target refusal, when the service could not match the selectors.
  final TargetSelectionRefused? targetSelection;

  /// Whether the bytes are stored and only the version was not selected.
  final bool incomplete;

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

/// How many times a push re-prepares when a blob vanished under it.
const _filesMissingRounds = 3;
const _filesMissingReason = 'files_missing';

/// How long a refused upload waits before its one retry.
const _uploadRetryDelay = Duration(milliseconds: 750);

/// The shape a refusal reason has to have before it reaches the terminal.
final _refusalReasonPattern = RegExp(r'^[a-z_]{1,64}$');

/// What a push moved, and how much of it the server already held.
@experimental
final class RenderBundlePushOutcome {
  const RenderBundlePushOutcome({
    required this.version,
    required this.contentHash,
    required this.organizationId,
    required this.organizationSlug,
    required this.headReference,
    required this.reactivated,
    required this.appFilesSent,
    required this.appFilesHeld,
    required this.engineFilesSent,
  });

  /// The version this push selected.
  final int version;

  /// The content hash that version carries.
  final String contentHash;

  /// The organization the push was filed under.
  final int organizationId;

  /// That organization's slug.
  final String organizationSlug;

  /// The head it moved, in its canonical text form.
  final String headReference;

  /// Whether an identical build already existed.
  final bool reactivated;

  /// App files whose bytes went on the wire.
  final int appFilesSent;

  /// App files the server already held.
  final int appFilesHeld;

  /// Engine files this push seeded.
  final int engineFilesSent;
}

/// Why a version cannot be evicted to make room for a push.
@experimental
final class RenderBundleProtectedHolder {
  const RenderBundleProtectedHolder({
    required this.kind,
    required this.label,
    required this.version,
    required this.byteLength,
  });

  /// `environmentHead`, `personalHead` or `replacedVersion`.
  final String kind;

  /// The head reference, or the version that replaced it.
  final String label;

  /// The version being held.
  final int version;

  /// What it occupies.
  final int byteLength;
}

/// A push refused because the organization is out of room.
@experimental
final class RenderBundleStorageRefusal {
  const RenderBundleStorageRefusal({
    required this.usedBytes,
    required this.limitBytes,
    required this.neededBytes,
    required this.holders,
    required this.evictedVersionIds,
  });

  final int usedBytes;
  final int limitBytes;
  final int neededBytes;

  /// Everything the storage policy may not evict.
  final List<RenderBundleProtectedHolder> holders;

  /// Versions no head pointed at that the attempt removed before refusing.
  final List<int> evictedVersionIds;
}

/// The status-safe part of one discovered head.
@experimental
final class RenderBundleDiscovery {
  const RenderBundleDiscovery({
    required this.version,
    required this.contentHash,
  });

  final int version;
  final String contentHash;
}

/// Status-safe projection of one head an app holds.
///
/// Bundle and actor identifiers remain behind the authenticated control API.
@experimental
final class RenderBundleHeadDiscovery {
  const RenderBundleHeadDiscovery({
    required this.head,
    required this.version,
    required this.libraries,
    required this.updatedAt,
    this.ownerDisplayName,
    this.sourceCommit,
    this.sourceDirty = false,
  });

  /// The head reference: an environment slug, or `user/<handle>`.
  final String head;

  /// The version this head points at.
  final int version;

  /// The app widget libraries that version registers, by namespace, at the
  /// capability version each declares.
  final Map<String, int> libraries;

  /// When it last moved.
  final DateTime updatedAt;

  /// Whose head it is, for a personal head.
  final String? ownerDisplayName;

  /// The commit the version was built from, when the push knew it.
  final String? sourceCommit;

  /// Whether that commit's tree carried local changes.
  final bool sourceDirty;

  /// The head as JSON, its time in UTC.
  Map<String, Object?> toJson() => <String, Object?>{
    'head': head,
    'version': version,
    'sourceCommit': sourceCommit,
    'sourceDirty': sourceDirty,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'owner': ownerDisplayName,
    'libraries': libraries,
  };
}

/// Whether an app's build for one environment registers what a published
/// surface draws with.
@experimental
final class RenderBundleCoverageDiscovery {
  const RenderBundleCoverageDiscovery({
    required this.required,
    required this.headVersion,
    required this.registered,
  });

  /// The app widget libraries the surface requires, by namespace, at the
  /// capability version each needs.
  final Map<String, int> required;

  /// The version the environment head points at, or null with no build.
  final int? headVersion;

  /// The libraries that version registers, by namespace, at the capability
  /// version each declares.
  final Map<String, int> registered;
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

/// Hand-written control client for the bounded render-bundle upload path.
///
/// Calls go through [rpc], and uploads carry its credential.
@experimental
final class RenderBundleApi {
  RenderBundleApi({
    required RestageApi rpc,
    Uri? trustedBundleOrigin,
    http.Client? uploadClient,
    Future<void> Function(Duration)? delay,
  }) : _rpc = rpc,
       _trustedBundleOrigin = trustedBundleOrigin,
       _uploadClient = uploadClient ?? http.Client(),
       _delay = delay ?? Future<void>.delayed;

  final RestageApi _rpc;
  final Uri? _trustedBundleOrigin;
  final http.Client _uploadClient;

  /// Waits out the pause before a retry; a test supplies its own.
  final Future<void> Function(Duration) _delay;

  /// Pushes one built bundle: what the server lacks, then the version.
  Future<RenderBundlePushOutcome> push({
    required String project,
    required String app,
    required BundlePushTarget target,
    required RenderBundleArtifact artifact,
    required BundleSource source,
    int? organizationId,
  }) async {
    if (app.isEmpty || artifact.appFiles.isEmpty) {
      throw const RenderBundleUploadException();
    }
    final manifest = <Map<String, Object?>>[
      for (final path in artifact.appFiles.keys.toList()..sort())
        <String, Object?>{
          'path': path,
          'contentHash': _hashOf(artifact.appFiles[path]!),
          'byteLength': artifact.appFiles[path]!.length,
        },
    ];
    final byHash = <String, Uint8List>{
      for (final bytes in artifact.appFiles.values) _hashOf(bytes): bytes,
    };

    var round = 0;
    // A round that runs again sends the same bytes again, so the figures
    // count what moved, by hash and by path.
    final appHashesSent = <String>{};
    final enginePathsSent = <String>{};
    while (true) {
      round++;
      final ticket = await _prepare(
        project: project,
        app: app,
        target: target,
        artifact: artifact,
        source: source,
        manifest: manifest,
        organizationId: organizationId,
      );
      appHashesSent.addAll(
        await _sendMissing(
          ticket: ticket,
          uri: ticket.blobUploadUrl,
          bodies: <String, Uint8List>{
            for (final hash in ticket.missingContentHashes)
              hash: byHash[hash] ?? (throw const RenderBundleUploadException()),
          },
          field: 'contentHash',
        ),
      );
      enginePathsSent.addAll(
        await _sendMissing(
          ticket: ticket,
          uri: ticket.engineUploadUrl,
          bodies: <String, Uint8List>{
            for (final path in ticket.missingEnginePaths)
              path:
                  artifact.engineFiles[path] ??
                  (throw const RenderBundleUploadException()),
          },
          field: 'path',
        ),
      );
      final result = await _commit(ticket.uploadToken, manifest);
      if (result != null) {
        return RenderBundlePushOutcome(
          version: result.version,
          contentHash: result.contentHash,
          organizationId: result.organizationId,
          organizationSlug: result.organizationSlug,
          headReference: result.headReference,
          reactivated: result.reactivated,
          appFilesSent: appHashesSent.length,
          // Held is a count of files, so it counts manifest entries; two
          // files with the same bytes move once and neither is held.
          appFilesHeld: manifest
              .where((entry) => !appHashesSent.contains(entry['contentHash']))
              .length,
          engineFilesSent: enginePathsSent.length,
        );
      }
      // A cleanup pass or an eviction removed a blob between the two calls.
      if (round >= _filesMissingRounds) {
        throw const RenderBundleUploadException(incomplete: true);
      }
    }
  }

  Future<_UploadTicket> _prepare({
    required String project,
    required String app,
    required BundlePushTarget target,
    required RenderBundleArtifact artifact,
    required BundleSource source,
    required List<Map<String, Object?>> manifest,
    required int? organizationId,
  }) async {
    final Object? raw;
    try {
      raw = await _rpc.call('renderBundleUpload', 'prepare', <String, dynamic>{
        'projectSlug': project,
        'appSlug': app,
        'environment': ?target.environment,
        'personal': target.personal,
        'engineSetId': artifact.engineSetId,
        'manifest': manifest,
        'provenance': <String, Object?>{
          'sourceCommit': ?source.commit,
          'sourceDirty': source.dirty,
        },
        'organizationId': ?organizationId,
      });
    } on RestageApiException catch (error) {
      throw _refusal(error);
    } on Object {
      throw const RenderBundleUploadException();
    }
    final ticket = _UploadTicket.from(raw);
    if (ticket == null) throw const RenderBundleUploadException();
    return ticket;
  }

  /// Returns the push result, or null when the server wants the files again.
  ///
  /// The manifest goes back with the token: the version's file rows are
  /// written from it, and the server checks it still hashes to what the token
  /// carries.
  Future<_PushResult?> _commit(
    String uploadToken,
    List<Map<String, Object?>> manifest,
  ) async {
    final Object? raw;
    try {
      raw = await _rpc.call('renderBundleUpload', 'commit', <String, dynamic>{
        'uploadToken': uploadToken,
        'manifest': manifest,
      });
    } on RestageApiException catch (error) {
      final refusal = _refusal(error);
      if (refusal.reason == _filesMissingReason) return null;
      throw refusal;
    } on Object {
      throw const RenderBundleUploadException();
    }
    final result = _PushResult.from(raw);
    if (result == null) throw const RenderBundleUploadException();
    return result;
  }

  /// Sends every body the ticket named, [ticket.uploadConcurrency] at a time,
  /// and returns the keys that moved.
  Future<Set<String>> _sendMissing({
    required _UploadTicket ticket,
    required String uri,
    required Map<String, Uint8List> bodies,
    required String field,
  }) async {
    if (bodies.isEmpty) return const <String>{};
    final address = _validatedUploadUri(uri, _trustedBundleOrigin);
    for (final bytes in bodies.values) {
      if (bytes.length > ticket.maxFileTransferBytes) {
        throw RenderBundleUploadException.oversize(
          RenderBundleOversize(
            measuredBytes: bytes.length,
            limitBytes: ticket.maxFileTransferBytes,
            compressed: false,
          ),
        );
      }
    }
    final pending = bodies.entries.toList();
    var next = 0;
    Future<void> worker() async {
      while (true) {
        final index = next++;
        if (index >= pending.length) return;
        await _sendOne(
          address: address,
          token: ticket.uploadToken,
          field: field,
          key: pending[index].key,
          bytes: pending[index].value,
        );
      }
    }

    final workers = ticket.uploadConcurrency < pending.length
        ? ticket.uploadConcurrency
        : pending.length;
    await Future.wait(<Future<void>>[
      for (var index = 0; index < workers; index++) worker(),
    ]);
    return bodies.keys.toSet();
  }

  /// Sends one file, retrying once because the same bytes are accepted twice.
  /// The retry waits: a 429, a 503 and a dropped connection all clear sooner
  /// when nothing asks again straight away.
  Future<void> _sendOne({
    required Uri address,
    required String token,
    required String field,
    required String key,
    required Uint8List bytes,
  }) async {
    final transfer = Uint8List.fromList(gzip.encode(bytes));
    RenderBundleUploadException? refusal;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        if (attempt > 0) await _delay(_uploadRetryDelay);
        final request =
            http.Request(
                'POST',
                address.replace(
                  queryParameters: <String, String>{
                    ...address.queryParameters,
                    field: key,
                  },
                ),
              )
              ..followRedirects = false
              ..maxRedirects = 0
              ..headers['authorization'] = _authorizationHeader(_rpc.credential)
              // A token is a capability, so it stays out of the query and the
              // access logs that record one.
              ..headers[renderBundleUploadTokenHeader] = token
              ..headers['content-type'] = renderBundleUploadMediaType
              ..headers['content-encoding'] = 'gzip'
              ..bodyBytes = transfer;
        final response = await _uploadClient.send(request);
        final answer = await response.stream.toBytes();
        if (response.statusCode == 204 && answer.isEmpty) return;
        final status = response.statusCode;
        if (status != 429 && status != 503) {
          throw RenderBundleUploadException(
            statusCode: status,
            transferBytes: transfer.length,
          );
        }
        refusal = RenderBundleUploadException(
          statusCode: status,
          transferBytes: transfer.length,
        );
      } on RenderBundleUploadException {
        rethrow;
      } on Object {
        // Transport failure; the next attempt sends the same bytes again.
      }
    }
    throw refusal ?? const RenderBundleUploadException();
  }

  /// Reads the head for status-only confirmation.
  Future<RenderBundleDiscovery?> discover({
    required String project,
    required String app,
    required String head,
    int? organizationId,
  }) async {
    if (app.isEmpty || !isValidRenderBundleHead(head)) {
      throw const RenderBundleUploadException();
    }
    try {
      final raw = await _rpc.call('renderBundle', 'discover', <String, dynamic>{
        'projectSlug': project,
        'appSlug': app,
        'head': head,
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

  /// Lists the heads one app holds, environment heads first.
  Future<List<RenderBundleHeadDiscovery>> listHeads({
    required String project,
    required String app,
    int? organizationId,
    String? organizationSlug,
  }) async {
    if (project.isEmpty ||
        app.isEmpty ||
        (organizationId != null && organizationId < 1)) {
      throw const RenderBundleUploadException();
    }
    try {
      final raw = await _rpc
          .call('renderBundle', 'listHeads', <String, dynamic>{
            'projectSlug': project,
            'appSlug': app,
            'organizationId': ?organizationId,
            'organizationSlug': ?organizationSlug,
          });
      if (raw is! Map<String, dynamic>) {
        throw const RenderBundleUploadException();
      }
      final heads = <RenderBundleHeadDiscovery>[];
      final seen = <String>{};
      for (final key in const <String>['environmentHeads', 'personalHeads']) {
        final items = raw[key];
        if (items is! List<dynamic>) {
          throw const RenderBundleUploadException();
        }
        for (final item in items) {
          heads.add(_readHead(item, seen: seen));
        }
      }
      return List<RenderBundleHeadDiscovery>.unmodifiable(heads);
    } on RenderBundleUploadException {
      rethrow;
    } on Object {
      throw const RenderBundleUploadException();
    }
  }

  /// Reads whether the app's build for [environment] registers what the
  /// published [surfaceSlug] draws with.
  Future<RenderBundleCoverageDiscovery> coverage({
    required String project,
    required String app,
    required SurfaceType surfaceType,
    required String surfaceSlug,
    required String environment,
    int? environmentTargetId,
    RuntimePlane? runtimePlane,
    int? organizationId,
  }) async {
    if (project.isEmpty ||
        app.isEmpty ||
        surfaceSlug.isEmpty ||
        environment.isEmpty ||
        (organizationId != null && organizationId < 1)) {
      throw const RenderBundleUploadException();
    }
    try {
      final raw = await _rpc.call('renderBundle', 'coverage', <String, dynamic>{
        'projectSlug': project,
        'appSlug': app,
        'surfaceType': surfaceType.wireName,
        'surfaceSlug': surfaceSlug,
        'environmentSlug': environment,
        if (environmentTargetId != null)
          'environmentTargetId': environmentTargetId,
        if (runtimePlane != null) 'runtimePlane': runtimePlane.wireName,
        'organizationId': ?organizationId,
      });
      final coverage = _readCoverage(raw);
      if (coverage == null) throw const RenderBundleUploadException();
      return coverage;
    } on RenderBundleUploadException {
      rethrow;
    } on Object {
      throw const RenderBundleUploadException();
    }
  }

  /// Mints one reveal-once bootstrap after exact per-bundle origin validation.
  Future<PreparedRenderBundleBootstrap> prepareBrowserBootstrap({
    required String project,
    required String app,
    required String head,
    required Uri trustedBundleOrigin,
    int? organizationId,
    String? organizationSlug,
    int? version,
  }) async {
    if (project.isEmpty ||
        app.isEmpty ||
        !isValidRenderBundleHead(head) ||
        (organizationId != null && organizationId < 1) ||
        (version != null && version < 1) ||
        !_isExactTrustedBundleOrigin(trustedBundleOrigin) ||
        !canDeriveRenderBundleExecutionOrigin(trustedBundleOrigin) ||
        !_isAllowedApiControlPair(
          apiEndpoint: _rpc.endpoint,
          trustedBundleOrigin: trustedBundleOrigin,
        )) {
      throw const RenderBundleUploadException();
    }
    try {
      final raw = await _rpc
          .call('renderBundle', 'prepareBrowserBootstrap', <String, dynamic>{
            'projectSlug': project,
            'appSlug': app,
            'head': head,
            'version': ?version,
            'organizationId': ?organizationId,
            'organizationSlug': ?organizationSlug,
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

/// Reads one head view, refusing anything the projection does not admit.
RenderBundleHeadDiscovery _readHead(Object? item, {required Set<String> seen}) {
  if (item is! Map<String, dynamic>) {
    throw const RenderBundleUploadException();
  }
  final head = item['head'];
  final versionView = item['version'];
  final owner = item['ownerDisplayName'];
  final updatedAtSource = item['updatedAt'];
  final updatedAt = updatedAtSource is String
      ? DateTime.tryParse(updatedAtSource)
      : null;
  final version = versionView is Map<String, dynamic>
      ? versionView['version']
      : null;
  final libraries = versionView is Map<String, dynamic>
      ? _registeredLibraries(versionView['capabilityManifestJson'])
      : null;
  final sourceCommit = versionView is Map<String, dynamic>
      ? versionView['sourceCommit']
      : null;
  final sourceDirty = versionView is Map<String, dynamic>
      ? versionView['sourceDirty']
      : null;
  if (head is! String ||
      !isValidRenderBundleHead(head) ||
      !seen.add(head) ||
      version is! int ||
      version < 1 ||
      libraries == null ||
      (sourceCommit != null && !_isCommitText(sourceCommit)) ||
      sourceDirty is! bool ||
      (owner != null && owner is! String) ||
      updatedAt == null ||
      !updatedAt.isUtc) {
    throw const RenderBundleUploadException();
  }
  return RenderBundleHeadDiscovery(
    head: head,
    version: version,
    libraries: libraries,
    updatedAt: updatedAt,
    ownerDisplayName: owner as String?,
    sourceCommit: sourceCommit as String?,
    sourceDirty: sourceDirty,
  );
}

final _commitTextPattern = RegExp(r'^[0-9a-f]{7,40}$');

bool _isCommitText(Object? value) =>
    value is String && _commitTextPattern.hasMatch(value);

RenderBundleCoverageDiscovery? _readCoverage(Object? raw) {
  if (raw is! Map<String, dynamic>) return null;
  final headVersion = raw['headVersion'];
  if (headVersion != null && (headVersion is! int || headVersion < 1)) {
    return null;
  }
  final required = _namespacedVersions(raw['requiredLibraries'], 'minVersion');
  final registered = _namespacedVersions(
    raw['registeredLibraries'],
    'capabilityVersion',
  );
  if (required == null || registered == null) return null;
  return RenderBundleCoverageDiscovery(
    required: required,
    headVersion: headVersion as int?,
    registered: registered,
  );
}

Map<String, int>? _namespacedVersions(Object? items, String versionKey) {
  if (items is! List) return null;
  final versions = <String, int>{};
  for (final item in items) {
    if (item is! Map<String, dynamic>) return null;
    final namespace = item['namespace'];
    final version = item[versionKey];
    if (namespace is! String ||
        namespace.isEmpty ||
        version is! int ||
        version < 1) {
      return null;
    }
    versions[namespace] = version;
  }
  return Map<String, int>.unmodifiable(versions);
}

/// The libraries a stored capability manifest registers, or null when the
/// manifest is not the shape the server admits.
Map<String, int>? _registeredLibraries(Object? manifestJson) {
  if (manifestJson is! String) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(manifestJson);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, dynamic>) return null;
  final catalog = decoded['catalog'];
  if (catalog is! Map<String, dynamic>) return null;
  final libraries = catalog['libraries'];
  if (libraries is! Map<String, dynamic>) return null;
  final registered = <String, int>{};
  for (final entry in libraries.entries) {
    final library = entry.value;
    if (library is! Map<String, dynamic>) return null;
    final capabilityVersion = library['capabilityVersion'] ?? 1;
    if (capabilityVersion is! int || capabilityVersion < 1) return null;
    registered[entry.key] = capabilityVersion;
  }
  return Map<String, int>.unmodifiable(registered);
}

/// The ticket a prepared push answers with.
final class _UploadTicket {
  const _UploadTicket({
    required this.uploadToken,
    required this.headReference,
    required this.blobUploadUrl,
    required this.engineUploadUrl,
    required this.missingContentHashes,
    required this.missingEnginePaths,
    required this.uploadConcurrency,
    required this.maxFileTransferBytes,
  });

  static _UploadTicket? from(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final uploadToken = raw['uploadToken'];
    final headReference = raw['headReference'];
    final blobUploadUrl = raw['blobUploadUrl'];
    final engineUploadUrl = raw['engineUploadUrl'];
    final uploadConcurrency = raw['uploadConcurrency'];
    final maxFileTransferBytes = raw['maxFileTransferBytes'];
    final hashes = _stringList(raw['missingContentHashes']);
    final paths = _stringList(raw['missingEnginePaths']);
    if (uploadToken is! String ||
        uploadToken.isEmpty ||
        headReference is! String ||
        !isValidRenderBundleHead(headReference) ||
        blobUploadUrl is! String ||
        engineUploadUrl is! String ||
        uploadConcurrency is! int ||
        uploadConcurrency < 1 ||
        maxFileTransferBytes is! int ||
        maxFileTransferBytes < 1 ||
        hashes == null ||
        paths == null) {
      return null;
    }
    return _UploadTicket(
      uploadToken: uploadToken,
      headReference: headReference,
      blobUploadUrl: blobUploadUrl,
      engineUploadUrl: engineUploadUrl,
      missingContentHashes: hashes,
      missingEnginePaths: paths,
      uploadConcurrency: uploadConcurrency,
      maxFileTransferBytes: maxFileTransferBytes,
    );
  }

  final String uploadToken;
  final String headReference;
  final String blobUploadUrl;
  final String engineUploadUrl;
  final List<String> missingContentHashes;
  final List<String> missingEnginePaths;
  final int uploadConcurrency;
  final int maxFileTransferBytes;
}

/// The version a committed push selected.
final class _PushResult {
  const _PushResult({
    required this.version,
    required this.contentHash,
    required this.organizationId,
    required this.organizationSlug,
    required this.headReference,
    required this.reactivated,
  });

  static _PushResult? from(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final view = raw['version'];
    final organizationId = raw['organizationId'];
    final organizationSlug = raw['organizationSlug'];
    final headReference = raw['headReference'];
    final reactivated = raw['reactivated'];
    final version = view is Map<String, dynamic> ? view['version'] : null;
    final contentHash = view is Map<String, dynamic>
        ? view['contentHash']
        : null;
    if (version is! int ||
        version < 1 ||
        contentHash is! String ||
        !RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(contentHash) ||
        organizationId is! int ||
        organizationId < 1 ||
        organizationSlug is! String ||
        organizationSlug.isEmpty ||
        headReference is! String ||
        !isValidRenderBundleHead(headReference) ||
        reactivated is! bool) {
      return null;
    }
    return _PushResult(
      version: version,
      contentHash: contentHash,
      organizationId: organizationId,
      organizationSlug: organizationSlug,
      headReference: headReference,
      reactivated: reactivated,
    );
  }

  final int version;
  final String contentHash;
  final int organizationId;
  final String organizationSlug;
  final String headReference;
  final bool reactivated;
}

List<String>? _stringList(Object? raw) {
  if (raw is! List<dynamic>) return null;
  final values = <String>[];
  for (final item in raw) {
    if (item is! String || item.isEmpty) return null;
    values.add(item);
  }
  return values;
}

String _hashOf(Uint8List bytes) => 'sha256:${crypto.sha256.convert(bytes)}';

/// The app environment target the calling API key belongs to.
Future<ApiKeyTarget> readApiKeyTarget(RestageApi rpc) async {
  final Object? raw;
  try {
    raw = await rpc.call(
      'renderBundleUpload',
      'keyTarget',
      <String, dynamic>{},
    );
  } on RestageApiException catch (error) {
    throw _refusal(error);
  } on Object {
    throw const RenderBundleUploadException();
  }
  if (raw is! Map<String, dynamic>) throw const RenderBundleUploadException();
  try {
    return ApiKeyTarget.fromJson(raw);
  } on Object {
    throw const RenderBundleUploadException();
  }
}

/// The scope a key needs to push a render bundle.
const renderBundlePushScope = 'renderBundlesPush';

/// The dashboard origin a build answers and the origin its files upload to.
typedef RenderBundleOrigins = ({Uri dashboardOrigin, Uri bundleOrigin});

/// Reads the origins this server's builds trust.
///
/// Each must be a bare http(s) origin on the API's own site: a loopback host
/// when the API is local http, otherwise https under the API host's parent
/// domain.
Future<RenderBundleOrigins> readRenderBundleOrigins(RestageApi rpc) async {
  final Object? raw;
  try {
    raw = await rpc.call('renderBundleUpload', 'origins', <String, dynamic>{});
  } on RestageApiException catch (error) {
    throw _refusal(error);
  } on Object {
    throw const RenderBundleUploadException();
  }
  if (raw is Map<String, dynamic>) {
    final local = rpc.endpoint.scheme == 'http';
    final dashboard = _origin(raw['dashboardOrigin'], allowHttp: local);
    final bundle = _origin(raw['bundleOrigin'], allowHttp: local);
    if (dashboard != null &&
        bundle != null &&
        isSameSiteOrigin(dashboard, rpc.endpoint) &&
        isSameSiteOrigin(bundle, rpc.endpoint)) {
      return (dashboardOrigin: dashboard, bundleOrigin: bundle);
    }
  }
  throw const RenderBundleUploadException();
}

Uri? _origin(Object? source, {required bool allowHttp}) {
  final uri = source is String ? Uri.tryParse(source) : null;
  if (uri == null ||
      !(uri.scheme == 'https' || (allowHttp && uri.scheme == 'http')) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      uri.hasQuery ||
      uri.hasFragment) {
    return null;
  }
  return Uri.parse(uri.origin);
}

/// Whether [origin] belongs to the site [api] is served from.
///
/// A local http API pairs only with loopback hosts. Otherwise [origin] must
/// sit at or under the API host's parent domain (the API host itself when it
/// has only two labels, or is an address).
@visibleForTesting
bool isSameSiteOrigin(Uri origin, Uri api) {
  final host = origin.host.toLowerCase();
  final apiHost = api.host.toLowerCase();
  if (api.scheme == 'http') {
    return _isLoopbackHost(apiHost) && _isLoopbackHost(host);
  }
  if (origin.scheme != 'https') return false;
  if (InternetAddress.tryParse(apiHost) != null) return host == apiHost;
  final labels = apiHost.split('.');
  final site = labels.length > 2 ? labels.skip(1).join('.') : apiHost;
  return host == site || host.endsWith('.$site');
}

bool _isLoopbackHost(String host) =>
    host == 'localhost' ||
    host.endsWith('.localhost') ||
    (InternetAddress.tryParse(host)?.isLoopback ?? false);

/// Reads a refusal into its short reason and figures, keeping server prose out.
RenderBundleUploadException _refusal(RestageApiException error) {
  final Object? document;
  try {
    document = jsonDecode(error.body);
  } on FormatException {
    return RenderBundleUploadException(statusCode: error.statusCode);
  }
  if (document is! Map<String, dynamic>) {
    return RenderBundleUploadException(statusCode: error.statusCode);
  }
  final data = document['data'];
  if (data is! Map<String, dynamic>) {
    return RenderBundleUploadException(statusCode: error.statusCode);
  }
  switch (document['className']) {
    case 'RenderBundleRejectedException':
      final reason = data['reason'];
      return RenderBundleUploadException(
        statusCode: error.statusCode,
        // The reason reaches the terminal, so only a short name gets through.
        reason: reason is String && _refusalReasonPattern.hasMatch(reason)
            ? reason
            : null,
      );
    case 'TargetSelectionRefusedException':
      final GenericTypedException? typed;
      try {
        typed = decodeGenericTypedException(error.body);
      } on Object {
        break;
      }
      if (typed is! TargetSelectionRefused) break;
      return RenderBundleUploadException(
        statusCode: error.statusCode,
        targetSelection: typed,
      );
    case 'RenderBundleStorageLimitException':
      final storage = _storageRefusal(data);
      if (storage == null) break;
      return RenderBundleUploadException(
        statusCode: error.statusCode,
        storage: storage,
      );
  }
  return RenderBundleUploadException(statusCode: error.statusCode);
}

RenderBundleStorageRefusal? _storageRefusal(Map<String, dynamic> data) {
  final used = data['usedBytes'];
  final limit = data['limitBytes'];
  final needed = data['neededBytes'];
  final entries = data['protectedHolders'];
  final evicted = data['evictedVersionIds'];
  if (used is! int ||
      limit is! int ||
      needed is! int ||
      entries is! List ||
      evicted is! List) {
    return null;
  }
  final evictedVersionIds = <int>[];
  for (final id in evicted) {
    if (id is! int) return null;
    evictedVersionIds.add(id);
  }
  final holders = <RenderBundleProtectedHolder>[];
  for (final entry in entries) {
    if (entry is! Map<String, dynamic>) return null;
    final kind = entry['kind'];
    final label = entry['label'];
    final version = entry['version'];
    final byteLength = entry['byteLength'];
    if (kind is! String ||
        label is! String ||
        version is! int ||
        byteLength is! int) {
      return null;
    }
    holders.add(
      RenderBundleProtectedHolder(
        kind: kind,
        label: label,
        version: version,
        byteLength: byteLength,
      ),
    );
  }
  return RenderBundleStorageRefusal(
    usedBytes: used,
    limitBytes: limit,
    neededBytes: needed,
    holders: List<RenderBundleProtectedHolder>.unmodifiable(holders),
    evictedVersionIds: List<int>.unmodifiable(evictedVersionIds),
  );
}

String _authorizationHeader(Credential? credential) =>
    switch (credential?.kind) {
      CredentialKind.authKey =>
        'Basic ${base64Encode(utf8.encode(credential!.authToken))}',
      CredentialKind.secretKey => 'Bearer ${credential!.authToken}',
      _ => throw const RenderBundleUploadException(),
    };

/// The upload address the ticket names, when it is on the trusted origin.
Uri _validatedUploadUri(String source, Uri? trustedBundleOrigin) {
  final uri = Uri.tryParse(source);
  if (uri == null ||
      trustedBundleOrigin == null ||
      (uri.scheme != 'https' && uri.scheme != 'http') ||
      !uri.hasAuthority ||
      uri.origin != trustedBundleOrigin.origin ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment ||
      uri.hasQuery ||
      !_uploadRoutes.contains(uri.path)) {
    throw const RenderBundleUploadException();
  }
  return uri;
}

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
