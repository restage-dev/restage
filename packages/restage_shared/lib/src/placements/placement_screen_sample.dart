import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/src/entitlements/commerce_wire.dart';
import 'package:restage_shared/src/placements/placement_delivery.dart';
import 'package:restage_shared/src/placements/placement_geometry.dart';
import 'package:restage_shared/src/render_bundle/bounded_png.dart';

/// Maximum canonical manifest bytes in one authored screen sample.
const int placementScreenSampleMaxManifestBytes = 64 * 1024;

/// Maximum transferred occurrences in one sample, independent of app size.
const int placementScreenSampleMaxMounts = 128;

const int _maximumEnvelopeBytes = kMaximumPlacementRequestBytes +
    placementScreenSampleMaxManifestBytes +
    1024;

/// The Flutter coordinate frame captured by an authored sample.
enum PlacementScreenCaptureScopeV1 {
  /// The complete Flutter view.
  flutterView,

  /// An explicitly selected capture boundary.
  explicitBoundary,
}

/// Whether an original mount rectangle fits entirely in its sample viewport.
enum SampleClipping {
  /// The complete rectangle is visible.
  inside,

  /// Some or all of the rectangle lies outside the viewport.
  clipped,
}

/// One occurrence of an exact placement and host in the captured frame.
final class PlacementSampleMountV1 extends _SampleValue {
  /// Creates bounded source geometry without accepting derived clipping facts.
  PlacementSampleMountV1({
    required this.key,
    required this.hostContractHash,
    required this.rect,
    required this.occurrenceIndex,
  }) : _viewport = null {
    _requireHash(hostContractHash, 'hostContractHash');
    _requireInteger(occurrenceIndex, 'occurrenceIndex');
  }

  PlacementSampleMountV1._inViewport(
    PlacementSampleMountV1 source,
    PlacementLogicalSizeV1 viewport,
  )   : key = source.key,
        hostContractHash = source.hostContractHash,
        rect = source.rect,
        occurrenceIndex = source.occurrenceIndex,
        _viewport = viewport;

  /// Decodes the closed source-geometry object.
  factory PlacementSampleMountV1.fromJson(Object? value) {
    final reader = _reader(value, _keys, 'sampleMount');
    return PlacementSampleMountV1(
      key: PlacementKeyV1.fromJson(reader.object('key')),
      hostContractHash: reader.string('hostContractHash'),
      rect: _construct(
        () => PlacementLogicalRectV1.fromJson(reader.object('rect')),
      ),
      occurrenceIndex: reader.integer('occurrenceIndex'),
    );
  }

  /// Decodes only exact canonical bytes.
  factory PlacementSampleMountV1.fromCanonicalBytes(List<int> bytes) =>
      _decode(bytes, PlacementSampleMountV1.fromJson);

  static const _keys = {'key', 'hostContractHash', 'rect', 'occurrenceIndex'};

  /// Namespace-qualified placement identity.
  final PlacementKeyV1 key;

  /// Exact host contract hash with the `sha256:` prefix.
  final String hostContractHash;

  /// Original same-frame geometry; offscreen positions are preserved.
  final PlacementLogicalRectV1 rect;

  /// Sample-local occurrence of this placement and host.
  final int occurrenceIndex;

  final PlacementLogicalSizeV1? _viewport;

  /// Clipping derived from the enclosing capture or manifest's viewport.
  ///
  /// A standalone mount uses [clippingFor] until it is part of a frame.
  SampleClipping get clipping => clippingFor(_boundViewport);

  /// Visible intersection in the enclosing frame; null when wholly outside.
  ///
  /// A standalone mount uses [overlayRectFor] until it is part of a frame.
  PlacementLogicalRectV1? get overlayRect => overlayRectFor(_boundViewport);

  PlacementLogicalSizeV1 get _boundViewport =>
      _viewport ??
      (throw StateError('The sample mount has no enclosing frame.'));

  /// Derives clipping against a supplied viewport without changing the source.
  SampleClipping clippingFor(PlacementLogicalSizeV1 viewport) =>
      rect.xUnits >= 0 &&
              rect.yUnits >= 0 &&
              rect.xUnits + rect.widthUnits <= viewport.widthUnits &&
              rect.yUnits + rect.heightUnits <= viewport.heightUnits
          ? SampleClipping.inside
          : SampleClipping.clipped;

  /// Computes a positive visible intersection, or null for no visible area.
  PlacementLogicalRectV1? overlayRectFor(PlacementLogicalSizeV1 viewport) {
    final left = math.max(0, rect.xUnits);
    final top = math.max(0, rect.yUnits);
    final right = math.min(viewport.widthUnits, rect.xUnits + rect.widthUnits);
    final bottom =
        math.min(viewport.heightUnits, rect.yUnits + rect.heightUnits);
    if (right <= left || bottom <= top) return null;
    return PlacementLogicalRectV1(
      xUnits: left,
      yUnits: top,
      widthUnits: right - left,
      heightUnits: bottom - top,
    );
  }

  @override
  Map<String, Object?> toJson() => {
        'key': key.toJson(),
        'hostContractHash': hostContractHash,
        'rect': rect.toJson(),
        'occurrenceIndex': occurrenceIndex,
      };
}

/// Immutable target-free capture evidence and the complete offline declaration.
final class PlacementScreenCaptureV1 extends _SampleFrame {
  /// Creates a capture, verifying its build hash and every mount declaration.
  PlacementScreenCaptureV1({
    required this.buildContract,
    required super.appBuildContractHash,
    required super.screenLabel,
    required super.captureScope,
    required super.logicalViewport,
    required super.rasterScale,
    required super.pngWidth,
    required super.pngHeight,
    required super.pngByteLength,
    required super.pngSha256,
    required super.mounts,
  }) {
    _validateBuild(buildContract, this);
    _requireBytes(canonicalBytes.length, _maximumEnvelopeBytes);
  }

