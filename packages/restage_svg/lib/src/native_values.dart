import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
// ignore: implementation_imports
import 'package:flutter_svg/src/utilities/file.dart' show File;
import 'package:http/http.dart' as http;
import 'package:rfw/rfw.dart';
import 'package:restage_core/restage_core.dart'
    show RestageDecoders, RestageValueBinding;

/// Reconstructs the catalog's closed native SVG values.
abstract final class SvgNativeValues {
  static T? _binding<T extends Object>(
    BuildContext context,
    DataSource source,
    List<Object> path,
    String type,
  ) {
    if (RestageValueBinding.isNativeValue(source, path)) {
      return RestageValueBinding.readNativeFromSource<T>(
        source,
        path,
        type: type,
      );
    }
    if (!source.isMap(path) &&
        !source.isList(path) &&
        source.v<String>(path) == null &&
        source.v<int>(path) == null &&
        source.v<double>(path) == null &&
        source.v<bool>(path) == null) {
      return null;
    }
    return RestageValueBinding.readNativeFromSource<T>(
      source,
      path,
      type: type,
    );
  }

  /// Resolves a borrowed asset bundle without replacing its native defaults.
  static AssetBundle? assetBundle(
    BuildContext context,
    DataSource source,
    List<Object> path,
  ) => _binding<AssetBundle>(context, source, path, 'flutter.AssetBundle');

  /// Resolves a borrowed client without acquiring ownership.
  static http.Client? httpClient(
    BuildContext context,
    DataSource source,
    List<Object> path,
  ) => _binding<http.Client>(context, source, path, 'http.Client');

  /// Resolves the actual mapper used by native decoding and cache keys.
  static ColorMapper? colorMapper(
    BuildContext context,
    DataSource source,
    List<Object> path,
  ) => _binding<ColorMapper>(context, source, path, 'flutter_svg.ColorMapper');

  /// Resolves an installed platform File; paths never construct files.
  static File? file(
    BuildContext context,
    DataSource source,
    List<Object> path,
  ) => _binding<File>(context, source, path, 'dart.io.File');

  /// Resolves the native error callback with its exact argument identities.
  static SvgErrorWidgetBuilder? errorBuilder(
    BuildContext context,
    DataSource source,
    List<Object> path,
  ) => _binding<SvgErrorWidgetBuilder>(
    context,
    source,
    path,
    'flutter_svg.SvgErrorWidgetBuilder(package:flutter/src/widgets/framework.dart#BuildContext,dart:core#Object,dart:core#StackTrace)->package:flutter/src/widgets/framework.dart#Widget',
  );

  /// Resolves the native image callback with its original native child.
  static SvgImageWidgetBuilder? imageBuilder(
    BuildContext context,
    DataSource source,
    List<Object> path,
  ) => _binding<SvgImageWidgetBuilder>(
    context,
    source,
    path,
    'flutter_svg.SvgImageWidgetBuilder(package:flutter/src/widgets/framework.dart#BuildContext,package:flutter/src/widgets/framework.dart#Widget)->package:flutter/src/widgets/framework.dart#Widget',
  );

  /// Reads a byte list without truncation or numeric coercion.
  static Uint8List? bytes(DataSource source, List<Object> path) {
    if (RestageValueBinding.isNativeValue(source, path)) {
      return RestageValueBinding.readNativeFromSource<Uint8List>(
        source,
        path,
        type: 'dart:typed_data#Uint8List',
      );
    }
    if (!source.isList(path)) {
      return null;
    }
    final length = source.length(path);
    if (length > 1048576) throw ArgumentError('SVG byte list is too large.');
    return Uint8List.fromList([
      for (var i = 0; i < length; i++) _byte(source, [...path, i]),
    ]);
  }

  static int _byte(DataSource source, List<Object> path) {
    final value = source.v<int>(path);
    if (value == null || value < 0 || value > 255) {
      throw ArgumentError('SVG bytes must be integers from 0 through 255.');
    }
    return value;
  }

  /// Preserves the native x-height default computed from font size.
  static SvgTheme? theme(DataSource source, List<Object> path) {
    if (RestageValueBinding.isNativeValue(source, path)) {
      return RestageValueBinding.readNativeFromSource<SvgTheme>(
        source,
        path,
        type: 'package:flutter_svg/src/loaders.dart#SvgTheme',
      );
    }
    if (!source.isMap(path)) return null;
    return SvgTheme(
      currentColor:
          RestageDecoders.color(source, [...path, 'currentColor']) ??
          const Color(0xff000000),
      fontSize: _number(source, [...path, 'fontSize']) ?? 14,
      xHeight: _number(source, [...path, 'xHeight']),
    );
  }

