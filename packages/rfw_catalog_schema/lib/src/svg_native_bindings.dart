/// Borrowed values consumed by the optional SVG library.
const kSvgNativeBindingTypes = <String, String>{
  'dart:ui#ColorFilter': 'dart:ui#ColorFilter',
  'dart:typed_data#Uint8List': 'dart:typed_data#Uint8List',
  'package:flutter_svg/src/loaders.dart#SvgTheme':
      'package:flutter_svg/src/loaders.dart#SvgTheme',
  'dart:core#Map': 'dart:core#Map<dart:core#String,dart:core#String>',
  'package:flutter/src/services/asset_bundle.dart#AssetBundle':
      'flutter.AssetBundle',
  'package:http/src/client.dart#Client': 'http.Client',
  'package:flutter_svg/src/loaders.dart#ColorMapper': 'flutter_svg.ColorMapper',
  'package:vector_graphics/src/loader.dart#BytesLoader':
      'vector_graphics.BytesLoader',
  'dart:io#File': 'dart.io.File',
  'package:flutter_svg/src/utilities/_file_none.dart#File': 'dart.io.File',
  'package:flutter_svg/svg.dart#SvgErrorWidgetBuilder':
      'flutter_svg.SvgErrorWidgetBuilder(package:flutter/src/widgets/framework.dart#BuildContext,dart:core#Object,dart:core#StackTrace)->package:flutter/src/widgets/framework.dart#Widget',
  'package:flutter_svg/svg.dart#SvgImageWidgetBuilder':
      'flutter_svg.SvgImageWidgetBuilder(package:flutter/src/widgets/framework.dart#BuildContext,package:flutter/src/widgets/framework.dart#Widget)->package:flutter/src/widgets/framework.dart#Widget',
};

/// Resolves a fixed native SVG type only in its owning catalog namespace.
String? svgNativeBindingType(String sourceType, {required String namespace}) =>
    namespace == 'restage.svg' ? kSvgNativeBindingTypes[sourceType] : null;