  /// Decodes a closed target-free capture and verifies its full declaration.
  factory PlacementScreenCaptureV1.fromJson(Object? value) {
    final reader = _reader(value, _keys, 'screenCapture');
    return _construct(
      () => PlacementScreenCaptureV1(
        buildContract:
            PlacementBuildContractV1.fromJson(reader.object('buildContract')),
        appBuildContractHash: reader.string('appBuildContractHash'),
        screenLabel: reader.string('screenLabel'),
        captureScope: _enum(
          reader.string('captureScope'),
          PlacementScreenCaptureScopeV1.values,
        ),
        logicalViewport:
            PlacementLogicalSizeV1.fromJson(reader.object('logicalViewport')),
        rasterScale:
            PlacementRasterScaleV1.fromJson(reader.object('rasterScale')),
        pngWidth: reader.integer('pngWidth'),
        pngHeight: reader.integer('pngHeight'),
        pngByteLength: reader.integer('pngByteLength'),
        pngSha256: reader.string('pngSha256'),
        mounts: _readMounts(reader),
      ),
    );
  }

  /// Decodes only exact canonical bytes.
  factory PlacementScreenCaptureV1.fromCanonicalBytes(List<int> bytes) =>
      _decode(bytes, PlacementScreenCaptureV1.fromJson);

  static const Set<String> _keys = {..._SampleFrame.keys, 'buildContract'};

  /// Full immutable renderer and host declaration, without target or reports.
  final PlacementBuildContractV1 buildContract;

  /// Binds verified capture facts to an authoring tool's resolved exact target.
  PlacementScreenSampleManifestV1 bindTarget(TargetCoordinate target) {
    _validateBuild(buildContract, this);
    return PlacementScreenSampleManifestV1(
      target: target,
      appBuildContractHash: appBuildContractHash,
      screenLabel: screenLabel,
      captureScope: captureScope,
      logicalViewport: logicalViewport,
      rasterScale: rasterScale,
      pngWidth: pngWidth,
      pngHeight: pngHeight,
      pngByteLength: pngByteLength,
      pngSha256: pngSha256,
      mounts: mounts,
    );
  }

  @override
  Map<String, Object?> toJson() => {
        ..._frameJson(),
        'buildContract': buildContract.toJson(),
      };
}

/// Exact target-bound frame and image evidence for an authored screen sample.
final class PlacementScreenSampleManifestV1 extends _SampleFrame {
  /// Creates a bounded manifest with immutable canonical mount occurrences.
  PlacementScreenSampleManifestV1({
    required this.target,
    required super.appBuildContractHash,
    required super.screenLabel,
    required super.captureScope,
    required super.logicalViewport,
    required super.rasterScale,
    required super.pngWidth,
    required super.pngHeight,
    required super.pngByteLength,
    required super.pngSha256,
    required super.mounts,
  }) {
    _requireBytes(canonicalBytes.length, placementScreenSampleMaxManifestBytes);
  }

  /// Decodes one closed target-bound manifest.
  factory PlacementScreenSampleManifestV1.fromJson(Object? value) {
    final reader = _reader(value, _keys, 'sampleManifest');
    return _construct(
      () => PlacementScreenSampleManifestV1(
        target: TargetCoordinate.fromJson(reader.object('target')),
        appBuildContractHash: reader.string('appBuildContractHash'),
        screenLabel: reader.string('screenLabel'),
        captureScope: _enum(
          reader.string('captureScope'),
          PlacementScreenCaptureScopeV1.values,
        ),
        logicalViewport:
            PlacementLogicalSizeV1.fromJson(reader.object('logicalViewport')),
        rasterScale:
            PlacementRasterScaleV1.fromJson(reader.object('rasterScale')),
        pngWidth: reader.integer('pngWidth'),
        pngHeight: reader.integer('pngHeight'),
        pngByteLength: reader.integer('pngByteLength'),
        pngSha256: reader.string('pngSha256'),
        mounts: _readMounts(reader),
      ),
    );
  }

  /// Decodes exact canonical manifest bytes within the 64 KiB limit.
  factory PlacementScreenSampleManifestV1.fromCanonicalBytes(List<int> bytes) =>
      _decode(
        bytes,
        PlacementScreenSampleManifestV1.fromJson,
        maxBytes: placementScreenSampleMaxManifestBytes,
      );

  static const Set<String> _keys = {..._SampleFrame.keys, 'target'};

  /// Exact resolved authoring target; the coordinate does not grant access.
  final TargetCoordinate target;

  /// SHA-256 of UTF-8 `restage.placement-screen-sample-manifest.v1`, NUL,
  /// then the exact canonical manifest bytes, with the `sha256:` prefix.
  late final String manifestDigest = _domainHash(
    'restage.placement-screen-sample-manifest.v1',
    canonicalBytes,
  );

  /// SHA-256 of UTF-8 `restage.placement-screen-sample-review.v1`, NUL,
  /// then canonical `{manifest, pngSha256}`, with the `sha256:` prefix.
  late final String reviewDigest = _domainHash(
    'restage.placement-screen-sample-review.v1',
    CanonicalJsonCodec.encode({'manifest': toJson(), 'pngSha256': pngSha256}),
  );

  /// Rebuilds and validates a manifest with selected evidence replaced.
  PlacementScreenSampleManifestV1 copyWith({
    TargetCoordinate? target,
    String? appBuildContractHash,
    String? screenLabel,
    PlacementScreenCaptureScopeV1? captureScope,
    PlacementLogicalSizeV1? logicalViewport,
    PlacementRasterScaleV1? rasterScale,
    int? pngWidth,
    int? pngHeight,
    int? pngByteLength,
    String? pngSha256,
    List<PlacementSampleMountV1>? mounts,
  }) =>
      PlacementScreenSampleManifestV1(
        target: target ?? this.target,
        appBuildContractHash: appBuildContractHash ?? this.appBuildContractHash,
        screenLabel: screenLabel ?? this.screenLabel,
        captureScope: captureScope ?? this.captureScope,
        logicalViewport: logicalViewport ?? this.logicalViewport,
        rasterScale: rasterScale ?? this.rasterScale,
        pngWidth: pngWidth ?? this.pngWidth,
        pngHeight: pngHeight ?? this.pngHeight,
        pngByteLength: pngByteLength ?? this.pngByteLength,
        pngSha256: pngSha256 ?? this.pngSha256,
        mounts: mounts ?? this.mounts,
      );

