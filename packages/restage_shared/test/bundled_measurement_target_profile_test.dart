import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  test('recognizes only exact source-owned bundled asset paths', () {
    expect(
      isMeasurementBundledSourceOwnedBundleAssetPathV1(
        'assets/restage/bundles/lib/paywalls/upgrade.rsbundle',
      ),
      isTrue,
    );
    expect(
      isMeasurementBundledSourceOwnedBundleAssetPathV1(
        'assets/restage/measurement/target-profile.v1.json',
      ),
      isFalse,
    );
    expect(
      isMeasurementBundledSourceOwnedBundleAssetPathV1(
        'assets/restage/bundles/lib/../upgrade.rsbundle',
      ),
      isFalse,
    );
  });

  test('encodes canonical bytes and sorts the selected bundle profile', () {
    final profile = MeasurementBundledTargetProfileV1(
      targetCanonicalBytes: utf8.encode('{"target":1}'),
      registryCanonicalBytes: utf8.encode('{"registry":1}'),
      bundles: <MeasurementBundledTargetProfileBundle>[
        _bundle('assets/restage/bundles/lib/z.rsbundle', 'b'),
        _bundle('assets/restage/bundles/lib/a.rsbundle', 'a'),
      ],
    );

    final decoded = MeasurementBundledTargetProfileV1.fromCanonicalBytes(
      profile.canonicalBytes,
    );

    expect(decoded.targetCanonicalBytes, utf8.encode('{"target":1}'));
    expect(decoded.registryCanonicalBytes, utf8.encode('{"registry":1}'));
    expect(
      decoded.bundles.map((bundle) => bundle.assetPath),
      <String>[
        'assets/restage/bundles/lib/a.rsbundle',
        'assets/restage/bundles/lib/z.rsbundle',
      ],
    );
    expect(
      profile.canonicalByteLength,
      profile.canonicalBytes.length,
    );
    expect(
      utf8.decode(profile.canonicalBytes),
      profile.encodeCanonicalJson(),
    );
  });

  test('rejects an empty, duplicate, or non-source-owned bundle profile', () {
    final duplicate = _bundle('assets/restage/bundles/lib/a.rsbundle', 'a');

    expect(
      () => MeasurementBundledTargetProfileV1(
        targetCanonicalBytes: const <int>[1],
        registryCanonicalBytes: const <int>[2],
        bundles: const <MeasurementBundledTargetProfileBundle>[],
      ),
      throwsArgumentError,
    );
    expect(
      () => MeasurementBundledTargetProfileV1.decodeCanonicalJson(
        _profileSource(bundles: '[]'),
      ),
      throwsFormatException,
    );
    expect(
      () => MeasurementBundledTargetProfileV1(
        targetCanonicalBytes: const <int>[1],
        registryCanonicalBytes: const <int>[2],
        bundles: <MeasurementBundledTargetProfileBundle>[
          duplicate,
          duplicate,
        ],
      ),
      throwsArgumentError,
    );
    expect(
      () => MeasurementBundledTargetProfileBundle(
        assetPath: 'assets/restage/measurement/target-profile.v1.json',
        sha256: 'sha256:${'a' * 64}',
      ),
      throwsFormatException,
    );
  });

  test('rejects a noncanonical or malformed profile asset', () {
    final profile = MeasurementBundledTargetProfileV1(
      targetCanonicalBytes: const <int>[1],
      registryCanonicalBytes: const <int>[2],
      bundles: <MeasurementBundledTargetProfileBundle>[
        _bundle('assets/restage/bundles/lib/app.rsbundle', 'a'),
      ],
    ).encodeCanonicalJson();

    expect(
      () => MeasurementBundledTargetProfileV1.decodeCanonicalJson(
        profile.replaceFirst('{', '{ '),
      ),
      throwsFormatException,
    );
    expect(
      () => MeasurementBundledTargetProfileV1.decodeCanonicalJson(
        profile.replaceFirst('"AQ"', '"AQ="'),
      ),
      throwsFormatException,
    );
  });

  test('admits exact target and registry byte bounds and rejects max plus one',
      () {
    final bundle = _bundle('assets/restage/bundles/lib/app.rsbundle', 'a');
    final targetAtMaximum = Uint8List(
      kMaximumMeasurementBundledTargetProfileTargetCanonicalBytes,
    );
    final registryAtMaximum = Uint8List(
      kMaximumMeasurementBundledTargetProfileRegistryCanonicalBytes,
    );
    final targetProfile = MeasurementBundledTargetProfileV1(
      targetCanonicalBytes: targetAtMaximum,
      registryCanonicalBytes: const <int>[1],
      bundles: <MeasurementBundledTargetProfileBundle>[bundle],
    );
    final registryProfile = MeasurementBundledTargetProfileV1(
      targetCanonicalBytes: const <int>[1],
      registryCanonicalBytes: registryAtMaximum,
      bundles: <MeasurementBundledTargetProfileBundle>[bundle],
    );

    expect(
      MeasurementBundledTargetProfileV1.fromCanonicalBytes(
        targetProfile.canonicalBytes,
      ).targetCanonicalBytes.length,
      kMaximumMeasurementBundledTargetProfileTargetCanonicalBytes,
    );
    expect(
      MeasurementBundledTargetProfileV1.fromCanonicalBytes(
        registryProfile.canonicalBytes,
      ).registryCanonicalBytes.length,
      kMaximumMeasurementBundledTargetProfileRegistryCanonicalBytes,
    );
    expect(
      () => MeasurementBundledTargetProfileV1(
        targetCanonicalBytes: Uint8List(
          kMaximumMeasurementBundledTargetProfileTargetCanonicalBytes + 1,
        ),
        registryCanonicalBytes: const <int>[1],
        bundles: <MeasurementBundledTargetProfileBundle>[bundle],
      ),
      throwsArgumentError,
    );
    expect(
      () => MeasurementBundledTargetProfileV1(
        targetCanonicalBytes: const <int>[1],
        registryCanonicalBytes: Uint8List(
          kMaximumMeasurementBundledTargetProfileRegistryCanonicalBytes + 1,
        ),
        bundles: <MeasurementBundledTargetProfileBundle>[bundle],
      ),
      throwsArgumentError,
    );
  });

  test('rejects max plus one base64 fields before base64 decoding', () {
    final targetOverlong = 'A' *
        (_base64UrlLength(
              kMaximumMeasurementBundledTargetProfileTargetCanonicalBytes,
            ) +
            1);
    final registryOverlong = 'A' *
        (_base64UrlLength(
              kMaximumMeasurementBundledTargetProfileRegistryCanonicalBytes,
            ) +
            1);

    expect(
      () => MeasurementBundledTargetProfileV1.decodeCanonicalJson(
        _profileSource(targetCanonicalBytes: targetOverlong),
      ),
      throwsFormatException,
    );
    expect(
      () => MeasurementBundledTargetProfileV1.decodeCanonicalJson(
        _profileSource(registryCanonicalBytes: registryOverlong),
      ),
      throwsFormatException,
    );
  });

  test(
      'admits 1,024 bundle records and rejects raw and constructed '
      'max plus one', () {
    final bundles = List<MeasurementBundledTargetProfileBundle>.generate(
      kMaximumMeasurementBundledTargetProfileBundleCount,
      (index) => _bundle(
        'assets/restage/bundles/lib/$index.rsbundle',
        (index % 16).toRadixString(16),
      ),
    );
    final profile = MeasurementBundledTargetProfileV1(
      targetCanonicalBytes: const <int>[1],
      registryCanonicalBytes: const <int>[2],
      bundles: bundles,
    );

    expect(
      MeasurementBundledTargetProfileV1.fromCanonicalBytes(
        profile.canonicalBytes,
      ).bundles,
      hasLength(kMaximumMeasurementBundledTargetProfileBundleCount),
    );
    expect(
      () => MeasurementBundledTargetProfileV1(
        targetCanonicalBytes: const <int>[1],
        registryCanonicalBytes: const <int>[2],
        bundles: <MeasurementBundledTargetProfileBundle>[
          ...bundles,
          _bundle('assets/restage/bundles/lib/overflow.rsbundle', 'a'),
        ],
      ),
      throwsArgumentError,
    );
    expect(
      () => MeasurementBundledTargetProfileV1.decodeCanonicalJson(
        _profileSource(
          bundles: '[${List<String>.filled(
            kMaximumMeasurementBundledTargetProfileBundleCount + 1,
            'null',
          ).join(',')}]',
        ),
      ),
      throwsFormatException,
    );
  });

  test('pins the closed maximum profile shape and asset-path ceiling', () {
    final maximumAssetPath = _maximumAssetPath();
    final maximumPathBundle = _bundle(maximumAssetPath, 'a');
    final profile = MeasurementBundledTargetProfileV1(
      targetCanonicalBytes: Uint8List(
        kMaximumMeasurementBundledTargetProfileTargetCanonicalBytes,
      ),
      registryCanonicalBytes: Uint8List(
        kMaximumMeasurementBundledTargetProfileRegistryCanonicalBytes,
      ),
      bundles: <MeasurementBundledTargetProfileBundle>[maximumPathBundle],
    );
    final maximumBundleRecordBytes = profile.canonicalByteLength -
        127 -
        _base64UrlLength(
          kMaximumMeasurementBundledTargetProfileTargetCanonicalBytes,
        ) -
        _base64UrlLength(
          kMaximumMeasurementBundledTargetProfileRegistryCanonicalBytes,
        );

    expect(
      utf8.encode(maximumAssetPath).length,
      kMaximumMeasurementBundledTargetProfileBundleAssetPathUtf8Bytes,
    );
    expect(maximumBundleRecordBytes, 99 + 393050);
    expect(
      kMaximumMeasurementBundledTargetProfileAssetBytes,
      profile.canonicalByteLength +
          ((kMaximumMeasurementBundledTargetProfileBundleCount - 1) *
              maximumBundleRecordBytes) +
          (kMaximumMeasurementBundledTargetProfileBundleCount - 1),
    );
    expect(kMaximumMeasurementBundledTargetProfileAssetBytes, 447325652);
    expect(
      () => MeasurementBundledTargetProfileBundle(
        assetPath: _maximumAssetPath(extraControlByte: true),
        sha256: 'sha256:${'a' * 64}',
      ),
      throwsFormatException,
    );
  });

  test('rejects a raw max plus one profile before reading its bytes', () {
    final oversized = _LengthOnlyByteList(
      kMaximumMeasurementBundledTargetProfileAssetBytes + 1,
    );

    expect(
      () => MeasurementBundledTargetProfileV1.fromCanonicalBytes(oversized),
      throwsFormatException,
    );
    expect(oversized.elementReads, 0);
  });
}

