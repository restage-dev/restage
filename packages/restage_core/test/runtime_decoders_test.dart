import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:restage_shared/restage_shared.dart'
    show
        kIconThemeDataFallbackKey,
        kIconThemeDataLerpKey,
        kMaxStructuredCopyWithLayers,
        kSupportedCurveNames,
        kStructuredCopyWithKey;
import 'package:rfw/rfw.dart';

const _overlayBase = SystemUiOverlayStyle(
  statusBarColor: Color(0xFF112233),
  systemNavigationBarColor: Color(0xFF445566),
  systemNavigationBarDividerColor: Color(0xFF778899),
  statusBarBrightness: Brightness.dark,
  statusBarIconBrightness: Brightness.light,
  systemNavigationBarIconBrightness: Brightness.dark,
  systemNavigationBarContrastEnforced: true,
  systemStatusBarContrastEnforced: false,
);
const _overlayBaseWire = <String, Object?>{
  'statusBarColor': 0xFF112233,
  'systemNavigationBarColor': 0xFF445566,
  'systemNavigationBarDividerColor': 0xFF778899,
  'statusBarBrightness': 'dark',
  'statusBarIconBrightness': 'light',
  'systemNavigationBarIconBrightness': 'dark',
  'systemNavigationBarContrastEnforced': true,
  'systemStatusBarContrastEnforced': false,
};