  @override
  Map<String, Object?> toJson() => {'target': target.toJson(), ..._frameJson()};
}

/// Validated actual PNG bytes and the exact immutable reviewed manifest.
final class ValidatedPlacementScreenSampleV1 {
  ValidatedPlacementScreenSampleV1._({
    required this.manifest,
    required this.pngBytes,
  }) : _manifestBytes = manifest.canonicalBytes.asUnmodifiableView();

  /// Exact immutable manifest used during image validation.
  final PlacementScreenSampleManifestV1 manifest;

  /// Defensive immutable PNG bytes validated by the bounded decoder.
  final Uint8List pngBytes;

  final Uint8List _manifestBytes;

  /// A fresh copy of the canonical validated manifest bytes.
  Uint8List get manifestCanonicalBytes => Uint8List.fromList(_manifestBytes);

  /// Commitment to the exact canonical manifest.
  String get manifestDigest => manifest.manifestDigest;

  /// Commitment to the explicitly reviewed manifest and image evidence.
  String get reviewDigest => manifest.reviewDigest;
}

/// Validates actual image bytes, exact dimensions, hash, length and layout fit.
ValidatedPlacementScreenSampleV1 validatePlacementScreenSample({
  required PlacementScreenSampleManifestV1 manifest,
  required Uint8List pngBytes,
}) {
  final png = validatePlacementScreenSamplePng(pngBytes);
  if (png.width != manifest.pngWidth ||
      png.height != manifest.pngHeight ||
      !placementRasterExtentIsConsistent(
        pixels: png.width,
        logicalUnits: manifest.logicalViewport.widthUnits,
        scale: manifest.rasterScale,
      ) ||
      !placementRasterExtentIsConsistent(
        pixels: png.height,
        logicalUnits: manifest.logicalViewport.heightUnits,
        scale: manifest.rasterScale,
      )) {
    throw const FormatException('sample_raster_frame_mismatch');
  }
  if (png.contentHash != manifest.pngSha256 ||
      png.byteLength != manifest.pngByteLength) {
    throw const FormatException('sample_image_digest_mismatch');
  }
  return ValidatedPlacementScreenSampleV1._(
    manifest: manifest,
    pngBytes: png.bytes,
  );
}

/// A canonical local review-file envelope with its complete build declaration.
final class PlacementSampleDraftV1 extends _ReviewedSample {
  /// Creates a draft whose digest and declarations match its exact manifest.
  PlacementSampleDraftV1({
    required super.manifest,
    required super.buildContract,
    required super.reviewedDigest,
  });

  /// Decodes a closed draft and verifies the reviewed commitment.
  factory PlacementSampleDraftV1.fromJson(Object? value) {
    final reader = _reader(value, _ReviewedSample.keys, 'sampleDraft');
    return PlacementSampleDraftV1(
      manifest:
          PlacementScreenSampleManifestV1.fromJson(reader.object('manifest')),
      buildContract:
          PlacementBuildContractV1.fromJson(reader.object('buildContract')),
      reviewedDigest: reader.string('reviewedDigest'),
    );
  }

  /// Decodes only exact canonical bytes.
  factory PlacementSampleDraftV1.fromCanonicalBytes(List<int> bytes) =>
      _decode(bytes, PlacementSampleDraftV1.fromJson);

  @override
  Map<String, Object?> toJson() => _reviewedJson();
}

/// Request to prepare a reviewed upload under separate authoring authority.
final class PlacementSamplePrepareV1 extends _ReviewedSample {
  /// Creates a reviewed request with a canonical lowercase UUIDv4 operation.
  PlacementSamplePrepareV1({
    required super.manifest,
    required super.buildContract,
    required super.reviewedDigest,
    required this.operationId,
  }) {
    _requireId(operationId, 'operationId');
  }

  /// Decodes a closed prepare request and verifies its build and review digest.
  factory PlacementSamplePrepareV1.fromJson(Object? value) {
    final reader = _reader(value, _keys, 'samplePrepare');
    return PlacementSamplePrepareV1(
      manifest:
          PlacementScreenSampleManifestV1.fromJson(reader.object('manifest')),
      buildContract:
          PlacementBuildContractV1.fromJson(reader.object('buildContract')),
      reviewedDigest: reader.string('reviewedDigest'),
      operationId: reader.string('operationId'),
    );
  }

  /// Decodes only exact canonical bytes.
  factory PlacementSamplePrepareV1.fromCanonicalBytes(List<int> bytes) =>
      _decode(bytes, PlacementSamplePrepareV1.fromJson);

  static const Set<String> _keys = {..._ReviewedSample.keys, 'operationId'};

  /// Canonical lowercase UUIDv4 used for exact operation replay.
  final String operationId;

  @override
  Map<String, Object?> toJson() =>
      {..._reviewedJson(), 'operationId': operationId};
}

/// Server-stated transfer limits at or below the hard sample admission bounds.
final class PlacementSampleUploadLimitsV1 extends _SampleValue {
  /// Creates the hard limits by default, or a narrower transfer budget.
  PlacementSampleUploadLimitsV1({
    this.maxPngBytes = placementScreenSampleMaxBytes,
    this.maxDecodedBytes = placementScreenSampleMaxDecodedBytes,
    this.maxDimension = placementScreenSampleMaxDimension,
    this.maxManifestBytes = placementScreenSampleMaxManifestBytes,
    this.maxMounts = placementScreenSampleMaxMounts,
  }) {
    _requireBound(maxPngBytes, placementScreenSampleMaxBytes, 'maxPngBytes');
    _requireBound(
      maxDecodedBytes,
      placementScreenSampleMaxDecodedBytes,
      'maxDecodedBytes',
    );
    _requireBound(
      maxDimension,
      placementScreenSampleMaxDimension,
      'maxDimension',
    );
    _requireBound(
      maxManifestBytes,
      placementScreenSampleMaxManifestBytes,
      'maxManifestBytes',
    );
    _requireBound(maxMounts, placementScreenSampleMaxMounts, 'maxMounts');
  }