MeasurementBundledTargetProfileBundle _bundle(String path, String hash) =>
    MeasurementBundledTargetProfileBundle(
      assetPath: path,
      sha256: 'sha256:${hash * 64}',
    );

String _profileSource({
  String targetCanonicalBytes = 'AQ',
  String registryCanonicalBytes = 'AQ',
  String? bundles,
}) {
  final selectedBundles = bundles ??
      '[{"assetPath":"assets/restage/bundles/lib/app.rsbundle",'
          '"sha256":"sha256:${'a' * 64}"}]';
  return '{"bundles":$selectedBundles,'
      '"kind":"measurementBundledTargetProfile",'
      '"registryCanonicalBytes":"$registryCanonicalBytes",'
      '"schemaVersion":1,'
      '"targetCanonicalBytes":"$targetCanonicalBytes"}';
}

String _maximumAssetPath({bool extraControlByte = false}) {
  const prefix = 'assets/restage/bundles/';
  const suffix = '.rsbundle';
  final controls =
      kMaximumMeasurementBundledTargetProfileBundleAssetPathUtf8Bytes -
          utf8.encode(prefix).length -
          utf8.encode(suffix).length +
          (extraControlByte ? 1 : 0);
  return '$prefix${'\u0001' * controls}$suffix';
}

int _base64UrlLength(int byteLength) {
  final paddedLength = ((byteLength + 2) ~/ 3) * 4;
  return switch (byteLength % 3) {
    1 => paddedLength - 2,
    2 => paddedLength - 1,
    _ => paddedLength,
  };
}

final class _LengthOnlyByteList extends ListBase<int> {
  _LengthOnlyByteList(this._length);

  final int _length;
  int elementReads = 0;

  @override
  int get length => _length;

  @override
  set length(int value) => throw UnsupportedError('immutable');

  @override
  int operator [](int index) {
    elementReads += 1;
    throw StateError('element access is forbidden');
  }

  @override
  void operator []=(int index, int value) =>
      throw UnsupportedError('immutable');
}
