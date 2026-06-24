import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restage_core/restage_core.dart';
import 'package:restage_shared/restage_shared.dart' show kSupportedCurveNames;
import 'package:rfw/rfw.dart';

void main() {
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