  /// Decodes the closed limits object; larger limits never authorize admission.
  factory PlacementSampleUploadLimitsV1.fromJson(Object? value) {
    final reader = _reader(value, _keys, 'sampleUploadLimits');
    return PlacementSampleUploadLimitsV1(
      maxPngBytes: reader.integer('maxPngBytes'),
      maxDecodedBytes: reader.integer('maxDecodedBytes'),
      maxDimension: reader.integer('maxDimension'),
      maxManifestBytes: reader.integer('maxManifestBytes'),
      maxMounts: reader.integer('maxMounts'),
    );
  }

  /// Decodes only exact canonical bytes.
  factory PlacementSampleUploadLimitsV1.fromCanonicalBytes(List<int> bytes) =>
      _decode(bytes, PlacementSampleUploadLimitsV1.fromJson);

  static const _keys = {
    'maxPngBytes',
    'maxDecodedBytes',
    'maxDimension',
    'maxManifestBytes',
    'maxMounts',
  };

  /// Maximum encoded image bytes accepted by this ticket.
  final int maxPngBytes;

  /// Maximum decoded scanline work accepted by this ticket.
  final int maxDecodedBytes;

  /// Maximum raster width or height accepted by this ticket.
  final int maxDimension;

  /// Maximum canonical manifest bytes accepted by this ticket.
  final int maxManifestBytes;

  /// Maximum transferred occurrences accepted by this ticket.
  final int maxMounts;

  @override
  Map<String, Object?> toJson() => {
        'maxPngBytes': maxPngBytes,
        'maxDecodedBytes': maxDecodedBytes,
        'maxDimension': maxDimension,
        'maxManifestBytes': maxManifestBytes,
        'maxMounts': maxMounts,
      };
}

/// A reviewed upload ticket; expiry enforcement belongs to its storage owner.
final class PlacementSampleUploadTicketV1 extends _SampleValue {
  /// Creates an exact ticket without granting network or target authority.
  PlacementSampleUploadTicketV1({
    required this.ticketId,
    required this.manifestDigest,
    required this.imageSha256,
    required this.expiresAtMicros,
    required this.limits,
  }) {
    _requireId(ticketId, 'ticketId');
    _requireHash(manifestDigest, 'manifestDigest');
    _requireHash(imageSha256, 'imageSha256');
    _requireInteger(expiresAtMicros, 'expiresAtMicros');
  }

  /// Decodes a closed upload-ticket result.
  factory PlacementSampleUploadTicketV1.fromJson(Object? value) {
    final reader = _reader(value, _keys, 'sampleUploadTicket');
    return PlacementSampleUploadTicketV1(
      ticketId: reader.string('ticketId'),
      manifestDigest: reader.string('manifestDigest'),
      imageSha256: reader.string('imageSha256'),
      expiresAtMicros: reader.integer('expiresAtMicros'),
      limits: PlacementSampleUploadLimitsV1.fromJson(reader.object('limits')),
    );
  }

  /// Decodes only exact canonical bytes.
  factory PlacementSampleUploadTicketV1.fromCanonicalBytes(List<int> bytes) =>
      _decode(bytes, PlacementSampleUploadTicketV1.fromJson);

  static const _keys = {
    'ticketId',
    'manifestDigest',
    'imageSha256',
    'expiresAtMicros',
    'limits',
  };

  /// Canonical lowercase UUIDv4 ticket identity.
  final String ticketId;

  /// Domain-separated digest of the exact canonical manifest.
  final String manifestDigest;

  /// Exact `sha256:` image identity committed by the manifest.
  final String imageSha256;

  /// Server-issued UTC expiry as a nonnegative portable microsecond integer.
  final int expiresAtMicros;

  /// Hard or narrower server-stated transfer limits.
  final PlacementSampleUploadLimitsV1 limits;

  @override
  Map<String, Object?> toJson() => {
        'ticketId': ticketId,
        'manifestDigest': manifestDigest,
        'imageSha256': imageSha256,
        'expiresAtMicros': expiresAtMicros,
        'limits': limits.toJson(),
      };
}

/// Request to store separately transported PNG bytes under an upload ticket.
final class PlacementSampleStoreV1 extends _SampleValue {
  /// Creates an exact ticket and manifest correlation request.
  PlacementSampleStoreV1({
    required this.ticketId,
    required this.manifestDigest,
  }) {
    _requireId(ticketId, 'ticketId');
    _requireHash(manifestDigest, 'manifestDigest');
  }

  /// Decodes a closed store request without embedding image bytes.
  factory PlacementSampleStoreV1.fromJson(Object? value) {
    final reader = _reader(value, _keys, 'sampleStore');
    return PlacementSampleStoreV1(
      ticketId: reader.string('ticketId'),
      manifestDigest: reader.string('manifestDigest'),
    );
  }

  /// Decodes only exact canonical bytes.
  factory PlacementSampleStoreV1.fromCanonicalBytes(List<int> bytes) =>
      _decode(bytes, PlacementSampleStoreV1.fromJson);

  static const _keys = {'ticketId', 'manifestDigest'};

  /// Canonical lowercase UUIDv4 ticket identity.
  final String ticketId;

  /// Exact manifest commitment returned by prepare.
  final String manifestDigest;

  @override
  Map<String, Object?> toJson() =>
      {'ticketId': ticketId, 'manifestDigest': manifestDigest};
}

/// A stored, still-unbound sample and its exact manifest/image commitments.
final class PlacementSampleStoredV1 extends _SampleValue {
  /// Creates a stored result; binding is a separate operation.
  PlacementSampleStoredV1({
    required this.sampleId,
    required this.manifestDigest,
    required this.imageSha256,
  }) {
    _requireId(sampleId, 'sampleId');
    _requireHash(manifestDigest, 'manifestDigest');
    _requireHash(imageSha256, 'imageSha256');
  }

