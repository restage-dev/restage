import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:rfw_catalog_schema/rfw_catalog_schema.dart'
    show kSvgNativeBindingTypes;

/// Installed decoders for closed native structured values.
const optionalNativeDecoders = <String, String>{
  'dart:ui#ColorFilter': 'colorFilter',
  'dart:typed_data#Uint8List': 'bytes',
  'package:flutter_svg/src/loaders.dart#SvgTheme': 'theme',
  'package:vector_graphics/src/loader.dart#BytesLoader': 'loader',
  'dart:core#Map': 'headers',
  'package:flutter/src/services/asset_bundle.dart#AssetBundle': 'assetBundle',
  'package:http/src/client.dart#Client': 'httpClient',
  'package:flutter_svg/src/loaders.dart#ColorMapper': 'colorMapper',
  'dart:io#File': 'file',
  'package:flutter_svg/src/utilities/_file_none.dart#File': 'file',
  'package:flutter_svg/svg.dart#SvgErrorWidgetBuilder': 'errorBuilder',
  'package:flutter_svg/svg.dart#SvgImageWidgetBuilder': 'imageBuilder',
};

/// Borrowed values consumed by the optional SVG library.
const Map<String, String> optionalNativeBindingTypes = kSvgNativeBindingTypes;

/// Decoder methods that require the actual descendant context.
const optionalContextualNativeDecoders = {
  'loader',
  'assetBundle',
  'httpClient',
  'colorMapper',
  'file',
  'errorBuilder',
  'imageBuilder',
};

/// Returns the decoder owned by the optional catalog, never by an unrelated
/// custom catalog that happens to expose the same Dart source type.
String? optionalNativeDecoder(String sourceType, {required String namespace}) =>
    namespace == 'restage.svg' ? optionalNativeDecoders[sourceType] : null;

/// Identifies a staged initializer by its resolved native SVG consumer.
String? optionalNativeInitializerType(Expression expression) {
  final declaration = expression.parent;
  if (declaration is! VariableDeclaration ||
      !identical(declaration.initializer, expression))
    return null;
  final variable = declaration.declaredFragment?.element;
  final body = declaration.thisOrAncestorOfType<FunctionBody>();
  if (variable == null || body == null) return null;
  final seen = <Element>{};
  String? consumer(Element element) {
    if (!seen.add(element)) return null;
    final uses = _NativeSvgUses(element);
    body.accept(uses);
    for (final parameter in uses.parameters) {
      final origin = parameter.library?.identifier;
      if (origin != 'package:flutter_svg/svg.dart' &&
          origin != 'package:flutter_svg/src/loaders.dart')
        continue;
      final source = optionalNativeSourceType(parameter.type);
      if ((source == 'dart:io#File' ||
              source ==
                  'package:flutter_svg/src/utilities/_file_none.dart#File') &&
          expression is! SimpleIdentifier) {
        continue;
      }
      final type = optionalNativeBindingTypes[source];
      if (type != null) return type;
    }
    for (final alias in uses.aliases) {
      final type = consumer(alias);
      if (type != null) return type;
    }
    return null;
  }

  return consumer(variable);
}

final class _NativeSvgUses extends RecursiveAstVisitor<void> {
  _NativeSvgUses(this.element);
  final Element element;
  final parameters = <FormalParameterElement>[];
  final aliases = <Element>[];
  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.element?.baseElement != element.baseElement) return;
    AstNode current = node;
    while (current.parent is ParenthesizedExpression) {
      current = current.parent!;
    }
    final parent = current.parent;
    if (parent is VariableDeclaration &&
        identical(parent.initializer, current)) {
      if (parent.declaredFragment?.element case final alias?)
        aliases.add(alias);
    }
    if (parent is NamedArgument) current = parent;
    if (current is Argument) {
      final parameter = current.correspondingParameter;
      if (parameter != null) parameters.add(parameter);
    }
  }
}

/// Recognizes a native value whose complete data contract is installed.
String? optionalNativeSourceType(DartType type) {
  if (type is FunctionType) {
    bool exact(DartType value, String identity) =>
        value is InterfaceType &&
        value.nullabilitySuffix == NullabilitySuffix.none &&
        '${value.element.library.identifier}#${value.element.name}' == identity;
    if (type.typeParameters.isNotEmpty ||
        !exact(
          type.returnType,
          'package:flutter/src/widgets/framework.dart#Widget',
        ) ||
        type.formalParameters.any((p) => !p.isRequiredPositional))
      return null;
    final parameters = type.formalParameters;
    if (parameters.isEmpty ||
        !exact(
          parameters.first.type,
          'package:flutter/src/widgets/framework.dart#BuildContext',
        ))
      return null;
    if (parameters.length == 2 &&
        exact(
          parameters[1].type,
          'package:flutter/src/widgets/framework.dart#Widget',
        )) {
      return 'package:flutter_svg/svg.dart#SvgImageWidgetBuilder';
    }
    if (parameters.length == 3 &&
        exact(parameters[1].type, 'dart:core#Object') &&
        exact(parameters[2].type, 'dart:core#StackTrace')) {
      return 'package:flutter_svg/svg.dart#SvgErrorWidgetBuilder';
    }
    return null;
  }
  if (type is! InterfaceType) return null;
  final identity = '${type.element.library.identifier}#${type.element.name}';
  if (!optionalNativeDecoders.containsKey(identity)) return null;
  if (identity == 'dart:core#Map' &&
      (type.typeArguments.length != 2 ||
          !type.typeArguments.every((argument) => argument.isDartCoreString))) {
    return null;
  }
  return identity;
}
