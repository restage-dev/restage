import 'dart:ui' show ColorSpace;
import 'package:flutter/material.dart' show Colors;
import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'lookalike.dart' as lookalike;
import 'native_constants.dart' as native;
import 'package:flutter_svg/flutter_svg.dart';

Object stringPicture() => SvgPicture.string(
  '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10" viewBox="0 0 10 10"><path fill="currentColor" d="M0 0h4v10H0z"/></svg>',
  width: 24,
  height: 20,
  semanticsLabel: 'Mark',
  matchTextDirection: true,
  theme: const SvgTheme(fontSize: 20),
  colorFilter: const ColorFilter.mode(Color(0xffaa0000), BlendMode.srcIn),
);
Object bytesPicture() =>
    SvgPicture.memory(Uint8List.fromList([60, 115, 118, 103, 47, 62]));
Object assetPicture() => SvgPicture.asset('tiny.svg', package: 'icons');
Object networkPicture() => SvgPicture.network(
  'http://localhost/tiny.svg',
  headers: {'X-Svg': 'fixture'},
);
Object loaderPicture() =>
    SvgPicture(const SvgStringLoader('<svg/>', theme: SvgTheme(fontSize: 18)));
Object loaderBytesPicture() =>
    SvgPicture(SvgBytesLoader(Uint8List.fromList([60, 115, 118, 103, 47, 62])));
Object loaderAssetPicture() =>
    SvgPicture(const SvgAssetLoader('tiny.svg', packageName: 'icons'));
Object loaderNetworkPicture() => SvgPicture(
  const SvgNetworkLoader(
    'http://localhost/tiny.svg',
    headers: {'X-Svg': 'fixture'},
  ),
);
Object placeholderPicture() => SvgPicture.asset(
  'tiny.svg',
  width: 24,
  placeholderBuilder: (context) => const SizedBox(width: 7, height: 9),
);
Object gammaPicture() => SvgPicture.string(
  '<svg/>',
  colorFilter: const ColorFilter.linearToSrgbGamma(),
);
Object badBytes() => SvgPicture.memory(Uint8List.fromList([256]));
Object badLoader() => SvgPicture(const CustomLoader());
Object badCallback() => SvgPicture.string(
  '<svg/>',
  errorBuilder: (context, error, stack) => const SizedBox(),
);

class CustomLoader extends BytesLoader {
  const CustomLoader();
  @override
  Future<ByteData> loadBytes(BuildContext? context) =>
      throw UnimplementedError();
}

Object badLookalike() => lookalike.SvgPicture.string('<svg/>');
Object badBundle() => SvgPicture.asset('tiny.svg', bundle: rootBundle);
Object badMapper() => SvgPicture.string('<svg/>', colorMapper: const Mapper());

class Mapper extends ColorMapper {
  const Mapper();
  @override
  Color substitute(
    String? id,
    String elementName,
    String attributeName,
    Color color,
  ) => color;
}

Object nullPlaceholderPicture() =>
    SvgPicture.string('<svg/>', placeholderBuilder: null);

const aliasTheme = SvgTheme(fontSize: 20);
const aliasFilter = ColorFilter.mode(Color(0xffaa0000), BlendMode.srcIn);
const aliasHeaders = <String, String>{'X-Test': 'yes'};
const aliasLoader = SvgStringLoader('<svg/>', theme: aliasTheme);
const aliasCustomLoader = CustomLoader();

Object directThemePicture() =>
    SvgPicture.string('<svg/>', theme: const SvgTheme(fontSize: 20));
Object aliasThemePicture() => SvgPicture.string('<svg/>', theme: aliasTheme);
Object crossThemePicture() => SvgPicture.string('<svg/>', theme: native.theme);
Object directFilterPicture() => SvgPicture.string(
  '<svg/>',
  colorFilter: const ColorFilter.mode(Color(0xffaa0000), BlendMode.srcIn),
);
Object aliasFilterPicture() =>
    SvgPicture.string('<svg/>', colorFilter: aliasFilter);
Object crossFilterPicture() =>
    SvgPicture.string('<svg/>', colorFilter: native.filter);
Object directHeadersPicture() => SvgPicture.network(
  'http://localhost/tiny.svg',
  headers: const <String, String>{'X-Test': 'yes'},
);
Object aliasHeadersPicture() =>
    SvgPicture.network('http://localhost/tiny.svg', headers: aliasHeaders);
Object crossHeadersPicture() =>
    SvgPicture.network('http://localhost/tiny.svg', headers: native.headers);
Object directStringLoaderPicture() =>
    SvgPicture(const SvgStringLoader('<svg/>', theme: SvgTheme(fontSize: 20)));
Object aliasStringLoaderPicture() => SvgPicture(aliasLoader);
Object crossStringLoaderPicture() => SvgPicture(native.stringLoader);
Object directAssetLoaderPicture() => SvgPicture(
  const SvgAssetLoader(
    'tiny.svg',
    packageName: 'icons',
    theme: SvgTheme(fontSize: 20),
  ),
);
Object crossAssetLoaderPicture() => SvgPicture(native.assetLoader);
Object directNetworkLoaderPicture() => SvgPicture(
  const SvgNetworkLoader(
    'http://localhost/tiny.svg',
    headers: {'X-Test': 'yes'},
    theme: SvgTheme(fontSize: 20),
  ),
);
Object crossNetworkLoaderPicture() => SvgPicture(native.networkLoader);
Object directBytesAliasPicture() =>
    SvgPicture.memory(Uint8List.fromList([60, 115, 118, 103, 47, 62]));