  /// Decodes a closed stored result.
  factory PlacementSampleStoredV1.fromJson(Object? value) {
    final reader = _reader(value, _keys, 'sampleStored');
    return PlacementSampleStoredV1(
      sampleId: reader.string('sampleId'),
      manifestDigest: reader.string('manifestDigest'),
      imageSha256: reader.string('imageSha256'),
    );
  }

  /// Decodes only exact canonical bytes.
  factory PlacementSampleStoredV1.fromCanonicalBytes(List<int> bytes) =>
      _decode(bytes, PlacementSampleStoredV1.fromJson);

  static const _keys = {'sampleId', 'manifestDigest', 'imageSha256'};

  /// Canonical lowercase UUIDv4 sample identity.
  final String sampleId;

  /// Exact domain-separated manifest commitment.
  final String manifestDigest;

  /// Exact `sha256:` image identity.
  final String imageSha256;

  @override
  Map<String, Object?> toJson() => {
        'sampleId': sampleId,
        'manifestDigest': manifestDigest,
        'imageSha256': imageSha256,
      };
}

/// Request to bind every occurrence in one immutable sample frame atomically.
final class PlacementSampleBindV1 extends _SampleMutation {
  /// Creates a request with an optional expected whole-frame revision.
  PlacementSampleBindV1({
    required super.sampleId,
    required super.operationId,
    super.expectedBindingRevision,
  });

  /// Decodes a closed bind request.
  factory PlacementSampleBindV1.fromJson(Object? value) {
    final reader = _reader(value, _SampleMutation.keys, 'sampleBind');
    return PlacementSampleBindV1(
      sampleId: reader.string('sampleId'),
      operationId: reader.string('operationId'),
      expectedBindingRevision:
          _nullableRevision(reader, 'expectedBindingRevision'),
    );
  }

  /// Decodes only exact canonical bytes.
  factory PlacementSampleBindV1.fromCanonicalBytes(List<int> bytes) =>
      _decode(bytes, PlacementSampleBindV1.fromJson);

  @override
  Map<String, Object?> toJson() => _mutationJson();
}

/// A bound screen frame's safe target, build, commitments and revision.
final class PlacementScreenSampleRefV1 extends _SampleValue {
  /// Creates a reference without image bytes or a publicly readable locator.
  PlacementScreenSampleRefV1({
    required this.target,
    required this.sampleId,
    required this.appBuildContractHash,
    required this.manifestDigest,
    required this.imageSha256,
    required this.screenLabel,
    required this.bindingRevision,
  }) {
    _requireId(sampleId, 'sampleId');
    _requireHash(appBuildContractHash, 'appBuildContractHash');
    _requireHash(manifestDigest, 'manifestDigest');
    _requireHash(imageSha256, 'imageSha256');
    _requireLabel(screenLabel);
    _requireInteger(bindingRevision, 'bindingRevision', positive: true);
  }

  /// Decodes the closed bound-sample reference.
  factory PlacementScreenSampleRefV1.fromJson(Object? value) {
    final reader = _reader(value, _keys, 'screenSampleRef');
    return PlacementScreenSampleRefV1(
      target: TargetCoordinate.fromJson(reader.object('target')),
      sampleId: reader.string('sampleId'),
      appBuildContractHash: reader.string('appBuildContractHash'),
      manifestDigest: reader.string('manifestDigest'),
      imageSha256: reader.string('imageSha256'),
      screenLabel: reader.string('screenLabel'),
      bindingRevision: reader.integer('bindingRevision'),
    );
  }

  /// Decodes only exact canonical bytes.
  factory PlacementScreenSampleRefV1.fromCanonicalBytes(List<int> bytes) =>
      _decode(bytes, PlacementScreenSampleRefV1.fromJson);

  static const _keys = {
    'target',
    'sampleId',
    'appBuildContractHash',
    'manifestDigest',
    'imageSha256',
    'screenLabel',
    'bindingRevision',
  };

  /// Exact target of the sample's current frame binding.
  final TargetCoordinate target;

  /// Canonical lowercase UUIDv4 sample identity.
  final String sampleId;

  /// Full immutable offline build commitment.
  final String appBuildContractHash;

  /// Domain-separated commitment to the exact canonical manifest.
  final String manifestDigest;

  /// Exact `sha256:` image commitment.
  final String imageSha256;

  /// Explicit authored screen label.
  final String screenLabel;

  /// Positive portable revision of the whole frame binding.
  final int bindingRevision;

  /// Checks manifest correlation, independently of authentication or storage.
  void validateForManifest(PlacementScreenSampleManifestV1 manifest) {
    if (target != manifest.target ||
        appBuildContractHash != manifest.appBuildContractHash ||
        manifestDigest != manifest.manifestDigest ||
        imageSha256 != manifest.pngSha256 ||
        screenLabel != manifest.screenLabel) {
      throw const CanonicalFormatException(
        'The sample reference and manifest disagree.',
      );
    }
  }

  @override
  Map<String, Object?> toJson() => {
        'target': target.toJson(),
        'sampleId': sampleId,
        'appBuildContractHash': appBuildContractHash,
        'manifestDigest': manifestDigest,
        'imageSha256': imageSha256,
        'screenLabel': screenLabel,
        'bindingRevision': bindingRevision,
      };
}

/// Request for authorized sample metadata or a separately transported image.
final class PlacementSampleReadV1 extends _SampleValue {
  /// Creates a read locator without granting access to the sample.
  PlacementSampleReadV1({required this.sampleId}) {
    _requireId(sampleId, 'sampleId');
  }

  /// Decodes a closed sample read request.
  factory PlacementSampleReadV1.fromJson(Object? value) {
    final reader = _reader(value, _keys, 'sampleRead');
    return PlacementSampleReadV1(sampleId: reader.string('sampleId'));
  }

  /// Decodes only exact canonical bytes.
  factory PlacementSampleReadV1.fromCanonicalBytes(List<int> bytes) =>
      _decode(bytes, PlacementSampleReadV1.fromJson);

  static const _keys = {'sampleId'};

