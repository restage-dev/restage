import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

void main() {
  test('the surface feature client floor is 9', () {
    expect(kSurfaceFeatureClientFloor, 9);
  });

  group('icon fonts section', () {
    test('a blob payload round-trips its icon fonts', () {
      final payload = _blob(
        iconFonts: [
          DeliveredIconFont(family: 'MaterialIcons', bytes: _bytes('m')),
          DeliveredIconFont(
            family: 'CupertinoIcons',
            fontPackage: 'cupertino_icons',
            bytes: _bytes('c'),
          ),
        ],
      );
      final decoded =
          SurfacePayload.decode(payload.canonicalBytes) as BlobSurfacePayload;
      expect(decoded, payload);
      expect(decoded.carriesSections, isTrue);
      expect(
        decoded.iconFonts.map((f) => f.family),
        ['CupertinoIcons', 'MaterialIcons'],
      );
      expect(decoded.iconFonts.first.fontPackage, 'cupertino_icons');
      expect(decoded.iconFonts.last.fontPackage, isNull);
      expect(decoded.iconFonts.last.bytes, _bytes('m'));
    });

    test('font order does not change the content hash', () {
      final a = DeliveredIconFont(family: 'A', bytes: _bytes('a'));
      final b = DeliveredIconFont(family: 'B', bytes: _bytes('b'));
      expect(
        _blob(iconFonts: [a, b]).contentHash,
        _blob(iconFonts: [b, a]).contentHash,
      );
    });

    test('font bytes are covered by the content hash', () {
      expect(
        _blob(iconFonts: [DeliveredIconFont(family: 'A', bytes: _bytes('a'))])
            .contentHash,
        isNot(
          _blob(
            iconFonts: [DeliveredIconFont(family: 'A', bytes: _bytes('b'))],
          ).contentHash,
        ),
      );
    });

    test('a duplicate family and package is refused', () {
      expect(
        () => _blob(
          iconFonts: [
            DeliveredIconFont(family: 'A', bytes: _bytes('a')),
            DeliveredIconFont(family: 'A', bytes: _bytes('b')),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('the same family from two packages is allowed', () {
      final payload = _blob(
        iconFonts: [
          DeliveredIconFont(family: 'A', bytes: _bytes('a')),
          DeliveredIconFont(family: 'A', fontPackage: 'p', bytes: _bytes('b')),
        ],
      );
      expect(payload.iconFonts, hasLength(2));
    });

    test('an empty family, package or font is refused', () {
      expect(
        () => DeliveredIconFont(family: '', bytes: _bytes('a')),
        throwsArgumentError,
      );
      expect(
        () =>
            DeliveredIconFont(family: 'A', fontPackage: '', bytes: _bytes('a')),
        throwsArgumentError,
      );
      expect(
        () => DeliveredIconFont(family: 'A', bytes: Uint8List(0)),
        throwsArgumentError,
      );
    });

    test('a flow payload round-trips its icon fonts', () {
      final payload = _flow(
        iconFonts: [DeliveredIconFont(family: 'A', bytes: _bytes('a'))],
      );
      final decoded =
          SurfacePayload.decode(payload.canonicalBytes) as FlowSurfacePayload;
      expect(decoded, payload);
      expect(decoded.iconFonts.single.family, 'A');
    });
  });

  group('local seeds section', () {
    test('a blob payload round-trips typed seed values', () {
      final payload = _blob(
        localSeeds: {
          'Survey': {
            'answer': '',
            'count': 3,
            'ratio': 0.5,
            'whole': 2.0,
            'enabled': true,
          },
        },
      );
      final decoded =
          SurfacePayload.decode(payload.canonicalBytes) as BlobSurfacePayload;
      expect(decoded, payload);
      final seeds = decoded.localSeeds['Survey']!;
      expect(seeds['answer'], '');
      expect(seeds['count'], isA<int>().having((v) => v, 'value', 3));
      expect(seeds['ratio'], 0.5);
      expect(seeds['whole'], isA<double>());
      expect(seeds['enabled'], isTrue);
    });

    test('an int and a whole double encode distinctly and round-trip', () {
      final asInt = _blob(
        localSeeds: {
          'R': {'n': 1},
        },
      );
      final asDouble = _blob(
        localSeeds: {
          'R': {'n': 1.0},
        },
      );
      expect(asInt.contentHash, isNot(asDouble.contentHash));
      final intBack =
          SurfacePayload.decode(asInt.canonicalBytes) as BlobSurfacePayload;
      final doubleBack =
          SurfacePayload.decode(asDouble.canonicalBytes) as BlobSurfacePayload;
      expect(intBack.localSeeds['R']!['n'], isA<int>());
      expect(doubleBack.localSeeds['R']!['n'], isA<double>());
      expect(intBack.contentHash, asInt.contentHash);
      expect(doubleBack.contentHash, asDouble.contentHash);
    });

    test('a decoded seed keeps its wire spelling', () {
      final plain = _blob().canonicalBytes;
      final bytes = (BytesBuilder()
            ..add(plain)
            ..add(_u32be(2))
            ..add(_u32be(1))
            ..add(_lp('R'))
            ..add(_u32be(1))
            ..add(_lp('n'))
            ..add(_u32be(3))
            ..add(_lp('2.50')))
          .toBytes();
      final decoded = SurfacePayload.decode(bytes);
      expect(decoded.localSeeds['R']!['n'], 2.5);
      expect(decoded.canonicalBytes, bytes);
      expect(
        decoded.contentHash,
        'sha256:${crypto.sha256.convert(bytes)}',
      );
    });

    test('seed order does not change the content hash', () {
      expect(
        _blob(
          localSeeds: {
            'B': {'y': 1, 'x': 2},
            'A': {'z': true},
          },
        ).contentHash,
        _blob(
          localSeeds: {
            'A': {'z': true},
            'B': {'x': 2, 'y': 1},
          },
        ).contentHash,
      );
    });

    test('an invalid key is refused', () {
      for (final key in ['', '1a', 'a-b', 'a' * 65, 'a.b']) {
        expect(
          () => _blob(
            localSeeds: {
              'Root': {key: 1},
            },
          ),
          throwsArgumentError,
          reason: key,
        );
      }
      expect(
        _blob(
          localSeeds: {
            'Root': {'_a${'b' * 62}': 1},
          },
        ).localSeeds['Root'],
        hasLength(1),
      );
    });

    test('a string over 4096 UTF-16 units is refused', () {
      expect(
        _blob(
          localSeeds: {
            'Root': {'a': 'x' * 4096},
          },
        ).localSeeds,
        hasLength(1),
      );
      expect(
        () => _blob(
          localSeeds: {
            'Root': {'a': 'x' * 4097},
          },
        ),
        throwsArgumentError,
      );
    });

    test('a non-finite number or an unsupported value is refused', () {
      for (final value in <Object>[double.nan, double.infinity, <int>[], {}]) {
        expect(
          () => _blob(
            localSeeds: {
              'Root': {'a': value},
            },
          ),
          throwsArgumentError,
          reason: '$value',
        );
      }
    });

    test('an empty root name or an empty root map is refused', () {
      expect(
        () => _blob(
          localSeeds: {
            '': {'a': 1},
          },
        ),
        throwsArgumentError,
      );
      expect(
        () => _blob(localSeeds: {'Root': {}}),
        throwsArgumentError,
      );
    });

    test('a flow seeds only its own screens', () {
      final payload = _flow(
        localSeeds: {
          'a_screen': {'answer': 'x'},
        },
      );
      final decoded =
          SurfacePayload.decode(payload.canonicalBytes) as FlowSurfacePayload;
      expect(decoded.localSeeds['a_screen'], {'answer': 'x'});
      expect(
        () => _flow(
          localSeeds: {
            'ghost': {'answer': 'x'},
          },
        ),
        throwsArgumentError,
      );
    });
  });

  group('client floor', () {
    test('a blob payload with a section below the floor is refused', () {
      expect(
        () => _blob(
          minClient: kSurfaceFeatureClientFloor - 1,
          localSeeds: {
            'Root': {'a': 1},
          },
        ),
        throwsArgumentError,
      );
      expect(
        () => _blob(
          minClient: kSurfaceFeatureClientFloor - 1,
          iconFonts: [DeliveredIconFont(family: 'A', bytes: _bytes('a'))],
        ),
        throwsArgumentError,
      );
    });

    test('a flow payload with a section below the floor is refused', () {
      expect(
        () => _flow(
          minClient: kSurfaceFeatureClientFloor - 1,
          localSeeds: {
            'a_screen': {'a': 1},
          },
        ),
        throwsArgumentError,
      );
    });

    test('a payload without sections keeps any floor', () {
      final payload = _blob(minClient: 3);
      expect(payload.carriesSections, isFalse);
    });
  });

  group('wire', () {
    test('a payload without sections keeps the pre-section bytes', () {
      final withNone = _blob(minClient: 3);
      final golden = _readGolden('paywall.surface_payload.golden.bin');
      final fromGolden = SurfacePayload.decode(golden) as BlobSurfacePayload;
      expect(
        BlobSurfacePayload(minClient: 3, blob: fromGolden.blob).canonicalBytes,
        golden,
      );
      expect(withNone.carriesSections, isFalse);
    });

    test('sections follow the required libraries in ascending tag order', () {
      final payload = _blob(
        iconFonts: [DeliveredIconFont(family: 'A', bytes: _bytes('a'))],
        localSeeds: {
          'R': {'k': true},
        },
      );
      final plain = _blob().canonicalBytes;
      final bytes = payload.canonicalBytes;
      expect(bytes.sublist(0, plain.length), plain);
      final tail = ByteData.sublistView(bytes, plain.length);
      expect(tail.getUint32(0), 1);
    });

    test('a section tag out of order is refused', () {
      final seeds = _blob(
        localSeeds: {
          'R': {'k': true},
        },
      ).canonicalBytes;
      final fonts = _blob(
        iconFonts: [DeliveredIconFont(family: 'A', bytes: _bytes('a'))],
      ).canonicalBytes;
      final plainLength = _blob().canonicalBytes.length;
      final swapped = (BytesBuilder()
            ..add(seeds)
            ..add(fonts.sublist(plainLength)))
          .toBytes();
      expect(() => SurfacePayload.decode(swapped), throwsFormatException);
    });

    test('an unknown section tag is refused', () {
      final bytes = (BytesBuilder()
            ..add(_blob().canonicalBytes)
            ..add(_u32be(9))
            ..add(_u32be(0)))
          .toBytes();
      expect(() => SurfacePayload.decode(bytes), throwsFormatException);
    });

    test('an empty section is refused as non-canonical', () {
      final bytes = (BytesBuilder()
            ..add(_blob().canonicalBytes)
            ..add(_u32be(1))
            ..add(_u32be(0)))
          .toBytes();
      expect(() => SurfacePayload.decode(bytes), throwsFormatException);
    });

    test('a section is refused when the caller disallows sections', () {
      final bytes = _blob(
        localSeeds: {
          'R': {'k': 1},
        },
      ).canonicalBytes;
      expect(
        () => SurfacePayload.decode(bytes, allowSections: false),
        throwsFormatException,
      );
      expect(
        SurfacePayload.decode(_blob().canonicalBytes, allowSections: false),
        _blob(),
      );
    });

    test('a decoded section below the floor is refused', () {
      final low = BlobSurfacePayload(
        minClient: kSurfaceFeatureClientFloor,
        blob: _bytes('blob'),
        localSeeds: const {
          'R': {'k': 1},
        },
      ).canonicalBytes;
      // Rewrite the u32 minClient that follows the "blob" kind frame.
      final tampered = Uint8List.fromList(low);
      ByteData.sublistView(tampered).setUint32(8, 3);
      expect(() => SurfacePayload.decode(tampered), throwsFormatException);
    });
  });

  group('payload format version', () {
    test('only a sectioned frame needs the sections format', () {
      expect(surfaceArtifactPayloadFormatVersionFor(_blob()), 1);
      expect(
        surfaceArtifactPayloadFormatVersionFor(
          _blob(
            localSeeds: {
              'R': {'k': 1},
            },
          ),
        ),
        kSurfaceArtifactSectionsPayloadFormatVersion,
      );
      expect(kMaxSupportedSurfaceArtifactPayloadFormatVersion, 2);
    });

    test('sections are allowed only from the sections format', () {
      expect(surfaceArtifactFrameAllowsSections(1), isFalse);
      expect(surfaceArtifactFrameAllowsSections(2), isTrue);
    });
  });

  group('envelope', () {
    test('a sectioned document round-trips under the sections version', () {
      final document = _document(
        _blob(
          iconFonts: [DeliveredIconFont(family: 'A', bytes: _bytes('a'))],
          localSeeds: {
            'R': {'k': 'v'},
          },
        ),
      );
      final bytes = SurfaceDocumentCodec.encode(document);
      expect(_header(bytes)['formatVersion'], 3);
      expect(SurfaceDocumentCodec.decode(bytes), document);
    });

    test('a document without sections still writes version 2', () {
      final bytes = SurfaceDocumentCodec.encode(_document(_blob()));
      expect(_header(bytes)['formatVersion'], 2);
    });

    test('a version-2 envelope carrying sections is refused', () {
      final payload = _blob(
        localSeeds: {
          'R': {'k': 1},
        },
      );
      final bytes = SurfaceDocumentCodec.encode(_document(payload));
      final header = _header(bytes)..['formatVersion'] = 2;
      expect(
        () => SurfaceDocumentCodec.decode(
          _envelope(header, payload.canonicalBytes),
        ),
        throwsFormatException,
      );
    });

    test('a version above 3 is refused', () {
      final payload = _blob();
      final bytes = SurfaceDocumentCodec.encode(_document(payload));
      final header = _header(bytes)..['formatVersion'] = 4;
      expect(
        () => SurfaceDocumentCodec.decode(
          _envelope(header, payload.canonicalBytes),
        ),
        throwsFormatException,
      );
    });
  });
}

Uint8List _bytes(String marker) => Uint8List.fromList(utf8.encode(marker));

BlobSurfacePayload _blob({
  int minClient = kSurfaceFeatureClientFloor,
  List<DeliveredIconFont> iconFonts = const [],
  Map<String, Map<String, Object>> localSeeds = const {},
}) =>
    BlobSurfacePayload(
      minClient: minClient,
      blob: _bytes('blob'),
      iconFonts: iconFonts,
      localSeeds: localSeeds,
    );

FlowSurfacePayload _flow({
  int minClient = kSurfaceFeatureClientFloor,
  List<DeliveredIconFont> iconFonts = const [],
  Map<String, Map<String, Object>> localSeeds = const {},
}) {
  final blob = _bytes('screen');
  final json = <String, Object?>{
    'flow': 'one_screen',
    'initial': 'a_screen',
    'minClient': minClient,
    'schemaVersion': 1,
    'screenArtifacts': {
      'a_screen': {
        'contentHash': 'sha256:${crypto.sha256.convert(blob)}',
        'minClient': 3,
        'path': 'a_screen.rfw',
        'schemaVersion': 1,
        'version': 1,
      },
    },
    'states': {
      'a_screen': {
        'kind': 'screen',
        'screen': 'a_screen',
        'on': {
          'act': {'target': 'done', 'type': 'goto'},
        },
      },
      'done': {'kind': 'end', 'result': <String, Object?>{}},
    },
    'version': 1,
  };
  return FlowSurfacePayload(
    flowDocument: FlowDocumentCodec.decodeJson(jsonEncode(json)),
    screenBlobs: {'a_screen': blob},
    iconFonts: iconFonts,
    localSeeds: localSeeds,
  );
}

SurfaceDocument _document(BlobSurfacePayload payload) => SurfaceDocument(
      surfaceType: Surface.general,
      surfaceSlug: 'feedback',
      version: 1,
      minClient: payload.minClient,
      payload: payload,
      publishedAt: DateTime.utc(2026),
    );

Map<String, Object?> _header(Uint8List envelope) {
  final length = ByteData.sublistView(envelope).getUint32(0);
  return jsonDecode(utf8.decode(envelope.sublist(4, 4 + length)))
      as Map<String, Object?>;
}

Uint8List _envelope(Map<String, Object?> header, List<int> payload) {
  final sorted = <String, Object?>{
    for (final key in header.keys.toList()..sort()) key: header[key],
  };
  final headerBytes = utf8.encode(jsonEncode(sorted));
  return (BytesBuilder()
        ..add(_u32be(headerBytes.length))
        ..add(headerBytes)
        ..add(payload))
      .toBytes();
}

Uint8List _lp(String text) {
  final bytes = utf8.encode(text);
  return (BytesBuilder()
        ..add(_u32be(bytes.length))
        ..add(bytes))
      .toBytes();
}

Uint8List _u32be(int value) {
  final bytes = Uint8List(4);
  ByteData.view(bytes.buffer).setUint32(0, value);
  return bytes;
}

Uint8List _readGolden(String name) {
  const dir = 'test/surface_document/goldens';
  final workspace = File('packages/restage_shared/$dir/$name');
  return (workspace.existsSync() ? workspace : File('$dir/$name'))
      .readAsBytesSync();
}
