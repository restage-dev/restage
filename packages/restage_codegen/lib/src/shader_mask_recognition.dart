import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:restage_codegen/src/const_folding.dart';
import 'package:restage_codegen/src/theme_recognition.dart';

/// A supported mask, or a reason to use a custom widget.
({Map<String, Expression>? arguments, String? reason}) recogniseShaderMask(
  InstanceCreationExpression creation, {
  required Expression Function(Expression) resolve,
}) {
  final args = <String, Expression>{};
  for (final arg in creation.argumentList.arguments) {
    if (arg is! NamedArgument ||
        !{'key', 'child', 'shaderCallback', 'blendMode', 'colorFilter'}
            .contains(arg.name.lexeme)) {
      return (
        arguments: null,
        reason: 'the widget has an unsupported argument'
      );
    }
    args[arg.name.lexeme] = arg.argumentExpression;
  }
  final arguments = <String, Expression>{
    if (args['blendMode'] case final mode?) 'blendMode': mode,
    if (args['child'] case final child?) 'child': child,
  };
  if (creation.constructorName.element?.enclosingElement.name ==
      'ColorFiltered') {
    final filter = _expand(args['colorFilter'], resolve);
    if (filter is! InstanceCreationExpression ||
        filter.constructorName.element?.enclosingElement.name !=
            'ColorFilter' ||
        filter.constructorName.element?.library.identifier != 'dart:ui' ||
        filter.constructorName.element?.name != 'mode' ||
        filter.argumentList.arguments.length != 2 ||
        filter.argumentList.arguments.any((arg) => arg is NamedArgument)) {
      return (arguments: null, reason: 'only ColorFilter.mode is supported');
    }
    return (
      arguments: {
        ...arguments,
        'color': filter.argumentList.arguments[0] as Expression,
        'blendMode': filter.argumentList.arguments[1] as Expression,
      },
      reason: null,
    );
  }

  final callback = _expand(args['shaderCallback'], resolve);
  Expression? gradientTarget = switch (callback) {
    PropertyAccess(
      :final target?,
      propertyName: SimpleIdentifier(name: 'createShader'),
    ) =>
      target,
    PrefixedIdentifier(
      :final prefix,
      identifier: SimpleIdentifier(name: 'createShader'),
    ) =>
      prefix,
    _ => null,
  };
  if (gradientTarget == null) {
    if (callback is! FunctionExpression ||
        callback.parameters?.parameters.length != 1 ||
        callback.body.isAsynchronous ||
        callback.body.isGenerator) {
      return (
        arguments: null,
        reason: 'shaderCallback must be a one-parameter closure or a '
            'gradient.createShader tear-off',
      );
    }
    final body = callback.body;
    final Expression? result = switch (body) {
      ExpressionFunctionBody() => body.expression,
      BlockFunctionBody() when body.block.statements.length == 1 => switch (
            body.block.statements.single) {
          ReturnStatement(:final expression) => expression,
          _ => null,
        },
      _ => null,
    };
    final call = _expand(result, resolve);
    if (call is! MethodInvocation || call.methodName.name != 'createShader') {
      return (
        arguments: null,
        reason: 'return a gradient.createShader(bounds) expression'
      );
    }
    final bounds = call.argumentList.arguments;
    final parameter =
        callback.parameters!.parameters.single.declaredFragment?.element;
    if (bounds.length != 1 ||
        bounds.single is! SimpleIdentifier ||
        parameter == null ||
        (bounds.single as SimpleIdentifier).element != parameter) {
      return (
        arguments: null,
        reason: 'createShader must receive the unchanged callback bounds'
      );
    }
    gradientTarget = call.target;
  }
  final gradient = _expand(gradientTarget, resolve);
  if (gradient is SimpleIdentifier ||
      gradient is PrefixedIdentifier ||
      gradient is PropertyAccess) {
    final type = gradient?.staticType;
    if (type is InterfaceType &&
        {'Gradient', 'LinearGradient', 'RadialGradient', 'SweepGradient'}
            .contains(type.element.name) &&
        libraryIsFlutter(type.element)) {
      return (
        arguments: {...arguments, 'gradient': gradient!},
        reason: null,
      );
    }
  }
  if (gradient is! InstanceCreationExpression ||
      !{'LinearGradient', 'RadialGradient', 'SweepGradient'}
          .contains(gradient.constructorName.element?.enclosingElement.name) ||
      !libraryIsFlutter(gradient.constructorName.element) ||
      !{null, '', 'new'}.contains(gradient.constructorName.element?.name)) {
    return (
      arguments: null,
      reason:
          'only Flutter LinearGradient, RadialGradient and SweepGradient are supported'
    );
  }
  arguments['gradient'] = gradient;
  for (final arg
      in gradient.argumentList.arguments.whereType<NamedArgument>()) {
    if (arg.name.lexeme != 'transform') continue;
    final transform = _expand(arg.argumentExpression, resolve);
    if (transform is NullLiteral) continue;
    if (transform is! InstanceCreationExpression ||
        transform.constructorName.element?.enclosingElement.name !=
            'GradientRotation' ||
        !libraryIsFlutter(transform.constructorName.element) ||
        transform.argumentList.arguments.length != 1 ||
        transform.argumentList.arguments.single is! Expression) {
      return (
        arguments: null,
        reason: 'only GradientRotation transforms are supported'
      );
    }
    arguments['rotation'] =
        transform.argumentList.arguments.single as Expression;
  }
  return (arguments: arguments, reason: null);
}

Expression? _expand(
  Expression? expression,
  Expression Function(Expression) resolve,
) {
  final seen = <Expression>{};
  while (expression != null && seen.add(expression)) {
    if (expression is ParenthesizedExpression) {
      expression = expression.expression;
      continue;
    }
    final bound = resolve(expression);
    if (!identical(bound, expression)) {
      expression = bound;
      continue;
    }
    final initializer = resolveConstIdentifierInitializer(expression);
    if (initializer == null) return expression;
    expression = initializer;
  }
  return null;
}