  /// Canonical lowercase UUIDv4 sample identity.
  final String sampleId;

  @override
  Map<String, Object?> toJson() => {'sampleId': sampleId};
}

/// Storage-state evidence returned by an authorized metadata read.
enum PlacementSampleStatusV1 {
  /// Stored image evidence exists without a current frame binding.
  unbound,

  /// Image evidence exists and has the returned current frame binding.
  bound,

  /// The known sample's image body has been removed.
  removed,

  /// No available sample is known for this locator.
  absent,
}

/// Truthful sample metadata with explicit absence and removal states.
final class PlacementSampleReadResultV1 extends _SampleValue {
  /// Creates a state-consistent metadata result with no embedded image.
  PlacementSampleReadResultV1({
    required this.sampleId,
    required this.status,
    this.manifest,
    this.ref,
    this.bindingRevision,
  }) {
    _requireId(sampleId, 'sampleId');
    _requireNullableRevision(bindingRevision, 'bindingRevision');
    switch (status) {
      case PlacementSampleStatusV1.bound:
        if (manifest == null ||
            ref == null ||
            ref!.sampleId != sampleId ||
            bindingRevision != ref!.bindingRevision) {
          throw const CanonicalFormatException(
            'A bound sample requires its exact manifest and current reference.',
          );
        }
        ref!.validateForManifest(manifest!);
      case PlacementSampleStatusV1.unbound:
        if (manifest == null || ref != null || bindingRevision != null) {
          throw const CanonicalFormatException(
            'An unbound sample requires a manifest without a current binding.',
          );
        }
      case PlacementSampleStatusV1.removed:
        if (manifest != null || ref != null) {
          throw const CanonicalFormatException(
            'A removed sample cannot carry image or current binding evidence.',
          );
        }
      case PlacementSampleStatusV1.absent:
        if (manifest != null || ref != null || bindingRevision != null) {
          throw const CanonicalFormatException(
            'An absent sample cannot carry manifest or binding evidence.',
          );
        }
    }
  }

  /// Decodes closed metadata with state-dependent evidence requirements.
  factory PlacementSampleReadResultV1.fromJson(Object? value) {
    final reader = _reader(value, _keys, 'sampleReadResult');
    final rawManifest = reader.requiredNullableValue('manifest');
    final rawRef = reader.requiredNullableValue('ref');
    return PlacementSampleReadResultV1(
      sampleId: reader.string('sampleId'),
      status: _enum(reader.string('status'), PlacementSampleStatusV1.values),
      manifest: rawManifest == null
          ? null
          : PlacementScreenSampleManifestV1.fromJson(rawManifest),
      ref: rawRef == null ? null : PlacementScreenSampleRefV1.fromJson(rawRef),
      bindingRevision: _nullableRevision(reader, 'bindingRevision'),
    );
  }

  /// Decodes only exact canonical bytes.
  factory PlacementSampleReadResultV1.fromCanonicalBytes(List<int> bytes) =>
      _decode(bytes, PlacementSampleReadResultV1.fromJson);

  static const _keys = {
    'sampleId',
    'status',
    'manifest',
    'ref',
    'bindingRevision',
  };

  /// Canonical lowercase UUIDv4 sample locator.
  final String sampleId;

  /// Reported storage state; absence never manufactures image evidence.
  final PlacementSampleStatusV1 status;

  /// Exact manifest only while the sample body remains available.
  final PlacementScreenSampleManifestV1? manifest;

  /// Current bound reference, present only for [PlacementSampleStatusV1.bound].
  final PlacementScreenSampleRefV1? ref;

  /// Current binding revision, or a removed frame's retained tombstone.
  final int? bindingRevision;

  @override
  Map<String, Object?> toJson() => {
        'sampleId': sampleId,
        'status': status.name,
        'manifest': manifest?.toJson(),
        'ref': ref?.toJson(),
        'bindingRevision': bindingRevision,
      };
}

/// Request to remove a sample body and its current frame binding.
final class PlacementSampleDeleteV1 extends _SampleMutation {
  /// Creates an exact deletion operation with optional whole-frame revision.
  PlacementSampleDeleteV1({
    required super.sampleId,
    required super.operationId,
    super.expectedBindingRevision,
  });

  /// Decodes a closed deletion request.
  factory PlacementSampleDeleteV1.fromJson(Object? value) {
    final reader = _reader(value, _SampleMutation.keys, 'sampleDelete');
    return PlacementSampleDeleteV1(
      sampleId: reader.string('sampleId'),
      operationId: reader.string('operationId'),
      expectedBindingRevision:
          _nullableRevision(reader, 'expectedBindingRevision'),
    );
  }

  /// Decodes only exact canonical bytes.
  factory PlacementSampleDeleteV1.fromCanonicalBytes(List<int> bytes) =>
      _decode(bytes, PlacementSampleDeleteV1.fromJson);

  @override
  Map<String, Object?> toJson() => _mutationJson();
}

/// Removal truth returned by a successful authorized deletion operation.
enum PlacementSampleDeletionStatusV1 {
  /// The sample's image body was removed or was already removed.
  removed,

  /// No sample body was known for the supplied locator.
  absent,
}

/// A deletion result with no image bytes, manifest or public image locator.
final class PlacementSampleDeleteResultV1 extends _SampleValue {
  /// Creates truthful removal evidence and an optional retained tombstone.
  PlacementSampleDeleteResultV1({
    required this.sampleId,
    required this.status,
    this.bindingRevision,
  }) {
    _requireId(sampleId, 'sampleId');
    _requireNullableRevision(bindingRevision, 'bindingRevision');
    if (status == PlacementSampleDeletionStatusV1.absent &&
        bindingRevision != null) {
      throw const CanonicalFormatException(
        'An absent sample cannot carry a binding revision.',
      );
    }
  }

  /// Decodes a closed deletion result.
  factory PlacementSampleDeleteResultV1.fromJson(Object? value) {
    final reader = _reader(value, _keys, 'sampleDeleteResult');
    return PlacementSampleDeleteResultV1(
      sampleId: reader.string('sampleId'),
      status: _enum(
        reader.string('status'),
        PlacementSampleDeletionStatusV1.values,
      ),
      bindingRevision: _nullableRevision(reader, 'bindingRevision'),
    );
  }

