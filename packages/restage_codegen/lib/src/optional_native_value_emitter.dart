import 'package:analyzer/dart/ast/ast.dart';
import 'package:restage_codegen/src/const_value_literal.dart';
import 'package:restage_codegen/src/optional_native_values.dart';

/// Emits inert data for the installed SVG native constructor vocabulary.
String? emitOptionalNativeValue(
  Expression expression, {
  required String Function(Expression) translate,
  required String Function(Expression) translateColor,
  required Expression Function(Expression) resolve,
  required String? Function(Expression, String Function(Expression))
  translateConstant,
  String? Function(Expression, String)? translateBinding,
  String? expected,
}) {
  final expr = resolve(expression);
  final bindingType = optionalNativeBindingTypes[expected];
  if (bindingType != null) {
    if (expr is NullLiteral) return 'null';
    final bound = translateBinding?.call(expression, bindingType);
    if (bound != null) return bound;
    if (!const {
      'package:vector_graphics/src/loader.dart#BytesLoader',
      'dart:ui#ColorFilter',
      'dart:typed_data#Uint8List',
      'package:flutter_svg/src/loaders.dart#SvgTheme',
      'dart:core#Map',
    }.contains(expected)) {
      throw const FormatException('An installed native binding is required.');
    }
  }
  if (expected == null) {
    final type = expr.staticType;
    final source = type == null ? null : optionalNativeSourceType(type);
    final owner = expr is InstanceCreationExpression
        ? constructionConstructor(expr)?.enclosingElement
        : null;
    final loader =
        owner?.library.identifier == 'package:flutter_svg/src/loaders.dart' &&
        const {
          'SvgStringLoader',
          'SvgBytesLoader',
          'SvgAssetLoader',
          'SvgNetworkLoader',
          'SvgFileLoader',
        }.contains(owner?.name);
    if (!loader && (source == null || source == 'dart:core#Map')) return null;
  }
  final constant = translateConstant(
    expr,
    (initializer) =>
        emitOptionalNativeValue(
          initializer,
          translate: translate,
          translateColor: translateColor,
          resolve: resolve,
          translateConstant: translateConstant,
          translateBinding: translateBinding,
          expected: expected,
        ) ??
        translate(initializer),
  );
  if (constant != null) return constant;
  String resolvedValue(Expression value, String Function(Expression) lower) {
    final resolved = resolve(value);
    return translateConstant(
          resolved,
          (initializer) => resolvedValue(initializer, lower),
        ) ??
        lower(resolved);
  }

  if (expr is NullLiteral) return 'null';
  if (expected == 'dart:core#Map') {
    if (expr is! SetOrMapLiteral ||
        (!expr.isMap &&
            (constValueAnchor(expr) == null ||
                expr.elements.any((element) => element is! MapLiteralEntry)))) {
      throw const FormatException('SVG headers require a string map literal.');
    }
    final entries = <String>[];
    for (final element in expr.elements) {
      if (element is! MapLiteralEntry ||
          (element.key is! StringLiteral &&
              element.key.staticType?.isDartCoreString != true) ||
          (element.value is! StringLiteral &&
              element.value.staticType?.isDartCoreString != true)) {
        throw const FormatException(
          'SVG headers require string keys and values.',
        );
      }
      entries.add(
        '{key: ${translate(element.key)}, value: ${translate(element.value)}}',
      );
    }
    return '[${entries.join(', ')}]';
  }
  if (expr is! InstanceCreationExpression) {
    if (expected != null) {
      throw const FormatException('A closed native constructor is required.');
    }
    return null;
  }
  final constructor = constructionConstructor(expr);
  if (constructor == null) return null;
  final cls = constructor.enclosingElement;
  final identity = '${cls.library.identifier}#${cls.name}';
  final variant = constructor.name == 'new' ? '' : (constructor.name ?? '');
  final positional = <Expression>[];
  final named = <String, Expression>{};
  for (final argument in expr.argumentList.arguments) {
    if (argument is NamedArgument) {
      named[argument.name.lexeme] = argument.argumentExpression;
    } else {
      positional.add(argument.argumentExpression);
    }
  }
  String data(Expression value, [String? type]) =>
      emitOptionalNativeValue(
        value,
        translate: translate,
        translateColor: translateColor,
        resolve: resolve,
        translateConstant: translateConstant,
        translateBinding: translateBinding,
        expected: type,
      ) ??
      translate(value);
  String object(Map<String, String> fields) {
    final entries = fields.entries.map(
      (field) => '${field.key}: ${field.value}',
    );
    return '{${entries.join(', ')}}';
  }

  void admitted(Set<String> names, int count) {
    if (positional.length != count ||
        named.keys.any((name) => !names.contains(name))) {
      throw FormatException(
        'Unsupported $identity constructor argument; installed objects and '
        'callbacks require application code.',
      );
    }
  }

  if (identity == 'dart:typed_data#Uint8List') {
    admitted({}, 1);
    if (variant != 'fromList') {
      throw const FormatException('Use Uint8List.fromList with byte data.');
    }
    return resolvedValue(positional.single, (list) {
      if (list is! ListLiteral ||
          list.elements.length > 1048576 ||
          list.elements.any(
            (element) =>
                element is! IntegerLiteral ||
                element.value == null ||
                element.value! < 0 ||
                element.value! > 255,
          )) {
        throw const FormatException(
          'Byte data requires integers from 0 through 255.',
        );
      }
      return translate(list);
    });
  }
  if (identity == 'dart:ui#ColorFilter') {
    if (variant == 'mode') {
      admitted({}, 2);
      return object({
        'kind': '"mode"',
        'color': translateColor(positional[0]),
        'blendMode': translate(positional[1]),
      });
    }
    if (variant == 'matrix') {
      admitted({}, 1);
      return resolvedValue(positional.single, (matrix) {
        if (matrix is! ListLiteral || matrix.elements.length != 20) {
          throw const FormatException(
            'ColorFilter.matrix requires exactly 20 numeric values.',
          );
        }
        return object({'kind': '"matrix"', 'matrix': translate(matrix)});
      });
    }
    if (variant == 'linearToSrgbGamma' || variant == 'srgbToLinearGamma') {
      admitted({}, 0);
      return object({'kind': '"$variant"'});
    }
    throw const FormatException('Unsupported ColorFilter constructor.');
  }
  if (identity == 'package:flutter_svg/src/loaders.dart#SvgTheme') {
    admitted({'currentColor', 'fontSize', 'xHeight'}, 0);
    return object(
      {
        for (final field in named.entries)
          field.key: field.key == 'currentColor'
              ? translateColor(field.value)
              : data(field.value),
      },
    );
  }
  const loaders = {
    'SvgStringLoader',
    'SvgBytesLoader',
    'SvgAssetLoader',
    'SvgNetworkLoader',
    'SvgFileLoader',
  };
  if (cls.library.identifier == 'package:flutter_svg/src/loaders.dart' &&
      loaders.contains(cls.name)) {
    final allowed = {
      'theme',
      'colorMapper',
      if (cls.name == 'SvgAssetLoader') 'packageName',
      if (cls.name == 'SvgAssetLoader') 'assetBundle',
      if (cls.name == 'SvgNetworkLoader') 'headers',
      if (cls.name == 'SvgNetworkLoader') 'httpClient',
    };
    admitted(allowed, 1);
    if (variant.isNotEmpty) {
      throw const FormatException('Unsupported SVG loader constructor.');
    }
    return object({
      'kind': '"${cls.name}"',
      'value': data(
        positional.single,
        cls.name == 'SvgBytesLoader'
            ? 'dart:typed_data#Uint8List'
            : cls.name == 'SvgFileLoader'
            ? 'dart:io#File'
            : null,
      ),
      for (final field in named.entries)
        field.key: data(
          field.value,
          field.key == 'colorMapper'
              ? 'package:flutter_svg/src/loaders.dart#ColorMapper'
              : field.key == 'assetBundle'
              ? 'package:flutter/src/services/asset_bundle.dart#AssetBundle'
              : field.key == 'httpClient'
              ? 'package:http/src/client.dart#Client'
              : field.key == 'headers'
              ? 'dart:core#Map'
              : field.key == 'theme'
              ? 'package:flutter_svg/src/loaders.dart#SvgTheme'
              : null,
        ),
    });
  }
  if (expected != null) {
    throw FormatException('Unsupported native value $identity for $expected.');
  }
  return null;
}
