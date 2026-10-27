import 'dart:ui' show ColorSpace;
import 'package:flutter/material.dart' show Colors;
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

const theme = SvgTheme(fontSize: 20);
const filter = ColorFilter.mode(Color(0xffaa0000), BlendMode.srcIn);
const matrix = <double>[
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
];
const matrixFilter = ColorFilter.matrix(matrix);
const linearFilter = ColorFilter.linearToSrgbGamma();
const srgbFilter = ColorFilter.srgbToLinearGamma();
const headers = <String, String>{'X-Test': 'yes'};
const stringLoader = SvgStringLoader('<svg/>', theme: theme);
const assetLoader = SvgAssetLoader(
  'tiny.svg',
  packageName: 'icons',
  theme: theme,
);
const networkLoader = SvgNetworkLoader(
  'http://localhost/tiny.svg',
  headers: headers,
  theme: theme,
);
const bytes = <int>[60, 115, 118, 103, 47, 62];

const exactColor = Color.from(
  alpha: .75,
  red: .2,
  green: .4,
  blue: .8,
  colorSpace: ColorSpace.displayP3,
);
const exactTheme = SvgTheme(currentColor: exactColor);
const exactFilter = ColorFilter.mode(exactColor, BlendMode.srcIn);
const subtypeTheme = SvgTheme(currentColor: Colors.red);

const ordinaryMaterialColor = Colors.red;

const exactSrgbColor = Color.from(alpha: .75, red: .2, green: .4, blue: .8);
const exactSrgbTheme = SvgTheme(currentColor: exactSrgbColor);