  /// Decodes only exact canonical bytes.
  factory PlacementSampleDeleteResultV1.fromCanonicalBytes(List<int> bytes) =>
      _decode(bytes, PlacementSampleDeleteResultV1.fromJson);

  static const _keys = {'sampleId', 'status', 'bindingRevision'};

  /// Canonical lowercase UUIDv4 sample locator.
  final String sampleId;

  /// Explicit removal or absence evidence.
  final PlacementSampleDeletionStatusV1 status;

  /// Positive tombstone revision when a former frame head is retained.
  final int? bindingRevision;

  @override
  Map<String, Object?> toJson() => {
        'sampleId': sampleId,
        'status': status.name,
        'bindingRevision': bindingRevision,
      };
}

abstract base class _SampleValue extends CanonicalValue
    implements ImmutableCanonicalDocument {}

abstract base class _SampleFrame extends _SampleValue {
  _SampleFrame({
    required this.appBuildContractHash,
    required this.screenLabel,
    required this.captureScope,
    required this.logicalViewport,
    required this.rasterScale,
    required this.pngWidth,
    required this.pngHeight,
    required this.pngByteLength,
    required this.pngSha256,
    required List<PlacementSampleMountV1> mounts,
  }) : mounts = _snapshotMounts(mounts, logicalViewport) {
    _requireHash(appBuildContractHash, 'appBuildContractHash');
    _requireHash(pngSha256, 'pngSha256');
    _requireLabel(screenLabel);
    _requireBound(pngWidth, placementScreenSampleMaxDimension, 'pngWidth');
    _requireBound(pngHeight, placementScreenSampleMaxDimension, 'pngHeight');
    _requireBound(
      pngByteLength,
      placementScreenSampleMaxBytes,
      'pngByteLength',
    );
    if (!placementRasterExtentIsConsistent(
          pixels: pngWidth,
          logicalUnits: logicalViewport.widthUnits,
          scale: rasterScale,
        ) ||
        !placementRasterExtentIsConsistent(
          pixels: pngHeight,
          logicalUnits: logicalViewport.heightUnits,
          scale: rasterScale,
        )) {
      throw const CanonicalFormatException(
        'The sample raster and logical frame disagree.',
      );
    }
  }

  static const keys = {
    'appBuildContractHash',
    'screenLabel',
    'captureScope',
    'logicalViewport',
    'rasterScale',
    'pngWidth',
    'pngHeight',
    'pngByteLength',
    'pngSha256',
    'mounts',
  };

  /// Exact complete offline build commitment.
  final String appBuildContractHash;

  /// Explicit label with 1..80 Unicode scalars and at most 320 UTF-8 bytes.
  final String screenLabel;

  /// Coordinate frame used to capture the image and mount bounds.
  final PlacementScreenCaptureScopeV1 captureScope;

  /// Positive bounded logical size in 1024 integer units per pixel.
  final PlacementLogicalSizeV1 logicalViewport;

  /// Exact reduced rational used by the raster encoder.
  final PlacementRasterScaleV1 rasterScale;

  /// Exact declared decoded raster width.
  final int pngWidth;

  /// Exact declared decoded raster height.
  final int pngHeight;

  /// Exact declared encoded image length.
  final int pngByteLength;

  /// Exact declared `sha256:` image commitment.
  final String pngSha256;

  /// Immutable occurrences sorted by their unsigned canonical source bytes.
  final List<PlacementSampleMountV1> mounts;

  Map<String, Object?> _frameJson() => {
        'appBuildContractHash': appBuildContractHash,
        'screenLabel': screenLabel,
        'captureScope': captureScope.name,
        'logicalViewport': logicalViewport.toJson(),
        'rasterScale': rasterScale.toJson(),
        'pngWidth': pngWidth,
        'pngHeight': pngHeight,
        'pngByteLength': pngByteLength,
        'pngSha256': pngSha256,
        'mounts': mounts.map((mount) => mount.toJson()).toList(),
      };
}

abstract base class _ReviewedSample extends _SampleValue {
  _ReviewedSample({
    required this.manifest,
    required this.buildContract,
    required this.reviewedDigest,
  }) {
    _validateBuild(buildContract, manifest);
    _requireHash(reviewedDigest, 'reviewedDigest');
    if (reviewedDigest != manifest.reviewDigest) {
      throw const CanonicalFormatException(
        'The review digest does not identify the exact sample evidence.',
      );
    }
    _requireBytes(canonicalBytes.length, _maximumEnvelopeBytes);
  }

  static const keys = {'manifest', 'buildContract', 'reviewedDigest'};

  /// Exact target-bound manifest reviewed for transfer.
  final PlacementScreenSampleManifestV1 manifest;

  /// Full immutable offline declaration, also checked against every occurrence.
  final PlacementBuildContractV1 buildContract;

  /// Exact domain-separated reviewed envelope commitment.
  final String reviewedDigest;

  /// Domain-separated commitment to the reviewed canonical manifest.
  String get manifestDigest => manifest.manifestDigest;

  Map<String, Object?> _reviewedJson() => {
        'manifest': manifest.toJson(),
        'buildContract': buildContract.toJson(),
        'reviewedDigest': reviewedDigest,
      };
}

abstract base class _SampleMutation extends _SampleValue {
  _SampleMutation({
    required this.sampleId,
    required this.operationId,
    this.expectedBindingRevision,
  }) {
    _requireId(sampleId, 'sampleId');
    _requireId(operationId, 'operationId');
    _requireNullableRevision(
      expectedBindingRevision,
      'expectedBindingRevision',
    );
  }

  static const keys = {'sampleId', 'operationId', 'expectedBindingRevision'};

  /// Canonical lowercase UUIDv4 sample identity.
  final String sampleId;

  /// Canonical lowercase UUIDv4 identity used for exact operation replay.
  final String operationId;

  /// Positive expected revision of the entire current frame binding, if known.
  final int? expectedBindingRevision;

  Map<String, Object?> _mutationJson() => {
        'sampleId': sampleId,
        'operationId': operationId,
        'expectedBindingRevision': expectedBindingRevision,
      };
}

