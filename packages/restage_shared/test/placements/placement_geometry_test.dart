import 'dart:convert';

import 'package:restage_measurement_schema/restage_measurement_schema.dart';
import 'package:restage_shared/restage_shared.dart';
import 'package:test/test.dart';

const _maximumUnits = 67108864;
const _throwsCanonical = TypeMatcher<CanonicalFormatException>();

void main() {
  group('PlacementLogicalSizeV1', () {
    test('quantizes once and exposes logical pixels from integer units', () {
      final size = PlacementLogicalSizeV1.fromLogical(
        width: 1.5001,
        height: 2.0001,
      );
      expect(size.widthUnits, 1536);
      expect(size.heightUnits, 2048);
      expect(size.width, 1.5);
      expect(size.height, 2);
    });

    test('rounds positive ties away from zero and refuses quantized zero', () {
      final size = PlacementLogicalSizeV1.fromLogical(
        width: 0.5 / 1024,
        height: 2.5 / 1024,
      );
      expect(size.widthUnits, 1);
      expect(size.heightUnits, 3);
      for (final value in [0.25 / 1024, 0.0, -0.5 / 1024]) {
        expect(
          () => PlacementLogicalSizeV1.fromLogical(width: value, height: 1),
          throwsArgumentError,
        );
        expect(
          () => PlacementLogicalSizeV1.fromLogical(width: 1, height: value),
          throwsArgumentError,
        );
      }
    });

    test('admits the exact positive integer and logical boundaries', () {
      final size = PlacementLogicalSizeV1(
        widthUnits: 1,
        heightUnits: _maximumUnits,
      );
      expect(size.width, 1 / 1024);
      expect(size.height, 65536);
      expect(
        PlacementLogicalSizeV1.fromLogical(width: 1 / 1024, height: 65536),
        size,
      );
      for (final value in [-1, 0, _maximumUnits + 1, 9007199254740992]) {
        expect(
          () => PlacementLogicalSizeV1(widthUnits: value, heightUnits: 1),
          throwsArgumentError,
        );
        expect(
          () => PlacementLogicalSizeV1(widthUnits: 1, heightUnits: value),
          throwsArgumentError,
        );
      }
    });

    test('rejects nonfinite and out-of-range sizes before quantization', () {
      for (final value in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
        65536 + 0.25 / 1024,
      ]) {
        expect(
          () => PlacementLogicalSizeV1.fromLogical(width: value, height: 1),
          throwsArgumentError,
        );
        expect(
          () => PlacementLogicalSizeV1.fromLogical(width: 1, height: value),
          throwsArgumentError,
        );
      }
    });

    test('compares both dimensions and keeps encoding copies independent', () {
      final size = PlacementLogicalSizeV1(widthUnits: 1536, heightUnits: 2048);
      final decoded = PlacementLogicalSizeV1.fromCanonicalBytes(
        size.canonicalBytes,
      );
      expect(decoded, size);
      expect(decoded.hashCode, size.hashCode);
      expect(
        size,
        isNot(PlacementLogicalSizeV1(widthUnits: 1537, heightUnits: 2048)),
      );
      expect(
        size,
        isNot(PlacementLogicalSizeV1(widthUnits: 1536, heightUnits: 2049)),
      );
      size.toJson()['widthUnits'] = 1;
      size.canonicalBytes[0] = 0;
      expect(size.widthUnits, 1536);
      expect(
        utf8.decode(size.canonicalBytes),
        '{"heightUnits":2048,"widthUnits":1536}',
      );
    });
  });

  group('PlacementLogicalRectV1', () {
    test('rounds signed position ties away from zero', () {
      final rect = PlacementLogicalRectV1.fromLogical(
        x: -0.5 / 1024,
        y: 0.5 / 1024,
        width: 1.5 / 1024,
        height: 2.5 / 1024,
      );
      expect(rect.xUnits, -1);
      expect(rect.yUnits, 1);
      expect(rect.widthUnits, 2);
      expect(rect.heightUnits, 3);
      expect(rect.x, -1 / 1024);
      expect(rect.y, 1 / 1024);
      expect(rect.width, 2 / 1024);
      expect(rect.height, 3 / 1024);
    });

    test('admits off-screen positions and all exact geometry boundaries', () {
      final rect = PlacementLogicalRectV1.fromLogical(
        x: -65536,
        y: 65536,
        width: 1 / 1024,
        height: 65536,
      );
      expect(
        rect,
        PlacementLogicalRectV1(
          xUnits: -_maximumUnits,
          yUnits: _maximumUnits,
          widthUnits: 1,
          heightUnits: _maximumUnits,
        ),
      );
      expect(rect.x, -65536);
      expect(rect.y, 65536);
    });

    test('rejects nonfinite and out-of-range positions before quantization',
        () {
      for (final value in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
        -65536 - 0.25 / 1024,
        65536 + 0.25 / 1024,
      ]) {
        expect(
          () => PlacementLogicalRectV1.fromLogical(
            x: value,
            y: 0,
            width: 1,
            height: 1,
          ),
          throwsArgumentError,
        );
        expect(
          () => PlacementLogicalRectV1.fromLogical(
            x: 0,
            y: value,
            width: 1,
            height: 1,
          ),
          throwsArgumentError,
        );
      }
      for (final value in [-_maximumUnits - 1, _maximumUnits + 1]) {
        expect(
          () => PlacementLogicalRectV1(
            xUnits: value,
            yUnits: 0,
            widthUnits: 1,
            heightUnits: 1,
          ),
          throwsArgumentError,
        );
        expect(
          () => PlacementLogicalRectV1(
            xUnits: 0,
            yUnits: value,
            widthUnits: 1,
            heightUnits: 1,
          ),
          throwsArgumentError,
        );
      }
    });

    test('refuses nonpositive and quantized-zero dimensions', () {
      for (final value in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
        65536 + 0.25 / 1024,
        -1.0,
        0.0,
        0.25 / 1024,
      ]) {
        expect(
          () => PlacementLogicalRectV1.fromLogical(
            x: 0,
            y: 0,
            width: value,
            height: 1,
          ),
          throwsArgumentError,
        );
        expect(
          () => PlacementLogicalRectV1.fromLogical(
            x: 0,
            y: 0,
            width: 1,
            height: value,
          ),
          throwsArgumentError,
        );
      }
      expect(
        () => PlacementLogicalRectV1(
          xUnits: 0,
          yUnits: 0,
          widthUnits: 0,
          heightUnits: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => PlacementLogicalRectV1(
          xUnits: 0,
          yUnits: 0,
          widthUnits: 1,
          heightUnits: _maximumUnits + 1,
        ),
        throwsArgumentError,
      );
    });

    test('equality includes every coordinate and dimension', () {
      final rect = PlacementLogicalRectV1(
        xUnits: -512,
        yUnits: 1536,
        widthUnits: 3072,
        heightUnits: 5120,
      );
      final decoded = PlacementLogicalRectV1.fromCanonicalBytes(
        rect.canonicalBytes,
      );
      expect(decoded, rect);
      expect(decoded.hashCode, rect.hashCode);
      for (final field in rect.toJson().keys) {
        final changed = rect.toJson();
        changed[field] = (changed[field]! as int) + 1;
        expect(PlacementLogicalRectV1.fromJson(changed), isNot(rect));
      }
      expect(
        rect,
        isNot(PlacementLogicalSizeV1(widthUnits: 3072, heightUnits: 5120)),
      );
    });
  });

  group('PlacementRasterScaleV1', () {
    test('quantizes the requested scale once and returns the actual ratio', () {
      final scale = PlacementRasterScaleV1.fromRequestedScale(1.5001);
      expect(scale.numerator, 3);
      expect(scale.denominator, 2);
      expect(scale.value, 1.5);
      expect(
        PlacementRasterScaleV1.fromRequestedScale(1536.5 / 1024),
        PlacementRasterScaleV1(numerator: 1537, denominator: 1024),
      );
      expect(
        PlacementRasterScaleV1.fromRequestedScale(128.5 / 1024),
        PlacementRasterScaleV1(numerator: 129, denominator: 1024),
      );
    });

    test('preserves every admitted 1/1024 scale after reduction', () {
      for (var units = 128; units <= 4096; units++) {
        final scale = PlacementRasterScaleV1.fromRequestedScale(units / 1024);
        expect(scale.value, units / 1024, reason: '$units/1024');
        expect(scale.numerator.gcd(scale.denominator), 1);
        expect(scale.denominator, inInclusiveRange(1, 1024));
        expect(scale.numerator, inInclusiveRange(1, 4096));
      }
    });

    test('rejects requested scales outside bounds before quantization', () {
      for (final value in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
        -1.0,
        0.0,
        1 / 8 - 0.25 / 1024,
        4 + 0.25 / 1024,
      ]) {
        expect(
          () => PlacementRasterScaleV1.fromRequestedScale(value),
          throwsArgumentError,
        );
      }
    });

    test('rejects bad denominators, nonreduced ratios and range violations',
        () {
      for (final (numerator, denominator) in [
        (0, 1),
        (-1, 1),
        (1, 0),
        (1, -1),
        (129, 1025),
        (4097, 1024),
        (1, 9),
        (5, 1),
        (2, 2),
        (128, 1024),
        (9007199254740992, 1),
        (1, 9007199254740992),
      ]) {
        expect(
          () => PlacementRasterScaleV1(
            numerator: numerator,
            denominator: denominator,
          ),
          throwsArgumentError,
          reason: '$numerator/$denominator',
        );
        expect(
          () => PlacementRasterScaleV1.fromJson({
            'numerator': numerator,
            'denominator': denominator,
          }),
          throwsA(_throwsCanonical),
          reason: 'JSON $numerator/$denominator',
        );
      }
    });

    test('admits ratio and field boundaries with value equality', () {
      final minimum = PlacementRasterScaleV1.fromRequestedScale(1 / 8);
      final maximum = PlacementRasterScaleV1.fromRequestedScale(4);
      expect(minimum, PlacementRasterScaleV1(numerator: 1, denominator: 8));
      expect(maximum, PlacementRasterScaleV1(numerator: 4, denominator: 1));
      expect(minimum.value, 1 / 8);
      expect(maximum.value, 4);
      final nearMaximum = PlacementRasterScaleV1(
        numerator: 4095,
        denominator: 1024,
      );
      final decoded = PlacementRasterScaleV1.fromCanonicalBytes(
        nearMaximum.canonicalBytes,
      );
      expect(decoded, nearMaximum);
      expect(decoded.hashCode, nearMaximum.hashCode);
      expect(decoded, isNot(minimum));
      expect(decoded, isNot(maximum));
      final scale = PlacementRasterScaleV1(numerator: 3, denominator: 2);
      expect(
        scale,
        isNot(PlacementRasterScaleV1(numerator: 1, denominator: 2)),
      );
      expect(
        scale,
        isNot(PlacementRasterScaleV1(numerator: 3, denominator: 4)),
      );
    });
  });

  final codecs = <({
    String name,
    Map<String, Object?> json,
    String canonical,
    List<int> bytes,
    Object Function(Object?) decode,
    Object Function(List<int>) decodeBytes,
  })>[
    (
      name: 'size',
      json: {'widthUnits': 1536, 'heightUnits': 2048},
      canonical: '{"heightUnits":2048,"widthUnits":1536}',
      bytes: PlacementLogicalSizeV1(widthUnits: 1536, heightUnits: 2048)
          .canonicalBytes,
      decode: PlacementLogicalSizeV1.fromJson,
      decodeBytes: PlacementLogicalSizeV1.fromCanonicalBytes,
    ),
    (
      name: 'rectangle',
      json: {
        'xUnits': -512,
        'yUnits': 1536,
        'widthUnits': 3072,
        'heightUnits': 5120,
      },
      canonical:
          '{"heightUnits":5120,"widthUnits":3072,"xUnits":-512,"yUnits":1536}',
      bytes: PlacementLogicalRectV1(
        xUnits: -512,
        yUnits: 1536,
        widthUnits: 3072,
        heightUnits: 5120,
      ).canonicalBytes,
      decode: PlacementLogicalRectV1.fromJson,
      decodeBytes: PlacementLogicalRectV1.fromCanonicalBytes,
    ),
    (
      name: 'scale',
      json: {'numerator': 3, 'denominator': 2},
      canonical: '{"denominator":2,"numerator":3}',
      bytes:
          PlacementRasterScaleV1(numerator: 3, denominator: 2).canonicalBytes,
      decode: PlacementRasterScaleV1.fromJson,
      decodeBytes: PlacementRasterScaleV1.fromCanonicalBytes,
    ),
  ];
  for (final codec in codecs) {
    group('${codec.name} canonical codec', () {
      test('pins integer-only bytes and roundtrips without normalization', () {
        expect(
          codec.bytes,
          utf8.encode(codec.canonical),
        );
        expect(
          codec.decodeBytes(utf8.encode(codec.canonical)),
          codec.decode(codec.json),
        );
        expect(
          CanonicalJsonCodec.encode(codec.json),
          utf8.encode(codec.canonical),
        );
      });

      test('rejects missing, extra, noninteger and nonobject input', () {
        for (final field in codec.json.keys) {
          expect(
            () => codec.decode({...codec.json}..remove(field)),
            throwsA(_throwsCanonical),
            reason: 'missing $field',
          );
          for (final value in <Object?>[
            null,
            1.0,
            true,
            '1',
            <Object?>[],
            <String, Object?>{'value': 1},
          ]) {
            expect(
              () => codec.decode({...codec.json, field: value}),
              throwsA(_throwsCanonical),
              reason: '$field: $value',
            );
          }
        }
        for (final field in ['hostContext', 'text', 'route', 'userId']) {
          expect(
            () => codec.decode({...codec.json, field: 'extra'}),
            throwsA(_throwsCanonical),
          );
          expect(
            () => codec.decodeBytes(
              CanonicalJsonCodec.encode({...codec.json, field: 'extra'}),
            ),
            throwsA(_throwsCanonical),
          );
        }
        for (final value in <Object?>[null, true, 1, 'text', <Object?>[]]) {
          expect(() => codec.decode(value), throwsA(_throwsCanonical));
          expect(
            () => codec.decodeBytes(CanonicalJsonCodec.encode(value)),
            throwsA(_throwsCanonical),
          );
        }
      });

      test('rejects alternate byte spellings and malformed UTF-8', () {
        final firstKey = codec.canonical.indexOf(':');
        final duplicate = '${codec.canonical.substring(0, firstKey + 1)}1,'
            '${codec.canonical.substring(1)}';
        final integerAsDouble =
            codec.canonical.replaceFirst(RegExp(r':-?\d+'), ':1.0');
        for (final source in [
          ' ${codec.canonical}',
          '${codec.canonical}\n',
          codec.canonical.replaceFirst(':', ': '),
          jsonEncode(codec.json),
          duplicate,
          integerAsDouble,
          '{}',
          'not JSON',
        ]) {
          expect(
            () => codec.decodeBytes(utf8.encode(source)),
            throwsA(_throwsCanonical),
            reason: source,
          );
        }
        expect(
          () => codec
              .decodeBytes([0xef, 0xbb, 0xbf, ...utf8.encode(codec.canonical)]),
          throwsA(_throwsCanonical),
        );
        expect(() => codec.decodeBytes([0xff]), throwsA(_throwsCanonical));
      });
    });
  }

  test('integer bounds apply to decoded size and rectangle fields', () {
    for (final codec in codecs.take(2)) {
      for (final field in codec.json.keys) {
        final position = field == 'xUnits' || field == 'yUnits';
        for (final value in [
          _maximumUnits + 1,
          if (position) -_maximumUnits - 1 else 0,
          9007199254740992,
        ]) {
          expect(
            () => codec.decode({...codec.json, field: value}),
            throwsA(_throwsCanonical),
            reason: '${codec.name} $field: $value',
          );
        }
      }
    }
    expect(
      () => PlacementLogicalRectV1.fromCanonicalBytes(
        utf8.encode('{"heightUnits":1,"widthUnits":1,"xUnits":-0,"yUnits":0}'),
      ),
      throwsA(_throwsCanonical),
    );
  });

  group('placementRasterExtentIsConsistent', () {
    test('uses ceil with exactly one pixel tolerance at a fractional edge', () {
      final scale = PlacementRasterScaleV1(numerator: 1, denominator: 1);
      for (final pixels in [1, 2, 3]) {
        expect(
          placementRasterExtentIsConsistent(
            pixels: pixels,
            logicalUnits: 1025,
            scale: scale,
          ),
          isTrue,
          reason: 'ceil(1025/1024) is 2; $pixels is within one pixel',
        );
      }
      expect(
        placementRasterExtentIsConsistent(
          pixels: 4,
          logicalUnits: 1025,
          scale: scale,
        ),
        isFalse,
      );
    });

    test('keeps exact extents and fractional rational scales consistent', () {
      final scale = PlacementRasterScaleV1(numerator: 3, denominator: 2);
      for (final pixels in [7, 8, 9]) {
        expect(
          placementRasterExtentIsConsistent(
            pixels: pixels,
            logicalUnits: 5121,
            scale: scale,
          ),
          isTrue,
        );
      }
      for (final pixels in [6, 10]) {
        expect(
          placementRasterExtentIsConsistent(
            pixels: pixels,
            logicalUnits: 5121,
            scale: scale,
          ),
          isFalse,
        );
      }
      expect(
        placementRasterExtentIsConsistent(
          pixels: 6,
          logicalUnits: 4096,
          scale: scale,
        ),
        isTrue,
      );
    });

    test('covers smallest and largest extents without losing integer precision',
        () {
      final minimumScale = PlacementRasterScaleV1(numerator: 1, denominator: 8);
      final maximumScale = PlacementRasterScaleV1(numerator: 4, denominator: 1);
      expect(
        placementRasterExtentIsConsistent(
          pixels: 1,
          logicalUnits: 1,
          scale: minimumScale,
        ),
        isTrue,
      );
      for (final pixels in [262143, 262144, 262145]) {
        expect(
          placementRasterExtentIsConsistent(
            pixels: pixels,
            logicalUnits: _maximumUnits,
            scale: maximumScale,
          ),
          isTrue,
        );
      }
      expect(
        placementRasterExtentIsConsistent(
          pixels: 262146,
          logicalUnits: _maximumUnits,
          scale: maximumScale,
        ),
        isFalse,
      );
      final largeDividendScale = PlacementRasterScaleV1(
        numerator: 4095,
        denominator: 1024,
      );
      expect(
        placementRasterExtentIsConsistent(
          pixels: 262080,
          logicalUnits: _maximumUnits - 1,
          scale: largeDividendScale,
        ),
        isTrue,
      );
      expect(
        placementRasterExtentIsConsistent(
          pixels: 262082,
          logicalUnits: _maximumUnits - 1,
          scale: largeDividendScale,
        ),
        isFalse,
      );
    });

    test('refuses nonpositive, out-of-range and nonportable input', () {
      final scale = PlacementRasterScaleV1(numerator: 1, denominator: 8);
      for (final pixels in [-1, 0, 9007199254740991, 9007199254740992]) {
        expect(
          placementRasterExtentIsConsistent(
            pixels: pixels,
            logicalUnits: 8192,
            scale: scale,
          ),
          isFalse,
        );
      }
      for (final logicalUnits in [-1, 0, _maximumUnits + 1, 9007199254740992]) {
        expect(
          placementRasterExtentIsConsistent(
            pixels: logicalUnits > 0 ? 8193 : 1,
            logicalUnits: logicalUnits,
            scale: scale,
          ),
          isFalse,
        );
      }
    });
  });
}