  /// Reads the four native color filter constructors.
  static ColorFilter? colorFilter(DataSource source, List<Object> path) {
    if (RestageValueBinding.isNativeValue(source, path)) {
      return RestageValueBinding.readNativeFromSource<ColorFilter>(
        source,
        path,
        type: 'dart:ui#ColorFilter',
      );
    }
    if (!source.isMap(path)) return null;
    switch (source.v<String>([...path, 'kind'])) {
      case 'mode':
        final color = RestageDecoders.color(source, [...path, 'color']);
        final mode = source.v<String>([...path, 'blendMode']);
        if (color == null ||
            !BlendMode.values.any((value) => value.name == mode)) {
          throw ArgumentError('Invalid SVG color filter mode.');
        }
        return ColorFilter.mode(color, BlendMode.values.byName(mode!));
      case 'matrix':
        final matrixPath = [...path, 'matrix'];
        if (!source.isList(matrixPath) || source.length(matrixPath) != 20) {
          throw ArgumentError('Color filter matrix requires 20 numbers.');
        }
        return ColorFilter.matrix([
          for (var i = 0; i < 20; i++)
            _number(source, [...matrixPath, i]) ??
                (throw ArgumentError('Invalid color filter matrix entry.')),
        ]);
      case 'linearToSrgbGamma':
        return const ColorFilter.linearToSrgbGamma();
      case 'srgbToLinearGamma':
        return const ColorFilter.srgbToLinearGamma();
      default:
        throw ArgumentError('Unsupported SVG color filter constructor.');
    }
  }

  /// Reads headers as ordered key/value data without inspecting host objects.
  static Map<String, String>? headers(DataSource source, List<Object> path) {
    if (RestageValueBinding.isNativeValue(source, path)) {
      return RestageValueBinding.readNativeFromSource<Map<String, String>>(
        source,
        path,
        type: 'dart:core#Map<dart:core#String,dart:core#String>',
      );
    }
    if (!source.isList(path)) return null;
    if (source.length(path) > 1024) {
      throw ArgumentError('Too many SVG headers.');
    }
    final result = <String, String>{};
    for (var i = 0; i < source.length(path); i++) {
      final key = source.v<String>([...path, i, 'key']);
      final value = source.v<String>([...path, i, 'value']);
      if (key == null || value == null) {
        throw ArgumentError('Invalid SVG header.');
      }
      result[key] = value;
    }
    return result;
  }

  /// Resolves a borrowed loader or constructs a standard native SVG loader.
  static BytesLoader? loader(
    BuildContext context,
    DataSource source,
    List<Object> path,
  ) {
    if (RestageValueBinding.isNativeValue(source, path) ||
        !source.isMap(path)) {
      return _binding<BytesLoader>(
        context,
        source,
        path,
        'vector_graphics.BytesLoader',
      );
    }
    final themeValue = theme(source, [...path, 'theme']);
    final mapper = colorMapper(context, source, [...path, 'colorMapper']);
    String text(String field) =>
        source.v<String>([...path, field]) ??
        (throw ArgumentError('SVG loader $field is required.'));
    return switch (source.v<String>([...path, 'kind'])) {
      'SvgStringLoader' => SvgStringLoader(
        text('value'),
        theme: themeValue,
        colorMapper: mapper,
      ),
      'SvgBytesLoader' => SvgBytesLoader(
        bytes(source, [...path, 'value']) ??
            (throw ArgumentError('SVG loader bytes are required.')),
        theme: themeValue,
        colorMapper: mapper,
      ),
      'SvgAssetLoader' => SvgAssetLoader(
        text('value'),
        packageName: source.v<String>([...path, 'packageName']),
        assetBundle: assetBundle(context, source, [...path, 'assetBundle']),
        theme: themeValue,
        colorMapper: mapper,
      ),
      'SvgNetworkLoader' => SvgNetworkLoader(
        text('value'),
        headers: headers(source, [...path, 'headers']),
        httpClient: httpClient(context, source, [...path, 'httpClient']),
        theme: themeValue,
        colorMapper: mapper,
      ),
      'SvgFileLoader' => SvgFileLoader(
        file(context, source, [...path, 'value']) ??
            (throw ArgumentError('SVG loader file is required.')),
        theme: themeValue,
        colorMapper: mapper,
      ),
      _ => throw ArgumentError('Unsupported SVG loader.'),
    };
  }

  static double? _number(DataSource source, List<Object> path) {
    final value = source.v<double>(path) ?? source.v<int>(path)?.toDouble();
    if (value != null && !value.isFinite) {
      throw ArgumentError('Expected a finite number.');
    }
    return value;
  }
}
