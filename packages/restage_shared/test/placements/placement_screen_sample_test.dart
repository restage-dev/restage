import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

const _operationId = '4d1f28ea-0c97-4d87-8fd7-15164749e440';
const _ticketId = 'dc0bdfb5-d815-4e7b-8d9f-76647d28c68b';
const _sampleId = '86505cf7-c04b-45d0-83c8-529ec1b8db1c';
final Matcher _refusal =
    anyOf(isA<CanonicalFormatException>(), isA<FormatException>());
final _target = TargetCoordinate(
  organizationId: OrganizationId(1),
  appId: ApplicationId(1),
  environmentTargetId: EnvironmentTargetId(1),
  namedEnvironmentId: NamedEnvironmentId(1),
  runtimePlane: RuntimePlane.live,
);
final _host = SurfaceHostContractV1(
  hosting: const SurfaceHostingV1(
    contentKind: SurfaceContentKindV1.single,
    presentation: SurfacePresentationV1.inline,
  ),
  providedContext: const SurfaceScreenHostDataSchema.empty(),
  handledEvents: SurfaceScreenEventSchema(events: const []),
);
final _capability = InstalledCapability(
  builtInCatalogVersion: 2,
  installedLibraries: const [],
);

void main() {
  test('one pixel explicit boundary retains offscreen source bounds', () {
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNg'
      'YAAAAAMAASsJTYQAAAAASUVORK5CYII=',
    );
    final manifest = _manifest().copyWith(
      logicalViewport: PlacementLogicalSizeV1.fromLogical(width: 1, height: 1),
      pngWidth: 1,
      pngHeight: 1,
      pngByteLength: bytes.length,
      pngSha256: _hash(bytes),
    );
    final accepted = validatePlacementScreenSample(
      manifest: manifest,
      pngBytes: bytes,
    );
    expect(accepted.manifest.mounts.single.rect.x, -0.5);
    expect(accepted.manifest.mounts.single.clipping, SampleClipping.clipped);
    expect(accepted.manifest.mounts.single.overlayRect?.width, 0.5);
  });

  test('accepts actual Flutter bytes and freezes image and manifest evidence',
      () {
    final source = _flutterPng();
    final original = Uint8List.fromList(source);
    final mounts = [_mount()];
    final manifest = _manifest(mounts: mounts);
    final accepted = validatePlacementScreenSample(
      manifest: manifest,
      pngBytes: source,
    );
    final heldManifest = accepted.manifestCanonicalBytes;
    expect(accepted.pngBytes, original);
    expect(accepted.manifest, manifest);
    expect(accepted.manifestDigest, manifest.manifestDigest);
    expect(accepted.reviewDigest, manifest.reviewDigest);
    source[0] ^= 1;
    mounts.clear();
    heldManifest.fillRange(0, heldManifest.length, 0);
    expect(accepted.pngBytes, original);
    expect(accepted.manifestCanonicalBytes, manifest.canonicalBytes);
    expect(manifest.mounts, hasLength(1));
    expect(manifest.mounts.clear, throwsUnsupportedError);
    expect(() => accepted.pngBytes[0] = 0, throwsUnsupportedError);
    expect(
      () => accepted.pngBytes.buffer.asUint8List()[0] = 0,
      throwsUnsupportedError,
    );
  });

  test('valid changed image cannot reuse retained manifest digest', () {
    final source = _flutterPng();
    final changed = _changedFlutterPng(source);
    final png = validatePlacementScreenSamplePng(changed);
    final manifest = _manifest();
    expect(changed.length, source.length);
    expect((png.width, png.height), (manifest.pngWidth, manifest.pngHeight));
    expect(png.contentHash, isNot(manifest.pngSha256));
    expect(
      () =>
          validatePlacementScreenSample(manifest: manifest, pngBytes: changed),
      throwsA(isA<FormatException>()),
    );
    final changedManifest = manifest.copyWith(pngSha256: png.contentHash);
    expect(
      validatePlacementScreenSample(
        manifest: changedManifest,
        pngBytes: changed,
      ).reviewDigest,
      isNot(manifest.reviewDigest),
    );
  });

  test('manifest and reviewed envelope have exact distinct digest preimages',
      () {
    final manifest = _manifest();
    expect(
      manifest.manifestDigest,
      _hash([
        ...utf8.encode('restage.placement-screen-sample-manifest.v1'),
        0,
        ...manifest.canonicalBytes,
      ]),
    );
    expect(
      manifest.reviewDigest,
      _hash([
        ...utf8.encode('restage.placement-screen-sample-review.v1'),
        0,
        ...CanonicalJsonCodec.encode({
          'manifest': manifest.toJson(),
          'pngSha256': manifest.pngSha256,
        }),
      ]),
    );
    expect(manifest.manifestDigest, isNot(manifest.reviewDigest));
    expect(manifest.toJson(), isNot(contains('reviewDigest')));
    expect(manifest.toJson(), isNot(contains('manifestDigest')));
    for (final changed in [
      manifest.copyWith(screenLabel: 'Daily check-in'),
      manifest.copyWith(
        captureScope: PlacementScreenCaptureScopeV1.flutterView,
      ),
      manifest.copyWith(target: _otherTarget()),
      manifest.copyWith(appBuildContractHash: 'sha256:${'a' * 64}'),
      manifest.copyWith(mounts: [_mount(x: 0)]),
      manifest.copyWith(pngSha256: 'sha256:${'b' * 64}'),
      manifest.copyWith(pngByteLength: manifest.pngByteLength + 1),
      manifest.copyWith(pngWidth: manifest.pngWidth + 1),
    ]) {
      expect(changed.manifestDigest, isNot(manifest.manifestDigest));
      expect(changed.reviewDigest, isNot(manifest.reviewDigest));
    }
  });

  test('offscreen source geometry survives derived clipping and overlay', () {
    final manifest = _manifest();
    final mount = manifest.mounts.single;
    expect(mount.rect.x, -0.5);
    expect(mount.clipping, SampleClipping.clipped);
    expect(
      mount.overlayRect,
      PlacementLogicalRectV1.fromLogical(
        x: 0,
        y: 0,
        width: 0.5,
        height: 1,
      ),
    );
    final inside = _manifest(mounts: [_mount(x: 1)]).mounts.single;
    expect(inside.clipping, SampleClipping.inside);
    expect(inside.overlayRect, inside.rect);
    for (final x in [-2.0, 3.0]) {
      final outside = _manifest(mounts: [_mount(x: x)]).mounts.single;
      expect(outside.clipping, SampleClipping.clipped);
      expect(outside.overlayRect, isNull);
      expect(outside.rect.x, x);
    }
    final bottom = PlacementSampleMountV1(
      key: mount.key,
      hostContractHash: mount.hostContractHash,
      occurrenceIndex: 0,
      rect: PlacementLogicalRectV1.fromLogical(
        x: 0,
        y: 1.5,
        width: 1,
        height: 1,
      ),
    );
    expect(_manifest(mounts: [bottom]).mounts.single.overlayRect?.height, 0.5);
    expect(mount.toJson(), isNot(contains('clipping')));
    expect(mount.toJson(), isNot(contains('overlayRect')));
  });

  test('capture is target free and verifies complete build before binding', () {
    final capture = _capture();
    final manifest = capture.bindTarget(_target);
    expect(manifest, _manifest());
    expect(capture.toJson(), isNot(contains('target')));
    expect(capture.buildContract, _build());
    expect(
      PlacementScreenCaptureV1.fromCanonicalBytes(capture.canonicalBytes),
      capture,
    );
    for (final json in [
      {
        ...capture.toJson(),
        'appBuildContractHash': _build(ordinal: 1).appBuildContractHash,
      },
      {...capture.toJson(), 'buildContract': _build(ordinal: 1).toJson()},
      {
        ...capture.toJson(),
        'mounts': [_mount(key: PlacementKeyV1.named(slug: 'other')).toJson()],
      },
      {
        ...capture.toJson(),
        'mounts': [_mount(hostHash: 'sha256:${'a' * 64}').toJson()],
      },
      {...capture.toJson(), 'target': _target.toJson()},
    ]) {
      expect(() => PlacementScreenCaptureV1.fromJson(json), throwsA(_refusal));
    }
  });

  test('draft and prepare join the exact build and reviewed manifest', () {
    final manifest = _manifest();
    final draft = PlacementSampleDraftV1(
      manifest: manifest,
      buildContract: _build(),
      reviewedDigest: manifest.reviewDigest,
    );
    expect(
      PlacementSampleDraftV1.fromCanonicalBytes(draft.canonicalBytes),
      draft,
    );
    final prepare = PlacementSamplePrepareV1(
      manifest: draft.manifest,
      buildContract: draft.buildContract,
      reviewedDigest: draft.reviewedDigest,
      operationId: _operationId,
    );
    for (final json in [
      {...draft.toJson(), 'reviewedDigest': true},
      {...draft.toJson(), 'reviewedDigest': manifest.manifestDigest},
      {
        ...draft.toJson(),
        'manifest': manifest.copyWith(screenLabel: 'Other').toJson(),
      },
      {...draft.toJson(), 'buildContract': _build(ordinal: 2).toJson()},
      {
        ...draft.toJson(),
        'manifest': manifest.copyWith(
          mounts: [_mount(key: PlacementKeyV1.named(slug: 'other'))],
        ).toJson(),
      },
    ]) {
      expect(() => PlacementSampleDraftV1.fromJson(json), throwsA(_refusal));
      expect(
        () => PlacementSamplePrepareV1.fromJson(
          {...json, 'operationId': _operationId},
        ),
        throwsA(_refusal),
      );
    }
    expect(prepare.manifestDigest, manifest.manifestDigest);
    expect(prepare.reviewedDigest, manifest.reviewDigest);
  });

  test('duplicate identities refuse and separate occurrences survive', () {
    final one = _mount();
    for (final repeated in [one, _mount(x: 1)]) {
      expect(() => _manifest(mounts: [one, repeated]), throwsA(_refusal));
    }
    final manifest = _manifest(mounts: [_mount(index: 1), one]);
    expect(manifest.mounts, hasLength(2));
    expect(manifest.mounts.map((m) => m.occurrenceIndex).toSet(), {0, 1});
    expect(
      _capture(mounts: [_mount(index: 1), one]).bindTarget(_target),
      manifest,
    );
    expect(
      () => PlacementScreenSampleManifestV1.fromCanonicalBytes(
        CanonicalJsonCodec.encode({
          ...manifest.toJson(),
          'mounts': manifest.mounts.reversed.map((m) => m.toJson()).toList(),
        }),
      ),
      throwsA(_refusal),
    );
  });

  test('accepts transfer mount ceiling and refuses next mount or invalid index',
      () {
    final atLimit = List.generate(128, (index) => _mount(index: index));
    expect(_manifest(mounts: atLimit).mounts, hasLength(128));
    expect(
      () => _manifest(mounts: [...atLimit, _mount(index: 128)]),
      throwsA(_refusal),
    );
    for (final index in [-1, kMaximumPortableJsonInteger + 1]) {
      expect(() => _mount(index: index), throwsA(_refusal));
    }
    expect(
      _mount(index: kMaximumPortableJsonInteger).occurrenceIndex,
      kMaximumPortableJsonInteger,
    );
    expect(_manifest(mounts: []).mounts, isEmpty);
  });

  test('labels count Unicode scalars and reject controls and invalid scalars',
      () {
    expect(_manifest(label: '😀' * 80).screenLabel.runes.length, 80);
    expect(
      utf8.encode(_manifest(label: '😀' * 80).screenLabel),
      hasLength(320),
    );
    for (final label in [
      '',
      'a' * 81,
      '😀' * 81,
      'x\n',
      'x\u0000',
      'x\u007f',
      'x\u009f',
      'x\u202e',
      String.fromCharCode(0xd800),
    ]) {
      expect(
        () => _manifest(label: label),
        throwsA(_refusal),
        reason: label,
      );
    }
  });

  test('manifest decoding bounds total bytes before parsing', () {
    final bytes = Uint8List(placementScreenSampleMaxManifestBytes + 1);
    expect(
      () => PlacementScreenSampleManifestV1.fromCanonicalBytes(bytes),
      throwsA(_refusal),
    );
    expect(
      () => PlacementScreenSampleManifestV1.fromJson({
        ..._manifest().toJson(),
        'screenLabel': 'x' * placementScreenSampleMaxManifestBytes,
      }),
      throwsA(_refusal),
    );
  });

  test('actual image length dimensions and quantized layout must agree', () {
    final manifest = _manifest();
    final source = _flutterPng();
    for (final changed in [
      manifest.copyWith(pngByteLength: source.length - 1),
      manifest.copyWith(pngWidth: 4),
      manifest.copyWith(pngHeight: 3),
    ]) {
      expect(
        () => validatePlacementScreenSample(
          manifest: changed,
          pngBytes: source,
        ),
        throwsA(isA<FormatException>()),
      );
    }
    for (final json in [
      {...manifest.toJson(), 'pngWidth': 0},
      {
        ...manifest.toJson(),
        'pngHeight': placementScreenSampleMaxDimension + 1,
      },
      {...manifest.toJson(), 'pngByteLength': 0},
      {
        ...manifest.toJson(),
        'pngByteLength': placementScreenSampleMaxBytes + 1,
      },
      {
        ...manifest.toJson(),
        'logicalViewport':
            PlacementLogicalSizeV1.fromLogical(width: 6, height: 2).toJson(),
      },
      {
        ...manifest.toJson(),
        'rasterScale': PlacementRasterScaleV1.fromRequestedScale(4).toJson(),
      },
    ]) {
      expect(
        () => PlacementScreenSampleManifestV1.fromJson(json),
        throwsA(_refusal),
      );
    }
    final corrupted = Uint8List.fromList(source)..[source.length - 1] ^= 1;
    expect(
      () => validatePlacementScreenSample(
        manifest: manifest,
        pngBytes: corrupted,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('all hashes require exact prefixed lowercase SHA-256 grammar', () {
    final manifest = _manifest();
    for (final bad in [
      'a' * 64,
      'sha256:${'A' * 64}',
      'sha256:${'a' * 63}',
      'sha256:${'a' * 64}\n',
    ]) {
      for (final field in ['appBuildContractHash', 'pngSha256']) {
        expect(
          () => PlacementScreenSampleManifestV1.fromJson(
            {...manifest.toJson(), field: bad},
          ),
          throwsA(_refusal),
        );
      }
      expect(() => _mount(hostHash: bad), throwsA(_refusal));
    }
  });

  test('ticket limits can narrow admission and cannot widen hard limits', () {
    final defaults = PlacementSampleUploadLimitsV1();
    expect(defaults.maxPngBytes, placementScreenSampleMaxBytes);
    expect(defaults.maxDecodedBytes, placementScreenSampleMaxDecodedBytes);
    expect(defaults.maxDimension, placementScreenSampleMaxDimension);
    expect(defaults.maxManifestBytes, placementScreenSampleMaxManifestBytes);
    expect(defaults.maxMounts, placementScreenSampleMaxMounts);
    final smaller = PlacementSampleUploadLimitsV1(
      maxPngBytes: 128,
      maxDecodedBytes: 64,
      maxDimension: 8,
      maxManifestBytes: 1024,
      maxMounts: 2,
    );
    expect(
      PlacementSampleUploadLimitsV1.fromCanonicalBytes(
        smaller.canonicalBytes,
      ),
      smaller,
    );
    for (final field in defaults.toJson().keys) {
      expect(
        () => PlacementSampleUploadLimitsV1.fromJson(
          {...defaults.toJson(), field: 0},
        ),
        throwsA(_refusal),
      );
      expect(
        () => PlacementSampleUploadLimitsV1.fromJson({
          ...defaults.toJson(),
          field: (defaults.toJson()[field]! as int) + 1,
        }),
        throwsA(_refusal),
      );
    }
  });

  test('identities revisions and timestamps use exact existing grammars', () {
    final ticket = _ticket();
    final ref = _ref();
    for (final id in [
      '',
      _sampleId.toUpperCase(),
      '$_sampleId\n',
      'sample:1',
      _sampleId.replaceRange(14, 15, '3'),
    ]) {
      expect(() => PlacementSampleReadV1(sampleId: id), throwsA(_refusal));
      expect(
        () => PlacementSampleStoreV1(
          ticketId: id,
          manifestDigest: ticket.manifestDigest,
        ),
        throwsA(_refusal),
      );
      expect(
        () => PlacementSampleBindV1(sampleId: _sampleId, operationId: id),
        throwsA(_refusal),
      );
    }
    for (final value in [-1, kMaximumPortableJsonInteger + 1]) {
      expect(
        () => PlacementSampleUploadTicketV1.fromJson(
          {...ticket.toJson(), 'expiresAtMicros': value},
        ),
        throwsA(_refusal),
      );
    }
    for (final value in [0, -1, kMaximumPortableJsonInteger + 1]) {
      expect(
        () => PlacementScreenSampleRefV1.fromJson(
          {...ref.toJson(), 'bindingRevision': value},
        ),
        throwsA(_refusal),
      );
      expect(
        () => PlacementSampleBindV1(
          sampleId: _sampleId,
          operationId: _operationId,
          expectedBindingRevision: value,
        ),
        throwsA(_refusal),
      );
      expect(
        () => PlacementSampleDeleteV1(
          sampleId: _sampleId,
          operationId: _operationId,
          expectedBindingRevision: value,
        ),
        throwsA(_refusal),
      );
    }
  });

  test('read states distinguish available evidence absence and removal', () {
    final manifest = _manifest();
    final ref = _ref();
    final bound = PlacementSampleReadResultV1(
      sampleId: _sampleId,
      status: PlacementSampleStatusV1.bound,
      manifest: manifest,
      ref: ref,
      bindingRevision: 1,
    );
    expect(bound.ref, ref);
    final unbound = PlacementSampleReadResultV1(
      sampleId: _sampleId,
      status: PlacementSampleStatusV1.unbound,
      manifest: manifest,
    );
    expect(unbound.ref, isNull);
    for (final status in [
      PlacementSampleStatusV1.absent,
      PlacementSampleStatusV1.removed,
    ]) {
      final removed = PlacementSampleReadResultV1(
        sampleId: _sampleId,
        status: status,
        bindingRevision: status == PlacementSampleStatusV1.removed ? 2 : null,
      );
      expect(removed.manifest, isNull);
      expect(removed.ref, isNull);
      expect(
        () => PlacementSampleReadResultV1.fromJson(
          {...removed.toJson(), 'manifest': manifest.toJson()},
        ),
        throwsA(_refusal),
      );
    }
    for (final json in [
      {...bound.toJson(), 'ref': null},
      {...bound.toJson(), 'manifest': null},
      {...bound.toJson(), 'bindingRevision': 2},
      {
        ...bound.toJson(),
        'ref': {...ref.toJson(), 'target': _otherTarget().toJson()},
      },
      {
        ...bound.toJson(),
        'ref': {...ref.toJson(), 'imageSha256': 'sha256:${'a' * 64}'},
      },
      {
        ...bound.toJson(),
        'ref': {...ref.toJson(), 'sampleId': _ticketId},
      },
      {...unbound.toJson(), 'ref': ref.toJson()},
      {...unbound.toJson(), 'bindingRevision': 1},
    ]) {
      expect(
        () => PlacementSampleReadResultV1.fromJson(json),
        throwsA(_refusal),
      );
    }
    final removed = PlacementSampleDeleteResultV1(
      sampleId: _sampleId,
      status: PlacementSampleDeletionStatusV1.removed,
      bindingRevision: 2,
    );
    expect(removed.bindingRevision, 2);
    expect(
      () => PlacementSampleDeleteResultV1.fromJson(
        {...removed.toJson(), 'status': 'bound'},
      ),
      throwsA(_refusal),
    );
    expect(
      () => PlacementSampleDeleteResultV1(
        sampleId: _sampleId,
        status: PlacementSampleDeletionStatusV1.absent,
        bindingRevision: 2,
      ),
      throwsA(_refusal),
    );
  });

  test('every codec is canonical closed and excludes host data and image URLs',
      () {
    final manifest = _manifest();
    final values = <(CanonicalValue, CanonicalValue Function(List<int>))>[
      (_mount(), PlacementSampleMountV1.fromCanonicalBytes),
      (_capture(), PlacementScreenCaptureV1.fromCanonicalBytes),
      (manifest, PlacementScreenSampleManifestV1.fromCanonicalBytes),
      (
        PlacementSampleDraftV1(
          manifest: manifest,
          buildContract: _build(),
          reviewedDigest: manifest.reviewDigest,
        ),
        PlacementSampleDraftV1.fromCanonicalBytes
      ),
      (
        PlacementSamplePrepareV1(
          manifest: manifest,
          buildContract: _build(),
          reviewedDigest: manifest.reviewDigest,
          operationId: _operationId,
        ),
        PlacementSamplePrepareV1.fromCanonicalBytes
      ),
      (
        PlacementSampleUploadLimitsV1(),
        PlacementSampleUploadLimitsV1.fromCanonicalBytes
      ),
      (_ticket(), PlacementSampleUploadTicketV1.fromCanonicalBytes),
      (
        PlacementSampleStoreV1(
          ticketId: _ticketId,
          manifestDigest: manifest.manifestDigest,
        ),
        PlacementSampleStoreV1.fromCanonicalBytes
      ),
      (
        PlacementSampleStoredV1(
          sampleId: _sampleId,
          manifestDigest: manifest.manifestDigest,
          imageSha256: manifest.pngSha256,
        ),
        PlacementSampleStoredV1.fromCanonicalBytes
      ),
      (
        PlacementSampleBindV1(sampleId: _sampleId, operationId: _operationId),
        PlacementSampleBindV1.fromCanonicalBytes
      ),
      (_ref(), PlacementScreenSampleRefV1.fromCanonicalBytes),
      (
        PlacementSampleReadV1(sampleId: _sampleId),
        PlacementSampleReadV1.fromCanonicalBytes
      ),
      (
        PlacementSampleReadResultV1(
          sampleId: _sampleId,
          status: PlacementSampleStatusV1.bound,
          manifest: manifest,
          ref: _ref(),
          bindingRevision: 1,
        ),
        PlacementSampleReadResultV1.fromCanonicalBytes
      ),
      (
        PlacementSampleDeleteV1(sampleId: _sampleId, operationId: _operationId),
        PlacementSampleDeleteV1.fromCanonicalBytes
      ),
      (
        PlacementSampleDeleteResultV1(
          sampleId: _sampleId,
          status: PlacementSampleDeletionStatusV1.removed,
          bindingRevision: 2,
        ),
        PlacementSampleDeleteResultV1.fromCanonicalBytes
      ),
    ];
    for (final (value, decode) in values) {
      expect(decode(value.canonicalBytes), value);
      final json = value.toJson();
      for (final field in [
        'unknown',
        'hostData',
        'hostValues',
        'text',
        'routeName',
        'userId',
        'pngBytes',
        'imageUrl',
        'clipping',
        'overlayRect',
      ]) {
        expect(
          () => decode(CanonicalJsonCodec.encode({...json, field: 'private'})),
          throwsA(_refusal),
          reason: '${value.runtimeType}.$field',
        );
      }
      for (final field in json.keys) {
        expect(
          () => decode(CanonicalJsonCodec.encode({...json}..remove(field))),
          throwsA(_refusal),
          reason: '${value.runtimeType}.$field',
        );
      }
      expect(() => decode([...value.canonicalBytes, 0x20]), throwsA(_refusal));
      expect(
        () => decode(
          utf8.encode(const JsonEncoder.withIndent(' ').convert(json)),
        ),
        throwsA(_refusal),
      );
    }
    expect(
      () => PlacementSampleMountV1.fromJson({
        ..._mount().toJson(),
        'rect': {..._mount().rect.toJson(), 'hostData': 'private'},
      }),
      throwsA(_refusal),
    );
    expect(
      () => PlacementScreenSampleManifestV1.fromJson({
        ...manifest.toJson(),
        'logicalViewport': {
          ...manifest.logicalViewport.toJson(),
          'text': 'private',
        },
      }),
      throwsA(_refusal),
    );
    final json = manifest.toJson();
    (json['mounts']! as List<Object?>).clear();
    expect(manifest.mounts, hasLength(1));
    final bytes = manifest.canonicalBytes;
    manifest.canonicalBytes.fillRange(0, bytes.length, 0);
    expect(manifest.canonicalBytes, bytes);
  });
}

PlacementBuildContractV1 _build({int? ordinal}) => PlacementBuildContractV1(
      platform: 'ios',
      buildOrdinal: ordinal,
      mounts: [
        PlacementMountRequestV1(
          key: PlacementKeyV1.named(slug: 'home_message'),
          hostContractHash: _host.contentHash,
        ),
      ],
      contractsByHash: {_host.contentHash: _host},
      installedCapability: _capability,
      installedCapabilityHash: _capability.contentHash,
    );

PlacementSampleMountV1 _mount({
  int index = 0,
  double x = -0.5,
  PlacementKeyV1? key,
  String? hostHash,
}) =>
    PlacementSampleMountV1(
      key: key ?? PlacementKeyV1.named(slug: 'home_message'),
      hostContractHash: hostHash ?? _host.contentHash,
      occurrenceIndex: index,
      rect: PlacementLogicalRectV1.fromLogical(x: x, y: 0, width: 1, height: 1),
    );

PlacementScreenSampleManifestV1 _manifest({
  List<PlacementSampleMountV1>? mounts,
  String label = 'Home',
}) {
  final bytes = _flutterPng();
  return PlacementScreenSampleManifestV1(
    target: _target,
    appBuildContractHash: _build().appBuildContractHash,
    screenLabel: label,
    captureScope: PlacementScreenCaptureScopeV1.explicitBoundary,
    logicalViewport: PlacementLogicalSizeV1.fromLogical(width: 3, height: 2),
    rasterScale: PlacementRasterScaleV1.fromRequestedScale(1),
    pngWidth: 3,
    pngHeight: 2,
    pngByteLength: bytes.length,
    pngSha256: _hash(bytes),
    mounts: mounts ?? [_mount()],
  );
}

PlacementScreenCaptureV1 _capture({List<PlacementSampleMountV1>? mounts}) {
  final manifest = _manifest(mounts: mounts);
  return PlacementScreenCaptureV1(
    buildContract: _build(),
    appBuildContractHash: manifest.appBuildContractHash,
    screenLabel: manifest.screenLabel,
    captureScope: manifest.captureScope,
    logicalViewport: manifest.logicalViewport,
    rasterScale: manifest.rasterScale,
    pngWidth: manifest.pngWidth,
    pngHeight: manifest.pngHeight,
    pngByteLength: manifest.pngByteLength,
    pngSha256: manifest.pngSha256,
    mounts: manifest.mounts,
  );
}

PlacementSampleUploadTicketV1 _ticket() => PlacementSampleUploadTicketV1(
      ticketId: _ticketId,
      manifestDigest: _manifest().manifestDigest,
      imageSha256: _manifest().pngSha256,
      expiresAtMicros: 1791067200000000,
      limits: PlacementSampleUploadLimitsV1(),
    );

PlacementScreenSampleRefV1 _ref() => PlacementScreenSampleRefV1(
      target: _target,
      sampleId: _sampleId,
      appBuildContractHash: _manifest().appBuildContractHash,
      manifestDigest: _manifest().manifestDigest,
      imageSha256: _manifest().pngSha256,
      screenLabel: _manifest().screenLabel,
      bindingRevision: 1,
    );

TargetCoordinate _otherTarget() => TargetCoordinate(
      organizationId: OrganizationId(1),
      appId: ApplicationId(1),
      environmentTargetId: EnvironmentTargetId(2),
      namedEnvironmentId: NamedEnvironmentId(1),
      runtimePlane: RuntimePlane.sandbox,
    );

Uint8List _flutterPng() =>
    File('test/fixtures/placements/flutter_screen_sample.png')
        .readAsBytesSync();

String _hash(List<int> bytes) => 'sha256:${crypto.sha256.convert(bytes)}';

Uint8List _changedFlutterPng(Uint8List source) {
  final changed = Uint8List.fromList(source);
  final data = ByteData.sublistView(changed);
  var offset = 8;
  while (offset < changed.length) {
    final length = data.getUint32(offset);
    final type = String.fromCharCodes(changed.sublist(offset + 4, offset + 8));
    if (type == 'IDAT') {
      final codec = ZLibCodec(level: 1, windowBits: 9);
      final scanlines =
          codec.decode(changed.sublist(offset + 8, offset + 8 + length));
      scanlines[3] = 1;
      final encoded = codec.encode(scanlines);
      if (encoded.length != length) {
        throw StateError('Changed pixel encoding must preserve image length.');
      }
      changed.setRange(offset + 8, offset + 8 + length, encoded);
      data.setUint32(
        offset + 8 + length,
        _crc32(changed, offset + 4, offset + 8 + length),
      );
      return changed;
    }
    offset += length + 12;
  }
  throw StateError('Flutter PNG has no IDAT chunk.');
}

int _crc32(List<int> bytes, int start, int end) {
  var crc = 0xffffffff;
  for (var i = start; i < end; i++) {
    crc ^= bytes[i];
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) == 1 ? (crc >>> 1) ^ 0xedb88320 : crc >>> 1;
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}