Object crossBytesAliasPicture() =>
    SvgPicture.memory(Uint8List.fromList(native.bytes));
Object directMatrixPicture() => SvgPicture.string(
  '<svg/>',
  colorFilter: const ColorFilter.matrix([
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ]),
);
Object crossMatrixPicture() =>
    SvgPicture.string('<svg/>', colorFilter: native.matrixFilter);
Object directLinearPicture() => SvgPicture.string(
  '<svg/>',
  colorFilter: const ColorFilter.linearToSrgbGamma(),
);
Object crossLinearPicture() =>
    SvgPicture.string('<svg/>', colorFilter: native.linearFilter);
Object directSrgbPicture() => SvgPicture.string(
  '<svg/>',
  colorFilter: const ColorFilter.srgbToLinearGamma(),
);
Object crossSrgbPicture() =>
    SvgPicture.string('<svg/>', colorFilter: native.srgbFilter);
Object badConstLoaderPicture() => SvgPicture(aliasCustomLoader);
int headerReads = 0;
Map<String, String> readHeaders() {
  headerReads++;
  return {'X-Test': 'yes'};
}

final runtimeHeaders = readHeaders();
Object badRuntimeHeadersPicture() =>
    SvgPicture.network('http://localhost/tiny.svg', headers: runtimeHeaders);

Object aliasedStringPicture() => SvgPicture.string(
  '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10" viewBox="0 0 10 10"><path fill="currentColor" d="M0 0h4v10H0z"/></svg>',
  width: 24,
  height: 20,
  semanticsLabel: 'Mark',
  matchTextDirection: true,
  theme: native.theme,
  colorFilter: native.filter,
);

Object combinedPicture() => LayoutBuilder(
  builder: (outer, constraints) {
    final dynamic base = const Color.from(
      alpha: .75,
      red: .2,
      green: .4,
      blue: .8,
      colorSpace: ColorSpace.displayP3,
    );
    final Null clear = null;
    return DefaultTextStyle(
      style: const TextStyle(fontSize: 27, fontWeight: FontWeight(550)),
      child: ClipPath.shape(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadiusDirectional.only(
            topStart: Radius.circular(8),
          ),
        ),
        child: SvgPicture.asset(
          'tiny.svg',
          package: 'fixture_icons',
          width: 24,
          height: 24,
          color: clear,
          theme: SvgTheme(
            currentColor: base,
            fontSize: constraints.maxWidth / 10,
          ),
          colorFilter: ColorFilter.mode(base, BlendMode.srcIn),
          placeholderBuilder: (localBuildContext) => SizedBox(
            width: DefaultTextStyle.of(localBuildContext).style.fontSize,
            height: DefaultTextStyle.of(outer).style.fontSize,
          ),
        ),
      ),
    );
  },
);

Object subtypeThemePicture() => LayoutBuilder(
  builder: (context, constraints) {
    final dynamic base = Colors.red;
    return SvgPicture.string('<svg/>', theme: SvgTheme(currentColor: base));
  },
);
Object subtypeFilterPicture() => LayoutBuilder(
  builder: (context, constraints) {
    final dynamic base = Colors.red;
    return SvgPicture.string(
      '<svg/>',
      colorFilter: ColorFilter.mode(base, BlendMode.srcIn),
    );
  },
);
Object nullThemePicture() => LayoutBuilder(
  builder: (context, constraints) {
    final dynamic clear = null;
    return SvgPicture.string('<svg/>', theme: SvgTheme(currentColor: clear));
  },
);
Object nullFilterPicture() => LayoutBuilder(
  builder: (context, constraints) {
    final dynamic clear = null;
    return SvgPicture.string(
      '<svg/>',
      colorFilter: ColorFilter.mode(clear, BlendMode.srcIn),
    );
  },
);

Object directSubtypeThemePicture() => SvgPicture.string(
  '<svg/>',
  theme: const SvgTheme(currentColor: Colors.red),
);
Object directSubtypeFilterPicture() => SvgPicture.string(
  '<svg/>',
  colorFilter: const ColorFilter.mode(Colors.red, BlendMode.srcIn),
);

Object crossSubtypeThemePicture() =>
    SvgPicture.string('<svg/>', theme: native.subtypeTheme);
Object crossExactColorPicture() => SvgPicture.string(
  '<svg/>',
  theme: native.exactTheme,
  colorFilter: native.exactFilter,
);

Object ordinarySubtypePaint() =>
    const ColoredBox(color: native.ordinaryMaterialColor, child: SizedBox());

Object crossExactSrgbPicture() =>
    SvgPicture.string('<svg/>', theme: native.exactSrgbTheme);
Object dynamicCrossExactPicture() => LayoutBuilder(
  builder: (context, constraints) {
    final dynamic base = native.exactColor;
    return SvgPicture.string(
      '<svg/>',
      theme: SvgTheme(currentColor: base),
      colorFilter: ColorFilter.mode(base, BlendMode.srcIn),
    );
  },
);

Object dynamicCrossSubtypePicture() => LayoutBuilder(
  builder: (context, constraints) {
    final dynamic base = native.ordinaryMaterialColor;
    return SvgPicture.string('<svg/>', theme: SvgTheme(currentColor: base));
  },
);