CanonicalObjectReader _reader(Object? value, Set<String> keys, String path) =>
    CanonicalObjectReader(
      requireCanonicalObject(value, path),
      allowedKeys: keys,
      requiredKeys: keys,
      path: path,
    );

T _decode<T extends CanonicalValue>(
  List<int> bytes,
  T Function(Object?) read, {
  int maxBytes = _maximumEnvelopeBytes,
}) {
  _requireBytes(bytes.length, maxBytes);
  return _construct(
    () => verifyCanonicalRoundTrip(
      read(CanonicalJsonCodec.decode(bytes)),
      bytes,
      path: 'placementSample',
    ),
  );
}

T _construct<T>(T Function() build) {
  try {
    return build();
    // Normalize the existing constructor validators at the wire boundary.
    // ignore: avoid_catching_errors
  } on ArgumentError catch (error) {
    throw CanonicalFormatException('${error.message}');
  } on FormatException catch (error) {
    throw CanonicalFormatException(error.message);
  }
}

void _requireHash(String value, String field) {
  if (!value.startsWith('sha256:')) {
    throw CanonicalFormatException('$field requires a sha256: content hash.');
  }
  _construct(() => CanonicalDigest(value.substring('sha256:'.length)));
}

void _requireId(String value, String field) =>
    _construct(() => requireCommerceUuidV4(value, field));

void _requireInteger(int value, String field, {bool positive = false}) {
  if (value < (positive ? 1 : 0) || value > kMaximumPortableJsonInteger) {
    throw CanonicalFormatException(
      '$field must be a ${positive ? 'positive' : 'nonnegative'} '
      'portable integer.',
    );
  }
}

void _requireBound(int value, int maximum, String field) {
  if (value < 1 || value > maximum) {
    throw CanonicalFormatException('$field is outside the sample limit.');
  }
}

void _requireBytes(int length, int maximum) {
  if (length > maximum) {
    throw const CanonicalFormatException(
      'The sample representation exceeds its byte limit.',
    );
  }
}

void _requireNullableRevision(int? value, String field) {
  if (value != null) _requireInteger(value, field, positive: true);
}

int? _nullableRevision(CanonicalObjectReader reader, String field) {
  final value = reader.requiredNullableValue(field);
  if (value == null) return null;
  if (value is! int) {
    throw CanonicalFormatException('$field must be null or an integer.');
  }
  _requireInteger(value, field, positive: true);
  return value;
}

T _enum<T extends Enum>(String value, List<T> values) {
  for (final candidate in values) {
    if (candidate.name == value) return candidate;
  }
  throw const CanonicalFormatException('Unknown sample discriminator.');
}

void _requireLabel(String value) {
  if (value.length > 160) {
    throw const CanonicalFormatException(
      'The screen label exceeds its scalar limit.',
    );
  }
  final scalars = value.runes.toList();
  if (scalars.isEmpty ||
      scalars.length > 80 ||
      utf8.encode(value).length > 320 ||
      scalars.any(
        (scalar) =>
            scalar <= 0x1f ||
            (scalar >= 0x7f && scalar <= 0x9f) ||
            (scalar >= 0xd800 && scalar <= 0xdfff) ||
            scalar == 0x061c ||
            scalar == 0x200e ||
            scalar == 0x200f ||
            (scalar >= 0x2028 && scalar <= 0x202e) ||
            (scalar >= 0x2066 && scalar <= 0x2069),
      )) {
    throw const CanonicalFormatException(
      'A screen label requires 1..80 Unicode scalars without controls.',
    );
  }
}

List<PlacementSampleMountV1> _readMounts(CanonicalObjectReader reader) {
  final raw = reader.list('mounts');
  if (raw.length > placementScreenSampleMaxMounts) {
    throw const CanonicalFormatException(
      'The sample exceeds its transferred mount limit.',
    );
  }
  return raw.map(PlacementSampleMountV1.fromJson).toList();
}

List<PlacementSampleMountV1> _snapshotMounts(
  List<PlacementSampleMountV1> input,
  PlacementLogicalSizeV1 viewport,
) {
  if (input.length > placementScreenSampleMaxMounts) {
    throw const CanonicalFormatException(
      'The sample exceeds its transferred mount limit.',
    );
  }
  final identities = <(PlacementKeyV1, String, int)>{};
  final mounts = <PlacementSampleMountV1>[];
  for (final mount in input) {
    if (!identities
        .add((mount.key, mount.hostContractHash, mount.occurrenceIndex))) {
      throw const CanonicalFormatException(
        'Sample mounts must have unique key/host/occurrence identities.',
      );
    }
    mounts.add(PlacementSampleMountV1._inViewport(mount, viewport));
  }
  final bytes = {for (final mount in mounts) mount: mount.canonicalBytes};
  mounts.sort((left, right) => _compareBytes(bytes[left]!, bytes[right]!));
  return List.unmodifiable(mounts);
}

int _compareBytes(List<int> left, List<int> right) {
  final count = math.min(left.length, right.length);
  for (var index = 0; index < count; index++) {
    if (left[index] != right[index]) return left[index] - right[index];
  }
  return left.length - right.length;
}

void _validateBuild(PlacementBuildContractV1 build, _SampleFrame frame) {
  build.verifyHash(frame.appBuildContractHash);
  final declarations = {
    for (final mount in build.mounts) (mount.key, mount.hostContractHash),
  };
  if (frame.mounts.any(
    (mount) => !declarations.contains((mount.key, mount.hostContractHash)),
  )) {
    throw const CanonicalFormatException(
      'Every sample occurrence must name an exact build declaration.',
    );
  }
}

String _domainHash(String domain, List<int> bytes) =>
    'sha256:${crypto.sha256.convert([...utf8.encode(domain), 0, ...bytes])}';