void main() {
  group('RestageDecoders.systemUiOverlayStyle', () {
    test(
        'applies ordered copy layers with native null retention for all fields',
        () {
      final source = _MapDataSource({
        'overlay': {
          ..._overlayBaseWire,
          kStructuredCopyWithKey: [
            {
              'statusBarColor': 0x00000000,
              'systemNavigationBarColor': 0xFFABCDEF,
              'systemNavigationBarDividerColor': 0xFFFEDCBA,
              'statusBarBrightness': 'light',
              'statusBarIconBrightness': 'dark',
              'systemNavigationBarIconBrightness': 'light',
              'systemNavigationBarContrastEnforced': false,
              'systemStatusBarContrastEnforced': true,
            },
            {for (final field in _overlayBaseWire.keys) field: null},
            {
              'statusBarColor': 0xFF123456,
              'systemStatusBarContrastEnforced': false
            },
            <String, Object?>{},
          ],
        },
      });
      expect(
        RestageDecoders.systemUiOverlayStyle(source, const ['overlay']),
        _overlayBase
            .copyWith(
              statusBarColor: const Color(0x00000000),
              systemNavigationBarColor: const Color(0xFFABCDEF),
              systemNavigationBarDividerColor: const Color(0xFFFEDCBA),
              statusBarBrightness: Brightness.light,
              statusBarIconBrightness: Brightness.dark,
              systemNavigationBarIconBrightness: Brightness.light,
              systemNavigationBarContrastEnforced: false,
              systemStatusBarContrastEnforced: true,
            )
            .copyWith(
              statusBarColor: null,
              systemNavigationBarColor: null,
              systemNavigationBarDividerColor: null,
              statusBarBrightness: null,
              statusBarIconBrightness: null,
              systemNavigationBarIconBrightness: null,
              systemNavigationBarContrastEnforced: null,
              systemStatusBarContrastEnforced: null,
            )
            .copyWith(
              statusBarColor: const Color(0xFF123456),
              systemStatusBarContrastEnforced: false,
            )
            .copyWith(),
      );
    });

    test('nullable copy colors return to the base when data becomes missing',
        () {
      final overrides = <String, Object?>{};
      final source = _MapDataSource({
        'overlay': {
          ..._overlayBaseWire,
          kStructuredCopyWithKey: [overrides],
        },
      });
      for (final color in [null, 0xFFABCDEF, null]) {
        overrides
          ..clear()
          ..addAll({
            if (color != null) 'statusBarColor': color,
            if (color != null) 'systemNavigationBarColor': color,
            if (color != null) 'systemNavigationBarDividerColor': color,
          });
        final nativeColor = color == null ? null : Color(color);
        expect(
          RestageDecoders.systemUiOverlayStyle(source, const ['overlay']),
          _overlayBase.copyWith(
            statusBarColor: nativeColor,
            systemNavigationBarColor: nativeColor,
            systemNavigationBarDividerColor: nativeColor,
          ),
        );
      }
    });

    test('null and empty copy lists preserve the native base', () {
      for (final copies in [null, <Object?>[]]) {
        expect(
          RestageDecoders.systemUiOverlayStyle(
            _MapDataSource({
              'overlay': {..._overlayBaseWire, kStructuredCopyWithKey: copies},
            }),
            const ['overlay'],
          ),
          _overlayBase,
        );
      }
    });

    test('malformed copy layers reject the complete style', () {
      for (final copies in [
        false,
        0,
        1.5,
        'invalid',
        <String, Object?>{},
        [null],
        [false],
        [42],
        ['invalid'],
        [<Object?>[]],
        [
          {'statusBarColor': 0xFFABCDEF},
          {kStructuredCopyWithKey: <Object?>[]},
        ],
      ]) {
        expect(
          RestageDecoders.systemUiOverlayStyle(
            _MapDataSource({
              'overlay': {..._overlayBaseWire, kStructuredCopyWithKey: copies},
            }),
            const ['overlay'],
          ),
          isNull,
          reason: 'copyWith: $copies',
        );
      }
    });

    test(
        'copy layer bound accepts the limit and rejects excess without a partial style',
        () {
      final copies = <Object?>[
        for (var index = 0; index < kMaxStructuredCopyWithLayers; index++)
          {'statusBarColor': 0xFFABCDEF},
      ];
      final source = _MapDataSource({
        'overlay': {..._overlayBaseWire, kStructuredCopyWithKey: copies},
      });
      expect(
        RestageDecoders.systemUiOverlayStyle(source, const ['overlay']),
        _overlayBase.copyWith(statusBarColor: const Color(0xFFABCDEF)),
      );
      copies.add(<String, Object?>{});
      expect(
        RestageDecoders.systemUiOverlayStyle(source, const ['overlay']),
        isNull,
      );
    });

    test('matches every native overlay field', () {
      final source = _MapDataSource({
        'overlay': {
          'statusBarColor': 0x00000000,
          'statusBarBrightness': 'dark',
          'statusBarIconBrightness': 'light',
          'systemNavigationBarColor': 0xFF123456,
          'systemNavigationBarDividerColor': 0xFF654321,
          'systemNavigationBarIconBrightness': 'dark',
          'systemNavigationBarContrastEnforced': false,
          'systemStatusBarContrastEnforced': true,
        },
      });
      expect(
        RestageDecoders.systemUiOverlayStyle(source, const ['overlay']),
        const SystemUiOverlayStyle(
          statusBarColor: Color(0x00000000),
          statusBarBrightness: Brightness.dark,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: Color(0xFF123456),
          systemNavigationBarDividerColor: Color(0xFF654321),
          systemNavigationBarIconBrightness: Brightness.dark,
          systemNavigationBarContrastEnforced: false,
          systemStatusBarContrastEnforced: true,
        ),
      );
    });

    test('preserves partial styles and both contrast boolean values', () {
      final source = _MapDataSource({
        'overlay': {
          'statusBarIconBrightness': 'dark',
          'systemNavigationBarContrastEnforced': true,
          'systemStatusBarContrastEnforced': false,
        },
      });
      expect(
        RestageDecoders.systemUiOverlayStyle(source, const ['overlay']),
        const SystemUiOverlayStyle(
          statusBarIconBrightness: Brightness.dark,
          systemNavigationBarContrastEnforced: true,
          systemStatusBarContrastEnforced: false,
        ),
      );
    });

    test('distinguishes missing, null, empty and nullable-field styles', () {
      final source = _MapDataSource({
        'null': null,
        'invalid': 'style',
        'empty': <String, Object?>{},
        'nullable': {
          'statusBarColor': null,
          'statusBarBrightness': null,
          'statusBarIconBrightness': null,
          'systemNavigationBarColor': null,
          'systemNavigationBarDividerColor': null,
          'systemNavigationBarIconBrightness': null,
          'systemNavigationBarContrastEnforced': null,
          'systemStatusBarContrastEnforced': null,
        },
      });
      for (final key in ['missing', 'null', 'invalid']) {
        expect(RestageDecoders.systemUiOverlayStyle(source, [key]), isNull);
      }
      for (final key in ['empty', 'nullable']) {
        expect(
          RestageDecoders.systemUiOverlayStyle(source, [key]),
          const SystemUiOverlayStyle(),
        );
      }
    });
  });

  group('RestageDecoders.iconThemeData', () {
    test('matches every native icon field', () {
      final source = _MapDataSource({
        'icons': {
          'color': 0x80112233,
          'size': 31.5,
          'opacity': 0.75,
          'fill': 0.5,
          'weight': 550.5,
          'grade': -25.5,
          'opticalSize': 42.5,
          'shadows': [
            {
              'color': 0xFF445566,
              'offset': {'x': 2, 'y': -3},
              'blurRadius': 4,
            },
          ],
          'applyTextScaling': true,
        },
      });
      expect(
        RestageDecoders.iconThemeData(source, const ['icons']),
        const IconThemeData(
          color: Color(0x80112233),
          size: 31.5,
          opacity: 0.75,
          fill: 0.5,
          weight: 550.5,
          grade: -25.5,
          opticalSize: 42.5,
          shadows: [
            Shadow(
              color: Color(0xFF445566),
              offset: Offset(2, -3),
              blurRadius: 4,
            ),
          ],
          applyTextScaling: true,
        ),
      );
    });

    test('preserves false, zero, empty shadows and integer numeric inputs', () {
      final source = _MapDataSource({
        'icons': {
          'color': 0,
          'size': 0,
          'opacity': 0,
          'fill': 0,
          'weight': 400,
          'grade': 0,
          'opticalSize': 48,
          'shadows': <Object?>[],
          'applyTextScaling': false,
        },
      });
      expect(
        RestageDecoders.iconThemeData(source, const ['icons']),
        const IconThemeData(
          color: Color(0x00000000),
          size: 0,
          opacity: 0,
          fill: 0,
          weight: 400,
          grade: 0,
          opticalSize: 48,
          shadows: [],
          applyTextScaling: false,
        ),
      );
    });

    test('distinguishes missing, null, empty and nullable-field styles', () {
      final source = _MapDataSource({
        'null': null,
        'invalid': 'style',
        'empty': <String, Object?>{},
        'nullable': {
          'color': null,
          'size': null,
          'opacity': null,
          'fill': null,
          'weight': null,
          'grade': null,
          'opticalSize': null,
          'shadows': null,
          'applyTextScaling': null,
        },
      });
      for (final key in ['missing', 'null', 'invalid']) {
        expect(RestageDecoders.iconThemeData(source, [key]), isNull);
      }
      for (final key in ['empty', 'nullable']) {
        expect(
          RestageDecoders.iconThemeData(source, [key]),
          const IconThemeData(),
        );
      }
    });

    test('leaves native scalar behavior to IconThemeData', () {
      for (final opacity in [-1.0, 2.0, double.infinity, double.nan]) {
        final source = _MapDataSource({
          'icons': {'size': -4, 'grade': double.infinity, 'opacity': opacity},
        });
        expect(
          RestageDecoders.iconThemeData(source, const ['icons']),
          IconThemeData(size: -4, grade: double.infinity, opacity: opacity),
        );
      }
      for (final fields in [
        {'fill': -1},
        {'weight': 0},
        {'opticalSize': 0},
      ]) {
        expect(
          () => RestageDecoders.iconThemeData(
            _MapDataSource({'icons': fields}),
            const ['icons'],
          ),
          throwsAssertionError,
        );
      }
    });
  });

  group('RestageDecoders.iconThemeData operations', () {
    IconThemeData? decode(Object? wire) =>
        RestageDecoders.iconThemeData(_MapDataSource({'icons': wire}), const [
          'icons',
        ]);

    const start = IconThemeData(
      size: 18,
      weight: 400,
      opticalSize: 24,
      opacity: 0.25,
      color: Color(0xFF102030),
      shadows: [Shadow(blurRadius: 2)],
      applyTextScaling: false,
    );
    const startWire = <String, Object?>{
      'size': 18,
      'weight': 400,
      'opticalSize': 24,
      'opacity': 0.25,
      'color': 0xFF102030,
      'shadows': [
        {'blurRadius': 2},
      ],
      'applyTextScaling': false,
    };
    const end = IconThemeData(
      size: 30,
      fill: 1,
      weight: 700,
      grade: 25,
      opticalSize: 40,
      opacity: 1,
      applyTextScaling: true,
    );
    const endWire = <String, Object?>{
      'size': 30,
      'fill': 1,
      'weight': 700,
      'grade': 25,
      'opticalSize': 40,
      'opacity': 1,
      'applyTextScaling': true,
    };

    test('fallback is the native fallback theme', () {
      expect(
        decode({kIconThemeDataFallbackKey: true}),
        same(const IconThemeData.fallback()),
      );
      expect(decode({kIconThemeDataFallbackKey: false}), isNull);
    });

    test('copyWith layers apply native null retention in order', () {
      expect(
        decode({
          kIconThemeDataFallbackKey: true,
          kStructuredCopyWithKey: [
            {'size': 0, 'color': null, 'shadows': <Object?>[]},
            {'opacity': 2, 'applyTextScaling': null},
            <String, Object?>{},
          ],
        }),
        const IconThemeData.fallback()
            .copyWith(size: 0, shadows: []).copyWith(opacity: 2),
      );
    });

    void expectNative(Object? wire, IconThemeData Function() native) {
      final IconThemeData expected;
      try {
        expected = native();
      } on AssertionError {
        expect(() => decode(wire), throwsAssertionError);
        return;
      }
      expect(decode(wire), expected);
    }

    for (final t in [0.0, 0.25, 0.49, 0.5, 0.75, 1.0, -0.5, 1.5]) {
      test('lerp matches native interpolation and validation at $t', () {
        expectNative(
          {
            kIconThemeDataLerpKey: {'a': startWire, 'b': endWire, 't': t},
          },
          () => IconThemeData.lerp(start, end, t),
        );
        expectNative(
          {
            kIconThemeDataLerpKey: {'a': startWire, 't': t},
          },
          () => IconThemeData.lerp(start, null, t),
        );
        expectNative(
          {
            kIconThemeDataLerpKey: {'b': endWire, 't': t},
          },
          () => IconThemeData.lerp(null, end, t),
        );
      });
    }

    test('lerp of two null endpoints is an empty theme', () {
      expect(
        decode({
          kIconThemeDataLerpKey: {'t': 0.5},
        }),
        IconThemeData.lerp(null, null, 0.5),
      );
      expect(IconThemeData.lerp(null, null, 0.5), const IconThemeData());
    });

    test('nested lerp and copyWith compose like native calls', () {
      expect(
        decode({
          kIconThemeDataLerpKey: {
            'a': {kIconThemeDataFallbackKey: true},
            'b': {
              kIconThemeDataLerpKey: {'b': endWire, 't': 0.8},
              kStructuredCopyWithKey: [
                {'size': 12},
              ],
            },
            't': 0.5,
          },
          kStructuredCopyWithKey: [
            {'grade': 5},
          ],
        }),
        IconThemeData.lerp(
          const IconThemeData.fallback(),
          IconThemeData.lerp(null, end, 0.8).copyWith(size: 12),
          0.5,
        ).copyWith(grade: 5),
      );
    });

    test('malformed operations invalidate the whole theme', () {
      for (final wire in <Object?>[
        {kIconThemeDataFallbackKey: 'yes'},
        {kIconThemeDataLerpKey: 'lerp'},
        {
          kIconThemeDataLerpKey: <String, Object?>{'a': startWire},
        },
        {
          kIconThemeDataLerpKey: {'a': 'start', 't': 0.5},
        },
        {
          kIconThemeDataLerpKey: {
            'a': {kIconThemeDataFallbackKey: 1},
            't': 0.5,
          },
        },
        {
          kStructuredCopyWithKey: [
            {
              kStructuredCopyWithKey: <Object?>[],
            },
          ],
        },
        {
          kStructuredCopyWithKey: List<Object?>.filled(
            kMaxStructuredCopyWithLayers + 1,
            const <String, Object?>{},
          ),
        },
      ]) {
        expect(decode(wire), isNull, reason: '$wire');
      }
    });
  });

  group('RestageDecoders.appBarBottomHeight', () {
    const marker = r'$restage.constructor.presence';
    const value = r'$restage.constructor.value';
    double? decode(Object? wire) => RestageDecoders.appBarBottomHeight(
          _MapDataSource({'bottom': wire}),
          const ['bottom'],
        );

    test('reads plain heights and treats absence as no AppBar bottom', () {
      expect(decode(31.5), 31.5);
      expect(decode(0), 0.0);
      expect(decode(null), isNull);
    });

    test('a supplied null takes the standard toolbar height', () {
      expect(decode({marker: 1, value: 40}), 40.0);
      expect(decode({marker: 1}), 56.0);
      expect(decode({marker: 2, value: 40}), isNull);
      expect(decode(<String, Object?>{value: 40}), isNull);
    });
  });

  group('RestageDecoders.alignmentXY', () {
    test('decodes a {x, y} map to the concrete Alignment (value-asserted)', () {
      final source = _MapDataSource({
        'topRight': {'x': 1.0, 'y': -1.0},
        'center': {'x': 0.0, 'y': 0.0},
        'bottomLeft': {'x': -1.0, 'y': 1.0},
      });

      final topRight = RestageDecoders.alignmentXY(source, const ['topRight']);
      expect(topRight, isA<Alignment>());
      expect(topRight, Alignment.topRight);
      expect(topRight, const Alignment(1, -1));

      expect(
        RestageDecoders.alignmentXY(source, const ['center']),
        Alignment.center,
      );
      expect(
        RestageDecoders.alignmentXY(source, const ['bottomLeft']),
        Alignment.bottomLeft,
      );
    });

    test('coerces integer x/y components to doubles', () {
      final source = _MapDataSource({
        'topRight': {'x': 1, 'y': -1},
      });
      expect(
        RestageDecoders.alignmentXY(source, const ['topRight']),
        Alignment.topRight,
      );
    });

    test('returns null when the slot or a component is absent', () {
      final source = _MapDataSource({
        'partial': {'x': 1.0},
        'empty': <String, Object?>{},
      });
      expect(RestageDecoders.alignmentXY(source, const ['missing']), isNull);
      expect(RestageDecoders.alignmentXY(source, const ['partial']), isNull);
      expect(RestageDecoders.alignmentXY(source, const ['empty']), isNull);
    });
  });

  group('RestageDecoders.offset', () {
    test('decodes a {x, y} map to an Offset (value-asserted)', () {
      final source = _MapDataSource({
        'slide': {'x': 0.2, 'y': -0.3},
        'zero': {'x': 0.0, 'y': 0.0},
      });

      final slide = RestageDecoders.offset(source, const ['slide']);
      expect(slide, isA<Offset>());
      expect(slide, const Offset(0.2, -0.3));

      expect(RestageDecoders.offset(source, const ['zero']), Offset.zero);
    });

    test('coerces integer x/y components to doubles', () {
      final source = _MapDataSource({
        'p': {'x': 1, 'y': 2},
      });
      expect(RestageDecoders.offset(source, const ['p']), const Offset(1, 2));
    });

    test('returns null when the slot or a component is absent', () {
      final source = _MapDataSource({
        'partial': {'x': 1.0},
        'empty': <String, Object?>{},
      });
      expect(RestageDecoders.offset(source, const ['missing']), isNull);
      expect(RestageDecoders.offset(source, const ['partial']), isNull);
      expect(RestageDecoders.offset(source, const ['empty']), isNull);
    });
  });

  group('RestageDecoders.decorationImage', () {
    test(
        'decodes the self-describing map to a real DecorationImage with the '
        'right provider + fit + alignment (value-asserted)', () {
      final source = _MapDataSource({
        'image': {
          'image': {'kind': 'network', 'src': 'https://x/h.jpg'},
          'fit': 'cover',
          'alignment': {'x': 0.0, 'y': -1.0},
        },
      });

      final decoded = RestageDecoders.decorationImage(source, const ['image']);
      expect(decoded, isA<DecorationImage>());
      final provider = decoded!.image;
      expect(provider, isA<NetworkImage>());
      expect((provider as NetworkImage).url, 'https://x/h.jpg');
      expect(decoded.fit, BoxFit.cover);
      expect(decoded.alignment, Alignment.topCenter);
    });

    test('decodes an AssetImage provider', () {
      final source = _MapDataSource({
        'image': {
          'image': {'kind': 'asset', 'src': 'assets/bg.png'},
        },
      });

      final decoded = RestageDecoders.decorationImage(source, const ['image']);
      expect(decoded, isA<DecorationImage>());
      expect(decoded!.image, isA<AssetImage>());
      expect((decoded.image as AssetImage).assetName, 'assets/bg.png');
    });

    test('applies a NetworkImage scale from the provider map', () {
      final source = _MapDataSource({
        'image': {
          'image': {'kind': 'network', 'src': 'https://x/h.jpg', 'scale': 2.0},
        },
      });
      final decoded = RestageDecoders.decorationImage(source, const ['image'])!;
      final provider = decoded.image as NetworkImage;
      expect(provider.url, 'https://x/h.jpg');
      expect(provider.scale, 2.0);
    });

    test('applies an AssetImage package from the provider map', () {
      final source = _MapDataSource({
        'image': {
          'image': {'kind': 'asset', 'src': 'icons/heart.png', 'package': 'p'},
        },
      });
      final decoded = RestageDecoders.decorationImage(source, const ['image'])!;
      final provider = decoded.image as AssetImage;
      // AssetImage prefixes the package into the keyName (packages/<pkg>/…).
      expect(provider.package, 'p');
      expect(provider.keyName, 'packages/p/icons/heart.png');
    });

    test('provider-specific keys default when absent (scale 1.0, no package)',
        () {
      final source = _MapDataSource({
        'net': {
          'image': {'kind': 'network', 'src': 'u'},
        },
        'asset': {
          'image': {'kind': 'asset', 'src': 'a.png'},
        },
      });
      final net = RestageDecoders.decorationImage(source, const ['net'])!;
      expect((net.image as NetworkImage).scale, 1.0);
      final asset = RestageDecoders.decorationImage(source, const ['asset'])!;
      expect((asset.image as AssetImage).package, isNull);
    });

    test('threads repeat, opacity, and scale; defaults the rest', () {
      final source = _MapDataSource({
        'image': {
          'image': {'kind': 'network', 'src': 'https://x/h.jpg'},
          'repeat': 'repeatX',
          'opacity': 0.8,
          'scale': 2.0,
        },
      });

      final decoded = RestageDecoders.decorationImage(source, const ['image'])!;
      expect(decoded.repeat, ImageRepeat.repeatX);
      expect(decoded.opacity, 0.8);
      expect(decoded.scale, 2.0);
      // The omitted fields fall back to the DecorationImage ctor defaults.
      expect(decoded.fit, isNull);
      expect(decoded.alignment, Alignment.center);
    });

    test('coerces integer opacity/scale to doubles', () {
      final source = _MapDataSource({
        'image': {
          'image': {'kind': 'asset', 'src': 'a.png'},
          'opacity': 1,
          'scale': 3,
        },
      });
      final decoded = RestageDecoders.decorationImage(source, const ['image'])!;
      expect(decoded.opacity, 1.0);
      expect(decoded.scale, 3.0);
    });

    test('returns null when the slot, the provider, or the src is absent', () {
      final source = _MapDataSource({
        'noProvider': {'fit': 'cover'},
        'noSrc': {
          'image': {'kind': 'network'},
        },
        'unknownKind': {
          'image': {'kind': 'memory', 'src': 'x'},
        },
      });
      expect(
        RestageDecoders.decorationImage(source, const ['missing']),
        isNull,
      );
      // No provider -> no fabricated image (the caller's no-background default
      // applies) rather than a DecorationImage with a broken provider.
      expect(
        RestageDecoders.decorationImage(source, const ['noProvider']),
        isNull,
      );
      expect(
        RestageDecoders.decorationImage(source, const ['noSrc']),
        isNull,
      );
      // An unrecognized provider kind decodes to null — the codegen only emits
      // network/asset, so an unknown kind is never a fabricated wrong image.
      expect(
        RestageDecoders.decorationImage(source, const ['unknownKind']),
        isNull,
      );
    });
  });

  group('RestageDecoders.borderSide', () {
    test('decodes a {color, width, style} map to a BorderSide', () {
      final source = _MapDataSource({
        'side': {'color': 0xFF112233, 'width': 2.0, 'style': 'solid'},
      });

      final side = RestageDecoders.borderSide(source, const ['side']);
      expect(side, isA<BorderSide>());
      expect(side!.color, const Color(0xFF112233));
      expect(side.width, 2.0);
      expect(side.style, BorderStyle.solid);
    });

    test('applies the rfw color/width/style defaults for partial maps', () {
      // The rfw borderSide decoder fills defaults (black / 1.0 / solid) for
      // an absent key, so a partial map still decodes to a coherent side.
      final source = _MapDataSource({
        'side': {'width': 4.0},
      });
      final side = RestageDecoders.borderSide(source, const ['side']);
      expect(side, isA<BorderSide>());
      expect(side!.width, 4.0);
      expect(side.style, BorderStyle.solid);
    });

    test('returns null when the slot is absent', () {
      final source = _MapDataSource(<String, Object?>{});
      expect(RestageDecoders.borderSide(source, const ['side']), isNull);
    });
  });

  group('RestageDecoders.textStyle', () {
    test('decodes a flat map to a TextStyle (value-asserted)', () {
      // The same {fontSize, fontWeight: "w700", ...} shape the codegen emits
      // for a structured TextStyle slot (`FontWeight.bold` -> "w700").
      final source = _MapDataSource({
        'style': {
          'fontSize': 18.0,
          'fontWeight': 'w700',
          'color': 0xFF112233,
        },
      });

      final style = RestageDecoders.textStyle(source, const ['style']);
      expect(style, isA<TextStyle>());
      expect(style!.fontSize, 18.0);
      expect(style.fontWeight, FontWeight.w700);
      expect(style.color, const Color(0xFF112233));
    });

    test('coerces an integer fontSize to a double', () {
      final source = _MapDataSource({
        'style': {'fontSize': 18},
      });
      expect(
        RestageDecoders.textStyle(source, const ['style'])!.fontSize,
        18.0,
      );
    });

    test('returns null when the slot is absent or not a map', () {
      final source = _MapDataSource({'style': 'not a map'});
      expect(RestageDecoders.textStyle(source, const ['missing']), isNull);
      expect(RestageDecoders.textStyle(source, const ['style']), isNull);
    });

    test('decodes a valid fontFamilyFallback list', () {
      final source = _MapDataSource({
        'style': {
          'fontFamilyFallback': const ['Inter', 'Roboto'],
        },
      });
      final style = RestageDecoders.textStyle(source, const ['style']);
      expect(style!.fontFamilyFallback, ['Inter', 'Roboto']);
    });

    test(
        'DROPS a malformed nested fontFamilyFallback element rather than '
        'throwing — the nested fail-safe', () {
      // A non-string element in the NESTED `textStyle.fontFamilyFallback` (a
      // corrupt / tamper wire) must degrade, not throw and abort the render —
      // the same present-malformed convention as the top-level stringList
      // slots. (Covers `Text.rich` span styles too, which decode via the same
      // `_textStyle` through `_inlineSpan`.)
      final source = _MapDataSource({
        'style': {
          'fontFamilyFallback': const ['Inter', 42, 'Roboto'],
        },
      });
      final style = RestageDecoders.textStyle(source, const ['style']);
      expect(style!.fontFamilyFallback, ['Inter', 'Roboto']);
    });
  });

  group('RestageDecoders.shapeBorder', () {
    test('decodes rounded-superellipse, linear, and polygon shapes', () {
      final source = _MapDataSource({
        'roundedSuperellipse': {
          'type': 'roundedSuperellipse',
          'borderRadius': 12.0,
          'side': {'color': 0xFF112233, 'width': 2.0},
        },
        'linear': {
          'type': 'linear',
          'bottom': {'size': 0.75, 'alignment': 1.0},
        },
        'polygon': {
          'type': 'polygon',
          'sides': 5.0,
          'rotation': 15.0,
        },
      });

      final rounded = RestageDecoders.shapeBorder(
        source,
        const ['roundedSuperellipse'],
      );
      expect(rounded, isA<RoundedSuperellipseBorder>());
      final roundedSuperellipse = rounded! as RoundedSuperellipseBorder;
      expect(roundedSuperellipse.borderRadius, BorderRadius.circular(12));
      expect(roundedSuperellipse.side.color, const Color(0xFF112233));
      expect(roundedSuperellipse.side.width, 2.0);

      final linear = RestageDecoders.shapeBorder(source, const ['linear']);
      expect(linear, isA<LinearBorder>());
      final linearBorder = linear! as LinearBorder;
      expect(linearBorder.bottom, isNotNull);
      expect(linearBorder.bottom!.size, 0.75);
      expect(linearBorder.bottom!.alignment, 1.0);

      final polygon = RestageDecoders.shapeBorder(source, const ['polygon']);
      expect(polygon, isA<StarBorder>());
      final star = polygon! as StarBorder;
      expect(star.points, 5.0);
      expect(star.rotation, closeTo(15.0, 0.000001));
    });

    test('decodes a uniform or per-corner border radius', () {
      final source = _MapDataSource({
        'uniform': {'type': 'rounded', 'borderRadius': 6},
        'corners': {
          'type': 'continuous',
          'borderRadius': {'topLeft': 8.0, 'bottomRight': 2},
        },
      });

      final uniform = RestageDecoders.shapeBorder(source, const ['uniform']);
      expect(
        (uniform! as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(6),
      );
      final corners = RestageDecoders.shapeBorder(source, const ['corners']);
      expect(
        (corners! as ContinuousRectangleBorder).borderRadius,
        const BorderRadius.only(
          topLeft: Radius.circular(8),
          bottomRight: Radius.circular(2),
        ),
      );
    });

    test('decodes rounded, circle, stadium, continuous, beveled, star', () {
      final source = _MapDataSource({
        'rounded': {'type': 'rounded', 'borderRadius': 8.0},
        'circle': {'type': 'circle', 'eccentricity': 0.5},
        'stadium': {'type': 'stadium'},
        'continuous': {'type': 'continuous', 'borderRadius': 10.0},
        'beveled': {'type': 'beveled', 'borderRadius': 4.0},
        'star': {'type': 'star', 'points': 6.0, 'innerRadiusRatio': 0.5},
      });

      final rounded = RestageDecoders.shapeBorder(source, const ['rounded']);
      expect(rounded, isA<RoundedRectangleBorder>());
      expect(
        (rounded! as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(8),
      );

      final circle = RestageDecoders.shapeBorder(source, const ['circle']);
      expect(circle, isA<CircleBorder>());
      expect((circle! as CircleBorder).eccentricity, 0.5);

      final stadium = RestageDecoders.shapeBorder(source, const ['stadium']);
      expect(stadium, isA<StadiumBorder>());

      final continuous =
          RestageDecoders.shapeBorder(source, const ['continuous']);
      expect(continuous, isA<ContinuousRectangleBorder>());
      expect(
        (continuous! as ContinuousRectangleBorder).borderRadius,
        BorderRadius.circular(10),
      );

      final beveled = RestageDecoders.shapeBorder(source, const ['beveled']);
      expect(beveled, isA<BeveledRectangleBorder>());
      expect(
        (beveled! as BeveledRectangleBorder).borderRadius,
        BorderRadius.circular(4),
      );

      final star = RestageDecoders.shapeBorder(source, const ['star']);
      expect(star, isA<StarBorder>());
      final starBorder = star! as StarBorder;
      expect(starBorder.points, 6.0);
      expect(starBorder.innerRadiusRatio, 0.5);
    });

    test('combines a multi-shape list into a compound border', () {
      final source = _MapDataSource({
        'combine': [
          {'type': 'rounded', 'borderRadius': 8.0},
          {'type': 'circle'},
        ],
      });

      final combined = RestageDecoders.shapeBorder(source, const ['combine']);
      expect(combined, isA<ShapeBorder>());
      // Composing two shapes with `+` yields a compound border, not either
      // single shape.
      expect(combined, isNot(isA<RoundedRectangleBorder>()));
      expect(combined, isNot(isA<CircleBorder>()));
    });

    test('unknown type falls back to the rfw decoder (null here)', () {
      final source = _MapDataSource({
        'unknown': {'type': 'unknownXYZ'},
      });

      // The default branch delegates to the rfw decoder, which does not
      // recognize this synthetic type and returns null.
      expect(RestageDecoders.shapeBorder(source, const ['unknown']), isNull);
    });

    test('absent type returns null', () {
      final source =
          _MapDataSource(<String, Object?>{'absent': <String, Object?>{}});
      expect(RestageDecoders.shapeBorder(source, const ['absent']), isNull);
    });
  });

  group('RestageDecoders.fontVariations', () {
    test('decodes well-formed axis/value pairs', () {
      final source = _MapDataSource({
        'variations': [
          {'axis': 'wght', 'value': 700},
          {'axis': 'wdth', 'value': 87.5},
        ],
      });

      final variations =
          RestageDecoders.fontVariations(source, const ['variations']);
      expect(variations, [
        const FontVariation('wght', 700),
        const FontVariation('wdth', 87.5),
      ]);
    });

    test('skips a malformed entry without fabricating a default', () {
      final source = _MapDataSource({
        'variations': [
          {'axis': 'bad', 'value': 1.0}, // axis length != 4
          {'axis': 'wght', 'value': 600},
        ],
      });

      final variations =
          RestageDecoders.fontVariations(source, const ['variations']);
      expect(variations, isNotNull);
      expect(variations, isNot(contains(const FontVariation('wght', 400))));
      expect(variations, [const FontVariation('wght', 600)]);
    });

    test('returns null when every entry is malformed', () {
      final source = _MapDataSource({
        'variations': [
          {'axis': 'bad'},
          {'value': 1.0},
        ],
      });

      expect(
        RestageDecoders.fontVariations(source, const ['variations']),
        isNull,
      );
    });

    test('returns null when absent', () {
      expect(
        RestageDecoders.fontVariations(_MapDataSource(null), const ['x']),
        isNull,
      );
    });
  });

  group('RestageDecoders.fontFeatures', () {
    test('decodes a list of feature tags', () {
      final source = _MapDataSource({
        'features': [
          {'feature': 'smcp', 'value': 1},
          {'feature': 'liga', 'value': 0},
        ],
      });

      final features = RestageDecoders.fontFeatures(source, const ['features']);
      expect(features, [
        const FontFeature('smcp'),
        const FontFeature('liga', 0),
      ]);
    });

    test('returns null when absent', () {
      expect(
        RestageDecoders.fontFeatures(_MapDataSource(null), const ['x']),
        isNull,
      );
    });
  });

  group('RestageDecoders.shadows', () {
    test('preserves an explicitly empty list', () {
      expect(
        RestageDecoders.shadows(
          _MapDataSource({'shadows': <Object?>[]}),
          const ['shadows'],
        ),
        isEmpty,
      );
    });

    test('decodes a list of shadows', () {
      final source = _MapDataSource({
        'shadows': [
          {'color': 0xFF112233, 'blurRadius': 4.0, 'spreadRadius': 1.0},
        ],
      });

      final shadows = RestageDecoders.shadows(source, const ['shadows']);
      expect(shadows, isNotNull);
      expect(shadows!.single.color, const Color(0xFF112233));
      expect(shadows.single.blurRadius, 4.0);
    });

    test('returns null when absent', () {
      expect(
        RestageDecoders.shadows(_MapDataSource(null), const ['x']),
        isNull,
      );
    });
  });

  group('RestageDecoders.textDecoration', () {
    test('decodes a single decoration', () {
      final source = _MapDataSource({'deco': 'underline'});
      expect(
        RestageDecoders.textDecoration(source, const ['deco']),
        TextDecoration.underline,
      );
    });

    test('combines a list of decorations', () {
      final source = _MapDataSource({
        'deco': ['underline', 'lineThrough'],
      });
      final combined = RestageDecoders.textDecoration(source, const ['deco']);
      expect(combined, isNotNull);
      expect(combined!.contains(TextDecoration.underline), isTrue);
      expect(combined.contains(TextDecoration.lineThrough), isTrue);
    });

    test('returns null when absent', () {
      expect(
        RestageDecoders.textDecoration(_MapDataSource(null), const ['x']),
        isNull,
      );
    });
  });

  group('RestageDecoders.duration', () {
    test('decodes integer milliseconds', () {
      final source = _MapDataSource({'d': 250});
      expect(
        RestageDecoders.duration(source, const ['d']),
        const Duration(milliseconds: 250),
      );
    });

    test('returns null when absent', () {
      expect(
        RestageDecoders.duration(_MapDataSource(null), const ['x']),
        isNull,
      );
    });
  });

  group('RestageDecoders.curve', () {
    test('decodes supported curve names from a closed lookup table', () {
      const samples = <String, Curve>{
        'linear': Curves.linear,
        'easeIn': Curves.easeIn,
        'easeOut': Curves.easeOut,
        'easeInOut': Curves.easeInOut,
        'fastOutSlowIn': Curves.fastOutSlowIn,
        'bounceIn': Curves.bounceIn,
      };
      final source = _MapDataSource({
        for (final name in samples.keys) name: name,
      });

      for (final sample in samples.entries) {
        expect(
          RestageDecoders.curve(source, <Object>[sample.key]),
          sample.value,
        );
      }
    });

    test('returns null for absent, non-string, and unsupported curves', () {
      final source = _MapDataSource({
        'unsupported': 'customBezier',
        'nonString': 7,
      });

      expect(RestageDecoders.curve(source, const ['missing']), isNull);
      expect(RestageDecoders.curve(source, const ['nonString']), isNull);
      expect(RestageDecoders.curve(source, const ['unsupported']), isNull);
    });

    test('the decoder accept-set is exactly the shared curve vocabulary', () {
      // The build-time validator accepts exactly `kSupportedCurveNames`; this
      // pins the runtime decode-set equal to it, so the validator can never
      // falsely reject a name the decoder resolves, and can never pass a name
      // the decoder would silently drop.
      expect(
        RestageDecoders.supportedCurveNames,
        equals(kSupportedCurveNames.toSet()),
      );
    });

    test('every supported curve name decodes to a non-null curve', () {
      final source = _MapDataSource({
        for (final name in kSupportedCurveNames) name: name,
      });
      for (final name in kSupportedCurveNames) {
        expect(
          RestageDecoders.curve(source, <Object>[name]),
          isNotNull,
          reason: '$name is in the supported vocabulary but did not decode — a '
              'shipped blob carrying it would silently null to the framework '
              'default.',
        );
      }
    });

    test('a real but unsupported curve member decodes to null', () {
      // `fastEaseInToSlowEaseOut` is a genuine `Curves` member outside the
      // supported set — the exact silent-drop the build-time validator now
      // diagnoses. The decoder confirms it resolves to null here.
      final source = _MapDataSource({'c': 'fastEaseInToSlowEaseOut'});
      expect(RestageDecoders.curve(source, const ['c']), isNull);
    });
  });

  group('RestageDecoders.alignment repairs', () {
    test('repairs non-finite components and preserves both subtypes', () {
      final source = _MapDataSource({
        'cartesian': {'x': double.nan, 'y': 2.0},
        'directional': {'start': double.infinity, 'y': -1.0},
      });

      final cartesian = RestageDecoders.alignment(source, const ['cartesian']);
      expect(cartesian, isA<Alignment>());
      expect(cartesian, const Alignment(0, 2));

      final directional =
          RestageDecoders.alignment(source, const ['directional']);
      expect(directional, isA<AlignmentDirectional>());
      final value = directional! as AlignmentDirectional;
      expect(value.start, 0.0);
      expect(value.y, -1.0);
    });

    test('preserves negative, large, and ordinary finite components', () {
      final source = _MapDataSource({
        'negative': {'x': -4.0, 'y': -3.0},
        'large': {'x': 1e100, 'y': -1e100},
        'ordinary': {'start': 0.25, 'y': 0.75},
      });

      expect(
        RestageDecoders.alignment(source, const ['negative']),
        const Alignment(-4, -3),
      );
      expect(
        RestageDecoders.alignment(source, const ['large']),
        const Alignment(1e100, -1e100),
      );
      final ordinary = RestageDecoders.alignment(source, const ['ordinary']);
      expect(ordinary, isA<AlignmentDirectional>());
      final ordinaryValue = ordinary! as AlignmentDirectional;
      expect(ordinaryValue.start, 0.25);
      expect(ordinaryValue.y, 0.75);
    });

    test('prefers start when both coordinate keys are present', () {
      final source = _MapDataSource({
        'alignment': {'x': 10.0, 'start': 0.25, 'y': 0.75},
      });

      final decoded = RestageDecoders.alignment(source, const ['alignment']);
      expect(decoded, isA<AlignmentDirectional>());
      final value = decoded! as AlignmentDirectional;
      expect(value.start, 0.25);
      expect(value.y, 0.75);
    });

    test('returns null for an absent, non-map, or incomplete slot', () {
      final source = _MapDataSource({
        'notMap': 'center',
        'incomplete': {'x': 1.0},
      });

      expect(RestageDecoders.alignment(source, const ['missing']), isNull);
      expect(RestageDecoders.alignment(source, const ['notMap']), isNull);
      expect(RestageDecoders.alignment(source, const ['incomplete']), isNull);
    });
  });

  group('RestageDecoders.alignmentXY repairs', () {
    test('zeroes only a non-finite component', () {
      final source = _MapDataSource({
        'x': {'x': double.nan, 'y': 3.0},
        'y': {'x': -2.0, 'y': double.negativeInfinity},
      });

      expect(
        RestageDecoders.alignmentXY(source, const ['x']),
        const Alignment(0, 3),
      );
      expect(
        RestageDecoders.alignmentXY(source, const ['y']),
        const Alignment(-2, 0),
      );
    });

    test('preserves negative and large finite components', () {
      final source = _MapDataSource({
        'negative': {'x': -4.0, 'y': -3.0},
        'large': {'x': 1e100, 'y': -1e100},
      });

      expect(
        RestageDecoders.alignmentXY(source, const ['negative']),
        const Alignment(-4, -3),
      );
      expect(
        RestageDecoders.alignmentXY(source, const ['large']),
        const Alignment(1e100, -1e100),
      );
    });
  });

  group('RestageDecoders border width repairs', () {
    test('floors non-finite and negative side widths at zero', () {
      final source = _MapDataSource({
        'nan': {'width': double.nan},
        'infinite': {'width': double.infinity},
        'negative': {'width': -4.0},
      });

      expect(
        RestageDecoders.borderSide(source, const ['nan'])!.width,
        0.0,
      );
      expect(
        RestageDecoders.borderSide(source, const ['infinite'])!.width,
        0.0,
      );
      expect(
        RestageDecoders.borderSide(source, const ['negative'])!.width,
        0.0,
      );
    });

    test('preserves ordinary and large finite non-negative widths', () {
      final source = _MapDataSource({
        'ordinary': {'width': 2.5},
        'large': {'width': 2e100},
      });

      expect(
        RestageDecoders.borderSide(source, const ['ordinary'])!.width,
        2.5,
      );
      expect(
        RestageDecoders.borderSide(source, const ['large'])!.width,
        2e100,
      );
    });

    test('repairs a directional border and preserves the fallback chain', () {
      final source = _MapDataSource({
        'border': [
          {'color': 0xFF112233, 'width': double.nan},
          {'width': 2.0},
          null,
        ],
      });

      final decoded = RestageDecoders.border(source, const ['border']);
      expect(decoded, isA<BorderDirectional>());
      final border = decoded! as BorderDirectional;
      expect(border.start.width, 0.0);
      expect(border.start.color, const Color(0xFF112233));
      expect(border.top.width, 2.0);
      expect(border.end, border.start);
      expect(border.bottom, border.top);
    });

    test('repairs the side used by a shape border', () {
      final source = _MapDataSource({
        'shape': {
          'type': 'rounded',
          'side': {'width': double.nan},
        },
      });

      final decoded = RestageDecoders.shapeBorder(source, const ['shape']);
      expect(decoded, isA<RoundedRectangleBorder>());
      expect((decoded! as RoundedRectangleBorder).side.width, 0.0);
    });

    test('returns null when a side or border is absent', () {
      final source = _MapDataSource(<String, Object?>{});
      expect(RestageDecoders.borderSide(source, const ['side']), isNull);
      expect(RestageDecoders.border(source, const ['border']), isNull);
    });
  });

  group('RestageDecoders.constraintScalar', () {
    test('nulls non-finite values', () {
      final source = _MapDataSource({
        'nan': double.nan,
        'infinite': double.infinity,
      });

      expect(
        RestageDecoders.constraintScalar(source, const ['nan']),
        isNull,
      );
      expect(
        RestageDecoders.constraintScalar(source, const ['infinite']),
        isNull,
      );
    });

    test('preserves negative, ordinary, and large finite values', () {
      final source = _MapDataSource({
        'negative': -4.0,
        'ordinary': 24,
        'large': 2e100,
      });

      expect(
        RestageDecoders.constraintScalar(source, const ['negative']),
        -4.0,
      );
      expect(
        RestageDecoders.constraintScalar(source, const ['ordinary']),
        24.0,
      );
      expect(
        RestageDecoders.constraintScalar(source, const ['large']),
        2e100,
      );
    });

    test('returns null when absent', () {
      expect(
        RestageDecoders.constraintScalar(
          _MapDataSource(null),
          const ['missing'],
        ),
        isNull,
      );
    });
  });

  group('RestageDecoders.requiredLayoutScalar', () {
    test('throws a named error for absent, malformed, and non-finite values',
        () {
      const slot = 'LimitedBox.maxWidth';
      final source = _MapDataSource({
        'malformed': 'wide',
        'nan': double.nan,
        'infinite': double.infinity,
      });
      final namedError = isA<ArgumentError>().having(
        (error) => error.message,
        'message',
        contains(slot),
      );

      for (final path in ['missing', 'malformed', 'nan', 'infinite']) {
        expect(
          () => RestageDecoders.requiredLayoutScalar(
            source,
            <Object>[path],
            slot: slot,
          ),
          throwsA(namedError),
          reason: path,
        );
      }
    });

    test('throws a named error for a non-positive positive-only slot', () {
      const slot = 'AspectRatio.aspectRatio';
      final source = _MapDataSource({
        'zero': 0.0,
        'negative': -2.0,
      });
      final namedError = isA<ArgumentError>().having(
        (error) => error.message,
        'message',
        contains(slot),
      );

      for (final path in ['zero', 'negative']) {
        expect(
          () => RestageDecoders.requiredLayoutScalar(
            source,
            <Object>[path],
            slot: slot,
            mustBePositive: true,
          ),
          throwsA(namedError),
          reason: path,
        );
      }
    });

    test('accepts both number shapes and every permitted finite magnitude', () {
      final source = _MapDataSource({
        'integer': 24,
        'negative': -4.0,
        'zero': 0.0,
        'large': 2e100,
      });

      expect(
        RestageDecoders.requiredLayoutScalar(
          source,
          const ['integer'],
          slot: 'LimitedBox.maxWidth',
        ),
        24.0,
      );
      expect(
        RestageDecoders.requiredLayoutScalar(
          source,
          const ['negative'],
          slot: 'LimitedBox.maxWidth',
        ),
        -4.0,
      );
      expect(
        RestageDecoders.requiredLayoutScalar(
          source,
          const ['zero'],
          slot: 'LimitedBox.maxWidth',
        ),
        0.0,
      );
      expect(
        RestageDecoders.requiredLayoutScalar(
          source,
          const ['large'],
          slot: 'AspectRatio.aspectRatio',
          mustBePositive: true,
        ),
        2e100,
      );
    });
  });

  group('RestageDecoders.textMetric', () {
    test('nulls absent, malformed, and non-finite values', () {
      final source = _MapDataSource({
        'malformed': 'large',
        'nan': double.nan,
        'infinite': double.infinity,
      });

      expect(RestageDecoders.textMetric(source, const ['missing']), isNull);
      expect(RestageDecoders.textMetric(source, const ['malformed']), isNull);
      expect(RestageDecoders.textMetric(source, const ['nan']), isNull);
      expect(RestageDecoders.textMetric(source, const ['infinite']), isNull);
    });

    test('accepts both number shapes and preserves every finite value', () {
      final source = _MapDataSource({
        'integer': 24,
        'negative': -4.0,
        'large': 2e100,
      });

      expect(RestageDecoders.textMetric(source, const ['integer']), 24.0);
      expect(RestageDecoders.textMetric(source, const ['negative']), -4.0);
      expect(RestageDecoders.textMetric(source, const ['large']), 2e100);
    });
  });

  group('RestageDecoders.layoutFactor', () {
    test('nulls non-finite and negative factors', () {
      final source = _MapDataSource({
        'nan': double.nan,
        'infinite': double.infinity,
        'negative': -2.0,
      });

      expect(RestageDecoders.layoutFactor(source, const ['nan']), isNull);
      expect(RestageDecoders.layoutFactor(source, const ['infinite']), isNull);
      expect(RestageDecoders.layoutFactor(source, const ['negative']), isNull);
    });

    test('preserves ordinary and large finite non-negative factors', () {
      final source = _MapDataSource({
        'ordinary': 2,
        'large': 2e100,
      });

      expect(RestageDecoders.layoutFactor(source, const ['ordinary']), 2.0);
      expect(RestageDecoders.layoutFactor(source, const ['large']), 2e100);
    });

    test('returns null when absent', () {
      expect(
        RestageDecoders.layoutFactor(
          _MapDataSource(null),
          const ['missing'],
        ),
        isNull,
      );
    });
  });

  group('RestageDecoders.derivedSpacing', () {
    test('defaults an absent value to zero', () {
      expect(
        RestageDecoders.derivedSpacing(
          _MapDataSource(null),
          const ['missing'],
          4,
        ),
        0.0,
      );
    });

    test('accepts both number shapes and preserves ordinary values', () {
      final source = _MapDataSource({
        'double': 12.5,
        'integer': 12,
      });

      expect(
        RestageDecoders.derivedSpacing(source, const ['double'], 4),
        12.5,
      );
      expect(
        RestageDecoders.derivedSpacing(source, const ['integer'], 4),
        12.0,
      );
    });

    test('preserves a large value when the derived spacing remains finite', () {
      const spacing = 8e307;
      final source = _MapDataSource({'spacing': spacing});

      expect(
        RestageDecoders.derivedSpacing(source, const ['spacing'], 3),
        spacing,
      );
    });

    test('repairs an overflowing derived spacing to zero', () {
      final source = _MapDataSource({'spacing': 1e308});

      expect(
        RestageDecoders.derivedSpacing(source, const ['spacing'], 3),
        0.0,
      );
    });

    test('repairs non-finite authored spacing to zero', () {
      final source = _MapDataSource({
        'nan': double.nan,
        'infinite': double.infinity,
      });

      expect(
        RestageDecoders.derivedSpacing(source, const ['nan'], 3),
        0.0,
      );
      expect(
        RestageDecoders.derivedSpacing(source, const ['infinite'], 3),
        0.0,
      );
    });

    test('repairs negative spacing and preserves both signed zero values', () {
      for (final value in [-1.0, -double.maxFinite]) {
        expect(
            RestageDecoders.derivedSpacing(
              _MapDataSource({'spacing': value}),
              const ['spacing'],
              2,
            ),
            0.0);
      }
      for (final value in [0.0, -0.0]) {
        final spacing = RestageDecoders.derivedSpacing(
          _MapDataSource({'spacing': value}),
          const ['spacing'],
          2,
        );
        expect(spacing, 0.0);
        expect(spacing.isNegative, value.isNegative);
      }
    });

    test('preserves finite spacing with one child or no children', () {
      const spacing = 1.7e308;
      final source = _MapDataSource({'spacing': spacing});

      expect(
        RestageDecoders.derivedSpacing(source, const ['spacing'], 1),
        spacing,
      );
      expect(
        RestageDecoders.derivedSpacing(source, const ['spacing'], 0),
        spacing,
      );
    });
  });

  group('RestageDecoders.positiveLayoutScalar', () {
    test('nulls non-finite and non-positive scalars', () {
      final source = _MapDataSource({
        'nan': double.nan,
        'infinite': double.infinity,
        'zero': 0.0,
        'negative': -2.0,
      });

      expect(
        RestageDecoders.positiveLayoutScalar(source, const ['nan']),
        isNull,
      );
      expect(
        RestageDecoders.positiveLayoutScalar(source, const ['infinite']),
        isNull,
      );
      expect(
        RestageDecoders.positiveLayoutScalar(source, const ['zero']),
        isNull,
      );
      expect(
        RestageDecoders.positiveLayoutScalar(source, const ['negative']),
        isNull,
      );
    });

    test('accepts both number shapes and preserves finite positive values', () {
      final source = _MapDataSource({
        'ordinary': 2.5,
        'integer': 2,
        'large': 2e100,
      });

      expect(
        RestageDecoders.positiveLayoutScalar(source, const ['ordinary']),
        2.5,
      );
      expect(
        RestageDecoders.positiveLayoutScalar(source, const ['integer']),
        2.0,
      );
      expect(
        RestageDecoders.positiveLayoutScalar(source, const ['large']),
        2e100,
      );
    });

    test('returns null when absent', () {
      expect(
        RestageDecoders.positiveLayoutScalar(
          _MapDataSource(null),
          const ['missing'],
        ),
        isNull,
      );
    });
  });

  group('RestageDecoders.size repairs', () {
    test('nulls the whole size when either component is non-finite', () {
      final source = _MapDataSource({
        'width': {'width': double.nan, 'height': 4.0},
        'height': {'width': 4.0, 'height': double.infinity},
      });

      expect(RestageDecoders.size(source, const ['width']), isNull);
      expect(RestageDecoders.size(source, const ['height']), isNull);
    });

    test('floors a negative component without disturbing its sibling', () {
      final source = _MapDataSource({
        'width': {'width': -4.0, 'height': 7.0},
        'height': {'width': 7.0, 'height': -4.0},
      });

      expect(
        RestageDecoders.size(source, const ['width']),
        const Size(0, 7),
      );
      expect(
        RestageDecoders.size(source, const ['height']),
        const Size(7, 0),
      );
    });

    test('preserves ordinary and large finite non-negative sizes', () {
      final source = _MapDataSource({
        'ordinary': {'width': 24, 'height': 48},
        'large': {'width': 1e100, 'height': 2e100},
      });

      expect(
        RestageDecoders.size(source, const ['ordinary']),
        const Size(24, 48),
      );
      expect(
        RestageDecoders.size(source, const ['large']),
        const Size(1e100, 2e100),
      );
    });

    test('returns null when absent or incomplete', () {
      final source = _MapDataSource({
        'incomplete': {'width': 4.0},
      });

      expect(RestageDecoders.size(source, const ['missing']), isNull);
      expect(RestageDecoders.size(source, const ['incomplete']), isNull);
    });
  });
}

final class _MapDataSource implements DataSource {
  const _MapDataSource(this.root);

  final Object? root;

  @override
  T? v<T extends Object>(List<Object> argsKey) {
    final value = _lookup(argsKey);
    return value is T ? value : null;
  }

  @override
  bool isList(List<Object> argsKey) => _lookup(argsKey) is List<Object?>;

  @override
  int length(List<Object> argsKey) {
    final value = _lookup(argsKey);
    return value is List<Object?> ? value.length : 0;
  }

  @override
  bool isMap(List<Object> argsKey) => _lookup(argsKey) is Map<String, Object?>;

  @override
  Widget child(List<Object> argsKey) => ErrorWidget('missing child');

  @override
  List<Widget> childList(List<Object> argsKey) => const [];

  @override
  Widget builder(List<Object> argsKey, DynamicMap builderArg) =>
      ErrorWidget('missing builder');

  @override
  T? handler<T extends Function>(
    List<Object> argsKey,
    HandlerGenerator<T> generator,
  ) =>
      null;

  @override
  Widget? optionalBuilder(List<Object> argsKey, DynamicMap builderArg) => null;

  @override
  Widget? optionalChild(List<Object> argsKey) => null;

  @override
  VoidCallback? voidHandler(
    List<Object> argsKey, [
    DynamicMap? extraArguments,
  ]) =>
      null;

  Object? _lookup(List<Object> path) {
    Object? current = root;
    for (final segment in path) {
      if (current is Map<String, Object?> && segment is String) {
        current = current[segment];
      } else if (current is List<Object?> && segment is int) {
        if (segment < 0 || segment >= current.length) return null;
        current = current[segment];
      } else {
        return null;
      }
    }
    return current;
  }
}
